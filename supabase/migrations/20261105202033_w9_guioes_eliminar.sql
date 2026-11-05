-- W9-01 · Eliminar guiões arquivados (PRD FR-02-01, R-09; AGENTS §2.6, §5; ADR-0051).
-- Eliminar = lápide (soft-delete com recuperação controlada, R-09): o guião sai de todas as listas, pesquisas, calendário,
-- exportações e ações; as versões e transições ficam (são imutáveis e são a prova das aprovações, AGENTS §2.6), mas deixam de
-- ser legíveis pela API. Só um guião arquivado, sem tarefas abertas, publicações por cancelar, publicações feitas nem ativos
-- na biblioteca, com confirmação explícita (o ID do guião) e sessão individual. Capacidade nova `scripts.purge` (só
-- workspace_owner e o dono da agência). Durante 30 dias [pressuposto] quem tem `scripts.purge` pode recuperá-lo (volta a
-- arquivado); depois não.
-- Expand (só aditivo para o código do main): colunas novas nulas, uma capacidade, um gatilho que só atua em linhas eliminadas
-- (não existem até haver este código), políticas que só escondem linhas eliminadas, funções novas e quatro funções
-- existentes com um filtro `deleted_at is null` a mais. Rollback no fim.

-- ───────────── capacidade ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('scripts.purge', 'Guiões', 'A', array['ws'], 'ativo', 'Eliminar guiões arquivados (com confirmação; recuperáveis 30 dias)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes, risk = excluded.risk;
insert into role_capabilities (scope, role, capability) values ('ws', 'workspace_owner', 'scripts.purge') on conflict do nothing;

-- ───────────── esquema ─────────────
alter table public.guioes
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists deleted_label text,
  add column if not exists deleted_reason text;
alter table public.guioes drop constraint if exists guioes_deleted_ok;
alter table public.guioes add constraint guioes_deleted_ok
  check ((deleted_at is null and deleted_by is null and deleted_reason is null)
         or (deleted_at is not null and editorial_status = 'archived' and (deleted_reason is null or char_length(deleted_reason) <= 500)));
create index if not exists guioes_deleted on public.guioes (client_id, deleted_at) where deleted_at is not null;

-- Um guião eliminado não muda (nem pelo motor, nem por RPCs antigas), exceto pela recuperação.
create or replace function public.guioes_deleted_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.deleted_at is not null and coalesce(current_setting('clipstudio.content_undelete', true), '') <> 'on' then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'Este guião foi eliminado.';
  end if;
  return new;
end $$;
drop trigger if exists guioes_deleted_guard on public.guioes;
create trigger guioes_deleted_guard before update on public.guioes for each row execute function public.guioes_deleted_guard();
revoke all on function public.guioes_deleted_guard() from public, anon, authenticated;

-- ───────────── leitura: eliminados fora do RLS ─────────────
create or replace function public._content_deleted(p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from guioes where id = p_id and deleted_at is not null)
$$;
revoke all on function public._content_deleted(text) from public, anon;
grant execute on function public._content_deleted(text) to authenticated;

drop policy if exists guioes_select on public.guioes;
create policy guioes_select on public.guioes for select to authenticated
  using (public.authorize('scripts.read', client_id) and deleted_at is null);
drop policy if exists content_versions_select on public.content_versions;
create policy content_versions_select on public.content_versions for select to authenticated
  using (public.authorize('scripts.read', workspace_id) and not public._content_deleted(content_id));
drop policy if exists content_transitions_select on public.content_transitions;
create policy content_transitions_select on public.content_transitions for select to authenticated
  using (public.authorize('scripts.read', workspace_id) and not public._content_deleted(content_id));

-- ───────────── RPCs novas ─────────────
-- O que impede eliminar (lista para a UI e para a mensagem do erro).
create or replace function public._content_delete_blockers(g guioes) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'tasks', nullif((select count(*) from tasks t where t.content_id = g.id and t.status in ('todo','doing','blocked')), 0),
    'publications', nullif((select count(*) from pub_publications p where p.content_id = g.id and p.status <> 'cancelada'), 0),
    'published', nullif((select count(*) from publication_lineage l where l.content_id = g.id), 0)
                 + case when g.production_status = 'published' then 1 else 0 end,
    'media', nullif((select count(*) from media_assets m where m.content_id = g.id and m.lifecycle = 'ativo'), 0)))
