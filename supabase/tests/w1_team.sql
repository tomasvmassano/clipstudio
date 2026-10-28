-- supabase/tests/w1_team.sql : RPCs da Equipa (workspace_team, invite_member, revoke_invitation).
-- Negativos só passam com o SQLSTATE esperado (42501/22023/28000); outro erro aborta a suite.
-- Corre tudo e termina com RAISE para fazer ROLLBACK (nada fica na base).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_owner uuid := gen_random_uuid(); u_mgrA uuid := gen_random_uuid(); u_cliA uuid := gen_random_uuid(); u_admB uuid := gen_random_uuid();
  inv_b uuid; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_owner,'t-owner@test.invalid',now(),'authenticated','authenticated'),(u_mgrA,'t-mgra@test.invalid',now(),'authenticated','authenticated'),
   (u_cliA,'t-clia@test.invalid',now(),'authenticated','authenticated'),(u_admB,'t-admb@test.invalid',now(),'authenticated','authenticated');
  insert into agency_memberships (organization_id, user_id, agency_role, status) values (org,u_owner,'agency_owner','active'),(org,u_mgrA,'agency_member','active');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, status) values
   ('numeiro',u_mgrA,'agency_staff','manager','active'),('numeiro',u_cliA,'client_staff','contributor','active'),
   ('ws_test_b',u_admB,'client_staff','workspace_admin','active');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';

  -- admin do cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_admB, 'role','authenticated')::text, true);
  begin perform workspace_team('ws_test_b'); insert into t values ('admin B lê equipa B', true, true);
  exception when others then insert into t values ('admin B lê equipa B', true, false); end;
  begin perform workspace_team('numeiro'); insert into t values ('admin B NÃO lê equipa A', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('admin B NÃO lê equipa A', false, false); end;
  begin perform invite_member('numeiro','x1@test.invalid','viewer','client_staff'); insert into t values ('admin B NÃO convida em A', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('admin B NÃO convida em A', false, false); end;
  begin perform invite_member('ws_test_b','x2@test.invalid','viewer','agency_staff'); insert into t values ('cliente NÃO convida staff da agência', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('cliente NÃO convida staff da agência', false, false); end;
  begin perform invite_member('ws_test_b','x3@test.invalid','workspace_owner','client_staff'); insert into t values ('admin NÃO convida acima do teto', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('admin NÃO convida acima do teto', false, false); end;
  begin perform invite_member('ws_test_b','x4@test.invalid','superuser','client_staff'); insert into t values ('papel inventado recusado', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('papel inventado recusado', false, false); end;
  begin inv_b := invite_member('ws_test_b','X5@Test.invalid','viewer','client_staff'); insert into t values ('admin B convida viewer em B', true, inv_b is not null);
  exception when others then insert into t values ('admin B convida viewer em B', true, false); end;
  execute 'reset role';  -- verificações internas (authenticated não lê invitations/audit_events diretamente)
  insert into t values ('authenticated sem SELECT direto em invitations', false, has_table_privilege('authenticated','public.invitations','select'));
  insert into t values ('email guardado em minúsculas', true, exists(select 1 from invitations where id = inv_b and email = 'x5@test.invalid'));
  insert into t values ('convite auditado', true, exists(select 1 from audit_events where entity_id = inv_b::text and action = 'invitation.create'));
  execute 'set local role authenticated';

  -- contributor do cliente A
  perform set_config('request.jwt.claims', json_build_object('sub', u_cliA, 'role','authenticated')::text, true);
  begin perform workspace_team('numeiro'); insert into t values ('contributor A lê equipa A', true, true);
  exception when others then insert into t values ('contributor A lê equipa A', true, false); end;
  begin perform invite_member('numeiro','x6@test.invalid','viewer','client_staff'); insert into t values ('contributor NÃO convida', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('contributor NÃO convida', false, false); end;
  begin perform revoke_invitation(inv_b); insert into t values ('A NÃO cancela convite de B', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('A NÃO cancela convite de B', false, false); end;
  begin perform workspace_team('ws_test_b'); insert into t values ('contributor A NÃO descobre B', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('contributor A NÃO descobre B', false, false); end;

  -- manager da agência em A (sem team.invite)
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgrA, 'role','authenticated')::text, true);
  begin perform invite_member('numeiro','x7@test.invalid','viewer','client_staff'); insert into t values ('manager agência NÃO convida', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('manager agência NÃO convida', false, false); end;
  insert into t values ('manager vê can_invite=false', false, (workspace_team('numeiro')->>'can_invite')::boolean);

  -- dono da agência
  perform set_config('request.jwt.claims', json_build_object('sub', u_owner, 'role','authenticated')::text, true);
  begin perform invite_member('ws_test_b','x8@test.invalid','manager','agency_staff'); insert into t values ('owner convida staff da agência', true, true);
  exception when others then insert into t values ('owner convida staff da agência', true, false); end;
  insert into t values ('owner vê can_invite_agency', true, (workspace_team('ws_test_b')->>'can_invite_agency')::boolean);

  -- admin B cancela o seu convite
  perform set_config('request.jwt.claims', json_build_object('sub', u_admB, 'role','authenticated')::text, true);
  begin perform revoke_invitation(inv_b); insert into t values ('admin B cancela convite de B', true, true);
  exception when others then insert into t values ('admin B cancela convite de B', true, false); end;
  insert into t values ('cancelado sai da lista', false, exists(select 1 from jsonb_array_elements(workspace_team('ws_test_b')->'invitations') e where e->>'id' = inv_b::text));

  -- anónimo
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  begin perform workspace_team('numeiro'); insert into t values ('anónimo NÃO lê equipa', false, true);
  exception when sqlstate '42501' or sqlstate '22023' or sqlstate '28000' then insert into t values ('anónimo NÃO lê equipa', false, false); end;

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
