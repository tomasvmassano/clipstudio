-- W10-01 · Saúde do sistema (PRD FR-17-15; FR-17-14; AGENTS §8, §10; ADR-0058, número sujeito a renumeração).
-- O que faltava a FR-17-15: alertas e um painel de saúde. Só dados persistidos, nunca estados inventados:
--  * workers: agent_workers (o worker dos agentes e o de media escrevem aqui em worker_claim / media_worker_claim);
--  * filas: agent_jobs e media_jobs (à espera, prontos, o mais antigo, a correr, lease expirada);
--  * falhas: failed/dead nas últimas 24 h e 7 dias, com o último erro sem segredos nem emails (_ops_redact);
--  * alertas: ops_health_tick (pg_cron, de 5 em 5 minutos) avisa os donos da agência, uma vez por incidente:
--      - worker sem contacto há mais de 10 minutos com trabalho pronto à espera (por cliente e origem);
--      - trabalho que foi para dead (últimas 24 h).
--    Idempotente: cada incidente tem uma chave única em ops_health_alerts e a notificação usa a mesma chave de dedupe.
-- Espaço: agência. Capacidade nova ops.health (org): dono e admin da agência. O dono vê todos os clientes ativos;
-- o admin só os clientes a que está atribuído; dentro de cada cliente, agentes exige agents.read e media exige media.read.
-- Expand (só aditivo): 1 capacidade, 2 tabelas fechadas à API, 2 índices parciais, funções novas, 1 tipo de notificação
-- (o check de notifications.kind é alargado a partir da definição atual), _ops_category passa a pôr system_health em
-- "Alerta", 1 job pg_cron. Não muda nenhuma função de worker. Rollback no fim.

-- ───────────── capacidade ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('ops.health', 'Agência', 'M', array['org'], 'ativo', 'Ver a saúde do sistema: workers, filas, trabalhos a correr e falhas')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
insert into role_capabilities (scope, role, capability) values
  ('org', 'agency_owner', 'ops.health'), ('org', 'agency_admin', 'ops.health')
on conflict do nothing;

-- ───────────── tabelas (fechadas à API: só pelas funções) ─────────────
-- Um incidente por linha. dedupe_key única = um aviso por incidente, por mais vezes que o tick corra.
create table if not exists public.ops_health_alerts (
  id bigint generated always as identity primary key,
  dedupe_key text not null unique check (char_length(dedupe_key) between 5 and 200),
  kind text not null check (kind in ('worker_down', 'job_dead')),
  source text not null check (source in ('agent', 'media')),
  workspace_id text not null references public.clients(id),
  job_id uuid,
  detail jsonb not null default '{}',
  notified int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists ops_health_alerts_ws on public.ops_health_alerts (workspace_id, created_at desc);
alter table public.ops_health_alerts enable row level security;
revoke all on public.ops_health_alerts from anon, authenticated;

-- Última corrida do tick (uma linha): o painel mostra se os alertas estão mesmo a correr.
create table if not exists public.ops_health_runs (
  key text primary key check (key = 'tick'),
  last_run_at timestamptz not null,
  last_result jsonb not null default '{}'
);
alter table public.ops_health_runs enable row level security;
revoke all on public.ops_health_runs from anon, authenticated;

create index if not exists agent_jobs_failed_idx on public.agent_jobs (finished_at desc) where status in ('failed', 'dead');
create index if not exists media_jobs_failed_idx on public.media_jobs (finished_at desc) where status in ('failed', 'dead');

-- ───────────── notificação system_health ─────────────
-- O check de kind é alargado a partir da definição que estiver na base (não da lista escrita aqui), para não apagar
-- tipos acrescentados por outras migrações.
do $$
declare def text; kinds text[];
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  if def is null then raise exception 'notifications_kind_check em falta: rever W10-01'; end if;
  if position('''system_health''' in def) > 0 then return; end if;
  kinds := array(select m[1] from regexp_matches(def, '''([a-z_]+)''', 'g') m) || array['system_health'];
  alter table public.notifications drop constraint notifications_kind_check;
  execute format('alter table public.notifications add constraint notifications_kind_check check (kind in (%s))',
                 (select string_agg(quote_literal(k), ', ') from unnest(kinds) k));
end $$;

insert into public.notification_event_defs (kind, group_key, label, description, recipients, channels, default_channels, mandatory, mandatory_reason, sort) values
  ('system_health', 'automacao', 'Saúde do sistema', 'Um worker deixou de contactar a base com trabalho à espera, ou um trabalho falhou de vez.',
   'Dono da agência', '{in_app}', '{in_app}', true, 'Falhas da infraestrutura chegam sempre ao dono da agência: sem isso o trabalho ficava parado sem ninguém saber.', 220)
on conflict (kind) do update set group_key = excluded.group_key, label = excluded.label, description = excluded.description, recipients = excluded.recipients,
  channels = excluded.channels, default_channels = excluded.default_channels, mandatory = excluded.mandatory, mandatory_reason = excluded.mandatory_reason, sort = excluded.sort;

-- Caixa (W6): system_health conta como alerta. Igual a 20261103171148_w5_media_review_notif_body.sql mais system_health.
create or replace function public._ops_category(p_reason text) returns text language sql immutable set search_path = public as $$
  select case
    when p_reason in ('assigned','blocked','changes_requested') then 'task'
    when p_reason = 'approval' then 'approval'
    when p_reason = 'recording' then 'recording'
    when p_reason in ('unassigned','blocked_other','talent_request') then 'decision'
    when p_reason in ('task_mention','script_mention','script_comment','video_comment') then 'mention'
    when p_reason in ('automation_error','task_blocked','overdue','system_health') then 'alert'
    else 'info' end
$$;

-- ───────────── ajudantes ─────────────
-- Tira segredos e dados pessoais de mensagens de erro antes de saírem da base (aceitação de FR-17-15).
create or replace function public._ops_redact(p text) returns text language sql immutable set search_path = public as $$
  select case when p is null then null else left(
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(p,
      '(bearer|basic)\s+[A-Za-z0-9._~+/=-]+', '\1 [removido]', 'gi'),
      'eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+', '[token removido]', 'g'),
      '((api[_-]?key|apikey|access[_-]?key|secret|token|password|passwd|pwd|signature|credential|authorization)["'']?\s*[=:]\s*["'']?)[^\s&"'',;]+', '\1[removido]', 'gi'),
      '([a-z][a-z0-9+.-]*://)[^:/@\s]+:[^@\s]+@', '\1[removido]@', 'gi'),
      '\m(sk|pk|rk)[-_][A-Za-z0-9_-]{12,}', '[chave removida]', 'g'),
      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email removido]', 'g'),
    300) end
