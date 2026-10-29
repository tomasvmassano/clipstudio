-- W4-01 Catálogo de agentes, configuração versionada por cliente e fila de execuções duráveis
-- (PRD M06 FR-06-01/02/03/04/05 parcial, FR-17-14, §7; AGENTS §2.8, §7).
-- Catálogo = os agentes que o motor implementa (código), com o modelo e os limites definidos por cliente na configuração.
-- Configuração = versões imutáveis por cliente (rascunho → ativa → retirada); validar antes de ativar; voltar atrás = ativar outra.
-- Execuções = fila durável com chave de idempotência, lease + heartbeat, tentativas com backoff exponencial, dead-letter,
-- cancelamento e limite de custo diário. O worker (motor) fala só por funções reservadas ao service_role.
-- Só aditivo. O motor atual continua a funcionar (não usa nada disto). Rollback: bloco no fim.

update public.capabilities set status = 'ativo' where key in ('agents.run','agents.configure','costs.read');

-- ───────────── catálogo ─────────────
create table public.agent_definitions (
  key text primary key check (key ~ '^[a-z_]{2,40}$'),
  name text not null,
  stage text not null check (stage in ('research','strategy','creative','quality','learning')),
  description text not null,
  default_model text not null,
  tools text[] not null default '{}',
  reads text[] not null default '{}',
  writes text[] not null default '{}',
  position integer not null default 0
);
alter table public.agent_definitions enable row level security;
revoke all on public.agent_definitions from anon, authenticated;
grant select on public.agent_definitions to authenticated;
create policy agent_definitions_select on public.agent_definitions for select to authenticated using (true);

create table public.agent_models (
  key text primary key,
  label text not null,
  active boolean not null default true
);
alter table public.agent_models enable row level security;
revoke all on public.agent_models from anon, authenticated;
grant select on public.agent_models to authenticated;
create policy agent_models_select on public.agent_models for select to authenticated using (true);

insert into public.agent_models (key, label) values
  ('claude-haiku-5-5', 'Claude Haiku 5.5'), ('claude-sonnet-5-5', 'Claude Sonnet 5.5'), ('claude-opus-5-5', 'Claude Opus 5.5');

-- Os agentes do motor (numeiro-engine/engine/agents), sem dados de cliente.
insert into public.agent_definitions (key, name, stage, description, default_model, tools, reads, writes, position) values
  ('reporter', 'Repórter', 'research', 'Procura notícias das últimas 48 h nas áreas definidas e traz factos com fonte.', 'claude-opus-5-5', '{pesquisa_web}', '{configuração}', '{fontes}', 10),
  ('curious', 'Curioso', 'research', 'Encontra temas que dividem opiniões nos comentários e nas tendências.', 'claude-opus-5-5', '{}', '{reels,comentários}', '{fontes}', 20),
  ('philosopher', 'Filósofo', 'research', 'Tira ideias da lista de leitura; citações literais só de obras em domínio público.', 'claude-opus-5-5', '{}', '{lista de leitura,citações}', '{fontes}', 30),
  ('analyst', 'Analista', 'research', 'Analisa os reels de referência: tese, gatilho, estrutura e porque viralizou.', 'claude-opus-5-5', '{}', '{reels}', '{análises}', 40),
  ('daily_analyst', 'Analista diário', 'learning', 'Relatório diário do que funcionou e do que não funcionou.', 'claude-opus-5-5', '{}', '{desempenho}', '{relatórios}', 50),
  ('strategist', 'Estratega', 'strategy', 'Distribui os guiões do dia pelos formatos e pelas fontes.', 'claude-sonnet-5-5', '{}', '{fontes,formatos,desempenho}', '{plano do dia}', 60),
  ('hooksmith', 'Hook Smith', 'creative', 'Escreve vários hooks por guião e fica com os de mecanismos diferentes.', 'claude-sonnet-5-5', '{}', '{plano do dia,voz}', '{hooks}', 70),
  ('writer', 'Escritor', 'creative', 'Escreve o corpo na voz do cliente, dentro do intervalo de palavras do formato.', 'claude-opus-5-5', '{}', '{hooks,voz,referências}', '{guiões}', 80),
  ('critic', 'Crítico', 'quality', 'Pontua cada guião pela rubrica e manda rever abaixo do limiar.', 'claude-opus-5-5', '{}', '{guiões,rubrica}', '{notas}', 90),
  ('compliance', 'Conformidade', 'quality', 'Aplica as regras de segurança do cliente (factos com fonte, sem desumanizar grupos).', 'claude-opus-5-5', '{}', '{guiões,regras}', '{bloqueios}', 100),
  ('editor', 'Editor', 'quality', 'Ajusta ritmo e tamanho final; chumba fora dos limites.', 'claude-haiku-5-5', '{}', '{guiões}', '{guiões}', 110),
  ('librarian', 'Bibliotecário', 'research', 'Gere o banco de citações verificadas e os períodos sem repetir.', 'claude-opus-5-5', '{}', '{citações}', '{citações}', 120),
  ('learner', 'Aprendiz', 'learning', 'Ajusta o mix de formatos com o desempenho real, dentro do mínimo e máximo de cada formato.', 'claude-sonnet-5-5', '{}', '{desempenho,formatos}', '{proposta de mix}', 130);

