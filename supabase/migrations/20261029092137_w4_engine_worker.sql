-- W4-02: o motor liga-se à fila (PRD FR-06-03, FR-06-05 parcial, FR-06-06 parcial; ADR-0011).
-- Só aditivo: o motor atual (ligação de dono) continua a funcionar. Rollback: bloco no fim.

-- preços por modelo (EUR por milhão de tokens); vazio = custo desconhecido, a app mostra só tokens
alter table public.agent_models add column if not exists eur_per_mtok_in numeric check (eur_per_mtok_in >= 0),
                                add column if not exists eur_per_mtok_out numeric check (eur_per_mtok_out >= 0);
-- tokens por chamada de agente (FR-06-05)
alter table public.agent_log add column if not exists tokens_in integer, add column if not exists tokens_out integer;

-- o que cada execução criou: torna a gravação idempotente por (execução, slot)
create table public.agent_job_outputs (
  job_id uuid not null references public.agent_jobs (id),
  slot integer not null check (slot between 0 and 1000),
  workspace_id text not null references public.clients (id),
  content_id text not null references public.guioes (id),
  created_at timestamptz not null default now(),
  primary key (job_id, slot)
);
alter table public.agent_job_outputs enable row level security;
revoke all on public.agent_job_outputs from anon, authenticated;

-- dia dos guiões: 0 = o próprio dia da corrida, 1 = o dia seguinte (preset Numeiro: corre às 18:00 para amanhã)
create or replace function public._agent_target_offset(p_config jsonb) returns integer language sql immutable as $$
  select coalesce((p_config->'pipeline'->>'target_day_offset')::integer, 1)
$$;

create or replace function public.worker_save_script(p_job uuid, p_worker text, p_slot integer, p_script jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; cfg jsonb; tz text; d date; n integer; cid text; o agent_job_outputs; hooks jsonb; h jsonb; corpo text;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  if p_slot is null or p_slot not between 0 and 1000 then raise exception 'slot_invalido' using errcode = '22023'; end if;
  -- repetir a mesma gravação devolve o guião que já existe
  select * into o from agent_job_outputs where job_id = j.id and slot = p_slot;
  if o.job_id is not null then
    return jsonb_build_object('id', o.content_id, 'created', false);
  end if;
  -- validação do que o motor manda: nunca confiar no payload
  corpo := btrim(coalesce(p_script->>'corpo', ''));
  if corpo = '' or length(corpo) > 20000 then raise exception 'corpo_invalido' using errcode = '22023'; end if;
  if jsonb_typeof(p_script->'hooks') <> 'array' or jsonb_array_length(p_script->'hooks') not between 1 and 10 then
    raise exception 'hooks_invalidos' using errcode = '22023';
  end if;
  hooks := '[]';
  for h in select * from jsonb_array_elements(p_script->'hooks') loop
    if btrim(coalesce(h->>'text', h->>'hook', '')) = '' or length(coalesce(h->>'text', h->>'hook')) > 500 then
      raise exception 'hooks_invalidos' using errcode = '22023';
    end if;
    hooks := hooks || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('text', btrim(coalesce(h->>'text', h->>'hook')),
              'mecanismo', left(h->>'mecanismo', 40), 'nota_critico', (h->>'nota_critico')::numeric)));
  end loop;
  select config into cfg from agent_config_versions where id = j.config_version_id;
  select coalesce(timezone, 'UTC') into tz from clients where id = j.workspace_id;
  d := (j.scheduled_for at time zone tz)::date + public._agent_target_offset(cfg);
  perform pg_advisory_xact_lock(hashtext('guioes:' || j.workspace_id || ':' || d::text));
  select coalesce(max(g.n), 0) + 1 into n from guioes g where g.client_id = j.workspace_id and g.date = d;
  loop
    cid := j.workspace_id || '-' || to_char(d, 'YYYY-MM-DD') || '-' || lpad(n::text, 2, '0');
    exit when not exists (select 1 from guioes where id = cid);
    n := n + 1;
  end loop;
  perform set_config('clipstudio.actor_kind', 'engine', true);
  perform set_config('clipstudio.actor_label', left('Motor · ' || coalesce(j.run_id, p_script->>'run_id', j.id::text), 80), true);
  -- entra sempre em revisão: um guião do motor nunca fica aprovado nem gravado sozinho (AGENTS §7, FR-06-06)
  insert into guioes (id, client_id, date, n, formato, maquina, tema, hooks, corpo, fonte, legenda, comentario_fixado, critic_score,
                      origem, status, validado, gravado, cta, notas)
  values (cid, j.workspace_id, d, n, left(p_script->>'formato', 60), left(p_script->>'maquina', 60), left(p_script->>'tema', 300), hooks, corpo,
          left(p_script->>'fonte', 1000), left(p_script->>'legenda', 2200), left(p_script->>'comentario_fixado', 1000),
          case when (p_script->>'critic_score') ~ '^\d+(\.\d+)?$' then least(10, (p_script->>'critic_score')::numeric) end,
          'motor', 'aprovado', false, false, left(p_script->>'cta', 1000), left(p_script->>'notas', 4000));
  insert into agent_job_outputs (job_id, slot, workspace_id, content_id) values (j.id, p_slot, j.workspace_id, cid);
  update agent_jobs set heartbeat_at = now(), locked_until = greatest(locked_until, now() + interval '10 minutes') where id = j.id;
  return jsonb_build_object('id', cid, 'date', d, 'n', n, 'created', true);
end $$;