$$;

-- Capacidade de agência; devolve a organização. Sem ops.health: 42501 (staff sem o papel, equipa do cliente, sem sessão).
create or replace function public._health_require() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select organization_id into org from agency_memberships where user_id = uid and status = 'active' order by created_at limit 1;
  if org is null or not public._org_can('ops.health', org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', 'ops.health', 'capability', 'ops.health');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return org;
end $$;

-- Clientes que a pessoa pode ver no painel: dono da agência, todos os ativos da organização; os outros, só os atribuídos
-- como staff da agência. Por cliente, agentes e media dependem da capacidade de leitura nesse cliente.
create or replace function public._health_ws(p_org uuid, p_uid uuid)
returns table (id text, name text, timezone text, agents boolean, media boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, coalesce(c.timezone, 'UTC'), public._authorize('agents.read', c.id, p_uid), public._authorize('media.read', c.id, p_uid)
    from clients c
   where c.organization_id = p_org and c.status = 'active'
     and (exists (select 1 from agency_memberships m where m.user_id = p_uid and m.organization_id = p_org
                    and m.agency_role = 'agency_owner' and m.status = 'active')
          or exists (select 1 from workspace_access a where a.workspace_id = c.id and a.user_id = p_uid and a.status = 'active'
                       and a.affiliation_type = 'agency_staff' and (a.expires_at is null or a.expires_at > now())))
$$;

-- Todos os trabalhos das duas filas numa forma só (sem verificação de acesso: só para as funções abaixo).
create or replace function public._health_jobs()
returns table (source text, id uuid, workspace_id text, kind text, status text, attempts int, max_attempts int, created_at timestamptz,
               ready_at timestamptz, started_at timestamptz, finished_at timestamptz, heartbeat_at timestamptz, locked_until timestamptz,
               locked_by text, last_error text, run_id text, asset_id uuid, cancel_requested boolean)
language sql stable security definer set search_path = public as $$
  select 'agent', j.id, j.workspace_id, j.kind, j.status, j.attempts, j.max_attempts, j.created_at, greatest(j.next_attempt_at, j.scheduled_for),
         j.started_at, j.finished_at, j.heartbeat_at, j.locked_until, j.locked_by, j.last_error, j.run_id, null::uuid, j.cancel_requested
    from agent_jobs j
  union all
  select 'media', j.id, j.workspace_id, j.kind, j.status, j.attempts, j.max_attempts, j.created_at, j.next_attempt_at,
         j.started_at, j.finished_at, j.heartbeat_at, j.locked_until, j.locked_by, j.last_error, null, j.asset_id, j.cancel_requested
    from media_jobs j
$$;

-- ───────────── leitura: painel de saúde ─────────────
create or replace function public.ops_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid; stale interval := interval '10 minutes'; tick ops_health_runs; scheduled boolean;
begin
  org := public._health_require();
  select * into tick from ops_health_runs where key = 'tick';
  if to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = $1 and active)' into scheduled using 'ops-health-tick';
  end if;
  return (
    with ws as (select * from public._health_ws(org, uid)),
    j as (select x.*, w.name as ws_name from public._health_jobs() x join ws w on w.id = x.workspace_id
           where (x.source = 'agent' and w.agents) or (x.source = 'media' and w.media)),
    wk as (select * from agent_workers),
    ready as (select j.* from j where j.status = 'queued' and j.ready_at <= now()),
    unc as (select r.* from ready r where not exists (select 1 from wk where r.kind = any (wk.kinds) and wk.last_seen > now() - stale))
    select jsonb_build_object(
      'generated_at', now(),
      'thresholds', jsonb_build_object('worker_stale_minutes', 10, 'window_days', 7),
      'tick', jsonb_build_object('scheduled', coalesce(scheduled, false), 'last_run_at', tick.last_run_at, 'last_result', tick.last_result),
      'workers', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'kinds', to_jsonb(w.kinds), 'version', w.version,
                   'last_seen', w.last_seen, 'recent', w.last_seen > now() - stale) order by w.last_seen desc) from wk w), '[]'),
      'queues', (select jsonb_agg(jsonb_build_object('source', s.src,
                   'queued', (select count(*) from j where j.source = s.src and j.status = 'queued'),
                   'ready', (select count(*) from ready r where r.source = s.src),
                   'oldest_ready_at', (select min(r.ready_at) from ready r where r.source = s.src),
                   'running', (select count(*) from j where j.source = s.src and j.status = 'running'),
                   'stalled', (select count(*) from j where j.source = s.src and j.status = 'running' and j.locked_until < now()),
                   'uncovered_kinds', coalesce((select jsonb_agg(distinct u.kind) from unc u where u.source = s.src), '[]'),
                   'uncovered', (select count(*) from unc u where u.source = s.src)) order by s.n)
                 from (values ('agent', 1), ('media', 2)) s(src, n)),
      'running', coalesce((select jsonb_agg(jsonb_build_object('source', x.source, 'id', x.id, 'kind', x.kind, 'workspace_id', x.workspace_id,
                   'workspace', x.ws_name, 'attempts', x.attempts, 'max_attempts', x.max_attempts, 'started_at', x.started_at,
                   'heartbeat_at', x.heartbeat_at, 'locked_until', x.locked_until, 'locked_by', x.locked_by, 'run_id', x.run_id,
                   'asset_id', x.asset_id, 'cancel_requested', x.cancel_requested, 'lease_expired', x.locked_until < now())
                   order by x.heartbeat_at nulls first)
                 from (select * from j where j.status = 'running' order by j.heartbeat_at nulls first limit 50) x), '[]'),
      'failure_counts', (select jsonb_object_agg(s.src, jsonb_build_object(
                   'failed_24h', (select count(*) from j where j.source = s.src and j.status = 'failed' and j.finished_at > now() - interval '24 hours'),
                   'dead_24h', (select count(*) from j where j.source = s.src and j.status = 'dead' and j.finished_at > now() - interval '24 hours'),
                   'failed_7d', (select count(*) from j where j.source = s.src and j.status = 'failed' and j.finished_at > now() - interval '7 days'),
                   'dead_7d', (select count(*) from j where j.source = s.src and j.status = 'dead' and j.finished_at > now() - interval '7 days')))
                 from (values ('agent'), ('media')) s(src)),
      'failures', coalesce((select jsonb_agg(jsonb_build_object('source', x.source, 'id', x.id, 'kind', x.kind, 'status', x.status,
                   'workspace_id', x.workspace_id, 'workspace', x.ws_name, 'attempts', x.attempts, 'max_attempts', x.max_attempts,
                   'finished_at', x.finished_at, 'run_id', x.run_id, 'asset_id', x.asset_id, 'last_error', public._ops_redact(x.last_error))
                   order by x.finished_at desc)
                 from (select * from j where j.status in ('failed', 'dead') and j.finished_at > now() - interval '7 days'
                        order by j.finished_at desc limit 100) x), '[]'),
      'workspaces', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'timezone', w.timezone,
                   'agent', case when w.agents then public._health_ws_counts(w.id, 'agent') end,
                   'media', case when w.media then public._health_ws_counts(w.id, 'media') end) order by lower(w.name)) from ws w), '[]'),
      'alerts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'source', a.source, 'workspace_id', a.workspace_id,
                   'workspace', w.name, 'job_id', a.job_id, 'detail', a.detail, 'notified', a.notified, 'created_at', a.created_at) order by a.created_at desc)
                 from (select * from ops_health_alerts x where x.created_at > now() - interval '7 days' order by x.created_at desc limit 200) a
                 join ws w on w.id = a.workspace_id and ((a.source = 'agent' and w.agents) or (a.source = 'media' and w.media))), '[]')
    ));
