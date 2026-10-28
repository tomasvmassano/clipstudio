-- 20261028110903 multi_agent_schema (exportado do Supabase a 28/10/2026; segredos tapados)
create table if not exists public.quotes (
  id bigint generated always as identity primary key,
  autor text not null, obra text, referencia text,
  texto_pt text not null unique,
  dominio_publico boolean default true,
  verificado boolean default false,
  tese_polemica text, categoria text, ultima_vez date, usos int default 0,
  created_at timestamptz default now()
);
create table if not exists public.agent_log (
  id bigint generated always as identity primary key,
  run_id text, slot int, agent text, model text,
  input jsonb, output jsonb, ms int, created_at timestamptz default now()
);
create index if not exists ix_agent_log_run on public.agent_log(run_id);
alter table public.generated add column if not exists formato text;
alter table public.generated add column if not exists critic_score real;
alter table public.generated add column if not exists critic_scores jsonb;
alter table public.generated add column if not exists revisoes int default 0;
alter table public.generated add column if not exists quote_id bigint references public.quotes(id) on delete set null;
alter table public.generated add column if not exists run_id text;
create index if not exists ix_gen_quote on public.generated(quote_id);
alter table public.quotes enable row level security;
alter table public.agent_log enable row level security;

create or replace view public.v_formatos with (security_invoker = true) as
  select g.formato, count(*) gerados, count(*) filter (where g.status='posted') publicados,
         round(avg(g.critic_score)::numeric,2) critic_medio,
         round((avg(r.outlier) filter (where g.status='posted'))::numeric,2) outlier_real
  from public.generated g left join public.reels r on r.id=g.posted_reel_id
  group by g.formato order by outlier_real desc nulls last;

drop view if exists public.v_guioes_hoje;
create view public.v_guioes_hoje with (security_invoker = true) as
  select g.id, g.status, g.formato, t.tema, g.critic_score, g.angulo, g.hook, g.guiao,
         g.data->>'texto_ecra' as texto_ecra, g.data->>'fecho_cta' as fecho_cta, g.data->>'legenda' as legenda,
         g.data->>'comentario_fixado' as comentario_fixado, g.data->>'cenario' as cenario,
         q.autor as citacao_autor, q.obra as citacao_obra
  from public.generated g left join public.themes t on t.id = g.theme_id left join public.quotes q on q.id=g.quote_id
  where g.date = current_date order by g.critic_score desc nulls last;;
