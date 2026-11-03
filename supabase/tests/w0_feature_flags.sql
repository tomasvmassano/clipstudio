-- supabase/tests/w0_feature_flags.sql : interruptores por cliente (MIG-09, CAP-09; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_staff uuid := gen_random_uuid(); u_cli uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ff_b', 'Flags B', 'ffb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'ff-own@test.invalid'),(u_staff,'ff-staff@test.invalid'),(u_cli,'ff-cli@test.invalid'),(u_b,'ff-b@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_staff, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_staff, 'agency_staff', 'manager'), ('numeiro', u_cli, 'client_staff', 'contributor'), ('ws_ff_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flag_defs (key, label, module, scope, default_stage) values
    ('teste.modulo', 'Módulo de teste', 'Teste', 'ws', 'owner'), ('teste.agencia', 'Painel de teste', 'Teste', 'org', 'owner');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('por defeito: dono vê', true, 'teste.modulo' = any(my_flags('numeiro')) and 'teste.agencia' = any(my_flags(null)));
  insert into t values ('flag do cliente não aparece na agência e vice-versa', true, not 'teste.modulo' = any(my_flags(null)) and not 'teste.agencia' = any(my_flags('numeiro')));
  perform set_config('request.jwt.claims', json_build_object('sub', u_staff, 'role','authenticated')::text, true);
  insert into t values ('por defeito: staff não vê', true, not 'teste.modulo' = any(my_flags('numeiro')));
  begin perform flag_set('teste.modulo', 'numeiro', 'all'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não liga flags (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := flag_set('teste.modulo', 'numeiro', 'agency');
  insert into t values ('dono passa o numeiro a agência', true,
    exists (select 1 from jsonb_array_elements(j->'flags') x where x->>'key' = 'teste.modulo' and x->'clients'->>'numeiro' = 'agency'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_staff, 'role','authenticated')::text, true);
  insert into t values ('staff vê no numeiro', true, 'teste.modulo' = any(my_flags('numeiro')));
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role','authenticated')::text, true);
  insert into t values ('equipa do cliente ainda não vê', true, not 'teste.modulo' = any(my_flags('numeiro')));
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform flag_set('teste.modulo', 'numeiro', 'all');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role','authenticated')::text, true);
  insert into t values ('ligado para todos: equipa do cliente vê', true, 'teste.modulo' = any(my_flags('numeiro')));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  insert into t values ('outro cliente fica com o defeito', true, not 'teste.modulo' = any(my_flags('ws_ff_b')));
  insert into t values ('B não vê flags do numeiro', true, my_flags('numeiro') = '{}');
  begin perform flags_admin(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê a gestão (42501)', true, st = '42501');
  -- exceção da agência vale para todos os clientes sem exceção própria
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform flag_set('teste.modulo', null, 'off');
  insert into t values ('desligar na agência: dono deixa de ver em B', true, not 'teste.modulo' = any(my_flags('ws_ff_b')));
  insert into t values ('exceção do cliente ganha à da agência', true, 'teste.modulo' = any(my_flags('numeiro')));
  perform flag_set('teste.modulo', 'numeiro', null);
  insert into t values ('apagar a exceção volta à da agência', true, not 'teste.modulo' = any(my_flags('numeiro')));
  begin perform flag_set('teste.agencia', 'numeiro', 'all'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag da agência não vai para um cliente (22023)', true, st = '22023');
  begin perform flag_set('teste.modulo', 'numeiro', 'sempre'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('fase inválida (22023)', true, st = '22023');

  -- código de equipa só vê o que está para todos
  perform flag_set('teste.modulo', 'numeiro', 'agency');
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  insert into t values ('código de equipa não vê fase agência', true, not 'teste.modulo' = any(my_flags('numeiro', tok)));
  execute 'reset role';
  update feature_flags set stage = 'all' where key = 'teste.modulo' and workspace_id = 'numeiro';
  execute 'set local role anon';
  insert into t values ('código de equipa vê fase todos', true, 'teste.modulo' = any(my_flags('numeiro', tok)));
  execute 'reset role';
  insert into t values ('mudanças ficam no histórico', true, (select count(*) from audit_events where action = 'flag.set' and entity_id = 'teste.modulo') >= 4);
  insert into t values ('tabelas fechadas', true, not has_table_privilege('authenticated', 'public.feature_flags', 'select'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