-- ───────────── configuração por cliente (versões imutáveis) ─────────────
create table public.agent_config_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  version_no integer not null,
  status text not null default 'draft' check (status in ('draft','active','retired')),
  config jsonb not null,
  notes text check (notes is null or length(notes) <= 1000),
  validation jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  activated_label text,
  unique (workspace_id, version_no)
);
create unique index agent_config_one_active on public.agent_config_versions (workspace_id) where status = 'active';

create or replace function public.agent_config_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'versao_nao_apagavel' using errcode = '42501'; end if;
  if (new.workspace_id, new.version_no, new.config, new.created_at) is distinct from (old.workspace_id, old.version_no, old.config, old.created_at) then
    raise exception 'versao_imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger agent_config_guard before update or delete on public.agent_config_versions for each row execute function public.agent_config_guard();

-- ───────────── fila de execuções ─────────────
create table public.agent_jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  kind text not null check (kind in ('daily_pipeline','scouts','analysis')),
  idempotency_key text not null check (length(idempotency_key) between 3 and 120),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','cancelled','dead')),
  config_version_id uuid not null references public.agent_config_versions(id),
  params jsonb not null default '{}',
  scheduled_for timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  attempts integer not null default 0,
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  locked_by text,
  locked_until timestamptz,
  heartbeat_at timestamptz,
  progress jsonb,
  cancel_requested boolean not null default false,
  last_error text,
  result jsonb,
  run_id text,
  cost_eur numeric(10,4),
  tokens_in bigint,
  tokens_out bigint,
  budget_cap_eur numeric(10,2),
  requested_by uuid references auth.users(id) on delete set null,
  requested_kind text not null check (requested_kind in ('user','legacy_code','system')),
  requested_label text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  unique (workspace_id, idempotency_key)
);
create index agent_jobs_queue on public.agent_jobs (next_attempt_at) where status = 'queued';
create index agent_jobs_ws on public.agent_jobs (workspace_id, created_at desc);

create table public.agent_job_attempts (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.agent_jobs(id) on delete restrict,
  workspace_id text not null references public.clients(id),
  attempt integer not null,
  worker text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running','succeeded','failed','lost','cancelled')),
  error text,
  cost_eur numeric(10,4),
  unique (job_id, attempt)
);

create table public.agent_workers (
  id text primary key check (length(id) between 3 and 80),
  kinds text[] not null default '{}',
  last_seen timestamptz not null default now(),
  version text
);

create trigger agent_jobs_no_delete before delete on public.agent_jobs for each row execute function public.content_append_only();
create trigger agent_job_attempts_no_delete before delete on public.agent_job_attempts for each row execute function public.content_append_only();

create or replace function public.agent_jobs_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if (new.workspace_id, new.kind, new.idempotency_key, new.config_version_id, new.created_at)
     is distinct from (old.workspace_id, old.kind, old.idempotency_key, old.config_version_id, old.created_at) then
    raise exception 'imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger agent_jobs_guard before update on public.agent_jobs for each row execute function public.agent_jobs_guard();

create or replace function public.agent_jobs_same_ws() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select workspace_id from agent_config_versions where id = new.config_version_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger agent_jobs_ws before insert on public.agent_jobs for each row execute function public.agent_jobs_same_ws();

