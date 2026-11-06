-- W10-04 · Referências por link (PRD §45, CHG-005): REF-01 colar link, REF-02 dissecção visível, REF-03 3 guiões por link
-- com 3 hooks cada, REF-04 via rápida (marcação). Também FR-07-01 e FR-07-04. AGENTS §7 (proveniência), R-17, R-20; ADR-0059.
-- Expand (só aditivo, compatível com o código em main e com o worker atual):
--   * capacidades references.analyze e references.adapt; flag references.link (equipa da agência por defeito);
--   * reference_items.ref_key (identidade do vídeo: instagram:<shortcode> / tiktok:<id>) com índice único parcial;
--     o preenchimento das linhas antigas salta repetidos já existentes (ficam com ref_key nulo, nada se apaga);
--   * agent_jobs.kind aceita mais dois valores (reference_analysis, reference_scripts): o worker em produção pede os
--     tipos pelo nome, por isso não os apanha até ser atualizado (os pedidos ficam em fila, visíveis);
--   * tabelas novas reference_analyses (versões imutáveis da dissecção) e reference_script_outputs (guiões gerados);
--   * RPCs novas reference_paste, reference_analyze, reference_adapt, reference_analysis_get; worker_reference_context,
--     worker_reference_save, worker_reference_save_script (engine_worker); reference_create e _reference_row reescritas
--     com a mesma assinatura (deteção de repetidos por ref_key; resumo da dissecção na linha).
-- Rollback: bloco no fim.

