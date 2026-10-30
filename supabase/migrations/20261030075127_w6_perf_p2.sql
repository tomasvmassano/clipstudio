-- Parte 2 de 3 de 20261030010100_w6_perf.sql (aplicada em produção como w6_perf_p2).

-- Publicações com etiquetas, fotografias e índices (json por publicação). Base de todas as leituras.
create or replace function public._perf_rows(p_ws text) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ix as (select * from public._perf_index(p_ws)),
  snaps as (
    select ix.reel_id, jsonb_object_agg(ix.age, jsonb_build_object('views', ix.views, 'idx', ix.idx, 'base_n', ix.base_n, 'base_median', ix.base_median)) s
    from ix group by ix.reel_id
  )
  select to_jsonb(p) || jsonb_build_object('snapshots', coalesce(s.s, '{}'::jsonb),
           'idx72', (s.s->'72h'->>'idx')::numeric,
           'comments_pk', case when p.views > 0 then round(p.comments * 1000.0 / p.views, 2) end,
           'likes_pk', case when p.views > 0 and p.likes > 0 then round(p.likes * 1000.0 / p.views, 2) end,
           'shares_pk', case when p.views > 0 and p.shares > 0 then round(p.shares * 1000.0 / p.views, 2) end)
  from public._perf_pubs(p_ws) p left join snaps s on s.reel_id = p.reel_id
$$;

