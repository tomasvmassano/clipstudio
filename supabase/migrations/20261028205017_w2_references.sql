-- W2-04 Referências (PRD M07 FR-07-01/02/03/05/06, §7; AGENTS §2.1, §2.5, §8). Isoladas por cliente (decisão do produto, ADR-0001).
-- reference_items = biblioteca curada (link manual ou reel recolhido pelo scraper). Os reels continuam a ser dados de
-- desempenho; uma referência só aponta para eles. Métricas mostram-se apenas quando vêm do scraper, com data de recolha.
-- Rollback: bloco no fim.

create table public.reference_items (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  url text,
  url_normalized text,
  reel_id text references public.reels(id) on delete set null,
  platform text,
  creator text,
  titulo text not null,
  hook text,
  formato text,
  estilo text,
  narrativa text,
  duracao_s integer check (duracao_s is null or duracao_s between 1 and 7200),
  idioma text,
  tags text[] not null default '{}',
  colecoes text[] not null default '{}',
  notas text,
  favorito boolean not null default false,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user','legacy_code','engine')),
  created_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (url is not null or reel_id is not null)
);
create unique index reference_items_ws_url on public.reference_items (workspace_id, url_normalized) where url_normalized is not null;
create unique index reference_items_ws_reel on public.reference_items (workspace_id, reel_id) where reel_id is not null;
create index reference_items_ws_created on public.reference_items (workspace_id, created_at desc);

create table public.reference_links (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  reference_id bigint not null references public.reference_items(id) on delete restrict,
  content_id text references public.guioes(id) on delete restrict,
  source_id bigint references public.ideas(id) on delete restrict,
  added_by uuid references auth.users(id) on delete set null,
  added_kind text not null check (added_kind in ('user','legacy_code','engine')),
  created_at timestamptz not null default now(),
  check ((content_id is null) <> (source_id is null))
);
create unique index reference_links_content on public.reference_links (reference_id, content_id) where content_id is not null;
create unique index reference_links_source on public.reference_links (reference_id, source_id) where source_id is not null;

-- Pertença: a referência, o guião/fonte e o reel têm de ser do mesmo cliente.
create or replace function public.reference_items_before_write() returns trigger language plpgsql set search_path = public as $$
begin
  new.url_normalized := public.normalize_url(new.url);
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  if new.reel_id is not null and not exists (
       select 1 from reels r join accounts a on a.id = r.account_id where r.id = new.reel_id and a.client_id = new.workspace_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger reference_items_before_write before insert or update on public.reference_items for each row execute function public.reference_items_before_write();

create or replace function public.reference_links_same_ws() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select workspace_id from reference_items where id = new.reference_id)
     or (new.content_id is not null and new.workspace_id is distinct from (select client_id from guioes where id = new.content_id))
     or (new.source_id is not null and new.workspace_id is distinct from (select client_id from ideas where id = new.source_id)) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger reference_links_ws before insert on public.reference_links for each row execute function public.reference_links_same_ws();

alter table public.reference_items enable row level security;
alter table public.reference_links enable row level security;
revoke all on public.reference_items, public.reference_links from anon, authenticated;
grant select on public.reference_items, public.reference_links to authenticated;
create policy reference_items_select on public.reference_items for select to authenticated using (public.authorize('references.read', workspace_id));
create policy reference_links_select on public.reference_links for select to authenticated using (public.authorize('references.read', workspace_id));

update public.capabilities set status = 'ativo' where key in ('references.read','references.manage');

-- O código de equipa do Numeiro passa a ler referências (sem gerir).
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','references.read',
                            'analytics.read','agents.read','agents.rehearse']);
$$;

