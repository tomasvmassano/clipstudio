-- W6 · Centro de desempenho (PRD §40: PERF-01..07) com origem de cada publicação (R-16) e linhagem gravada (R-18).
-- Expand: capacidade, flag, quatro tabelas e funções novas. Nada do que existe muda: o motor (numeiro-engine) continua a
-- escrever em reels/script_analysis/generated/themes e tudo aqui é derivado dessas tabelas e tolera dados em falta.
-- Métricas vêm do scraping (Apify) até haver APIs oficiais (R-19, PERF-08 adiado): o que o scraping não dá fica
-- "indisponível", nunca estimado. Rollback no fim.
--
-- Definições (ADR-0033):
--  * Publicação = reel de uma conta do cliente (accounts.role = 'client'). Referências nunca entram.
--  * Leitura = (views, likes, comentários, partilhas) num instante. perf_readings guarda uma por cada vez que o scraper
--    atualizou o reel (reels.updated_at); o estado atual de reels conta sempre como mais uma leitura.
--  * Fotografia à idade T (1 h, 24 h, 72 h, 7 d, 30 d) = a leitura mais próxima de published_at + T dentro de ±25% de T.
--    Sem leitura nessa janela não há fotografia (nunca se interpola).
--  * Índice à idade T = views à idade T ÷ mediana das views à idade T das publicações da MESMA conta publicadas nos 30 dias
--    anteriores. Base mínima: 5 publicações [pressuposto]; abaixo disso "amostra insuficiente". Nunca se somam nem
--    comparam views absolutas entre contas ou plataformas. YouTube: views do scraping (engagedViews só com a API oficial).
--  * "Vencedor" e alavancas medem-se às 72 h. Alavanca só com 15 publicações com índice [pressuposto, PRD 10-20].

