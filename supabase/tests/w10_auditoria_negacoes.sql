-- supabase/tests/w10_auditoria_negacoes.sql : tentativas recusadas em audit_events (W10-16, R-05; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  u_stf uuid := gen_random_uuid(); u_aadm uuid := gen_random_uuid();
  j jsonb; st text; i int; n int; ok int := 0; bad int := 0; res text := ''; r record; e audit_events;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ng_a', 'Negações A', 'na', org), ('ws_ng_b', 'Negações B', 'nb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, m, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'ng-adm@test.invalid'),(u_mgr,'ng-mgr@test.invalid'),(u_b,'ng-b@test.invalid'),(u_own,'ng-own@test.invalid'),
    (u_stf,'ng-stf@test.invalid'),(u_aadm,'ng-aadm@test.invalid')) v(x, m);
  insert into agency_memberships (organization_id, user_id, agency_role) values
    (org, u_own, 'agency_owner'), (org, u_stf, 'agency_member'), (org, u_aadm, 'agency_admin');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_ng_a', u_adm, 'client_staff', 'workspace_admin'), ('ws_ng_a', u_mgr, 'client_staff', 'manager'),
    ('ws_ng_b', u_b, 'client_staff', 'workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- 1. manager de A regista a recusa que recebeu em A
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.9, 10.0.0.1","user-agent":"Teste/1.0"}', true);
  j := audit_denied_record('ws_ng_a', 'rpc:audit_list', 'g-1', '42501', 'audit.read', 'browser', '11111111-2222-3333-4444-555555555555');
  insert into t values ('regista a própria recusa', true, (j->>'recorded')::boolean and j->>'correlation_id' = '11111111-2222-3333-4444-555555555555');
  execute 'reset role';
  select * into e from audit_events where action = 'access.denied' and correlation_id = '11111111-2222-3333-4444-555555555555';
  insert into t values ('ator vem da sessão, linha no cliente A, resultado denied', true,
    e.actor_user_id = u_mgr and e.actor_kind = 'user' and e.workspace_id = 'ws_ng_a' and e.result = 'denied' and e.organization_id = org);
  insert into t values ('guarda tentativa, capacidade confirmada, afiliação e via', true,
    e.after->>'attempted' = 'rpc:audit_list' and e.after->>'capability' = 'audit.read' and (e.after->>'verified')::boolean
    and e.after->>'affiliation' = 'client_staff' and e.after->>'via' = 'browser' and e.after->>'scope' = 'cliente' and e.entity_id = 'g-1');
  insert into t values ('IP e browser só como pseudónimo (nunca em claro)', true,
    length(e.after->>'ip_hash') = 16 and length(e.after->>'ua_hash') = 16 and position('203.0.113' in e.after::text) = 0 and position('Teste' in e.after::text) = 0);
  execute 'set local role authenticated';

  -- 2. não há forma de registar em nome de outra pessoa: a assinatura não tem ator e o ator é sempre auth.uid()
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform audit_denied_record('ws_ng_a', 'rpc:task_update', null, '42501', 'nao.existe', 'api', 'lixo');
  execute 'reset role';
  select * into e from audit_events where action = 'access.denied' and actor_user_id = u_adm order by id desc limit 1;
  insert into t values ('capacidade desconhecida descartada, correlação inválida substituída, via api', true,
    e.after->>'capability' is null and e.correlation_id ~ '^[0-9a-f-]{36}$' and e.after->>'via' = 'api' and e.after->>'attempted' = 'rpc:task_update');
  insert into t values ('capacidade desconhecida: sem verificação', true,
    (select (after->>'verified') is null from audit_events where id = e.id));
  execute 'set local role authenticated';
  perform audit_denied_record('ws_ng_a', 'rpc:audit_list', null, '42501', 'audit.read');
  execute 'reset role';
  insert into t values ('declaração de recusa de algo que a pessoa pode: verified=false', true,
    (select (after->>'verified')::boolean = false from audit_events where action = 'access.denied' and actor_user_id = u_adm order by id desc limit 1));
  execute 'set local role authenticated';

  -- 3. validação de entrada
  begin perform audit_denied_record('ws_ng_a', 'X; drop table', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ação inválida recusada (22023)', true, st = '22023');
  begin perform audit_denied_record('ws_ng_a', 'rpc:x', null, '23505'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código diferente de 42501 recusado (22023)', true, st = '22023');
  perform audit_denied_record('ws_ng_a', 'rpc:x', 'abc<script>?token=ey', '42501');
  execute 'reset role';
  insert into t values ('id do recurso limpo', true,
    (select entity_id = 'abcscripttokeney' from audit_events where action = 'access.denied' and actor_user_id = u_adm order by id desc limit 1));
  execute 'set local role authenticated';

  -- 4. cruzado: pessoa de B tenta A e um cliente inexistente; resposta igual, nada no histórico de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := audit_denied_record('ws_ng_a', 'rpc:guiao_update', 'ws_ng_a-1', '42501', 'scripts.edit');
  insert into t values ('tentativa a outro cliente: resposta igual (recorded)', true, (j->>'recorded')::boolean and j ?& array['recorded','correlation_id'] and (select count(*) from jsonb_object_keys(j)) = 2);
  j := audit_denied_record('nao_existe_x', 'rpc:guiao_update', null, '42501');
  insert into t values ('cliente inexistente: mesma forma de resposta', true, (j->>'recorded')::boolean and (select count(*) from jsonb_object_keys(j)) = 2);
  execute 'reset role';
  insert into t values ('tentativa de B a A fica fora de qualquer cliente (target_ws), sem verified', true,
    exists (select 1 from audit_events where action = 'access.denied' and actor_user_id = u_b and workspace_id is null and organization_id = org
            and after->>'target_ws' = 'ws_ng_a' and after->>'scope' = 'fora' and after->>'affiliation' = 'none' and after->>'verified' is null));
  insert into t values ('nenhuma linha de B no histórico de A', true,
    not exists (select 1 from audit_events where actor_user_id = u_b and workspace_id = 'ws_ng_a'));
  execute 'set local role authenticated';

  -- staff da agência sem atribuição
  perform set_config('request.jwt.claims', json_build_object('sub', u_stf, 'role','authenticated')::text, true);
  perform audit_denied_record('ws_ng_a', 'rpc:tasks_list', null);
  execute 'reset role';
  insert into t values ('staff sem atribuição fica fora, com afiliação marcada', true,
    exists (select 1 from audit_events where action = 'access.denied' and actor_user_id = u_stf and workspace_id is null and after->>'affiliation' = 'agency_staff_sem_atribuicao'));
  execute 'set local role authenticated';

  -- 5. limite: 30 por pessoa por minuto
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  for i in 1..40 loop j := audit_denied_record('ws_ng_a', 'rpc:spam', null); end loop;
  insert into t values ('acima do limite não grava e diz porquê', true, not (j->>'recorded')::boolean and j->>'reason' = 'limite');
  execute 'reset role';
  select count(*) into n from audit_events where action = 'access.denied' and actor_user_id = u_mgr;
  insert into t values ('no máximo 30 por minuto', true, n = 30);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  insert into t values ('limite é por pessoa (outra pessoa continua a gravar)', true, (audit_denied_record('ws_ng_a', 'rpc:outra', null)->>'recorded')::boolean);

  -- 6. lista: admin de A vê as recusas de A (quem, o quê, quando), não as de fora
  j := audit_denials_list('ws_ng_a', null, 200);
  insert into t values ('admin de A lista recusas de A com quem/o quê/quando', true,
    jsonb_array_length(j->'rows') = 34 and j->'rows'->0 ?& array['actor','attempted','at','capability','affiliation']
    and exists (select 1 from jsonb_array_elements(j->'rows') x where x->>'actor' = 'ng-mgr@test.invalid' and x->>'attempted' = 'rpc:audit_list'));
  insert into t values ('admin do cliente não vê tentativas de fora (nem quem é de B)', true,
    not (j->>'includes_outside')::boolean
    and not exists (select 1 from jsonb_array_elements(j->'rows') x where x->>'actor' in ('ng-b@test.invalid', 'ng-stf@test.invalid') or x->>'scope' = 'fora'));
  insert into t values ('lista não traz IP nem browser', true, not exists (select 1 from jsonb_array_elements(j->'rows') x where x ? 'ip_hash' or x ? 'ua_hash'));
  insert into t values ('paginação com cursor', true,
    jsonb_array_length(audit_denials_list('ws_ng_a', null, 10)->'rows') = 10 and (audit_denials_list('ws_ng_a', null, 10)->>'next_before') is not null);
  begin perform audit_denials_list('ws_ng_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de A não lista recusas de B (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform audit_denials_list('ws_ng_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não lista (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform audit_denials_list('ws_ng_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lista recusas de A (42501)', true, st = '42501');
  insert into t values ('admin de B não vê a própria tentativa a A na lista de B', true,
    jsonb_array_length(audit_denials_list('ws_ng_b')->'rows') = 0);

  -- 7. agência: dona vê também as tentativas de fora; admin da agência vê as de fora
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := audit_denials_list('ws_ng_a', null, 200);
  insert into t values ('dona da agência vê recusas de A e tentativas de fora', true,
    (j->>'includes_outside')::boolean and jsonb_array_length(j->'rows') = 36
    and exists (select 1 from jsonb_array_elements(j->'rows') x where x->>'actor' = 'ng-b@test.invalid' and x->>'scope' = 'fora'));
  insert into t values ('tentativa a cliente inexistente não aparece em nenhum cliente', true,
    (select count(*) from jsonb_array_elements(j->'rows') x where x->>'actor' = 'ng-b@test.invalid') = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_aadm, 'role','authenticated')::text, true);
  j := audit_denials_list('ws_ng_a', null, 200);
  insert into t values ('admin da agência sem atribuição vê só as de fora', true,
    (j->>'includes_outside')::boolean and jsonb_array_length(j->'rows') = 2
    and not exists (select 1 from jsonb_array_elements(j->'rows') x where x->>'scope' = 'cliente'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_stf, 'role','authenticated')::text, true);
  begin perform audit_denials_list('ws_ng_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem audit.read não lista (42501)', true, st = '42501');

  -- 8. a tabela continua fechada e append-only
  begin perform 1 from audit_events limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('audit_events fechada à API (42501)', true, st = '42501');
  execute 'reset role';
  begin update audit_events set result = 'ok' where action = 'access.denied'; st := 'none'; exception when others then st := 'erro'; end;
  insert into t values ('recusas não se alteram (append-only)', true, st = 'erro');

  -- 9. anónimo recusado
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  begin perform audit_denied_record('ws_ng_a', 'rpc:x', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não regista (42501)', true, st = '42501');
  begin perform audit_denials_list('ws_ng_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não lista (42501)', true, st = '42501');
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', '{}', true);
  begin perform audit_denied_record('ws_ng_a', 'rpc:x', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão individual não regista (28000)', true, st = '28000');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
