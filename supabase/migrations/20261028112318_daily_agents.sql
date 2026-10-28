-- 20261028112318 daily_agents (exportado do Supabase a 28/10/2026; segredos tapados)
create table if not exists public.ideas (
  id bigint generated always as identity primary key,
  created_at timestamptz default now(), agent text, run_id text,
  fonte_tipo text check (fonte_tipo in ('livro','reel','noticia','comentario')),
  titulo text, fonte text, fonte_url text, categoria text, formato_sugerido text,
  urgencia text, data jsonb, status text default 'nova' check (status in ('nova','usada','rejeitada')),
  expira_em date, used_at timestamptz
);
create index if not exists ix_ideas_open on public.ideas(status, expira_em);
create table if not exists public.daily_reports (
  id bigint generated always as identity primary key,
  data date not null, created_at timestamptz default now(), report jsonb not null
);
create index if not exists ix_daily_reports_data on public.daily_reports(data desc);
alter table public.ideas enable row level security;
alter table public.daily_reports enable row level security;

create or replace view public.v_ideias_abertas with (security_invoker = true) as
  select id, created_at::date dia, agent, fonte_tipo, urgencia, titulo, data->>'take_numeiro' take_numeiro,
         data->>'porque_comentam' porque_comentam, fonte, fonte_url, expira_em
  from public.ideas where status='nova' and (expira_em is null or expira_em >= current_date)
  order by case urgencia when 'hoje' then 0 when 'semana' then 1 else 2 end, created_at desc;;
