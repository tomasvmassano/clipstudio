-- W5-09 · pacote de edição automático (EDL-01, ING-03; ADR-0048). Expand (aditivo): job de media "package" (alarga o
-- check de kind), tabela de saídas por job (idempotência por guião e hook), pedido/lista na app, gravação pelo worker.
-- Da sessão gravada (câmara da frente + câmara do lado com o som, já no R2) saem as versões 1 dos documentos de edição,
-- uma por hook de cada guião, como proposta da IA (source "ai") para um humano rever no editor.

alter table public.media_jobs drop constraint if exists media_jobs_kind_check;
alter table public.media_jobs add constraint media_jobs_kind_check check (kind in ('ingest', 'export', 'package'));

create table if not exists public.media_job_outputs (
  job_id uuid not null references public.media_jobs(id),
  workspace_id text not null references public.clients(id),
  guiao_id text not null,
  hook int not null check (hook between 1 and 9),
  asset_id uuid not null references public.media_assets(id),
  edit_version_id uuid references public.edit_versions(id),
  created_at timestamptz not null default now(),
  primary key (job_id, guiao_id, hook)
);
alter table public.media_job_outputs enable row level security;
revoke all on public.media_job_outputs from anon, authenticated;

-- Pedir: as duas gravações (versões R2 prontas de vídeo deste cliente) e os guiões gravados na sessão.
create or replace function public.edit_package_request(p_ws text, p_front uuid, p_side uuid, p_guioes text[], p_style text default 'S15',
                                                       p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; f media_versions; s media_versions; gs jsonb; n int; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
begin
  uid := public._edit_require(p_ws, p_token, 'edit.package', coalesce(p_front::text, ''), true);
  if not public.ws_can('edit.timeline', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pacote automático precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  if p_front is null or p_side is null or p_front = p_side then
    raise exception 'camaras_invalidas' using errcode = '22023', detail = 'Escolhe duas gravações diferentes: a câmara da frente e a câmara do lado (com o som).'; end if;
  select v.* into f from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_front and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
  select v.* into s from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_side and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
  if f.id is null or s.id is null then
    raise exception 'gravacao_nao_encontrada' using errcode = 'P0002', detail = 'As gravações têm de estar prontas na Biblioteca (no R2) deste cliente.'; end if;
  if coalesce(cardinality(p_guioes), 0) = 0 or cardinality(p_guioes) > 40 then
    raise exception 'guioes_invalidos' using errcode = '22023', detail = 'Escolhe entre 1 e 40 guiões gravados nesta sessão.'; end if;
  select count(*), jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'hooks', g.hooks, 'corpo', g.corpo)
                             order by array_position(p_guioes, g.id))
    into n, gs from guioes g where g.client_id = p_ws and g.id = any (p_guioes);
  if n <> cardinality(p_guioes) then raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'Um dos guiões não é deste cliente.'; end if;
  k := 'package:' || f.id || ':' || s.id || ':' || md5(array_to_string(p_guioes, ',')) || ':' || st;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'package', k, s.id,
            jsonb_build_object('front', jsonb_build_object('version_id', f.id, 'key', f.storage_path, 'name', f.original_name, 'info', f.media_info),
                               'side', jsonb_build_object('version_id', s.id, 'key', s.storage_path, 'name', s.original_name, 'info', s.media_info),
                               'guioes', gs, 'style', st),
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.package_requested', 'media_job', j.id::text, null,
      jsonb_build_object('front', f.id, 'side', s.id, 'guioes', to_jsonb(p_guioes), 'style', st));
  end if;
  return public._media_job_json(j);
end $$;

-- Pacotes recentes do cliente e os documentos que cada um criou.
create or replace function public.edit_package_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  return coalesce((select jsonb_agg(public._media_job_json(j) || jsonb_build_object(
      'front_name', j.input->'front'->>'name', 'side_name', j.input->'side'->>'name',
      'guioes', (select jsonb_agg(jsonb_build_object('id', g->>'id', 'n', (g->>'n')::int, 'tema', g->>'tema')) from jsonb_array_elements(j.input->'guioes') g),
      'outputs', (select coalesce(jsonb_agg(jsonb_build_object('guiao_id', o.guiao_id, 'hook', o.hook, 'asset_id', o.asset_id, 'title', a.title)
                                           order by o.guiao_id, o.hook), '[]')
                    from media_job_outputs o join media_assets a on a.id = o.asset_id where o.job_id = j.id))
      order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'package' order by created_at desc limit 20) j), '[]');
