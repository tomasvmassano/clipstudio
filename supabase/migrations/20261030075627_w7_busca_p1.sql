-- Parte 1 de 2 de 20261030100100_w7_busca.sql (aplicada em produção como w7_busca_p1).
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