insert into capabilities (key, module, risk, scopes, status, label) values
  ('analytics.manage', 'Desempenho', 'M', array['ws'], 'ativo', 'Corrigir dados de desempenho (camada, criador, estado da conta, origem)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'analytics.manage'), ('ws', 'workspace_admin', 'analytics.manage'), ('ws', 'manager', 'analytics.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('perf.center', 'Centro de desempenho', 'Desempenho', 'ws', 'owner',
   'Fotografias por idade, índice normalizado por conta, vistas por atributo, origem e linhagem de cada publicação e alavancas "o que replicar" (PRD §40).')
on conflict do nothing;

-- PERF-01: camada e criador/marca de cada conta do cliente; estado da conta registado à mão (PERF-05 saúde).
create table if not exists public.perf_accounts (
  account_id text primary key references public.accounts(id),
  workspace_id text not null references public.clients(id),
  tier text check (tier is null or tier in ('A', 'B', 'C', 'D')),
  creator text check (creator is null or char_length(creator) between 1 and 80),
  health_state text not null default 'sem_registo' check (health_state in ('sem_registo', 'normal', 'alcance_reduzido', 'restrita', 'suspensa')),
  health_note text check (health_note is null or char_length(health_note) <= 500),
  health_set_at timestamptz,
  health_set_label text,
  updated_at timestamptz not null default now()
);
create index if not exists perf_accounts_ws on public.perf_accounts (workspace_id);

-- PERF-03/PERF-09: várias leituras por publicação (só de acrescentar).
create table if not exists public.perf_readings (
  workspace_id text not null references public.clients(id),
  reel_id text not null,
  captured_at timestamptz not null,
  views bigint, likes bigint, comments bigint, shares bigint,
  source text not null default 'scraper' check (source in ('scraper', 'api', 'manual')),
  inserted_at timestamptz not null default now(),
  primary key (workspace_id, reel_id, captured_at),
  foreign key (workspace_id, reel_id) references public.reels(client_id, id) on delete cascade
);

-- R-16 + R-18 + PERF-02: uma linha por publicação. 'gravada' = escrita pelo publicador no momento (imutável, só a origem
-- se corrige com auditoria); 'inferida' = importada, ligada por inferência e marcada como tal.
create table if not exists public.publication_lineage (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  account_id text not null references public.accounts(id),
  platform text not null,
  external_id text not null check (char_length(external_id) between 1 and 200),
  url text check (url is null or char_length(url) <= 1000),
  published_at timestamptz,
  origin text not null check (origin in ('sistema', 'externo')),
  origin_source text not null check (origin_source in ('publicador', 'correspondencia', 'importacao', 'manual')),
  origin_reason text check (origin_reason is null or char_length(origin_reason) <= 500),
  lineage_mode text not null check (lineage_mode in ('gravada', 'inferida')),
  inference_source text check (inference_source is null or inference_source in ('publicacoes', 'motor', 'analise', 'nenhuma')),
  inference_confidence numeric check (inference_confidence is null or inference_confidence between 0 and 1),
  content_id text references public.guioes(id) on delete set null,
  content_version_id uuid references public.content_versions(id),
  version_no int,
  hook_index int check (hook_index is null or hook_index between 0 and 9),
  hook_text text check (hook_text is null or char_length(hook_text) <= 500),
  hook_mechanism text check (hook_mechanism is null or hook_mechanism in ('contra', 'numero', 'ego', 'confissao', 'segredo', 'pergunta')),
  formato text check (formato is null or char_length(formato) <= 60),
  maquina text check (maquina is null or char_length(maquina) <= 60),
  tema text check (tema is null or char_length(tema) <= 300),
  edit_style_key text,
  edit_style_version int,
  persona_phrase text check (persona_phrase is null or char_length(persona_phrase) <= 200),
  asset_ref text check (asset_ref is null or char_length(asset_ref) <= 500),
  duration_s numeric check (duration_s is null or duration_s between 0 and 36000),
  source_type text check (source_type is null or source_type in ('guiao', 'fonte_longa', 'telemovel', 'lifestyle')),
  generation int check (generation is null or generation between 0 and 100),
  parent_lineage_id bigint references public.publication_lineage(id),
  tier text check (tier is null or tier in ('A', 'B', 'C', 'D')),
  local_tz text,
  local_hour int check (local_hour is null or local_hour between 0 and 23),
  correlation_id text check (correlation_id is null or char_length(correlation_id) <= 200),
  recorded_at timestamptz not null default now(),
  recorded_kind text not null,
  recorded_label text,
  updated_at timestamptz not null default now(),
  unique (workspace_id, account_id, external_id)
);
create index if not exists publication_lineage_content on public.publication_lineage (workspace_id, content_id) where content_id is not null;

alter table public.perf_accounts enable row level security;
alter table public.perf_readings enable row level security;
alter table public.publication_lineage enable row level security;
revoke all on public.perf_accounts, public.perf_readings, public.publication_lineage from anon, authenticated;   -- só pelas RPCs

-- Linhagem gravada é imutável: só origem (com motivo) e updated_at mudam; não se apaga.
create or replace function public.perf_lineage_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.lineage_mode = 'gravada' then raise exception 'linhagem_imutavel' using errcode = '42501'; end if;
    return old;
  end if;
  if old.lineage_mode = 'gravada' and
     (to_jsonb(new) - array['origin', 'origin_source', 'origin_reason', 'updated_at']) is distinct from
     (to_jsonb(old) - array['origin', 'origin_source', 'origin_reason', 'updated_at']) then
    raise exception 'linhagem_imutavel' using errcode = '42501', detail = 'A linhagem gravada no momento da publicação não se altera (R-18).';
  end if;
  return new;
end $$;
drop trigger if exists publication_lineage_guard on public.publication_lineage;
create trigger publication_lineage_guard before update or delete on public.publication_lineage for each row execute function public.perf_lineage_guard();

-- Limiares num só sítio (devolvidos à UI para os explicar). Todos [pressuposto] a calibrar com dados próprios.
create or replace function public._perf_params() returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'ages', jsonb_build_array('1h', '24h', '72h', '7d', '30d'),
    'tolerance', 0.25,          -- janela de cada fotografia: ±25% da idade
    'min_base', 5,              -- publicações da mesma conta nos 30 dias anteriores para haver índice
    'min_sample', 15,           -- publicações com índice para mostrar uma alavanca (PRD: 10-20)
    'winner_age', '72h',
    'near_zero', 0.1,           -- "perto de zero": índice às 72 h abaixo de 0,1
    'drop_ratio', 0.6,          -- mediana a cair: mediana 72 h dos últimos 7 d < 60% da dos 30 d anteriores
    'cut_below', 0.8)           -- estilo a cortar: índice mediano abaixo de 0,8 com amostra mínima
$$;