end $$;

-- Documentos de edição do cliente (para a lista: o que há para rever/exportar).
create or replace function public.edit_doc_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  return coalesce((select jsonb_agg(x order by x->>'updated_at' desc) from (
    select jsonb_build_object('asset_id', a.id, 'title', a.title, 'content_id', a.content_id, 'tags', to_jsonb(a.tags),
             'version_no', v.version_no, 'source', v.source, 'updated_at', d.updated_at, 'created_label', v.created_label,
             'has_video', a.current_version_id is not null,
             'confidence', v.doc->'ai'->'confidence', 'flags', v.doc->'ai'->'flags',
             'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema) from guioes g where g.id = a.content_id and g.client_id = p_ws),
             'export', (select jsonb_build_object('status', j.status, 'progress', j.progress) from media_jobs j
                         where j.asset_id = a.id and j.kind = 'export' order by j.created_at desc limit 1)) x
      from edit_documents d join media_assets a on a.id = d.asset_id join edit_versions v on v.id = d.current_version_id
     where d.workspace_id = p_ws and a.lifecycle = 'ativo'
     order by d.updated_at desc limit 300) t), '[]');
end $$;

-- Worker: grava a versão 1 de um documento (idempotente por job, guião e hook). Cria o ativo de vídeo (ainda sem ficheiro).
create or replace function public.media_worker_package_save(p_worker text, p_job uuid, p_guiao text, p_hook int, p_doc jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; o media_job_outputs; g guioes; a media_assets; d edit_documents; v edit_versions; why text; st text; ttl text;
begin
  select * into j from media_jobs where id = p_job;
  if j.id is null or j.kind <> 'package' or j.status <> 'running' or j.locked_by is distinct from p_worker then
    raise exception 'job_perdido' using errcode = 'PT409'; end if;
  select * into o from media_job_outputs where job_id = j.id and guiao_id = p_guiao and hook = p_hook;
  if o.job_id is not null then return jsonb_build_object('asset_id', o.asset_id, 'repeated', true); end if;
  select * into g from guioes where id = p_guiao and client_id = j.workspace_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  why := public._edit_doc_problem(p_doc);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  st := coalesce(nullif(p_doc->>'style', ''), j.input->>'style', 'S15');
  ttl := format('g%s_hook%s_%s', lpad(g.n::text, 2, '0'), p_hook, st) || ' · ' || to_char(g.date, 'DD/MM');
  insert into media_assets (workspace_id, kind, title, tags, status, content_id, notes, created_by, created_label)
  values (j.workspace_id, 'video', left(ttl, 160), array['hook_' || p_hook, lower(st), 'pacote'], 'em_trabalho', g.id,
          'Criado pelo pacote de edição automático da sessão (' || coalesce(j.input->'front'->>'name', '?') || ' + ' || coalesce(j.input->'side'->>'name', '?') || ').',
          j.created_by, 'pacote automático')
  returning * into a;
  insert into edit_documents (workspace_id, asset_id, content_id) values (j.workspace_id, a.id, g.id) returning * into d;
  insert into edit_versions (workspace_id, document_id, version_no, doc, source, note, created_by, created_label)
  values (j.workspace_id, d.id, 1, p_doc, 'ai', 'Versão 1 do pacote automático (proposta da IA)', null, 'pacote automático')
  returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  insert into media_job_outputs (job_id, workspace_id, guiao_id, hook, asset_id, edit_version_id) values (j.id, j.workspace_id, g.id, p_hook, a.id, v.id);
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'edit.package_doc', 'media_asset', a.id::text,
          jsonb_build_object('job_id', j.id, 'guiao_id', g.id, 'hook', p_hook, 'edit_version_id', v.id), 'media:' || a.id);
  return jsonb_build_object('asset_id', a.id, 'edit_version_id', v.id, 'repeated', false);
end $$;

