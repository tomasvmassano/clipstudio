-- W10-02 · Pesquisa global: media da biblioteca, comentários da revisão de vídeos e as minhas notificações
-- (PRD FR-16-01, FR-16-05, MIG-08; ADR-0054). Expand (só aditivo): 1 função pura nova, 1 índice novo e search_global
-- refeita a partir da última definição (20261105202033_w9_guioes_eliminar.sql), com o mesmo formato de resposta e três
-- tipos novos ('media', 'comment', 'notification'). Sem capacidades nem flags novas: cada grupo usa as regras da
-- funcionalidade dona (media_library, media_review_list, inbox). Código de equipa: só o que legacy_can permite (nenhum
-- dos três). Compatível com o código em main: os grupos novos só acrescentam itens com kind novo.
-- Rollback no fim.

-- documento de pesquisa de um ativo da biblioteca (título, etiquetas e nomes originais dos ficheiros)
create or replace function public._sdoc_media(p_title text, p_tags text[], p_names text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select public._search_fold(concat_ws(' ', p_title, array_to_string(p_tags, ' '), p_names))
$$;
revoke all on function public._sdoc_media(text, text[], text) from public, anon, authenticated;

-- comentários: o LIKE '%termo%' no corpo usa um índice trigram (o resto dos grupos novos filtra primeiro pelo cliente)
do $$
declare s text := (select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm');
begin
  execute format('create index if not exists media_comments_search_trgm on public.media_comments using gin (public._search_fold(body) %I.gin_trgm_ops)', s);
end $$;
create index if not exists notifications_user_ws on public.notifications (user_id, workspace_id);

CREATE OR REPLACE FUNCTION public.search_global(p_q text, p_ws text DEFAULT NULL::text, p_limit integer DEFAULT 5, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid(); lim int := least(greatest(coalesce(p_limit, 5), 1), 20);
  q text := left(btrim(coalesce(p_q, '')), 100); fq text; words text[]; main text; pat text; tag text; num bigint; uu uuid;
  w_all text[]; w_scripts text[]; w_sources text[]; w_refs text[]; w_tasks text[]; w_team text[]; w_styles text[];
  w_media text[]; w_comments text[]; w_notif text[];
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
  -- W10 (FR-16-01): as mesmas regras de quem é dono de cada entidade.
  -- media: media.read + flag media.library (como media_library); o código de equipa não tem media.read (legacy_can).
  w_media    := array(select x from unnest(w_all) x where public.ws_can('media.read', x, p_token) and public._flag_on('media.library', x, p_token));
  -- comentários dos vídeos: como media_review_list (media.read, flag, sessão individual) e scripts.read, que a página /revisao exige
  w_comments := case when uid is null then '{}' else array(select x from unnest(w_media) x where public.ws_can('scripts.read', x, p_token)) end;
  -- notificações: só as minhas, nos clientes onde as recebo (tasks.read, como a caixa); nunca com código de equipa
  w_notif    := case when uid is null then '{}' else array(select x from unnest(w_all) x where public._authorize('tasks.read', x, uid)) end;

  -- ── sem texto: sugestões ──
  if q = '' then
    groups := groups || jsonb_build_object('kind', 'recent', 'label', 'Guiões mexidos há pouco', 'more', false, 'items',
      coalesce((select jsonb_agg(x.j order by x.u desc) from (
        select jsonb_build_object('kind', 'script', 'id', g.id, 'ws', g.client_id, 'ws_name', names->>g.client_id,
               'title', coalesce(nullif(g.tema, ''), left(g.hooks->0->>'text', 80), 'Guião ' || g.n), 'date', g.date, 'n', g.n,
               'status', g.editorial_status) j, g.updated_at u
          from guioes g where g.client_id = any (w_scripts) and g.deleted_at is null and g.editorial_status <> 'archived'
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
          select unnest(g.tags) t from guioes g where g.client_id = any (w_scripts) and g.deleted_at is null
          union all select unnest(s.tags) from ideas s where s.client_id = any (w_sources)
          union all select unnest(r.tags) from reference_items r where r.workspace_id = any (w_refs) and r.archived_at is null
          union all select unnest(m.tags) from media_assets m where m.workspace_id = any (w_media) and m.lifecycle = 'ativo') z
        where public._search_fold(t) like pat group by t order by count(*) desc, t limit 8) x), '[]'));
    g := (select jsonb_build_object('kind', 'script', 'label', 'Guiões', 'more', count(*) > lim,
                 'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
      select jsonb_build_object('kind', 'script', 'id', g.id, 'ws', g.client_id, 'ws_name', names->>g.client_id,
             'title', coalesce(nullif(g.tema, ''), left(g.hooks->0->>'text', 80), 'Guião ' || g.n), 'date', g.date, 'n', g.n,
             'status', g.editorial_status, 'tags', to_jsonb(g.tags)) j,
             row_number() over (order by (g.editorial_status = 'archived'), g.date desc, g.n) o
        from guioes g where g.client_id = any (w_scripts) and g.deleted_at is null and exists (select 1 from unnest(g.tags) t where public._search_fold(t) like pat)
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
    -- media ativa (o lixo e os eliminados ficam de fora)
    g := (select jsonb_build_object('kind', 'media', 'label', 'Biblioteca de media', 'more', count(*) > lim,
                 'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
      select jsonb_build_object('kind', 'media', 'id', a.id, 'ws', a.workspace_id, 'ws_name', names->>a.workspace_id, 'title', a.title,
             'media_kind', a.kind, 'status', a.status, 'format', a.format, 'tags', to_jsonb(a.tags), 'file_name', cv.original_name) j,
             row_number() over (order by (a.status = 'arquivado'), a.updated_at desc) o
        from media_assets a left join media_versions cv on cv.id = a.current_version_id
       where a.workspace_id = any (w_media) and a.lifecycle = 'ativo'
         and exists (select 1 from unnest(a.tags) t where public._search_fold(t) like pat)
       order by o limit lim + 1) x);
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
     where g.client_id = any (w_scripts) and g.deleted_at is null
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

  -- W10 · media da biblioteca: título, etiquetas, nome original do ficheiro (de qualquer versão) e ID. Só ativos.
  g := (select jsonb_build_object('kind', 'media', 'label', 'Biblioteca de media', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'media', 'id', a.id, 'ws', a.workspace_id, 'ws_name', names->>a.workspace_id, 'title', a.title,
           'media_kind', a.kind, 'status', a.status, 'format', a.format, 'tags', to_jsonb(a.tags), 'file_name', cv.original_name) j,
           row_number() over (order by (a.id = uu) desc, (strpos(public._search_fold(a.title), main) > 0) desc, (a.status = 'arquivado'), a.updated_at desc) o
      from media_assets a left join media_versions cv on cv.id = a.current_version_id
     where a.workspace_id = any (w_media) and a.lifecycle = 'ativo'
       and (a.id = uu or public._search_all(public._sdoc_media(a.title, a.tags,
              (select string_agg(v.original_name, ' ') from media_versions v where v.asset_id = a.id)), words))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- W10 · comentários da revisão de vídeos: só vídeos que a revisão mostra (ativo, ligado a um guião não eliminado, versão
  -- atual elegível) e versões prontas, como media_review_list/media_review_detail.
  g := (select jsonb_build_object('kind', 'comment', 'label', 'Comentários nos vídeos', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'comment', 'id', c.id, 'ws', c.workspace_id, 'ws_name', names->>c.workspace_id,
           'title', left(regexp_replace(c.body, '\s+', ' ', 'g'), 140), 'asset_id', a.id, 'asset_title', a.title, 'version', v.version_no,
           't_ms', c.t_ms, 'author', coalesce(c.author_label, 'alguém'), 'resolved', c.resolved_at is not null, 'created_at', c.created_at) j,
           row_number() over (order by (c.id = uu) desc, (c.resolved_at is null) desc, c.created_at desc) o
      from media_comments c
      join media_assets a on a.id = c.asset_id and a.workspace_id = c.workspace_id
      join media_versions v on v.id = c.version_id and v.asset_id = a.id
      join media_versions cv on cv.id = a.current_version_id
      join guioes gg on gg.id = a.content_id and gg.client_id = a.workspace_id
     where c.workspace_id = any (w_comments) and a.lifecycle = 'ativo' and gg.deleted_at is null
       and v.state = 'pronta' and public._review_eligible(cv)
       and (c.id = uu or (public._search_fold(c.body) like pat and public._search_all(public._search_fold(c.body), words)))
     order by o limit lim + 1) x);
  groups := groups || g;

  -- W10 · as minhas notificações (user_id = eu), nos clientes onde as recebo; as de um guião eliminado ficam de fora
  g := (select jsonb_build_object('kind', 'notification', 'label', 'As minhas notificações', 'more', count(*) > lim,
               'items', coalesce(jsonb_agg(x.j order by x.o) filter (where x.o <= lim), '[]')) from (
    select jsonb_build_object('kind', 'notification', 'id', n.id, 'ws', n.workspace_id, 'ws_name', names->>n.workspace_id, 'title', n.title,
           'body', left(n.body, 140), 'notif_kind', n.kind, 'entity_type', n.entity_type, 'entity_id', n.entity_id,
           'read', n.read_at is not null, 'created_at', n.created_at) j,
           row_number() over (order by (n.id = uu) desc, (n.read_at is null) desc, n.created_at desc) o
      from notifications n
     where uid is not null and n.user_id = uid and n.workspace_id = any (w_notif)
       and not (n.entity_type = 'content' and exists (select 1 from guioes x where x.id = n.entity_id and x.deleted_at is not null))
       and (n.id = uu or public._search_all(public._search_fold(concat_ws(' ', n.title, n.body)), words))
     order by o limit lim + 1) x);
  groups := groups || g;

  return jsonb_build_object('q', q, 'mode', 'text', 'workspaces', cardinality(w_all),
                            'groups', (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(groups) x where jsonb_array_length(x->'items') > 0));
end $function$;


revoke all on function public.search_global(text, text, integer, text) from public;
grant execute on function public.search_global(text, text, integer, text) to anon, authenticated;
-- anon só passa com código de equipa válido (_search_ws recusa sem sessão nem código).

/* Rollback (compatível; o browser ignora tipos que não conhece e deixa de os receber):
   1. Repor search_global a partir de 20261105202033_w9_guioes_eliminar.sql (o bloco CREATE OR REPLACE FUNCTION
      public.search_global ... end $function$;), tal como está, e voltar a correr o revoke/grant acima.
   2. drop index if exists public.media_comments_search_trgm, public.notifications_user_ws;
      drop function if exists public._sdoc_media(text, text[], text);
*/