$$;

create or replace function public._content_delete_why(b jsonb) returns text
language sql immutable set search_path = public as $$
  select nullif(concat_ws('; ',
    case when b ? 'tasks' then (b->>'tasks') || ' tarefa(s) aberta(s): fecha-as ou cancela-as em Tarefas' end,
    case when b ? 'publications' then (b->>'publications') || ' publicação(ões) planeada(s): cancela-as no calendário de publicações' end,
    case when b ? 'published' then 'já foi publicado: fica arquivado para não perder as métricas' end,
    case when b ? 'media' then (b->>'media') || ' ativo(s) na biblioteca: manda-os para o lixo primeiro' end), '')
$$;

-- Eliminar: arquivado, confirmação = ID do guião, sessão individual, scripts.purge, sem dependências.
create or replace function public.content_delete(p_id text, p_confirm text, p_reason text default null, p_lock integer default null,
                                                 p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); corr uuid := gen_random_uuid(); b jsonb; why text;
begin
  if auth.uid() is null then
    raise exception 'sessao_individual' using errcode = '42501', detail = 'Eliminar guiões precisa de uma sessão individual (não do código de equipa).'; end if;
  select * into g from guioes where id = p_id for update;
  if g.id is null or g.deleted_at is not null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.purge', g.client_id, p_token, 'script.delete', g.id);
  if p_lock is not null and p_lock <> g.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  if g.editorial_status <> 'archived' then
    raise exception 'nao_arquivado' using errcode = '22023', detail = 'Só se eliminam guiões arquivados. Arquiva-o primeiro.'; end if;
  if p_confirm is distinct from g.id then
    raise exception 'confirmacao_invalida' using errcode = '22023', detail = 'Confirmação em falta ou errada: nada foi eliminado.'; end if;
  p_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if char_length(p_reason) > 500 then raise exception 'motivo_longo' using errcode = '22023', detail = 'O motivo tem de ter até 500 caracteres.'; end if;
  b := public._content_delete_blockers(g);
  why := public._content_delete_why(b);
  if why is not null then raise exception 'tem_dependencias' using errcode = '22023', detail = 'Não se pode eliminar: ' || why || '.'; end if;

  update guioes set deleted_at = now(), deleted_by = auth.uid(), deleted_label = a->>'label', deleted_reason = p_reason,
                    lock_version = lock_version + 1, updated_at = now()
   where id = g.id returning * into g;
  perform public._content_log(g, 'editorial', 'archived', 'deleted', g.current_version_id, p_reason, a, 'script.deleted', corr);
  return jsonb_build_object('id', g.id, 'deleted_at', g.deleted_at, 'recoverable_until', g.deleted_at + interval '30 days');
end $$;

-- Eliminados recuperáveis do cliente (só para quem pode eliminar).
create or replace function public.content_deleted_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sessao_individual' using errcode = '42501'; end if;
  perform public._content_require('scripts.purge', p_ws, p_token, 'script.deleted_list', null);
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
            'hook', g.hooks->0->>'text', 'deleted_at', g.deleted_at, 'deleted_by', g.deleted_label, 'reason', g.deleted_reason,
            'recoverable_until', g.deleted_at + interval '30 days') order by g.deleted_at desc)
    from guioes g where g.client_id = p_ws and g.deleted_at is not null and g.deleted_at > now() - interval '30 days'), '[]');
end $$;

-- Recuperar (R-09): volta a arquivado, dentro de 30 dias, com scripts.purge. Não usa _content_require com o ID (que o trata
-- como inexistente) e devolve o mesmo erro para outro cliente e para inexistente.
create or replace function public.content_undelete(p_id text, p_token text default null) returns guioes
language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); corr uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'sessao_individual' using errcode = '42501'; end if;
  select * into g from guioes where id = p_id for update;
  if g.id is null or g.deleted_at is null or not public.ws_can('scripts.purge', g.client_id, p_token) then
    if g.id is not null then
      raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', g.client_id, 'action', 'script.undelete', 'entity_id', g.id);
    end if;
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002';
  end if;
  if g.deleted_at <= now() - interval '30 days' then
    raise exception 'prazo_expirado' using errcode = '22023', detail = 'Passaram mais de 30 dias desde que foi eliminado: já não se recupera.'; end if;
  perform set_config('clipstudio.content_undelete', 'on', true);
  update guioes set deleted_at = null, deleted_by = null, deleted_label = null, deleted_reason = null,
                    lock_version = lock_version + 1, updated_at = now()
   where id = g.id returning * into g;
  perform set_config('clipstudio.content_undelete', 'off', true);
  perform public._content_log(g, 'editorial', 'deleted', 'archived', g.current_version_id, null, a, 'script.undeleted', corr);
  return g;
