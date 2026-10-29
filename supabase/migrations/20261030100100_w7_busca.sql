-- W7 · Pesquisa global com controlo de acesso, paleta de comandos com ações rápidas e operações em lote nos guiões
-- (PRD FR-16-01, FR-16-02, FR-16-05, FR-01-05, FR-17-07, QA-12; ADR-0035).
-- Expand (só aditivo): extensão pg_trgm (schema extensions), 2 flags, 1 tabela fechada à API (idempotência dos lotes),
-- índices trigram por expressão e funções novas. Não muda nenhuma função existente: as operações em lote chamam
-- content_meta_set, content_transition e content_reschedule tal como estão (cada uma volta a verificar a permissão e audita).
-- Sem capacidades novas: cada grupo da pesquisa e cada ação em lote usa a capacidade que já protege essa entidade/ação.
-- Rollback no fim.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

-- ───────────── flags ─────────────
-- Uma flag por cliente (scope ws) para a pesquisa: a pesquisa só olha para os clientes onde a flag está ligada para a
-- pessoa; a paleta aparece (também no espaço da agência) quando está ligada em pelo menos um. Assim a equipa de um
-- cliente (sem pertença à agência) pode recebê-la cliente a cliente, o que uma flag de agência (scope org) não permite.
insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('busca.global', 'Pesquisa global e ações rápidas', 'Pesquisa', 'ws', 'owner',
   'Ctrl/Cmd+K: pesquisa em guiões, fontes, referências, tarefas, campanhas, pessoas e estilos dos clientes a que a pessoa tem acesso, e ações rápidas para criar.'),
  ('guioes.bulk', 'Operações em lote nos guiões', 'Guiões', 'ws', 'owner',
   'Selecionar vários guiões e mudar responsável, campanha, etiquetas, aprovar, reagendar ou exportar CSV, com pré-visualização do impacto.')
on conflict do nothing;