create or replace function public._perf_age_seconds(p_age text) returns int
language sql immutable as $$
  select case p_age when '1h' then 3600 when '24h' then 86400 when '72h' then 259200 when '7d' then 604800 when '30d' then 2592000 end
$$;

create or replace function public._perf_ts(p text) returns timestamptz
language plpgsql stable as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  return p::timestamptz;
exception when others then return null;
end $$;

create or replace function public._perf_mech(p text) returns text
language sql immutable as $$
  select case when m in ('contra', 'numero', 'ego', 'confissao', 'segredo', 'pergunta') then m end
  from (select translate(lower(btrim(coalesce(p, ''))), 'áàãâéêíóõôúç', 'aaaaeeiooouc') m) x
$$;

-- Inferência para publicações importadas (nunca gravada): 1) publicacoes (reel ligado a um guião), 2) motor (generated,
-- correspondência por transcrição com match_score), 3) análise do motor (script_analysis, reel_themes). Hook: o hook do
-- guião cujo início coincide com o início do reel.
create or replace function public._perf_inferred(p_ws text)
returns table (reel_id text, account_id text, platform text, url text, published_at timestamptz, duration_s numeric,
  inference_source text, inference_confidence numeric, content_id text, content_version_id uuid, version_no int,
  hook_index int, hook_text text, hook_mechanism text, formato text, maquina text, tema text, source_type text)
language sql stable security definer set search_path = public as $$
  select r.id, r.account_id, a.platform, r.url, coalesce(r.taken_at, public._perf_ts(r."timestamp")), nullif(r.duration, 0)::numeric,
    case when gu.id is not null then 'publicacoes' when gen.found then 'motor' when sa.reel_id is not null or th.tema is not null then 'analise' else 'nenhuma' end,
    case when gu.id is not null then 0.9 when gen.found then least(1, greatest(0, coalesce(gen.match_score, 0)))::numeric end,
    gu.id, cv.id, cv.version_no,
    hk.idx, left(coalesce(hk.txt, nullif(gen.hook, ''), nullif(sa.hook, ''), nullif(r.hook, '')), 500), public._perf_mech(hk.mec),
    left(coalesce(gu.formato, gen.formato, sa.formato_norm, sa.formato), 60), left(gu.maquina, 60), left(coalesce(gu.tema, gen.tema, th.tema), 300),
    case when gu.id is not null then 'guiao' end
  from reels r
  join accounts a on a.id = r.account_id and a.client_id = r.client_id and a.role = 'client'
  left join lateral (select p.guiao_id from publicacoes p where p.reel_id = r.id and p.account_id = r.account_id and p.guiao_id is not null
                     order by p.updated_at desc limit 1) pl on true
  left join guioes gu on gu.id = pl.guiao_id and gu.client_id = r.client_id
  left join content_versions cv on cv.id = coalesce(gu.approved_version_id, gu.current_version_id)
  left join lateral (select (h.ord - 1)::int idx, h.e->>'text' txt, h.e->>'mecanismo' mec
                     from jsonb_array_elements(case when jsonb_typeof(gu.hooks) = 'array' then gu.hooks else '[]' end) with ordinality h(e, ord)
                     where char_length(coalesce(h.e->>'text', '')) >= 12
                       and left(lower(coalesce(nullif(r.hook, ''), r.transcript, '')), least(25, char_length(h.e->>'text'))) = lower(left(h.e->>'text', 25))
                     order by h.ord limit 1) hk on true
  left join lateral (select true found, g.formato, t.tema, g.hook, g.match_score from generated g
                     left join themes t on t.client_id = g.client_id and t.id = g.theme_id
                     where g.client_id = r.client_id and g.posted_reel_id = r.id order by g.match_score desc nulls last limit 1) gen on true
  left join script_analysis sa on sa.client_id = r.client_id and sa.reel_id = r.id
  left join lateral (select t.tema from reel_themes rt join themes t on t.client_id = rt.client_id and t.id = rt.theme_id
                     where rt.client_id = r.client_id and rt.reel_id = r.id order by t.id limit 1) th on true
  where r.client_id = p_ws
$$;

