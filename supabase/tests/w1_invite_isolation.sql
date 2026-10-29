-- supabase/tests/w1_invite_isolation.sql : convites da agência e do cliente só dão acesso a esse cliente (PRD R-03, R-04; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_cx uuid := gen_random_uuid(); u_cy uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid();
  d0 date := current_date - 6; d1 date := current_date;
  j jsonb; st text; n int; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_i_a', 'Convite A', 'ia', org), ('ws_i_b', 'Convite B', 'ib', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'i-own@test.invalid'),(u_cx,'i-cx@test.invalid'),(u_cy,'i-cy@test.invalid'),(u_ag,'i-ag@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- 1. a agência convida o dono do cliente A
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform invite_member('ws_i_a', 'i-cx@test.invalid', 'workspace_admin', 'client_staff');
  perform invite_member('ws_i_a', 'i-ag@test.invalid', 'manager', 'agency_staff');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cx, 'role','authenticated')::text, true);
  insert into t values ('cliente aceita o convite da agência', true, accept_invitations() = 1);
  j := my_context();
  insert into t values ('cliente só tem o cliente A', true, jsonb_array_length(j->'workspaces') = 1 and j->'workspaces'->0->>'id' = 'ws_i_a');
  insert into t values ('cliente não é da agência', true, j->'agency' is null or j->'agency' = 'null'::jsonb);
  begin perform agency_dashboard(d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não abre o painel da agência (42501)', true, st = '42501');
  begin perform workspaces_list(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não vê a lista de clientes (42501)', true, st = '42501');
  begin perform dashboard_get('ws_i_b', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente A não abre o Início de B (42501)', true, st = '42501');
  begin perform desempenho('ws_i_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente A não vê o Desempenho de B (42501)', true, st = '42501');
  begin perform hoje_resumo('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente A não vê métricas do Numeiro (42501)', true, st = '42501');
  insert into t values ('cliente A abre o seu Início', true, dashboard_get('ws_i_a', d0, d1) ? 'kpis');

  -- 2. o cliente convida alguém da sua equipa
  perform invite_member('ws_i_a', 'i-cy@test.invalid', 'viewer', 'client_staff');
  begin perform invite_member('ws_i_b', 'i-cy@test.invalid', 'viewer', 'client_staff'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente A não convida para B (42501)', true, st = '42501');
  begin perform invite_member('ws_i_a', 'x1@test.invalid', 'manager', 'agency_staff'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não convida staff da agência (42501)', true, st = '42501');
  begin perform invite_member('ws_i_a', 'x2@test.invalid', 'workspace_owner', 'client_staff'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não dá papel acima do seu (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cy, 'role','authenticated')::text, true);
  insert into t values ('membro da equipa do cliente aceita', true, accept_invitations() = 1);
  j := my_context();
  insert into t values ('membro só tem o cliente A', true, jsonb_array_length(j->'workspaces') = 1 and j->'workspaces'->0->>'id' = 'ws_i_a'
    and (j->'agency' is null or j->'agency' = 'null'::jsonb));
  j := dashboard_get('ws_i_a', d0, d1);
  insert into t values ('membro (leitor) vê o Início de A sem custos', true, not (j->'kpis' ? 'kpi.costs'));
  begin perform dashboard_get('ws_i_b', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro de A não abre B (42501)', true, st = '42501');
  begin perform agency_dashboard(d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro não abre o painel da agência (42501)', true, st = '42501');

  -- 3. a mesma pessoa convidada para outro cliente: o convite é cancelado (um cliente por pessoa da equipa do cliente)
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform invite_member('ws_i_b', 'i-cx@test.invalid', 'viewer', 'client_staff');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cx, 'role','authenticated')::text, true);
  insert into t values ('convite para um segundo cliente não é aceite', true, accept_invitations() = 0);
  insert into t values ('e continua só com o cliente A', true, jsonb_array_length(my_context()->'workspaces') = 1);
  execute 'reset role';
  insert into t values ('convite cancelado e registado no histórico', true,
    exists (select 1 from invitations where workspace_id = 'ws_i_b' and email = 'i-cx@test.invalid' and revoked_at is not null and accepted_at is null)
    and exists (select 1 from audit_events where workspace_id = 'ws_i_b' and action = 'invitation.blocked'));
  execute 'set local role authenticated';

  -- 4. staff da agência convidado para A: entra na agência, mas só vê A
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  insert into t values ('staff da agência aceita', true, accept_invitations() = 1);
  j := agency_dashboard(d0, d1);
  insert into t values ('staff da agência vê no painel só o cliente atribuído', true, (j->>'count')::int = 1 and j->'clients'->0->>'id' = 'ws_i_a');
  begin perform dashboard_get('ws_i_b', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência não abre B sem atribuição (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