-- ───────────── leitura ─────────────
create or replace function public._reference_row(x reference_items) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(x) || jsonb_build_object(
    'metrics', (select jsonb_build_object('views', r.views, 'likes', r.likes, 'comments', r.comments, 'outlier', r.outlier,
                                          'duration', r.duration, 'collected_at', r.updated_at, 'source', 'scraper')
                from reels r where r.id = x.reel_id),
    'analysis', (select jsonb_build_object('tese', sa.tese, 'gatilho', sa.gatilho, 'estrutura', sa.estrutura, 'porque_viraliza', sa.porque_viraliza,
                                           'formato', coalesce(sa.formato_norm, sa.formato), 'analyzed_at', sa.analyzed_at)
                 from script_analysis sa where sa.reel_id = x.reel_id),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('content_id', l.content_id, 'source_id', l.source_id,
                     'label', coalesce(case when g.id is not null then to_char(g.date,'DD/MM') || ' #' || g.n || ' ' || coalesce(g.tema,'') end, s.titulo)) order by l.created_at), '[]')
              from reference_links l left join guioes g on g.id = l.content_id left join ideas s on s.id = l.source_id where l.reference_id = x.id));
$$;

create or replace function public.references_list(p_ws text, p_q text default null, p_tag text default null, p_colecao text default null,
                                                  p_favoritos boolean default false, p_archived boolean default false, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('references.read', p_ws, p_token, 'reference.list', null);
  return (select coalesce(jsonb_agg(public._reference_row(x) order by x.favorito desc, x.created_at desc), '[]') from reference_items x
          where x.workspace_id = p_ws
            and (case when p_archived then x.archived_at is not null else x.archived_at is null end)
            and (not p_favoritos or x.favorito)
            and (p_tag is null or p_tag = any (x.tags))
            and (p_colecao is null or p_colecao = any (x.colecoes))
            and (p_q is null or x.titulo ilike '%' || p_q || '%' or x.hook ilike '%' || p_q || '%' or x.creator ilike '%' || p_q || '%'
                 or x.notas ilike '%' || p_q || '%' or x.formato ilike '%' || p_q || '%'));
end $$;

-- Descobrir: reels dos criadores de referência deste cliente que ainda não estão na biblioteca.
create or replace function public.references_discover(p_ws text, p_account text default null, p_limit integer default 60, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('references.read', p_ws, p_token, 'reference.discover', null);
  return jsonb_build_object(
    'creators', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'handle', a.handle, 'platform', a.platform,
                   'reels', (select count(*) from reels r where r.account_id = a.id)) order by a.handle), '[]')
                 from accounts a where a.client_id = p_ws and a.role = 'reference' and a.active),
    'reels', (select coalesce(jsonb_agg(z order by (z->>'outlier')::real desc nulls last), '[]') from (
       select jsonb_build_object('id', r.id, 'url', r.url, 'platform', r.platform, 'creator', a.handle, 'hook', nullif(r.hook,''),
              'caption', nullif(left(r.caption, 280), ''), 'views', r.views, 'likes', r.likes, 'comments', r.comments, 'outlier', r.outlier,
              'duration', r.duration, 'collected_at', r.updated_at,
              'analysis', (select jsonb_build_object('tese', sa.tese, 'porque_viraliza', sa.porque_viraliza, 'formato', coalesce(sa.formato_norm, sa.formato))
                           from script_analysis sa where sa.reel_id = r.id)) z
         from reels r join accounts a on a.id = r.account_id
        where a.client_id = p_ws and a.role = 'reference' and (p_account is null or a.id = p_account)
          and not exists (select 1 from reference_items x where x.workspace_id = p_ws and x.reel_id = r.id)
        order by r.outlier desc nulls last limit least(greatest(p_limit, 1), 200)) q));
end $$;

-- ───────────── escrita ─────────────
create or replace function public.reference_create(p_ws text, p_fields jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); x reference_items; dup bigint; u text := nullif(btrim(p_fields->>'url'), '');
        rid text := nullif(p_fields->>'reel_id', ''); r reels; sa script_analysis; acc accounts;