-- Todas as publicações do cliente com etiquetas (gravadas quando existem, senão inferidas) e a última leitura.
create or replace function public._perf_pubs(p_ws text)
returns table (reel_id text, lineage_id bigint, account_id text, platform text, handle text, tier text, creator text,
  url text, title text, published_at timestamptz, duration_s numeric, views bigint, likes bigint, comments bigint, shares bigint,
  last_read_at timestamptz, origin text, origin_source text, lineage_mode text, inference_source text, inference_confidence numeric,
  content_id text, version_no int, hook_index int, hook_text text, hook_mechanism text, formato text, maquina text, tema text,
  edit_style_key text, edit_style_version int, persona_phrase text, source_type text, generation int, local_hour int)
language sql stable security definer set search_path = public as $$
  with c as (select coalesce(timezone, 'Asia/Dubai') tz, name from clients where id = p_ws),
  base as (
    select i.*, r.views, r.likes, r.comments, r.shares, r.updated_at, left(coalesce(nullif(r.hook, ''), nullif(r.caption, ''), r.id), 110) title,
           l.id lid, l.lineage_mode lmode, l.origin lorigin, l.origin_source lsource, l.published_at lpub, l.duration_s ldur,
           l.content_id lcontent, l.version_no lver, l.hook_index lhi, l.hook_text lht, l.hook_mechanism lhm, l.formato lfmt, l.maquina lmaq,
           l.tema ltema, l.edit_style_key lstyle, l.edit_style_version lstylev, l.persona_phrase lpersona, l.source_type lsrc, l.generation lgen,
           l.tier ltier, l.local_hour lhour
    from public._perf_inferred(p_ws) i
    join reels r on r.client_id = p_ws and r.id = i.reel_id
    left join publication_lineage l on l.workspace_id = p_ws and l.account_id = i.account_id and l.external_id = i.reel_id
  )
  select b.reel_id, b.lid, b.account_id, b.platform, a.handle, case when b.lmode = 'gravada' then b.ltier else pa.tier end,
    coalesce(pa.creator, (select name from c)), b.url, b.title,
    case when b.lmode = 'gravada' then coalesce(b.lpub, b.published_at) else b.published_at end,
    case when b.lmode = 'gravada' then coalesce(b.ldur, b.duration_s) else b.duration_s end,
    b.views, b.likes, b.comments, b.shares, b.updated_at,
    coalesce(b.lorigin, 'externo'), coalesce(b.lsource, 'importacao'), coalesce(b.lmode, 'inferida'),
    case when b.lmode = 'gravada' then null else b.inference_source end, case when b.lmode = 'gravada' then null else b.inference_confidence end,
    case when b.lmode = 'gravada' then b.lcontent else b.content_id end, case when b.lmode = 'gravada' then b.lver else b.version_no end,
    case when b.lmode = 'gravada' then b.lhi else b.hook_index end, case when b.lmode = 'gravada' then b.lht else b.hook_text end,
    case when b.lmode = 'gravada' then b.lhm else b.hook_mechanism end, case when b.lmode = 'gravada' then b.lfmt else b.formato end,
    case when b.lmode = 'gravada' then b.lmaq else b.maquina end, case when b.lmode = 'gravada' then b.ltema else b.tema end,
    case when b.lmode = 'gravada' then b.lstyle end, case when b.lmode = 'gravada' then b.lstylev end,
    case when b.lmode = 'gravada' then b.lpersona end, case when b.lmode = 'gravada' then b.lsrc else b.source_type end,
    case when b.lmode = 'gravada' then b.lgen end,
    case when b.lmode = 'gravada' and b.lhour is not null then b.lhour
         else extract(hour from (case when b.lmode = 'gravada' then coalesce(b.lpub, b.published_at) else b.published_at end) at time zone (select tz from c))::int end
  from base b
  join accounts a on a.id = b.account_id
  left join perf_accounts pa on pa.account_id = b.account_id and pa.workspace_id = p_ws
$$;

-- PERF-03: fotografias por idade (uma por publicação e idade, a leitura mais próxima dentro de ±25%).
create or replace function public._perf_snapshots(p_ws text)
returns table (reel_id text, account_id text, published_at timestamptz, age text, age_s int, captured_at timestamptz,
  views bigint, likes bigint, comments bigint, shares bigint)