alter table public.agent_config_versions enable row level security;
alter table public.agent_jobs enable row level security;
alter table public.agent_job_attempts enable row level security;
alter table public.agent_workers enable row level security;
revoke all on public.agent_config_versions, public.agent_jobs, public.agent_job_attempts, public.agent_workers from anon, authenticated;
-- agent_jobs só pela função agents_overview: o custo fica escondido de quem não tem costs.read
grant select on public.agent_config_versions to authenticated;
create policy agent_config_select on public.agent_config_versions for select to authenticated using (public.authorize('agents.configure', workspace_id));

-- notificações: erro de automação (fila de exceções, FR-17-06)
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done','automation_error'));

-- ───────────── validação da configuração ─────────────
create or replace function public.agent_config_validate(p_config jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare errs jsonb := '[]'; warns jsonb := '[]'; k text; f jsonb; s numeric := 0; m text; p jsonb := coalesce(p_config->'pipeline', '{}');
        num numeric;
begin
  if jsonb_typeof(p_config) <> 'object' then return jsonb_build_object('ok', false, 'errors', jsonb_build_array('A configuração tem de ser um objeto.'), 'warnings', '[]'::jsonb); end if;
  if length(p_config::text) > 60000 then errs := errs || jsonb_build_array('Configuração grande demais.'); end if;
  for k in select jsonb_object_keys(p_config) loop
    if k not in ('language','voice','lexicon','guardrails','formats','pipeline','models','schedule','budget_eur_day','enabled_agents','news_beats','reading_list') then
      errs := errs || jsonb_build_array('Campo desconhecido: ' || k);
    end if;
  end loop;
  if coalesce(btrim(p_config->>'voice'), '') = '' then errs := errs || jsonb_build_array('Falta a voz do cliente.'); end if;
  if coalesce(p_config->>'language', '') !~ '^[a-z]{2}(-[A-Z]{2})?$' then errs := errs || jsonb_build_array('Idioma inválido (ex.: pt-PT).'); end if;
  if jsonb_typeof(coalesce(p_config->'guardrails', '[]')) <> 'array' or jsonb_array_length(coalesce(p_config->'guardrails', '[]')) = 0 then
    errs := errs || jsonb_build_array('Tem de haver pelo menos uma regra de segurança.');
  end if;
  -- formatos: proporções entre min e max e a somar 1
  if jsonb_typeof(coalesce(p_config->'formats', 'null')) <> 'object' or (select count(*) from jsonb_object_keys(p_config->'formats')) = 0 then
    errs := errs || jsonb_build_array('Tem de haver pelo menos um formato.');
  else
    for k, f in select * from jsonb_each(p_config->'formats') loop
      begin
        if (f->>'share')::numeric < (f->>'min')::numeric or (f->>'share')::numeric > (f->>'max')::numeric then
          errs := errs || jsonb_build_array(format('Formato %s: a proporção tem de estar entre o mínimo e o máximo.', k));
        end if;
        if (f->'palavras'->>0)::integer >= (f->'palavras'->>1)::integer or (f->'palavras'->>0)::integer < 10 then
          errs := errs || jsonb_build_array(format('Formato %s: intervalo de palavras inválido.', k));
        end if;
        s := s + (f->>'share')::numeric;
      exception when others then
        errs := errs || jsonb_build_array(format('Formato %s: valores em falta ou inválidos.', k));
      end;
    end loop;
    if abs(s - 1) > 0.05 then errs := errs || jsonb_build_array(format('As proporções dos formatos somam %s; têm de somar 1 (±0,05).', round(s, 2))); end if;
  end if;
  -- pipeline
  for k, num in select x.k, x.v from (values
      ('scripts_per_day', (p->>'scripts_per_day')::numeric), ('hooks_per_slot', (p->>'hooks_per_slot')::numeric),
      ('critic_threshold', (p->>'critic_threshold')::numeric), ('concurrency', (p->>'concurrency')::numeric)) x(k, v) loop
    if num is null then errs := errs || jsonb_build_array('Falta pipeline.' || k); end if;
  end loop;
  if (p->>'scripts_per_day')::numeric not between 1 and 100 then errs := errs || jsonb_build_array('Guiões por dia entre 1 e 100.'); end if;
  if (p->>'hooks_per_slot')::numeric not between 1 and 20 then errs := errs || jsonb_build_array('Hooks por guião entre 1 e 20.'); end if;
  if (p->>'critic_threshold')::numeric not between 0 and 10 then errs := errs || jsonb_build_array('Limiar do Crítico entre 0 e 10.'); end if;
  if (p->>'concurrency')::numeric not between 1 and 20 then errs := errs || jsonb_build_array('Concorrência entre 1 e 20.'); end if;
  -- modelos: só modelos conhecidos e agentes do catálogo
  if p_config ? 'models' then
    for k, m in select * from jsonb_each_text(p_config->'models') loop
      if not exists (select 1 from agent_models where key = m and active) then errs := errs || jsonb_build_array(format('Modelo desconhecido para %s: %s', k, m)); end if;
    end loop;
  end if;
  if p_config ? 'enabled_agents' and exists (select 1 from jsonb_array_elements_text(p_config->'enabled_agents') x where x not in (select key from agent_definitions)) then
    errs := errs || jsonb_build_array('Há agentes ativos que não existem no catálogo.');
  end if;
  -- agenda e orçamento
  if coalesce((p_config->'schedule'->>'enabled')::boolean, false) and coalesce(p_config->'schedule'->>'time', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' then
    errs := errs || jsonb_build_array('Hora da corrida diária inválida (HH:MM).');
  end if;
  if p_config->>'budget_eur_day' is null then warns := warns || jsonb_build_array('Sem limite de custo diário: as corridas não param por custo.');
  elsif (p_config->>'budget_eur_day')::numeric not between 0.5 and 1000 then errs := errs || jsonb_build_array('Limite de custo diário entre 0,50 e 1000 EUR.'); end if;
  if not coalesce((p_config->'schedule'->>'enabled')::boolean, false) then warns := warns || jsonb_build_array('Corrida diária desligada: só corre quando alguém carregar em Correr.'); end if;
  return jsonb_build_object('ok', jsonb_array_length(errs) = 0, 'errors', errs, 'warnings', warns);
exception when others then
  return jsonb_build_object('ok', false, 'errors', errs || jsonb_build_array('Configuração com valores inválidos: ' || sqlerrm), 'warnings', warns);
end $$;

-- ───────────── leitura ─────────────
create or replace function public.agents_overview(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare act agent_config_versions; costs boolean; cfg boolean; tz text; today date;
begin
  perform public._content_require('agents.read', p_ws, p_token, 'agents.overview', null);
  costs := public.ws_can('costs.read', p_ws, p_token);
  cfg := public.ws_can('agents.configure', p_ws, p_token);
  select * into act from agent_config_versions where workspace_id = p_ws and status = 'active';
  select coalesce(timezone, 'UTC') into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  return jsonb_build_object(
    'agents', (select coalesce(jsonb_agg(jsonb_build_object('key', d.key, 'name', d.name, 'stage', d.stage, 'description', d.description,
                 'model', coalesce(act.config->'models'->>d.key, d.default_model), 'tools', d.tools, 'reads', d.reads, 'writes', d.writes,
                 'enabled', act.id is null or not (act.config ? 'enabled_agents') or act.config->'enabled_agents' ? d.key) order by d.position), '[]')
               from agent_definitions d),
    'active', case when act.id is null then null else jsonb_build_object('id', act.id, 'version_no', act.version_no, 'activated_at', act.activated_at,
                 'activated_label', act.activated_label, 'schedule', act.config->'schedule', 'budget_eur_day', case when costs then act.config->'budget_eur_day' end,
                 'scripts_per_day', act.config->'pipeline'->'scripts_per_day') end,
    'versions', case when cfg then (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'status', v.status, 'notes', v.notes,
                 'validation', v.validation, 'created_label', v.created_label, 'created_at', v.created_at, 'activated_at', v.activated_at)
                 order by v.version_no desc), '[]') from agent_config_versions v where v.workspace_id = p_ws) end,
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'status', j.status, 'idempotency_key', j.idempotency_key,
                 'attempts', j.attempts, 'max_attempts', j.max_attempts, 'scheduled_for', j.scheduled_for, 'next_attempt_at', j.next_attempt_at,
                 'started_at', j.started_at, 'finished_at', j.finished_at, 'heartbeat_at', j.heartbeat_at, 'progress', j.progress,
                 'last_error', j.last_error, 'cancel_requested', j.cancel_requested, 'run_id', j.run_id, 'requested_label', j.requested_label,
                 'config_version', (select version_no from agent_config_versions where id = j.config_version_id),
                 'cost_eur', case when costs then j.cost_eur end, 'tokens_in', case when costs then j.tokens_in end, 'tokens_out', case when costs then j.tokens_out end,
                 'result', j.result) order by j.created_at desc), '[]')
             from (select * from agent_jobs where workspace_id = p_ws order by created_at desc limit 30) j),
    'spend_today', case when costs then (select coalesce(sum(cost_eur), 0) from agent_jobs where workspace_id = p_ws
                    and (created_at at time zone tz)::date = today) end,
    'worker', (select jsonb_build_object('id', w.id, 'last_seen', w.last_seen, 'version', w.version) from agent_workers w order by w.last_seen desc limit 1),
    'can', jsonb_build_object('run', public.ws_can('agents.run', p_ws, p_token), 'configure', cfg, 'costs', costs));
