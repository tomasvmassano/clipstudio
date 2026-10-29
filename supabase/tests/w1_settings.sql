-- supabase/tests/w1_settings.sql : definições do cliente, logótipo no storage e cor (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_s_a', 'Definições A', 'sa', org), ('ws_s_b', 'Definições B', 'sb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'s-adm@test.invalid'),(u_view,'s-view@test.invalid'),(u_b,'s-b@test.invalid'),(u_own,'s-own@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_s_a', u_adm, 'client_staff', 'workspace_admin'), ('ws_s_a', u_view, 'client_staff', 'viewer'), ('ws_s_b', u_b, 'client_staff', 'workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- admin de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := workspace_settings('ws_s_a');
  insert into t values ('admin lê definições com permissão de gerir', true, j->>'name' = 'Definições A' and (j->'can'->>'manage')::boolean and not (j->'can'->>'archive')::boolean);
  begin insert into storage.objects (bucket_id, name, owner) values ('branding', 'ws_s_a/logo-abcdefgh12.png', u_adm); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('admin carrega logótipo no seu cliente', true, st = 'none');
  begin insert into storage.objects (bucket_id, name, owner) values ('branding', 'ws_s_b/logo-abcdefgh12.png', u_adm); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('admin de A não carrega em B (42501)', true, st = '42501');
  begin insert into storage.objects (bucket_id, name, owner) values ('branding', 'ws_s_a/evil.svg', u_adm); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('caminho ou extensão fora do padrão recusado (42501)', true, st = '42501');
  j := workspace_update('ws_s_a', '{"logo_path":"ws_s_a/logo-abcdefgh12.png","brand_color":"#FF6600"}');
  insert into t values ('guarda logótipo e cor (normalizada)', true, j->>'logo_path' = 'ws_s_a/logo-abcdefgh12.png' and j->>'brand_color' = '#ff6600');
  begin perform workspace_update('ws_s_a', '{"logo_path":"ws_s_a/logo-naoexiste99.png"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('logótipo que não existe no storage recusado (22023)', true, st = '22023');
  begin perform workspace_update('ws_s_a', '{"logo_path":"ws_s_b/logo-abcdefgh12.png"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('logótipo de outro cliente recusado (22023)', true, st = '22023');
  begin perform workspace_update('ws_s_a', '{"brand_color":"vermelho"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cor inválida recusada (22023)', true, st = '22023');
  insert into t values ('contexto traz logótipo e cor', true,
    exists (select 1 from jsonb_array_elements(my_context()->'workspaces') w where w->>'id' = 'ws_s_a' and w->>'brand_color' = '#ff6600' and w->>'logo_path' is not null));

  -- viewer de A lê mas não muda
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform workspace_settings('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer sem team.read não lê definições (42501)', true, st = '42501');
  insert into t values ('viewer vê o logótipo do seu cliente', true, (select count(*) from storage.objects where bucket_id = 'branding' and name = 'ws_s_a/logo-abcdefgh12.png') = 1);
  begin insert into storage.objects (bucket_id, name, owner) values ('branding', 'ws_s_a/logo-zzzzzzzz12.png', u_view); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('viewer não carrega logótipo (42501)', true, st = '42501');
  begin perform workspace_update('ws_s_a', '{"brand_color":"#000000"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não muda a cor (42501)', true, st = '42501');

  -- admin de B não vê nada de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  insert into t values ('B não vê o logótipo de A', true, (select count(*) from storage.objects where bucket_id = 'branding' and name like 'ws_s_a/%') = 0);
  begin perform workspace_settings('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê definições de A (42501)', true, st = '42501');
  begin delete from storage.objects where bucket_id = 'branding' and name = 'ws_s_a/logo-abcdefgh12.png'; st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('B não apaga o logótipo de A', true, exists (select 1 from storage.objects where bucket_id = 'branding' and name = 'ws_s_a/logo-abcdefgh12.png'));
  execute 'set local role authenticated';

  -- dono da agência: vê arquivar; caminho inválido não é lido por ser dono
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência pode arquivar a partir das definições', true, (workspace_settings('ws_s_a')->'can'->>'archive')::boolean);
  execute 'reset role';
  insert into storage.objects (bucket_id, name) values ('branding', 'solto.png');
  execute 'set local role authenticated';
  insert into t values ('ficheiro fora do padrão não é lido nem pelo dono da agência', true, (select count(*) from storage.objects where bucket_id = 'branding' and name = 'solto.png') = 0);
  execute 'reset role';
  insert into t values ('mudança de logótipo e cor auditada', true,
    exists (select 1 from audit_events where action = 'workspace.updated' and entity_id = 'ws_s_a' and after->>'brand_color' = '#ff6600'));
  execute 'set local role anon';
  begin perform workspace_settings('ws_s_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não lê definições (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
