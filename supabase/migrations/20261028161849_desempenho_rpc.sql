-- 20261028161849 desempenho_rpc (exportado do Supabase a 28/10/2026; segredos tapados)
create or replace function public.desempenho(p_client text default 'numeiro')
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
with c as (
  select * from clients where id = p_client
),
r as (
  select r.*, coalesce(r.taken_at, nullif(r.timestamp,'')::timestamptz) as dt
  from reels r, c
  where r.role = 'client' and (r.owner = c.id or r.owner = ltrim(c.handle,'@'))
),
d as (select distinct on (id) * from r order by id, updated_at desc nulls last),
wk as (
  select date_trunc('week', dt)::date as semana, count(*) n, sum(views) views, round(avg(views)) media
  from d where dt is not null and dt > now() - interval '26 weeks'
  group by 1 order by 1
),
top as (
  select id, platform, url, left(coalesce(nullif(hook,''), caption),110) titulo, views, likes, comments, shares, outlier, dt
  from d order by views desc nulls last limit 10
),
recent as (
  select id, platform, url, left(coalesce(nullif(hook,''), caption),110) titulo, views, likes, comments, outlier, dt
  from d where dt is not null order by dt desc limit 10
),
refs as (
  select owner, count(*) n, percentile_cont(0.5) within group (order by views) mediana, max(views) melhor
  from reels where role='reference' group by owner order by mediana desc
),
fmt as (
  select formato, count(*) n,
         count(*) filter (where validado) validados,
         count(*) filter (where gravado) gravados,
         count(*) filter (where status='rejeitado') rejeitados,
         round(avg(critic_score)::numeric,2) score
  from guioes where client_id = p_client group by formato order by n desc
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
      'outliers', count(*) filter (where outlier >= 2)
    ) from d),
  'semanas', (select coalesce(jsonb_agg(to_jsonb(wk)),'[]') from wk),
  'top', (select coalesce(jsonb_agg(to_jsonb(top)),'[]') from top),
  'recentes', (select coalesce(jsonb_agg(to_jsonb(recent)),'[]') from recent),
  'referencias', (select coalesce(jsonb_agg(to_jsonb(refs)),'[]') from refs),
  'formatos', (select coalesce(jsonb_agg(to_jsonb(fmt)),'[]') from fmt),
  'dias', (select coalesce(jsonb_agg(to_jsonb(dias)),'[]') from dias)
);
$$;
revoke all on function public.desempenho(text) from public;
grant execute on function public.desempenho(text) to anon, authenticated;;
