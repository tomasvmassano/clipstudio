-- 20261019171228 engine_schema (exportado do Supabase a 28/10/2026; segredos tapados)
create table public.reels (
  id text primary key, platform text, owner text, role text, url text, "timestamp" text,
  caption text default '', transcript text default '', hook text default '',
  views bigint default 0, likes bigint default 0, comments bigint default 0, shares bigint default 0,
  duration real default 0, outlier real, debate_idx real, share_idx real, heat real,
  first_seen timestamptz default now(), updated_at timestamptz default now(),
  fts tsvector generated always as (to_tsvector('simple', coalesce(transcript,'') || ' ' || coalesce(caption,''))) stored
);
create index ix_reels_owner on public.reels(owner);
create index ix_reels_heat on public.reels(heat desc nulls last);
create index ix_reels_fts on public.reels using gin(fts);

create table public.comment_analysis (
  reel_id text primary key references public.reels(id) on delete cascade,
  data jsonb, polarizacao real, ponto_de_fricao text, emocao text, analyzed_at timestamptz default now()
);

create table public.themes (
  id bigint generated always as identity primary key, tema text unique not null, categoria text, alvo text,
  porque_viraliza text, ponto_de_fricao text, hooks jsonb default '[]', formatos jsonb default '[]',
  heat_medio real, fit real, risco text, nota_risco text,
  client_posts int default 0, client_avg_outlier real, active boolean default true, updated_at timestamptz default now()
);

create table public.reel_themes (
  reel_id text references public.reels(id) on delete cascade,
  theme_id bigint references public.themes(id) on delete cascade,
  primary key (reel_id, theme_id)
);
create index ix_reel_themes_theme on public.reel_themes(theme_id);

create table public.meta (k text primary key, v jsonb);

create table public.generated (
  id bigint generated always as identity primary key, date date default current_date,
  theme_id bigint references public.themes(id) on delete set null,
  angulo text, hook text, guiao text, data jsonb, revisto text default '',
  status text default 'draft' check (status in ('draft','approved','rejected','posted')),
  posted_reel_id text references public.reels(id) on delete set null, match_score real
);
create index ix_gen_date on public.generated(date);
create index ix_gen_theme on public.generated(theme_id);
create index ix_gen_posted on public.generated(posted_reel_id);

alter table public.reels enable row level security;
alter table public.comment_analysis enable row level security;
alter table public.themes enable row level security;
alter table public.reel_themes enable row level security;
alter table public.meta enable row level security;
alter table public.generated enable row level security;

comment on table public.reels is 'Todos os clips scrapeados (referências + Numeiro). Acesso só via service role / ligação direta do motor.';
comment on table public.generated is 'Guiões gerados. status: draft -> approved/rejected (equipa) -> posted (auto via feedback).';

-- Vistas para a equipa usar no Table Editor
create view public.v_guioes_hoje with (security_invoker = true) as
  select g.id, g.status, t.tema, g.angulo, g.hook, g.guiao, g.data->>'texto_ecra' as texto_ecra,
         g.data->>'fecho_cta' as fecho_cta, g.data->>'legenda' as legenda,
         g.data->>'comentario_fixado' as comentario_fixado, g.data->>'cenario' as cenario
  from public.generated g left join public.themes t on t.id = g.theme_id
  where g.date = current_date order by t.tema, g.id;

create view public.v_top_reels with (security_invoker = true) as
  select r.owner, r.heat, r.outlier, r.debate_idx, r.views, r.comments, ca.polarizacao,
         ca.ponto_de_fricao, r.hook, r.url
  from public.reels r left join public.comment_analysis ca on ca.reel_id = r.id
  where r.heat is not null order by r.heat desc limit 200;

create view public.v_temas with (security_invoker = true) as
  select t.tema, t.categoria, t.alvo, t.heat_medio, t.fit, t.risco, t.client_posts,
         round(t.client_avg_outlier::numeric, 2) as numeiro_outlier,
         (select count(*) from public.reel_themes rt where rt.theme_id = t.id) as n_exemplos,
         t.porque_viraliza, t.ponto_de_fricao
  from public.themes t where t.active order by t.heat_medio desc nulls last;;
