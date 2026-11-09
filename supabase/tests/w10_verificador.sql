-- supabase/tests/w10_verificador.sql : resultado do verificador ao lado do guião (VAR-04, R-17; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  cfg jsonb := '{"language":"pt-PT","voice":"Voz","guardrails":["Regra"],"formats":{"a":{"share":1,"min":0.5,"max":1,"palavras":[50,100]}},"pipeline":{"scripts_per_day":5,"hooks_per_slot":3,"critic_threshold":7,"concurrency":2},"budget_eur_day":5}';
  script jsonb := '{"hooks":[{"hook":"Sou o homem mais rico do mundo."},{"hook":"O homem mais rico de Portugal não paga."}],"corpo":"Linha um.\nLinha dois.","formato":"a","tema":"T"}';
  ver jsonb := '{"versao":"2026-11-06.1","modelo":"claude-haiku-5-5","prompts_version":"p1","persona_version":3,"marca":"bloqueado",
    "hooks":[{"i":0,"texto":"Sou o homem mais rico do mundo.","marca":"bloqueado","afirmacoes":[{"tipo":"persona","trecho":"o homem mais rico","marca":"bloqueado","motivo":"fora da lista"}]},
             {"i":1,"texto":"O homem mais rico de Portugal não paga.","marca":"ok","afirmacoes":[{"tipo":"persona","trecho":"o homem mais rico de Portugal","marca":"ok"}]}]}';
  ja uuid; jb uuid; c jsonb; sa text; sb text; sa2 text; v jsonb; st text; tok text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_v_a', 'Verif A (teste)', 'va', org, 'Asia/Dubai'),
    ('ws_v_b', 'Verif B (teste)', 'vb', org, 'Europe/Lisbon');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_a,'v-a@test.invalid',now(),'authenticated','authenticated'),(u_b,'v-b@test.invalid',now(),'authenticated','authenticated'),
   (u_v,'v-v@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('ws_v_a',u_a,'client_staff','workspace_admin'),('ws_v_b',u_b,'client_staff','workspace_admin'),('ws_v_a',u_v,'client_staff','viewer');
  insert into agent_config_versions (workspace_id, version_no, status, config, validation, activated_at) values
    ('ws_v_a', 1, 'active', cfg, '{"ok":true,"errors":[],"warnings":[]}', now()), ('ws_v_b', 1, 'active', cfg, '{"ok":true,"errors":[],"warnings":[]}', now());
  ja := (_agent_enqueue('ws_v_a', 'daily_pipeline', 'verif-a', now(), '{"kind":"system","label":"t"}', '{}')).id;
  jb := (_agent_enqueue('ws_v_b', 'daily_pipeline', 'verif-b', now(), '{"kind":"system","label":"t"}', '{}')).id;
  perform agent_schedule_tick();   -- a agenda corre dentro do worker_claim: já aqui (idempotente por dia), para não depender da hora
  update agent_jobs set next_attempt_at = now() + interval '1 day' where status = 'queued' and id not in (ja, jb);
  update agent_jobs set scheduled_for = now() - interval '1 minute', next_attempt_at = now() - interval '1 minute' where id = ja;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, service_role, engine_worker;

  execute 'grant engine_worker to current_user';
  execute 'set local role engine_worker';
  c := worker_claim('w-verif-1');
  c := worker_claim('w-verif-1');   -- as duas execuções ficam com este worker
  sa := worker_save_script(ja, 'w-verif-1', 1, script)->>'id';
  sa2 := worker_save_script(ja, 'w-verif-1', 2, script)->>'id';
  sb := worker_save_script(jb, 'w-verif-1', 1, script)->>'id';
  v := worker_save_verification(ja, 'w-verif-1', sa, ver);
  insert into t values ('worker grava a verificação do guião', true, (v->>'created')::boolean);
  insert into t values ('repetir não duplica (idempotente)', true, not (worker_save_verification(ja, 'w-verif-1', sa, ver)->>'created')::boolean);
  begin perform worker_save_verification(ja, 'w-verif-1', sb, ver); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('guião de outro cliente/execução recusado (22023)', true, st = '22023');
  begin perform worker_save_verification(ja, 'outro-worker', sa2, ver); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem a lease não grava (PT409)', true, st = 'PT409');
  begin perform worker_save_verification(ja, 'w-verif-1', sa2, jsonb_set(ver, '{marca}', '"verificado"')); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('marca desconhecida recusada (22023)', true, st = '22023');
  begin perform worker_save_verification(ja, 'w-verif-1', sa2, jsonb_set(ver, '{hooks,0,afirmacoes,0,tipo}', '"boato"')); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tipo de afirmação desconhecido recusado (22023)', true, st = '22023');
  begin perform worker_save_verification(ja, 'w-verif-1', sa2, ver - 'versao'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem versão do verificador recusado (22023)', true, st = '22023');
  begin perform worker_save_verification(ja, 'w-verif-1', sa2, jsonb_set(ver, '{lixo}', to_jsonb(repeat('x', 70000)))); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('resultado demasiado grande recusado (22023)', true, st = '22023');
  perform worker_save_verification(jb, 'w-verif-1', sb, jsonb_set(ver, '{marca}', '"ok"'));
  execute 'reset role';

  insert into t values ('fica a versão do texto, do verificador e da lista', true, exists (select 1 from script_verifications s join guioes g on g.id = s.content_id
    where s.content_id = sa and s.version_id is not distinct from g.current_version_id and s.verifier_version = '2026-11-06.1'
      and s.persona_version = 3 and s.model = 'claude-haiku-5-5' and s.marca = 'bloqueado' and s.workspace_id = 'ws_v_a'));
  insert into t values ('evento script.verified', true, exists (select 1 from domain_events where type = 'script.verified' and entity_id = sa and payload->>'marca' = 'bloqueado'));
  insert into t values ('flag scripts.verifier registada e ligada para todos', true,
    exists (select 1 from feature_flag_defs where key = 'scripts.verifier' and default_stage = 'all'));
  insert into t values ('guião continua em revisão (nada chumbado sozinho)', true, (select editorial_status from guioes where id = sa) <> 'rejected');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);
  v := content_verifications('ws_v_a', array[sa, sa2, sb]);
  insert into t values ('cliente A lê a verificação por hook', true, v->sa->>'marca' = 'bloqueado' and v->sa->'result'->'hooks'->0->>'marca' = 'bloqueado');
  insert into t values ('guião sem verificação não aparece', true, not v ? sa2);
  insert into t values ('id de outro cliente no pedido não aparece', true, not v ? sb);
  begin perform content_verifications('ws_v_b', array[sb]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não lê o cliente B (42501)', true, st = '42501');
  begin perform 1 from script_verifications; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tabela fechada à API (42501)', true, st = '42501');
  begin perform worker_save_verification(ja, 'w-verif-1', sa2, ver); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('utilizador não chama a função do worker (42501)', true, st = '42501');
  begin perform content_verifications('ws_v_a', array_fill('x'::text, array[201])); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('mais de 200 ids recusado (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  insert into t values ('viewer com scripts.read lê', true, content_verifications('ws_v_a', array[sa]) ? sa);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_verifications('ws_v_a', array[sa]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê o cliente A (42501)', true, st = '42501');
  insert into t values ('B lê o seu', true, content_verifications('ws_v_b', array[sb])->sb->>'marca' = 'ok');
  begin perform content_verifications('ws_nao_existe', array[sa]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente inexistente igual a sem acesso (42501)', true, st = '42501');
  execute 'reset role';

  -- código de equipa (transição): lê o seu cliente pelo token, nada sem token
  insert into studio_tokens (token, client_id, role, label) values ('tok-verif-a', 'ws_v_a', 'creator', 'teste') on conflict do nothing;
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform content_verifications('ws_v_a', array[sa], 'tok-verif-a'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa do cliente lê', true, st = 'ok');
  begin perform content_verifications('ws_v_b', array[sb], 'tok-verif-a'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não lê B (42501)', true, st = '42501');
  begin perform content_verifications('ws_v_a', array[sa]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código (42501)', true, st = '42501');
  execute 'reset role';

  -- guião eliminado deixa de aparecer
  update guioes set editorial_status = 'archived' where id = sa;
  update guioes set deleted_at = now(), deleted_by = u_a, deleted_reason = 'teste' where id = sa;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);
  insert into t values ('guião eliminado não aparece', true, not content_verifications('ws_v_a', array[sa]) ? sa);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
