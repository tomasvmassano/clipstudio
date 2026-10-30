-- W8 · Biblioteca de media, parte 1 de 3: capacidades, flag, bucket, tabelas, guardas e políticas do storage
-- (PRD M08 FR-08-01..06; §39 ING-01; §22; AGENTS §2, §8; ADR-0038).
-- O bruto das sessões continua fora da app (Google Drive, ING-01). Esta biblioteca guarda finais, miniaturas, legendas,
-- áudio, imagens e documentos num bucket privado do Supabase Storage (decisão do Tomás para já), atrás de um adaptador
-- (src/lib/storage) para passar a Cloudflare R2 sem mudar o resto. Links externos (ex.: URL do Drive) registam-se como
-- ativo do tipo "link_externo", sem descarregar nada.
-- Expand (só aditivo): 2 capacidades novas (+1 de agência), 3 planeadas passam a ativas, 1 flag, 1 bucket, 5 tabelas
-- fechadas à API, funções novas e políticas novas em storage.objects só para o bucket `media`. Não muda nenhuma função
-- existente. Rollback no fim.

-- ───────────── capacidades e flag ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('media.read', 'Biblioteca', 'B', array['ws'], 'ativo', 'Ver a biblioteca de media e pré-visualizar'),
  ('media.manage', 'Biblioteca', 'A', array['ws'], 'ativo', 'Limpar órfãos e apagar definitivamente ativos do lixo'),
  ('media.policy.manage', 'Biblioteca', 'A', array['org'], 'ativo', 'Definir tipos, tamanho máximo, quota e retenção da biblioteca por cliente')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
-- media.upload / media.download / media.share existiam como planeadas (W5) com papéis já atribuídos: passam a ser usadas.
update capabilities set status = 'ativo', label = 'Carregar media, novas versões, editar dados e mandar para o lixo' where key = 'media.upload';
update capabilities set status = 'ativo', label = 'Descarregar media' where key = 'media.download';
update capabilities set status = 'ativo', label = 'Criar e revogar links temporários de partilha' where key = 'media.share';
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'media.read'), ('ws', 'workspace_admin', 'media.read'), ('ws', 'manager', 'media.read'),
  ('ws', 'contributor', 'media.read'), ('ws', 'reviewer', 'media.read'), ('ws', 'viewer', 'media.read'),
  ('ws', 'workspace_owner', 'media.manage'), ('ws', 'workspace_admin', 'media.manage'),
  ('org', 'agency_owner', 'media.policy.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('media.library', 'Biblioteca de media', 'Biblioteca', 'ws', 'owner',
   'Ativos finais, miniaturas, legendas, áudio, imagens e documentos por cliente, com versões, progresso e retentativa, links temporários, lixo e órfãos. O bruto das sessões fica no Google Drive (ING-01). Sem antivírus.')
on conflict do nothing;

-- ───────────── bucket privado ─────────────
-- 50 MiB por ficheiro é o limite do plano gratuito do Supabase. É o teto: o máximo por cliente nunca passa o limite do
-- bucket. Subir exige o plano certo e mudar `file_size_limit` do bucket (decisão em aberto para o Tomás, ADR-0038).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 52428800, array[
  'video/mp4', 'video/quicktime', 'video/webm',
  'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/webm',
  'image/png', 'image/jpeg', 'image/webp', 'image/gif',
  'text/vtt', 'application/x-subrip', 'text/plain',
  'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update set public = false;

-- ───────────── tabelas ─────────────
-- Ativo: uma peça lógica do cliente. kind e workspace_id nunca mudam. status é o estado na biblioteca (não é aprovação:
-- a revisão de media vive em M07/EDL-02). lifecycle: ativo → no_lixo (recuperável até purge_after) → eliminado (lápide).
create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  kind text not null check (kind in ('video', 'audio', 'imagem', 'thumbnail', 'legenda', 'documento', 'link_externo')),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  tags text[] not null default '{}' check (cardinality(tags) <= 20),
  project_id uuid references public.projects(id),
  format text check (format is null or format in ('9:16', '16:9', '1:1', '4:5', 'outro')),
  status text not null default 'em_trabalho' check (status in ('em_trabalho', 'final', 'arquivado')),
  content_id text references public.guioes(id),
  take_id uuid references public.takes(id),
  publication_id uuid references public.pub_publications(id),
  notes text check (notes is null or char_length(notes) <= 2000),
  current_version_id uuid,
  lifecycle text not null default 'ativo' check (lifecycle in ('ativo', 'no_lixo', 'eliminado')),
  trashed_at timestamptz, trashed_by uuid, trashed_label text,
  trash_reason text check (trash_reason is null or char_length(trash_reason) <= 500),
  purge_after timestamptz,
  purge_requested_at timestamptz, purge_requested_by uuid,
  purged_at timestamptz, purged_by uuid,
  created_by uuid, created_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  lock_version int not null default 1,
  check ((lifecycle = 'ativo') = (trashed_at is null)),
  check ((lifecycle = 'eliminado') = (purged_at is not null))
);
create index if not exists media_assets_ws on public.media_assets (workspace_id, lifecycle, updated_at desc);
create index if not exists media_assets_tags on public.media_assets using gin (tags);
create index if not exists media_assets_content on public.media_assets (workspace_id, content_id) where content_id is not null;

