-- Parte 1 de 3 de 20261030010100_w6_perf.sql (aplicada em produção como w6_perf_p1).
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