end $$;

-- Contagens de uma origem num cliente (o chamador já verificou o acesso).
create or replace function public._health_ws_counts(p_ws text, p_source text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'queued', count(*) filter (where status = 'queued'),
    'ready', count(*) filter (where status = 'queued' and ready_at <= now()),
    'oldest_ready_at', min(ready_at) filter (where status = 'queued' and ready_at <= now()),
    'running', count(*) filter (where status = 'running'),
    'stalled', count(*) filter (where status = 'running' and locked_until < now()),
    'failed_24h', count(*) filter (where status in ('failed', 'dead') and finished_at > now() - interval '24 hours'),
    'failed_7d', count(*) filter (where status in ('failed', 'dead') and finished_at > now() - interval '7 days'),
    'dead_7d', count(*) filter (where status = 'dead' and finished_at > now() - interval '7 days'))
  from public._health_jobs() where workspace_id = p_ws and source = p_source
$$;

-- ───────────── alertas (pg_cron, de 5 em 5 minutos) ─────────────
-- Avisa os donos da agência do cliente. Um aviso por incidente:
--  worker_down: chave = origem + cliente + último contacto de um worker capaz desses tipos (ou "nunca"). Se o worker voltar
--               e cair outra vez, o último contacto muda e há um aviso novo; enquanto estiver em baixo, não se repete.
--  job_dead:    chave = origem + trabalho. Quem já recebeu o erro de automação desse trabalho (worker_finish) não recebe outra vez.
create or replace function public.ops_health_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; o uuid; aid bigint; n_users int; down int := 0; dead int := 0; k text; et text; eid text; t text; b text; res jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('ops_health_tick'));

  for r in
    with q as (select x.* from public._health_jobs() x join clients c on c.id = x.workspace_id and c.status = 'active'
                where x.status = 'queued' and x.ready_at <= now()),
    u as (select q.* from q where not exists (select 1 from agent_workers w where q.kind = any (w.kinds) and w.last_seen > now() - interval '10 minutes')),
    g as (select u.source, u.workspace_id, count(*) n, min(u.ready_at) oldest, array_agg(distinct u.kind order by u.kind) kinds,
                 (array_agg(u.id order by u.created_at))[1] first_id, (array_agg(u.asset_id order by u.created_at))[1] first_asset
            from u group by u.source, u.workspace_id)
    select g.*, (select max(w.last_seen) from agent_workers w where w.kinds && g.kinds) seen, c.timezone from g join clients c on c.id = g.workspace_id
  loop
    k := 'saude:worker:' || r.source || ':' || r.workspace_id || ':' || coalesce(to_char(r.seen at time zone 'UTC', 'YYYYMMDD"T"HH24MISS'), 'nunca');
    aid := null;
    insert into ops_health_alerts (dedupe_key, kind, source, workspace_id, job_id, detail)
    values (k, 'worker_down', r.source, r.workspace_id, r.first_id,
            jsonb_build_object('waiting', r.n, 'oldest_ready_at', r.oldest, 'kinds', to_jsonb(r.kinds), 'worker_last_seen', r.seen))
    on conflict (dedupe_key) do nothing returning id into aid;
    continue when aid is null;
    down := down + 1;
    if r.source = 'agent' then et := 'agent_job'; eid := r.first_id::text;
    elsif r.first_asset is not null then et := 'media_asset'; eid := r.first_asset::text;
    else et := 'media_job'; eid := r.first_id::text; end if;
    t := 'Worker sem contacto: ' || case r.source when 'agent' then 'fila dos agentes' else 'fila de media' end || ' parada';
    b := r.n || case when r.n = 1 then ' trabalho à espera' else ' trabalhos à espera' end || ' desde '
         || to_char(r.oldest at time zone coalesce(r.timezone, 'UTC'), 'DD/MM HH24:MI') || ' (' || coalesce(r.timezone, 'UTC') || '). '
         || case when r.seen is null then 'Nenhum worker para ' || array_to_string(r.kinds, ', ') || ' contactou a base até hoje.'
                 else 'O último worker para ' || array_to_string(r.kinds, ', ') || ' contactou a base às '
                      || to_char(r.seen at time zone coalesce(r.timezone, 'UTC'), 'DD/MM HH24:MI') || '.' end;
    n_users := 0;
    for o in select m.user_id from agency_memberships m join clients c on c.organization_id = m.organization_id
              where c.id = r.workspace_id and m.agency_role = 'agency_owner' and m.status = 'active' loop
      perform public._notify(o, r.workspace_id, 'system_health', et, eid, t, b, k);
      n_users := n_users + 1;
    end loop;
    update ops_health_alerts set notified = n_users where id = aid;
  end loop;

  for r in
    select x.*, c.timezone from public._health_jobs() x join clients c on c.id = x.workspace_id and c.status = 'active'
     where x.status = 'dead' and coalesce(x.finished_at, x.created_at) > now() - interval '24 hours'
  loop
    k := 'saude:dead:' || r.source || ':' || r.id;
    aid := null;
    insert into ops_health_alerts (dedupe_key, kind, source, workspace_id, job_id, detail)
    values (k, 'job_dead', r.source, r.workspace_id, r.id,
            jsonb_build_object('kind', r.kind, 'attempts', r.attempts, 'finished_at', r.finished_at, 'run_id', r.run_id, 'error', public._ops_redact(r.last_error)))
    on conflict (dedupe_key) do nothing returning id into aid;
    continue when aid is null;
    dead := dead + 1;
    if r.source = 'agent' then et := 'agent_job'; eid := r.id::text;
    elsif r.asset_id is not null then et := 'media_asset'; eid := r.asset_id::text;
    else et := 'media_job'; eid := r.id::text; end if;
    t := 'Trabalho falhou de vez: ' || case r.source when 'agent' then 'agentes' else 'media' end || ' · ' || r.kind;
    b := 'Esgotou ' || r.attempts || ' de ' || r.max_attempts || ' tentativas.' || coalesce(' Último erro: ' || public._ops_redact(r.last_error), '');
    n_users := 0;
    for o in select m.user_id from agency_memberships m join clients c on c.organization_id = m.organization_id
              where c.id = r.workspace_id and m.agency_role = 'agency_owner' and m.status = 'active'
                and not exists (select 1 from notifications x where x.user_id = m.user_id and x.dedup_key = 'job_dead:' || r.id) loop
      perform public._notify(o, r.workspace_id, 'system_health', et, eid, t, b, k);
      n_users := n_users + 1;
    end loop;
    update ops_health_alerts set notified = n_users where id = aid;
  end loop;

  res := jsonb_build_object('worker_down', down, 'job_dead', dead);
  insert into ops_health_runs (key, last_run_at, last_result) values ('tick', now(), res)
  on conflict (key) do update set last_run_at = excluded.last_run_at, last_result = excluded.last_result;
  return res;
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public._ops_redact(text), public._health_require(), public._health_ws(uuid, uuid), public._health_jobs(),
  public._health_ws_counts(text, text), public.ops_health_tick() from public, anon, authenticated;
