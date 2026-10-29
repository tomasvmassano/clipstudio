-- supabase/tests/w1_audit.sql : histórico de ações por cliente (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  j jsonb; j2 jsonb; st text; i int; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_au_a', 'Auditoria A', 'aa', org), ('ws_au_b', 'Auditoria B', 'ab', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'au-adm@test.invalid'),(u_mgr,'au-mgr@test.invalid'),(u_b,'au-b@test.invalid'),(u_own,'au-own@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_au_a', u_adm, 'client_staff', 'workspace_admin'), ('ws_au_a', u_mgr, 'client_staff', 'manager'), ('ws_au_b', u_b, 'client_staff', 'workspace_admin');
  for i in 1..60 loop
    insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, entity_id, before, after)
    values (case when i % 2 = 0 then u_adm else u_mgr end, 'user', 'ws_au_a', case when i % 3 = 0 then 'script.approved' else 'task.updated' end,
            'content', 'g-' || i, jsonb_build_object('n', i - 1), jsonb_build_object('n', i));
  end loop;
  insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, entity_id) values (u_b, 'user', 'ws_au_b', 'script.approved', 'content', 'segredo-b');
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id) values ('system', null, 'ws_au_a', 'script.update', 'content', 'g-motor');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := audit_list('ws_au_a');
  insert into t values ('primeira página com 50, a mais recente primeiro, e cursor', true,
    jsonb_array_length(j->'rows') = 50 and j->'rows'->0->>'entity_id' = 'g-motor' and (j->>'next_before') is not null);
  insert into t values ('ações do sistema aparecem como Sistema', true, j->'rows'->0->>'actor' = 'Sistema');
  j2 := audit_list('ws_au_a', null, null, null, null, (j->>'next_before')::bigint);
  insert into t values ('segunda página traz o resto e acaba', true, jsonb_array_length(j2->'rows') = 11 and j2->'next_before' = 'null'::jsonb
    and (j2->'rows'->0->>'id')::bigint < (j->>'next_before')::bigint + 1);
  insert into t values ('filtro por ação', true, (select bool_and(x->>'action' = 'script.approved') from jsonb_array_elements(audit_list('ws_au_a', 'script.approved')->'rows') x)
    and jsonb_array_length(audit_list('ws_au_a', 'script.approved')->'rows') = 20);
  insert into t values ('filtro por prefixo de ação', true, jsonb_array_length(audit_list('ws_au_a', 'script', null, null, null, null, 200)->'rows') = 21);
  insert into t values ('filtro por pessoa', true, jsonb_array_length(audit_list('ws_au_a', null, u_mgr, null, null, null, 200)->'rows') = 30);
  insert into t values ('filtro por período', true, jsonb_array_length(audit_list('ws_au_a', null, null, now() + interval '1 hour')->'rows') = 0);
  insert into t values ('lista de pessoas e ações do cliente', true, jsonb_array_length(j->'actors') = 2 and j->'actions' ? 'task.updated' and not (j->'actions' @> '["x"]'));
  insert into t values ('nada de B no histórico de A', true, not exists (select 1 from jsonb_array_elements(audit_list('ws_au_a', null, null, null, null, null, 200)->'rows') x where x->>'entity_id' = 'segredo-b')
    and not exists (select 1 from jsonb_array_elements(j->'actors') a where (a->>'id')::uuid = u_b));
  begin perform audit_list('ws_au_a', 'x; drop'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('filtro de ação inválido recusado (22023)', true, st = '22023');
  insert into t values ('limite máximo de 200', true, jsonb_array_length(audit_list('ws_au_a', null, null, null, null, null, 10000)->'rows') = 61);
  begin perform audit_list('ws_au_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de A não lê o histórico de B (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform audit_list('ws_au_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não lê o histórico (42501)', true, st = '42501');
  begin perform 1 from audit_events limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabela de auditoria fechada à API (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência lê o histórico de qualquer cliente', true, jsonb_array_length(audit_list('ws_au_b')->'rows') = 1);
  execute 'reset role';
  execute 'set local role anon';
  begin perform audit_list('ws_au_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não lê (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