end $$;

create or replace function public.agent_config_get(p_ws text, p_version uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v agent_config_versions;
begin
  perform public._content_require('agents.configure', p_ws, null, 'agent_config.get', p_version::text);
  if p_version is null then
    select * into v from agent_config_versions where workspace_id = p_ws order by (status = 'active') desc, version_no desc limit 1;
  else
    select * into v from agent_config_versions where id = p_version and workspace_id = p_ws;
  end if;
  return jsonb_build_object('version', to_jsonb(v), 'models', (select jsonb_agg(jsonb_build_object('key', key, 'label', label)) from agent_models where active),
                            'agents', (select jsonb_agg(jsonb_build_object('key', key, 'name', name, 'default_model', default_model) order by position) from agent_definitions));
end $$;

-- ───────────── escrita: versões ─────────────
create or replace function public.agent_config_save(p_ws text, p_config jsonb, p_notes text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); v agent_config_versions; val jsonb;
begin
  perform public._content_require('agents.configure', p_ws, null, 'agent_config.save', null);
  val := public.agent_config_validate(p_config);
  perform pg_advisory_xact_lock(hashtext('agent_config:' || p_ws));
  insert into agent_config_versions (workspace_id, version_no, config, notes, validation, created_by, created_label)
  values (p_ws, coalesce((select max(version_no) from agent_config_versions where workspace_id = p_ws), 0) + 1, p_config,
          nullif(btrim(p_notes), ''), val, (a->>'uid')::uuid, a->>'label')
  returning * into v;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'agent_config.saved', 'agent_config', v.id::text, jsonb_build_object('version_no', v.version_no, 'ok', val->'ok'));
  return to_jsonb(v);
