-- supabase/tests/w1_agency_team.sql : Equipa da agência (W1-13; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_mem uuid := gen_random_uuid(); u_cli uuid := gen_random_uuid();
  j jsonb; st text; inv uuid; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_t_a', 'Equipa A', 'ta', org), ('ws_t_b', 'Equipa B', 'tb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'t-own@test.invalid'),(u_adm,'t-adm@test.invalid'),(u_mem,'t-mem@test.invalid'),(u_cli,'t-cli@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_adm, 'agency_admin'), (org, u_mem, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_t_a', u_adm, 'agency_staff', 'manager'), ('ws_t_a', u_mem, 'agency_staff', 'contributor'), ('ws_t_b', u_mem, 'agency_staff', 'contributor'),
    ('ws_t_b', u_cli, 'client_staff', 'workspace_admin');
  insert into tasks (workspace_id, title, assignee_id, created_kind) values ('ws_t_a', 'tarefa A', u_mem, 'system'), ('ws_t_b', 'tarefa B', u_mem, 'system');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := agency_team();
  insert into t values ('dono vê o staff com clientes e carga', true,
    exists (select 1 from jsonb_array_elements(j->'staff') s where s->>'email' = 't-mem@test.invalid' and jsonb_array_length(s->'clients') = 2 and (s->>'open_tasks')::int = 2));
  insert into t values ('dono pode convidar e gerir', true, (j #>> '{can,invite}')::boolean and (j #>> '{can,manage}')::boolean);
  insert into t values ('equipa do cliente não aparece como staff', true, not exists (select 1 from jsonb_array_elements(j->'staff') s where s->>'email' = 't-cli@test.invalid'));
  inv := agency_invite('Novo@Test.invalid', 'agency_member');
  insert into t values ('convite para a agência criado', true, exists (select 1 from jsonb_array_elements(agency_team()->'invites') i where i->>'email' = 'novo@test.invalid'));
  begin perform agency_invite('novo@test.invalid', 'agency_member'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('convite repetido (PT409)', true, st = 'PT409');
  begin perform agency_invite('t-mem@test.invalid', 'agency_admin'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem já é staff (PT409)', true, st = 'PT409');
  begin perform agency_invite('t-cli@test.invalid', 'agency_member'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa de um cliente não entra na agência (22023)', true, st = '22023');
  begin perform agency_invite('x@test.invalid', 'agency_owner'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se convida outro dono (22023)', true, st = '22023');
  perform agency_invite_revoke(inv);
  insert into t values ('convite cancelado sai da lista', true, not exists (select 1 from jsonb_array_elements(agency_team()->'invites') i where i->>'email' = 'novo@test.invalid'));
  j := agency_member_update(u_mem, '{"agency_role":"agency_manager"}');
  insert into t values ('dono muda o papel na agência', true, j->>'agency_role' = 'agency_manager');
  j := agency_member_update(u_mem, '{"status":"suspended"}');
  insert into t values ('suspender', true, j->>'status' = 'suspended');
  execute 'reset role';
  insert into t values ('suspenso perde logo o acesso aos clientes', true, not _authorize('scripts.read', 'ws_t_a', u_mem));
  execute 'set local role authenticated';
  perform agency_member_update(u_mem, '{"status":"active"}');
  execute 'reset role';
  insert into t values ('reativar devolve o acesso', true, _authorize('scripts.read', 'ws_t_a', u_mem));
  execute 'set local role authenticated';
  begin perform agency_member_update(u_own, '{"status":"suspended"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se muda a si próprio (42501)', true, st = '42501');
  begin perform agency_member_update(u_mem, '{"agency_role":"agency_owner"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não promove a dono (22023)', true, st = '22023');
  execute 'reset role';
  insert into t values ('mudanças no histórico da agência', true, (select count(*) from audit_events where organization_id = org and entity_id = u_mem::text and action = 'agency.member.updated') = 3);
  execute 'set local role authenticated';

  -- admin da agência: vê, não gere, e só vê os clientes a que tem acesso
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := agency_team();
  insert into t values ('admin vê a equipa mas não convida nem gere', true, not (j #>> '{can,invite}')::boolean and not (j #>> '{can,manage}')::boolean and j->'invites' = '[]'::jsonb);
  insert into t values ('admin não vê o cliente B nos clientes do colega', true,
    (select bool_and(not exists (select 1 from jsonb_array_elements(s->'clients') c where c->>'id' = 'ws_t_b')) from jsonb_array_elements(j->'staff') s)
    and not exists (select 1 from jsonb_array_elements(j->'clients') c where c->>'id' = 'ws_t_b'));
  insert into t values ('carga do colega conta só o que o admin pode ver', true,
    exists (select 1 from jsonb_array_elements(j->'staff') s where s->>'email' = 't-mem@test.invalid' and (s->>'open_tasks')::int = 1));
  begin perform agency_invite('y@test.invalid', 'agency_member'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin não convida (42501)', true, st = '42501');
  begin perform agency_member_update(u_mem, '{"status":"suspended"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin não suspende (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_mem, 'role','authenticated')::text, true);
  begin perform agency_team(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro da agência sem team.read não vê a equipa (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role','authenticated')::text, true);
  begin perform agency_team(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não vê a equipa da agência (42501)', true, st = '42501');
  execute 'reset role';
  execute 'set local role anon';
  begin perform agency_team(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo recusado', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
