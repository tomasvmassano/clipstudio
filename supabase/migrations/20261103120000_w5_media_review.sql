-- W5-04 · Revisão de vídeo por link da Google Drive (FR-05-03, FR-05-04 parcial; CHG-006). Expand: tabelas e funções novas.
-- O vídeo fica na Drive da agência; a app guarda o ID do ficheiro, a variante (hook, estilo) e a versão, e regista
-- comentários com momento (ms) e decisões com motivo. Tudo por workspace e só por RPC. Rollback no fim.

update capabilities set status = 'ativo' where key in ('media.upload', 'review.approve', 'review.comment');

create table if not exists public.content_media (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  variant text not null check (variant ~ '^(geral|hook_([1-9]|1[0-9]|20))$'),
  style text check (style is null or style ~ '^[A-Z][A-Z0-9_]{1,15}$'),
  version int not null check (version >= 1),
  source text not null default 'drive' check (source in ('drive')),
  drive_file_id text not null check (drive_file_id ~ '^[A-Za-z0-9_-]{10,200}$'),
  file_name text check (file_name is null or char_length(file_name) <= 200),
  duration_s numeric(7,2) check (duration_s is null or duration_s between 0 and 36000),
  review_status text not null default 'in_review' check (review_status in ('in_review', 'approved', 'changes_requested', 'rejected')),
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user', 'legacy_code', 'system')),
  created_label text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_label text,
  unique (content_id, variant, version)
);
create index if not exists content_media_ws on public.content_media (workspace_id, review_status, created_at desc);
create index if not exists content_media_content on public.content_media (content_id, variant, version desc);
alter table public.content_media enable row level security;
revoke all on public.content_media from anon, authenticated;

create table if not exists public.media_comments (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  media_id uuid not null references public.content_media(id) on delete restrict,
  parent_id uuid references public.media_comments(id),
  t_ms int check (t_ms is null or t_ms between 0 and 36000000),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  author_id uuid references auth.users(id) on delete set null,
  author_kind text not null check (author_kind in ('user', 'legacy_code')),
  author_label text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_label text
);
create index if not exists media_comments_media on public.media_comments (media_id, t_ms nulls first, created_at);
alter table public.media_comments enable row level security;
revoke all on public.media_comments from anon, authenticated;

create table if not exists public.media_decisions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  media_id uuid not null references public.content_media(id) on delete restrict,
  from_status text not null,
  to_status text not null check (to_status in ('approved', 'changes_requested', 'rejected')),
  reason text check (reason is null or char_length(reason) <= 2000),
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  actor_label text,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create index if not exists media_decisions_media on public.media_decisions (media_id, created_at);
alter table public.media_decisions enable row level security;
revoke all on public.media_decisions from anon, authenticated;

-- media: só o estado de revisão muda; nada se apaga. Comentários e decisões não se reescrevem.
create or replace function public.content_media_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'media_nao_se_apaga' using errcode = '42501'; end if;
  if (new.workspace_id, new.content_id, new.variant, new.style, new.version, new.source, new.drive_file_id, new.file_name, new.duration_s,
      new.created_by, new.created_kind, new.created_label, new.created_at)
     is distinct from (old.workspace_id, old.content_id, old.variant, old.style, old.version, old.source, old.drive_file_id, old.file_name, old.duration_s,
      old.created_by, old.created_kind, old.created_label, old.created_at) then
    raise exception 'media_nao_se_edita' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists content_media_guard on public.content_media;
create trigger content_media_guard before update or delete on public.content_media for each row execute function public.content_media_guard();

create or replace function public.media_comments_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'comentarios_nao_se_apagam' using errcode = '42501'; end if;
  if (new.workspace_id, new.media_id, new.parent_id, new.t_ms, new.body, new.author_id, new.author_kind, new.author_label, new.created_at)
     is distinct from (old.workspace_id, old.media_id, old.parent_id, old.t_ms, old.body, old.author_id, old.author_kind, old.author_label, old.created_at) then
    raise exception 'comentarios_nao_se_editam' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists media_comments_guard on public.media_comments;
