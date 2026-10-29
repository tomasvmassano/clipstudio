-- supabase/tests/w4_agents.sql : catálogo, configuração versionada e fila durável dos agentes (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  ok_cfg jsonb := '{"language":"pt-PT","voice":"Voz de teste","guardrails":["Regra"],"formats":{"a":{"share":0.6,"min":0.3,"max":0.8,"palavras":[50,100]},"b":{"share":0.4,"min":0.1,"max":0.6,"palavras":[60,120]}},"pipeline":{"scripts_per_day":5,"hooks_per_slot":3,"critic_threshold":7,"concurrency":2},"models":{"writer":"claude-opus-5-5"},"budget_eur_day":1,"schedule":{"enabled":true,"time":"00:00"}}';
  bad_cfg jsonb := '{"language":"pt-PT","voice":"Voz","guardrails":["Regra"],"formats":{"a":{"share":0.5,"min":0.3,"max":0.8,"palavras":[50,100]}},"pipeline":{"scripts_per_day":5,"hooks_per_slot":3,"critic_threshold":7,"concurrency":2},"models":{"writer":"gpt-9"}}';
  v1 uuid := (select id from agent_config_versions where workspace_id = 'numeiro' and status = 'active');
  j jsonb; v2 uuid; v3 uuid; job uuid; job2 uuid; c jsonb; st text; today text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_adm,'t-adm@test.invalid',now(),'authenticated','authenticated'),(u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),
   (u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_adm,'client_staff','workspace_admin'),('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_view,'client_staff','viewer'),
   ('ws_test_b',u_b,'client_staff','workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, service_role;
  execute 'set local role authenticated';

  -- viewer
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  j := agents_overview('numeiro');
  insert into t values ('catálogo com os 13 agentes e o modelo da configuração ativa', true,
    jsonb_array_length(j->'agents') = 13 and exists (select 1 from jsonb_array_elements(j->'agents') a where a->>'key' = 'editor' and a->>'model' = 'claude-haiku-5-5'));
  insert into t values ('viewer não vê versões nem custos', true, j->'versions' = 'null'::jsonb and j->'spend_today' = 'null'::jsonb and not (j->'can'->>'run')::boolean);
  begin perform agent_job_enqueue('numeiro', 'daily_pipeline'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não corre agentes (42501)', true, st = '42501');
  begin perform 1 from agent_jobs; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabela de execuções fechada à API (42501)', true, st = '42501');

  -- manager: corre, não configura
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := agent_job_enqueue('numeiro', 'daily_pipeline'); job := (j->>'id')::uuid;
  insert into t values ('correr enfileira com a versão ativa e chave do dia', true,
    j->>'status' = 'queued' and j->>'idempotency_key' = 'daily_pipeline:' || today and (j->>'config_version_id')::uuid = v1);
  insert into t values ('correr outra vez no mesmo dia devolve a mesma execução', true, (agent_job_enqueue('numeiro', 'daily_pipeline')->>'id')::uuid = job);
  begin perform agent_config_save('numeiro', ok_cfg); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não configura (42501)', true, st = '42501');
  insert into t values ('manager não vê custos', true, agents_overview('numeiro')->'jobs'->0->'cost_eur' = 'null'::jsonb);

  -- admin: versões
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := agent_config_save('numeiro', bad_cfg, 'má'); v2 := (j->>'id')::uuid;
  insert into t values ('versão inválida fica guardada com os erros', true, j->>'version_no' = '2' and not (j->'validation'->>'ok')::boolean
    and jsonb_array_length(j->'validation'->'errors') >= 2);
  begin perform agent_config_activate(v2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão inválida não se ativa (22023)', true, st = '22023');
  j := agent_config_save('numeiro', ok_cfg, 'boa'); v3 := (j->>'id')::uuid;
  j := agent_config_activate(v3);
  insert into t values ('ativar versão válida retira a anterior', true, j->>'status' = 'active'
    and (select status from agent_config_versions where id = v1) = 'retired' and (select count(*) from agent_config_versions where workspace_id = 'numeiro' and status = 'active') = 1);
  insert into t values ('admin vê versões e custos', true, jsonb_array_length(agents_overview('numeiro')->'versions') = 3 and agents_overview('numeiro')->'spend_today' is not null);
  perform agent_config_activate(v1);
  insert into t values ('voltar atrás = ativar a versão antiga', true, (select status from agent_config_versions where id = v1) = 'active' and (select status from agent_config_versions where id = v3) = 'retired');
  perform agent_config_activate(v3);
  execute 'reset role';
  begin update agent_config_versions set config = '{}' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões imutáveis (42501)', true, st = '42501');
  begin delete from agent_config_versions where id = v2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se apagam (42501)', true, st = '42501');

  -- worker
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  c := worker_claim('worker-a');
  insert into t values ('worker apanha a execução com a configuração fixada', true, (c->'job'->>'id')::uuid = job and c->'job'->>'status' = 'running'
    and (c->'job'->>'attempts')::int = 1 and c->'config'->>'voice' is not null and c->'workspace'->>'id' = 'numeiro');
  insert into t values ('worker regista-se', true, exists (select 1 from agent_workers where id = 'worker-a'));
  insert into t values ('heartbeat sem cancelamento', true, not (worker_heartbeat(job, 'worker-a', '{"step":"writer","done":3}')->>'cancel')::boolean);
  begin perform worker_heartbeat(job, 'worker-b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outro worker não mexe na execução (PT409)', true, st = 'PT409');
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  insert into t values ('progresso visível na app', true, agents_overview('numeiro')->'jobs'->0->'progress'->>'step' = 'writer');
  perform agent_job_cancel(job);
  execute 'reset role';
  execute 'set local role service_role';
  insert into t values ('cancelamento chega ao worker no heartbeat', true, (worker_heartbeat(job, 'worker-a')->>'cancel')::boolean);
  j := worker_finish(job, 'worker-a', false, null, 'cancelado pelo utilizador');
  insert into t values ('fecha como cancelada', true, j->>'status' = 'cancelled');

  -- tentativas e dead-letter
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  job2 := (agent_job_enqueue('numeiro', 'scouts', 'scouts:teste-1')->>'id')::uuid;
  execute 'reset role';
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  c := worker_claim('worker-a', array['scouts']);
  j := worker_finish(job2, 'worker-a', false, null, 'timeout da API', true);
  insert into t values ('falha repetível volta à fila com espera', true, j->>'status' = 'queued' and (j->>'next_attempt_at')::timestamptz > now());
  insert into t values ('não apanha antes da hora', true, worker_claim('worker-a', array['scouts']) is null);
  execute 'reset role';
  update agent_jobs set next_attempt_at = now() where id = job2;
  execute 'set local role service_role';
  c := worker_claim('worker-a', array['scouts']);
  -- lease expira: outro worker apanha e a tentativa fica perdida
  execute 'reset role';
  update agent_jobs set locked_until = now() - interval '1 second' where id = job2;
  execute 'set local role service_role';
  c := worker_claim('worker-b', array['scouts']);
  insert into t values ('lease expirada: outro worker retoma (tentativa 3)', true, (c->'job'->>'id')::uuid = job2 and (c->'job'->>'attempts')::int = 3);
  begin perform worker_finish(job2, 'worker-a', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker antigo já não fecha (PT409)', true, st = 'PT409');
  j := worker_finish(job2, 'worker-b', false, null, 'falhou outra vez', true, 0.10);
  insert into t values ('esgotadas as tentativas vai para dead-letter', true, j->>'status' = 'dead');
  execute 'reset role';
  insert into t values ('tentativas registadas (perdida e falhadas)', true,
    (select count(*) from agent_job_attempts where job_id = job2) = 3 and exists (select 1 from agent_job_attempts where job_id = job2 and status = 'lost'));
  insert into t values ('quem configura é avisado do erro', true, exists (select 1 from notifications where user_id = u_adm and kind = 'automation_error' and entity_id = job2::text));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := agent_job_retry(job2);
  insert into t values ('repetir execução morta volta à fila', true, j->>'status' = 'queued' and (j->>'max_attempts')::int = 4);

  -- orçamento
  execute 'reset role';
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  c := worker_claim('worker-b', array['scouts']);
  perform worker_finish(job2, 'worker-b', true, '{"guioes":5}', null, true, 2.5, 1000, 2000, 'run-xyz');
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform agent_job_enqueue('numeiro', 'analysis'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('limite de custo diário atingido não enfileira (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  insert into t values ('admin vê o custo do dia', true, (agents_overview('numeiro')->>'spend_today')::numeric >= 2.5);

  -- worker só para o service_role
  begin perform worker_claim('worker-x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('utilizador não chama funções do worker (42501)', true, st = '42501');

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform agents_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê os agentes de A (42501)', true, st = '42501');
  begin perform agent_job_cancel(job2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não cancela execuções de A (42501)', true, st = '42501');
  begin perform agent_config_activate(v1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não ativa versões de A (42501)', true, st = '42501');
  insert into t values ('B só vê as suas versões (RLS)', true, (select count(*) from agent_config_versions) = 0);
  begin perform agent_job_enqueue('ws_test_b', 'daily_pipeline'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem configuração ativa não corre (22023)', true, st = '22023');
  perform agent_config_activate((agent_config_save('ws_test_b', ok_cfg)->>'id')::uuid);
  execute 'reset role';
  execute 'set local role service_role';
  perform agent_schedule_tick();
  execute 'reset role';
  insert into t values ('agenda enfileira a corrida diária de B', true, exists (select 1 from agent_jobs where workspace_id = 'ws_test_b' and idempotency_key = 'daily_pipeline:' || today));
  execute 'set local role service_role';
  perform agent_schedule_tick();
  execute 'reset role';
  insert into t values ('agenda não duplica', true, (select count(*) from agent_jobs where workspace_id = 'ws_test_b') = 1);
  begin insert into agent_jobs (workspace_id, kind, idempotency_key, config_version_id, requested_kind) values ('ws_test_b', 'scouts', 'x-y-z', v1, 'system'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('execução de B com versão de A (23514)', true, st = '23514');

  -- código de equipa
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código vê o catálogo e as execuções', true, jsonb_array_length(agents_overview('numeiro', tok)->'agents') = 13);
  begin perform agent_job_enqueue('numeiro', 'scouts', null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não corre agentes (42501)', true, st = '42501');
  begin perform worker_claim('worker-x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não chama o worker (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