end $$;

-- Ativar = a versão passou na validação; a anterior fica retirada. Voltar atrás = ativar uma versão antiga.
create or replace function public.agent_config_activate(p_version uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); v agent_config_versions; prev uuid; val jsonb;
begin
  select * into v from agent_config_versions where id = p_version for update;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('agents.configure', v.workspace_id, null, 'agent_config.activate', v.id::text);
  val := public.agent_config_validate(v.config);
  update agent_config_versions set validation = val where id = v.id;
  if not (val->>'ok')::boolean then raise exception 'configuracao_invalida' using errcode = '22023'; end if;
  if v.status = 'active' then return to_jsonb(v); end if;
  select id into prev from agent_config_versions where workspace_id = v.workspace_id and status = 'active' for update;
  update agent_config_versions set status = 'retired' where id = prev;
  update agent_config_versions set status = 'active', activated_at = now(), activated_label = a->>'label' where id = v.id returning * into v;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', v.workspace_id, 'agent_config.activated', 'agent_config', v.id::text,
          jsonb_build_object('active', prev), jsonb_build_object('active', v.id, 'version_no', v.version_no));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (v.workspace_id, 'agent.config_activated', 'agent_config', v.id::text, jsonb_build_object('version_no', v.version_no, 'previous', prev));
  return to_jsonb(v);
end $$;

