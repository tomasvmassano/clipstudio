-- supabase/tests/w1_permissions.sql : consola de permissões, exceções e "porque tem acesso?" (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  u_stf uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_boss uuid := gen_random_uuid();
  lacks text := 'costs.read';   -- o admin tem tudo pelo papel; nega-se-lhe isto para testar o teto
  j jsonb; st text; g1 bigint; g2 bigint; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_p_a', 'Permissões A', 'pa', org), ('ws_p_b', 'Permissões B', 'pb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'p-adm@test.invalid'),(u_mgr,'p-mgr@test.invalid'),(u_con,'p-con@test.invalid'),(u_own,'p-own@test.invalid'),
    (u_stf,'p-stf@test.invalid'),(u_b,'p-b@test.invalid'),(u_boss,'p-boss@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_stf, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_p_a', u_adm, 'client_staff', 'workspace_admin'), ('ws_p_a', u_mgr, 'client_staff', 'manager'), ('ws_p_a', u_con, 'client_staff', 'contributor'),
    ('ws_p_a', u_stf, 'agency_staff', 'contributor'), ('ws_p_a', u_boss, 'client_staff', 'workspace_owner'), ('ws_p_b', u_b, 'client_staff', 'workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- admin de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := permissions_matrix('ws_p_a');
  insert into t values ('matriz traz capacidades com nome, papéis e pessoas', true,
    jsonb_array_length(j->'capabilities') > 30 and (select bool_and(c->>'label' is not null) from jsonb_array_elements(j->'capabilities') c)
    and jsonb_array_length(j->'roles'->'viewer') > 0 and jsonb_array_length(j->'members') = 5);
  insert into t values ('admin não edita o dono nem staff da agência na matriz', true,
    (select bool_and(not (m->>'can_edit')::boolean) from jsonb_array_elements(j->'members') m where m->>'email' in ('p-boss@test.invalid','p-stf@test.invalid','p-adm@test.invalid')));
  insert into t values ('contributor sem aprovar pelo papel', true, not exists (select 1 from jsonb_array_elements(j->'members') m, jsonb_array_elements_text(m->'effective') e
    where m->>'email' = 'p-con@test.invalid' and e = 'scripts.approve'));
  j := grant_set('ws_p_a', u_con, 'scripts.approve', 'allow', now() + interval '7 days', 'Cobre as férias do revisor');
  g1 := (j->>'id')::bigint;
  insert into t values ('exceção de permitir dá acesso, explicado como exceção', true, (j->'now'->>'allowed')::boolean and j->'now'->>'source' = 'grant');
  execute 'reset role';
  insert into t values ('_authorize vê a exceção', true, _authorize('scripts.approve', 'ws_p_a', u_con));
  insert into t values ('exceção auditada com motivo e prazo', true,
    exists (select 1 from audit_events where action = 'grant.set' and entity_id = u_con::text and after->>'reason' = 'Cobre as férias do revisor' and after->>'expires_at' is not null));
  execute 'set local role authenticated';
  j := grant_set('ws_p_a', u_con, 'scripts.approve', 'allow', null, 'Passa a ser revisor de reserva');
  g2 := (j->>'id')::bigint;
  execute 'reset role';
  insert into t values ('nova exceção substitui a anterior (uma ativa)', true,
    (select count(*) from permission_grants where workspace_id = 'ws_p_a' and user_id = u_con and capability = 'scripts.approve' and revoked_at is null) = 1
    and (select revoked_at is not null from permission_grants where id = g1));
  execute 'set local role authenticated';
  j := grant_set('ws_p_a', u_con, 'scripts.read', 'deny', null, 'Só trabalha nas fontes');
  insert into t values ('negar vence o papel', true, not (j->'now'->>'allowed')::boolean and j->'now'->>'source' = 'deny');
  execute 'reset role';
  insert into t values ('_authorize respeita a negação', true, not _authorize('scripts.read', 'ws_p_a', u_con) and _authorize('sources.read', 'ws_p_a', u_con));
  execute 'set local role authenticated';
  j := grant_revoke((j->>'id')::bigint, 'Engano');
  insert into t values ('retirar a negação devolve o acesso do papel', true, (j->'now'->>'allowed')::boolean and j->'now'->>'source' = 'role');
  execute 'reset role';
  insert into t values ('retirar fica auditado e a linha fica no histórico', true,
    exists (select 1 from audit_events where action = 'grant.revoked' and entity_id = u_con::text)
    and exists (select 1 from permission_grants where workspace_id = 'ws_p_a' and user_id = u_con and capability = 'scripts.read' and revoked_at is not null));
  execute 'set local role authenticated';

  -- limites
  execute 'reset role';
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('ws_p_a', u_adm, lacks, 'deny', 'teste do teto');
  execute 'set local role authenticated';
  begin perform grant_set('ws_p_a', u_con, lacks, 'allow', null, 'Dar o que não tenho'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se dá o que não se tem (42501)', true, st = '42501');
  begin perform grant_set('ws_p_a', u_con, lacks, 'deny', null, 'Negar o que não tenho'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('negar é sempre possível dentro do teto', true, st = 'none');
  begin perform grant_set('ws_p_a', u_adm, 'scripts.read', 'allow', null, 'A mim'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não mexe nas próprias permissões (42501)', true, st = '42501');
  begin perform grant_set('ws_p_a', u_boss, 'scripts.read', 'deny', null, 'Ao dono'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não mexe em quem está acima (42501)', true, st = '42501');
  begin perform grant_set('ws_p_a', u_stf, 'scripts.read', 'deny', null, 'Ao staff'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não mexe em staff da agência (42501)', true, st = '42501');
  begin perform grant_set('ws_p_a', u_con, 'scripts.read', 'deny', null, ''); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem motivo recusado (22023)', true, st = '22023');
  begin perform grant_set('ws_p_a', u_con, 'scripts.fly', 'deny', null, 'Inventada'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('capacidade desconhecida recusada (22023)', true, st = '22023');
  begin perform grant_set('ws_p_a', u_con, 'workspaces.create', 'allow', null, 'Âmbito de agência'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('capacidade de agência não se dá por cliente (22023)', true, st = '22023');
  begin perform grant_set('ws_p_a', u_con, 'scripts.read', 'deny', now() - interval '1 hour', 'Passado'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('prazo no passado recusado (22023)', true, st = '22023');
  begin perform grant_set('ws_p_a', u_con, 'scripts.read', 'deny', now() + interval '2 years', 'Longe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('prazo acima de um ano recusado (22023)', true, st = '22023');
  begin perform grant_set('ws_p_a', u_con, 'scripts.read', 'talvez', null, 'Efeito'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('efeito inválido recusado (22023)', true, st = '22023');

  -- outros papéis e outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform permissions_matrix('ws_p_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não abre a consola (42501)', true, st = '42501');
  begin perform grant_set('ws_p_a', u_con, 'scripts.read', 'deny', null, 'Tentativa'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não dá exceções (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform permissions_matrix('ws_p_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não vê permissões de A (42501)', true, st = '42501');
  begin perform grant_revoke(g2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não retira exceções de A (42501)', true, st = '42501');
  begin perform access_explain('ws_p_a', u_con, 'scripts.read'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não pergunta por pessoas de A (42501)', true, st = '42501');

  -- "porque tenho acesso?" para o próprio
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := access_explain('ws_p_a', u_con, 'scripts.approve');
  insert into t values ('pessoa vê porque tem acesso', true, (j->>'allowed')::boolean and j->'reasons'->>0 like 'Exceção dada à pessoa%');
  j := access_explain('ws_p_a', u_con, 'agents.configure');
  insert into t values ('pessoa vê porque não tem acesso', true, not (j->>'allowed')::boolean and j->'reasons'->>0 like 'O papel contributor não inclui%');
  begin perform access_explain('ws_p_a', u_mgr, 'scripts.read'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa não pergunta por outros (42501)', true, st = '42501');
  begin perform access_explain('ws_p_b', u_con, 'scripts.read'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa não pergunta sobre outro cliente (42501)', true, st = '42501');

  -- dono da agência
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := grant_set('ws_p_a', u_stf, 'tasks.manage', 'allow', null, 'Coordena a produção');
  insert into t values ('dono da agência dá exceções a staff da agência', true, (j->'now'->>'allowed')::boolean);
  j := access_explain('ws_p_a', u_own, 'scripts.read');
  insert into t values ('dono da agência vê a razão do acesso global', true, j->>'source' = 'agency_owner');
  execute 'reset role';
  update clients set status = 'archived' where id = 'ws_p_a';
  insert into t values ('cliente arquivado: explicação diz porquê', true, _access_explain('ws_p_a', u_con, 'scripts.read')->'reasons'->>0 like 'O cliente está arquivado%');
  execute 'set local role anon';
  begin perform permissions_matrix('ws_p_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não abre a consola (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
