-- W5-07 · vídeo no Cloudflare R2 + jobs de media no worker (ING-01, FR-08-01, EDL-08, EDL-11; ADR-0047). Expand (aditivo):
-- 1 flag (media.r2, ligada por cliente, não por pessoa), colunas novas em media_versions, tabela media_jobs (fechada à API),
-- funções novas para o worker (engine_worker) e para o editor. Reescreve media_upload_begin/target/complete e
-- _media_policy/_media_usage só para o caso R2: para o Supabase Storage o comportamento é o mesmo.
-- O R2 não é visível à base: ninguém confia no browser sobre o objeto. Para R2, "concluir" só pede a verificação;
-- é o worker (credenciais R2 no alojamento) que lê o objeto, confere tamanho e SHA-256, gera o proxy e marca pronta.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('media.r2', 'Vídeo no R2', 'Media', 'ws', 'off',
   'Uploads novos deste cliente vão para o Cloudflare R2 (ficheiros até 50 GB, envio por partes) e o worker verifica, gera o proxy e exporta. Liga-se por cliente inteiro (fase "all"); outras fases não mudam o armazenamento.')
on conflict do nothing;

alter table public.media_versions
  add column if not exists storage_provider text not null default 'supabase',
  add column if not exists upload_claimed_at timestamptz,
  add column if not exists proxy_path text,
  add column if not exists proxy_state text,
  add column if not exists proxy_error text,
  add column if not exists media_info jsonb;
