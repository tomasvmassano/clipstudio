-- supabase/tests/w1_data_access.sql : acesso aos dados com login e com código (rollback no fim)
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_cliA uuid := gen_random_uuid(); u_cliB uuid := gen_random_uuid(); u_viewA uuid := gen_random_uuid(); u_owner uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  res text; ok int; bad int; n int; j jsonb; errmsg text;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into accounts (id, client_id, role, platform, handle) values ('ws_test_b-ig','ws_test_b','client','instagram','clienteb_test');
  insert into guioes (id, client_id, date, n, corpo) values ('ws_test_b-2026-10-28-01','ws_test_b','2026-10-28',1,'guião secreto do cliente B');
  insert into ideas (client_id, titulo, fonte_tipo) values ('ws_test_b','ideia secreta B','noticia');
  insert into agent_log (run_id, client_id, agent, status, message) values ('run-b','ws_test_b','writer','talk','mensagem secreta B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_cliA,'t-clia@test.invalid',now(),'authenticated','authenticated'),(u_cliB,'t-clib@test.invalid',now(),'authenticated','authenticated'),
   (u_viewA,'t-viewa@test.invalid',now(),'authenticated','authenticated'),(u_owner,'t-owner@test.invalid',now(),'authenticated','authenticated');
  insert into agency_memberships (organization_id, user_id, agency_role) values (org,u_owner,'agency_owner');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_cliA,'client_staff','contributor'),('ws_test_b',u_cliB,'client_staff','workspace_admin'),('numeiro',u_viewA,'client_staff','viewer');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- cliente A
  perform set_config('request.jwt.claims', json_build_object('sub', u_cliA, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into t values ('A vê os 30 guiões de A', true, (select count(*) from guioes where client_id='numeiro') = 30);
  insert into t values ('A não vê guiões de B (RLS)', true, (select count(*) from guioes where client_id='ws_test_b') = 0);
  insert into t values ('A não vê guiões de B pelo id', true, (select count(*) from guioes where id='ws_test_b-2026-10-28-01') = 0);
  insert into t values ('A não vê ideias de B', true, (select count(*) from ideas where client_id='ws_test_b') = 0);
  insert into t values ('A não vê contas de B', true, (select count(*) from accounts where client_id='ws_test_b') = 0);
  insert into t values ('A não vê o workspace B', true, (select count(*) from clients where id='ws_test_b') = 0);
  begin j := public.desempenho('ws_test_b'); insert into t values ('A não lê desempenho de B', false, true);
  exception when insufficient_privilege then insert into t values ('A não lê desempenho de B', false, false); end;
  begin j := public.hoje_resumo('ws_test_b'); insert into t values ('A não lê hoje de B', false, true);
  exception when insufficient_privilege then insert into t values ('A não lê hoje de B', false, false); end;
  begin j := public.agent_run_events('ws_test_b','run-b'); insert into t values ('A não lê eventos de agentes de B', false, true);
  exception when insufficient_privilege then insert into t values ('A não lê eventos de agentes de B', false, false); end;
  begin perform public.guiao_update('ws_test_b-2026-10-28-01','{"corpo":"x"}'::jsonb); insert into t values ('A não edita guião de B', false, true);
  exception when insufficient_privilege then insert into t values ('A não edita guião de B', false, false); end;
  begin perform public.guiao_update('numeiro-2026-10-28-30','{"validado":true}'::jsonb); insert into t values ('contributor não valida (sem scripts.approve)', false, true);
  exception when insufficient_privilege then insert into t values ('contributor não valida (sem scripts.approve)', false, false); end;
  begin perform public.guiao_update('numeiro-2026-10-28-30','{"gravado":true}'::jsonb); insert into t values ('contributor marca gravado', true, true);
  exception when others then get stacked diagnostics errmsg = message_text; insert into t values ('contributor marca gravado ('||errmsg||')', true, false); end;
  j := public.desempenho('numeiro');
  insert into t values ('A lê desempenho de A', true, (j->'kpi'->>'reels')::int = 100);
  begin perform 1 from audit_events; insert into t values ('audit fechado à API', false, true);
  exception when insufficient_privilege then insert into t values ('audit fechado à API', false, false); end;
  execute 'reset role';

  -- viewer de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_viewA, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform public.guiao_update('numeiro-2026-10-28-29','{"corpo":"x"}'::jsonb); insert into t values ('viewer não edita', false, true);
  exception when insufficient_privilege then insert into t values ('viewer não edita', false, false); end;
  begin perform public.agent_simulate('numeiro','[]'::jsonb); insert into t values ('viewer não ensaia agentes', false, true);
  exception when insufficient_privilege then insert into t values ('viewer não ensaia agentes', false, false); end;
  execute 'reset role';

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_cliB, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into t values ('B vê o seu guião', true, (select count(*) from guioes where client_id='ws_test_b') = 1);
  insert into t values ('B não vê os 30 de A', true, (select count(*) from guioes where client_id='numeiro') = 0);
  insert into t values ('B lê eventos dos seus agentes', true, jsonb_array_length(public.agent_run_events('ws_test_b','run-b')) = 1);
  execute 'reset role';

  -- owner da agência vê os dois
  perform set_config('request.jwt.claims', json_build_object('sub', u_owner, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into t values ('owner vê A e B', true, (select count(distinct client_id) from guioes where client_id in ('numeiro','ws_test_b')) = 2);
  execute 'reset role';

  -- código de equipa (anon)
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código lê guiões de A', true, (select count(*) from public.legacy_guioes(tok, '2026-10-28', '2026-10-28')) = 30);
  begin j := public.desempenho('ws_test_b', null, tok); insert into t values ('código de A não lê B', false, true);
  exception when insufficient_privilege then insert into t values ('código de A não lê B', false, false); end;
  begin perform public.guiao_update('ws_test_b-2026-10-28-01','{"validado":true}'::jsonb, tok); insert into t values ('código de A não valida B', false, true);
  exception when insufficient_privilege then insert into t values ('código de A não valida B', false, false); end;
  begin perform 1 from guioes; insert into t values ('anon sem acesso à tabela', false, true);
  exception when insufficient_privilege then insert into t values ('anon sem acesso à tabela', false, false); end;
  execute 'reset role';

  -- negações vão para RAISE LOG 'audit_denied' (ver migração w1_denials_to_db_log), não para audit_events
  insert into t values ('gravado do contributor no audit', true, exists(select 1 from audit_events where action='recording.confirmed' and actor_user_id=u_cliA));

  select count(*) filter (where expected is not distinct from got), count(*) filter (where expected is distinct from got) into ok, bad from t;
  select string_agg(case when expected is not distinct from got then 'PASS ' else 'FAIL ' end || name, E'\n' order by name) into res from t;
  raise exception E'RESULT ok=% fail=%\n%', ok, bad, res;
end $$;