language sql stable security definer set search_path = public as $$
  with p as (
    select r.id reel_id, r.account_id, coalesce(r.taken_at, public._perf_ts(r."timestamp")) published_at
    from reels r join accounts a on a.id = r.account_id and a.client_id = r.client_id and a.role = 'client'
    where r.client_id = p_ws
  ),
  rd as (
    select x.reel_id, x.captured_at, x.views, x.likes, x.comments, x.shares from perf_readings x where x.workspace_id = p_ws
    union
    select r.id, r.updated_at, r.views, r.likes, r.comments, r.shares from reels r where r.client_id = p_ws and r.updated_at is not null
  ),
  ages(age, s) as (values ('1h', 3600), ('24h', 86400), ('72h', 259200), ('7d', 604800), ('30d', 2592000)),
  cand as (
    select p.reel_id, p.account_id, p.published_at, ages.age, ages.s, rd.captured_at, rd.views, rd.likes, rd.comments, rd.shares,
           row_number() over (partition by p.reel_id, ages.age
                              order by abs(extract(epoch from rd.captured_at - p.published_at) - ages.s), rd.captured_at) rn
    from p join rd on rd.reel_id = p.reel_id cross join ages
    where p.published_at is not null
      and extract(epoch from rd.captured_at - p.published_at) between ages.s * 0.75 and ages.s * 1.25
  )
  select reel_id, account_id, published_at, age, s, captured_at, views, likes, comments, shares from cand where rn = 1
$$;

-- PERF-04: índice normalizado por idade. Base = mesma conta, mesma idade, publicadas nos 30 dias anteriores.
create or replace function public._perf_index(p_ws text)
returns table (reel_id text, account_id text, published_at timestamptz, age text, views bigint, base_n int, base_median numeric, idx numeric)
language sql stable security definer set search_path = public as $$
  with s as (select * from public._perf_snapshots(p_ws)),
  m as (select (public._perf_params()->>'min_base')::int min_base)
  select s.reel_id, s.account_id, s.published_at, s.age, s.views, b.n, b.med,
    case when b.n >= (select min_base from m) and b.med > 0 and s.views is not null then round(s.views / b.med, 3) end
  from s
  left join lateral (select count(q.views)::int n, percentile_cont(0.5) within group (order by q.views)::numeric med
                     from s q where q.account_id = s.account_id and q.age = s.age and q.reel_id <> s.reel_id
                       and q.published_at >= s.published_at - interval '30 days' and q.published_at < s.published_at) b on true
$$;

-- PERF-05: famílias de métricas e o que a fonte atual (scraping) dá. O que não dá fica indisponível, nunca estimado.
create or replace function public._perf_families() returns jsonb
language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'alcance', 'label', 'Alcance', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'views', 'label', 'Views', 'available', true, 'note', 'No YouTube são as views do scraping; engagedViews só com a API oficial.'),
      jsonb_build_object('key', 'reach', 'label', 'Alcance (contas únicas)', 'available', false),
      jsonb_build_object('key', 'non_followers', 'label', '% não seguidores / For You', 'available', false))),
    jsonb_build_object('key', 'hook', 'label', 'Hook', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'skip_rate', 'label', 'Taxa de saltos (IG reels_skip_rate)', 'available', false),
      jsonb_build_object('key', 'view_rate_3s', 'label', 'Visto mais de 3 s', 'available', false),
      jsonb_build_object('key', 'early_retention', 'label', 'Retenção inicial', 'available', false))),
    jsonb_build_object('key', 'retencao', 'label', 'Retenção', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'avg_watched', 'label', '% médio visto', 'available', false),
      jsonb_build_object('key', 'completion', 'label', '% até ao fim', 'available', false))),
    jsonb_build_object('key', 'ressonancia', 'label', 'Ressonância', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'comments_pk', 'label', 'Comentários por 1.000 views', 'available', true),
      jsonb_build_object('key', 'likes_pk', 'label', 'Gostos por 1.000 views', 'available', true),
      jsonb_build_object('key', 'shares_pk', 'label', 'Partilhas por 1.000 views', 'available', 'conta', 'note', 'Só quando a recolha da plataforma devolve partilhas.'),
      jsonb_build_object('key', 'saves_pk', 'label', 'Guardados por 1.000 views', 'available', false))),
    jsonb_build_object('key', 'crescimento', 'label', 'Crescimento', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'followers_pk', 'label', 'Seguidores por 1.000 views', 'available', false))),
    jsonb_build_object('key', 'saude', 'label', 'Saúde da conta', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'median_drop', 'label', 'Mediana a cair', 'available', true),
      jsonb_build_object('key', 'near_zero', 'label', '% de posts perto de zero', 'available', true),
      jsonb_build_object('key', 'for_you_drop', 'label', '% For You a cair', 'available', false),
      jsonb_build_object('key', 'manual_state', 'label', 'Estado registado à mão', 'available', true))),
    jsonb_build_object('key', 'eficiencia', 'label', 'Eficiência', 'metrics', jsonb_build_array(
      jsonb_build_object('key', 'cost_per_video', 'label', 'Custo por vídeo', 'available', false, 'reason', 'Custo por vídeo ainda não é atribuído (BIZ-06).'),
      jsonb_build_object('key', 'cost_per_k', 'label', 'Custo por 1.000 views', 'available', false, 'reason', 'Custo por vídeo ainda não é atribuído (BIZ-06).'))))