begin
  perform public._content_require('references.manage', p_ws, p_token, 'reference.create', null);
  if rid is not null then
    select * into r from reels where id = rid;
    select * into acc from accounts where id = r.account_id;
    if r.id is null or acc.client_id is distinct from p_ws then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select * into sa from script_analysis where reel_id = rid;
    u := coalesce(u, r.url);
    if exists (select 1 from reference_items where workspace_id = p_ws and reel_id = rid) then
      raise exception 'duplicado:%', (select id from reference_items where workspace_id = p_ws and reel_id = rid) using errcode = 'PT409';
    end if;
  end if;
  if u is not null and u !~* '^https?://[^\s/$.?#].[^\s]*$' then raise exception 'url_invalido' using errcode = '22023'; end if;
  if u is null then raise exception 'url_obrigatorio' using errcode = '22023'; end if;
  select id into dup from reference_items where workspace_id = p_ws and url_normalized = public.normalize_url(u) limit 1;
  if dup is not null then raise exception 'duplicado:%', dup using errcode = 'PT409'; end if;
  insert into reference_items (workspace_id, url, reel_id, platform, creator, titulo, hook, formato, estilo, narrativa, duracao_s, idioma, tags, colecoes,
                               notas, created_by, created_kind, created_label)
  values (p_ws, u, rid,
          coalesce(nullif(p_fields->>'platform',''), r.platform, case when u ~* 'instagram\.com' then 'instagram' when u ~* 'tiktok\.com' then 'tiktok'
                                                                    when u ~* 'youtu' then 'youtube' end),
          coalesce(nullif(p_fields->>'creator',''), acc.handle),
          coalesce(nullif(btrim(p_fields->>'titulo'),''), nullif(r.hook,''), nullif(left(r.caption, 120),''), u),
          coalesce(nullif(p_fields->>'hook',''), nullif(r.hook,'')),
          coalesce(nullif(p_fields->>'formato',''), sa.formato_norm, sa.formato),
          nullif(p_fields->>'estilo',''),
          coalesce(nullif(p_fields->>'narrativa',''), sa.estrutura),
          coalesce(nullif(p_fields->>'duracao_s','')::integer, round(r.duration)::integer),
          coalesce(nullif(p_fields->>'idioma',''), sa.language),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'tags','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'colecoes','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          nullif(p_fields->>'notas',''), (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into x;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('url', x.url, 'reel_id', x.reel_id));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('reel_id', x.reel_id, 'actor_kind', a->>'kind'));
  return public._reference_row(x);
end $$;

create or replace function public.reference_update(p_id bigint, p_patch jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); x reference_items; k text; before jsonb;
begin
  select * into x from reference_items where id = p_id for update;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('references.manage', x.workspace_id, p_token, 'reference.update', x.id::text);
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('titulo','hook','formato','estilo','narrativa','duracao_s','idioma','tags','colecoes','notas','favorito','creator','archived') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
  end loop;
  if p_patch ? 'titulo' and coalesce(btrim(p_patch->>'titulo'),'') = '' then raise exception 'titulo_obrigatorio' using errcode = '22023'; end if;
  before := jsonb_build_object('titulo', x.titulo, 'tags', x.tags, 'colecoes', x.colecoes, 'favorito', x.favorito, 'archived', x.archived_at is not null);
  update reference_items set
    titulo = coalesce(nullif(btrim(p_patch->>'titulo'),''), titulo),
    hook = case when p_patch ? 'hook' then nullif(p_patch->>'hook','') else hook end,
    formato = case when p_patch ? 'formato' then nullif(p_patch->>'formato','') else formato end,
    estilo = case when p_patch ? 'estilo' then nullif(p_patch->>'estilo','') else estilo end,
    narrativa = case when p_patch ? 'narrativa' then nullif(p_patch->>'narrativa','') else narrativa end,
    duracao_s = case when p_patch ? 'duracao_s' then nullif(p_patch->>'duracao_s','')::integer else duracao_s end,
    idioma = case when p_patch ? 'idioma' then nullif(p_patch->>'idioma','') else idioma end,
    creator = case when p_patch ? 'creator' then nullif(p_patch->>'creator','') else creator end,
    notas = case when p_patch ? 'notas' then nullif(p_patch->>'notas','') else notas end,
    tags = case when p_patch ? 'tags' then coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(p_patch->'tags') t where btrim(t) <> ''), '{}') else tags end,
    colecoes = case when p_patch ? 'colecoes' then coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(p_patch->'colecoes') t where btrim(t) <> ''), '{}') else colecoes end,
    favorito = coalesce((p_patch->>'favorito')::boolean, favorito),
    archived_at = case when p_patch ? 'archived' then (case when (p_patch->>'archived')::boolean then now() end) else archived_at end
  where id = p_id returning * into x;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', x.workspace_id, 'reference.update', 'reference', x.id::text, before, p_patch);
  return public._reference_row(x);
