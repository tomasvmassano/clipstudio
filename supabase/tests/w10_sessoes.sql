-- supabase/tests/w10_sessoes.sql : sessões e dispositivos (FR-14-03) e revogação imediata (R-11, CAP-06, FL-07, QA-03, QA-13).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_c uuid := gen_random_uuid(); u_s uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  s_a1 uuid := gen_random_uuid(); s_a2 uuid := gen_random_uuid(); s_a3 uuid := gen_random_uuid(); s_b1 uuid := gen_random_uuid();
  s_c1 uuid := gen_random_uuid(); s_s1 uuid := gen_random_uuid(); s_s2 uuid := gen_random_uuid(); s_adm uuid := gen_random_uuid(); s_own uuid := gen_random_uuid();
  j jsonb; st text; n int; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_s_a', 'Sessões A', 'sa', org), ('ws_s_b', 'Sessões B', 'sb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_a,'s-a@test.invalid'),(u_b,'s-b@test.invalid'),(u_c,'s-c@test.invalid'),(u_s,'s-staff@test.invalid'),
    (u_adm,'s-adm@test.invalid'),(u_own,'s-own@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_s, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_s_a', u_a, 'client_staff', 'contributor'), ('ws_s_b', u_b, 'client_staff', 'contributor'),
    ('ws_s_a', u_c, 'client_staff', 'manager'), ('ws_s_a', u_adm, 'client_staff', 'workspace_admin'),
    ('ws_s_a', u_s, 'agency_staff', 'contributor'), ('ws_s_b', u_s, 'agency_staff', 'contributor');
  insert into auth.sessions (id, user_id, created_at, updated_at, refreshed_at, user_agent, ip, aal) values
    (s_a1, u_a, now() - interval '3 days', now() - interval '1 minute', null, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/130.0 Safari/537.36', '10.0.0.1', 'aal1'),
    (s_a2, u_a, now() - interval '2 days', now() - interval '2 days', (now() - interval '1 hour') at time zone 'UTC', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile/15E148 Safari/604.1', '10.0.0.2', 'aal1'),
    (s_a3, u_a, now() - interval '1 day', now() - interval '1 day', null, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Firefox/131.0', '10.0.0.3', 'aal1'),
    (s_b1, u_b, now(), now(), null, 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130.0', '10.0.0.9', 'aal1'),
    (s_c1, u_c, now(), now(), null, 'curl/8', '10.0.1.1', 'aal1'),
    (s_s1, u_s, now(), now(), null, 'Safari', '10.0.2.1', 'aal1'), (s_s2, u_s, now(), now(), null, 'Chrome', '10.0.2.2', 'aal1'),
    (s_adm, u_adm, now(), now(), null, 'Chrome', '10.0.3.1', 'aal1'), (s_own, u_own, now(), now(), null, 'Chrome', '10.0.4.1', 'aal1');
  insert into auth.refresh_tokens (token, user_id, revoked, session_id) values ('rt-a2', u_a::text, false, s_a2), ('rt-b1', u_b::text, false, s_b1);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- A vê as suas 3 sessões, a atual primeiro e marcada; nenhuma de B
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  j := my_sessions();
  insert into t values ('A vê só as suas 3 sessões', true, jsonb_array_length(j) = 3
    and not exists (select 1 from jsonb_array_elements(j) x where (x->>'id')::uuid in (s_b1, s_c1)));
  insert into t values ('a atual vem primeiro e marcada', true, (j->0->>'id')::uuid = s_a1 and (j->0->>'current')::boolean
    and (select count(*) from jsonb_array_elements(j) x where (x->>'current')::boolean) = 1);
  insert into t values ('sessão traz agente, IP e última atividade (refreshed_at)', true,
    (select x->>'ip' = '10.0.0.2' and x->>'user_agent' like '%iPhone%' and (x->>'last_active_at')::timestamptz > now() - interval '2 hours'
       from jsonb_array_elements(j) x where (x->>'id')::uuid = s_a2));
  insert into t values ('tabela auth.sessions fechada a authenticated', true, not has_table_privilege('authenticated', 'auth.sessions', 'select'));

  -- A não termina a sessão de B (mesmo erro que inexistente)
  begin perform session_terminate(s_b1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não termina sessão de outra pessoa (P0002)', true, st = 'P0002');
  begin perform session_terminate(gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sessão inexistente (P0002)', true, st = 'P0002');
  execute 'reset role';
  insert into t values ('sessão de B continua', true, exists (select 1 from auth.sessions where id = s_b1));
  execute 'set local role authenticated';

  -- A termina a sessão do iPhone: refresh token vai junto; audit
  j := session_terminate(s_a2);
  insert into t values ('terminar uma sessão própria', true, (j->>'id')::uuid = s_a2 and not (j->>'current')::boolean);
  execute 'reset role';
  insert into t values ('sessão e refresh token apagados', true, not exists (select 1 from auth.sessions where id = s_a2)
    and not exists (select 1 from auth.refresh_tokens where token = 'rt-a2') and exists (select 1 from auth.refresh_tokens where token = 'rt-b1'));
  insert into t values ('audit security.session_terminated', true, exists (select 1 from audit_events where actor_user_id = u_a
    and action = 'security.session_terminated' and entity_id = s_a2::text and after->>'user_agent' like '%iPhone%'));
  execute 'set local role authenticated';

  -- o JWT da sessão terminada deixa de servir já (antes de expirar)
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a2)::text, true);
  begin perform workspace_team('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('JWT de sessão terminada: RPC recusa (42501)', true, st = '42501');
  begin perform my_context(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('JWT de sessão terminada: my_context diz sessao_terminada (42501)', true, st = '42501');
  begin perform my_sessions(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('JWT de sessão terminada: não lista sessões (42501)', true, st = '42501');
  begin perform profile_update('{"theme":"light"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('JWT de sessão terminada: não muda o perfil (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('JWT de sessão terminada: _authorize recusa', true, not _authorize('scripts.read', 'ws_s_a'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  insert into t values ('sessão viva continua com acesso', true, _authorize('scripts.read', 'ws_s_a'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  insert into t values ('session_id de outra pessoa não serve', true, not _authorize('scripts.read', 'ws_s_b'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1')::text, true);
  insert into t values ('JWT sem session_id: comportamento de antes', true, _authorize('scripts.read', 'ws_s_a'));
  execute 'reset role';
  update auth.sessions set not_after = now() - interval '1 minute' where id = s_a3;
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a3)::text, true);
  insert into t values ('sessão para lá do not_after recusada', true, not _authorize('scripts.read', 'ws_s_a'));
  update auth.sessions set not_after = null where id = s_a3;

  -- terminar todas as outras: fica só a atual
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  n := sessions_terminate_others();
  insert into t values ('terminar as outras devolve quantas', true, n = 1);
  insert into t values ('fica só a atual', true, jsonb_array_length(my_sessions()) = 1 and (my_sessions()->0->>'id')::uuid = s_a1);
  insert into t values ('histórico de segurança mostra as sessões terminadas', true,
    (select count(*) from jsonb_array_elements(my_security_log()) x where x->>'action' in ('security.session_terminated', 'security.sessions_terminated_others')) = 2);
  perform security_event('security.signed_out_here');
  insert into t values ('"saiu desta sessão" no histórico', true, exists (select 1 from jsonb_array_elements(my_security_log()) x where x->>'action' = 'security.signed_out_here'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1')::text, true);
  begin perform sessions_terminate_others(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem session_id não sabe qual é a atual (22023)', true, st = '22023');
  execute 'reset role';
  insert into t values ('B não foi tocado', true, exists (select 1 from auth.sessions where id = s_b1));
  insert into t values ('audit de "saiu desta sessão" guarda a sessão', true, exists (select 1 from audit_events where actor_user_id = u_a and action = 'security.signed_out_here' and after->>'session_id' = s_a1::text));
  insert into t values ('audit das outras', true, exists (select 1 from audit_events where actor_user_id = u_a and action = 'security.sessions_terminated_others' and (after->>'sessions')::int = 1));

  -- anónimo
  execute 'set local role anon';
  begin perform my_sessions(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não lista sessões', true, st in ('42501', '28000'));
  execute 'reset role';

  -- QA-13: papel reduzido durante a sessão -> nova autorização no pedido seguinte
  perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role','authenticated', 'aal','aal1', 'session_id', s_c1)::text, true);
  insert into t values ('manager gere tarefas antes', true, _authorize('tasks.manage', 'ws_s_a'));
  update workspace_access set workspace_role = 'viewer' where workspace_id = 'ws_s_a' and user_id = u_c;
  insert into t values ('reduzido a viewer: já não gere (mesmo JWT)', true, not _authorize('tasks.manage', 'ws_s_a') and _authorize('scripts.read', 'ws_s_a'));
  insert into t values ('reduzir papel não termina sessões', true, exists (select 1 from auth.sessions where id = s_c1));

  -- QA-03/FL-07: admin remove A (último acesso) -> sessões terminadas; o JWT antigo dá 42501 no pedido seguinte
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  begin perform workspace_team('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A lê a equipa antes de ser removido', true, st = 'none');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated', 'aal','aal1', 'session_id', s_adm)::text, true);
  perform member_remove('ws_s_a', u_a);
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a1)::text, true);
  begin perform workspace_team('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido: próximo pedido com o mesmo JWT dá 42501', true, st = '42501');
  execute 'reset role';
  insert into t values ('removido sem outro acesso: sessões terminadas', true, not exists (select 1 from auth.sessions where user_id = u_a));
  insert into t values ('audit security.sessions_revoked com o admin como ator', true, exists (select 1 from audit_events
    where action = 'security.sessions_revoked' and entity_id = u_a::text and actor_user_id = u_adm and workspace_id = 'ws_s_a'
      and after->>'reason' = 'workspace_access.removed'));
  insert into t values ('autoria e audit preservados (member.removed)', true, exists (select 1 from audit_events where action = 'member.removed' and entity_id = u_a::text));
  -- mesmo com a sessão ainda lá (p.ex. sem trigger), a pertença é verificada a cada pedido
  insert into auth.sessions (id, user_id, user_agent) values (s_a2, u_a, 'teste');
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1', 'session_id', s_a2)::text, true);
  insert into t values ('removido com sessão viva: sem acesso na mesma', true, not _authorize('scripts.read', 'ws_s_a'));

  -- staff da agência retirado de um cliente mas ainda noutro: não é desligado, perde só esse cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated', 'aal','aal1', 'session_id', s_own)::text, true);
  execute 'set local role authenticated';
  perform member_remove('ws_s_a', u_s);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u_s, 'role','authenticated', 'aal','aal1', 'session_id', s_s1)::text, true);
  insert into t values ('staff retirado de A: sessões mantêm-se', true, (select count(*) from auth.sessions where user_id = u_s) = 2);
  insert into t values ('staff retirado de A: sem A, com B', true, not _authorize('scripts.read', 'ws_s_a') and _authorize('scripts.read', 'ws_s_b'));
  -- suspenso na agência: perde tudo e as sessões
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated', 'aal','aal1', 'session_id', s_own)::text, true);
  execute 'set local role authenticated';
  perform agency_member_update(u_s, '{"status":"suspended"}');
  execute 'reset role';
  insert into t values ('staff suspenso na agência: sessões terminadas', true, not exists (select 1 from auth.sessions where user_id = u_s));
  insert into t values ('audit da suspensão com a organização', true, exists (select 1 from audit_events where action = 'security.sessions_revoked'
    and entity_id = u_s::text and organization_id = org and after->>'reason' = 'agency_memberships.suspended'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_s, 'role','authenticated', 'aal','aal1')::text, true);
  insert into t values ('staff suspenso: sem B mesmo com JWT sem sessão', true, not _authorize('scripts.read', 'ws_s_b'));
  insert into t values ('B (outro cliente) não perdeu sessões', true, exists (select 1 from auth.sessions where id = s_b1));
  insert into t values ('funções internas fechadas a authenticated', true,
    not has_function_privilege('authenticated', 'public._session_alive()', 'execute')
    and not has_function_privilege('authenticated', 'public._has_any_access(uuid)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