-- ───────────── escrita: execuções ─────────────
create or replace function public._agent_enqueue(p_ws text, p_kind text, p_key text, p_when timestamptz, p_actor jsonb, p_params jsonb) returns agent_jobs
language plpgsql security definer set search_path = public as $$
declare act agent_config_versions; j agent_jobs; tz text; spent numeric;
begin
  select * into act from agent_config_versions where workspace_id = p_ws and status = 'active';
  if act.id is null then raise exception 'sem_configuracao_ativa' using errcode = '22023'; end if;
  select * into j from agent_jobs where workspace_id = p_ws and idempotency_key = p_key;
  if j.id is not null then return j; end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = p_ws;
  if act.config->>'budget_eur_day' is not null then
    select coalesce(sum(cost_eur), 0) into spent from agent_jobs where workspace_id = p_ws and (created_at at time zone tz)::date = (now() at time zone tz)::date;
    if spent >= (act.config->>'budget_eur_day')::numeric then raise exception 'orcamento_esgotado' using errcode = '22023'; end if;
  end if;
  insert into agent_jobs (workspace_id, kind, idempotency_key, config_version_id, params, scheduled_for, next_attempt_at, budget_cap_eur,
                          requested_by, requested_kind, requested_label)
  values (p_ws, p_kind, p_key, act.id, coalesce(p_params, '{}'), coalesce(p_when, now()), coalesce(p_when, now()),
          (act.config->>'budget_eur_day')::numeric, (p_actor->>'uid')::uuid, p_actor->>'kind', p_actor->>'label')
  on conflict (workspace_id, idempotency_key) do nothing
  returning * into j;
  if j.id is null then select * into j from agent_jobs where workspace_id = p_ws and idempotency_key = p_key; return j; end if;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'agent.job_queued', 'agent_job', j.id::text, jsonb_build_object('kind', p_kind, 'key', p_key));
  return j;
end $$;

-- "Correr agora": por omissão uma corrida por tipo e por dia do cliente (repetir devolve a mesma).
create or replace function public.agent_job_enqueue(p_ws text, p_kind text, p_key text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); j agent_jobs; tz text; key text;
begin
  perform public._content_require('agents.run', p_ws, p_token, 'agent_job.enqueue', null);
  if p_kind not in ('daily_pipeline','scouts','analysis') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = p_ws;
  key := coalesce(nullif(btrim(p_key), ''), p_kind || ':' || to_char(now() at time zone tz, 'YYYY-MM-DD'));
  if key !~ '^[A-Za-z0-9:_.-]{3,120}$' then raise exception 'chave_invalida' using errcode = '22023'; end if;
  j := public._agent_enqueue(p_ws, p_kind, key, null, a, '{}');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'agent_job.enqueued', 'agent_job', j.id::text, jsonb_build_object('kind', p_kind, 'key', key));
  return to_jsonb(j);
end $$;

create or replace function public.agent_job_cancel(p_job uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); j agent_jobs;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null then raise exception 'execucao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('agents.run', j.workspace_id, p_token, 'agent_job.cancel', j.id::text);
  if j.status = 'queued' then
    update agent_jobs set status = 'cancelled', finished_at = now(), cancel_requested = true where id = j.id returning * into j;
  elsif j.status = 'running' then
    update agent_jobs set cancel_requested = true where id = j.id returning * into j;   -- o worker para no próximo heartbeat
  else
    raise exception 'transicao_invalida' using errcode = '22023';
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', j.workspace_id, 'agent_job.cancel_requested', 'agent_job', j.id::text, jsonb_build_object('status', j.status));
  return to_jsonb(j);
end $$;

-- Repetir uma execução que falhou, morreu ou foi cancelada (reprocessamento autorizado, FR-17-14).
create or replace function public.agent_job_retry(p_job uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); j agent_jobs;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null then raise exception 'execucao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('agents.run', j.workspace_id, p_token, 'agent_job.retry', j.id::text);
  if j.status not in ('failed','dead','cancelled') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
  update agent_jobs set status = 'queued', next_attempt_at = now(), cancel_requested = false, finished_at = null,
         max_attempts = greatest(max_attempts, least(attempts + 1, 10)) where id = j.id returning * into j;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', j.workspace_id, 'agent_job.retried', 'agent_job', j.id::text, jsonb_build_object('attempts', j.attempts));
  return to_jsonb(j);
end $$;

