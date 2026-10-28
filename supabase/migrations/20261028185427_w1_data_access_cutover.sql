-- 20261028185427 w1_data_access_cutover
-- W1-02: acesso aos dados passa a authorize() (login) ou código de equipa legado (ADR-0001 §7). Fim das leituras públicas.
-- Rollback: recriar políticas *_read using (true) e as RPCs anteriores (ver migrações 20261028160333, 20261028162355, 20261028190000).

-- ===== código de equipa legado =====
create or replace function public.legacy_ws(p_token text) returns text
language sql stable security definer set search_path = public as $$
  select client_id from studio_tokens where p_token is not null and token = p_token;
$$;
revoke all on function public.legacy_ws(text) from public, anon, authenticated;

-- capacidades do papel 'creator' do código (docs/access-matrix.md, "Mapeamento de hoje")
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','analytics.read','agents.read','agents.rehearse']);
$$;
revoke all on function public.legacy_can(text, text, text) from public, anon, authenticated;

create or replace function public.ws_can(p_cap text, p_ws text, p_token text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public._authorize(p_cap, p_ws, auth.uid()) or public.legacy_can(p_token, p_cap, p_ws);
$$;
revoke all on function public.ws_can(text, text, text) from public, anon, authenticated;

-- ===== políticas: fim do using(true) =====
drop policy if exists guioes_read on public.guioes;
drop policy if exists ideas_read on public.ideas;
drop policy if exists clients_read on public.clients;
drop policy if exists accounts_public_read on public.accounts;
drop policy if exists publicacoes_public_read on public.publicacoes;

create policy guioes_select on public.guioes for select to authenticated using (public.authorize('scripts.read', client_id));
create policy ideas_select on public.ideas for select to authenticated using (public.authorize('sources.read', client_id));
create policy clients_select on public.clients for select to authenticated
  using (public.authorize('scripts.read', id) or public.authorize('analytics.read', id));
create policy accounts_select on public.accounts for select to authenticated using (public.authorize('analytics.read', client_id));
create policy publicacoes_select on public.publicacoes for select to authenticated
  using (exists (select 1 from public.accounts a where a.id = account_id and public.authorize('analytics.read', a.client_id)));
revoke select on public.guioes, public.ideas, public.clients, public.accounts, public.publicacoes from anon;

-- ===== leituras para quem usa o código =====
create or replace function public.legacy_guioes(p_token text, p_from date, p_to date) returns setof public.guioes
language plpgsql stable security definer set search_path = public as $$
declare v_ws text := public.legacy_ws(p_token);
begin
  if v_ws is null then raise exception 'codigo_invalido' using errcode = '28000'; end if;
  return query select * from guioes where client_id = v_ws and date between p_from and p_to order by date, n;
end $$;
revoke all on function public.legacy_guioes(text, date, date) from public;
grant execute on function public.legacy_guioes(text, date, date) to anon, authenticated;

create or replace function public.legacy_ideas(p_token text, p_limit int default 100) returns setof public.ideas
language plpgsql stable security definer set search_path = public as $$
declare v_ws text := public.legacy_ws(p_token);
begin
  if v_ws is null then raise exception 'codigo_invalido' using errcode = '28000'; end if;
  return query select * from ideas where client_id = v_ws order by created_at desc limit least(p_limit, 500);
end $$;
revoke all on function public.legacy_ideas(text, int) from public;
grant execute on function public.legacy_ideas(text, int) to anon, authenticated;

-- ===== escrita de guiões: capacidade por campo + auditoria =====
create or replace function public.guiao_update(p_id text, p_patch jsonb, p_token text default null)
returns public.guioes language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); g public.guioes; before jsonb; v_kind text; v_label text; need text[] := '{}'; c text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;

  if p_patch ? 'validado' then need := need || 'scripts.approve'; end if;
  if p_patch->>'status' = 'rejeitado' or p_patch ? 'motivo_rejeicao' then need := need || 'scripts.reject'; end if;
  if p_patch->>'status' = 'aprovado' then need := need || 'scripts.approve'; end if;
  if p_patch ? 'gravado' then need := need || 'recording.confirm'; end if;
  if p_patch ?| array['hooks','corpo','formato','tema','n'] then need := need || 'scripts.edit'; end if;
  if cardinality(need) = 0 then raise exception 'nada_a_alterar' using errcode = '22023'; end if;

  if uid is not null then v_kind := 'user'; select email into v_label from auth.users where id = uid;
  elsif public.legacy_ws(p_token) is not null then v_kind := 'legacy_code'; select label into v_label from studio_tokens where token = p_token;
  else raise exception 'nao_autenticado' using errcode = '28000'; end if;

  foreach c in array need loop
    if not public.ws_can(c, g.client_id, p_token) then
      insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, result)
      values (uid, v_kind, v_label, g.client_id, 'script.update', 'guiao', g.id, jsonb_build_object('capability', c), 'denied');
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
  end loop;

  before := jsonb_build_object('status', g.status, 'validado', g.validado, 'gravado', g.gravado, 'motivo_rejeicao', g.motivo_rejeicao,
                               'hooks', g.hooks, 'corpo', g.corpo, 'formato', g.formato, 'tema', g.tema, 'n', g.n);
  if p_patch ? 'corpo' or p_patch ? 'hooks' then
    g.history := (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select x from jsonb_array_elements(g.history || jsonb_build_array(jsonb_build_object('hooks', g.hooks, 'corpo', g.corpo, 'at', g.updated_at))) x
      order by 1 desc limit 10) s);
  end if;

  update guioes set
    status = coalesce(p_patch->>'status', status),
    motivo_rejeicao = case when p_patch ? 'motivo_rejeicao' then p_patch->>'motivo_rejeicao' else motivo_rejeicao end,
    validado = coalesce((p_patch->>'validado')::boolean, validado),
    validado_em = case when p_patch ? 'validado' then (case when (p_patch->>'validado')::boolean then now() else null end) else validado_em end,
    gravado = coalesce((p_patch->>'gravado')::boolean, gravado),
    gravado_em = case when p_patch ? 'gravado' then (case when (p_patch->>'gravado')::boolean then now() else null end) else gravado_em end,
    hooks = coalesce(p_patch->'hooks', hooks),
    corpo = coalesce(p_patch->>'corpo', corpo),
    formato = coalesce(p_patch->>'formato', formato),
    tema = coalesce(p_patch->>'tema', tema),
    n = coalesce((p_patch->>'n')::int, n),
    history = g.history,
    updated_at = now()
  where id = p_id returning * into g;

  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, v_kind, v_label, g.client_id,
          case when p_patch ? 'validado' then 'script.approval' when p_patch ? 'gravado' then 'recording.confirm'
               when p_patch->>'status' = 'rejeitado' then 'script.rejected' else 'script.update' end,
          'guiao', g.id, before, p_patch);
  return g;