-- Fechar: igual a 20261105175803 mais o ramo do pacote (guarda o resultado; os documentos já foram gravados um a um).
create or replace function public.media_worker_finish(p_worker text, p_job uuid, p_ok boolean, p_result jsonb default null,
                                                      p_error text default null, p_retryable boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j media_jobs; v media_versions; a media_assets; why text; n int; out_sha text; out_size bigint;
begin
  select * into j from media_jobs where id = p_job for update;
  if j.id is null or j.locked_by is distinct from p_worker or j.status <> 'running' then return jsonb_build_object('lost', true); end if;
  if not p_ok then
    if j.cancel_requested then
      update media_jobs set status = 'cancelled', finished_at = now(), locked_by = null, locked_until = null, last_error = left(p_error, 2000) where id = j.id;
    elsif p_retryable and j.attempts < j.max_attempts then
      update media_jobs set status = 'queued', locked_by = null, locked_until = null, last_error = left(p_error, 2000),
             next_attempt_at = now() + make_interval(secs => least(3600, 30 * power(2, j.attempts)::int)) where id = j.id;
    else
      update media_jobs set status = case when p_retryable then 'dead' else 'failed' end, finished_at = now(), locked_by = null, locked_until = null,
             last_error = left(p_error, 2000) where id = j.id;
      if j.kind = 'ingest' then
        update media_versions set state = 'falhou', failed_reason = left('verificacao_falhou: ' || coalesce(p_error, ''), 500)
         where id = j.version_id and state = 'pendente';
      end if;
    end if;
    insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
    values ('system', 'worker ' || p_worker, j.workspace_id, 'media.job_error', 'media_job', j.id::text,
            jsonb_build_object('kind', j.kind, 'attempt', j.attempts, 'error', left(p_error, 500), 'retryable', p_retryable), 'media:' || coalesce(j.asset_id::text, ''));
    return jsonb_build_object('lost', false);
  end if;

  if j.kind = 'ingest' then
    select * into v from media_versions where id = j.version_id for update;
    if v.state <> 'pendente' then
      update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
      return jsonb_build_object('lost', false, 'state', v.state);
    end if;
    if (p_result->>'size_bytes')::bigint is distinct from v.size_bytes then
      why := format('tamanho_diferente: declarado %s, guardado %s', v.size_bytes, coalesce(p_result->>'size_bytes', 'desconhecido'));
    elsif lower(coalesce(p_result->>'sha256', '')) <> v.sha256 then
      why := 'checksum_diferente: o SHA-256 do objeto guardado não é o do ficheiro do browser';
    end if;
    if why is not null then
      update media_versions set state = 'falhou', failed_reason = why where id = v.id;
      update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result || jsonb_build_object('rejected', why) where id = j.id;
      insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
      values ('system', 'worker ' || p_worker, j.workspace_id, 'media.upload_failed', 'media_asset', v.asset_id::text,
              jsonb_build_object('version_id', v.id, 'reason', why), 'media:' || v.asset_id);
      return jsonb_build_object('lost', false, 'state', 'falhou');
    end if;
    update media_versions set state = 'pronta', completed_at = now(), checksum_verified = true, checksum_verified_at = now(),
           media_info = p_result->'info',
           proxy_path = nullif(p_result->>'proxy_key', ''),
           proxy_state = case when v.mime like 'video/%' then case when nullif(p_result->>'proxy_key', '') is not null then 'pronta' else 'falhou' end else 'nao_aplica' end,
           proxy_error = p_result->>'proxy_error'
     where id = v.id returning * into v;
    update media_assets x set current_version_id = v.id
     where x.id = v.asset_id and (x.current_version_id is null or (select version_no from media_versions where id = x.current_version_id) < v.version_no)
     returning * into a;
    if a.id is null then select * into a from media_assets where id = v.asset_id; end if;
    insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
    values ('system', 'worker ' || p_worker, j.workspace_id, 'media.version_ready', 'media_asset', v.asset_id::text,
            jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'size_bytes', v.size_bytes, 'sha256', v.sha256, 'checksum_verified', true,
                               'proxy', v.proxy_state), 'media:' || v.asset_id);
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (j.workspace_id, 'asset.uploaded', 'media_asset', v.asset_id::text, jsonb_build_object('version_id', v.id, 'version_no', v.version_no,
            'kind', a.kind, 'content_id', a.content_id, 'size_bytes', v.size_bytes, 'mime', v.mime));
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta');
  end if;

  if j.kind = 'package' then
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta', 'documents', (select count(*) from media_job_outputs where job_id = j.id));
  end if;

  -- export
  out_sha := lower(coalesce(p_result->>'sha256', '')); out_size := (p_result->>'size_bytes')::bigint;
  if out_sha !~ '^[0-9a-f]{64}$' or out_size is null or out_size <= 0 or coalesce(p_result->>'key', '') <> j.input->>'out_key' then
    update media_jobs set status = 'failed', finished_at = now(), locked_by = null, locked_until = null, last_error = 'resultado_invalido', result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'falhou');
  end if;
  select * into a from media_assets where id = j.asset_id for update;
  n := coalesce((select max(version_no) from media_versions where asset_id = a.id), 0) + 1;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256,
                              upload_expires_at, uploaded_by, uploaded_label, storage_provider)
  values (j.workspace_id, a.id, n, 'upload', 'pendente', 'r2', j.input->>'out_key',
          left(regexp_replace(coalesce(a.title, 'video'), '[^A-Za-z0-9 ._-]', '', 'g'), 120) || ' (edição v' || (j.input->>'edit_version_no') || ').mp4',
          out_size, 'video/mp4', out_sha, now() + interval '1 hour', j.created_by, j.created_label, 'r2')
  returning * into v;
  update media_versions set state = 'pronta', completed_at = now(), checksum_verified = true, checksum_verified_at = now(), upload_claimed_at = now(),
         media_info = p_result->'info', proxy_path = nullif(p_result->>'proxy_key', ''),
         proxy_state = case when nullif(p_result->>'proxy_key', '') is not null then 'pronta' else 'falhou' end
   where id = v.id returning * into v;
  update media_assets set current_version_id = v.id where id = a.id;
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'edit.exported', 'media_asset', a.id::text,
          jsonb_build_object('job_id', j.id, 'version_id', v.id, 'version_no', n, 'edit_version_id', j.edit_version_id, 'size_bytes', out_size), 'media:' || a.id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'asset.uploaded', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', n, 'kind', a.kind,
          'content_id', a.content_id, 'size_bytes', out_size, 'mime', 'video/mp4', 'from_edit', j.edit_version_id));
  update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, version_id = v.id,
         result = p_result || jsonb_build_object('version_id', v.id, 'version_no', n) where id = j.id;
  if j.created_by is not null then
    perform public._notify(j.created_by, j.workspace_id, 'video_decision', 'media_asset', a.id::text,
      'Exportação pronta: ' || coalesce(a.title, 'vídeo') || ' (v' || n || ')', 'A versão editada já está na revisão.', 'export:' || j.id);
  end if;
  return jsonb_build_object('lost', false, 'state', 'pronta', 'version_id', v.id, 'version_no', n);
