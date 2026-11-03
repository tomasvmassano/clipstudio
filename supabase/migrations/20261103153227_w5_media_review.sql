-- W5-04 · Revisão de vídeo (FR-05-03, FR-05-04 parcial; CHG-006, ADR-0043). Expand: tabelas e funções novas, por cima da
-- biblioteca de media (W8, ADR-0038). O vídeo é um ativo da biblioteca ligado ao guião, com a versão atual num link da
-- Google Drive (media_versions.source = 'link'); as etiquetas hook_N e Sxx dizem a variante e o estilo. A revisão é por
-- versão: estado, comentários com momento (ms) e decisões com motivo. Sessão individual (como a biblioteca), sem código de
-- equipa. Rollback no fim.

update capabilities set status = 'ativo' where key in ('review.approve', 'review.comment');

-- estado de revisão de cada versão (sem linha = por rever)
create table if not exists public.media_reviews (
  version_id uuid primary key references public.media_versions(id),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null references public.media_assets(id),
  status text not null check (status in ('approved', 'changes_requested', 'rejected')),
  decided_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_label text
);
create index if not exists media_reviews_ws on public.media_reviews (workspace_id, status);
alter table public.media_reviews enable row level security;
revoke all on public.media_reviews from anon, authenticated;

create table if not exists public.media_comments (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null references public.media_assets(id),
  version_id uuid not null references public.media_versions(id),
  parent_id uuid references public.media_comments(id),
  t_ms int check (t_ms is null or t_ms between 0 and 36000000),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  author_id uuid references auth.users(id) on delete set null,
  author_label text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_label text
);
create index if not exists media_comments_version on public.media_comments (version_id, t_ms nulls first, created_at);
alter table public.media_comments enable row level security;
revoke all on public.media_comments from anon, authenticated;

create table if not exists public.media_decisions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null references public.media_assets(id),
  version_id uuid not null references public.media_versions(id),
  from_status text not null,
  to_status text not null check (to_status in ('approved', 'changes_requested', 'rejected')),
  reason text check (reason is null or char_length(reason) <= 2000),
  actor_id uuid references auth.users(id) on delete set null,
  actor_label text,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create index if not exists media_decisions_version on public.media_decisions (version_id, created_at);
alter table public.media_decisions enable row level security;
revoke all on public.media_decisions from anon, authenticated;

-- comentários não se apagam nem se reescrevem (só resolver/reabrir); decisões não se alteram; o estado de uma versão aprovada não muda
create or replace function public.media_comments_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'comentarios_nao_se_apagam' using errcode = '42501'; end if;
  if (new.workspace_id, new.asset_id, new.version_id, new.parent_id, new.t_ms, new.body, new.author_id, new.author_label, new.created_at)
     is distinct from (old.workspace_id, old.asset_id, old.version_id, old.parent_id, old.t_ms, old.body, old.author_id, old.author_label, old.created_at) then
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

create or replace function public.media_reviews_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'revisao_nao_se_apaga' using errcode = '42501'; end if;
  if old.status = 'approved' then raise exception 'ja_aprovado' using errcode = '22023'; end if;
  if (new.version_id, new.workspace_id, new.asset_id) is distinct from (old.version_id, old.workspace_id, old.asset_id) then
    raise exception 'revisao_nao_se_edita' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists media_reviews_guard on public.media_reviews;
create trigger media_reviews_guard before update or delete on public.media_reviews for each row execute function public.media_reviews_guard();

-- ID do ficheiro a partir de um link da Drive (…/file/d/ID/…, …?id=ID) ou do próprio ID; null se não for da Drive
create or replace function public._drive_file_id(p text) returns text
language sql immutable set search_path = public as $$
  select coalesce(substring(btrim(p) from '^https://(?:drive|docs)\.google\.com/(?:.*/)?file/d/([A-Za-z0-9_-]{10,200})'),
                  substring(btrim(p) from '^https://drive\.google\.com/.*[?&]id=([A-Za-z0-9_-]{10,200})'),
                  case when btrim(coalesce(p, '')) ~ '^[A-Za-z0-9_-]{10,200}$' then btrim(p) end)
