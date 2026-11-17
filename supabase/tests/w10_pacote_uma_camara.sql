-- supabase/tests/w10_pacote_uma_camara.sql : pacote com uma câmara só (EDL-01, W10-47, ADR-0086); rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('a', 64); g1 text; f uuid; s uuid; bf uuid; bs uuid;
  j jsonb; k jsonb; k2 jsonb; k3 jsonb; st text; inp jsonb; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_uc_b', 'Uma camara B', 'ucb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'uc-adm@test.invalid'),(u_b,'uc-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_uc_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_uc_b', 'all'), ('edit.studio', org, 'ws_uc_b', 'all'), ('media.r2', org, 'ws_uc_b', 'all');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  -- gravações no R2: duas no numeiro, duas em B
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'UC_C8128.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'UC_C0009.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_uc_b', null, '{}', jsonb_build_object('name', 'B1.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); bf := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_uc_b', bf, null);
  j := media_upload_begin('ws_uc_b', null, '{}', jsonb_build_object('name', 'B2.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); bs := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_uc_b', bs, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 4) loop
    j := media_worker_claim('w-uc', array['ingest']);
    perform media_worker_finish('w-uc', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/proxy.mp4'));
  end loop;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, null, array[g1], 'S15');
  k2 := edit_package_request('numeiro', f, null, array[g1], 'S15', null, 'side');   -- a câmara do som é ignorada: só há uma
  k3 := edit_package_request('numeiro', f, s, array[g1], 'S15');                     -- duas câmaras continuam iguais
  begin perform edit_package_request('numeiro', f, f, array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('a mesma gravação nas duas câmaras continua recusada (22023)', true, st = '22023');
  begin perform edit_package_request('numeiro', null, null, array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem gravação nenhuma: 22023', true, st = '22023');
  begin perform edit_package_request('numeiro', bf, null, array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('uma câmara de outro cliente: não encontrada (P0002)', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, null, array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não pede pacotes em A (42501)', true, st = '42501');
  execute 'reset role';

  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('uma câmara: input.single', true, (inp->>'single')::boolean);
  insert into t values ('uma câmara: som da frente', true, inp->>'audio' = 'front');
  insert into t values ('uma câmara: frente e lado são a mesma gravação', true,
    inp->'front'->>'version_id' = f::text and inp->'side'->>'version_id' = f::text);
  insert into t values ('pedido repetido (mesmo com p_audio side): o mesmo job', true, k2->>'id' = k->>'id');
  insert into t values ('duas câmaras: outro job, sem single', true,
    k3->>'id' <> k->>'id' and (select input->'single' is null and input->'side'->>'version_id' = s::text from media_jobs where id = (k3->>'id')::uuid));
  insert into t values ('audit diz que foi uma câmara', true,
    (select (after->>'single')::boolean from audit_events where action = 'edit.package_requested' and entity_id = k->>'id' limit 1));
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.edit_package_request(text, uuid, uuid, text[], text, text, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