-- ───────────── normalização e documentos de pesquisa ─────────────
-- Minúsculas e sem acentos (PT-PT), imutável para poder ser indexada.
create or replace function public._search_fold(p text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select translate(lower(coalesce(p, '')), 'áàâãäåéèêëíìîïóòôõöúùûüçñ', 'aaaaaaeeeeiiiiooooouuuucn')
$$;

create or replace function public._sdoc_guiao(p_id text, p_tema text, p_corpo text, p_cta text, p_hooks jsonb, p_tags text[], p_formato text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select public._search_fold(concat_ws(' ', p_id, p_tema, p_formato, array_to_string(p_tags, ' '), p_cta,
    (select string_agg(h->>'text', ' ') from jsonb_array_elements(case when jsonb_typeof(p_hooks) = 'array' then p_hooks else '[]'::jsonb end) h),
    p_corpo))
$$;
create or replace function public._sdoc_source(p_titulo text, p_resumo text, p_fonte text, p_autor text, p_url text, p_tags text[]) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select public._search_fold(concat_ws(' ', p_titulo, p_fonte, p_autor, array_to_string(p_tags, ' '), p_url, p_resumo))
$$;
create or replace function public._sdoc_reference(p_titulo text, p_hook text, p_creator text, p_formato text, p_estilo text, p_notas text, p_tags text[]) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select public._search_fold(concat_ws(' ', p_titulo, p_hook, p_creator, p_formato, p_estilo, array_to_string(p_tags, ' '), p_notas))
$$;
create or replace function public._sdoc_task(p_title text, p_description text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select public._search_fold(concat_ws(' ', p_title, p_description))
$$;

-- Índices trigram (aceleram o LIKE '%termo%'). O opclass vem do schema onde a pg_trgm está instalada.
do $$
declare s text := (select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm');
begin
  execute format('create index if not exists guioes_search_trgm on public.guioes using gin (public._sdoc_guiao(id, tema, corpo, cta, hooks, tags, formato) %I.gin_trgm_ops)', s);
  execute format('create index if not exists ideas_search_trgm on public.ideas using gin (public._sdoc_source(titulo, resumo, fonte, autor, fonte_url, tags) %I.gin_trgm_ops)', s);
  execute format('create index if not exists reference_items_search_trgm on public.reference_items using gin (public._sdoc_reference(titulo, hook, creator, formato, estilo, notas, tags) %I.gin_trgm_ops)', s);
  execute format('create index if not exists tasks_search_trgm on public.tasks using gin (public._sdoc_task(title, description) %I.gin_trgm_ops)', s);
end $$;

-- Todas as palavras aparecem no documento (o índice trata da mais longa; isto confirma as restantes).
create or replace function public._search_all(p_doc text, p_words text[]) returns boolean
language sql immutable parallel safe set search_path = pg_catalog as $$
  select coalesce(bool_and(strpos(p_doc, w) > 0), true) from unnest(p_words) w
$$;
create or replace function public._like_escape(p text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select replace(replace(replace(p, '\', '\\'), '%', '\%'), '_', '\_')
$$;

-- Clientes onde esta pessoa pode pesquisar agora: acesso ativo (ou dono da agência), cliente ativo e flag ligada.
-- Código de equipa: só o cliente do código. p_ws restringe a um cliente (nunca alarga).
create or replace function public._search_ws(p_ws text, p_token text) returns table (ws text, name text)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); lws text;
begin
  if uid is null then
    lws := public.legacy_ws(p_token);
    if lws is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
    return query select c.id, c.name from clients c
      where c.id = lws and (p_ws is null or c.id = p_ws) and coalesce(c.status, 'active') = 'active' and public._flag_on('busca.global', c.id, p_token);
    return;
  end if;
  return query select c.id, c.name from clients c
    where coalesce(c.status, 'active') = 'active' and (p_ws is null or c.id = p_ws)
      and (exists (select 1 from workspace_access a where a.workspace_id = c.id and a.user_id = uid and a.status = 'active'
                   and (a.expires_at is null or a.expires_at > now()))
           or exists (select 1 from agency_memberships m where m.user_id = uid and m.organization_id = c.organization_id
                      and m.agency_role = 'agency_owner' and m.status = 'active'))
      and public._flag_on('busca.global', c.id, null)
    order by c.name;
end $$;

-- ───────────── paleta: onde está disponível e que ações rápidas mostrar ─────────────
create or replace function public.search_scope(p_ws text default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cur boolean;
begin
  if auth.uid() is null and public.legacy_ws(p_token) is null then return jsonb_build_object('enabled', '[]'::jsonb, 'actions', null); end if;
  cur := p_ws is not null and exists (select 1 from public._search_ws(p_ws, p_token));
  return jsonb_build_object(
    'enabled', coalesce((select jsonb_agg(jsonb_build_object('id', s.ws, 'name', s.name) order by s.name) from public._search_ws(null, p_token) s), '[]'),
    -- só para o cliente aberto; cada RPC de criação volta a verificar a capacidade
    'actions', case when cur then jsonb_build_object(
        'source', public.ws_can('sources.create', p_ws, p_token),
        'script', public.ws_can('scripts.create', p_ws, p_token),
        'project', public.ws_can('projects.manage', p_ws, p_token),
        'task', public.ws_can('tasks.manage', p_ws, p_token)) end);
end $$;

-- ───────────── pesquisa global ─────────────
-- p_q: texto livre (todas as palavras), "#etiqueta" (prefixo da etiqueta) ou um ID (guião, tarefa, número da fonte ou
-- referência). Vazio: sugestões (guiões mexidos há pouco e as minhas tarefas abertas). Cada grupo só olha para os
-- clientes onde a pessoa tem a capacidade de leitura dessa entidade (FR-16-05): nada de outro cliente entra no resultado.
create or replace function public.search_global(p_q text, p_ws text default null, p_limit integer default 5, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); lim int := least(greatest(coalesce(p_limit, 5), 1), 20);
  q text := left(btrim(coalesce(p_q, '')), 100); fq text; words text[]; main text; pat text; tag text; num bigint; uu uuid;
  w_all text[]; w_scripts text[]; w_sources text[]; w_refs text[]; w_tasks text[]; w_team text[]; w_styles text[];
  names jsonb; groups jsonb := '[]'; g jsonb;
begin
  select coalesce(array_agg(s.ws), '{}'), coalesce(jsonb_object_agg(s.ws, s.name), '{}') into w_all, names from public._search_ws(p_ws, p_token) s;
  if cardinality(w_all) = 0 then
    if p_ws is not null and not (public.ws_can('scripts.read', p_ws, p_token) or public.ws_can('team.read', p_ws, p_token)) then
      raise exception 'sem_permissao' using errcode = '42501'; end if;
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A pesquisa global ainda não está ligada para ti.';
  end if;
  w_scripts := array(select x from unnest(w_all) x where public.ws_can('scripts.read', x, p_token));
  w_sources := array(select x from unnest(w_all) x where public.ws_can('sources.read', x, p_token));
  w_refs    := array(select x from unnest(w_all) x where public.ws_can('references.read', x, p_token));
  w_tasks   := array(select x from unnest(w_all) x where public.ws_can('tasks.read', x, p_token));
  w_team    := case when uid is null then '{}' else array(select x from unnest(w_all) x where public._authorize('team.read', x, uid)) end;
  w_styles  := array(select x from unnest(w_all) x where public.ws_can('scripts.read', x, p_token) or public.ws_can('styles.manage', x, p_token));

  -- ── sem texto: sugestões ──
  if q = '' then
    groups := groups || jsonb_build_object('kind', 'recent', 'label', 'Guiões mexidos há pouco', 'more', false, 'items',
      coalesce((select jsonb_agg(x.j order by x.u desc) from (
        select jsonb_build_object('kind', 'script', 'id', g.id, 'ws', g.client_id, 'ws_name', names->>g.client_id,
               'title', coalesce(nullif(g.tema, ''), left(g.hooks->0->>'text', 80), 'Guião ' || g.n), 'date', g.date, 'n', g.n,
               'status', g.editorial_status) j, g.updated_at u
          from guioes g where g.client_id = any (w_scripts) and g.editorial_status <> 'archived'
         order by g.updated_at desc nulls last limit lim) x), '[]'));
    if uid is not null then
      groups := groups || jsonb_build_object('kind', 'my_tasks', 'label', 'As minhas tarefas abertas', 'more', false, 'items',
        coalesce((select jsonb_agg(x.j order by x.o) from (
          select jsonb_build_object('kind', 'task', 'id', t.id, 'ws', t.workspace_id, 'ws_name', names->>t.workspace_id, 'title', t.title,
                 'status', t.status, 'due_at', t.due_at) j, row_number() over (order by t.due_at nulls last, t.created_at) o
            from tasks t where t.workspace_id = any (w_tasks) and t.assignee_id = uid and t.status in ('todo','doing','blocked')
           order by t.due_at nulls last, t.created_at limit lim) x), '[]'));
    end if;
    return jsonb_build_object('q', q, 'mode', 'suggestions', 'workspaces', cardinality(w_all), 'groups', groups);
  end if;

  -- ── por etiqueta ──
  if left(q, 1) = '#' and char_length(q) > 1 and position(' ' in q) = 0 then
    tag := public._search_fold(substr(q, 2));
    pat := public._like_escape(tag) || '%';
    groups := groups || jsonb_build_object('kind', 'tag', 'label', 'Etiquetas', 'more', false, 'items',
      coalesce((select jsonb_agg(jsonb_build_object('kind', 'tag', 'id', x.t, 'title', '#' || x.t, 'count', x.c) order by x.c desc, x.t) from (
        select t, count(*) c from (
          select unnest(g.tags) t from guioes g where g.client_id = any (w_scripts)
          union all select unnest(s.tags) from ideas s where s.client_id = any (w_sources)
          union all select unnest(r.tags) from reference_items r where r.workspace_id = any (w_refs) and r.archived_at is null) z
        where public._search_fold(t) like pat group by t order by count(*) desc, t limit 8) x), '[]'));
    g := (select jsonb_build_object('kind', 'script', 'label', 'Guiões', 'more', count(*) > lim,
                 'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
      select jsonb_build_object('kind', 'script', 'id', g.id, 'ws', g.client_id, 'ws_name', names->>g.client_id,
             'title', coalesce(nullif(g.tema, ''), left(g.hooks->0->>'text', 80), 'Guião ' || g.n), 'date', g.date, 'n', g.n,
             'status', g.editorial_status, 'tags', to_jsonb(g.tags)) j,
             row_number() over (order by (g.editorial_status = 'archived'), g.date desc, g.n) o
        from guioes g where g.client_id = any (w_scripts) and exists (select 1 from unnest(g.tags) t where public._search_fold(t) like pat)
        order by (g.editorial_status = 'archived'), g.date desc, g.n limit lim + 1) x);
    groups := groups || g;
    g := (select jsonb_build_object('kind', 'source', 'label', 'Fontes', 'more', count(*) > lim,
                 'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
      select jsonb_build_object('kind', 'source', 'id', s.id, 'ws', s.client_id, 'ws_name', names->>s.client_id, 'title', coalesce(s.titulo, 'Fonte ' || s.id),
             'status', s.status, 'source_kind', s.kind, 'tags', to_jsonb(s.tags)) j, row_number() over (order by s.created_at desc) o
        from ideas s where s.client_id = any (w_sources) and exists (select 1 from unnest(s.tags) t where public._search_fold(t) like pat)
        order by s.created_at desc limit lim + 1) x);
    groups := groups || g;
    g := (select jsonb_build_object('kind', 'reference', 'label', 'Referências', 'more', count(*) > lim,
                 'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
      select jsonb_build_object('kind', 'reference', 'id', r.id, 'ws', r.workspace_id, 'ws_name', names->>r.workspace_id,
             'title', coalesce(nullif(r.titulo, ''), nullif(r.hook, ''), r.url), 'creator', r.creator, 'tags', to_jsonb(r.tags)) j,
             row_number() over (order by r.created_at desc) o
        from reference_items r where r.workspace_id = any (w_refs) and r.archived_at is null
         and exists (select 1 from unnest(r.tags) t where public._search_fold(t) like pat)
        order by r.created_at desc limit lim + 1) x);
    groups := groups || g;
    return jsonb_build_object('q', q, 'mode', 'tag', 'workspaces', cardinality(w_all),
                              'groups', (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(groups) x where jsonb_array_length(x->'items') > 0));
  end if;

  if char_length(q) < 2 then
    return jsonb_build_object('q', q, 'mode', 'short', 'workspaces', cardinality(w_all), 'groups', '[]'::jsonb);
  end if;

  fq := public._search_fold(q);
  words := array(select w from regexp_split_to_table(fq, '\s+') w where w <> '' limit 6);
  main := (select w from unnest(words) w order by char_length(w) desc limit 1);
  pat := '%' || public._like_escape(main) || '%';
  if q ~ '^#?[0-9]{1,12}$' then num := ltrim(q, '#')::bigint; end if;
  if q ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then uu := q::uuid; end if;

  -- guiões: título (tema), hooks, corpo, CTA, etiquetas, formato e ID
  g := (select jsonb_build_object('kind', 'script', 'label', 'Guiões', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'script', 'id', g.id, 'ws', g.client_id, 'ws_name', names->>g.client_id,
           'title', coalesce(nullif(g.tema, ''), left(g.hooks->0->>'text', 80), 'Guião ' || g.n), 'date', g.date, 'n', g.n,
           'status', g.editorial_status, 'tags', to_jsonb(g.tags)) j,
           row_number() over (order by (lower(g.id) = lower(q)) desc, (public._search_fold(g.tema) like public._like_escape(main) || '%') desc,
                              (strpos(public._search_fold(g.tema), main) > 0) desc, (g.editorial_status = 'archived'), g.date desc, g.n) o
      from guioes g
     where g.client_id = any (w_scripts)
       and (lower(g.id) = lower(q)
            or (public._sdoc_guiao(g.id, g.tema, g.corpo, g.cta, g.hooks, g.tags, g.formato) like pat
                and public._search_all(public._sdoc_guiao(g.id, g.tema, g.corpo, g.cta, g.hooks, g.tags, g.formato), words)))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- fontes (e pedidos do talento)
  g := (select jsonb_build_object('kind', 'source', 'label', 'Fontes', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'source', 'id', s.id, 'ws', s.client_id, 'ws_name', names->>s.client_id, 'title', coalesce(s.titulo, 'Fonte ' || s.id),
           'status', s.status, 'source_kind', s.kind, 'tags', to_jsonb(s.tags)) j,
           row_number() over (order by (s.id = num) desc, (strpos(public._search_fold(s.titulo), main) > 0) desc, s.created_at desc) o
      from ideas s
     where s.client_id = any (w_sources)
       and (s.id = num or (public._sdoc_source(s.titulo, s.resumo, s.fonte, s.autor, s.fonte_url, s.tags) like pat
                           and public._search_all(public._sdoc_source(s.titulo, s.resumo, s.fonte, s.autor, s.fonte_url, s.tags), words)))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- referências (arquivadas ficam de fora)
  g := (select jsonb_build_object('kind', 'reference', 'label', 'Referências', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'reference', 'id', r.id, 'ws', r.workspace_id, 'ws_name', names->>r.workspace_id,
           'title', coalesce(nullif(r.titulo, ''), nullif(r.hook, ''), r.url), 'creator', r.creator, 'tags', to_jsonb(r.tags)) j,
           row_number() over (order by (r.id = num) desc, (strpos(public._search_fold(coalesce(r.titulo, r.hook)), main) > 0) desc, r.favorito desc, r.created_at desc) o
      from reference_items r
     where r.workspace_id = any (w_refs) and r.archived_at is null
       and (r.id = num or (public._sdoc_reference(r.titulo, r.hook, r.creator, r.formato, r.estilo, r.notas, r.tags) like pat
                           and public._search_all(public._sdoc_reference(r.titulo, r.hook, r.creator, r.formato, r.estilo, r.notas, r.tags), words)))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- tarefas
  g := (select jsonb_build_object('kind', 'task', 'label', 'Tarefas', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'task', 'id', t.id, 'ws', t.workspace_id, 'ws_name', names->>t.workspace_id, 'title', t.title,
           'status', t.status, 'due_at', t.due_at) j,
           row_number() over (order by (t.id = uu) desc, (t.status in ('todo','doing','blocked')) desc, (strpos(public._search_fold(t.title), main) > 0) desc,
                              t.due_at nulls last, t.created_at desc) o
      from tasks t
     where t.workspace_id = any (w_tasks)
       and (t.id = uu or (public._sdoc_task(t.title, t.description) like pat and public._search_all(public._sdoc_task(t.title, t.description), words)))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- campanhas e séries (poucas por cliente: sem índice)
  g := (select jsonb_build_object('kind', 'project', 'label', 'Campanhas', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'project', 'id', p.id, 'ws', p.workspace_id, 'ws_name', names->>p.workspace_id, 'title', p.name,
           'project_kind', p.kind, 'status', p.status) j,
           row_number() over (order by (p.status = 'ativa') desc, (public._search_fold(p.name) like public._like_escape(main) || '%') desc, lower(p.name)) o
      from projects p
     where p.workspace_id = any (w_scripts) and (p.id = uu or public._search_all(public._search_fold(p.name), words))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- pessoas da equipa de cada cliente (só com sessão: quem usa o código de equipa não vê a equipa)
  g := (select jsonb_build_object('kind', 'person', 'label', 'Pessoas', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'person', 'id', a.user_id, 'ws', a.workspace_id, 'ws_name', names->>a.workspace_id,
           'title', coalesce(nullif(p.display_name, ''), u.email), 'email', u.email, 'role', a.workspace_role, 'job_title', a.job_title,
           'affiliation', a.affiliation_type) j,
           row_number() over (order by lower(coalesce(nullif(p.display_name, ''), u.email)), a.workspace_id) o
      from workspace_access a join auth.users u on u.id = a.user_id left join profiles p on p.user_id = a.user_id
     where a.workspace_id = any (w_team) and a.status = 'active' and (a.expires_at is null or a.expires_at > now())
       and public._search_all(public._search_fold(concat_ws(' ', p.display_name, u.email, a.job_title)), words)
     order by o limit lim + 1) x);
  groups := groups || g;

  -- estilos de edição (nome da versão atual e chave)
  g := (select jsonb_build_object('kind', 'style', 'label', 'Estilos', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'style', 'id', e.key, 'ws', e.workspace_id, 'ws_name', names->>e.workspace_id, 'title', v.name,
           'status', e.status, 'version', e.current_version) j,
           row_number() over (order by (e.status = 'ativo') desc, lower(v.name)) o
      from edit_styles e join edit_style_versions v on v.workspace_id = e.workspace_id and v.key = e.key and v.version = e.current_version
     where e.workspace_id = any (w_styles) and public._search_all(public._search_fold(concat_ws(' ', e.key, v.name, v.notes)), words)
     order by o limit lim + 1) x);
  groups := groups || g;

  return jsonb_build_object('q', q, 'mode', 'text', 'workspaces', cardinality(w_all),
                            'groups', (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(groups) x where jsonb_array_length(x->'items') > 0));
end $$;

-- ───────────── operações em lote nos guiões (FR-17-07) ─────────────
-- Uma linha por lote confirmado: a chave (gerada pelo browser quando abre a confirmação) torna o pedido idempotente. Repetir
-- o mesmo pedido devolve o resultado guardado sem voltar a aplicar nada.
create table if not exists public.content_bulk_ops (
  id uuid primary key,
  workspace_id text not null references public.clients(id),
  action text not null check (action in ('owner', 'project', 'tags', 'approve', 'reschedule')),
  args jsonb not null default '{}',
  ids text[] not null check (cardinality(ids) between 1 and 200),
  actor_user_id uuid,
  actor_kind text not null,
  actor_label text,
  results jsonb,
  summary jsonb,
  created_at timestamptz not null default now()
);
create index if not exists content_bulk_ops_ws on public.content_bulk_ops (workspace_id, created_at desc);
alter table public.content_bulk_ops enable row level security;
revoke all on public.content_bulk_ops from anon, authenticated;   -- só pelas RPCs

create or replace function public._bulk_snapshot(g guioes) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('owner_id', g.owner_id, 'owner', (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = g.owner_id),
    'project_id', g.project_id, 'project', (select name from projects where id = g.project_id), 'tags', to_jsonb(g.tags),
    'editorial_status', g.editorial_status, 'date', g.date, 'n', g.n)
$$;

-- p_preview: corre cada item a sério e desfaz no fim (mesmas validações e permissões, nada fica gravado), para mostrar o
-- impacto antes de confirmar. Cada item é independente: o resultado diz, item a item, o que mudou ou porque falhou.
create or replace function public.content_bulk(p_ws text, p_ids text[], p_action text, p_args jsonb, p_key uuid, p_preview boolean default false,
                                              p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a jsonb := public._content_actor(p_token); cap text; v_ids text[]; cid text; g guioes; n guioes; prev content_bulk_ops;
  args jsonb := coalesce(p_args, '{}'); res jsonb := '[]'; item jsonb; bef jsonb; aft jsonb; tg text[]; mode text; dt date;
  st text; msg text; det text; n_ok int := 0; n_fail int := 0; n_changed int := 0; inserted boolean;
begin
  cap := case p_action when 'owner' then 'scripts.edit' when 'project' then 'scripts.edit' when 'tags' then 'scripts.edit'
                       when 'approve' then 'scripts.approve' when 'reschedule' then 'calendar.schedule' end;
  if cap is null then raise exception 'acao_invalida' using errcode = '22023', detail = 'Ação em lote desconhecida.'; end if;
  perform public._content_require(cap, p_ws, p_token, 'script.bulk.' || p_action, null);
  if not public._flag_on('guioes.bulk', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'As operações em lote ainda não estão ligadas para ti.'; end if;
  v_ids := array(select x from unnest(p_ids) with ordinality u(x, o) where x is not null group by x order by min(o));
  if coalesce(cardinality(v_ids), 0) = 0 or cardinality(v_ids) > 200 then
    raise exception 'selecao_invalida' using errcode = '22023', detail = 'Escolhe entre 1 e 200 guiões.'; end if;

  -- argumentos
  if p_action = 'owner' and not (args ? 'owner_id') then raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Falta o responsável.'; end if;
  if p_action = 'project' and not (args ? 'project_id') then raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Falta a campanha.'; end if;
  if p_action = 'tags' then
    mode := coalesce(args->>'mode', 'add');
    if mode not in ('add', 'remove', 'replace') or jsonb_typeof(args->'tags') is distinct from 'array' then
      raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Etiquetas: modo add, remove ou replace e uma lista.'; end if;
    tg := array(select distinct lower(btrim(x)) from jsonb_array_elements_text(args->'tags') x where btrim(x) <> '');
    if mode <> 'replace' and coalesce(cardinality(tg), 0) = 0 then
      raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Escreve pelo menos uma etiqueta.'; end if;
  end if;
  if p_action = 'reschedule' then
    begin dt := (args->>'date')::date; exception when others then dt := null; end;
    if dt is null then raise exception 'data_obrigatoria' using errcode = '22023', detail = 'Escolhe a nova data.'; end if;
  end if;

  -- idempotência (só para o lote confirmado)
  if not p_preview then
    if p_key is null then raise exception 'chave_obrigatoria' using errcode = '22023', detail = 'Pedido sem chave de idempotência.'; end if;
    insert into content_bulk_ops (id, workspace_id, action, args, ids, actor_user_id, actor_kind, actor_label)
    values (p_key, p_ws, p_action, args, v_ids, (a->>'uid')::uuid, a->>'kind', a->>'label')
    on conflict (id) do nothing;
    get diagnostics inserted = row_count;
    if not inserted then
      select * into prev from content_bulk_ops where id = p_key;
      if prev.workspace_id <> p_ws or prev.action <> p_action or prev.ids <> v_ids or prev.args <> args
         or prev.actor_user_id is distinct from (a->>'uid')::uuid or prev.actor_kind <> a->>'kind' then
        raise exception 'chave_reutilizada' using errcode = '22023', detail = 'Esta confirmação já foi usada para outro pedido. Abre a pré-visualização outra vez.'; end if;
      return jsonb_build_object('replayed', true, 'preview', false, 'key', p_key, 'results', prev.results, 'summary', prev.summary);
    end if;
  end if;

  foreach cid in array v_ids loop
    bef := null; aft := null; item := null;
    begin
      select * into g from guioes where id = cid and client_id = p_ws for update;
      if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;   -- mesmo erro se for de outro cliente
      bef := public._bulk_snapshot(g);
      if p_action = 'owner' then
        n := case when g.owner_id is not distinct from nullif(args->>'owner_id', '')::uuid then g
                  else public.content_meta_set(g.id, jsonb_build_object('owner_id', args->'owner_id'), p_token) end;
      elsif p_action = 'project' then
        n := case when g.project_id is not distinct from nullif(args->>'project_id', '')::uuid then g
                  else public.content_meta_set(g.id, jsonb_build_object('project_id', args->'project_id'), p_token) end;
      elsif p_action = 'tags' then
        n := public.content_meta_set(g.id, jsonb_build_object('tags', to_jsonb(case mode
               when 'add' then array(select distinct x from unnest(g.tags || tg) x)
               when 'remove' then array(select x from unnest(g.tags) x where not x = any (tg))
               else tg end)), p_token);
      elsif p_action = 'approve' then
        n := case when g.editorial_status = 'approved' then g else public.content_transition(g.id, 'approved', null, null, p_token) end;
      else
        n := jsonb_populate_record(null::guioes, public.content_reschedule(g.id, dt, null, p_token));
      end if;
      aft := public._bulk_snapshot(n);
      item := jsonb_build_object('id', cid, 'ok', true, 'changed', bef is distinct from aft, 'before', bef, 'after', aft);
      if p_preview then raise exception 'previa' using errcode = 'PT200'; end if;   -- desfaz este item
    exception
      when sqlstate 'PT200' then null;
      when others then
        get stacked diagnostics st = returned_sqlstate, msg = message_text, det = pg_exception_detail;
        item := jsonb_build_object('id', cid, 'ok', false, 'changed', false, 'before', bef, 'code', st, 'error', msg, 'detail', nullif(det, ''));
    end;
    res := res || jsonb_build_array(item);
    if (item->>'ok')::boolean then n_ok := n_ok + 1; if (item->>'changed')::boolean then n_changed := n_changed + 1; end if;
    else n_fail := n_fail + 1; end if;
  end loop;

  if not p_preview then
    update content_bulk_ops set results = res, summary = jsonb_build_object('total', cardinality(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail)
     where id = p_key;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.bulk', 'content_bulk', p_key::text,
            jsonb_build_object('action', p_action, 'args', args, 'ids', to_jsonb(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail,
                               'failed_ids', (select coalesce(jsonb_agg(x->'id'), '[]') from jsonb_array_elements(res) x where not (x->>'ok')::boolean)));
  end if;
  return jsonb_build_object('replayed', false, 'preview', p_preview, 'key', p_key, 'results', res,
                            'summary', jsonb_build_object('total', cardinality(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail));
end $$;

-- Exportar os guiões escolhidos (CSV montado no browser). Só os do cliente; os outros contam como em falta. Auditado.
create or replace function public.content_bulk_export(p_ws text, p_ids text[], p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); ids text[]; rows jsonb;
begin
  perform public._content_require('scripts.export', p_ws, p_token, 'script.bulk.export', null);
  perform public._content_require('scripts.read', p_ws, p_token, 'script.bulk.export', null);
  if not public._flag_on('guioes.bulk', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'As operações em lote ainda não estão ligadas para ti.'; end if;
  ids := array(select distinct x from unnest(p_ids) x where x is not null);
  if coalesce(cardinality(ids), 0) = 0 or cardinality(ids) > 500 then
    raise exception 'selecao_invalida' using errcode = '22023', detail = 'Escolhe entre 1 e 500 guiões.'; end if;
  rows := (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'date', g.date, 'n', g.n, 'tema', g.tema, 'formato', g.formato,
              'editorial_status', g.editorial_status, 'production_status', g.production_status,
              'campanha', (select name from projects where id = g.project_id),
              'responsavel', (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = g.owner_id),
              'tags', to_jsonb(g.tags), 'platforms', to_jsonb(g.platforms),
              'hooks', (select coalesce(jsonb_agg(h->>'text'), '[]') from jsonb_array_elements(case when jsonb_typeof(g.hooks) = 'array' then g.hooks else '[]'::jsonb end) h),
              'corpo', g.corpo, 'cta', g.cta) order by g.date, g.n), '[]')
           from guioes g where g.client_id = p_ws and g.id = any (ids));
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.exported', 'content_bulk', null,
          jsonb_build_object('format', 'csv', 'count', jsonb_array_length(rows), 'ids', (select jsonb_agg(x->'id') from jsonb_array_elements(rows) x)));
  return jsonb_build_object('rows', rows, 'missing', cardinality(ids) - jsonb_array_length(rows));
end $$;

revoke all on function public._search_fold(text), public._sdoc_guiao(text, text, text, text, jsonb, text[], text), public._sdoc_source(text, text, text, text, text, text[]),
  public._sdoc_reference(text, text, text, text, text, text, text[]), public._sdoc_task(text, text), public._search_all(text, text[]), public._like_escape(text),
  public._search_ws(text, text), public._bulk_snapshot(guioes) from public, anon, authenticated;
revoke all on function public.search_scope(text, text), public.search_global(text, text, integer, text),
  public.content_bulk(text, text[], text, jsonb, uuid, boolean, text), public.content_bulk_export(text, text[], text) from public;
grant execute on function public.search_scope(text, text), public.search_global(text, text, integer, text),
  public.content_bulk(text, text[], text, jsonb, uuid, boolean, text), public.content_bulk_export(text, text[], text) to anon, authenticated;
-- anon só passa com código de equipa válido (_content_actor / _search_ws recusam sem sessão nem código).

/* Rollback (compatível): drop function public.content_bulk_export(text, text[], text), public.content_bulk(text, text[], text, jsonb, uuid, boolean, text),
   public.search_global(text, text, integer, text), public.search_scope(text, text), public._search_ws(text, text), public._bulk_snapshot(guioes),
   public._like_escape(text), public._search_all(text, text[]);
   drop index if exists guioes_search_trgm, ideas_search_trgm, reference_items_search_trgm, tasks_search_trgm;
   drop function public._sdoc_task(text, text), public._sdoc_reference(text, text, text, text, text, text, text[]),
     public._sdoc_source(text, text, text, text, text, text[]), public._sdoc_guiao(text, text, text, text, jsonb, text[], text), public._search_fold(text);
   delete from feature_flags where key in ('busca.global', 'guioes.bulk'); delete from feature_flag_defs where key in ('busca.global', 'guioes.bulk');
-- contract posterior: drop table public.content_bulk_ops; (a extensão pg_trgm pode ficar) */