-- Versão: imutável depois de sair de "pendente". O caminho é gerado no servidor:
-- <workspace>/<asset_id>/<version_no>/<nome-sanitizado>. Link externo = versão com external_url e sem objeto.
create table if not exists public.media_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null references public.media_assets(id),
  version_no int not null check (version_no > 0),
  source text not null check (source in ('upload', 'link')),
  state text not null default 'pendente' check (state in ('pendente', 'pronta', 'falhou', 'apagada')),
  storage_bucket text,
  storage_path text unique,
  original_name text check (original_name is null or char_length(original_name) <= 255),
  size_bytes bigint check (size_bytes is null or size_bytes > 0),
  mime text,
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  checksum_verified boolean not null default false,
  checksum_verified_at timestamptz,
  external_url text check (external_url is null or (external_url ~ '^https://[^\s/]+\.[^\s/]+(/\S*)?$' and char_length(external_url) <= 2000)),
  upload_expires_at timestamptz,
  completed_at timestamptz,
  failed_reason text,
  deleted_at timestamptz,
  uploaded_by uuid, uploaded_label text,
  created_at timestamptz not null default now(),
  unique (asset_id, version_no),
  check ((source = 'upload') = (storage_path is not null and size_bytes is not null and mime is not null and sha256 is not null and external_url is null)),
  check (source = 'upload' or (external_url is not null and storage_path is null)),
  check (not checksum_verified or checksum_verified_at is not null)
);
create index if not exists media_versions_asset on public.media_versions (asset_id, version_no desc);
create index if not exists media_versions_ws_state on public.media_versions (workspace_id, state);
alter table public.media_assets drop constraint if exists media_assets_current_version_fk;
alter table public.media_assets add constraint media_assets_current_version_fk foreign key (current_version_id) references public.media_versions(id);

-- Política por cliente (FR-08-05). Nulo = valor por defeito (_media_policy).
create table if not exists public.media_policies (
  workspace_id text primary key references public.clients(id),
  allowed_mime text[],
  max_file_bytes bigint check (max_file_bytes is null or max_file_bytes > 0),
  quota_bytes bigint check (quota_bytes is null or quota_bytes > 0),
  trash_days int check (trash_days is null or trash_days between 1 and 365),
  updated_at timestamptz not null default now(),
  updated_by uuid, updated_label text
);

-- Links de partilha (FR-08-03): só o hash do token fica guardado; o token aparece uma vez a quem o cria.
create table if not exists public.media_shares (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null references public.media_assets(id),
  version_id uuid not null references public.media_versions(id),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  note text check (note is null or char_length(note) <= 200),
  open_count int not null default 0,
  last_opened_at timestamptz,
  created_by uuid not null, created_label text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz, revoked_by uuid, revoked_label text
);
create index if not exists media_shares_version on public.media_shares (version_id);

-- Autorizações de leitura de um objeto, curtas (60 s), criadas só pelas RPCs depois de verificar capacidade e auditar.
-- A política de leitura do storage exige uma destas: quem tem media.read não assina URLs à margem das RPCs.
create table if not exists public.media_access_grants (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  object_path text not null,
  user_id uuid,
  share_id uuid references public.media_shares(id),
  purpose text not null check (purpose in ('preview', 'download', 'share')),
  expires_at timestamptz not null,
  check ((user_id is null) = (share_id is not null))
);
create index if not exists media_access_grants_path on public.media_access_grants (object_path, expires_at);

alter table public.media_assets enable row level security;
alter table public.media_versions enable row level security;
alter table public.media_policies enable row level security;
alter table public.media_shares enable row level security;
alter table public.media_access_grants enable row level security;
revoke all on public.media_assets, public.media_versions, public.media_policies, public.media_shares, public.media_access_grants from anon, authenticated;