create trigger media_comments_guard before update or delete on public.media_comments for each row execute function public.media_comments_guard();

create or replace function public.media_decisions_guard() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'decisoes_nao_se_alteram' using errcode = '42501'; end $$;
drop trigger if exists media_decisions_guard on public.media_decisions;
create trigger media_decisions_guard before update or delete on public.media_decisions for each row execute function public.media_decisions_guard();

-- código de equipa do Numeiro: igual ao de 20261029162938, mais review.approve (já aprova guiões; passa a decidir vídeos)
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','references.read','tasks.read','calendar.read',
                            'analytics.read','agents.read','agents.rehearse','review.comment','review.approve']);
$$;

-- ID do ficheiro a partir de um link da Drive (…/file/d/ID/…, …?id=ID) ou do próprio ID
create or replace function public._drive_file_id(p text) returns text
language sql immutable set search_path = public as $$
  select coalesce(substring(btrim(p) from '/file/d/([A-Za-z0-9_-]{10,200})'),
                  substring(btrim(p) from '[?&]id=([A-Za-z0-9_-]{10,200})'),
                  case when btrim(p) ~ '^[A-Za-z0-9_-]{10,200}$' then btrim(p) end)
$$;

create or replace function public._media_json(m public.content_media) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', m.id, 'content_id', m.content_id, 'variant', m.variant, 'style', m.style, 'version', m.version,
    'drive_file_id', m.drive_file_id, 'file_name', m.file_name, 'duration_s', m.duration_s, 'review_status', m.review_status,
    'created_at', m.created_at, 'created_by', m.created_label, 'decided_at', m.decided_at, 'decided_by', m.decided_label,
    'latest', not exists (select 1 from content_media x where x.content_id = m.content_id and x.variant = m.variant and x.version > m.version),
    'open_comments', (select count(*) from media_comments c where c.media_id = m.id and c.parent_id is null and c.resolved_at is null),
    'all_comments', (select count(*) from media_comments c where c.media_id = m.id))
$$;

create or replace function public._media_comment_json(c public.media_comments) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', c.id, 'parent_id', c.parent_id, 't_ms', c.t_ms, 'body', c.body,
    'author', coalesce(c.author_label, 'alguém'), 'author_id', c.author_id, 'author_kind', c.author_kind, 'at', c.created_at,
    'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by_label)
$$;

-- Registar um vídeo (link da Drive) para um guião e uma variante. Nova versão se já houver; repetir o mesmo ficheiro não duplica.
create or replace function public.media_link_add(p_content text, p_variant text, p_drive text, p_style text default null,
                                                 p_file_name text default null, p_duration numeric default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); fid text := public._drive_file_id(p_drive); m content_media; v int; hk int;
