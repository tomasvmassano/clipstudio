-- supabase/tests/w10_som_da_lapela.sql : câmara com o som da lapela escolhida no pedido do pacote (EDL-01, ADR-0074). W10-27; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('a', 64); g1 text; f uuid; s uuid; bf uuid; bs uuid;
  j jsonb; k jsonb; k2 jsonb; k3 jsonb; st text; inp jsonb; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_lp_b', 'Lapela B', 'lpb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'lp-adm@test.invalid'),(u_b,'lp-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_lp_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_lp_b', 'all'), ('edit.studio', org, 'ws_lp_b', 'all'), ('media.r2', org, 'ws_lp_b', 'all');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  -- gravações no R2: duas no numeiro, duas em B
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'LP_C7870.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'LP_C0008.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_lp_b', null, '{}', jsonb_build_object('name', 'B1.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); bf := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_lp_b', bf, null);
  j := media_upload_begin('ws_lp_b', null, '{}', jsonb_build_object('name', 'B2.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); bs := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_lp_b', bs, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 4) loop
    j := media_worker_claim('w-lp', array['ingest']);
    perform media_worker_finish('w-lp', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/proxy.mp4'));
  end loop;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  -- 1. sem p_audio: o comportamento de sempre (som do lado), chave igual
  k := edit_package_request('numeiro', f, s, array[g1], 'S15');
  -- 2. som na frente: input.audio = front e chave diferente (outro job)
  k2 := edit_package_request('numeiro', f, s, array[g1], 'S15', null, 'front');
  -- 3. repetir com som na frente: o mesmo job (idempotente)
  k3 := edit_package_request(p_ws => 'numeiro', p_front => f, p_side => s, p_guioes => array[g1], p_audio => 'front');
  begin perform edit_package_request('numeiro', f, s, array[g1], 'S15', null, 'lapela'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('câmara do som desconhecida é recusada (22023)', true, st = '22023');
  -- isolamento: com o som na frente, A não usa gravações de B
  begin perform edit_package_request('numeiro', bf, bs, array[g1], 'S15', null, 'front'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gravações de outro cliente: não encontradas', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1], 'S15', null, 'front'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não pede pacotes em A (42501)', true, st = '42501');
  execute 'reset role';

  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('sem p_audio: som do lado no job', true, inp->>'audio' = 'side');
  insert into t values ('sem p_audio: chave sem sufixo :af', true, (select idempotency_key not like '%:af' from media_jobs where id = (k->>'id')::uuid));
  select input into inp from media_jobs where id = (k2->>'id')::uuid;
  insert into t values ('som na frente: input.audio = front', true, inp->>'audio' = 'front');
  insert into t values ('som na frente: outro job', true, k2->>'id' <> k->>'id');
  insert into t values ('som na frente: chave com :af', true, (select idempotency_key like '%:af' from media_jobs where id = (k2->>'id')::uuid));
  insert into t values ('repetir com som na frente: mesmo job', true, k3->>'id' = k2->>'id');
  insert into t values ('as câmaras continuam no sítio (frente e lado)', true, inp->'front'->>'version_id' = f::text and inp->'side'->>'version_id' = s::text);
  insert into t values ('audit do pedido diz de onde vem o som', true,
    (select after->>'audio' = 'front' from audit_events where action = 'edit.package_requested' and entity_id = k2->>'id' limit 1));
  insert into t values ('só existe uma edit_package_request (sem sobrecarga ambígua)', true,
    (select count(*) = 1 from pg_proc where proname = 'edit_package_request' and pronamespace = 'public'::regnamespace));
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.edit_package_request(text, uuid, uuid, text[], text, text, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