-- ───────────── capacidades e flag ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('references.analyze', 'Referências', 'M', array['org','ws'], 'ativo', 'Pedir ao motor a dissecção de uma referência (REF-02; gasta orçamento de IA)'),
  ('references.adapt', 'Referências', 'M', array['org','ws'], 'ativo', 'Pedir ao motor 3 guiões adaptados a partir de uma referência (REF-03; gasta orçamento de IA)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes, risk = excluded.risk;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'references.analyze'), ('ws', 'workspace_admin', 'references.analyze'), ('ws', 'manager', 'references.analyze'),
  ('ws', 'workspace_owner', 'references.adapt'), ('ws', 'workspace_admin', 'references.adapt'), ('ws', 'manager', 'references.adapt')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('references.link', 'Referências por link (colar, dissecar, 3 guiões)', 'Referências', 'ws', 'agency',
   'Colar um link de Reel ou TikTok, dissecção pelo motor e 3 guiões adaptados em via rápida (PRD §45, REF-01..04). Precisa do worker atualizado.')
on conflict do nothing;

-- ───────────── identidade do vídeo (REF-01) ─────────────
-- instagram.com/(<user>/)?(reel|reels|p|tv)/<shortcode>  -> instagram:<shortcode> (o shortcode distingue maiúsculas)
-- tiktok.com/@<user>/(video|photo)/<id>, /v/<id>, /embed/(v2/)?<id>  -> tiktok:<id>
-- Links curtos (vm./vt.tiktok.com) só se resolvem com rede: ficam sem ref_key e a deteção usa o link normalizado.
create or replace function public.reel_ref_key(p text) returns text language plpgsql immutable set search_path = public as $$
declare m text[];
begin
  if p is null or btrim(p) = '' then return null; end if;
  m := regexp_match(p, '^\s*(?:https?://)?(?:www\.|m\.)?instagram\.com/(?:[A-Za-z0-9._]{1,30}/)?(?:reel|reels|p|tv)/([A-Za-z0-9_-]{5,40})', 'i');
  if m is not null then return 'instagram:' || m[1]; end if;
  m := regexp_match(p, '^\s*(?:https?://)?(?:www\.|m\.)?tiktok\.com/(?:@[A-Za-z0-9._-]{1,40}/(?:video|photo)/|v/|embed/(?:v2/)?)([0-9]{6,25})', 'i');
  if m is not null then return 'tiktok:' || m[1]; end if;
  return null;
end $$;

-- Autor quando vem no link (TikTok sempre; Instagram só no formato instagram.com/<user>/reel/...).
create or replace function public._reel_url_author(p text) returns text language sql immutable set search_path = public as $$
  select coalesce(
    (regexp_match(p, 'tiktok\.com/@([A-Za-z0-9._-]{1,40})/', 'i'))[1],
    nullif((regexp_match(p, 'instagram\.com/([A-Za-z0-9._]{1,30})/(?:reel|reels|p|tv)/', 'i'))[1], 'reel'))
$$;

alter table public.reference_items add column if not exists ref_key text;
-- Preenche as linhas antigas, a mais antiga de cada vídeo primeiro; um repetido já existente fica com ref_key nulo.
do $$
declare r record;
begin
  for r in select id, workspace_id, public.reel_ref_key(url) k from reference_items where ref_key is null and public.reel_ref_key(url) is not null order by id loop
    if not exists (select 1 from reference_items where workspace_id = r.workspace_id and ref_key = r.k) then
      update reference_items set ref_key = r.k where id = r.id;
    end if;
  end loop;
end $$;
create unique index if not exists reference_items_ws_refkey on public.reference_items (workspace_id, ref_key) where ref_key is not null;

-- ref_key só se calcula ao criar: reference_update não muda o link e assim um repetido antigo nunca rebenta no índice.
create or replace function public.reference_items_before_write()
 returns trigger language plpgsql set search_path to 'public' as $function$
begin
  new.url_normalized := public.normalize_url(new.url);
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.ref_key := public.reel_ref_key(new.url);
  else
    new.ref_key := old.ref_key;
  end if;
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  if new.reel_id is not null and not exists (
       select 1 from reels r where r.id = new.reel_id and r.client_id = new.workspace_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $function$;

-- ───────────── tipos de execução ─────────────
alter table public.agent_jobs drop constraint if exists agent_jobs_kind_check;
alter table public.agent_jobs add constraint agent_jobs_kind_check
  check (kind in ('daily_pipeline','scouts','analysis','reference_analysis','reference_scripts'));
create index if not exists agent_jobs_reference on public.agent_jobs (workspace_id, ((params->>'reference_id')))
  where kind in ('reference_analysis','reference_scripts');

-- ───────────── dissecção versionada (REF-02) ─────────────
create table if not exists public.reference_analyses (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  reference_id bigint not null references public.reference_items(id) on delete restrict,
  version integer not null check (version > 0),
  job_id uuid not null unique references public.agent_jobs(id),
  transcript text not null check (char_length(transcript) between 1 and 20000),
  transcript_source text not null check (transcript_source in ('scraper','manual')),
  metrics jsonb check (metrics is null or jsonb_typeof(metrics) = 'object'),
  dissection jsonb not null check (jsonb_typeof(dissection) = 'object'),
  third_party_flags integer not null default 0 check (third_party_flags >= 0),
  model text not null check (char_length(model) between 1 and 80),
  prompt_version text not null check (char_length(prompt_version) between 1 and 80),
  agent_version text not null check (char_length(agent_version) between 1 and 80),
  tokens_in integer, tokens_out integer,
  created_at timestamptz not null default now(),
  unique (reference_id, version)
);
create index if not exists reference_analyses_ws on public.reference_analyses (workspace_id, reference_id, version desc);

-- guiões que a via rápida criou: idempotência por (execução, slot) e linhagem referência -> dissecção -> guião (R-18, REF-09)
create table if not exists public.reference_script_outputs (
  job_id uuid not null references public.agent_jobs(id),
  slot integer not null check (slot between 1 and 20),
  workspace_id text not null references public.clients(id),
  reference_id bigint not null references public.reference_items(id) on delete restrict,
  analysis_id uuid not null references public.reference_analyses(id),
  content_id text not null references public.guioes(id) on delete restrict,
  similarity numeric check (similarity is null or similarity between 0 and 1),
  created_at timestamptz not null default now(),
  primary key (job_id, slot)
);
create index if not exists reference_script_outputs_ref on public.reference_script_outputs (workspace_id, reference_id);

create or replace function public._reference_outputs_immutable() returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'versao_imutavel' using errcode = '42501', detail = 'Uma dissecção guardada não se altera: pede uma nova.';
end $$;
drop trigger if exists reference_analyses_immutable on public.reference_analyses;
create trigger reference_analyses_immutable before update or delete on public.reference_analyses
  for each row execute function public._reference_outputs_immutable();
drop trigger if exists reference_script_outputs_immutable on public.reference_script_outputs;
create trigger reference_script_outputs_immutable before update or delete on public.reference_script_outputs
  for each row execute function public._reference_outputs_immutable();

alter table public.reference_analyses enable row level security;
alter table public.reference_script_outputs enable row level security;
revoke all on public.reference_analyses, public.reference_script_outputs from anon, authenticated;   -- só pelas RPCs

-- ───────────── linha da referência (mesma assinatura) ─────────────
create or replace function public._reference_row(x reference_items)
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select to_jsonb(x) || jsonb_build_object(
    'metrics', (select jsonb_build_object('views', r.views, 'likes', r.likes, 'comments', r.comments, 'outlier', r.outlier,
                                          'duration', r.duration, 'collected_at', r.updated_at, 'source', 'scraper')
                from reels r where r.id = x.reel_id and r.client_id = x.workspace_id),
    'analysis', (select jsonb_build_object('tese', sa.tese, 'gatilho', sa.gatilho, 'estrutura', sa.estrutura, 'porque_viraliza', sa.porque_viraliza,
                                           'formato', coalesce(sa.formato_norm, sa.formato), 'analyzed_at', sa.analyzed_at)
                 from script_analysis sa where sa.reel_id = x.reel_id and sa.client_id = x.workspace_id),
    'dissection', (select jsonb_build_object('version', a.version, 'at', a.created_at, 'third_party_flags', a.third_party_flags,
                                             'tese', a.dissection->>'tese', 'maquina', a.dissection->>'maquina')
                   from reference_analyses a where a.reference_id = x.id and a.workspace_id = x.workspace_id order by a.version desc limit 1),
    'job', (select jsonb_build_object('kind', j.kind, 'status', j.status, 'at', coalesce(j.finished_at, j.started_at, j.created_at))
            from agent_jobs j where j.workspace_id = x.workspace_id and j.kind in ('reference_analysis','reference_scripts')
              and j.params->>'reference_id' = x.id::text order by j.created_at desc limit 1),
    'scripts', (select count(*) from reference_script_outputs o where o.reference_id = x.id and o.workspace_id = x.workspace_id),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('content_id', l.content_id, 'source_id', l.source_id,
                     'label', coalesce(case when g.id is not null then to_char(g.date,'DD/MM') || ' #' || g.n || ' ' || coalesce(g.tema,'') end, s.titulo)) order by l.created_at), '[]')
              from reference_links l left join guioes g on g.id = l.content_id left join ideas s on s.id = l.source_id where l.reference_id = x.id));
$function$;