begin
  select * into g from guioes where id = p_content;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('media.upload', g.client_id, p_token, 'media.link', g.id);
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  if fid is null then raise exception 'link_drive_invalido' using errcode = '22023'; end if;
  if coalesce(p_variant, '') !~ '^(geral|hook_([1-9]|1[0-9]|20))$' then raise exception 'variante_invalida' using errcode = '22023'; end if;
  if p_variant like 'hook_%' then
    hk := substr(p_variant, 6)::int;
    if hk > greatest(jsonb_array_length(coalesce(g.hooks, '[]')), 1) then raise exception 'variante_invalida' using errcode = '22023'; end if;
  end if;
  if p_style is not null and p_style !~ '^[A-Z][A-Z0-9_]{1,15}$' then raise exception 'estilo_invalido' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('media:' || g.id || ':' || p_variant));
  select * into m from content_media where content_id = g.id and variant = p_variant order by version desc limit 1;
  if m.id is not null and m.drive_file_id = fid then return public._media_json(m); end if;   -- idempotente
  v := coalesce(m.version, 0) + 1;
  insert into content_media (workspace_id, content_id, variant, style, version, drive_file_id, file_name, duration_s, created_by, created_kind, created_label)
  values (g.client_id, g.id, p_variant, p_style, v, fid, nullif(left(btrim(coalesce(p_file_name, '')), 200), ''), p_duration,
          (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into m;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'media.linked', 'content', g.id, jsonb_build_object('media_id', m.id, 'variant', m.variant, 'version', m.version, 'source', 'drive'));
  return public._media_json(m);
end $$;

-- Lista de vídeos a rever (FR-05-01 alargado a vídeo): filtros por estado, guião e texto; só a versão mais recente por variante.
create or replace function public.media_review_list(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text[]; q text := nullif(btrim(p_filters->>'q'), ''); cid text := nullif(p_filters->>'content_id', '');
begin
  if not public.ws_can('scripts.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  st := coalesce((select array_agg(x) from jsonb_array_elements_text(p_filters->'status') x), array['in_review', 'changes_requested', 'approved', 'rejected']);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(jsonb_build_object('media', public._media_json(m), 'guiao',
                 jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
                   'hook', case when m.variant like 'hook_%' then g.hooks -> (substr(m.variant, 6)::int - 1) ->> 'text' end))
               order by g.date, g.n, m.variant), '[]')
              from content_media m join guioes g on g.id = m.content_id
              where m.workspace_id = p_ws and m.review_status = any (st)
                and not exists (select 1 from content_media x where x.content_id = m.content_id and x.variant = m.variant and x.version > m.version)
                and (cid is null or m.content_id = cid)
                and (q is null or g.tema ilike '%' || q || '%' or coalesce(m.file_name, '') ilike '%' || q || '%')),
    'counts', (select coalesce(jsonb_object_agg(s, c), '{}') from (
                 select m.review_status s, count(*) c from content_media m
                  where m.workspace_id = p_ws
                    and not exists (select 1 from content_media x where x.content_id = m.content_id and x.variant = m.variant and x.version > m.version)
                  group by 1) z),
    'can', jsonb_build_object('link', public.ws_can('media.upload', p_ws, p_token), 'comment', public.ws_can('review.comment', p_ws, p_token),
                              'decide', public.ws_can('review.approve', p_ws, p_token)));
end $$;

-- Um vídeo: comentários, decisões e as outras versões da mesma variante.
create or replace function public.media_detail(p_media uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m content_media; a jsonb := public._content_actor(p_token);
begin
  select * into m from content_media where id = p_media;
  if m.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  if not public.ws_can('scripts.read', m.workspace_id, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object('media', public._media_json(m),
    'comments', (select coalesce(jsonb_agg(public._media_comment_json(c) order by c.t_ms nulls first, c.created_at), '[]') from media_comments c where c.media_id = m.id),
    'decisions', (select coalesce(jsonb_agg(jsonb_build_object('from', d.from_status, 'to', d.to_status, 'reason', d.reason, 'by', coalesce(d.actor_label, 'alguém'), 'at', d.created_at)
                   order by d.created_at), '[]') from media_decisions d where d.media_id = m.id),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version, 'review_status', x.review_status, 'created_at', x.created_at) order by x.version desc), '[]')
                 from content_media x where x.content_id = m.content_id and x.variant = m.variant),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', m.workspace_id, p_token),
                              'decide', public.ws_can('review.approve', m.workspace_id, p_token)),
    'me', a->>'uid');
end $$;