end $$;

revoke all on function public._content_delete_blockers(guioes), public._content_delete_why(jsonb) from public, anon, authenticated;
revoke all on function public.content_delete(text, text, text, integer, text), public.content_deleted_list(text, text),
  public.content_undelete(text, text) from public;
grant execute on function public.content_delete(text, text, text, integer, text), public.content_deleted_list(text, text),
  public.content_undelete(text, text) to anon, authenticated;

-- ───────────── funções existentes: eliminados ficam de fora ─────────────
-- _content_require: um ID de guião eliminado dá P0002 em todas as RPCs que recebem o guião (histórico, editar, transições,
-- recuperar do arquivo, metadados, produção, reagendar, comentários, publicações…). Corpo igual + 3 linhas.

CREATE OR REPLACE FUNCTION public._content_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.ws_can(p_cap, p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', p_action, 'entity_id', p_entity, 'capability', p_cap);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  -- guião eliminado (FR-02-01, W9-01): para todas as ações é como se não existisse
  if p_entity is not null and exists (select 1 from guioes where id = p_entity and deleted_at is not null) then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002';
  end if;
end $function$;

-- legacy_guioes (código de equipa), search_global e content_bulk_export: corpo igual + filtro deleted_at is null.

CREATE OR REPLACE FUNCTION public.legacy_guioes(p_token text, p_from date, p_to date)
 RETURNS SETOF guioes
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ws text := public.legacy_ws(p_token);
begin
  if v_ws is null then raise exception 'codigo_invalido' using errcode = '28000'; end if;
  return query select * from guioes where client_id = v_ws and deleted_at is null and date between p_from and p_to order by date, n;
end $function$;

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
          union all select unnest(r.tags) from reference_items r where r.workspace_id = any (w_refs) and r.archived_at is null) z
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

  return jsonb_build_object('q', q, 'mode', 'text', 'workspaces', cardinality(w_all),
                            'groups', (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(groups) x where jsonb_array_length(x->'items') > 0));
end $function$;

CREATE OR REPLACE FUNCTION public.content_bulk_export(p_ws text, p_ids text[], p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           from guioes g where g.client_id = p_ws and g.id = any (ids) and g.deleted_at is null);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.exported', 'content_bulk', null,
          jsonb_build_object('format', 'csv', 'count', jsonb_array_length(rows), 'ids', (select jsonb_agg(x->'id') from jsonb_array_elements(rows) x)));
  return jsonb_build_object('rows', rows, 'missing', cardinality(ids) - jsonb_array_length(rows));
end $function$;


/* Rollback (só depois de recuperar ou aceitar a perda dos eliminados; antes, `select id from guioes where deleted_at is not null`):
   1. Repor as quatro funções existentes a partir das migrações anteriores (corpo sem o filtro deleted_at):
      _content_require e legacy_guioes (20261028185427_w1_data_access_cutover / 20261028195656_w2_content_core),
      search_global (20261030075627_w7_busca_p1) e content_bulk_export (20261030075706_w7_busca_p2).
   2. drop policy guioes_select, content_versions_select, content_transitions_select e recriá-las sem `deleted_at` /
      `_content_deleted` (como em 20261028185427 e 20261028195656).
   3. drop function public.content_undelete(text, text), public.content_deleted_list(text, text),
        public.content_delete(text, text, text, integer, text), public._content_delete_why(jsonb),
        public._content_delete_blockers(guioes), public._content_deleted(text);
      drop trigger guioes_deleted_guard on public.guioes; drop function public.guioes_deleted_guard();
   4. alter table public.guioes drop constraint guioes_deleted_ok, drop column deleted_reason, drop column deleted_label,
        drop column deleted_by, drop column deleted_at;   -- destrutivo: os eliminados voltam a arquivados visíveis
   5. delete from role_capabilities where capability = 'scripts.purge'; delete from permission_grants where capability = 'scripts.purge';
      delete from capabilities where key = 'scripts.purge';
*/