-- ───────────── reference_create: repetidos também pela identidade do vídeo ─────────────
create or replace function public.reference_create(p_ws text, p_fields jsonb, p_token text DEFAULT NULL::text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare a jsonb := public._content_actor(p_token); x reference_items; dup bigint; u text := nullif(btrim(p_fields->>'url'), '');
        rid text := nullif(p_fields->>'reel_id', ''); r reels; sa script_analysis; acc accounts;
begin
  perform public._content_require('references.manage', p_ws, p_token, 'reference.create', null);
  if rid is not null then
    select * into r from reels where id = rid and client_id = p_ws;
    select * into acc from accounts where id = r.account_id;
    if r.id is null or acc.client_id is distinct from p_ws then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select * into sa from script_analysis where reel_id = rid and client_id = p_ws;
    u := coalesce(u, r.url);
    if exists (select 1 from reference_items where workspace_id = p_ws and reel_id = rid) then
      raise exception 'duplicado:%', (select id from reference_items where workspace_id = p_ws and reel_id = rid) using errcode = 'PT409';
    end if;
  end if;
  if u is not null and u !~* '^https?://[^\s/$.?#].[^\s]*$' then raise exception 'url_invalido' using errcode = '22023'; end if;
  if u is null then raise exception 'url_obrigatorio' using errcode = '22023'; end if;
  select id into dup from reference_items where workspace_id = p_ws
     and (url_normalized = public.normalize_url(u) or (public.reel_ref_key(u) is not null and ref_key = public.reel_ref_key(u))) order by id limit 1;
  if dup is not null then raise exception 'duplicado:%', dup using errcode = 'PT409'; end if;
  insert into reference_items (workspace_id, url, reel_id, platform, creator, titulo, hook, formato, estilo, narrativa, duracao_s, idioma, tags, colecoes,
                               notas, created_by, created_kind, created_label)
  values (p_ws, u, rid,
          coalesce(nullif(p_fields->>'platform',''), r.platform, case when u ~* 'instagram\.com' then 'instagram' when u ~* 'tiktok\.com' then 'tiktok'
                                                                    when u ~* 'youtu' then 'youtube' end),
          coalesce(nullif(p_fields->>'creator',''), acc.handle),
          coalesce(nullif(btrim(p_fields->>'titulo'),''), nullif(r.hook,''), nullif(left(r.caption, 120),''), u),
          coalesce(nullif(p_fields->>'hook',''), nullif(r.hook,'')),
          coalesce(nullif(p_fields->>'formato',''), sa.formato_norm, sa.formato),
          nullif(p_fields->>'estilo',''),
          coalesce(nullif(p_fields->>'narrativa',''), sa.estrutura),
          coalesce(nullif(p_fields->>'duracao_s','')::integer, nullif(least(round(r.duration)::integer, 7200), 0)),
          coalesce(nullif(p_fields->>'idioma',''), sa.language),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'tags','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'colecoes','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          nullif(p_fields->>'notas',''), (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into x;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('url', x.url, 'reel_id', x.reel_id));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('reel_id', x.reel_id, 'actor_kind', a->>'kind'));
  return public._reference_row(x);
end $function$;

-- ───────────── pôr na fila (interno) ─────────────
-- Uma execução ativa por referência e tipo: pedir outra vez devolve a que está em fila ou a correr (idempotente).
create or replace function public._reference_enqueue(p_ref reference_items, p_kind text, p_actor jsonb, p_params jsonb) returns agent_jobs
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; n int;
begin
  perform pg_advisory_xact_lock(hashtext('refjob:' || p_ref.workspace_id || ':' || p_ref.id || ':' || p_kind));
  select * into j from agent_jobs where workspace_id = p_ref.workspace_id and kind = p_kind and params->>'reference_id' = p_ref.id::text
     and status in ('queued','running') order by created_at desc limit 1;
  if j.id is not null then return j; end if;
  select count(*) + 1 into n from agent_jobs where workspace_id = p_ref.workspace_id and kind = p_kind and params->>'reference_id' = p_ref.id::text;
  j := public._agent_enqueue(p_ref.workspace_id, p_kind, (case p_kind when 'reference_analysis' then 'refan:' else 'refsc:' end) || p_ref.id || ':' || n,
                             null, p_actor, jsonb_build_object('reference_id', p_ref.id::text) || coalesce(p_params, '{}'));
  return j;
end $$;

create or replace function public._reference_job_json(j agent_jobs) returns jsonb language sql stable set search_path = public as $$
  select case when j.id is null then null else jsonb_build_object('id', j.id, 'kind', j.kind, 'status', j.status, 'attempts', j.attempts,
    'max_attempts', j.max_attempts, 'created_at', j.created_at, 'started_at', j.started_at, 'finished_at', j.finished_at,
    'next_attempt_at', j.next_attempt_at, 'progress', j.progress, 'last_error', j.last_error, 'requested_label', j.requested_label,
    'result', j.result) end
$$;

-- ───────────── REF-02: pedir a dissecção ─────────────
-- p_transcript: transcrição colada à mão (caminho manual quando a recolha automática não está disponível).
create or replace function public.reference_analyze(p_ref bigint, p_transcript text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); x reference_items; j agent_jobs; tr text := nullif(btrim(coalesce(p_transcript, '')), '');
begin
  select * into x from reference_items where id = p_ref;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('references.analyze', x.workspace_id, p_token, 'reference.analyze', null);
  if not public._flag_on('references.link', x.workspace_id, p_token) then raise exception 'funcionalidade_desligada' using errcode = '55000'; end if;
  if x.archived_at is not null then raise exception 'referencia_arquivada' using errcode = '22023'; end if;
  if tr is not null and char_length(tr) not between 20 and 20000 then raise exception 'transcricao_invalida' using errcode = '22023'; end if;
  if x.url is null then raise exception 'url_obrigatorio' using errcode = '22023'; end if;
  j := public._reference_enqueue(x, 'reference_analysis', a,
         jsonb_strip_nulls(jsonb_build_object('url', x.url, 'platform', x.platform, 'transcript', tr)));
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', x.workspace_id, 'reference.analysis_requested', 'reference', x.id::text,
          jsonb_build_object('job_id', j.id, 'manual_transcript', tr is not null));
  return jsonb_build_object('job', public._reference_job_json(j));