-- Comentar num momento do vídeo (ms, opcional) ou responder a um comentário.
create or replace function public.media_comment_add(p_media uuid, p_body text, p_t_ms int default null, p_parent uuid default null,
                                                    p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m content_media; a jsonb := public._content_actor(p_token); c media_comments; par media_comments; t int := p_t_ms;
begin
  select * into m from content_media where id = p_media;
  if m.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('review.comment', m.workspace_id, p_token, 'media.comment', m.id::text);
  if coalesce(btrim(p_body), '') = '' then raise exception 'comentario_vazio' using errcode = '22023'; end if;
  if char_length(p_body) > 4000 then raise exception 'comentario_longo' using errcode = '22023'; end if;
  if t is not null and (t < 0 or (m.duration_s is not null and t > ceil(m.duration_s * 1000) + 1000)) then
    raise exception 'momento_invalido' using errcode = '22023';
  end if;
  if p_parent is not null then
    select * into par from media_comments where id = p_parent;
    if par.id is null or par.media_id <> m.id or par.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
    t := par.t_ms;
  end if;
  insert into media_comments (workspace_id, media_id, parent_id, t_ms, body, author_id, author_kind, author_label)
  values (m.workspace_id, m.id, p_parent, t, btrim(p_body), (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into c;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (m.workspace_id, 'media.commented', 'content', m.content_id, jsonb_build_object('media_id', m.id, 'comment_id', c.id, 't_ms', c.t_ms));
  return public._media_comment_json(c);
end $$;

-- Resolver / reabrir: quem escreveu, ou quem decide na revisão.
create or replace function public.media_comment_resolve(p_comment uuid, p_resolved boolean default true, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c media_comments; a jsonb := public._content_actor(p_token);
begin
  select * into c from media_comments where id = p_comment for update;
  if c.id is null then raise exception 'comentario_nao_encontrado' using errcode = 'P0002'; end if;
  if not public.ws_can('scripts.read', c.workspace_id, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if c.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
  if not ((c.author_id is not null and c.author_id = (a->>'uid')::uuid) or public.ws_can('review.approve', c.workspace_id, p_token)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update media_comments set resolved_at = case when p_resolved then now() end, resolved_by_label = case when p_resolved then a->>'label' end
   where id = c.id returning * into c;
  return public._media_comment_json(c);
end $$;

-- Decidir um vídeo: aprovar, pedir alterações ou rejeitar (estes dois com motivo). Só a versão mais recente; aprovado é final.
create or replace function public.media_decide(p_media uuid, p_status text, p_reason text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m content_media; a jsonb := public._content_actor(p_token); r text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  select * into m from content_media where id = p_media for update;
  if m.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('review.approve', m.workspace_id, p_token, 'media.decide', m.id::text);
  if p_status not in ('approved', 'changes_requested', 'rejected') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if p_status <> 'approved' and r is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  if r is not null and char_length(r) > 2000 then raise exception 'motivo_longo' using errcode = '22023'; end if;
  if exists (select 1 from content_media x where x.content_id = m.content_id and x.variant = m.variant and x.version > m.version) then
    raise exception 'versao_antiga' using errcode = '22023';
  end if;
  if m.review_status = 'approved' then raise exception 'ja_aprovado' using errcode = '22023'; end if;
  if m.review_status = p_status then return public._media_json(m); end if;   -- repetir não duplica
  insert into media_decisions (workspace_id, media_id, from_status, to_status, reason, actor_id, actor_kind, actor_label)
  values (m.workspace_id, m.id, m.review_status, p_status, r, (a->>'uid')::uuid, a->>'kind', a->>'label');
  update content_media set review_status = p_status, decided_at = now(), decided_label = a->>'label' where id = m.id returning * into m;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (m.workspace_id, 'media.decided', 'content', m.content_id, jsonb_build_object('media_id', m.id, 'status', p_status, 'variant', m.variant, 'version', m.version));
  return public._media_json(m);
end $$;

/* Rollback (só se nada depender ainda disto):
   drop function if exists public.media_decide(uuid, text, text, text), public.media_comment_resolve(uuid, boolean, text),
     public.media_comment_add(uuid, text, int, uuid, text), public.media_detail(uuid, text), public.media_review_list(text, jsonb, text),
     public.media_link_add(text, text, text, text, text, numeric, text), public._media_comment_json(public.media_comments),
     public._media_json(public.content_media), public._drive_file_id(text);
   drop table if exists public.media_decisions, public.media_comments, public.content_media;
   drop function if exists public.content_media_guard(), public.media_comments_guard(), public.media_decisions_guard();
   repor legacy_can de 20261029162938 (sem review.approve);
   update capabilities set status = 'W5' where key in ('media.upload', 'review.approve'); */
