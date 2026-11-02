-- supabase/tests/w1_access_simulate.sql : simulador "Ver como" (CAP-05, BIZ-07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_out uuid := gen_random_uuid();
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_sim_b', 'Sim B', 'simb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'sim-adm@test.invalid'),(u_view,'sim-view@test.invalid'),(u_b,'sim-b@test.invalid'),(u_out,'sim-out@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_sim_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason, created_by) values ('numeiro', u_view, 'scripts.read', 'deny', 'teste', u_adm);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);

  j := access_simulate('numeiro', u_view, null);
  insert into t values ('ver como pessoa: negação explícita aparece', true,
    exists (select 1 from jsonb_array_elements(j->'capabilities') x where x->>'key' = 'scripts.read' and not (x->>'allowed')::boolean and x->>'source' = 'deny'));
  insert into t values ('ver como pessoa: o papel não dá edição', true,
    exists (select 1 from jsonb_array_elements(j->'capabilities') x where x->>'key' = 'scripts.edit' and not (x->>'allowed')::boolean));
  insert into t values ('alvo descrito', true, j->'target'->>'role' = 'viewer' and j->'target'->>'kind' = 'user');
  j := access_simulate('numeiro', null, 'manager');
  insert into t values ('ver como papel', true,
    exists (select 1 from jsonb_array_elements(j->'capabilities') x where x->>'key' = 'scripts.approve' and (x->>'allowed')::boolean)
    and exists (select 1 from jsonb_array_elements(j->'capabilities') x where x->>'key' = 'scripts.delete' and not (x->>'allowed')::boolean));
  begin perform access_simulate('numeiro', u_b, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não sonda pessoas de outro cliente (22023)', true, st = '22023');
  begin perform access_simulate('numeiro', u_view, 'manager'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa e papel ao mesmo tempo (22023)', true, st = '22023');
  begin perform access_simulate('numeiro', null, 'deus'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('papel desconhecido (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform access_simulate('numeiro', u_adm, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem não gere permissões não simula (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform access_simulate('numeiro', null, 'viewer'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não simula no numeiro (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('simulações ficam no histórico', true, (select count(*) from audit_events where action = 'access.simulated' and workspace_id = 'numeiro') = 2);
  insert into t values ('simular não muda acessos', true, (select workspace_role from workspace_access where user_id = u_view) = 'viewer');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