$$;

-- variante e estilo pelas etiquetas do ativo (hook_1 … hook_20, s14, s15 …)
create or replace function public._review_variant(p_tags text[]) returns text
language sql immutable set search_path = public as $$
  select coalesce((select t from unnest(p_tags) t where t ~ '^hook_([1-9]|1[0-9]|20)$' order by t limit 1), 'geral')
$$;
create or replace function public._review_style(p_tags text[]) returns text
language sql immutable set search_path = public as $$
  select (select upper(t) from unnest(p_tags) t where t ~ '^s[0-9]{1,3}$' order by t limit 1)
$$;

-- Ler: quem tem media.read no cliente (todos os papéis), com a biblioteca ligada. Sessão individual.
create or replace function public._review_read(p_ws text, p_token text) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.review.read', p_ws);
  return public._media_uid();
end $$;

create or replace function public._review_status(p_version uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select r.status from media_reviews r where r.version_id = p_version), 'in_review')
$$;

create or replace function public._review_comment_json(c public.media_comments) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'parent_id', c.parent_id, 't_ms', c.t_ms, 'body', c.body,
    'author', coalesce(c.author_label, 'alguém'), 'author_id', c.author_id, 'at', c.created_at,
    'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by_label)
$$;

-- Um vídeo em revisão: ativo ativo, ligado a um guião, versão atual pronta e de um link da Drive.
create or replace function public._review_item_json(a public.media_assets) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'asset_id', a.id, 'title', a.title, 'variant', public._review_variant(a.tags), 'style', public._review_style(a.tags),
    'version_id', v.id, 'version', v.version_no, 'drive_file_id', public._drive_file_id(v.external_url), 'url', v.external_url,
    'status', public._review_status(v.id),
    'decided_at', (select r.decided_at from media_reviews r where r.version_id = v.id),
    'decided_by', (select r.decided_label from media_reviews r where r.version_id = v.id),
    'open_comments', (select count(*) from media_comments c where c.version_id = v.id and c.parent_id is null and c.resolved_at is null),
    'all_comments', (select count(*) from media_comments c where c.version_id = v.id),
    'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
                'hook', case when public._review_variant(a.tags) like 'hook_%'
                             then g.hooks -> (substr(public._review_variant(a.tags), 6)::int - 1) ->> 'text' end)
              from guioes g where g.id = a.content_id))
  from media_versions v where v.id = a.current_version_id
$$;

-- Lista de vídeos a rever: filtros por estado e texto; a versão atual de cada ativo.
create or replace function public.media_review_list(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text[]; q text := nullif(btrim(p_filters->>'q'), '');
begin
  perform public._review_read(p_ws, p_token);
  st := coalesce((select array_agg(x) from jsonb_array_elements_text(p_filters->'status') x), array['in_review', 'changes_requested', 'approved', 'rejected']);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._review_item_json(a) order by g.date, g.n, public._review_variant(a.tags)), '[]')
              from media_assets a join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
              where a.workspace_id = p_ws and a.lifecycle = 'ativo' and v.state = 'pronta' and v.source = 'link'
                and public._drive_file_id(v.external_url) is not null
                and public._review_status(v.id) = any (st)
                and (q is null or g.tema ilike '%' || q || '%' or a.title ilike '%' || q || '%')),
    'counts', (select coalesce(jsonb_object_agg(s, c), '{}') from (
                 select public._review_status(v.id) s, count(*) c
                   from media_assets a join media_versions v on v.id = a.current_version_id
                  where a.workspace_id = p_ws and a.lifecycle = 'ativo' and a.content_id is not null and v.state = 'pronta'
                    and v.source = 'link' and public._drive_file_id(v.external_url) is not null
                  group by 1) z),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', p_ws, p_token), 'decide', public.ws_can('review.approve', p_ws, p_token),
                              'link', public.ws_can('media.upload', p_ws, p_token)));