end $$;

-- Ligar referência a guião (scripts.edit) ou a fonte (references.manage). Desligar remove a linha, auditado.
create or replace function public.reference_link(p_reference bigint, p_content text default null, p_source bigint default null,
                                                 p_link boolean default true, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); x reference_items; ws text;
begin
  select * into x from reference_items where id = p_reference;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  if (p_content is null) = (p_source is null) then raise exception 'alvo_invalido' using errcode = '22023'; end if;
  if p_content is not null then
    select client_id into ws from guioes where id = p_content;
    if ws is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
    perform public._content_require('scripts.edit', ws, p_token, 'reference.link', p_content);
  else
    select client_id into ws from ideas where id = p_source;
    if ws is null then raise exception 'fonte_nao_encontrada' using errcode = 'P0002'; end if;
    perform public._content_require('references.manage', ws, p_token, 'reference.link', p_source::text);
  end if;
  perform public._content_require('references.read', x.workspace_id, p_token, 'reference.link', x.id::text);
  if ws <> x.workspace_id then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_link then
    insert into reference_links (workspace_id, reference_id, content_id, source_id, added_by, added_kind)
    values (ws, x.id, p_content, p_source, (a->>'uid')::uuid, a->>'kind') on conflict do nothing;
  else
    delete from reference_links where reference_id = x.id and content_id is not distinct from p_content and source_id is not distinct from p_source;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', ws, case when p_link then 'reference.linked' else 'reference.unlinked' end,
          'reference', x.id::text, jsonb_build_object('content_id', p_content, 'source_id', p_source));
  select * into x from reference_items where id = p_reference;
  return public._reference_row(x);
end $$;

-- O contexto do guião passa a incluir as referências ligadas.
create or replace function public.content_context(p_content text, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g guioes;
begin
  select * into g from guioes where id = p_content;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'content.context', g.id);
  return jsonb_build_object(
    'brief', (select to_jsonb(b) from content_briefs b where b.id = g.brief_id),
    'brief_versions', (select count(*) from content_briefs where content_id = g.id),
    'approved_brief_id', (select v.brief_id from content_versions v where v.id = g.approved_version_id),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo, 'kind', s.kind, 'fonte_tipo', s.fonte_tipo,
                       'fonte', s.fonte, 'fonte_url', s.fonte_url, 'status', s.status) order by cs.created_at), '[]')
                from content_sources cs join ideas s on s.id = cs.source_id where cs.content_id = g.id),
    'references', case when public.ws_can('references.read', g.client_id, p_token) then
                  (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'titulo', x.titulo, 'creator', x.creator, 'url', x.url, 'formato', x.formato)
                          order by l.created_at), '[]')
                   from reference_links l join reference_items x on x.id = l.reference_id where l.content_id = g.id)
                  else '[]'::jsonb end);
end $$;

revoke all on function public._reference_row(reference_items), public.reference_items_before_write(), public.reference_links_same_ws()
  from public, anon, authenticated;
revoke all on function public.references_list(text,text,text,text,boolean,boolean,text), public.references_discover(text,text,integer,text),
  public.reference_create(text,jsonb,text), public.reference_update(bigint,jsonb,text), public.reference_link(bigint,text,bigint,boolean,text)
  from public;
grant execute on function public.references_list(text,text,text,text,boolean,boolean,text), public.references_discover(text,text,integer,text),
  public.reference_create(text,jsonb,text), public.reference_update(bigint,jsonb,text), public.reference_link(bigint,text,bigint,boolean,text)
  to anon, authenticated;

/* Rollback:
drop function references_list, references_discover, reference_create, reference_update, reference_link, _reference_row,
  reference_items_before_write, reference_links_same_ws;
drop table reference_links, reference_items;
-- reaplicar content_context e legacy_can de 20261028202656_w2_sources_briefs_requests.
update capabilities set status = 'W2' where key in ('references.read','references.manage');
*/