end $$;

-- ───────────── REF-01: colar link ─────────────
-- Só Reels do Instagram e vídeos do TikTok. Repetido não é erro: devolve a referência que já existe (duplicate=true).
create or replace function public.reference_paste(p_ws text, p_url text, p_analyze boolean default false, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); u text := btrim(coalesce(p_url, '')); k text; x reference_items; plat text; code text;
        author text; rid text; j agent_jobs;
begin
  perform public._content_require('references.manage', p_ws, p_token, 'reference.paste', null);
  if not public._flag_on('references.link', p_ws, p_token) then raise exception 'funcionalidade_desligada' using errcode = '55000'; end if;
  if u = '' then raise exception 'url_obrigatorio' using errcode = '22023'; end if;
  if u !~* '^https?://' then u := 'https://' || u; end if;
  if char_length(u) > 2000 or u !~* '^https?://[^\s/$.?#].[^\s]*$' then raise exception 'url_invalido' using errcode = '22023'; end if;
  k := public.reel_ref_key(u);
  if k is null and u !~* '^https?://(vm|vt)\.tiktok\.com/[A-Za-z0-9]+' then raise exception 'link_nao_suportado' using errcode = '22023'; end if;
  plat := split_part(coalesce(k, 'tiktok:'), ':', 1);
  code := nullif(split_part(coalesce(k, ''), ':', 2), '');
  perform pg_advisory_xact_lock(hashtext('refpaste:' || p_ws || ':' || coalesce(k, public.normalize_url(u))));
  select * into x from reference_items where workspace_id = p_ws
     and ((k is not null and ref_key = k) or url_normalized = public.normalize_url(u)) order by id limit 1;
  if x.id is not null then
    return jsonb_build_object('created', false, 'duplicate', true, 'reference', public._reference_row(x));
  end if;
  author := lower(public._reel_url_author(u));
  if plat = 'instagram' then   -- se o scraper já recolheu este reel para o cliente, liga-o (métricas com data de recolha)
    select r.id into rid from reels r where r.client_id = p_ws and r.id = code;
    if rid is not null and exists (select 1 from reference_items where workspace_id = p_ws and reel_id = rid) then rid := null; end if;
    if rid is not null then select coalesce(author, nullif(lower(r.owner), '')) into author from reels r where r.client_id = p_ws and r.id = rid; end if;
  end if;
  insert into reference_items (workspace_id, url, reel_id, platform, creator, titulo, created_by, created_kind, created_label, notas)
  values (p_ws, u, rid, plat, author,
          case when plat = 'instagram' then 'Reel' else 'TikTok' end || coalesce(' de @' || author, '') || coalesce(' · ' || code, ''),
          (a->>'uid')::uuid, a->>'kind', a->>'label', null)
  returning * into x;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'reference.created', 'reference', x.id::text,
          jsonb_build_object('url', x.url, 'ref_key', x.ref_key, 'via', 'paste'));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('via', 'paste', 'actor_kind', a->>'kind'));
  if p_analyze and public.ws_can('references.analyze', p_ws, p_token) then
    j := public._reference_enqueue(x, 'reference_analysis', a, jsonb_build_object('url', x.url, 'platform', x.platform));
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'reference.analysis_requested', 'reference', x.id::text,
            jsonb_build_object('job_id', j.id, 'manual_transcript', false));
  end if;
  select * into x from reference_items where id = x.id;
  return jsonb_build_object('created', true, 'duplicate', false, 'reference', public._reference_row(x), 'job', public._reference_job_json(j));
end $$;

-- ───────────── REF-03: pedir 3 guiões a partir da dissecção mais recente ─────────────
create or replace function public.reference_adapt(p_ref bigint, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); x reference_items; an reference_analyses; j agent_jobs;
begin
  select * into x from reference_items where id = p_ref;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('references.adapt', x.workspace_id, p_token, 'reference.adapt', null);
  if not public._flag_on('references.link', x.workspace_id, p_token) then raise exception 'funcionalidade_desligada' using errcode = '55000'; end if;
  if x.archived_at is not null then raise exception 'referencia_arquivada' using errcode = '22023'; end if;
  select * into an from reference_analyses where reference_id = x.id and workspace_id = x.workspace_id order by version desc limit 1;
  if an.id is null then raise exception 'sem_disseccao' using errcode = '22023'; end if;
  j := public._reference_enqueue(x, 'reference_scripts', a, jsonb_build_object('analysis_id', an.id, 'analysis_version', an.version));
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', x.workspace_id, 'reference.adapt_requested', 'reference', x.id::text,
          jsonb_build_object('job_id', j.id, 'analysis_version', an.version));
  return jsonb_build_object('job', public._reference_job_json(j));
end $$;