end $$;
revoke all on function public.guiao_update(text, jsonb, text) from public;
grant execute on function public.guiao_update(text, jsonb, text) to anon, authenticated;

-- ===== RPCs de leitura agregada: workspace verificado =====
create or replace function public.hoje_resumo(p_client text default 'numeiro', p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare res jsonb; show_agents boolean;
begin
  if not public.ws_can('analytics.read', p_client, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  show_agents := public.ws_can('agents.read', p_client, p_token);
  with acc as (select id from accounts where client_id = p_client and role = 'client'),
  r as (
    select distinct on (r.id) r.id, r.views, coalesce(r.taken_at, nullif(r.timestamp,'')::timestamptz) dt
    from reels r where r.account_id in (select id from acc) order by r.id, r.updated_at desc nulls last),
  dia as (select (dt at time zone 'Asia/Dubai')::date d, sum(views) views, count(*) reels from r where dt > now() - interval '61 days' group by 1),
  ult_run as (select run_id from agent_log where client_id = p_client and not simulated and show_agents order by created_at desc limit 1),
  ag as (
    select distinct on (agent) agent, status, left(message,140) message, created_at,
           (select count(*) from agent_log l2 where l2.run_id = l.run_id and l2.agent = l.agent) passos, simulated
    from agent_log l where run_id = (select run_id from ult_run) order by agent, id desc),
  act as (
    (select 'validado' tipo, g.n, g.tema, g.validado_em at from guioes g where g.client_id = p_client and g.validado_em is not null order by g.validado_em desc limit 6)
    union all
    (select 'gravado', g.n, g.tema, g.gravado_em from guioes g where g.client_id = p_client and g.gravado_em is not null order by g.gravado_em desc limit 6)
    union all
    (select case when g.status = 'rejeitado' then 'rejeitado' else 'editado' end, g.n, g.tema, g.updated_at
       from guioes g where g.client_id = p_client and (g.status = 'rejeitado' or jsonb_array_length(coalesce(g.history,'[]'::jsonb)) > 0)
       order by g.updated_at desc limit 6)
    union all
    (select 'corrida', null, 'corrida do motor', max(created_at)
       from agent_log where client_id = p_client and not simulated and show_agents group by run_id order by max(created_at) desc limit 3))
  select jsonb_build_object(
    'views_30d', (select coalesce(sum(views),0) from r where dt > now() - interval '30 days'),
    'views_prev_30d', (select coalesce(sum(views),0) from r where dt <= now() - interval '30 days' and dt > now() - interval '60 days'),
    'reels_30d', (select count(*) from r where dt > now() - interval '30 days'),
    'ultimo', (select max(dt) from r),
    'diario', (select coalesce(jsonb_agg(jsonb_build_object('date', d, 'views', views, 'reels', reels) order by d), '[]') from dia),
    'agentes', (select coalesce(jsonb_agg(to_jsonb(ag)), '[]') from ag),
    'run_id', (select run_id from ult_run),
    'atividade', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]') from (select * from act where at is not null order by at desc limit 8) a)
  ) into res;
  return res;
end $$;
drop function if exists public.hoje_resumo(text);
revoke all on function public.hoje_resumo(text, text) from public;
grant execute on function public.hoje_resumo(text, text) to anon, authenticated;

-- desempenho: mesmo conteúdo, agora com verificação e referências só do workspace (ADR-0001 §5)
do $$ declare src text; begin
  select pg_get_functiondef('public.desempenho(text,text)'::regprocedure) into src;
  src := replace(src, 'public.desempenho(p_client text DEFAULT ''numeiro''::text, p_account text DEFAULT NULL::text)',
                      'public.desempenho(p_client text DEFAULT ''numeiro''::text, p_account text DEFAULT NULL::text, p_token text DEFAULT NULL::text)');
  src := replace(src, 'LANGUAGE sql', 'LANGUAGE plpgsql');
  src := replace(src, E'AS $function$\nwith r as (', E'AS $function$\ndeclare res jsonb;\nbegin\n  if not public.ws_can(''analytics.read'', p_client, p_token) then raise exception ''sem_permissao'' using errcode = ''42501''; end if;\nwith r as (');
  src := replace(src, E'  where a.role=''reference'' group by a.handle order by mediana desc', E'  where a.role=''reference'' and a.client_id = p_client group by a.handle order by mediana desc');
  src := replace(src, E'select jsonb_build_object(\n  ''kpi''', E'select jsonb_build_object(\n  ''kpi''');
  src := regexp_replace(src, E'\\);\\n\\$function\\$', E') into res;\nreturn res;\nend;\n$function$');
  if position('ws_can' in src) = 0 or position('a.client_id = p_client group by a.handle' in src) = 0 or position('into res' in src) = 0 then
    raise exception 'patch desempenho falhou';
  end if;
  execute src;
end $$;
drop function if exists public.desempenho(text, text);
revoke all on function public.desempenho(text, text, text) from public;
grant execute on function public.desempenho(text, text, text) to anon, authenticated;

-- ===== agentes: fim da vista pública; eventos por workspace =====
revoke select on public.agent_feed from anon, authenticated;
drop view if exists public.agent_feed;

create or replace function public.agent_runs(p_ws text, p_token text default null, p_limit int default 8) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ws_can('agents.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]') from (
    select jsonb_build_object('run_id', run_id, 'created_at', max(created_at), 'simulated', bool_or(simulated), 'n', count(*)) x
    from agent_log where client_id = p_ws group by run_id order by max(created_at) desc limit least(p_limit, 50)) s);
