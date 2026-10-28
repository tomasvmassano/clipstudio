-- supabase/tests/w1_isolation.sql : corre tudo e termina com RAISE para fazer ROLLBACK (nada fica na base)
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_owner uuid := gen_random_uuid(); u_agA uuid := gen_random_uuid(); u_agAB uuid := gen_random_uuid();
  u_cliA uuid := gen_random_uuid(); u_cliB uuid := gen_random_uuid(); u_deny uuid := gen_random_uuid();
  u_susp uuid := gen_random_uuid(); u_exp uuid := gen_random_uuid(); u_none uuid := gen_random_uuid(); u_inv uuid := gen_random_uuid();
  res text := ''; ok int := 0; bad int := 0; ctx jsonb; errmsg text;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_owner,'t-owner@test.invalid',now(),'authenticated','authenticated'),(u_agA,'t-aga@test.invalid',now(),'authenticated','authenticated'),
   (u_agAB,'t-agab@test.invalid',now(),'authenticated','authenticated'),(u_cliA,'t-clia@test.invalid',now(),'authenticated','authenticated'),
   (u_cliB,'t-clib@test.invalid',now(),'authenticated','authenticated'),(u_deny,'t-deny@test.invalid',now(),'authenticated','authenticated'),
   (u_susp,'t-susp@test.invalid',now(),'authenticated','authenticated'),(u_exp,'t-exp@test.invalid',now(),'authenticated','authenticated'),
   (u_none,'t-none@test.invalid',now(),'authenticated','authenticated'),(u_inv,'t-inv@test.invalid',null,'authenticated','authenticated');
  insert into agency_memberships (organization_id, user_id, agency_role, status) values
   (org,u_owner,'agency_owner','active'),(org,u_agA,'agency_member','active'),(org,u_agAB,'agency_member','active'),(org,u_susp,'agency_member','suspended');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, status, expires_at) values
   ('numeiro',u_agA,'agency_staff','manager','active',null),
   ('numeiro',u_agAB,'agency_staff','manager','active',null),('ws_test_b',u_agAB,'agency_staff','viewer','active',null),
   ('numeiro',u_cliA,'client_staff','contributor','active',null),
   ('ws_test_b',u_cliB,'client_staff','workspace_admin','active',null),
   ('numeiro',u_deny,'client_staff','contributor','active',null),
   ('numeiro',u_susp,'agency_staff','manager','active',null),
   ('numeiro',u_exp,'client_staff','contributor','active',now() - interval '1 day');
  insert into permission_grants (workspace_id, user_id, capability, effect) values
   ('numeiro',u_deny,'scripts.read','deny'),('numeiro',u_cliA,'scripts.approve','allow');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  insert into t values
   ('owner lê A', true, _authorize('scripts.read','numeiro',u_owner)),
   ('owner lê B', true, _authorize('scripts.read','ws_test_b',u_owner)),
   ('owner capacidade desconhecida', false, _authorize('scripts.fly','numeiro',u_owner)),
   ('agency A lê A', true, _authorize('scripts.read','numeiro',u_agA)),
   ('agency A NÃO lê B (TEAM-03)', false, _authorize('scripts.read','ws_test_b',u_agA)),
   ('agency AB aprova em A (manager)', true, _authorize('scripts.approve','numeiro',u_agAB)),
   ('agency AB NÃO aprova em B (viewer)', false, _authorize('scripts.approve','ws_test_b',u_agAB)),
   ('agency AB lê B (viewer)', true, _authorize('scripts.read','ws_test_b',u_agAB)),
   ('cliente A lê A', true, _authorize('scripts.read','numeiro',u_cliA)),
   ('cliente A NÃO lê B', false, _authorize('scripts.read','ws_test_b',u_cliA)),
   ('cliente A aprova por grant', true, _authorize('scripts.approve','numeiro',u_cliA)),
   ('cliente A NÃO publica (edit não dá publish)', false, _authorize('publishing.publish','numeiro',u_cliA)),
   ('cliente B NÃO lê A', false, _authorize('scripts.read','numeiro',u_cliB)),
   ('cliente B admin convida em B', true, _authorize('team.invite','ws_test_b',u_cliB)),
   ('deny explícito vence o papel', false, _authorize('scripts.read','numeiro',u_deny)),
   ('deny só nessa capacidade', true, _authorize('sources.read','numeiro',u_deny)),
   ('staff agência suspenso perde clientes', false, _authorize('scripts.read','numeiro',u_susp)),
   ('acesso expirado perde acesso', false, _authorize('scripts.read','numeiro',u_exp)),
   ('sem acesso não vê nada', false, _authorize('scripts.read','numeiro',u_none)),
   ('anónimo não vê nada', false, _authorize('scripts.read','numeiro',null)),
   ('cliente A sem âmbito org', false, _authorize('workspaces.read',null,u_cliA)),
   ('owner âmbito org', true, _authorize('workspaces.create',null,u_owner)),
   ('agency member sem criar workspaces', false, _authorize('workspaces.create',null,u_agA));

  perform set_config('request.jwt.claims', json_build_object('sub', u_cliA, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into t values ('API: authorize() usa o próprio uid', true, public.authorize('scripts.read','numeiro'));
  insert into t values ('API: authorize() de A para B negado', false, public.authorize('scripts.read','ws_test_b'));
  ctx := public.my_context();
  insert into t values ('my_context cliente A só vê A', true, jsonb_array_length(ctx->'workspaces') = 1 and ctx->'workspaces'->0->>'id' = 'numeiro');
  begin perform public._authorize('scripts.read','ws_test_b', u_owner); insert into t values ('API: não chama _authorize (personificar owner)', false, true);
  exception when insufficient_privilege then insert into t values ('API: não chama _authorize (personificar owner)', false, false); end;
  begin perform 1 from public.workspace_access; insert into t values ('API: tabela de acessos fechada', false, true);
  exception when insufficient_privilege then insert into t values ('API: tabela de acessos fechada', false, false); end;
  begin perform public.invite_member('numeiro','x@test.invalid','manager','client_staff'); insert into t values ('contributor não convida', false, true);
  exception when others then insert into t values ('contributor não convida', false, false); end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', u_cliB, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform public.invite_member('ws_test_b','y@test.invalid','manager','agency_staff'); insert into t values ('cliente não convida staff da agência (TEAM-02)', false, true);
  exception when others then insert into t values ('cliente não convida staff da agência (TEAM-02)', false, false); end;
  begin perform public.invite_member('numeiro','y@test.invalid','viewer','client_staff'); insert into t values ('admin de B não convida em A', false, true);
  exception when others then insert into t values ('admin de B não convida em A', false, false); end;
  begin perform public.invite_member('ws_test_b','t-inv@test.invalid','contributor','client_staff'); insert into t values ('admin de B convida em B', true, true);
  exception when others then get stacked diagnostics errmsg = message_text; insert into t values ('admin de B convida em B ('||errmsg||')', true, false); end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', u_inv, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into t values ('convite não é aceite com email por confirmar', true, public.accept_invitations() = 0);
  execute 'reset role';
  update auth.users set email_confirmed_at = now() where id = u_inv;
  execute 'set local role authenticated';
  insert into t values ('convite aceite após confirmar email', true, public.accept_invitations() = 1);
  insert into t values ('convidado vê B', true, public.authorize('scripts.read','ws_test_b'));
  insert into t values ('convidado não vê A', false, public.authorize('scripts.read','numeiro'));
  execute 'reset role';
  insert into t values ('audit regista aceitação', true, exists(select 1 from audit_events where action='invitation.accepted' and actor_user_id=u_inv));
  begin update audit_events set result='ok' where actor_user_id=u_inv; insert into t values ('audit é append-only', false, true);
  exception when others then insert into t values ('audit é append-only', false, false); end;

  select count(*) filter (where expected is not distinct from got), count(*) filter (where expected is distinct from got) into ok, bad from t;
  select string_agg(case when expected is not distinct from got then 'PASS ' else 'FAIL ' end || name, E'\n' order by name) into res from t;
  raise exception E'RESULT ok=% fail=%\n%', ok, bad, res;
end $$;