do $$ begin
  alter table public.media_versions add constraint media_versions_provider_check check (storage_provider in ('supabase', 'r2'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.media_versions add constraint media_versions_proxy_state_check check (proxy_state is null or proxy_state in ('pendente', 'pronta', 'falhou', 'nao_aplica'));
exception when duplicate_object then null; end $$;

-- R2 está ligado para o cliente inteiro? (fase "all"; owner/agency não contam: o sítio dos bytes não depende de quem envia)
create or replace function public._media_r2(p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select public._flag_stage('media.r2', c.organization_id, c.id) = 'all' from clients c where c.id = p_ws), false)
$$;

-- Teto por ficheiro: R2 com envio por partes vai até 50 GiB [pressuposto, ADR-0047]; Supabase como antes.
create or replace function public._media_ceiling_ws(p_ws text) returns bigint
language sql stable security definer set search_path = public as $$
  select case when public._media_r2(p_ws) then 53687091200 else public._media_ceiling() end
$$;

create or replace function public._media_policy(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'allowed_mime', to_jsonb(coalesce(p.allowed_mime, public._media_default_mime())),
    'max_file_bytes', least(coalesce(p.max_file_bytes, public._media_ceiling_ws(p_ws)), public._media_ceiling_ws(p_ws)),
    'ceiling_bytes', public._media_ceiling_ws(p_ws),
    -- quota por defeito: 5 GiB no Supabase, 500 GiB no R2 (gravações brutas por sessão) [pressuposto, ADR-0047]
    'quota_bytes', coalesce(p.quota_bytes, case when public._media_r2(p_ws) then 536870912000 else 5368709120 end),
    'trash_days', coalesce(p.trash_days, 30),
    'pending_hours', 24,
    'storage', case when public._media_r2(p_ws) then 'r2' else 'supabase' end,
    'customized', p.workspace_id is not null,
    'updated_at', p.updated_at, 'updated_label', p.updated_label)
  from (select 1) one left join media_policies p on p.workspace_id = p_ws
$$;

-- Uso: objetos do Supabase como antes + versões R2 (o tamanho conta a partir do momento em que o envio é dado como feito).
create or replace function public._media_usage(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  with o as (
    select o.name, coalesce((o.metadata->>'size')::bigint, 0) as size, v.state, v.upload_expires_at, a.lifecycle
      from storage.objects o left join media_versions v on v.storage_path = o.name left join media_assets a on a.id = v.asset_id
     where o.bucket_id = 'media' and o.name like p_ws || '/%'
    union all
    select v.storage_path, v.size_bytes, v.state, v.upload_expires_at, a.lifecycle
      from media_versions v join media_assets a on a.id = v.asset_id
     where v.workspace_id = p_ws and v.storage_provider = 'r2' and v.state in ('pronta', 'pendente', 'falhou')
       and (v.state = 'pronta' or v.upload_claimed_at is not null)),
  r as (
    select coalesce(sum(v.size_bytes), 0) as reserved from media_versions v
     where v.workspace_id = p_ws and v.state = 'pendente' and v.upload_expires_at > now() and v.upload_claimed_at is null
       and not exists (select 1 from storage.objects x where x.bucket_id = 'media' and x.name = v.storage_path))
  select jsonb_build_object(
    'stored_bytes', coalesce((select sum(size) from o), 0),
    'active_bytes', coalesce((select sum(size) from o where state = 'pronta' and lifecycle = 'ativo'), 0),
    'trash_bytes', coalesce((select sum(size) from o where state = 'pronta' and lifecycle = 'no_lixo'), 0),
    'orphan_bytes', coalesce((select sum(size) from o where state is null or state = 'falhou' or (state = 'pendente' and upload_expires_at <= now())), 0),
    'pending_bytes', coalesce((select sum(size) from o where state = 'pendente' and upload_expires_at > now()), 0) + (select reserved from r),
    'reserved_bytes', (select reserved from r),
    'objects', (select count(*) from o))
$$;

create or replace function public._media_version_json(v media_versions) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when v.id is null then null else jsonb_build_object(
    'id', v.id, 'version_no', v.version_no, 'source', v.source, 'state', v.state, 'original_name', v.original_name,
    'size_bytes', v.size_bytes, 'mime', v.mime, 'sha256', v.sha256, 'checksum_verified', v.checksum_verified,
    'external_url', v.external_url, 'upload_expires_at', v.upload_expires_at, 'completed_at', v.completed_at,
    'failed_reason', v.failed_reason, 'deleted_at', v.deleted_at, 'created_at', v.created_at, 'uploaded_label', v.uploaded_label,
    'mine', v.uploaded_by = auth.uid(),
    'expired', v.state = 'pendente' and v.upload_expires_at <= now(),
    'storage', v.storage_provider,
    'verifying', v.state = 'pendente' and v.upload_claimed_at is not null,
    'proxy_state', v.proxy_state, 'proxy_error', v.proxy_error, 'media_info', v.media_info) end
$$;

-- ───────────────────────────── jobs de media (verificar+proxy, exportar) ─────────────────────────────
create table if not exists public.media_jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  kind text not null check (kind in ('ingest', 'export')),
  idempotency_key text not null unique,
  version_id uuid references public.media_versions(id),
  asset_id uuid references public.media_assets(id),
  edit_version_id uuid references public.edit_versions(id),
  input jsonb not null default '{}',
  status text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed', 'dead', 'cancelled')),
  attempts int not null default 0, max_attempts int not null default 5,
  next_attempt_at timestamptz not null default now(),
  locked_by text, locked_until timestamptz, heartbeat_at timestamptz,
  progress jsonb, result jsonb, last_error text, cancel_requested boolean not null default false,
  created_by uuid references auth.users(id) on delete set null, created_label text,
  created_at timestamptz not null default now(), started_at timestamptz, finished_at timestamptz
);
create index if not exists media_jobs_queue_idx on public.media_jobs (status, next_attempt_at) where status in ('queued', 'running');
create index if not exists media_jobs_asset_idx on public.media_jobs (asset_id, created_at desc);
alter table public.media_jobs enable row level security;
revoke all on public.media_jobs from anon, authenticated;

create or replace function public._media_job_json(j media_jobs) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', j.id, 'kind', j.kind, 'status', j.status, 'attempts', j.attempts, 'max_attempts', j.max_attempts,
    'progress', j.progress, 'result', j.result, 'last_error', j.last_error, 'created_label', j.created_label, 'created_at', j.created_at,
    'started_at', j.started_at, 'finished_at', j.finished_at, 'version_id', j.version_id, 'edit_version_id', j.edit_version_id,
    'edit_version_no', (select version_no from edit_versions where id = j.edit_version_id),
    'worker_seen', exists (select 1 from agent_workers w where w.last_seen > now() - interval '2 minutes'))
$$;