-- ───────────── leitura da dissecção ─────────────
create or replace function public.reference_analysis_get(p_ref bigint, p_version int default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare x reference_items; an reference_analyses; ja agent_jobs; js agent_jobs; flag boolean;
begin
  select * into x from reference_items where id = p_ref;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('references.read', x.workspace_id, p_token, 'reference.analysis_read', null);
  select * into an from reference_analyses where reference_id = x.id and workspace_id = x.workspace_id
     and (p_version is null or version = p_version) order by version desc limit 1;
  if p_version is not null and an.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  select * into ja from agent_jobs where workspace_id = x.workspace_id and kind = 'reference_analysis' and params->>'reference_id' = x.id::text
   order by created_at desc limit 1;
  select * into js from agent_jobs where workspace_id = x.workspace_id and kind = 'reference_scripts' and params->>'reference_id' = x.id::text
   order by created_at desc limit 1;
  flag := public._flag_on('references.link', x.workspace_id, p_token);
  return jsonb_build_object(
    'reference', public._reference_row(x),
    'analysis', case when an.id is null then null else jsonb_build_object('version', an.version, 'created_at', an.created_at,
       'transcript', an.transcript, 'transcript_source', an.transcript_source, 'metrics', an.metrics, 'dissection', an.dissection,
       'third_party_flags', an.third_party_flags, 'model', an.model, 'prompt_version', an.prompt_version, 'agent_version', an.agent_version) end,
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'created_at', v.created_at, 'model', v.model,
                   'prompt_version', v.prompt_version, 'transcript_source', v.transcript_source) order by v.version desc), '[]')
                 from reference_analyses v where v.reference_id = x.id and v.workspace_id = x.workspace_id),
    'analysis_job', public._reference_job_json(ja),
    'scripts_job', public._reference_job_json(js),
    'scripts', (select coalesce(jsonb_agg(jsonb_build_object('content_id', o.content_id, 'date', g.date, 'n', g.n, 'tema', g.tema,
                   'editorial_status', g.editorial_status, 'similarity', o.similarity, 'analysis_version', v.version, 'created_at', o.created_at)
                   order by o.created_at desc, o.slot), '[]')
                from reference_script_outputs o join guioes g on g.id = o.content_id and g.deleted_at is null
                join reference_analyses v on v.id = o.analysis_id
               where o.reference_id = x.id and o.workspace_id = x.workspace_id),
    -- o worker em produção só apanha estes tipos depois de atualizado: sem worker que os aceite, a UI diz isso em vez de esperar
    'worker_ready', exists (select 1 from agent_workers w where 'reference_analysis' = any (w.kinds) and w.last_seen > now() - interval '10 minutes'),
    'can', jsonb_build_object(
       'analyze', flag and public.ws_can('references.analyze', x.workspace_id, p_token),
       'adapt', flag and public.ws_can('references.adapt', x.workspace_id, p_token)));
end $$;

-- ───────────── worker (engine_worker) ─────────────
create or replace function public._reference_worker_job(p_job uuid, p_worker text, p_kind text) returns agent_jobs
language plpgsql security definer set search_path = public as $$
declare j agent_jobs;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  if p_kind is not null and j.kind <> p_kind then raise exception 'tipo_invalido' using errcode = '22023'; end if;
  return j;
end $$;

-- Mediana das views dos reels do mesmo autor que o scraper já recolheu para este cliente (mínimo 5).
create or replace function public._reference_author_median(p_ws text, p_author text) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when count(*) >= 5 then jsonb_build_object('median_views', percentile_cont(0.5) within group (order by views), 'sample', count(*)) end
    from reels where client_id = p_ws and p_author is not null and lower(owner) = lower(p_author) and views > 0
$$;

