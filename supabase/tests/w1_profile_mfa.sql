-- supabase/tests/w1_profile_mfa.sql : perfil e MFA aplicado no servidor (W1-15; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_p_a', 'Perfil A', 'pa', org), ('ws_p_b', 'Perfil B', 'pb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_a,'p-a@test.invalid'),(u_b,'p-b@test.invalid'),(u_own,'p-own@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_p_a', u_a, 'client_staff', 'contributor'), ('ws_p_b', u_b, 'client_staff', 'contributor');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1')::text, true);
  j := profile_update('{"display_name":"  Ana Teste  ","timezone":"Europe/Lisbon","theme":"dark","preferred_workspace":"ws_p_a"}');
  insert into t values ('perfil guarda nome, fuso, tema e cliente preferido', true,
    j->>'display_name' = 'Ana Teste' and j->>'timezone' = 'Europe/Lisbon' and j->>'theme' = 'dark' and j->>'preferred_workspace' = 'ws_p_a');
  insert into t values ('my_context traz o perfil', true, my_context() #>> '{user,display_name}' = 'Ana Teste' and (my_context()->>'mfa_required')::boolean = false);
  begin perform profile_update('{"preferred_workspace":"ws_p_b"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente preferido só entre os seus (42501)', true, st = '42501');
  begin perform profile_update('{"timezone":"Lua/Mar"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('fuso inválido (22023)', true, st = '22023');
  begin perform profile_update('{"theme":"rosa"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tema inválido (22023)', true, st = '22023');
  begin perform profile_update(jsonb_build_object('avatar_path', u_b::text || '/a.webp')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('avatar só na própria pasta (22023)', true, st = '22023');
  j := profile_update(jsonb_build_object('avatar_path', u_a::text || '/avatar-1.webp'));
  insert into t values ('avatar na própria pasta aceite', true, j->>'avatar_path' = u_a::text || '/avatar-1.webp');
  begin perform profile_update('{"email":"x@y.z"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campos fora do perfil recusados (22023)', true, st = '22023');
  begin perform profile_update(jsonb_build_object('display_name', repeat('x', 81))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('nome com mais de 80 (22023)', true, st = '22023');
  begin perform security_event('security.password_changed'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('registar mudança de palavra-passe', true, st = 'none');
  begin perform security_event('qualquer.coisa'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('evento de segurança desconhecido (22023)', true, st = '22023');
  insert into t values ('histórico de segurança da própria pessoa', true,
    (select count(*) from jsonb_array_elements(my_security_log()) x where x->>'action' in ('profile.updated', 'security.password_changed')) >= 2);
  execute 'reset role';
  insert into t values ('tabela profiles fechada a leitura direta', true, not has_table_privilege('authenticated', 'public.profiles', 'select'));

  -- B não vê o perfil nem o histórico de A
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated', 'aal','aal1')::text, true);
  insert into t values ('histórico de segurança é só o próprio', true, jsonb_array_length(my_security_log()) = 0);
  insert into t values ('my_context de B não traz A', true, my_context() #>> '{user,display_name}' is null);

  -- MFA: A ativa um fator; com aal1 perde o acesso, com aal2 volta
  execute 'reset role';
  insert into auth.mfa_factors (user_id, factor_type, status) values (u_a, 'totp', 'verified');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal1')::text, true);
  execute 'reset role';  -- _authorize não é executável por authenticated; as claims da sessão continuam
  insert into t values ('com MFA e sessão aal1: sem acesso ao cliente', true, not _authorize('scripts.read', 'ws_p_a'));
  execute 'set local role authenticated';
  insert into t values ('com MFA e aal1: my_context pede o código', true, (my_context()->>'mfa_required')::boolean and jsonb_array_length(my_context()->'workspaces') = 0);
  begin perform profile_update('{"theme":"light"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('com MFA e aal1: não muda o perfil (42501)', true, st = '42501');
  begin perform workspace_team('ws_p_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('com MFA e aal1: RPCs recusam (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated', 'aal','aal2')::text, true);
  insert into t values ('com MFA e aal2: my_context volta a ter o cliente', true, jsonb_array_length(my_context()->'workspaces') = 1);
  execute 'reset role';
  insert into t values ('com MFA e aal2: acesso volta', true, _authorize('scripts.read', 'ws_p_a'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated', 'aal','aal1')::text, true);
  insert into t values ('verificações do servidor para outro utilizador não dependem da sessão', true, _authorize('scripts.read', 'ws_p_a', u_a));
  -- dono da agência com MFA por verificar (unverified) não é afetado
  insert into auth.mfa_factors (user_id, factor_type, status) values (u_own, 'totp', 'unverified');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated', 'aal','aal1')::text, true);
  insert into t values ('fator por verificar não bloqueia', true, _authorize('scripts.read', 'ws_p_b') and _org_can('team.read', org));
  execute 'set local role anon';
  begin perform profile_update('{"theme":"dark"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não tem perfil', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