-- Visão geral: hierarquia (PERF-01), contas com saúde e ressonância (PERF-05), cobertura das fotografias (PERF-03).
create or replace function public.perf_center(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb; prm jsonb := public._perf_params();
begin
  perform public._content_require('analytics.read', p_ws, p_token, 'perf.center', p_ws);
  with rows as (select x j from public._perf_rows(p_ws) x),
  acc as (
    select a.id, a.platform, a.handle, a.label, a.active, pa.tier, coalesce(pa.creator, c.name) creator,
           coalesce(pa.health_state, 'sem_registo') health_state, pa.health_note, pa.health_set_at, pa.health_set_label
    from accounts a join clients c on c.id = a.client_id
    left join perf_accounts pa on pa.account_id = a.id and pa.workspace_id = p_ws
    where a.client_id = p_ws and a.role = 'client'
  ),
  per as (
    select acc.*,
      (select count(*) from rows where j->>'account_id' = acc.id) n,
      (select count(*) from rows where j->>'account_id' = acc.id and (j->>'published_at')::timestamptz >= now() - interval '30 days') n_30d,
      (select max((j->>'last_read_at')::timestamptz) from rows where j->>'account_id' = acc.id) last_read_at,
      (select percentile_cont(0.5) within group (order by (j->>'idx72')::numeric) from rows
        where j->>'account_id' = acc.id and j->>'idx72' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') idx72_median_30d,
      (select count(*) from rows where j->>'account_id' = acc.id and j->>'idx72' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') idx72_n_30d,
      (select percentile_cont(0.5) within group (order by (j->>'comments_pk')::numeric) from rows
        where j->>'account_id' = acc.id and j->>'comments_pk' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') comments_pk,
      (select percentile_cont(0.5) within group (order by (j->>'likes_pk')::numeric) from rows
        where j->>'account_id' = acc.id and j->>'likes_pk' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') likes_pk,
      (select percentile_cont(0.5) within group (order by (j->>'shares_pk')::numeric) from rows
        where j->>'account_id' = acc.id and j->>'shares_pk' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') shares_pk,
      exists (select 1 from rows where j->>'account_id' = acc.id and (j->>'shares')::bigint > 0) shares_available,
      -- saúde: views às 72 h das publicadas nos últimos 7 dias vs nos 30 dias anteriores (mesma conta, mesma idade)
      (select count(*) from rows where j->>'account_id' = acc.id and j->'snapshots'->'72h'->>'views' is not null
         and (j->>'published_at')::timestamptz >= now() - interval '7 days') h_recent_n,
      (select percentile_cont(0.5) within group (order by (j->'snapshots'->'72h'->>'views')::numeric) from rows
        where j->>'account_id' = acc.id and j->'snapshots'->'72h'->>'views' is not null and (j->>'published_at')::timestamptz >= now() - interval '7 days') h_recent_med,
      (select count(*) from rows where j->>'account_id' = acc.id and j->'snapshots'->'72h'->>'views' is not null
         and (j->>'published_at')::timestamptz >= now() - interval '37 days' and (j->>'published_at')::timestamptz < now() - interval '7 days') h_prev_n,
      (select percentile_cont(0.5) within group (order by (j->'snapshots'->'72h'->>'views')::numeric) from rows
        where j->>'account_id' = acc.id and j->'snapshots'->'72h'->>'views' is not null
          and (j->>'published_at')::timestamptz >= now() - interval '37 days' and (j->>'published_at')::timestamptz < now() - interval '7 days') h_prev_med,
      (select count(*) filter (where (j->>'idx72')::numeric < (prm->>'near_zero')::numeric)::numeric / nullif(count(*), 0) from rows
        where j->>'account_id' = acc.id and j->>'idx72' is not null and (j->>'published_at')::timestamptz >= now() - interval '30 days') near_zero_30d,
      (select count(*) filter (where (j->>'idx72')::numeric < (prm->>'near_zero')::numeric)::numeric / nullif(count(*), 0) from rows
        where j->>'account_id' = acc.id and j->>'idx72' is not null and (j->>'published_at')::timestamptz >= now() - interval '60 days'
          and (j->>'published_at')::timestamptz < now() - interval '30 days') near_zero_prev
    from acc
  )
  select jsonb_build_object(
    'client', (select jsonb_build_object('id', id, 'name', name, 'timezone', coalesce(timezone, 'Asia/Dubai')) from clients where id = p_ws),
    'params', prm,
    'can_manage', public.ws_can('analytics.manage', p_ws, p_token),
    'families', public._perf_families(),
    'source', 'scraping',
    'first_reading_at', (select min(captured_at) from perf_readings where workspace_id = p_ws),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'platform', platform, 'handle', handle, 'label', label, 'active', active, 'tier', tier, 'creator', creator,
        'n', n, 'n_30d', n_30d, 'last_read_at', last_read_at,
        'idx72_median_30d', round(idx72_median_30d::numeric, 2), 'idx72_n_30d', idx72_n_30d,
        'comments_pk', round(comments_pk::numeric, 2), 'likes_pk', round(likes_pk::numeric, 2),
        'shares_pk', case when shares_available then round(shares_pk::numeric, 2) end, 'shares_available', shares_available,
        'health', jsonb_build_object(
          'state', health_state, 'note', health_note, 'set_at', health_set_at, 'set_label', health_set_label,
          'recent_n', h_recent_n, 'prev_n', h_prev_n,
          'median_ratio', case when h_recent_n >= 3 and h_prev_n >= (prm->>'min_base')::int and h_prev_med > 0 then round((h_recent_med / h_prev_med)::numeric, 2) end,
          'median_drop', case when h_recent_n >= 3 and h_prev_n >= (prm->>'min_base')::int and h_prev_med > 0 then h_recent_med / h_prev_med < (prm->>'drop_ratio')::numeric end,
          'near_zero_30d', round(near_zero_30d, 3), 'near_zero_prev', round(near_zero_prev, 3),
          'near_zero_doubling', case when near_zero_prev > 0 then near_zero_30d >= 2 * near_zero_prev end))
        order by platform, handle) from per), '[]'),
    'coverage', (select jsonb_object_agg(a.age, jsonb_build_object(
        'snapshots', (select count(*) from rows where j->'snapshots' ? a.age),
        'indexed', (select count(*) from rows where j->'snapshots'->a.age->>'idx' is not null)))
      from jsonb_array_elements_text(prm->'ages') a(age)),
    'totals', (select jsonb_build_object('publications', count(*),
        'sistema', count(*) filter (where j->>'origin' = 'sistema'), 'externo', count(*) filter (where j->>'origin' = 'externo'),
        'gravada', count(*) filter (where j->>'lineage_mode' = 'gravada'), 'inferida', count(*) filter (where j->>'lineage_mode' = 'inferida'),
        'linked', count(*) filter (where j->>'content_id' is not null)) from rows)
  ) into res;
  return res;
end $$;

-- Lista de publicações (PERF-02, PERF-03, PERF-04). p_filters: account, platform, origin, days, sort ('recentes'|'indice'), limit, offset.
create or replace function public.perf_publications(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := coalesce(p_filters, '{}'); lim int; off int;
begin
  perform public._content_require('analytics.read', p_ws, p_token, 'perf.publications', p_ws);
  if jsonb_typeof(f) <> 'object' then raise exception 'filtros_invalidos' using errcode = '22023'; end if;
  lim := least(200, greatest(1, coalesce((f->>'limit')::int, 50)));
  off := greatest(0, coalesce((f->>'offset')::int, 0));
  return (with rows as (select x j from public._perf_rows(p_ws) x where public._perf_match(x, f))
    select jsonb_build_object('total', (select count(*) from rows), 'limit', lim, 'offset', off,
      'items', coalesce((select jsonb_agg(j) from (select j from rows
          order by case when f->>'sort' = 'indice' then (j->>'idx72')::numeric end desc nulls last,
                   (j->>'published_at')::timestamptz desc nulls last, j->>'reel_id'
          limit lim offset off) t), '[]')));
end $$;

-- PERF-06: vistas por dimensão. Grupos com mediana do índice à idade escolhida; views absolutas só dentro de uma conta.
create or replace function public.perf_breakdown(p_ws text, p_dimension text, p_age text default '72h', p_filters jsonb default '{}', p_token text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := coalesce(p_filters, '{}'); expr text;
begin
  perform public._content_require('analytics.read', p_ws, p_token, 'perf.breakdown', p_ws);
  if public._perf_age_seconds(p_age) is null then raise exception 'idade_invalida' using errcode = '22023', detail = 'Idades: 1h, 24h, 72h, 7d, 30d.'; end if;
  if p_dimension not in ('account', 'platform', 'creator', 'tier', 'content', 'hook', 'style', 'theme', 'format', 'persona', 'generation', 'origin') then
    raise exception 'dimensao_invalida' using errcode = '22023'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'filtros_invalidos' using errcode = '22023'; end if;
  return (with rows as (
      select x j, (x->'snapshots'->p_age->>'idx')::numeric idx, (x->'snapshots'->p_age->>'views')::bigint av,
        case p_dimension
          when 'account' then x->>'account_id' when 'platform' then x->>'platform' when 'creator' then x->>'creator'
          when 'tier' then x->>'tier' when 'content' then x->>'content_id' when 'hook' then x->>'hook_mechanism'
          when 'style' then x->>'edit_style_key' when 'theme' then x->>'tema' when 'format' then x->>'formato'
          when 'persona' then x->>'persona_phrase' when 'generation' then x->>'generation' when 'origin' then x->>'origin' end k
      from public._perf_rows(p_ws) x where public._perf_match(x, f)),
    -- canibalização: a mesma peça já tinha saído noutra conta da mesma plataforma antes desta
    rep as (select r.j->>'reel_id' reel_id from rows r where r.j->>'content_id' is not null and exists (
              select 1 from rows o where o.j->>'content_id' = r.j->>'content_id' and o.j->>'platform' = r.j->>'platform'
                and o.j->>'account_id' <> r.j->>'account_id' and (o.j->>'published_at')::timestamptz < (r.j->>'published_at')::timestamptz)),
    g as (
      select k, count(*) n, count(idx) n_indexed,
        percentile_cont(0.5) within group (order by idx) idx_median,
        max(idx) idx_best, min(idx) idx_worst,
        count(distinct j->>'account_id') accounts,
        min(j->>'account_id') one_account,
        percentile_cont(0.5) within group (order by av) views_median,
        count(idx) filter (where j->>'reel_id' in (select reel_id from rep)) repeat_n,
        percentile_cont(0.5) within group (order by idx) filter (where j->>'reel_id' in (select reel_id from rep)) repeat_idx_median,
        jsonb_agg(jsonb_build_object('reel_id', j->>'reel_id', 'platform', j->>'platform', 'handle', j->>'handle', 'hook_index', j->'hook_index',
                   'hook_text', j->>'hook_text', 'title', j->>'title', 'url', j->>'url', 'idx', idx, 'published_at', j->>'published_at')
                  order by idx desc nulls last) filter (where p_dimension = 'content') items
      from rows where k is not null group by k
    )
    select jsonb_build_object('dimension', p_dimension, 'age', p_age,
      'unassigned', (select count(*) from rows where k is null),
      'groups', coalesce((select jsonb_agg(jsonb_build_object(
          'key', k, 'n', n, 'n_indexed', n_indexed, 'idx_median', round(idx_median::numeric, 2),
          'idx_best', idx_best, 'idx_worst', idx_worst, 'accounts', accounts,
          -- views absolutas só quando o grupo é de uma única conta (PERF-04)
          'views_median', case when accounts = 1 then round(views_median::numeric) end,
          'label', case when p_dimension = 'account' then (select '@' || handle || ' · ' || platform from accounts where id = k) end,
          'repeat_n', repeat_n, 'repeat_idx_median', round(repeat_idx_median::numeric, 2),
          'items', items) order by idx_median desc nulls last, n desc) from g), '[]')));
end $$;

-- PERF-07: alavancas "o que replicar" e relatório semanal. Só "Só o que fizemos" por defeito (R-16).
create or replace function public.perf_levers(p_ws text, p_only_system boolean default true, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prm jsonb := public._perf_params(); ms int := (prm->>'min_sample')::int;
begin
  perform public._content_require('analytics.read', p_ws, p_token, 'perf.levers', p_ws);
  return (with rows as (
      select x j, (x->>'idx72')::numeric idx from public._perf_rows(p_ws) x
      where (not coalesce(p_only_system, true) or x->>'origin' = 'sistema')),
    att as (
      select d.dim, d.k, r.idx from rows r cross join lateral (values
        ('format', r.j->>'formato'), ('theme', r.j->>'tema'), ('hook', r.j->>'hook_mechanism'), ('style', r.j->>'edit_style_key'),
        ('persona', r.j->>'persona_phrase'), ('generation', r.j->>'generation'), ('platform', r.j->>'platform'), ('tier', r.j->>'tier'),
        ('hour', case when r.j->>'local_hour' is not null then lpad(r.j->>'local_hour', 2, '0') || 'h' end),
        ('duration', case when (r.j->>'duration_s')::numeric is null then null when (r.j->>'duration_s')::numeric < 20 then '<20 s'
                          when (r.j->>'duration_s')::numeric < 40 then '20-40 s' when (r.j->>'duration_s')::numeric < 60 then '40-60 s' else '60 s ou mais' end)
      ) d(dim, k)
      where d.k is not null and r.idx is not null and (r.j->>'published_at')::timestamptz >= now() - interval '90 days'),
    lv as (select dim, k, count(*) n, percentile_cont(0.5) within group (order by idx) med from att group by dim, k),
    wk as (select * from rows where idx is not null and (j->>'published_at')::timestamptz >= now() - interval '10 days'
             and (j->>'published_at')::timestamptz < now() - interval '3 days'),
    pick as (select j - 'snapshots' || jsonb_build_object('idx72', idx) p from wk)
    select jsonb_build_object('params', prm, 'only_system', coalesce(p_only_system, true),
      'eligible', (select count(*) from rows where idx is not null and (j->>'published_at')::timestamptz >= now() - interval '90 days'),
      'levers', coalesce((select jsonb_agg(jsonb_build_object('dimension', dim, 'key', k, 'n', n, 'shown', n >= ms,
          'idx_median', case when n >= ms then round(med::numeric, 2) end) order by dim, (n >= ms) desc, med desc) from lv), '[]'),
      'week', jsonb_build_object(
        'from', now() - interval '10 days', 'to', now() - interval '3 days', 'n', (select count(*) from wk),
        'top', coalesce((select jsonb_agg(p order by (p->>'idx72')::numeric desc) from (select p from pick order by (p->>'idx72')::numeric desc limit 10) t), '[]'),
        'bottom', coalesce((select jsonb_agg(p order by (p->>'idx72')::numeric) from (select p from pick order by (p->>'idx72')::numeric limit 10) t), '[]'),
        'hooks_by_platform', coalesce((select jsonb_object_agg(pl, hs) from (
            select pl, jsonb_agg(h order by (h->>'idx72')::numeric desc) hs from (
              select p->>'platform' pl, jsonb_build_object('hook_text', p->>'hook_text', 'hook_mechanism', p->>'hook_mechanism', 'idx72', p->'idx72',
                       'reel_id', p->>'reel_id', 'handle', p->>'handle') h,
                     row_number() over (partition by p->>'platform' order by (p->>'idx72')::numeric desc) rn
              from pick where p->>'hook_text' is not null) z where rn <= 3 group by pl) y), '{}'),
        'styles_to_cut', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'n', n, 'idx_median', round(med::numeric, 2)))
            from lv where dim = 'style' and n >= ms and med < (prm->>'cut_below')::numeric), '[]'))));
end $$;

-- PERF-01/PERF-05: camada, criador e estado da conta registado à mão (analytics.manage, auditado).
create or replace function public.perf_account_set(p_ws text, p_account text, p_patch jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); before jsonb; cur perf_accounts;
begin
  perform public._content_require('analytics.manage', p_ws, p_token, 'perf.account_set', p_account);
  if not exists (select 1 from accounts where id = p_account and client_id = p_ws and role = 'client') then
    raise exception 'conta_nao_encontrada' using errcode = 'P0002'; end if;
  if jsonb_typeof(coalesce(p_patch, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if p_patch ? 'tier' and nullif(p_patch->>'tier', '') is not null and p_patch->>'tier' not in ('A', 'B', 'C', 'D') then
    raise exception 'camada_invalida' using errcode = '22023', detail = 'Camadas: A, B, C ou D.'; end if;
  if p_patch ? 'health_state' and p_patch->>'health_state' not in ('sem_registo', 'normal', 'alcance_reduzido', 'restrita', 'suspensa') then
    raise exception 'estado_invalido' using errcode = '22023'; end if;
  if char_length(coalesce(p_patch->>'creator', '')) > 80 or char_length(coalesce(p_patch->>'health_note', '')) > 500 then
    raise exception 'texto_longo' using errcode = '22023', detail = 'Criador até 80 caracteres, nota até 500.'; end if;
  insert into perf_accounts (account_id, workspace_id) values (p_account, p_ws) on conflict (account_id) do nothing;
  select * into cur from perf_accounts where account_id = p_account for update;
  before := to_jsonb(cur) - 'workspace_id';
  update perf_accounts set
    tier = case when p_patch ? 'tier' then nullif(p_patch->>'tier', '') else tier end,
    creator = case when p_patch ? 'creator' then nullif(btrim(p_patch->>'creator'), '') else creator end,
    health_state = case when p_patch ? 'health_state' then p_patch->>'health_state' else health_state end,
    health_note = case when p_patch ? 'health_note' then nullif(btrim(p_patch->>'health_note'), '') else health_note end,
    health_set_at = case when p_patch ? 'health_state' or p_patch ? 'health_note' then now() else health_set_at end,
    health_set_label = case when p_patch ? 'health_state' or p_patch ? 'health_note' then a->>'label' else health_set_label end,
    updated_at = now()
  where account_id = p_account;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'perf.account_set', 'account', p_account, before,
          (select to_jsonb(x) - 'workspace_id' from perf_accounts x where account_id = p_account));
  return public.perf_center(p_ws, p_token);
end $$;

-- Materializa a linhagem inferida das publicações importadas (origem externo, marcada 'inferida'). Nunca toca nas gravadas
-- nem na origem corrigida à mão. Idempotente.
create or replace function public.perf_sync_lineage(p_ws text) returns int
language plpgsql security definer set search_path = public as $$
declare n int; tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
begin
  with i as (select i.*, pa.tier from public._perf_inferred(p_ws) i left join perf_accounts pa on pa.account_id = i.account_id),
  ins as (
    insert into publication_lineage (workspace_id, account_id, platform, external_id, url, published_at, origin, origin_source, lineage_mode,
      inference_source, inference_confidence, content_id, content_version_id, version_no, hook_index, hook_text, hook_mechanism, formato, maquina,
      tema, duration_s, source_type, tier, local_tz, local_hour, recorded_kind, recorded_label)
    select p_ws, i.account_id, i.platform, i.reel_id, left(i.url, 1000), i.published_at, 'externo', 'importacao', 'inferida',
      i.inference_source, i.inference_confidence, i.content_id, i.content_version_id, i.version_no, i.hook_index, i.hook_text, i.hook_mechanism,
      i.formato, i.maquina, i.tema, i.duration_s, i.source_type, i.tier, tz, extract(hour from i.published_at at time zone tz)::int, 'system', 'Importação'
    from i
    on conflict (workspace_id, account_id, external_id) do update set
      url = excluded.url, published_at = excluded.published_at, inference_source = excluded.inference_source,
      inference_confidence = excluded.inference_confidence, content_id = excluded.content_id, content_version_id = excluded.content_version_id,
      version_no = excluded.version_no, hook_index = excluded.hook_index, hook_text = excluded.hook_text, hook_mechanism = excluded.hook_mechanism,
      formato = excluded.formato, maquina = excluded.maquina, tema = excluded.tema, duration_s = excluded.duration_s,
      source_type = excluded.source_type, tier = excluded.tier, local_tz = excluded.local_tz, local_hour = excluded.local_hour, updated_at = now()
    where publication_lineage.lineage_mode = 'inferida'
      and (to_jsonb(publication_lineage) - array['id','updated_at','recorded_at','origin','origin_source','origin_reason','recorded_kind','recorded_label','correlation_id',
                                                  'edit_style_key','edit_style_version','persona_phrase','asset_ref','generation','parent_lineage_id'])
          is distinct from (to_jsonb(excluded) - array['id','updated_at','recorded_at','origin','origin_source','origin_reason','recorded_kind','recorded_label','correlation_id',
                                                  'edit_style_key','edit_style_version','persona_phrase','asset_ref','generation','parent_lineage_id'])
    returning 1)
  select count(*) into n from ins;
  return n;
end $$;