grant execute on function public.ops_health_tick() to service_role;
revoke all on function public.ops_health() from public, anon;
grant execute on function public.ops_health() to authenticated;

-- ───────────── agenda ─────────────
create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'ops-health-tick') then
    perform cron.schedule('ops-health-tick', '*/5 * * * *', 'select public.ops_health_tick()');
  end if;
end $$;

/* Rollback (compatível, por esta ordem):
   select cron.unschedule('ops-health-tick');
   drop function public.ops_health_tick(), public.ops_health(), public._health_ws_counts(text, text), public._health_jobs(),
     public._health_ws(uuid, uuid), public._health_require(), public._ops_redact(text);
   _ops_category: repor como em 20261103171148_w5_media_review_notif_body.sql (sem 'system_health');
   delete from notifications where kind = 'system_health'; delete from notification_user_prefs where kind = 'system_health';
   delete from notification_ws_prefs where kind = 'system_health'; delete from notification_event_defs where kind = 'system_health';
   notifications_kind_check: recriar sem 'system_health' (a partir de pg_get_constraintdef, como acima);
   drop index if exists public.media_jobs_failed_idx, public.agent_jobs_failed_idx;
   drop table public.ops_health_runs, public.ops_health_alerts;
   delete from permission_grants where capability = 'ops.health'; delete from role_capabilities where capability = 'ops.health';
   delete from capabilities where key = 'ops.health';
   Os alertas já enviados perdem-se com as tabelas; nenhum dado de negócio é alterado. */