end $$;

-- Fim de um pacote: avisa quem pediu.
create or replace function public._media_package_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if new.kind = 'package' and new.status = 'done' and old.status is distinct from 'done' and new.created_by is not null then
    select count(*) into n from media_job_outputs where job_id = new.id;
    perform public._notify(new.created_by, new.workspace_id, 'video_decision', 'media_job', new.id::text,
      'Pacote de edição pronto: ' || n || ' vídeos para rever', 'Abre Edição automática para rever e exportar.', 'package:' || new.id);
  end if;
  return new;
end $$;
drop trigger if exists media_jobs_package_done on public.media_jobs;
create trigger media_jobs_package_done after update of status on public.media_jobs for each row execute function public._media_package_done();

revoke all on function public._media_package_done() from public, anon, authenticated;
revoke all on function public.media_worker_package_save(text, uuid, text, int, jsonb) from public, anon, authenticated;
grant execute on function public.media_worker_package_save(text, uuid, text, int, jsonb) to engine_worker, service_role;
revoke all on function public.edit_package_request(text, uuid, uuid, text[], text, text), public.edit_package_list(text, text),
  public.edit_doc_list(text, text) from public, anon;
grant execute on function public.edit_package_request(text, uuid, uuid, text[], text, text), public.edit_package_list(text, text),
  public.edit_doc_list(text, text) to authenticated;

/* Rollback (compatível): drop trigger media_jobs_package_done on public.media_jobs; drop function public._media_package_done(),
   public.media_worker_package_save(text, uuid, text, int, jsonb), public.edit_doc_list(text, text), public.edit_package_list(text, text),
   public.edit_package_request(text, uuid, uuid, text[], text, text);
   contract posterior (sem jobs package): drop table public.media_job_outputs; repor o check de kind sem 'package'. */
