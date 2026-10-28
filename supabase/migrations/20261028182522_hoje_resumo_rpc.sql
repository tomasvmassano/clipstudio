-- 20261028182522 hoje_resumo_rpc (exportado do Supabase a 28/10/2026; segredos tapados)
create or replace function public.hoje_resumo(p_client text default 'numeiro')
returns jsonb language sql security definer set search_path = public stable as $$
with acc as (select id from accounts where client_id = p_client and role = 'client'),
r as (
  select distinct on (r.id) r.id, r.views, coalesce(r.taken_at, nullif(r.timestamp,'')::timestamptz) dt
  from reels r where r.account_id in (select id from acc)
  order by r.id, r.updated_at desc nulls last
),
dia as (
  select (dt at time zone 'Asia/Dubai')::date d, sum(views) views, count(*) reels
  from r where dt > now() - interval '61 days' group by 1
),
ult_run as (
  select run_id from agent_log where client_id = p_client order by created_at desc limit 1
),
ag as (
  select distinct on (agent) agent, status, left(message,140) message, created_at,
         (select count(*) from agent_log l2 where l2.run_id = l.run_id and l2.agent = l.agent) passos, simulated
  from agent_log l where run_id = (select run_id from ult_run)
  order by agent, id desc
),
act as (
  (select 'validado' tipo, g.n, g.tema, g.validado_em at from guioes g where g.client_id = p_client and g.validado_em is not null order by g.validado_em desc limit 6)
  union all
  (select 'gravado', g.n, g.tema, g.gravado_em from guioes g where g.client_id = p_client and g.gravado_em is not null order by g.gravado_em desc limit 6)
  union all
  (select case when g.status = 'rejeitado' then 'rejeitado' else 'editado' end, g.n, g.tema, g.updated_at
     from guioes g where g.client_id = p_client and (g.status = 'rejeitado' or jsonb_array_length(coalesce(g.history,'[]'::jsonb)) > 0)
     order by g.updated_at desc limit 6)
  union all
  (select 'corrida', null, case when bool_or(simulated) then 'corrida simulada' else 'corrida do motor' end, max(created_at)
     from agent_log where client_id = p_client group by run_id order by max(created_at) desc limit 3)
)
select jsonb_build_object(
  'views_30d', (select coalesce(sum(views),0) from r where dt > now() - interval '30 days'),
  'views_prev_30d', (select coalesce(sum(views),0) from r where dt <= now() - interval '30 days' and dt > now() - interval '60 days'),
  'reels_30d', (select count(*) from r where dt > now() - interval '30 days'),
  'ultimo', (select max(dt) from r),
  'diario', (select coalesce(jsonb_agg(jsonb_build_object('date', d, 'views', views, 'reels', reels) order by d), '[]') from dia),
  'agentes', (select coalesce(jsonb_agg(to_jsonb(ag)), '[]') from ag),
  'run_id', (select run_id from ult_run),
  'atividade', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]') from (select * from act where at is not null order by at desc limit 8) a)
);
$$;
revoke all on function public.hoje_resumo(text) from public;
grant execute on function public.hoje_resumo(text) to anon, authenticated;;