-- ───────────────────────────── uploads (reescritos só no ramo R2) ─────────────────────────────
create or replace function public.media_upload_begin(p_ws text, p_asset_id uuid, p_fields jsonb, p_file jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; lbl text; pol jsonb := public._media_policy(p_ws); use jsonb; a media_assets; v media_versions;
        fname text := btrim(coalesce(p_file->>'name', '')); fsize bigint; fmime text := lower(btrim(coalesce(p_file->>'mime', '')));
        fsha text := lower(btrim(coalesce(p_file->>'sha256', ''))); kind text; n int; path text; avail bigint;
        r2 boolean := public._media_r2(p_ws); bkt text;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_begin', coalesce(p_asset_id::text, p_ws));
  uid := public._media_uid(); lbl := public._media_label(uid);
  bkt := case when r2 then 'r2' else 'media' end;
  begin fsize := (p_file->>'size')::bigint; exception when others then fsize := null; end;
  if fname = '' or char_length(fname) > 255 then raise exception 'nome_invalido' using errcode = '22023', detail = 'O ficheiro precisa de um nome (até 255 caracteres).'; end if;
  if fsize is null or fsize <= 0 then raise exception 'tamanho_invalido' using errcode = '22023', detail = 'O ficheiro está vazio.'; end if;
  if fsha !~ '^[0-9a-f]{64}$' then raise exception 'checksum_invalido' using errcode = '22023', detail = 'Falta o SHA-256 do ficheiro.'; end if;
  if not fmime = any(array(select jsonb_array_elements_text(pol->'allowed_mime'))) then
    raise exception 'tipo_nao_permitido' using errcode = '22023', detail = format('O tipo %s não é permitido neste cliente.', coalesce(nullif(fmime, ''), 'desconhecido')); end if;
  if fsize > (pol->>'max_file_bytes')::bigint then
    raise exception 'ficheiro_grande_demais' using errcode = '22023',
      detail = format('Máximo por ficheiro neste cliente: %s MB.', round((pol->>'max_file_bytes')::numeric / 1048576, 1)); end if;

  if p_asset_id is null then
    kind := coalesce(nullif(p_fields->>'kind', ''), case when fmime like 'video/%' then 'video' when fmime like 'audio/%' then 'audio'
              when fmime like 'image/%' then 'imagem' when fmime in ('text/vtt', 'application/x-subrip') then 'legenda' else 'documento' end);
    if kind not in ('video', 'audio', 'imagem', 'thumbnail', 'legenda', 'documento') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
    select v2.* into v from media_versions v2 join media_assets a2 on a2.id = v2.asset_id
     where v2.workspace_id = p_ws and v2.uploaded_by = uid and v2.state = 'pendente' and v2.upload_expires_at > now()
       and v2.sha256 = fsha and v2.size_bytes = fsize and v2.original_name = fname and a2.current_version_id is null and a2.lifecycle = 'ativo'
     order by v2.created_at desc limit 1;
    if v.id is not null then
      return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'version_no', v.version_no, 'bucket', v.storage_bucket,
        'path', v.storage_path, 'expires_at', v.upload_expires_at, 'reused', true, 'storage', v.storage_provider,
        'verifying', v.upload_claimed_at is not null);
    end if;
    a.id := gen_random_uuid(); a.workspace_id := p_ws; a.kind := kind; a.status := 'em_trabalho'; a.tags := '{}';
    a.title := coalesce(nullif(btrim(p_fields->>'title'), ''), left(regexp_replace(fname, '\.[A-Za-z0-9]{1,10}$', ''), 160));
    a := public._media_apply_fields(a, p_fields - 'kind', array['title', 'tags', 'project_id', 'format', 'status', 'content_id', 'take_id', 'publication_id', 'notes']);
  else
    select * into a from media_assets where id = p_asset_id and workspace_id = p_ws for update;
    if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
    if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023', detail = 'Recupera o ativo do lixo antes de carregar uma versão nova.'; end if;
    if a.kind = 'link_externo' then raise exception 'tipo_invalido' using errcode = '22023', detail = 'Um link externo não recebe ficheiros.'; end if;
    if coalesce(p_fields, '{}') <> '{}' then raise exception 'campo_desconhecido' using errcode = '22023', detail = 'Os dados do ativo mudam-se à parte.'; end if;
    select * into v from media_versions where asset_id = a.id and uploaded_by = uid and state = 'pendente' and upload_expires_at > now()
       and sha256 = fsha and size_bytes = fsize order by version_no desc limit 1;
    if v.id is not null then
      return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'version_no', v.version_no, 'bucket', v.storage_bucket,
        'path', v.storage_path, 'expires_at', v.upload_expires_at, 'reused', true, 'storage', v.storage_provider,
        'verifying', v.upload_claimed_at is not null);
    end if;
  end if;
  if not public._media_kind_mime_ok(a.kind, fmime) then
    raise exception 'tipo_nao_corresponde' using errcode = '22023', detail = format('Um ficheiro %s não serve para um ativo do tipo %s.', fmime, a.kind); end if;
  if (select count(*) from media_versions where workspace_id = p_ws and uploaded_by = uid and state = 'pendente' and upload_expires_at > now()) >= 20 then
    raise exception 'demasiados_pendentes' using errcode = '22023', detail = 'Tens 20 uploads por concluir neste cliente: conclui ou desiste de algum.'; end if;
  use := public._media_usage(p_ws);
  avail := (pol->>'quota_bytes')::bigint - (use->>'stored_bytes')::bigint - (use->>'reserved_bytes')::bigint;
  if fsize > avail then
    raise exception 'quota_excedida' using errcode = '22023',
      detail = format('A quota deste cliente (%s GB) não chega: livre %s MB, o ficheiro tem %s MB.',
        round((pol->>'quota_bytes')::numeric / 1073741824, 2), round(greatest(avail, 0)::numeric / 1048576, 1), round(fsize::numeric / 1048576, 1)); end if;

  if p_asset_id is null then
    insert into media_assets (id, workspace_id, kind, title, tags, project_id, format, status, content_id, take_id, publication_id, notes, created_by, created_label)
    values (a.id, p_ws, a.kind, a.title, a.tags, a.project_id, a.format, a.status, a.content_id, a.take_id, a.publication_id, a.notes, uid, lbl);
  end if;
  n := coalesce((select max(version_no) from media_versions where asset_id = a.id), 0) + 1;
  path := p_ws || '/' || a.id || '/' || n || '/' || public._media_safe_name(fname);
  insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256,
                              upload_expires_at, uploaded_by, uploaded_label, storage_provider)
  values (p_ws, a.id, n, 'upload', 'pendente', bkt, path, fname, fsize, fmime, fsha, now() + make_interval(hours => (pol->>'pending_hours')::int), uid, lbl,
          case when r2 then 'r2' else 'supabase' end)
  returning * into v;
  perform public._media_audit(p_ws, 'media.upload_started', 'media_asset', a.id::text, null,
    jsonb_build_object('version_id', v.id, 'version_no', n, 'size_bytes', fsize, 'mime', fmime, 'sha256', fsha, 'new_asset', p_asset_id is null,
                       'storage', v.storage_provider));
  return jsonb_build_object('asset_id', a.id, 'version_id', v.id, 'version_no', n, 'bucket', bkt, 'path', path, 'expires_at', v.upload_expires_at,
                            'reused', false, 'storage', v.storage_provider, 'verifying', false);