end $$;

-- Um vídeo: a versão pedida (ou a atual), comentários, decisões e as outras versões.
create or replace function public.media_review_detail(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a media_assets; v media_versions; uid uuid;
begin
  uid := public._review_read(p_ws, p_token);
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo';
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from media_versions where id = coalesce(p_version, a.current_version_id) and asset_id = a.id and state = 'pronta';
  if v.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'item', public._review_item_json(a),
    'version', jsonb_build_object('id', v.id, 'version', v.version_no, 'drive_file_id', public._drive_file_id(v.external_url),
                                  'url', v.external_url, 'status', public._review_status(v.id), 'current', v.id = a.current_version_id,
                                  'decided_by', (select r.decided_label from media_reviews r where r.version_id = v.id),
                                  'decided_at', (select r.decided_at from media_reviews r where r.version_id = v.id)),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version_no, 'status', public._review_status(x.id))
                   order by x.version_no desc), '[]') from media_versions x where x.asset_id = a.id and x.state = 'pronta'),
    'comments', (select coalesce(jsonb_agg(public._review_comment_json(c) order by c.t_ms nulls first, c.created_at), '[]')
                 from media_comments c where c.version_id = v.id),
    'decisions', (select coalesce(jsonb_agg(jsonb_build_object('from', d.from_status, 'to', d.to_status, 'reason', d.reason,
                   'by', coalesce(d.actor_label, 'alguém'), 'at', d.created_at) order by d.created_at), '[]')
                  from media_decisions d where d.version_id = v.id),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', p_ws, p_token), 'decide', public.ws_can('review.approve', p_ws, p_token)),
    'me', uid);
end $$;

-- Comentar num momento (ms, opcional) da versão, ou responder a um comentário (herda o momento).
create or replace function public.media_review_comment(p_ws text, p_version uuid, p_body text, p_t_ms int default null,
                                                       p_parent uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid; c media_comments; par media_comments; t int := p_t_ms;
begin
  uid := public._review_read(p_ws, p_token);
  perform public._content_require('review.comment', p_ws, p_token, 'media.review.comment', p_version::text);
  select * into v from media_versions where id = p_version and workspace_id = p_ws and state = 'pronta';
  select * into a from media_assets where id = v.asset_id and lifecycle = 'ativo';
  if v.id is null or a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  if coalesce(btrim(p_body), '') = '' then raise exception 'comentario_vazio' using errcode = '22023'; end if;
  if char_length(p_body) > 4000 then raise exception 'comentario_longo' using errcode = '22023'; end if;
  if t is not null and (t < 0 or t > 36000000) then raise exception 'momento_invalido' using errcode = '22023'; end if;
  if p_parent is not null then
    select * into par from media_comments where id = p_parent;
    if par.id is null or par.version_id <> v.id or par.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
    t := par.t_ms;
  end if;
  insert into media_comments (workspace_id, asset_id, version_id, parent_id, t_ms, body, author_id, author_label)
  values (p_ws, a.id, v.id, p_parent, t, btrim(p_body), uid, public._media_label(uid)) returning * into c;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'media.commented', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'comment_id', c.id, 't_ms', c.t_ms));
  return public._review_comment_json(c);
end $$;

