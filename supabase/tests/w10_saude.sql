-- supabase/tests/w10_saude.sql : saúde do sistema (FR-17-15). Painel só com dados persistidos (workers, filas, a correr,
-- falhas), isolamento por cliente e por capacidade (dono vê tudo, admin só os atribuídos, staff sem ops.health e equipa do
-- cliente: 42501), erros sem segredos, alertas idempotentes aos donos da agência. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_adm2 uuid := gen_random_uuid(); u_mb uuid := gen_random_uuid();
  u_ca uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  cfg uuid := (select id from agent_config_versions where workspace_id = 'numeiro' order by created_at desc limit 1);
  j_dead uuid := gen_random_uuid(); j_run uuid := gen_random_uuid(); m_dead uuid := gen_random_uuid(); m_q uuid := gen_random_uuid(); j_dead2 uuid;
  j jsonb; x jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int; n2 int;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_saude_b', 'Saude B', 'saudeb', org, 'Europe/Lisbon');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select v.x, v.e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'saude-own@test.invalid'),(u_adm,'saude-adm@test.invalid'),(u_adm2,'saude-adm2@test.invalid'),(u_mb,'saude-mb@test.invalid'),
    (u_ca,'saude-ca@test.invalid'),(u_cb,'saude-cb@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values
    (org, u_own, 'agency_owner'), (org, u_adm, 'agency_admin'), (org, u_adm2, 'agency_admin'), (org, u_mb, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_saude_b', u_adm, 'agency_staff', 'manager'), ('numeiro', u_mb, 'agency_staff', 'workspace_admin'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('ws_saude_b', u_cb, 'client_staff', 'workspace_admin');

  -- dados persistidos: um worker de agentes visto há 30 min (em baixo), nenhum de media; numeiro com um job de agentes
  -- dead (com segredos no erro) e um a correr com lease expirada; B com um job de media dead e outro à espera
  insert into agent_workers (id, kinds, last_seen, version) values ('worker-saude-1', array['daily_pipeline','scouts','analysis'], now() - interval '30 minutes', 'v1');
  insert into agent_jobs (id, workspace_id, kind, idempotency_key, status, config_version_id, attempts, max_attempts, last_error, finished_at, requested_kind, run_id)
  values (j_dead, 'numeiro', 'daily_pipeline', 'saude-dead-1', 'dead', cfg, 3, 3,
          'HTTP 401 Bearer sk-abcdefghijklmnop1234 token=s3cr3tvalue para ana@exemplo.pt', now() - interval '2 hours', 'system', 'run-saude-1'),
         (j_run, 'numeiro', 'scouts', 'saude-run-1', 'running', cfg, 1, 3, null, null, 'system', null);
  update agent_jobs set started_at = now() - interval '40 minutes', heartbeat_at = now() - interval '35 minutes',
         locked_until = now() - interval '25 minutes', locked_by = 'worker-saude-1' where id = j_run;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, next_attempt_at, scheduled_for)
  values ('numeiro', 'analysis', 'saude-q-1', 'queued', cfg, 'system', now() - interval '20 minutes', now() - interval '20 minutes'),
         ('numeiro', 'analysis', 'saude-q-futuro', 'queued', cfg, 'system', now() + interval '2 hours', now() + interval '2 hours');
  insert into media_jobs (id, workspace_id, kind, idempotency_key, status, attempts, max_attempts, last_error, finished_at, next_attempt_at)
  values (m_dead, 'ws_saude_b', 'export', 'saude-m-dead', 'dead', 5, 5, 'postgres://user:pa55@db.host/x falhou', now() - interval '3 days', now()),
         (m_q, 'ws_saude_b', 'ingest', 'saude-m-q', 'queued', 0, 5, null, null, now() - interval '15 minutes');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── dono da agência: tudo ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := ops_health();
  insert into t values ('dono vê os dois clientes', true,
    exists (select 1 from jsonb_array_elements(j->'workspaces') w where w->>'id' = 'numeiro')
    and exists (select 1 from jsonb_array_elements(j->'workspaces') w where w->>'id' = 'ws_saude_b'));
  insert into t values ('worker real, visto há 30 min, não recente', true,
    exists (select 1 from jsonb_array_elements(j->'workers') w where w->>'id' = 'worker-saude-1' and not (w->>'recent')::boolean and w->>'version' = 'v1'));
  x := (select q from jsonb_array_elements(j->'queues') q where q->>'source' = 'agent');
  insert into t values ('fila dos agentes: 2 à espera, 1 pronto, sem worker para analysis', true,
    (x->>'queued')::int >= 2 and (x->>'ready')::int >= 1 and x->'uncovered_kinds' ? 'analysis' and x->>'oldest_ready_at' is not null);
  insert into t values ('a correr com lease expirada aparece como parado', true,
    (x->>'stalled')::int >= 1 and exists (select 1 from jsonb_array_elements(j->'running') rr where rr->>'id' = j_run::text and (rr->>'lease_expired')::boolean));
  x := (select q from jsonb_array_elements(j->'queues') q where q->>'source' = 'media');
  insert into t values ('fila de media: ingest sem worker', true, (x->>'ready')::int >= 1 and x->'uncovered_kinds' ? 'ingest');
  insert into t values ('falhas: dead de agentes nas 24 h, dead de media nos 7 dias', true,
    (j->'failure_counts'->'agent'->>'dead_24h')::int >= 1 and (j->'failure_counts'->'media'->>'dead_24h')::int = 0
    and (j->'failure_counts'->'media'->>'dead_7d')::int >= 1);
  x := (select f from jsonb_array_elements(j->'failures') f where f->>'id' = j_dead::text);
  insert into t values ('erro sem segredos nem email, com run_id', true,
    x->>'last_error' not like '%sk-abcdef%' and x->>'last_error' not like '%s3cr3t%' and x->>'last_error' not like '%ana@exemplo%'
    and x->>'last_error' like '%[removido]%' and x->>'run_id' = 'run-saude-1');
  x := (select f from jsonb_array_elements(j->'failures') f where f->>'id' = m_dead::text);
  insert into t values ('erro de media sem palavra-passe do URL', true, x->>'last_error' not like '%pa55%' and x->>'workspace_id' = 'ws_saude_b');
  insert into t values ('tick agendado e ainda sem corrida', true, (j->'tick'->>'scheduled')::boolean and j->'tick'->>'last_run_at' is null);

  -- ── admin da agência: só os clientes atribuídos ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := ops_health();
  insert into t values ('admin atribuído a B vê só B', true,
    jsonb_array_length(j->'workspaces') = 1 and j->'workspaces'->0->>'id' = 'ws_saude_b' and j::text not like '%"numeiro"%'
    and not exists (select 1 from jsonb_array_elements(j->'failures') f where f->>'id' = j_dead::text));
  insert into t values ('admin não conta jobs de outros clientes', true,
    (select (q->>'queued')::int from jsonb_array_elements(j->'queues') q where q->>'source' = 'agent') = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm2, 'role','authenticated')::text, true);
  j := ops_health();
  insert into t values ('admin sem atribuições: vazio (vê workers, não clientes)', true,
    jsonb_array_length(j->'workspaces') = 0 and jsonb_array_length(j->'failures') = 0 and jsonb_array_length(j->'workers') >= 1);

  -- ── sem capacidade ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_mb, 'role','authenticated')::text, true);
  begin perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem ops.health (mesmo admin de um cliente): 42501', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A: 42501', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente B: 42501', true, st = '42501');
  perform set_config('request.jwt.claims', '{}', true);
  begin perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão: 28000', true, st = '28000');
  begin perform ops_health_tick(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('browser não corre o tick (42501)', true, st = '42501');
  execute 'reset role';
  begin execute 'set local role anon'; perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('anónimo não lê (42501)', true, st = '42501');

  -- ── alertas ──
  j := ops_health_tick();
  insert into t values ('tick: workers em baixo nos dois clientes e um dead nas 24 h', true,
    (j->>'worker_down')::int = 2 and (j->>'job_dead')::int = 1);
  insert into t values ('dono recebe aviso de worker (agentes, numeiro)', true,
    exists (select 1 from notifications where user_id = u_own and kind = 'system_health' and workspace_id = 'numeiro' and entity_type = 'agent_job'
            and dedup_key like 'saude:worker:agent:numeiro:%'));
  insert into t values ('dono recebe aviso de worker de media em B', true,
    exists (select 1 from notifications where user_id = u_own and kind = 'system_health' and workspace_id = 'ws_saude_b' and dedup_key like 'saude:worker:media:ws_saude_b:nunca'));
  insert into t values ('dono recebe o dead, sem segredos no texto', true,
    exists (select 1 from notifications where user_id = u_own and dedup_key = 'saude:dead:agent:' || j_dead and body not like '%s3cr3t%' and body not like '%ana@%'));
  insert into t values ('dead de media com 3 dias não avisa', true, not exists (select 1 from notifications where dedup_key = 'saude:dead:media:' || m_dead));
  insert into t values ('só os donos recebem (admin, staff e cliente não)', true,
    not exists (select 1 from notifications where kind = 'system_health' and user_id in (u_adm, u_adm2, u_mb, u_ca, u_cb)));
  select count(*) into n from notifications where kind = 'system_health';
  select count(*) into n2 from ops_health_alerts;
  j := ops_health_tick();
  insert into t values ('segundo tick: nada de novo (idempotente)', true,
    (j->>'worker_down')::int = 0 and (j->>'job_dead')::int = 0 and (select count(*) from notifications where kind = 'system_health') = n
    and (select count(*) from ops_health_alerts) = n2);
  insert into t values ('corrida registada', true, (select last_result from ops_health_runs where key = 'tick') = j);
  -- o worker volta e cai outra vez: incidente novo
  update agent_workers set last_seen = now() - interval '12 minutes' where id = 'worker-saude-1';
  j := ops_health_tick();
  insert into t values ('worker voltou e caiu: aviso novo só dos agentes', true, (j->>'worker_down')::int = 1);
  -- worker vivo: sem avisos
  update agent_workers set last_seen = now() where id = 'worker-saude-1';
  j := ops_health_tick();
  insert into t values ('worker visto agora: sem aviso de agentes', true, (j->>'worker_down')::int = 0);
  -- quem já recebeu o erro de automação desse trabalho não é avisado duas vezes
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, attempts, max_attempts, finished_at, requested_kind)
  values ('numeiro', 'scouts', 'saude-dead-2', 'dead', cfg, 3, 3, now(), 'system') returning id into j_dead2;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, dedup_key)
  values (u_own, 'numeiro', 'automation_error', 'agent_job', j_dead2::text, 'x', 'job_dead:' || (j_dead2::text));
  j := ops_health_tick();
  insert into t values ('dead já avisado por worker_finish: alerta registado, sem notificação repetida', true,
    (j->>'job_dead')::int = 1 and not exists (select 1 from notifications where dedup_key = 'saude:dead:agent:' || (j_dead2::text))
    and (select notified from ops_health_alerts where dedupe_key = 'saude:dead:agent:' || (j_dead2::text)) = 0);

  -- o painel mostra os alertas enviados, filtrados por cliente
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := ops_health();
  insert into t values ('admin vê os alertas de B e não os de numeiro', true,
    exists (select 1 from jsonb_array_elements(j->'alerts') a where a->>'workspace_id' = 'ws_saude_b')
    and not exists (select 1 from jsonb_array_elements(j->'alerts') a where a->>'workspace_id' = 'numeiro')
    and j->'tick'->>'last_run_at' is not null);
  -- negação explícita de media.read em B tira a parte de media
  execute 'reset role';
  insert into permission_grants (workspace_id, user_id, capability, effect) values ('ws_saude_b', u_adm, 'media.read', 'deny');
  execute 'set local role authenticated';
  j := ops_health();
  insert into t values ('negação de media.read: sem media de B', true,
    j->'workspaces'->0->'media' = 'null'::jsonb and not exists (select 1 from jsonb_array_elements(j->'alerts') a where a->>'source' = 'media')
    and not exists (select 1 from jsonb_array_elements(j->'failures') f where f->>'source' = 'media'));
  -- admin perde a atribuição: deixa de ver B
  execute 'reset role';
  update workspace_access set status = 'suspended' where workspace_id = 'ws_saude_b' and user_id = u_adm;
  execute 'set local role authenticated';
  j := ops_health();
  insert into t values ('atribuição suspensa: B desaparece', true, jsonb_array_length(j->'workspaces') = 0);
  execute 'reset role';
  update agency_memberships set status = 'suspended' where user_id = u_adm;
  execute 'set local role authenticated';
  begin perform ops_health(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin suspenso na agência: 42501', true, st = '42501');
  execute 'reset role';

  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.ops_health_alerts', 'select') and not has_table_privilege('authenticated', 'public.ops_health_runs', 'select'));
  insert into t values ('funções auxiliares fechadas', true,
    not has_function_privilege('authenticated', 'public._health_jobs()', 'execute') and not has_function_privilege('authenticated', 'public._ops_redact(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.ops_health_tick()', 'execute'));
  insert into t values ('capacidade registada: dono e admin, não gestor nem membro', true,
    exists (select 1 from capabilities where key = 'ops.health' and status = 'ativo' and scopes = array['org'])
    and (select array_agg(role order by role) from role_capabilities where capability = 'ops.health') = array['agency_admin', 'agency_owner']);
  insert into t values ('agendado de 5 em 5 minutos', true, exists (select 1 from cron.job where jobname = 'ops-health-tick' and schedule = '*/5 * * * *'));
  insert into t values ('system_health obrigatório e na caixa como alerta', true,
    exists (select 1 from notification_event_defs where kind = 'system_health' and mandatory) and public._ops_category('system_health') = 'alert');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
