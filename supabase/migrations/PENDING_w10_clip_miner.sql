-- W10-12 · Clip Miner MVP: cortes de vídeos longos (CLIP-01..07, SCALE-03, VAR-06; ADR-0060). Expand (só aditivo e compatível
-- com o main): 1 capacidade (clips.mine, já registada no CHG-008), 1 flag (clips.miner), alarga o check de kind de media_jobs
-- com 'clips', 1 tabela fechada à API (media_job_clips: um corte por linha, com os metadados do candidato), RPCs novas para a app
-- e para o worker, e três corpos substituídos com a mesma assinatura e as mesmas chaves de resposta:
--   media_worker_finish (ramo 'clips' igual ao do pacote), media_review_list (passa a incluir os cortes, que não têm guião).
-- Fonte = ficheiro master original na Biblioteca do cliente, no R2 (CLIP-01). Os cortes são propostas da IA (versão 1 "ai" dos
-- documentos de edição); um humano revê no editor, exporta e decide na revisão em lote. Nada é publicado aqui.
-- Até esta migração existir, um worker que peça 'clips' em media_worker_claim não recebe nada (o check de kind não deixa haver
-- jobs 'clips'), por isso o motor pode sair antes da app.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('clips.mine', 'Clipping', 'M', array['ws'], 'ativo', 'Encontrar cortes num vídeo longo (Clip Miner)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes, risk = excluded.risk;
-- mesmo grupo que edit.timeline (cada pedido gasta transcrição e IA); outros por grant individual no Centro de Acessos
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'clips.mine'), ('ws', 'workspace_admin', 'clips.mine'), ('ws', 'manager', 'clips.mine')
on conflict do nothing;
insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('clips.miner', 'Cortes de vídeos longos', 'Edição', 'ws', 'owner',
   'Clip Miner (CLIP-01..07): de um vídeo longo na Biblioteca (R2) a 5-10 cortes verticais propostos pela IA, com pontuação, justificação, etiquetas de polémica e riscos, para rever no editor e exportar. Precisa também de edit.studio e media.r2.')
on conflict do nothing;

alter table public.media_jobs drop constraint if exists media_jobs_kind_check;
alter table public.media_jobs add constraint media_jobs_kind_check check (kind in ('ingest', 'export', 'package', 'clips'));

create table if not exists public.media_job_clips (
  job_id uuid not null references public.media_jobs(id),
  idx int not null check (idx between 1 and 20),
  workspace_id text not null references public.clients(id),
  master_asset_id uuid not null references public.media_assets(id),
  asset_id uuid not null references public.media_assets(id),
  edit_version_id uuid references public.edit_versions(id),
  meta jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key (job_id, idx)
);
create index if not exists media_job_clips_asset_idx on public.media_job_clips (asset_id);
create index if not exists media_job_clips_ws_idx on public.media_job_clips (workspace_id, created_at desc);
alter table public.media_job_clips enable row level security;
revoke all on public.media_job_clips from anon, authenticated;

