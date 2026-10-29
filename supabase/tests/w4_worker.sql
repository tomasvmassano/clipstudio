-- supabase/tests/w4_worker.sql : o motor liga-se à fila e grava guiões em revisão (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  cfg jsonb := '{"language":"pt-PT","voice":"Voz","guardrails":["Regra"],"formats":{"a":{"share":1,"min":0.5,"max":1,"palavras":[50,100]}},"pipeline":{"scripts_per_day":5,"hooks_per_slot":3,"critic_threshold":7,"concurrency":2},"budget_eur_day":5}';
  va uuid; vb uuid; ja uuid; jb uuid; c jsonb; s jsonb; s2 jsonb; st text; g record; d date;
  script jsonb := '{"hooks":[{"hook":"Hook um","mecanismo":"contra","nota_critico":8.5},{"hook":"Hook dois","mecanismo":"numero"},{"text":"Hook três"}],
                    "corpo":"Linha um.\nLinha dois.","formato":"a","tema":"Tema de teste","critic_score":8.1,"legenda":"Legenda","fonte":"https://exemplo.pt"}';
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_w_a', 'Worker A (teste)', 'wa', org, 'Asia/Dubai'),
    ('ws_w_b', 'Worker B (teste)', 'wb', org, 'Europe/Lisbon');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_a,'w-a@test.invalid',now(),'authenticated','authenticated'),(u_b,'w-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('ws_w_a',u_a,'client_staff','workspace_admin'),('ws_w_b',u_b,'client_staff','workspace_admin');
  insert into agent_config_versions (workspace_id, version_no, status, config, validation, activated_at)
    values ('ws_w_a', 1, 'active', cfg, '{"ok":true,"errors":[],"warnings":[]}', now()) returning id into va;
  insert into agent_config_versions (workspace_id, version_no, status, config, validation, activated_at)
    values ('ws_w_b', 1, 'active', jsonb_set(cfg, '{pipeline,target_day_offset}', '0'), '{"ok":true,"errors":[],"warnings":[]}', now()) returning id into vb;
  ja := (_agent_enqueue('ws_w_a', 'daily_pipeline', 'teste-a', now(), '{"kind":"system","label":"t"}', '{}')).id;
  jb := (_agent_enqueue('ws_w_b', 'daily_pipeline', 'teste-b', now(), '{"kind":"system","label":"t"}', '{}')).id;
  -- só estas duas execuções na fila durante o teste
  update agent_jobs set next_attempt_at = now() + interval '1 day' where status = 'queued' and id not in (ja, jb);
  update agent_models set eur_per_mtok_in = 1, eur_per_mtok_out = 2 where key = 'claude-haiku-5-5';
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, service_role, engine_worker;

  -- validação do dia alvo
  insert into t values ('validação recusa dia alvo 2', true,
    not (agent_config_validate(jsonb_set(cfg, '{pipeline,target_day_offset}', '2'))->>'ok')::boolean);
  insert into t values ('validação aceita dia alvo 0', true, (agent_config_validate(jsonb_set(cfg, '{pipeline,target_day_offset}', '0'))->>'ok')::boolean);

  -- o worker com o seu próprio utilizador
  execute 'grant engine_worker to current_user';
  execute 'set local role engine_worker';
  c := worker_claim('w-test-1');
  insert into t values ('engine_worker apanha execuções', true, (c->'job'->>'id')::uuid in (ja, jb));
  if (c->'job'->>'id')::uuid = jb then
    -- garante a ordem: A primeiro
    execute 'reset role'; update agent_jobs set status = 'queued', locked_by = null, attempts = 0 where id = jb;
    update agent_jobs set scheduled_for = now() - interval '1 minute', next_attempt_at = now() - interval '1 minute' where id = ja;
    execute 'set local role engine_worker'; c := worker_claim('w-test-1');
  end if;
  insert into t values ('claim traz dia alvo (amanhã por defeito), orçamento e preços', true,
    (c->>'target_date')::date = (now() at time zone 'Asia/Dubai')::date + 1 and (c->>'budget_remaining_eur')::numeric = 5
    and (c->'models'->'claude-haiku-5-5'->>'out')::numeric = 2);
  s := worker_save_script(ja, 'w-test-1', 3, script);
  insert into t values ('grava o guião no dia alvo com número', true, (s->>'created')::boolean and (s->>'date')::date = (c->>'target_date')::date
    and s->>'id' = 'ws_w_a-' || (s->>'date') || '-01');
  s2 := worker_save_script(ja, 'w-test-1', 3, script);
  insert into t values ('repetir o mesmo slot não duplica', true, s2->>'id' = s->>'id' and not (s2->>'created')::boolean);
  insert into t values ('outro slot leva o número seguinte', true, (worker_save_script(ja, 'w-test-1', 4, script)->>'n')::int = 2);
  begin perform worker_save_script(ja, 'w-test-1', 5, '{"hooks":[],"corpo":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem hooks é recusado (22023)', true, st = '22023');
  begin perform worker_save_script(ja, 'w-test-1', 5, '{"hooks":[{"hook":"h"}],"corpo":"  "}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('corpo vazio é recusado (22023)', true, st = '22023');
  begin perform worker_save_script(ja, 'outro-worker', 6, script); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem a lease não grava (PT409)', true, st = 'PT409');
  begin perform worker_save_script(jb, 'w-test-1', 1, script); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não grava numa execução que não apanhou (PT409)', true, st = 'PT409');
  -- o que o worker pode e não pode ler
  begin perform 1 from guioes limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker não lê guiões diretamente (42501)', true, st = '42501');
  begin perform 1 from workspace_access limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker não lê membros (42501)', true, st = '42501');
  begin perform 1 from agent_jobs limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker não lê a fila fora das funções (42501)', true, st = '42501');
  begin perform agent_config_save('ws_w_a', cfg); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker não muda configurações', true, st <> 'none');
  perform set_config('engine.client_id', 'ws_w_a', true);  -- o PgDB do worker fixa o cliente ao ligar (W4-03)
  begin insert into agent_log (run_id, agent, model, client_id, tokens_in, tokens_out) values ('run-t', 'writer', 'm', 'ws_w_a', 10, 20); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('worker escreve no log dos agentes com tokens', true, st = 'none');
  perform worker_heartbeat(ja, 'w-test-1', '{"etapa":"guioes","guioes":2}');
  perform worker_finish(ja, 'w-test-1', true, '{"guioes":2}', null, false, 0.42, 100, 200, 'run-t');
  execute 'reset role';

  select * into g from guioes where id = s->>'id';
  insert into t values ('guião do motor entra em revisão, não gravado', true, g.editorial_status = 'in_review' and g.production_status = 'not_started'
    and not g.validado and g.origem = 'motor' and g.client_id = 'ws_w_a');
  insert into t values ('hooks normalizados com mecanismo e nota', true, jsonb_array_length(g.hooks) = 3 and g.hooks->0->>'text' = 'Hook um'
    and g.hooks->0->>'mecanismo' = 'contra' and g.hooks->2->>'text' = 'Hook três');
  insert into t values ('versão 1 criada pelo motor', true, exists (select 1 from content_versions where content_id = g.id and version_no = 1 and created_kind = 'engine'));
  insert into t values ('transição e evento script.created', true,
    exists (select 1 from content_transitions where content_id = g.id and actor_kind = 'engine' and to_status = 'in_review')
    and exists (select 1 from domain_events where entity_id = g.id and type = 'script.created'));
  insert into t values ('execução concluída com custo e tokens', true,
    (select status = 'succeeded' and cost_eur = 0.42 and tokens_out = 200 from agent_jobs where id = ja));

  -- B: dia alvo 0 no fuso de Lisboa, e nada de A
  execute 'set local role engine_worker';
  c := worker_claim('w-test-1');
  insert into t values ('B: claim com dia alvo = hoje em Lisboa', true, (c->'job'->>'id')::uuid = jb and (c->>'target_date')::date = (now() at time zone 'Europe/Lisbon')::date);
  s := worker_save_script(jb, 'w-test-1', 1, script);
  perform worker_finish(jb, 'w-test-1', true, '{"guioes":1}', null, false, null, 10, 5, 'run-b');
  execute 'reset role';
  insert into t values ('custo desconhecido fica vazio, não 0', true, (select cost_eur is null and tokens_in = 10 from agent_jobs where id = jb));
  insert into t values ('B: guião fica em B com número 1', true, (select client_id from guioes where id = s->>'id') = 'ws_w_b' and (s->>'n')::int = 1);

  -- utilizadores da app não chamam o worker nem leem as saídas
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);
  begin perform worker_save_script(jb, 'w-test-1', 9, script); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('utilizador não grava como worker (42501)', true, st = '42501');
  begin perform 1 from agent_job_outputs; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('saídas das execuções fechadas à API (42501)', true, st = '42501');
  insert into t values ('A vê o seu guião do motor e não o de B', true,
    (select count(*) from guioes where client_id = 'ws_w_a') = 2 and (select count(*) from guioes where client_id = 'ws_w_b') = 0);
  execute 'reset role';
  execute 'set local role anon';
  begin perform worker_save_script(jb, 'w-test-1', 9, script); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não grava como worker (42501)', true, st = '42501');
  execute 'reset role';

  insert into t values ('agenda corre no Supabase a cada 5 min', true, exists (select 1 from cron.job where jobname = 'agent-schedule-tick' and active));
  insert into t values ('engine_worker sem login até ter password', true, not (select rolcanlogin from pg_roles where rolname = 'engine_worker'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