-- ───────────── worker (só service_role / dono da base) ─────────────
-- Enfileira as corridas diárias que já passaram da hora em cada cliente com agenda ligada. Idempotente por dia.
create or replace function public.agent_schedule_tick() returns integer
language plpgsql security definer set search_path = public as $$
declare v agent_config_versions; tz text; n integer := 0; j agent_jobs; local_now timestamp;
begin
  for v in select x.* from agent_config_versions x join clients c on c.id = x.workspace_id
            where x.status = 'active' and c.status = 'active' and coalesce((x.config->'schedule'->>'enabled')::boolean, false) loop
    select coalesce(timezone, 'UTC') into tz from clients where id = v.workspace_id;
    local_now := now() at time zone tz;
    if to_char(local_now, 'HH24:MI') >= v.config->'schedule'->>'time' then
      begin
        j := public._agent_enqueue(v.workspace_id, 'daily_pipeline', 'daily_pipeline:' || to_char(local_now, 'YYYY-MM-DD'), now(),
                                   jsonb_build_object('kind', 'system', 'uid', null, 'label', 'Agenda'), jsonb_build_object('scheduled', true));
        if j.created_at > now() - interval '5 seconds' then n := n + 1; end if;
      exception when sqlstate '22023' then null;  -- sem orçamento: não enfileira
      end;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.worker_claim(p_worker text, p_kinds text[] default array['daily_pipeline','scouts','analysis'], p_lease_seconds integer default 600)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; cfg jsonb;
begin
  if p_worker is null or length(p_worker) not between 3 and 80 then raise exception 'worker_invalido' using errcode = '22023'; end if;
  insert into agent_workers (id, kinds, last_seen) values (p_worker, p_kinds, now())
  on conflict (id) do update set kinds = excluded.kinds, last_seen = now();
  perform public.agent_schedule_tick();
  -- leases expirados: a tentativa perdeu-se; volta à fila (ou morre se esgotou)
  update agent_job_attempts ja set status = 'lost', finished_at = now()
    from agent_jobs x where ja.job_id = x.id and ja.status = 'running' and x.status = 'running' and x.locked_until < now();
  update agent_jobs set status = case when attempts >= max_attempts then 'dead' else 'queued' end,
         next_attempt_at = now(), locked_by = null, locked_until = null,
         last_error = coalesce(last_error, 'worker deixou de responder'), finished_at = case when attempts >= max_attempts then now() end
   where status = 'running' and locked_until < now();
  select * into j from agent_jobs
   where status = 'queued' and next_attempt_at <= now() and scheduled_for <= now() and kind = any (p_kinds)
   order by scheduled_for, created_at limit 1 for update skip locked;
  if j.id is null then return null; end if;
  update agent_jobs set status = 'running', attempts = attempts + 1, locked_by = p_worker, locked_until = now() + make_interval(secs => p_lease_seconds),
         heartbeat_at = now(), started_at = coalesce(started_at, now()), last_error = null
   where id = j.id returning * into j;
  insert into agent_job_attempts (job_id, workspace_id, attempt, worker) values (j.id, j.workspace_id, j.attempts, p_worker);
  select config into cfg from agent_config_versions where id = j.config_version_id;
  return jsonb_build_object('job', to_jsonb(j), 'config', cfg, 'workspace', (select jsonb_build_object('id', id, 'name', name, 'timezone', timezone) from clients where id = j.workspace_id));
end $$;

create or replace function public.worker_heartbeat(p_job uuid, p_worker text, p_progress jsonb default null, p_lease_seconds integer default 600)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  update agent_jobs set heartbeat_at = now(), locked_until = now() + make_interval(secs => p_lease_seconds), progress = coalesce(p_progress, progress)
   where id = j.id returning * into j;
  update agent_workers set last_seen = now() where id = p_worker;
  return jsonb_build_object('cancel', j.cancel_requested, 'budget_cap_eur', j.budget_cap_eur);
end $$;