end $$;
create or replace function public.agent_run_events(p_ws text, p_run text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ws_can('agents.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'run_id', run_id, 'client_id', client_id, 'slot', slot, 'agent', agent,
            'to_agent', to_agent, 'status', status, 'message', left(message, 280), 'model', model, 'ms', ms, 'cost_eur', cost_eur,
            'simulated', simulated, 'created_at', created_at) order by id), '[]')
          from agent_log where client_id = p_ws and run_id = p_run);
end $$;
revoke all on function public.agent_runs(text, text, int), public.agent_run_events(text, text, text) from public;
grant execute on function public.agent_runs(text, text, int), public.agent_run_events(text, text, text) to anon, authenticated;

-- ensaio: login com agents.rehearse ou código
create or replace function public.agent_simulate(p_ws text, p_events jsonb, p_token text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare v_run text := 'sim-' || to_char(now(), 'YYYYMMDDHH24MISS'); e jsonb; n int := 0; uid uuid := auth.uid();
begin
  if not public.ws_can('agents.rehearse', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if jsonb_array_length(p_events) > 60 then raise exception 'demasiados_eventos' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_events) loop
    insert into agent_log (run_id, client_id, slot, agent, to_agent, status, message, model, ms, cost_eur, simulated)
    values (v_run, p_ws, nullif(e->>'slot','')::int, e->>'agent', e->>'to', coalesce(e->>'status','talk'),
            left(e->>'message', 280), 'ensaio', nullif(e->>'ms','')::int, 0, true);
    n := n + 1;
  end loop;
  insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, entity_id, after)
  values (uid, case when uid is null then 'legacy_code' else 'user' end, p_ws, 'agents.rehearse', 'agent_run', v_run, jsonb_build_object('events', n));
  return n;