create or replace function public.worker_reference_context(p_job uuid, p_worker text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; x reference_items; r reels; an reference_analyses;
begin
  j := public._reference_worker_job(p_job, p_worker, null);
  if j.kind not in ('reference_analysis','reference_scripts') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
  select * into x from reference_items where id = (j.params->>'reference_id')::bigint and workspace_id = j.workspace_id;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  select * into r from reels where client_id = j.workspace_id and id = x.reel_id;
  if j.kind = 'reference_scripts' then
    select * into an from reference_analyses where id = (j.params->>'analysis_id')::uuid and reference_id = x.id and workspace_id = j.workspace_id;
    if an.id is null then raise exception 'sem_disseccao' using errcode = '22023'; end if;
  end if;
  return jsonb_build_object(
    'reference', jsonb_build_object('id', x.id, 'url', x.url, 'platform', x.platform, 'creator', x.creator, 'ref_key', x.ref_key, 'titulo', x.titulo),
    'manual_transcript', j.params->>'transcript',
    'reel', case when r.id is null then null else jsonb_build_object('id', r.id, 'owner', r.owner, 'transcript', nullif(r.transcript, ''),
              'caption', nullif(r.caption, ''), 'views', r.views, 'likes', r.likes, 'comments', r.comments, 'shares', r.shares,
              'duration', r.duration, 'collected_at', r.updated_at) end,
    'author', public._reference_author_median(j.workspace_id, coalesce(x.creator, r.owner)),
    'analysis', case when an.id is null then null else jsonb_build_object('id', an.id, 'version', an.version, 'transcript', an.transcript,
              'dissection', an.dissection) end,
    -- exemplos da voz do cliente: guiões aprovados mais recentes (só para a adaptação)
    'approved_scripts', case when j.kind <> 'reference_scripts' then '[]'::jsonb else
       (select coalesce(jsonb_agg(jsonb_build_object('tema', g.tema, 'formato', g.formato, 'hook', g.hooks->0->>'text', 'corpo', left(g.corpo, 1500))), '[]')
          from (select * from guioes where client_id = j.workspace_id and editorial_status = 'approved' and deleted_at is null
                 order by coalesce(validado_em, updated_at) desc limit 5) g) end,
    -- os vídeos do próprio cliente que mais renderam (contas próprias recolhidas pelo scraper)
    'top_own', case when j.kind <> 'reference_scripts' then '[]'::jsonb else
       (select coalesce(jsonb_agg(jsonb_build_object('hook', nullif(rr.hook, ''), 'outlier', rr.outlier, 'transcript', left(rr.transcript, 1200))), '[]')
          from (select rr.* from reels rr join accounts ac on ac.id = rr.account_id
                 where rr.client_id = j.workspace_id and ac.client_id = j.workspace_id and ac.role <> 'reference' and coalesce(rr.transcript, '') <> ''
                 order by rr.outlier desc nulls last limit 3) rr) end);
end $$;

-- Limpa um texto do motor: nunca confiar no payload.
create or replace function public._ref_txt(p jsonb, p_max int) returns text language sql immutable set search_path = public as $$
  select case when p is null or jsonb_typeof(p) not in ('string','number') then null else nullif(left(btrim(p #>> '{}'), p_max), '') end
$$;
create or replace function public._ref_num(p jsonb) returns numeric language sql immutable set search_path = public as $$
  select case when p is not null and jsonb_typeof(p) = 'number' and (p #>> '{}')::numeric >= 0 then (p #>> '{}')::numeric end
$$;

create or replace function public.worker_reference_save(p_job uuid, p_worker text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; x reference_items; an reference_analyses; d jsonb; dis jsonb; est jsonb := '[]'; afs jsonb := '[]'; e jsonb;
        m jsonb; met jsonb; tr text; src text; v int; maq text; med jsonb; views numeric; vhook jsonb;
begin
  j := public._reference_worker_job(p_job, p_worker, 'reference_analysis');
  select * into an from reference_analyses where job_id = j.id;
  if an.id is not null then return jsonb_build_object('id', an.id, 'version', an.version, 'created', false); end if;
  select * into x from reference_items where id = (j.params->>'reference_id')::bigint and workspace_id = j.workspace_id for update;
  if x.id is null then raise exception 'referencia_nao_encontrada' using errcode = 'P0002'; end if;
  tr := btrim(coalesce(p_payload->>'transcript', ''));
  src := p_payload->>'transcript_source';
  if tr = '' or char_length(tr) > 20000 then raise exception 'transcricao_invalida' using errcode = '22023'; end if;
  if src is null or src not in ('scraper','manual') then raise exception 'origem_invalida' using errcode = '22023'; end if;
  if src = 'manual' and j.params->>'transcript' is null then raise exception 'origem_invalida' using errcode = '22023'; end if;
  d := p_payload->'dissection';
  if d is null or jsonb_typeof(d) <> 'object' then raise exception 'disseccao_invalida' using errcode = '22023'; end if;
  maq := public._ref_txt(d->'maquina', 40);
  if maq is null or maq not in ('lei absurda','redefinição','mecanismo','isco e revelação','ataque com recibos','outra') then
    raise exception 'disseccao_invalida' using errcode = '22023', detail = 'maquina'; end if;
  if public._ref_txt(d->'tese', 600) is null or public._ref_txt(d->'hook'->'texto', 500) is null then
    raise exception 'disseccao_invalida' using errcode = '22023', detail = 'tese/hook'; end if;
  if jsonb_typeof(d->'estrutura') is distinct from 'array' or jsonb_array_length(d->'estrutura') not between 1 and 30 then
    raise exception 'disseccao_invalida' using errcode = '22023', detail = 'estrutura'; end if;
  for e in select * from jsonb_array_elements(d->'estrutura') loop
    if public._ref_txt(e->'parte', 60) is null then raise exception 'disseccao_invalida' using errcode = '22023', detail = 'estrutura.parte'; end if;
    est := est || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('inicio_s', public._ref_num(e->'inicio_s'), 'fim_s', public._ref_num(e->'fim_s'),
             'parte', public._ref_txt(e->'parte', 60), 'resumo', public._ref_txt(e->'resumo', 400))));
  end loop;
  if d->'afirmacoes_terceiros' is not null and jsonb_typeof(d->'afirmacoes_terceiros') = 'array' then
    for e in select * from jsonb_array_elements(d->'afirmacoes_terceiros') limit 30 loop
      if public._ref_txt(e->'texto', 400) is not null then
        afs := afs || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('texto', public._ref_txt(e->'texto', 400),
                 'pessoa', public._ref_txt(e->'pessoa', 120), 'tipo', public._ref_txt(e->'tipo', 60))));
      end if;
    end loop;
  end if;
  vhook := jsonb_strip_nulls(jsonb_build_object('texto', public._ref_txt(d->'hook'->'texto', 500), 'mecanismo', public._ref_txt(d->'hook'->'mecanismo', 300),
            'segundos', public._ref_num(d->'hook'->'segundos')));
  dis := jsonb_strip_nulls(jsonb_build_object('hook', vhook, 'maquina', maq, 'maquina_porque', public._ref_txt(d->'maquina_porque', 400),
           'tese', public._ref_txt(d->'tese', 600), 'inimigo', public._ref_txt(d->'inimigo', 300), 'estrutura', est,
           'duracao_s', public._ref_num(d->'duracao_s'), 'palavras_por_segundo', public._ref_num(d->'palavras_por_segundo'),
           'ritmo', public._ref_txt(d->'ritmo', 400), 'porque_funciona', public._ref_txt(d->'porque_funciona', 800),
           'idioma', public._ref_txt(d->'idioma', 20), 'afirmacoes_terceiros', afs));
  -- métricas públicas (R-20): números só se vierem do scraper, com data; índice calculado aqui face à mediana do autor
  m := p_payload->'metrics';
  if m is not null and jsonb_typeof(m) = 'object' and public._ref_num(m->'views') is not null then
    views := public._ref_num(m->'views');
    med := public._reference_author_median(j.workspace_id, coalesce(public._ref_txt(m->'owner', 60), x.creator));
    met := jsonb_strip_nulls(jsonb_build_object('views', views, 'likes', public._ref_num(m->'likes'), 'comments', public._ref_num(m->'comments'),
             'shares', public._ref_num(m->'shares'), 'duration_s', public._ref_num(m->'duration_s'), 'owner', public._ref_txt(m->'owner', 60),
             'collected_at', coalesce(public._ref_txt(m->'collected_at', 40), now()::text), 'source', 'scraper',
             'author_median_views', med->'median_views', 'author_sample', med->'sample',
             'index', case when (med->>'median_views')::numeric > 0 then round(views / (med->>'median_views')::numeric, 2) end));
  end if;
  if public._ref_txt(p_payload->'model', 80) is null or public._ref_txt(p_payload->'prompt_version', 80) is null
     or public._ref_txt(p_payload->'agent_version', 80) is null then raise exception 'proveniencia_em_falta' using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into v from reference_analyses where reference_id = x.id;
  insert into reference_analyses (workspace_id, reference_id, version, job_id, transcript, transcript_source, metrics, dissection, third_party_flags,
                                  model, prompt_version, agent_version, tokens_in, tokens_out)
  values (j.workspace_id, x.id, v, j.id, tr, src, met, dis, jsonb_array_length(afs),
          public._ref_txt(p_payload->'model', 80), public._ref_txt(p_payload->'prompt_version', 80), public._ref_txt(p_payload->'agent_version', 80),
          case when public._ref_num(p_payload->'tokens_in') is not null then least(public._ref_num(p_payload->'tokens_in'), 2000000000)::int end,
          case when public._ref_num(p_payload->'tokens_out') is not null then least(public._ref_num(p_payload->'tokens_out'), 2000000000)::int end)
  returning * into an;
  -- completa a classificação que ainda está vazia (nunca sobrescreve o que a equipa escreveu)
  update reference_items set
    hook = coalesce(reference_items.hook, public._ref_txt(d->'hook'->'texto', 500)),
    duracao_s = coalesce(duracao_s, nullif(least(round(coalesce(public._ref_num(m->'duration_s'), public._ref_num(d->'duracao_s'), 0))::int, 7200), 0)),
    creator = coalesce(creator, lower(public._ref_txt(m->'owner', 60))),
    idioma = coalesce(idioma, public._ref_txt(d->'idioma', 20))
  where id = x.id;
  update agent_jobs set heartbeat_at = now(), locked_until = greatest(locked_until, now() + interval '10 minutes') where id = j.id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values (null, 'system', left('Motor · ' || coalesce(j.run_id, j.id::text), 80), j.workspace_id, 'reference.analyzed', 'reference', x.id::text,
          jsonb_build_object('version', v, 'job_id', j.id, 'transcript_source', src, 'third_party_flags', jsonb_array_length(afs),
                             'model', an.model, 'prompt_version', an.prompt_version));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'reference.analyzed', 'reference', x.id::text, jsonb_build_object('version', v, 'job_id', j.id));
  return jsonb_build_object('id', an.id, 'version', v, 'created', true);
end $$;

-- Guião da via rápida (REF-03/04): entra sempre em revisão (nunca aprovado sozinho), marcado origem 'via_rapida',
-- ligado à referência (reference_links) e à dissecção usada (reference_script_outputs). Idempotente por (execução, slot).
create or replace function public.worker_reference_save_script(p_job uuid, p_worker text, p_slot integer, p_script jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; x reference_items; an reference_analyses; o reference_script_outputs; tz text; d date; n int; cid text;
        hooks jsonb := '[]'; h jsonb; corpo text; sim numeric;
begin
  j := public._reference_worker_job(p_job, p_worker, 'reference_scripts');
  if p_slot is null or p_slot not between 1 and 3 then raise exception 'slot_invalido' using errcode = '22023'; end if;
  select * into o from reference_script_outputs where job_id = j.id and slot = p_slot;
  if o.job_id is not null then return jsonb_build_object('id', o.content_id, 'created', false); end if;
  select * into x from reference_items where id = (j.params->>'reference_id')::bigint and workspace_id = j.workspace_id;
  select * into an from reference_analyses where id = (j.params->>'analysis_id')::uuid and reference_id = x.id and workspace_id = j.workspace_id;
  if x.id is null or an.id is null then raise exception 'sem_disseccao' using errcode = '22023'; end if;
  corpo := btrim(coalesce(p_script->>'corpo', ''));
  if corpo = '' or length(corpo) > 20000 then raise exception 'corpo_invalido' using errcode = '22023'; end if;
  -- decisão do PRD: 3 hooks por guião
  if jsonb_typeof(p_script->'hooks') is distinct from 'array' or jsonb_array_length(p_script->'hooks') <> 3 then
    raise exception 'hooks_invalidos' using errcode = '22023'; end if;
  for h in select * from jsonb_array_elements(p_script->'hooks') loop
    if btrim(coalesce(h->>'text', h->>'hook', '')) = '' or length(coalesce(h->>'text', h->>'hook')) > 500 then
      raise exception 'hooks_invalidos' using errcode = '22023'; end if;
    hooks := hooks || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('text', btrim(coalesce(h->>'text', h->>'hook')),
              'mecanismo', left(h->>'mecanismo', 40))));
  end loop;
  sim := case when (p_script->>'similarity') ~ '^(0(\.\d+)?|1(\.0+)?)$' then (p_script->>'similarity')::numeric end;
  if sim is null then raise exception 'semelhanca_em_falta' using errcode = '22023'; end if;
  -- limiar [pressuposto] 0,25: o motor já bloqueia acima do seu limite; isto é a segunda linha
  if sim > 0.25 then raise exception 'demasiado_parecido' using errcode = '22023'; end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = j.workspace_id;
  d := (now() at time zone tz)::date;   -- via rápida: guiões do próprio dia
  perform pg_advisory_xact_lock(hashtext('guioes:' || j.workspace_id || ':' || d::text));
  select coalesce(max(g.n), 0) + 1 into n from guioes g where g.client_id = j.workspace_id and g.date = d;
  loop
    cid := j.workspace_id || '-' || to_char(d, 'YYYY-MM-DD') || '-' || lpad(n::text, 2, '0');
    exit when not exists (select 1 from guioes where id = cid);
    n := n + 1;
  end loop;
  perform set_config('clipstudio.actor_kind', 'engine', true);
  perform set_config('clipstudio.actor_label', left('Motor · via rápida · ' || coalesce(j.run_id, j.id::text), 80), true);
  insert into guioes (id, client_id, date, n, formato, maquina, tema, hooks, corpo, fonte, legenda, comentario_fixado, critic_score,
                      origem, status, validado, gravado, cta, notas, tags)
  values (cid, j.workspace_id, d, n, left(p_script->>'formato', 60), left(p_script->>'maquina', 60), left(p_script->>'tema', 300), hooks, corpo,
          left(x.url, 1000), left(p_script->>'legenda', 2200), left(p_script->>'comentario_fixado', 1000), null,
          'via_rapida', 'aprovado', false, false, left(p_script->>'cta', 1000),
          left('Via rápida: adaptado da referência #' || x.id || coalesce(' (@' || x.creator || ')', '') || ', dissecção v' || an.version
               || '. Semelhança com a transcrição original: ' || round(sim * 100) || '%.'
               || coalesce(E'\n' || nullif(p_script->>'notas', ''), ''), 4000),
          array['via rápida'])
  ;
  insert into reference_script_outputs (job_id, slot, workspace_id, reference_id, analysis_id, content_id, similarity)
  values (j.id, p_slot, j.workspace_id, x.id, an.id, cid, sim);
  insert into reference_links (workspace_id, reference_id, content_id, added_kind) values (j.workspace_id, x.id, cid, 'engine') on conflict do nothing;
  update agent_jobs set heartbeat_at = now(), locked_until = greatest(locked_until, now() + interval '10 minutes') where id = j.id;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'reference.script_created', 'reference', x.id::text, jsonb_build_object('content_id', cid, 'job_id', j.id, 'slot', p_slot));
  return jsonb_build_object('id', cid, 'date', d, 'n', n, 'created', true);