create or replace function public.worker_finish(p_job uuid, p_worker text, p_ok boolean, p_result jsonb default null, p_error text default null,
                                                p_retryable boolean default true, p_cost_eur numeric default null, p_tokens_in bigint default null,
                                                p_tokens_out bigint default null, p_run_id text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; st text; u record;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  st := case when p_ok then 'succeeded'
             when j.cancel_requested then 'cancelled'
             when p_retryable and j.attempts < j.max_attempts then 'queued'
             else 'dead' end;
  update agent_jobs set status = st, locked_by = null, locked_until = null, result = coalesce(p_result, result),
         last_error = case when p_ok then null else left(p_error, 2000) end,
         next_attempt_at = case when st = 'queued' then now() + make_interval(mins => least(60, power(2, j.attempts)::integer)) else next_attempt_at end,
         finished_at = case when st in ('succeeded','cancelled','dead') then now() end,
         cost_eur = coalesce(cost_eur, 0) + coalesce(p_cost_eur, 0), tokens_in = coalesce(tokens_in, 0) + coalesce(p_tokens_in, 0),
         tokens_out = coalesce(tokens_out, 0) + coalesce(p_tokens_out, 0), run_id = coalesce(p_run_id, run_id)
   where id = j.id returning * into j;
  update agent_job_attempts set status = case when p_ok then 'succeeded' when st = 'cancelled' then 'cancelled' else 'failed' end,
         finished_at = now(), error = left(p_error, 2000), cost_eur = p_cost_eur
   where job_id = j.id and attempt = j.attempts;
  update agent_workers set last_seen = now() where id = p_worker;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'agent.job_' || case st when 'queued' then 'failed' else st end, 'agent_job', j.id::text,
          jsonb_build_object('attempt', j.attempts, 'error', left(p_error, 300), 'will_retry', st = 'queued'));
  if st = 'dead' then
    -- fila de exceções: quem configura os agentes é avisado
    for u in select a.user_id from workspace_access a where a.workspace_id = j.workspace_id and a.status = 'active'
              and public._authorize('agents.configure', j.workspace_id, a.user_id) loop
      perform public._notify(u.user_id, j.workspace_id, 'automation_error', 'agent_job', j.id::text,
                             'Execução dos agentes falhou: ' || j.kind, left(p_error, 300), 'job_dead:' || j.id);
    end loop;
  end if;
  return jsonb_build_object('status', st, 'next_attempt_at', j.next_attempt_at);
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public.agent_config_guard(), public.agent_jobs_guard(), public.agent_jobs_same_ws(),
  public._agent_enqueue(text,text,text,timestamptz,jsonb,jsonb), public.agent_schedule_tick(),
  public.worker_claim(text,text[],integer), public.worker_heartbeat(uuid,text,jsonb,integer),
  public.worker_finish(uuid,text,boolean,jsonb,text,boolean,numeric,bigint,bigint,text) from public, anon, authenticated;
grant execute on function public.worker_claim(text,text[],integer), public.worker_heartbeat(uuid,text,jsonb,integer),
  public.worker_finish(uuid,text,boolean,jsonb,text,boolean,numeric,bigint,bigint,text), public.agent_schedule_tick() to service_role;
revoke all on function public.agent_config_validate(jsonb), public.agents_overview(text,text), public.agent_config_get(text,uuid),
  public.agent_config_save(text,jsonb,text), public.agent_config_activate(uuid), public.agent_job_enqueue(text,text,text,text),
  public.agent_job_cancel(uuid,text), public.agent_job_retry(uuid,text) from public, anon;
grant execute on function public.agents_overview(text,text), public.agent_job_enqueue(text,text,text,text), public.agent_job_cancel(uuid,text),
  public.agent_job_retry(uuid,text) to anon, authenticated;
grant execute on function public.agent_config_validate(jsonb), public.agent_config_get(text,uuid), public.agent_config_save(text,jsonb,text),
  public.agent_config_activate(uuid) to authenticated;

/* Rollback:
drop function worker_finish, worker_heartbeat, worker_claim, agent_schedule_tick, agent_job_retry, agent_job_cancel, agent_job_enqueue, _agent_enqueue,
  agent_config_activate, agent_config_save, agent_config_get, agents_overview, agent_config_validate, agent_jobs_same_ws, agent_jobs_guard, agent_config_guard;
drop table agent_job_attempts, agent_jobs, agent_workers, agent_config_versions, agent_definitions, agent_models;
alter table notifications drop constraint notifications_kind_check;  -- recriar sem 'automation_error' depois de apagar essas notificações
update capabilities set status = 'W4' where key in ('agents.run','agents.configure','costs.read');
*/