-- o claim passa a levar preços, orçamento que sobra e o dia alvo
create or replace function public.worker_claim(p_worker text, p_kinds text[] default array['daily_pipeline','scouts','analysis'], p_lease_seconds integer default 600)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; cfg jsonb; tz text; spent numeric;
begin
  if p_worker is null or length(p_worker) not between 3 and 80 then raise exception 'worker_invalido' using errcode = '22023'; end if;
  insert into agent_workers (id, kinds, last_seen) values (p_worker, p_kinds, now())
  on conflict (id) do update set kinds = excluded.kinds, last_seen = now();
  perform public.agent_schedule_tick();
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
  select coalesce(timezone, 'UTC') into tz from clients where id = j.workspace_id;
  select coalesce(sum(cost_eur), 0) into spent from agent_jobs
   where workspace_id = j.workspace_id and id <> j.id and (created_at at time zone tz)::date = (now() at time zone tz)::date;
  return jsonb_build_object('job', to_jsonb(j), 'config', cfg,
    'workspace', (select jsonb_build_object('id', id, 'name', name, 'timezone', timezone) from clients where id = j.workspace_id),
    'target_date', (j.scheduled_for at time zone tz)::date + public._agent_target_offset(cfg),
    'budget_remaining_eur', case when j.budget_cap_eur is not null then greatest(0, j.budget_cap_eur - spent - coalesce(j.cost_eur, 0)) end,
    'models', (select jsonb_object_agg(key, jsonb_build_object('in', eur_per_mtok_in, 'out', eur_per_mtok_out)) from agent_models));
end $$;

-- validação: aceita o dia alvo
create or replace function public._agent_config_validate_extra(p_config jsonb) returns jsonb language plpgsql immutable as $$
declare o text := p_config->'pipeline'->>'target_day_offset';
begin
  if o is not null and o not in ('0','1') then return jsonb_build_array('O dia dos guiões tem de ser o próprio dia (0) ou o seguinte (1).'); end if;
  return '[]';
end $$;
do $$
declare src text;
begin
  select pg_get_functiondef('public.agent_config_validate(jsonb)'::regprocedure) into src;
  if position('_agent_config_validate_extra' in src) = 0 then
    src := replace(src, '  return jsonb_build_object(''ok'', jsonb_array_length(errs) = 0, ''errors'', errs, ''warnings'', warns);
exception',
      '  errs := errs || public._agent_config_validate_extra(p_config);
  return jsonb_build_object(''ok'', jsonb_array_length(errs) = 0, ''errors'', errs, ''warnings'', warns);
exception');
    if position('_agent_config_validate_extra' in src) = 0 then raise exception 'nao_consegui_alterar_agent_config_validate'; end if;
    execute src;
  end if;
end $$;

-- utilizador próprio do worker, com o mínimo: sem login até o dono definir a password no Supabase
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'engine_worker') then create role engine_worker nologin noinherit; end if;
end $$;
grant usage on schema public to engine_worker;
grant select, insert, update on public.reels, public.themes, public.reel_themes, public.quotes, public.meta, public.generated,
  public.agent_log, public.ideas, public.daily_reports, public.script_analysis, public.comment_analysis to engine_worker;
do $$
declare t text;
begin
  foreach t in array array['reels','themes','reel_themes','quotes','meta','generated','agent_log','ideas','daily_reports','script_analysis','comment_analysis'] loop
    execute format('drop policy if exists %I on public.%I', t || '_engine_worker', t);
    execute format('create policy %I on public.%I for all to engine_worker using (true) with check (true)', t || '_engine_worker', t);
  end loop;
  -- só as sequências destas tabelas
  for t in select distinct s.oid::regclass::text from pg_depend d join pg_class s on s.oid = d.objid and s.relkind = 'S'
            join pg_class c on c.oid = d.refobjid
           where c.relnamespace = 'public'::regnamespace
             and c.relname = any (array['reels','themes','reel_themes','quotes','meta','generated','agent_log','ideas','daily_reports','script_analysis','comment_analysis']) loop
    execute format('grant usage, select on sequence %s to engine_worker', t);
  end loop;
end $$;
revoke all on function public.worker_save_script(uuid,text,integer,jsonb), public._agent_target_offset(jsonb),
  public._agent_config_validate_extra(jsonb) from public, anon, authenticated;
grant execute on function public.worker_claim(text,text[],integer), public.worker_heartbeat(uuid,text,jsonb,integer),
  public.worker_finish(uuid,text,boolean,jsonb,text,boolean,numeric,bigint,bigint,text), public.worker_save_script(uuid,text,integer,jsonb)
  to service_role, engine_worker;

-- agenda: o Supabase põe a corrida diária na fila mesmo que o worker esteja a reiniciar
create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'agent-schedule-tick') then
    perform cron.schedule('agent-schedule-tick', '*/5 * * * *', 'select public.agent_schedule_tick()');
  end if;
end $$;

/* Rollback:
select cron.unschedule('agent-schedule-tick');
drop function worker_save_script(uuid,text,integer,jsonb);
-- worker_claim: recriar a versão de 20261029084441; agent_config_validate: tirar a linha _agent_config_validate_extra
drop function _agent_config_validate_extra(jsonb), _agent_target_offset(jsonb);
drop table agent_job_outputs;
-- políticas *_engine_worker, grants e role engine_worker: drop policy ...; revoke ...; drop role engine_worker;
alter table agent_log drop column tokens_in, drop column tokens_out;
alter table agent_models drop column eur_per_mtok_in, drop column eur_per_mtok_out;
*/