$$;

-- Filtros comuns: {account, platform, origin: 'sistema'|'externo'|null, days}
create or replace function public._perf_match(p jsonb, f jsonb) returns boolean
language sql stable as $$
  select (nullif(f->>'account', '') is null or p->>'account_id' = f->>'account')
     and (nullif(f->>'platform', '') is null or p->>'platform' = f->>'platform')
     and (nullif(f->>'origin', '') is null or p->>'origin' = f->>'origin')
     and (nullif(f->>'days', '') is null or ((p->>'published_at')::timestamptz >= now() - make_interval(days => least(3650, greatest(1, (f->>'days')::int)))))
$$;

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

-- R-16: corrigir a origem à mão (motivo obrigatório, auditado).
create or replace function public.perf_origin_set(p_ws text, p_account text, p_external_id text, p_origin text, p_reason text, p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); l publication_lineage;
begin
  perform public._content_require('analytics.manage', p_ws, p_token, 'perf.origin_set', p_external_id);
  if p_origin not in ('sistema', 'externo') then raise exception 'origem_invalida' using errcode = '22023', detail = 'Origem: sistema ou externo.'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 500 then
    raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Explica porque mudas a origem (3 a 500 caracteres).'; end if;
  if not exists (select 1 from accounts where id = p_account and client_id = p_ws and role = 'client') then
    raise exception 'conta_nao_encontrada' using errcode = 'P0002'; end if;
  select * into l from publication_lineage where workspace_id = p_ws and account_id = p_account and external_id = p_external_id for update;
  if l.id is null then
    if not exists (select 1 from reels where client_id = p_ws and id = p_external_id and account_id = p_account) then
      raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
    perform public.perf_sync_lineage(p_ws);
    select * into l from publication_lineage where workspace_id = p_ws and account_id = p_account and external_id = p_external_id for update;
  end if;
  update publication_lineage set origin = p_origin, origin_source = 'manual', origin_reason = btrim(p_reason), updated_at = now() where id = l.id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'perf.origin_set', 'publication', p_account || '/' || p_external_id,
          jsonb_build_object('origin', l.origin, 'origin_source', l.origin_source),
          jsonb_build_object('origin', p_origin, 'origin_source', 'manual', 'reason', btrim(p_reason)));
  return (select to_jsonb(x) - 'workspace_id' from publication_lineage x where id = l.id);
end $$;