-- Acesso comum: editor ligado e acessível (media.read, edit.studio, edit.timeline|guided) + flag clips.miner.
create or replace function public._clips_require(p_ws text, p_token text, p_action text, p_entity text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid;
begin
  uid := public._edit_require(p_ws, p_token, p_action, p_entity, false);
  if not public._flag_on('clips.miner', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os cortes de vídeos longos ainda não estão ligados neste cliente.'; end if;
  return uid;
end $$;

-- Metadados de um corte que a app mostra (sem nada fora do que o worker gravou e validou aqui).
create or replace function public._clip_meta_problem(m jsonb) returns text
language plpgsql immutable set search_path = public as $$
begin
  if jsonb_typeof(m) is distinct from 'object' then return 'metadados em falta'; end if;
  if octet_length(m::text) > 40000 then return 'metadados demasiado grandes'; end if;
  if jsonb_typeof(m->'score') is distinct from 'number' or (m->>'score')::numeric not between 0 and 100 then return 'pontuação entre 0 e 100'; end if;
  if jsonb_typeof(m->'start') is distinct from 'string' or jsonb_typeof(m->'end') is distinct from 'string' then return 'início/fim em IDs de frase'; end if;
  if jsonb_typeof(coalesce(m->'polemic', '[]')) <> 'array' or jsonb_typeof(coalesce(m->'risks', '[]')) <> 'array' then return 'etiquetas inválidas'; end if;
  if char_length(coalesce(m->>'title', '')) = 0 or coalesce(array_length(regexp_split_to_array(btrim(m->>'title'), '\s+'), 1), 0) > 8 then
    return 'título com 1 a 8 palavras'; end if;
  -- portão da dignidade (CLIP-04): um corte bloqueado nunca chega à app, nem que o worker o mande
  if coalesce((m->'dignity'->>'blocked')::boolean, false) then return 'corte bloqueado pelo portão da dignidade'; end if;
  return null;
end $$;

-- Pedir: um vídeo longo (versão R2 pronta de vídeo deste cliente, ativo ativo). Idempotente pelo vídeo e pelo número de cortes.
create or replace function public.clips_request(p_ws text, p_version uuid, p_count int default 8, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; v media_versions; a media_assets; k text; j media_jobs; n int := coalesce(p_count, 8); dur numeric;
begin
  uid := public._clips_require(p_ws, p_token, 'clips.request', coalesce(p_version::text, ''));
  if not public.ws_can('clips.mine', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'clips.mine');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os cortes precisam do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  if n not between 5 and 10 then raise exception 'numero_invalido' using errcode = '22023', detail = 'Pede entre 5 e 10 cortes por vídeo.'; end if;
  select x.* into v from media_versions x join media_assets y on y.id = x.asset_id
   where x.id = p_version and x.workspace_id = p_ws and x.state = 'pronta' and x.storage_provider = 'r2' and x.mime like 'video/%' and y.lifecycle = 'ativo';
  if v.id is null then
    raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'O vídeo tem de estar pronto na Biblioteca (no R2) deste cliente.'; end if;
  select * into a from media_assets where id = v.asset_id;
  dur := case when jsonb_typeof(v.media_info->'duration') = 'number' then (v.media_info->>'duration')::numeric end;
  if dur is not null and dur < 120 then
    raise exception 'video_curto' using errcode = '22023', detail = 'O vídeo tem menos de 2 minutos: os cortes são para vídeos longos.'; end if;
  if dur is not null and dur > 4 * 3600 then
    raise exception 'video_longo' using errcode = '22023', detail = 'O vídeo tem mais de 4 horas: corta-o em partes antes de pedir cortes.'; end if;
  k := 'clips:' || v.id || ':' || n;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, version_id, asset_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'clips', k, v.id, a.id,
            jsonb_build_object('master', jsonb_build_object('version_id', v.id, 'asset_id', a.id, 'key', v.storage_path, 'name', v.original_name,
                                                            'title', a.title, 'info', v.media_info),
                               'count', n, 'language', 'pt'),
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'clips.requested', 'media_job', j.id::text, null,
      jsonb_build_object('version_id', v.id, 'asset_id', a.id, 'count', n));
  end if;
  return public._media_job_json(j);
end $$;

create or replace function public._clip_json(c media_job_clips) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('idx', c.idx, 'asset_id', c.asset_id, 'title', a.title, 'meta', c.meta, 'active', a.lifecycle = 'ativo',
           'version_no', (select ev.version_no from edit_documents d join edit_versions ev on ev.id = d.current_version_id where d.asset_id = a.id),
           'has_video', a.current_version_id is not null,
           'export', (select jsonb_build_object('status', x.status, 'progress', x.progress) from media_jobs x
                       where x.asset_id = a.id and x.kind = 'export' order by x.created_at desc limit 1))
  from media_assets a where a.id = c.asset_id
$$;

-- Pedidos recentes do cliente e os cortes que cada um criou (metadados do candidato: pontuação, justificação, etiquetas, riscos).
create or replace function public.clips_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._clips_require(p_ws, p_token, 'clips.read', p_ws);
  return coalesce((select jsonb_agg(public._media_job_json(j) || jsonb_build_object(
      'master_name', j.input->'master'->>'name', 'master_title', j.input->'master'->>'title', 'count', (j.input->>'count')::int,
      'master_active', exists (select 1 from media_assets m where m.id = j.asset_id and m.lifecycle = 'ativo'),
      'clips', (select coalesce(jsonb_agg(public._clip_json(c) order by c.idx), '[]') from media_job_clips c where c.job_id = j.id))
      order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'clips' order by created_at desc limit 20) j), '[]');
end $$;

-- Exportar todos os cortes de um pedido: um export por corte, pelas regras de edit_export_request (como edit_package_export).
create or replace function public.clips_export(p_ws text, p_job uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; o record; r jsonb; queued int := 0; fails jsonb := '[]'; jobs jsonb := '[]';
begin
  perform public._clips_require(p_ws, p_token, 'clips.export', p_job::text);
  if not public.ws_can('edit.export', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'clips.export');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into j from media_jobs where id = p_job and workspace_id = p_ws and kind = 'clips';
  if j.id is null then raise exception 'pedido_nao_encontrado' using errcode = 'P0002'; end if;
  if j.status <> 'done' then raise exception 'pedido_por_acabar' using errcode = '22023', detail = 'A procura de cortes ainda não acabou.'; end if;
  for o in select x.asset_id, a.title from media_job_clips x join media_assets a on a.id = x.asset_id
            where x.job_id = j.id and a.lifecycle = 'ativo' order by x.idx loop
    begin
      r := public.edit_export_request(p_ws, o.asset_id, null, p_token);
      queued := queued + 1;
      jobs := jobs || jsonb_build_array(jsonb_build_object('asset_id', o.asset_id, 'job_id', r->>'id', 'status', r->>'status'));
    exception when others then
      fails := fails || jsonb_build_array(jsonb_build_object('asset_id', o.asset_id, 'title', o.title, 'error', coalesce(nullif(sqlerrm, ''), 'erro')));
    end;
  end loop;
  perform public._media_audit(p_ws, 'clips.export', 'media_job', p_job::text, null,
    jsonb_build_object('queued', queued, 'failed', jsonb_array_length(fails)));
  return jsonb_build_object('queued', queued, 'jobs', jobs, 'failed', fails);
end $$;

-- Worker: grava a versão 1 do documento de um corte (idempotente por job e posição). Cria o ativo de vídeo (ainda sem ficheiro).
-- O documento tem de ser válido (_edit_doc_problem) e só pode apontar para o vídeo do pedido (source.cams); os metadados passam
-- em _clip_meta_problem (o portão da dignidade é a segunda linha aqui). O vídeo longo tem de continuar ativo.
create or replace function public.media_worker_clips_save(p_worker text, p_job uuid, p_idx int, p_doc jsonb, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; o media_job_clips; m media_assets; a media_assets; d edit_documents; v edit_versions; why text; ttl text; cams jsonb;
begin
  select * into j from media_jobs where id = p_job;
  if j.id is null or j.kind <> 'clips' or j.status <> 'running' or j.locked_by is distinct from p_worker then
    raise exception 'job_perdido' using errcode = 'PT409'; end if;
  select * into o from media_job_clips where job_id = j.id and idx = p_idx;
  if o.job_id is not null then return jsonb_build_object('asset_id', o.asset_id, 'repeated', true); end if;
  if p_idx is null or p_idx < 1 or p_idx > least(20, coalesce((j.input->>'count')::int, 10)) then
    raise exception 'corte_invalido' using errcode = '22023', detail = 'Posição do corte fora do pedido.'; end if;
  select * into m from media_assets where id = j.asset_id and workspace_id = j.workspace_id and lifecycle = 'ativo';
  if m.id is null then raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'O vídeo longo foi apagado ou está no lixo.'; end if;
  why := public._edit_doc_problem(p_doc);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  cams := coalesce(p_doc->'source'->'cams', '{}');
  if jsonb_typeof(cams) <> 'object' or cams = '{}'::jsonb
     or exists (select 1 from jsonb_each_text(cams) c where c.value is distinct from j.input->'master'->>'name') then
    raise exception 'documento_invalido: o corte só pode usar o vídeo do pedido' using errcode = '22023'; end if;
  why := public._clip_meta_problem(p_meta);
  if why is not null then raise exception 'corte_invalido: %', why using errcode = '22023'; end if;
  ttl := 'Corte ' || p_idx || ' · ' || btrim(p_meta->>'title');
  insert into media_assets (workspace_id, kind, title, tags, status, content_id, notes, created_by, created_label)
  values (j.workspace_id, 'video', left(ttl, 160), array['corte', 'corte_' || p_idx, lower(coalesce(nullif(p_doc->>'style', ''), 's15'))], 'em_trabalho', null,
          left('Criado pelo Clip Miner a partir de ' || coalesce(j.input->'master'->>'name', '?') || ' (proposta da IA para rever).', 500),
          j.created_by, 'Clip Miner')
  returning * into a;
  insert into edit_documents (workspace_id, asset_id, content_id) values (j.workspace_id, a.id, null) returning * into d;
  insert into edit_versions (workspace_id, document_id, version_no, doc, source, note, created_by, created_label)
  values (j.workspace_id, d.id, 1, p_doc, 'ai', 'Versão 1 do Clip Miner (proposta da IA)', null, 'Clip Miner')
  returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  insert into media_job_clips (job_id, idx, workspace_id, master_asset_id, asset_id, edit_version_id, meta)
  values (j.id, p_idx, j.workspace_id, m.id, a.id, v.id, p_meta);
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'clips.doc', 'media_asset', a.id::text,
          jsonb_build_object('job_id', j.id, 'idx', p_idx, 'master_asset_id', m.id, 'edit_version_id', v.id, 'score', p_meta->'score'), 'media:' || a.id);
  return jsonb_build_object('asset_id', a.id, 'edit_version_id', v.id, 'repeated', false);
end $$;

-- Fechar: igual a 20261105192728_w5_edit_package.sql mais o ramo 'clips' (guarda o resultado; os cortes já foram gravados um a um).
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

  if j.kind = 'clips' then
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta', 'clips', (select count(*) from media_job_clips where job_id = j.id));
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

-- Fim de uma procura de cortes: avisa quem pediu.
create or replace function public._media_clips_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if new.kind = 'clips' and new.status = 'done' and old.status is distinct from 'done' and new.created_by is not null then
    select count(*) into n from media_job_clips where job_id = new.id;
    perform public._notify(new.created_by, new.workspace_id, 'video_decision', 'media_job', new.id::text,
      'Cortes prontos: ' || n || ' para rever', 'Abre Cortes de vídeos longos para rever e exportar.', 'clips:' || new.id);
  end if;
  return new;
end $$;
drop trigger if exists media_jobs_clips_done on public.media_jobs;
create trigger media_jobs_clips_done after update of status on public.media_jobs for each row execute function public._media_clips_done();

-- Revisão em lote (EDL-02): os cortes não têm guião; entram na fila como os vídeos dos guiões (corpo de 20261105211447_w5_review_stored.sql
-- com "join guioes" passado a "left join" só para ativos que são cortes do Clip Miner).
create or replace function public.media_review_list(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text[]; q text := nullif(btrim(p_filters->>'q'), '');
begin
  perform public._review_read(p_ws, p_token);
  st := coalesce((select array_agg(x) from jsonb_array_elements_text(p_filters->'status') x), array['in_review', 'changes_requested', 'approved', 'rejected']);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._review_item_json(a) order by g.date, g.n, public._review_variant(a.tags), a.title), '[]')
              from media_assets a left join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
              where a.workspace_id = p_ws and a.lifecycle = 'ativo' and public._review_eligible(v)
                and ((g.id is not null and g.deleted_at is null)
                     or (a.content_id is null and exists (select 1 from media_job_clips c where c.asset_id = a.id and c.workspace_id = p_ws)))
                and public._review_status(v.id) = any (st)
                and (q is null or g.tema ilike '%' || q || '%' or a.title ilike '%' || q || '%')),
    'counts', (select coalesce(jsonb_object_agg(s, c), '{}') from (
                 select public._review_status(v.id) s, count(*) c
                   from media_assets a left join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
                  where a.workspace_id = p_ws and a.lifecycle = 'ativo' and public._review_eligible(v)
                    and ((g.id is not null and g.deleted_at is null)
                         or (a.content_id is null and exists (select 1 from media_job_clips c where c.asset_id = a.id and c.workspace_id = p_ws)))
                  group by 1) z),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', p_ws, p_token), 'decide', public.ws_can('review.approve', p_ws, p_token),
                              'link', public.ws_can('media.upload', p_ws, p_token)));