end $$;

revoke all on function public.reel_ref_key(text), public._reel_url_author(text) from public;
grant execute on function public.reel_ref_key(text) to anon, authenticated;
revoke all on function public._reference_enqueue(reference_items, text, jsonb, jsonb), public._reference_job_json(agent_jobs),
  public._reference_worker_job(uuid, text, text), public._reference_author_median(text, text), public._ref_txt(jsonb, int), public._ref_num(jsonb),
  public._reference_outputs_immutable(), public._reel_url_author(text) from public, anon, authenticated;
revoke all on function public.reference_analyze(bigint, text, text), public.reference_paste(text, text, boolean, text),
  public.reference_adapt(bigint, text), public.reference_analysis_get(bigint, int, text) from public;
grant execute on function public.reference_analyze(bigint, text, text), public.reference_paste(text, text, boolean, text),
  public.reference_adapt(bigint, text), public.reference_analysis_get(bigint, int, text) to anon, authenticated;
revoke all on function public.worker_reference_context(uuid, text), public.worker_reference_save(uuid, text, jsonb),
  public.worker_reference_save_script(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function public.worker_reference_context(uuid, text), public.worker_reference_save(uuid, text, jsonb),
  public.worker_reference_save_script(uuid, text, integer, jsonb) to engine_worker, service_role;

/* Rollback (compatível, por esta ordem):
   drop function public.worker_reference_save_script(uuid, text, integer, jsonb), public.worker_reference_save(uuid, text, jsonb),
     public.worker_reference_context(uuid, text), public.reference_analysis_get(bigint, int, text), public.reference_adapt(bigint, text),
     public.reference_paste(text, text, boolean, text), public.reference_analyze(bigint, text, text), public._reference_enqueue(reference_items, text, jsonb, jsonb),
     public._reference_job_json(agent_jobs), public._reference_worker_job(uuid, text, text), public._reference_author_median(text, text),
     public._ref_txt(jsonb, int), public._ref_num(jsonb), public._reel_url_author(text);
   repor _reference_row, reference_create e reference_items_before_write de 20261029111417_w4_engine_client_scope.sql
     (reference_create com o replace de 20261028205134_w2_references_zero_duration.sql);
   contract posterior (só depois de o código deixar de os usar):
     drop table public.reference_script_outputs, public.reference_analyses; drop function public._reference_outputs_immutable();
     drop index public.agent_jobs_reference; drop index public.reference_items_ws_refkey; alter table public.reference_items drop column ref_key;
     drop function public.reel_ref_key(text);
     agent_jobs_kind_check de volta a ('daily_pipeline','scouts','analysis') só sem linhas dos tipos novos;
     delete from feature_flags where key = 'references.link'; delete from feature_flag_defs where key = 'references.link';
     delete from role_capabilities where capability in ('references.analyze','references.adapt');
     update capabilities set status = 'W10' where key in ('references.analyze','references.adapt'). */