-- Resolver / reabrir: quem escreveu, ou quem decide na revisão.
create or replace function public.media_review_comment_resolve(p_ws text, p_comment uuid, p_resolved boolean default true,
                                                               p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c media_comments; uid uuid;
begin
  uid := public._review_read(p_ws, p_token);
  select * into c from media_comments where id = p_comment and workspace_id = p_ws for update;
  if c.id is null then raise exception 'comentario_nao_encontrado' using errcode = 'P0002'; end if;
  if c.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
  if not (c.author_id = uid or public.ws_can('review.approve', p_ws, p_token)) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  update media_comments set resolved_at = case when p_resolved then now() end,
         resolved_by_label = case when p_resolved then public._media_label(uid) end
   where id = c.id returning * into c;
  return public._review_comment_json(c);
end $$;

-- Decidir: aprovar, pedir alterações ou rejeitar (estes dois com motivo). Só a versão atual; aprovado é final.
create or replace function public.media_review_decide(p_ws text, p_version uuid, p_status text, p_reason text default null,
                                                      p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid; r text := nullif(btrim(coalesce(p_reason, '')), ''); cur text;
begin
  uid := public._review_read(p_ws, p_token);
  perform public._content_require('review.approve', p_ws, p_token, 'media.review.decide', p_version::text);
  if p_status not in ('approved', 'changes_requested', 'rejected') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if p_status <> 'approved' and r is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  if r is not null and char_length(r) > 2000 then raise exception 'motivo_longo' using errcode = '22023'; end if;
  select * into v from media_versions where id = p_version and workspace_id = p_ws and state = 'pronta';
  select * into a from media_assets where id = v.asset_id and lifecycle = 'ativo' for update;
  if v.id is null or a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  if a.current_version_id <> v.id then raise exception 'versao_antiga' using errcode = '22023'; end if;
  cur := public._review_status(v.id);
  if cur = 'approved' then raise exception 'ja_aprovado' using errcode = '22023'; end if;
  if cur = p_status then return public._review_item_json(a); end if;   -- repetir não duplica
  insert into media_decisions (workspace_id, asset_id, version_id, from_status, to_status, reason, actor_id, actor_label)
  values (p_ws, a.id, v.id, cur, p_status, r, uid, public._media_label(uid));
  insert into media_reviews (version_id, workspace_id, asset_id, status, decided_at, decided_by, decided_label)
  values (v.id, p_ws, a.id, p_status, now(), uid, public._media_label(uid))
  on conflict (version_id) do update set status = excluded.status, decided_at = excluded.decided_at,
    decided_by = excluded.decided_by, decided_label = excluded.decided_label;
  perform public._media_audit(p_ws, 'media.review.decided', 'media_asset', a.id::text, jsonb_build_object('status', cur),
                              jsonb_build_object('status', p_status, 'version_id', v.id, 'reason', r));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'media.decided', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'status', p_status, 'content_id', a.content_id));
  return public._review_item_json(a);
end $$;

revoke all on function public._review_read(text, text), public._review_status(uuid), public._review_comment_json(public.media_comments),
  public._review_item_json(public.media_assets) from public, anon, authenticated;
revoke all on function public.media_review_list(text, jsonb, text), public.media_review_detail(text, uuid, uuid, text),
  public.media_review_comment(text, uuid, text, int, uuid, text), public.media_review_comment_resolve(text, uuid, boolean, text),
  public.media_review_decide(text, uuid, text, text, text) from public;
grant execute on function public.media_review_list(text, jsonb, text), public.media_review_detail(text, uuid, uuid, text),
  public.media_review_comment(text, uuid, text, int, uuid, text), public.media_review_comment_resolve(text, uuid, boolean, text),
  public.media_review_decide(text, uuid, text, text, text) to authenticated;

/* Rollback (só se nada depender ainda disto):
   drop function if exists public.media_review_decide(text, uuid, text, text, text), public.media_review_comment_resolve(text, uuid, boolean, text),
     public.media_review_comment(text, uuid, text, int, uuid, text), public.media_review_detail(text, uuid, uuid, text),
     public.media_review_list(text, jsonb, text), public._review_item_json(public.media_assets), public._review_comment_json(public.media_comments),
     public._review_status(uuid), public._review_read(text, text), public._review_style(text[]), public._review_variant(text[]), public._drive_file_id(text);
   drop table if exists public.media_decisions, public.media_comments, public.media_reviews;
   drop function if exists public.media_comments_guard(), public.media_decisions_guard(), public.media_reviews_guard();
   update capabilities set status = 'W5' where key = 'review.approve'; */