end $$;
drop function if exists public.agent_simulate(text, jsonb);
revoke all on function public.agent_simulate(text, jsonb, text) from public;
grant execute on function public.agent_simulate(text, jsonb, text) to anon, authenticated;

-- broadcast privado: só utilizadores com agents.read no workspace do tópico
create or replace function public.agent_log_broadcast() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new.id, 'run_id', new.run_id, 'client_id', new.client_id, 'slot', new.slot,
      'agent', new.agent, 'to_agent', new.to_agent, 'status', new.status, 'message', left(new.message, 280),
      'model', new.model, 'ms', new.ms, 'cost_eur', new.cost_eur, 'simulated', new.simulated, 'created_at', new.created_at),
    'agent_event', 'agents:' || coalesce(new.client_id, 'none'), true);
  return new;
end $$;
revoke execute on function public.agent_log_broadcast() from public, anon, authenticated;

drop policy if exists agents_topic_read on realtime.messages;
create policy agents_topic_read on realtime.messages for select to authenticated
  using (realtime.topic() like 'agents:%' and public.authorize('agents.read', split_part(realtime.topic(), ':', 2)));

-- guiões ao vivo (postgres_changes respeita RLS para utilizadores com login)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'guioes') then
    alter publication supabase_realtime add table public.guioes;
  end if;
end $$;