-- ───────────── guardas ─────────────
create or replace function public.media_assets_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'ativo_nao_se_apaga' using errcode = '42501', detail = 'Ativos vão para o lixo; a lápide fica.'; end if;
  if tg_op = 'UPDATE' then
    if new.workspace_id <> old.workspace_id or new.kind <> old.kind or new.created_by is distinct from old.created_by then
      raise exception 'ativo_imutavel' using errcode = '42501'; end if;
    if old.lifecycle = 'eliminado' then raise exception 'ativo_eliminado' using errcode = '22023', detail = 'Este ativo foi apagado definitivamente.'; end if;
    new.updated_at := now();
    new.lock_version := old.lock_version + 1;
  end if;
  if new.project_id is not null and not exists (select 1 from projects p where p.id = new.project_id and p.workspace_id = new.workspace_id) then
    raise exception 'campanha_de_outro_cliente' using errcode = '22023'; end if;
  if new.content_id is not null and not exists (select 1 from guioes g where g.id = new.content_id and g.client_id = new.workspace_id) then
    raise exception 'guiao_de_outro_cliente' using errcode = '22023'; end if;
  if new.take_id is not null and not exists (select 1 from takes t where t.id = new.take_id and t.workspace_id = new.workspace_id) then
    raise exception 'take_de_outro_cliente' using errcode = '22023'; end if;
  if new.publication_id is not null and not exists (select 1 from pub_publications p where p.id = new.publication_id and p.workspace_id = new.workspace_id) then
    raise exception 'publicacao_de_outro_cliente' using errcode = '22023'; end if;
  if new.current_version_id is not null and not exists (select 1 from media_versions v where v.id = new.current_version_id and v.asset_id = new.id and v.state = 'pronta') then
    raise exception 'versao_invalida' using errcode = '22023'; end if;
  return new;
end $$;
drop trigger if exists media_assets_guard on public.media_assets;
create trigger media_assets_guard before insert or update or delete on public.media_assets for each row execute function public.media_assets_guard();

-- Uma versão nunca se apaga nem muda o que é. Transições: pendente → pronta | falhou | apagada; falhou → apagada;
-- pronta → apagada (só quando o objeto já não existe). O checksum só fica verificado na passagem a pronta.
create or replace function public.media_versions_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare fixed text[] := array['id', 'workspace_id', 'asset_id', 'version_no', 'source', 'storage_bucket', 'storage_path', 'original_name',
                              'size_bytes', 'mime', 'sha256', 'external_url', 'uploaded_by', 'uploaded_label', 'created_at'];
        k text;
begin
  if tg_op = 'DELETE' then raise exception 'versao_imutavel' using errcode = '42501', detail = 'As versões ficam no histórico.'; end if;
  if tg_op = 'INSERT' then
    if new.workspace_id <> (select workspace_id from media_assets where id = new.asset_id) then
      raise exception 'versao_de_outro_cliente' using errcode = '42501'; end if;
    if new.source = 'upload' and (new.state <> 'pendente' or new.checksum_verified) then
      raise exception 'estado_inicial_invalido' using errcode = '42501', detail = 'Um upload nasce pendente.'; end if;
    if new.source = 'link' and new.state <> 'pronta' then raise exception 'estado_inicial_invalido' using errcode = '42501'; end if;
    return new;
  end if;
  foreach k in array fixed loop
    if to_jsonb(new) -> k is distinct from to_jsonb(old) -> k then
      raise exception 'versao_imutavel' using errcode = '42501', detail = format('O campo %s de uma versão não muda: carrega uma versão nova.', k);
    end if;
  end loop;
  if new.state <> old.state and not (
       (old.state = 'pendente' and new.state in ('pronta', 'falhou', 'apagada'))
    or (old.state in ('falhou', 'pronta') and new.state = 'apagada')) then
    raise exception 'transicao_invalida' using errcode = '42501', detail = format('%s → %s', old.state, new.state);
  end if;
  if old.state <> 'pendente' and (new.checksum_verified is distinct from old.checksum_verified
                                  or new.checksum_verified_at is distinct from old.checksum_verified_at
                                  or new.completed_at is distinct from old.completed_at) then
    raise exception 'versao_imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists media_versions_guard on public.media_versions;
create trigger media_versions_guard before insert or update or delete on public.media_versions for each row execute function public.media_versions_guard();

