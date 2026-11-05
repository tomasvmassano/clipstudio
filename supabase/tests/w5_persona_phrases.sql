-- supabase/tests/w5_persona_phrases.sql : lista de frases-persona versionada por cliente (W5-14, R-17; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  p1 jsonb := '[{"id":"p01","text":"o homem mais rico de Portugal"},{"id":"p02","text":"o filho do Jeff Bezos"}]';
  p2 jsonb := '[{"id":"p01","text":"o homem mais rico de Portugal"},{"id":"p03","text":"o marido mais caro do mundo","involves":{"name":"Parceira","consent_by":"Parceira","consent_at":"2026-11-05","consent_note":"por mensagem"}}]';
  j jsonb; c jsonb; st text; job uuid; det text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pp_b', 'Persona B', 'ppb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'pp-adm@test.invalid'),(u_mgr,'pp-mgr@test.invalid'),(u_view,'pp-view@test.invalid'),(u_b,'pp-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_adm,'client_staff','workspace_admin'),('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_view,'client_staff','viewer'),
   ('ws_pp_b',u_b,'client_staff','workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, service_role;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := persona_list_get('numeiro');
  insert into t values ('lista começa vazia (versão 0)', true, (j->>'version')::int = 0 and j->'phrases' = '[]'::jsonb and (j->'can'->>'manage')::boolean);
  j := persona_list_save('numeiro', p1, 0, 'primeira');
  insert into t values ('gravar cria a versão 1', true, (j->>'version')::int = 1 and jsonb_array_length(j->'phrases') = 2 and j->>'note' = 'primeira');
  j := persona_list_save('numeiro', p1, 1);
  insert into t values ('gravar sem mudanças não cria versão', true, (j->>'version')::int = 1);
  begin perform persona_list_save('numeiro', p2, 0); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versão desatualizada dá conflito (40001)', true, st = '40001');
  begin perform persona_list_save('numeiro', '[{"id":"p03","text":"o marido mais caro","involves":{"name":"Parceira"}}]', 1); st := 'ok';
  exception when others then st := sqlstate; get stacked diagnostics det = pg_exception_detail; end;
  insert into t values ('outra pessoa sem consentimento recusada (22023)', true, st = '22023' and det like '%consentimento%');
  begin perform persona_list_save('numeiro', '[{"id":"a","text":"xx"}]', 1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('frase demasiado curta (22023)', true, st = '22023');
  begin perform persona_list_save('numeiro', '[{"id":"a","text":"igual igual"},{"id":"b","text":"Igual igual"}]', 1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('frases repetidas (22023)', true, st = '22023');
  j := persona_list_save('numeiro', p2, 1, 'com a parceira');
  insert into t values ('versão 2 com consentimento registado', true, (j->>'version')::int = 2
    and j->'phrases'->1->'involves'->>'consent_by' = 'Parceira' and jsonb_array_length(j->'history') = 2);
  j := persona_list_version('numeiro', 1);
  insert into t values ('versão antiga continua legível', true, j->'phrases'->1->>'text' = 'o filho do Jeff Bezos');

  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := persona_list_get('numeiro');
  insert into t values ('manager lê mas não gere', true, (j->>'version')::int = 2 and not (j->'can'->>'manage')::boolean);
  begin perform persona_list_save('numeiro', p1, 2); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('manager não grava (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform persona_list_get('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('viewer com agents.read lê a lista', true, st = 'ok');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform persona_list_get('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não lê (42501)', true, st = '42501');
  begin perform persona_list_save('numeiro', p1, 2); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não grava (42501)', true, st = '42501');
  j := persona_list_get('ws_pp_b');
  insert into t values ('cada cliente tem a sua lista', true, (j->>'version')::int = 0);
  begin perform 1 from persona_lists; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tabela fechada à API (42501)', true, st = '42501');
  execute 'reset role';

  begin update persona_lists set note = 'x' where workspace_id = 'numeiro'; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versões imutáveis (42501)', true, st = '42501');
  begin delete from persona_lists where workspace_id = 'numeiro'; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se apagam (42501)', true, st = '42501');
  insert into t values ('gravação auditada com o que entrou e saiu', true, exists (select 1 from audit_events where workspace_id = 'numeiro'
    and action = 'persona.list_saved' and after->>'version' = '2' and after->'added' ? 'o marido mais caro do mundo' and after->'removed' ? 'o filho do Jeff Bezos'));
  insert into t values ('capacidade registada e ativa', true, exists (select 1 from capabilities where key = 'persona.manage' and status = 'ativo'));

  -- worker recebe a lista em vigor, sem o consentimento
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  job := (agent_job_enqueue('numeiro', 'daily_pipeline')->>'id')::uuid;
  execute 'reset role';
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  c := worker_claim('worker-pp');
  insert into t values ('claim leva a versão e as frases', true, (c->'job'->>'id')::uuid = job and (c->'persona'->>'version')::int = 2
    and jsonb_array_length(c->'persona'->'phrases') = 2 and c->'persona'->'phrases'->1->>'involves' = 'Parceira'
    and not (c->'persona'->'phrases'->1 ? 'consent_by'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
