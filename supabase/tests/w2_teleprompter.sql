-- supabase/tests/w2_teleprompter.sql : sessões, fila, takes e preferências do teleprompter (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := '2026-10-28'; g1 text := 'numeiro-2026-10-28-01'; g2 text := 'numeiro-2026-10-28-02'; g30 text := 'numeiro-2026-10-28-30';
  grej text := 'numeiro-2026-10-28-05'; grec text := 'numeiro-2026-10-28-06'; gb text := 'ws_test_b-2026-10-28-01';
  s jsonb; s2 jsonb; sid uuid; sidb uuid; j jsonb; t1 uuid; t2 uuid; ref1 uuid := gen_random_uuid(); n0 int; ev int;
  st text; msg text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_test_b', d, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),(u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),
   (u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_con,'client_staff','contributor'),('numeiro',u_mgr,'client_staff','manager'),
   ('numeiro',u_view,'client_staff','viewer'),('ws_test_b',u_b,'client_staff','workspace_admin');
  update guioes set editorial_status = 'rejected' where id = grej;
  update guioes set production_status = 'recorded' where id = grec;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  s := recording_session_open('numeiro', d); sid := (s->>'id')::uuid;
  insert into t values ('abrir sessão: fila com os elegíveis do dia (sem rejeitados)', true,
    jsonb_array_length(s->'items') = 29 and not exists (select 1 from jsonb_array_elements(s->'items') i where i->>'content_id' = grej));
  insert into t values ('fila pela ordem do dia (n)', true, s->'items'->0->>'content_id' = g1 and s->'items'->28->>'content_id' = g30);
  s2 := recording_session_open('numeiro', d);
  insert into t values ('segundo dispositivo entra na mesma sessão', true, (s2->>'id')::uuid = sid and jsonb_array_length(s2->'items') = 29);
  insert into t values ('sessão traz blocos do conteúdo', true, jsonb_array_length(s->'items'->0->'content'->'hooks') >= 3 and s->'items'->0->'content'->>'corpo' <> '');

  s := recording_queue_set(sid, jsonb_build_array(jsonb_build_object('content_id', g30), jsonb_build_object('content_id', g2, 'skipped', true),
                                                  jsonb_build_object('content_id', g1, 'skipped_blocks', jsonb_build_array('hook_3'))));
  insert into t values ('reordenar: os referidos primeiro, o resto mantém a ordem', true,
    s->'items'->0->>'content_id' = g30 and s->'items'->1->>'content_id' = g2 and s->'items'->2->>'content_id' = g1
    and s->'items'->3->>'content_id' = 'numeiro-2026-10-28-03' and (s->'items'->28->>'position')::int = 29);
  insert into t values ('saltar conteúdo e bloco persiste', true, (s->'items'->1->>'skipped')::boolean and s->'items'->2->'skipped_blocks' = '["hook_3"]');
  begin perform recording_queue_set(sid, '[{"content_id":"numeiro-2026-10-28-01","skipped_blocks":["intro"]}]'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('bloco inventado na fila (22023)', true, st = '22023');
  begin perform recording_queue_set(sid, jsonb_build_array(jsonb_build_object('content_id', gb))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião de B não entra na fila de A (22023)', true, st = '22023');

  -- takes
  j := take_create(sid, g1, 'body', ref1, 'primeiro'); t1 := (j->>'id')::uuid;
  j := take_create(sid, g1, 'body', gen_random_uuid()); t2 := (j->>'id')::uuid;
  insert into t values ('takes do mesmo bloco numeram 1, 2', true,
    (select take_number from takes where id = t1) = 1 and (select take_number from takes where id = t2) = 2);
  insert into t values ('take ligado à versão atual do guião', true,
    (select version_id from takes where id = t1) = (select current_version_id from guioes where id = g1));
  n0 := (select count(*) from takes);
  j := take_create(sid, g1, 'body', ref1);
  insert into t values ('repetir com o mesmo client_ref devolve o mesmo take (idempotente)', true, (j->>'id')::uuid = t1 and (select count(*) from takes) = n0);
  begin perform take_create(sid, g1, 'hook_1', ref1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('client_ref reutilizado noutro bloco (22023)', true, st = '22023');
  begin perform take_create(sid, g1, 'hook_9', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('hook que não existe (22023)', true, st = '22023');
  begin perform take_create(sid, g1, 'cta', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('CTA vazio não aceita take (22023)', true, st = '22023');
  j := take_create(sid, g1, 'hook_1', gen_random_uuid());
  insert into t values ('outro bloco começa no take 1', true, (j->>'take_number')::int = 1);
  insert into t values ('takes não mexem no estado editorial nem no de produção', true,
    (select editorial_status = 'approved' and production_status = 'not_started' from guioes where id = g1));

  perform take_update(t2, '{"selected":true}');
  perform take_update(t1, '{"selected":true,"notes":"melhor energia"}');
  insert into t values ('selecionar um take desmarca o outro do mesmo bloco', true,
    (select selected from takes where id = t1) and not (select selected from takes where id = t2)
    and (select notes from takes where id = t1) = 'melhor energia');
  perform take_update(t1, '{"status":"discarded"}');
  insert into t values ('descartar tira a seleção e guarda o take', true, (select status = 'discarded' and not selected from takes where id = t1));
  begin perform take_update(t1, '{"selected":true}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se seleciona um take descartado (22023)', true, st = '22023');
  begin perform take_update(t2, '{"take_number":9}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo não editável no take (22023)', true, st = '22023');

  execute 'reset role';
  ev := (select count(*) from domain_events where type = 'recording.viewed_80' and entity_id = g2);
  execute 'set local role authenticated';
  perform recording_progress(sid, g2, 'body', 0.85);
  perform recording_progress(sid, g2, 'body', 0.95);
  execute 'reset role';
  insert into t values ('ler 80% regista telemetria uma vez', true,
    (select count(*) from domain_events where type = 'recording.viewed_80' and entity_id = g2) = ev + 1);
  execute 'set local role authenticated';
  insert into t values ('ler 80% não marca gravado', true, (select production_status from guioes where id = g2) = 'not_started');
  insert into t values ('progresso fica para retomar', true, (select last_content_id = g2 and last_block = 'body' and abs(last_pct - 0.95) < 0.001 from recording_sessions where id = sid));
  begin perform recording_progress(sid, g2, 'body', 1.5); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('progresso fora de 0..1 (22023)', true, st = '22023');

  -- preferências
  j := tp_prefs_set('ipad-estudio-01', '{"speed":20,"font":40,"mirror_v":true,"line_height":1.6,"contrast":"alto","keys":{"play":[" ","Enter"]}}');
  insert into t values ('preferências guardadas e limitadas ao intervalo', true,
    (j->>'speed')::int = 10 and (j->>'font')::int = 40 and (j->>'mirror_v')::boolean and tp_prefs_get('ipad-estudio-01') = j);
  insert into t values ('outro dispositivo tem as suas', true, tp_prefs_get('portatil-0001') is null);
  begin perform tp_prefs_set('ipad-estudio-01', '{"cor":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('preferência desconhecida (22023)', true, st = '22023');
  begin perform tp_prefs_set('ipad-estudio-01', '{"keys":{"apagar_tudo":["x"]}}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('atalho para ação inexistente (22023)', true, st = '22023');

  -- contributor grava takes; viewer não usa o teleprompter
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := take_create(sid, g2, 'hook_2', gen_random_uuid());
  insert into t values ('contributor marca takes', true, (j->>'take_number')::int = 1);
  insert into t values ('contributor não vê as preferências do manager', true, tp_prefs_get('ipad-estudio-01') is null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform recording_session_open('numeiro', d); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer sem recording.use (42501)', true, st = '42501');
  insert into t values ('viewer não lê sessões nem takes (RLS)', true, (select count(*) from recording_sessions) = 0 and (select count(*) from takes) = 0);

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform recording_session_open('numeiro', d); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não abre sessão de A (42501)', true, st = '42501');
  begin perform take_create(sid, g1, 'body', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não grava take na sessão de A (42501)', true, st = '42501');
  begin perform take_update(t2, '{"notes":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não edita take de A (42501)', true, st = '42501');
  begin perform recording_queue_set(sid, '[]'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não reordena a fila de A (42501)', true, st = '42501');
  begin perform recording_progress(sid, g1, 'body', 0.1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não escreve progresso em A (42501)', true, st = '42501');
  s := recording_session_open('ws_test_b', d); sidb := (s->>'id')::uuid;
  insert into t values ('B abre a sua sessão, só com o seu guião', true, jsonb_array_length(s->'items') = 1 and s->'items'->0->>'content_id' = gb);
  insert into t values ('B só vê a sua sessão (RLS)', true, (select count(*) from recording_sessions) = 1 and (select count(*) from takes) = 0);
  begin perform take_create(sidb, g1, 'body', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião de A na sessão de B (22023)', true, st = '22023');
  execute 'reset role';

  -- código de equipa
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  s := recording_session_open('numeiro', d, tok);
  insert into t values ('código entra na sessão do dia', true, (s->>'id')::uuid = sid);
  j := take_create(sid, g2, 'body', gen_random_uuid(), null, tok);
  insert into t values ('código marca takes', true, j->>'created_kind' = 'legacy_code');
  begin perform recording_session_open('ws_test_b', d, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não abre B (42501)', true, st = '42501');
  begin perform tp_prefs_set('ipad-estudio-01', '{"speed":3}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não guarda preferências no servidor (42501)', true, st = '42501');
  begin perform take_create(sid, g1, 'body', gen_random_uuid(), null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão nem código (28000)', true, st = '28000');
  execute 'reset role';

  -- integridade
  begin delete from takes where id = t2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('takes não se apagam (42501)', true, st = '42501');
  begin update takes set version_id = null where id = t2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão do take é imutável (42501)', true, st = '42501');
  begin insert into recording_session_items (session_id, workspace_id, content_id, position) values (sid, 'numeiro', gb, 99); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('item de B em sessão de A (23514)', true, st = '23514');

  -- dia seguinte: não gravados passam, gravados não; fechar sessão
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  s := recording_session_open('numeiro', d + 1);
  insert into t values ('dia seguinte traz os não gravados como transitados', true,
    jsonb_array_length(s->'items') = 28 and (s->'items'->0->>'carried')::boolean
    and not exists (select 1 from jsonb_array_elements(s->'items') i where i->>'content_id' in (grec, grej)));
  insert into t values ('takes antigos acompanham o guião transitado', true,
    exists (select 1 from jsonb_array_elements(s->'items') i where i->>'content_id' = g1 and jsonb_array_length(i->'takes') = 3));
  perform recording_session_close(sid);
  begin perform take_create(sid, g1, 'body', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sessão fechada não aceita takes (22023)', true, st = '22023');
  insert into t values ('reabrir o dia cria sessão nova', true, (recording_session_open('numeiro', d)->>'id')::uuid <> sid);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