end $$;

revoke all on function public._clips_require(text, text, text, text), public._clip_meta_problem(jsonb), public._clip_json(media_job_clips),
  public._media_clips_done() from public, anon, authenticated;
revoke all on function public.media_worker_clips_save(text, uuid, int, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.media_worker_clips_save(text, uuid, int, jsonb, jsonb) to engine_worker, service_role;
revoke all on function public.clips_request(text, uuid, int, text), public.clips_list(text, text), public.clips_export(text, uuid, text) from public, anon;
grant execute on function public.clips_request(text, uuid, int, text), public.clips_list(text, text), public.clips_export(text, uuid, text) to authenticated;

/* Rollback (compatível, por esta ordem):
   1. flag_set('clips.miner', <ws>, 'off') onde estiver ligada (a página e as RPCs param com 55000).
   2. repor media_review_list de 20261105211447_w5_review_stored.sql e media_worker_finish de 20261105192728_w5_edit_package.sql;
      drop trigger if exists media_jobs_clips_done on public.media_jobs;
      drop function if exists public._media_clips_done(), public.media_worker_clips_save(text, uuid, int, jsonb, jsonb),
        public.clips_export(text, uuid, text), public.clips_list(text, text), public.clips_request(text, uuid, int, text),
        public._clip_json(media_job_clips), public._clip_meta_problem(jsonb), public._clips_require(text, text, text, text);
   3. contract posterior (sem jobs 'clips'): drop table public.media_job_clips; repor o check de kind sem 'clips';
      delete from role_capabilities where capability = 'clips.mine'; update capabilities set status = 'W5' where key = 'clips.mine';
      delete from feature_flags where key = 'clips.miner'; delete from feature_flag_defs where key = 'clips.miner'.
   Os ativos e documentos criados pelos cortes ficam (são dados do cliente; vão para o lixo pela Biblioteca). */