-- R-18: o publicador grava a linhagem no momento da publicação. Valida tudo contra o próprio cliente; idempotente por
-- (conta, id externo): repetir devolve a linha existente sem duplicar. Uso interno (publicador com service_role) e RPC.
create or replace function public._perf_record_lineage(p_ws text, p jsonb, p_actor jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare acc accounts; g guioes; cv content_versions; l publication_lineage; parent publication_lineage; st edit_style_versions;
  ext text := btrim(coalesce(p->>'external_id', '')); hi int; mech text; tz text; pub timestamptz; created boolean := false;
begin
  if jsonb_typeof(coalesce(p, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  select * into acc from accounts where id = p->>'account_id' and client_id = p_ws and role = 'client';
  if acc.id is null then raise exception 'conta_nao_encontrada' using errcode = '22023', detail = 'A conta não é deste cliente.'; end if;
  if ext = '' or char_length(ext) > 200 then raise exception 'id_externo_invalido' using errcode = '22023'; end if;
  select * into l from publication_lineage where workspace_id = p_ws and account_id = acc.id and external_id = ext for update;
  if l.lineage_mode = 'gravada' then
    return (to_jsonb(l) - 'workspace_id') || jsonb_build_object('created', false);
  end if;
  select * into g from guioes where id = p->>'content_id' and client_id = p_ws;
  if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = '22023', detail = 'O conteúdo não é deste cliente.'; end if;
  select * into cv from content_versions where id = nullif(p->>'content_version_id', '')::uuid and content_id = g.id and workspace_id = p_ws;
  if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Indica a versão exata que foi publicada.'; end if;
  hi := nullif(p->>'hook_index', '')::int;
  if hi is not null and (hi < 0 or hi >= jsonb_array_length(cv.hooks)) then raise exception 'hook_invalido' using errcode = '22023'; end if;
  mech := coalesce(p->>'hook_mechanism', case when hi is not null then cv.hooks->hi->>'mecanismo' end);
  if nullif(btrim(coalesce(p->>'hook_mechanism', '')), '') is not null and public._perf_mech(mech) is null then
    raise exception 'mecanismo_invalido' using errcode = '22023', detail = 'Mecanismos: contra, numero, ego, confissao, segredo, pergunta.'; end if;
  if p ? 'edit_style_key' and nullif(p->>'edit_style_key', '') is not null then
    select * into st from edit_style_versions where workspace_id = p_ws and key = p->>'edit_style_key' and version = nullif(p->>'edit_style_version', '')::int;
    if st.key is null then raise exception 'estilo_invalido' using errcode = '22023', detail = 'Estilo e versão têm de existir neste cliente.'; end if;
  end if;
  if coalesce(p->>'source_type', 'guiao') not in ('guiao', 'fonte_longa', 'telemovel', 'lifestyle') then raise exception 'tipo_fonte_invalido' using errcode = '22023'; end if;
  if nullif(p->>'parent_lineage_id', '') is not null then
    select * into parent from publication_lineage where id = (p->>'parent_lineage_id')::bigint and workspace_id = p_ws;
    if parent.id is null then raise exception 'origem_republicacao_invalida' using errcode = '22023'; end if;
  end if;
  pub := coalesce(nullif(p->>'published_at', '')::timestamptz, now());
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
  if l.id is not null then delete from publication_lineage where id = l.id; end if;   -- a inferida dá lugar à gravada
  insert into publication_lineage (workspace_id, account_id, platform, external_id, url, published_at, origin, origin_source, lineage_mode,
    content_id, content_version_id, version_no, hook_index, hook_text, hook_mechanism, formato, maquina, tema, edit_style_key, edit_style_version,
    persona_phrase, asset_ref, duration_s, source_type, generation, parent_lineage_id, tier, local_tz, local_hour, correlation_id,
    recorded_kind, recorded_label)
  values (p_ws, acc.id, acc.platform, ext, left(p->>'url', 1000), pub, 'sistema', 'publicador', 'gravada',
    g.id, cv.id, cv.version_no, hi, left(coalesce(case when hi is not null then cv.hooks->hi->>'text' end, p->>'hook_text'), 500), public._perf_mech(mech),
    left(coalesce(cv.formato, g.formato), 60), left(g.maquina, 60), left(coalesce(cv.tema, g.tema), 300), st.key, st.version,
    nullif(left(p->>'persona_phrase', 200), ''), nullif(left(p->>'asset_ref', 500), ''), nullif(p->>'duration_s', '')::numeric,
    coalesce(p->>'source_type', 'guiao'), case when parent.id is not null then coalesce(parent.generation, 0) + 1 else coalesce(nullif(p->>'generation', '')::int, 0) end,
    parent.id, (select tier from perf_accounts where account_id = acc.id), tz, extract(hour from pub at time zone tz)::int,
    nullif(left(p->>'correlation_id', 200), ''), coalesce(p_actor->>'kind', 'system'), p_actor->>'label')
  returning * into l;
  created := true;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((p_actor->>'uid')::uuid, coalesce(p_actor->>'kind', 'system'), p_actor->>'label', p_ws, 'perf.lineage_recorded', 'publication',
          acc.id || '/' || ext, null, to_jsonb(l) - 'workspace_id', l.correlation_id);
  return (to_jsonb(l) - 'workspace_id') || jsonb_build_object('created', created);
end $$;

create or replace function public.perf_record_lineage(p_ws text, p_lineage jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token);
begin
  perform public._content_require('publishing.publish', p_ws, p_token, 'perf.lineage_record', p_lineage->>'external_id');
  return public._perf_record_lineage(p_ws, p_lineage, a);
end $$;

-- Recolha: guarda uma leitura por cada atualização do scraper (reels.updated_at). Idempotente. Corre de hora a hora.
create or replace function public.perf_capture(p_ws text) returns int
language sql security definer set search_path = public as $$
  with ins as (
    insert into perf_readings (workspace_id, reel_id, captured_at, views, likes, comments, shares, source)
    select r.client_id, r.id, r.updated_at, r.views, r.likes, r.comments, r.shares, 'scraper'
    from reels r join accounts a on a.id = r.account_id and a.client_id = r.client_id and a.role = 'client'
    where r.client_id = p_ws and r.updated_at is not null
    on conflict do nothing returning 1)
  select count(*)::int from ins
$$;

create or replace function public.perf_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record; res jsonb := '{}';
begin
  for c in select id from clients where status = 'active' order by id loop
    begin
      res := res || jsonb_build_object(c.id, jsonb_build_object('readings', public.perf_capture(c.id), 'lineage', public.perf_sync_lineage(c.id)));
    exception when others then
      raise log 'perf_tick_failed %', jsonb_build_object('workspace_id', c.id, 'error', sqlerrm);
      res := res || jsonb_build_object(c.id, jsonb_build_object('error', sqlstate));
    end;
  end loop;
  return res;
end $$;

create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'perf-tick') then
    perform cron.schedule('perf-tick', '17 * * * *', 'select public.perf_tick()');
  end if;
end $$;

revoke all on function public.perf_lineage_guard(), public._perf_params(), public._perf_age_seconds(text), public._perf_ts(text), public._perf_mech(text),
  public._perf_inferred(text), public._perf_pubs(text), public._perf_snapshots(text), public._perf_index(text), public._perf_families(),
  public._perf_match(jsonb, jsonb), public._perf_rows(text), public._perf_record_lineage(text, jsonb, jsonb),
  public.perf_sync_lineage(text), public.perf_capture(text), public.perf_tick() from public, anon, authenticated;
grant execute on function public._perf_record_lineage(text, jsonb, jsonb), public.perf_sync_lineage(text), public.perf_capture(text), public.perf_tick()
  to service_role;
revoke all on function public.perf_center(text, text), public.perf_publications(text, jsonb, text), public.perf_breakdown(text, text, text, jsonb, text),
  public.perf_levers(text, boolean, text), public.perf_account_set(text, text, jsonb, text),
  public.perf_origin_set(text, text, text, text, text, text), public.perf_record_lineage(text, jsonb, text) from public;
grant execute on function public.perf_center(text, text), public.perf_publications(text, jsonb, text), public.perf_breakdown(text, text, text, jsonb, text),
  public.perf_levers(text, boolean, text), public.perf_account_set(text, text, jsonb, text),
  public.perf_origin_set(text, text, text, text, text, text), public.perf_record_lineage(text, jsonb, text) to anon, authenticated;

/* Rollback (compatível, nada do que existia mudou):
   select cron.unschedule('perf-tick');
   drop function public.perf_tick(), public.perf_capture(text), public.perf_record_lineage(text, jsonb, text), public._perf_record_lineage(text, jsonb, jsonb),
     public.perf_origin_set(text, text, text, text, text, text), public.perf_sync_lineage(text), public.perf_account_set(text, text, jsonb, text),
     public.perf_levers(text, boolean, text), public.perf_breakdown(text, text, text, jsonb, text), public.perf_publications(text, jsonb, text),
     public.perf_center(text, text), public._perf_rows(text), public._perf_match(jsonb, jsonb), public._perf_families(), public._perf_index(text),
     public._perf_snapshots(text), public._perf_pubs(text), public._perf_inferred(text), public._perf_mech(text), public._perf_ts(text),
     public._perf_age_seconds(text), public._perf_params();
   delete from feature_flags where key = 'perf.center'; delete from feature_flag_defs where key = 'perf.center';
   delete from role_capabilities where capability = 'analytics.manage'; update capabilities set status = 'W6' where key = 'analytics.manage';
-- contract posterior (só depois de o código deixar de depender): drop table public.publication_lineage, public.perf_readings, public.perf_accounts;
   drop function public.perf_lineage_guard(); */