end $$;

create or replace function public.media_upload_target(p_ws text, p_version uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v media_versions; uid uuid;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_target', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws and source = 'upload';
  if v.id is null or v.uploaded_by <> uid then raise exception 'upload_nao_encontrado' using errcode = 'P0002'; end if;
  if v.state <> 'pendente' then raise exception 'upload_terminado' using errcode = '22023', detail = format('Este upload já está %s.', v.state); end if;
  if v.upload_expires_at <= now() then raise exception 'upload_expirado' using errcode = '22023', detail = 'Este upload expirou: carrega o ficheiro outra vez.'; end if;
  if v.upload_claimed_at is not null then
    raise exception 'upload_a_verificar' using errcode = '22023', detail = 'O ficheiro já chegou e está a ser verificado.'; end if;
  return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'bucket', v.storage_bucket, 'path', v.storage_path, 'size_bytes', v.size_bytes,
    'mime', v.mime, 'sha256', v.sha256, 'expires_at', v.upload_expires_at, 'storage', v.storage_provider,
    -- R2: a base não vê o objeto (a rota confere com HEAD); null = desconhecido
    'object_exists', case when v.storage_provider = 'r2' then null
                          else exists (select 1 from storage.objects o where o.bucket_id = 'media' and o.name = v.storage_path) end);
