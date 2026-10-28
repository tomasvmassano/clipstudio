-- 20261028184500 drift_hoje_resumo_desempenho
-- Regista definições aplicadas fora de migração (patches de 28/10 via SQL direto): ensaios fora do Hoje; diario/bandas/prev_30d no desempenho.
CREATE OR REPLACE FUNCTION public.hoje_resumo(p_client text DEFAULT 'numeiro'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  select run_id from agent_log where client_id = p_client and not simulated order by created_at desc limit 1
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
     from agent_log where client_id = p_client and not simulated group by run_id order by max(created_at) desc limit 3)
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
$function$;

CREATE OR REPLACE FUNCTION public.desempenho(p_client text DEFAULT 'numeiro'::text, p_account text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with r as (
  select r.*, coalesce(r.taken_at, nullif(r.timestamp,'')::timestamptz) as dt
  from reels r join accounts a on a.id = r.account_id
  where a.client_id = p_client and (p_account is null or a.id = p_account)
),
d as (select distinct on (id) * from r order by id, updated_at desc nulls last),
wk as (
  select date_trunc('week', dt)::date as semana, count(*) n, sum(views) views, round(avg(views)) media
  from d where dt is not null and dt > now() - interval '26 weeks'
  group by 1 order by 1
),
top as (
  select id, account_id, platform, url, left(coalesce(nullif(hook,''), caption),110) titulo, views, likes, comments, shares, outlier, dt
  from d order by views desc nulls last limit 10
),
recent as (
  select id, account_id, platform, url, left(coalesce(nullif(hook,''), caption),110) titulo, views, likes, comments, outlier, dt
  from d where dt is not null order by dt desc limit 10
),
contas as (
  select a.id, a.platform, a.handle, a.label, a.active,
         count(r.id) n, coalesce(sum(r.views),0) views,
         percentile_cont(0.5) within group (order by r.views) mediana,
         max(coalesce(r.taken_at, nullif(r.timestamp,'')::timestamptz)) ultimo
  from accounts a left join reels r on r.account_id = a.id
  where a.client_id = p_client group by a.id order by a.platform, a.handle
),
refs as (
  select a.handle as owner, count(*) n, percentile_cont(0.5) within group (order by r.views) mediana, max(r.views) melhor
  from reels r join accounts a on a.id = r.account_id
  where a.role='reference' group by a.handle order by mediana desc
),
fmt as (
  select formato, count(*) n,
         count(*) filter (where validado) validados,
         count(*) filter (where gravado) gravados,
         count(*) filter (where status='rejeitado') rejeitados,
         round(avg(critic_score)::numeric,2) score
  from guioes where client_id = p_client and (p_account is null or account_id = p_account or account_id is null)
  group by formato order by n desc
),
dias as (
  select date, count(*) n, count(*) filter (where validado) validados, count(*) filter (where gravado) gravados,
         count(*) filter (where status='rejeitado') rejeitados
  from guioes where client_id = p_client and date > current_date - 30 group by date order by date
)
select jsonb_build_object(
  'kpi', (select jsonb_build_object(
      'reels', count(*), 'views', coalesce(sum(views),0),
      'mediana', percentile_cont(0.5) within group (order by views),
      'media', round(avg(views)),
      'likes', coalesce(sum(likes),0), 'comentarios', coalesce(sum(comments),0),
      'ultimo', max(dt),
      'views_30d', coalesce(sum(views) filter (where dt > now() - interval '30 days'),0),
      'reels_30d', count(*) filter (where dt > now() - interval '30 days'),
      'outliers', count(*) filter (where outlier >= 2),
      'views_prev_30d', coalesce(sum(views) filter (where dt <= now() - interval '30 days' and dt > now() - interval '60 days'),0),
      'reels_prev_30d', count(*) filter (where dt <= now() - interval '30 days' and dt > now() - interval '60 days')
    ) from d),
  'diario', (select coalesce(jsonb_agg(jsonb_build_object('date', x.d, 'views', x.views, 'reels', x.reels) order by x.d), '[]')
             from (select (dt at time zone 'Asia/Dubai')::date d, sum(views) views, count(*) reels from d where dt > now() - interval '61 days' group by 1) x),
  'bandas', (select jsonb_build_object(
               'abaixo', count(*) filter (where outlier < 0.5),
               'normal', count(*) filter (where outlier >= 0.5 and outlier < 1),
               'acima', count(*) filter (where outlier >= 1 and outlier < 2),
               'viral', count(*) filter (where outlier >= 2)) from d where outlier is not null),
  'contas', (select coalesce(jsonb_agg(to_jsonb(contas)),'[]') from contas),
  'semanas', (select coalesce(jsonb_agg(to_jsonb(wk)),'[]') from wk),
  'top', (select coalesce(jsonb_agg(to_jsonb(top)),'[]') from top),
  'recentes', (select coalesce(jsonb_agg(to_jsonb(recent)),'[]') from recent),
  'referencias', (select coalesce(jsonb_agg(to_jsonb(refs)),'[]') from refs),
  'formatos', (select coalesce(jsonb_agg(to_jsonb(fmt)),'[]') from fmt),
  'dias', (select coalesce(jsonb_agg(to_jsonb(dias)),'[]') from dias)
);
$function$;