-- ───────────── auxiliares puras ─────────────
create or replace function public._media_default_mime() returns text[]
language sql immutable set search_path = public as $$
  select array['video/mp4', 'video/quicktime', 'video/webm', 'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/webm',
               'image/png', 'image/jpeg', 'image/webp', 'image/gif', 'text/vtt', 'application/x-subrip', 'text/plain', 'application/pdf',
               'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
$$;

create or replace function public._media_kind_mime_ok(p_kind text, p_mime text) returns boolean
language sql immutable set search_path = public as $$
  select case p_kind
    when 'video' then p_mime like 'video/%'
    when 'audio' then p_mime like 'audio/%'
    when 'imagem' then p_mime like 'image/%'
    when 'thumbnail' then p_mime in ('image/png', 'image/jpeg', 'image/webp')
    when 'legenda' then p_mime in ('text/vtt', 'application/x-subrip', 'text/plain')
    when 'documento' then p_mime in ('application/pdf', 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    else false end
$$;

-- Nome de ficheiro seguro para a chave do objeto: minúsculas, sem acentos, [a-z0-9._-], extensão preservada.
create or replace function public._media_safe_name(p_name text) returns text
language plpgsql immutable set search_path = public as $$
declare n text := coalesce(p_name, ''); ext text; base text;
begin
  n := lower(translate(n, 'áàâãäåçéèêëíìîïñóòôõöúùûüýÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝ', 'aaaaaaceeeeiiiinooooouuuuyAAAAAACEEEEIIIINOOOOOUUUUY'));
  n := regexp_replace(n, '^.*[/\\]', '');                               -- nunca pastas vindas do browser
  ext := substring(n from '\.([a-z0-9]{1,10})$');
  base := case when ext is null then n else left(n, char_length(n) - char_length(ext) - 1) end;
  base := regexp_replace(regexp_replace(base, '[^a-z0-9_-]+', '-', 'g'), '(^-+|-+$)', '', 'g');
  base := left(coalesce(nullif(base, ''), 'ficheiro'), 80);
  return base || coalesce('.' || ext, '');
end $$;

create or replace function public._media_tags(p jsonb) returns text[]
language plpgsql immutable set search_path = public as $$
declare out text[] := '{}'; x text; t text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'; end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'etiquetas_invalidas' using errcode = '22023'; end if;
  for x in select jsonb_array_elements_text(p) loop
    t := lower(btrim(regexp_replace(x, '^\s*#+', '')));
    if t = '' then continue; end if;
    if char_length(t) > 40 then raise exception 'etiquetas_invalidas' using errcode = '22023', detail = 'Cada etiqueta até 40 caracteres.'; end if;
    if not t = any(out) then out := out || t; end if;
  end loop;
  if cardinality(out) > 20 then raise exception 'etiquetas_invalidas' using errcode = '22023', detail = 'Até 20 etiquetas por ativo.'; end if;
  return out;
end $$;

-- Teto por ficheiro: o limite do bucket (o plano do Supabase decide; sem limite no bucket, 50 MiB).
create or replace function public._media_ceiling() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce((select file_size_limit from storage.buckets where id = 'media'), 52428800)
$$;

-- Política efetiva do cliente (FR-08-05). Quota por defeito 5 GiB e lixo 30 dias [pressupostos, ADR-0038].
create or replace function public._media_policy(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'allowed_mime', to_jsonb(coalesce(p.allowed_mime, public._media_default_mime())),
    'max_file_bytes', least(coalesce(p.max_file_bytes, public._media_ceiling()), public._media_ceiling()),
    'ceiling_bytes', public._media_ceiling(),
    'quota_bytes', coalesce(p.quota_bytes, 5368709120),
    'trash_days', coalesce(p.trash_days, 30),
    'pending_hours', 24,
    'customized', p.workspace_id is not null,
    'updated_at', p.updated_at, 'updated_label', p.updated_label)
  from (select 1) one left join media_policies p on p.workspace_id = p_ws
$$;

-- Uso real: bytes dos objetos guardados com o prefixo do cliente + reservas de uploads pendentes ainda sem objeto.
create or replace function public._media_usage(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  with o as (
    select o.name, coalesce((o.metadata->>'size')::bigint, 0) as size, v.state, v.upload_expires_at, a.lifecycle
      from storage.objects o left join media_versions v on v.storage_path = o.name left join media_assets a on a.id = v.asset_id
     where o.bucket_id = 'media' and o.name like p_ws || '/%'),
  r as (
    select coalesce(sum(v.size_bytes), 0) as reserved from media_versions v
     where v.workspace_id = p_ws and v.state = 'pendente' and v.upload_expires_at > now()
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

-- ───────────── storage.objects: só o caminho pendente do próprio, leitura só com autorização curta ─────────────
-- insert: a versão pendente deste caminho é de quem carrega, não expirou, o ativo está ativo e a pessoa tem media.upload.
-- select: (a) o próprio upload ainda pendente (o storage lê o que acabou de escrever e o servidor confere o checksum);
--         (b) versão pronta com uma autorização de 60 s criada pela RPC (pessoa com media.read, ou link de partilha válido).
--         (c) quem pode apagar o objeto (abaixo), porque o DELETE só toca no que consegue ler.
-- delete: media.manage e só órfãos (falhou / pendente expirado) ou ativos no lixo com eliminação pedida há < 15 min.
-- Sem update: as versões são imutáveis (sem upsert).
create or replace function public._media_object_can(p_op text, p_name text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid := auth.uid();
begin
  if p_name is null then return false; end if;
  select * into v from media_versions where storage_path = p_name and source = 'upload';
  if v.id is null then return false; end if;
  select * into a from media_assets where id = v.asset_id;
  if p_op = 'insert' then
    return uid is not null and v.state = 'pendente' and v.uploaded_by = uid and v.upload_expires_at > now()
       and a.lifecycle = 'ativo' and public._authorize('media.upload', v.workspace_id, uid);
  elsif p_op = 'select' then
    if uid is not null and v.state = 'pendente' and v.uploaded_by = uid and public._authorize('media.upload', v.workspace_id, uid) then
      return true;
    end if;
    -- quem limpa (media.manage) vê os objetos que pode apagar: o DELETE do Postgres e do storage só toca no que se lê
    if public._media_object_can('delete', p_name) then return true; end if;
    return v.state = 'pronta' and a.lifecycle <> 'eliminado' and exists (
      select 1 from media_access_grants g where g.object_path = p_name and g.expires_at > now()
         and ((uid is not null and g.user_id = uid and public._authorize('media.read', v.workspace_id, uid))
           or (uid is null and g.user_id is null and exists (select 1 from media_shares s where s.id = g.share_id and s.revoked_at is null and s.expires_at > now()))));
  elsif p_op = 'delete' then
    return uid is not null and public._authorize('media.manage', v.workspace_id, uid)
       and (v.state = 'falhou' or (v.state = 'pendente' and v.upload_expires_at <= now())
            or (a.lifecycle = 'no_lixo' and a.purge_requested_at > now() - interval '15 minutes'));
  end if;
  return false;
end $$;

drop policy if exists media_objects_insert on storage.objects;
create policy media_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public._media_object_can('insert', name));
drop policy if exists media_objects_select on storage.objects;
create policy media_objects_select on storage.objects for select to anon, authenticated
  using (bucket_id = 'media' and public._media_object_can('select', name));
drop policy if exists media_objects_delete on storage.objects;
create policy media_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public._media_object_can('delete', name));

revoke all on function public.media_assets_guard(), public.media_versions_guard(), public._media_default_mime(), public._media_kind_mime_ok(text, text),
  public._media_safe_name(text), public._media_tags(jsonb), public._media_ceiling(), public._media_policy(text), public._media_usage(text)
  from public, anon, authenticated;
revoke all on function public._media_object_can(text, text) from public;
grant execute on function public._media_object_can(text, text) to anon, authenticated;   -- usada nas políticas do storage

/* Rollback (compatível; nada mais depende disto):
   drop policy if exists media_objects_insert on storage.objects; drop policy if exists media_objects_select on storage.objects;
   drop policy if exists media_objects_delete on storage.objects;
   drop function public._media_object_can(text, text), public._media_usage(text), public._media_policy(text), public._media_ceiling(),
     public._media_tags(jsonb), public._media_safe_name(text), public._media_kind_mime_ok(text, text), public._media_default_mime();
   delete from role_capabilities where capability in ('media.read', 'media.manage', 'media.policy.manage');
   update capabilities set status = 'W5' where key in ('media.upload', 'media.download', 'media.share');
   delete from permission_grants where capability in ('media.read', 'media.manage', 'media.policy.manage');
   delete from capabilities where key in ('media.read', 'media.manage', 'media.policy.manage');
   delete from feature_flags where key = 'media.library'; delete from feature_flag_defs where key = 'media.library';
-- contract posterior (depois de esvaziar o bucket pelo painel ou pela API do storage e exportar o histórico):
   drop table public.media_access_grants, public.media_shares, public.media_policies; alter table public.media_assets drop constraint media_assets_current_version_fk;
   drop table public.media_versions, public.media_assets; drop function public.media_versions_guard(), public.media_assets_guard();
   delete from storage.buckets where id = 'media'; */