end $$;

-- Concluir: Supabase como antes. R2: marca "enviado, a verificar" e põe um job de verificação na fila (idempotente);
-- a versão só fica pronta quando o worker confere o objeto (media_worker_finish).
create or replace function public.media_upload_complete(p_ws text, p_version uuid, p_server_sha256 text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; o record; uid uuid; why text; sha text := lower(nullif(btrim(coalesce(p_server_sha256, '')), ''));
        j media_jobs;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_complete', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws and source = 'upload' for update;
  if v.id is null or v.uploaded_by <> uid then raise exception 'upload_nao_encontrado' using errcode = 'P0002'; end if;
  if v.state = 'pronta' then
    select * into a from media_assets where id = v.asset_id;
    return jsonb_build_object('state', 'pronta', 'version', public._media_version_json(v), 'asset', public._media_asset_json(a), 'repeated', true);
  end if;
  if v.state <> 'pendente' then raise exception 'upload_terminado' using errcode = '22023', detail = format('Este upload já está %s.', v.state); end if;

  if v.storage_provider = 'r2' then
    if v.upload_claimed_at is null then
      if v.upload_expires_at <= now() then raise exception 'upload_expirado' using errcode = '22023', detail = 'Este upload expirou: carrega o ficheiro outra vez.'; end if;
      update media_versions set upload_claimed_at = now(), upload_expires_at = greatest(upload_expires_at, now() + interval '48 hours'),
             proxy_state = case when mime like 'video/%' then 'pendente' else 'nao_aplica' end
       where id = v.id returning * into v;
      perform public._media_audit(p_ws, 'media.upload_sent', 'media_asset', v.asset_id::text, null, jsonb_build_object('version_id', v.id));
    end if;
    insert into media_jobs (workspace_id, kind, idempotency_key, version_id, asset_id, input, created_by, created_label)
    values (p_ws, 'ingest', 'ingest:' || v.id, v.id, v.asset_id,
            jsonb_build_object('key', v.storage_path, 'size_bytes', v.size_bytes, 'mime', v.mime, 'sha256', v.sha256, 'proxy', v.mime like 'video/%'),
            uid, public._media_label(uid))
    on conflict (idempotency_key) do nothing;
    select * into j from media_jobs where idempotency_key = 'ingest:' || v.id;
    return jsonb_build_object('state', 'pendente', 'verifying', true, 'version', public._media_version_json(v), 'job', public._media_job_json(j));
  end if;

  if sha is not null and sha !~ '^[0-9a-f]{64}$' then raise exception 'checksum_invalido' using errcode = '22023'; end if;
  select * into o from storage.objects where bucket_id = 'media' and name = v.storage_path;
  if o.id is null then
    raise exception 'objeto_em_falta' using errcode = 'P0002', detail = 'O ficheiro ainda não chegou ao armazenamento: tenta enviar outra vez.'; end if;
  if coalesce((o.metadata->>'size')::bigint, -1) <> v.size_bytes then
    why := format('tamanho_diferente: declarado %s, guardado %s', v.size_bytes, coalesce(o.metadata->>'size', 'desconhecido'));
  elsif lower(coalesce(o.metadata->>'mimetype', '')) <> v.mime then
    why := format('tipo_diferente: declarado %s, guardado %s', v.mime, coalesce(o.metadata->>'mimetype', 'desconhecido'));
  elsif sha is not null and sha <> v.sha256 then
    why := 'checksum_diferente: o SHA-256 do objeto guardado não é o do ficheiro do browser';
  end if;
  if why is not null then
    update media_versions set state = 'falhou', failed_reason = why where id = v.id returning * into v;
    perform public._media_audit(p_ws, 'media.upload_failed', 'media_asset', v.asset_id::text, null, jsonb_build_object('version_id', v.id, 'reason', why));
    return jsonb_build_object('state', 'falhou', 'reason', why, 'version', public._media_version_json(v));
  end if;
  update media_versions set state = 'pronta', completed_at = now(), checksum_verified = sha is not null,
         checksum_verified_at = case when sha is not null then now() end
   where id = v.id returning * into v;
  update media_assets x set current_version_id = v.id
   where x.id = v.asset_id and (x.current_version_id is null or (select version_no from media_versions where id = x.current_version_id) < v.version_no)
   returning * into a;
  if a.id is null then select * into a from media_assets where id = v.asset_id; end if;
  perform public._media_audit(p_ws, 'media.version_ready', 'media_asset', v.asset_id::text, null,
    jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'size_bytes', v.size_bytes, 'sha256', v.sha256, 'checksum_verified', v.checksum_verified));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'asset.uploaded', 'media_asset', v.asset_id::text, jsonb_build_object('version_id', v.id, 'version_no', v.version_no,
          'kind', a.kind, 'content_id', a.content_id, 'size_bytes', v.size_bytes, 'mime', v.mime));
  return jsonb_build_object('state', 'pronta', 'version', public._media_version_json(v), 'asset', public._media_asset_json(a), 'repeated', false);
end $$;

-- Ler o proxy (pré-visualização leve) de uma versão: só com media.read e o proxy pronto.
create or replace function public.media_proxy_access(p_ws text, p_version uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v media_versions; a media_assets;
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.proxy', p_version::text);
  select * into v from media_versions where id = p_version and workspace_id = p_ws;
  select * into a from media_assets where id = v.asset_id;
  if v.id is null or a.lifecycle <> 'ativo' or v.state <> 'pronta' then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  if v.proxy_state is distinct from 'pronta' or v.proxy_path is null then
    raise exception 'proxy_indisponivel' using errcode = '55000', detail = 'A versão leve deste vídeo ainda não está pronta.'; end if;
  return jsonb_build_object('bucket', 'r2', 'path', v.proxy_path, 'mime', 'video/mp4', 'ttl_seconds', 3600);
end $$;

-- ───────────────────────────── editor: fontes da pré-visualização e exportar ─────────────────────────────
-- As câmaras do documento (source.cams: nome do ficheiro da gravação) resolvem-se para vídeos R2 prontos do mesmo cliente
-- com esse nome de ficheiro (o mais recente). Devolve por câmara o estado e, se houver, o caminho do proxy e do original.
create or replace function public._edit_resolve_cams(p_ws text, p_doc jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(c.key, (
    select jsonb_build_object('name', c.value #>> '{}', 'version_id', v.id, 'asset_id', v.asset_id, 'key', v.storage_path,
             'proxy_key', case when v.proxy_state = 'pronta' then v.proxy_path end, 'proxy_state', v.proxy_state,
             'size_bytes', v.size_bytes, 'media_info', v.media_info)
      from media_versions v join media_assets a on a.id = v.asset_id
     where v.workspace_id = p_ws and v.storage_provider = 'r2' and v.state = 'pronta' and a.lifecycle = 'ativo'
       and v.original_name = regexp_replace(c.value #>> '{}', '^.*/', '')
     order by v.completed_at desc nulls last limit 1)), '{}')
  from jsonb_each(coalesce(p_doc->'source'->'cams', '{}')) c
$$;

create or replace function public.edit_preview_sources(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d edit_documents; v edit_versions; cams jsonb;
begin
  perform public._edit_require(p_ws, p_token, 'edit.preview', p_asset::text, false);
  select * into d from edit_documents where asset_id = p_asset and workspace_id = p_ws;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  cams := public._edit_resolve_cams(p_ws, v.doc);
  return jsonb_build_object('windows', v.doc->'source'->'windows', 'audio', v.doc->'source'->>'audio',
    'cams', (select coalesce(jsonb_object_agg(key, case when value = 'null'::jsonb then jsonb_build_object('state', 'em_falta')
               else jsonb_build_object('state', coalesce(value->>'proxy_state', 'nao_aplica'), 'version_id', value->>'version_id',
                                       'name', value->>'name', 'media_info', value->'media_info') end), '{}')
             from jsonb_each(cams)),
    'names', v.doc->'source'->'cams');
end $$;

-- Exportar uma versão do documento: job idempotente por versão (pedir duas vezes devolve o mesmo job, salvo se falhou).
create or replace function public.edit_export_request(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; d edit_documents; v edit_versions; cams jsonb; missing text; j media_jobs; k text; music jsonb; mv media_versions;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.export', p_asset::text, true);
  if not public.ws_can('edit.export', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.export');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Exportar precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  select * into d from edit_documents where asset_id = p_asset and workspace_id = p_ws;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  cams := public._edit_resolve_cams(p_ws, v.doc);
  select string_agg(coalesce(v.doc->'source'->'cams'->>key, key), ', ') into missing from jsonb_each(cams) where value = 'null'::jsonb;
  if missing is not null or cams = '{}'::jsonb then
    raise exception 'camaras_em_falta' using errcode = '22023',
      detail = format('Carrega primeiro na Biblioteca as gravações: %s.', coalesce(missing, 'nenhuma câmara no documento')); end if;
  if v.doc->'audio'->'music'->>'asset' is not null then
    select x.* into mv from media_versions x join media_assets a on a.id = x.asset_id
     where a.id::text = v.doc->'audio'->'music'->>'asset' and a.workspace_id = p_ws and x.id = a.current_version_id and x.state = 'pronta' and x.source = 'upload';
    if mv.id is null then raise exception 'musica_em_falta' using errcode = '22023', detail = 'A música escolhida já não está na biblioteca.'; end if;
    music := jsonb_build_object('key', mv.storage_path, 'bucket', mv.storage_bucket, 'db', coalesce((v.doc->'audio'->'music'->>'db')::numeric, -18));
  end if;
  k := 'export:' || v.id;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, asset_id, edit_version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'export', k, p_asset, v.id,
            jsonb_build_object('doc', v.doc, 'cams', cams, 'music', music, 'edit_version_no', v.version_no,
                               'out_key', p_ws || '/' || p_asset || '/exports/' || v.id || '.mp4'),
            uid, public._media_label(uid), 3)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.export_requested', 'media_asset', p_asset::text, null,
      jsonb_build_object('job_id', j.id, 'edit_version_id', v.id, 'edit_version_no', v.version_no));
  end if;
  return public._media_job_json(j);
end $$;

create or replace function public.edit_export_list(p_ws text, p_asset uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_asset::text, false);
  return coalesce((select jsonb_agg(public._media_job_json(j) order by j.created_at desc) from
    (select * from media_jobs where workspace_id = p_ws and asset_id = p_asset and kind = 'export' order by created_at desc limit 10) j), '[]');
end $$;

create or replace function public.edit_export_cancel(p_ws text, p_job uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs;
begin
  perform public._edit_require(p_ws, p_token, 'edit.export', p_job::text, true);
  if not public.ws_can('edit.export', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update media_jobs set cancel_requested = true,
         status = case when status = 'queued' then 'cancelled' else status end,
         finished_at = case when status = 'queued' then now() else finished_at end
   where id = p_job and workspace_id = p_ws and kind = 'export' and status in ('queued', 'running') returning * into j;
  if j.id is null then raise exception 'job_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._media_audit(p_ws, 'edit.export_cancelled', 'media_asset', j.asset_id::text, null, jsonb_build_object('job_id', j.id));
  return public._media_job_json(j);
end $$;

-- ───────────────────────────── worker (engine_worker) ─────────────────────────────
create or replace function public.media_worker_claim(p_worker text, p_kinds text[] default array['ingest', 'export'], p_lease_seconds int default 900)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j media_jobs;
begin
  if p_worker is null or length(p_worker) not between 3 and 80 then raise exception 'worker_invalido' using errcode = '22023'; end if;
  insert into agent_workers (id, kinds, last_seen) values (p_worker, p_kinds, now())
  on conflict (id) do update set kinds = (select array(select distinct unnest(agent_workers.kinds || excluded.kinds))), last_seen = now();
  update media_jobs set status = case when attempts >= max_attempts then 'dead' else 'queued' end, next_attempt_at = now(),
         locked_by = null, locked_until = null, last_error = coalesce(last_error, 'worker deixou de responder'),
         finished_at = case when attempts >= max_attempts then now() end
   where status = 'running' and locked_until < now();
  select * into j from media_jobs where status = 'queued' and next_attempt_at <= now() and kind = any (p_kinds)
   order by case kind when 'ingest' then 0 else 1 end, created_at limit 1 for update skip locked;
  if j.id is null then return null; end if;
  update media_jobs set status = 'running', attempts = attempts + 1, locked_by = p_worker,
         locked_until = now() + make_interval(secs => p_lease_seconds), heartbeat_at = now(), started_at = coalesce(started_at, now()), last_error = null
   where id = j.id returning * into j;
  return jsonb_build_object('job', to_jsonb(j));
end $$;

create or replace function public.media_worker_heartbeat(p_worker text, p_job uuid, p_progress jsonb default null, p_lease_seconds int default 900)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j media_jobs;
begin
  update media_jobs set heartbeat_at = now(), locked_until = now() + make_interval(secs => p_lease_seconds), progress = coalesce(p_progress, progress)
   where id = p_job and locked_by = p_worker and status = 'running' returning * into j;
  update agent_workers set last_seen = now() where id = p_worker;
  if j.id is null then return jsonb_build_object('lost', true); end if;
  return jsonb_build_object('lost', false, 'cancel', j.cancel_requested);
end $$;

-- Fechar: ok com resultado, ou erro (repete com espera crescente até max_attempts se retryable).
-- ingest ok: confere o SHA-256 e o tamanho lidos do R2 com os declarados; pronta (+proxy) ou falhou.
-- export ok: cria a versão nova do ativo (R2, pronta, checksum conferido pelo worker) e passa a atual.
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

revoke all on function public._media_r2(text), public._media_ceiling_ws(text), public._media_job_json(media_jobs),
  public._edit_resolve_cams(text, jsonb) from public, anon, authenticated;
revoke all on function public.media_worker_claim(text, text[], int), public.media_worker_heartbeat(text, uuid, jsonb, int),
  public.media_worker_finish(text, uuid, boolean, jsonb, text, boolean) from public, anon, authenticated;
grant execute on function public.media_worker_claim(text, text[], int), public.media_worker_heartbeat(text, uuid, jsonb, int),
  public.media_worker_finish(text, uuid, boolean, jsonb, text, boolean) to engine_worker, service_role;
revoke all on function public.media_proxy_access(text, uuid, text), public.edit_preview_sources(text, uuid, uuid, text),
  public.edit_export_request(text, uuid, uuid, text), public.edit_export_list(text, uuid, text), public.edit_export_cancel(text, uuid, text) from public, anon;
grant execute on function public.media_proxy_access(text, uuid, text), public.edit_preview_sources(text, uuid, uuid, text),
  public.edit_export_request(text, uuid, uuid, text), public.edit_export_list(text, uuid, text), public.edit_export_cancel(text, uuid, text) to authenticated;

/* Rollback (compatível, por esta ordem): flag_set('media.r2', <ws>, 'off') para todos os clientes; repor media_upload_begin,
   media_upload_target, media_upload_complete, _media_policy, _media_usage e _media_version_json como em 20261103152523_w8_media_p2.sql
   e 20261103152309_w8_media_p1.sql; drop function public.media_worker_finish(text, uuid, boolean, jsonb, text, boolean),
   public.media_worker_heartbeat(text, uuid, jsonb, int), public.media_worker_claim(text, text[], int), public.edit_export_cancel(text, uuid, text),
   public.edit_export_list(text, uuid, text), public.edit_export_request(text, uuid, uuid, text), public.edit_preview_sources(text, uuid, uuid, text),
   public._edit_resolve_cams(text, jsonb), public.media_proxy_access(text, uuid, text), public._media_job_json(media_jobs),
   public._media_ceiling_ws(text), public._media_r2(text);
   contract posterior (só sem versões R2): drop table public.media_jobs; alter table public.media_versions drop column storage_provider, ...;
   delete from feature_flag_defs where key = 'media.r2'. */
