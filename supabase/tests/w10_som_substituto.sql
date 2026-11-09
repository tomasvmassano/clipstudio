-- supabase/tests/w10_som_substituto.sql : som substituto de uma gravação (EDL-08, ADR-0080). W10-32; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_view uuid := gen_random_uuid();
  sha text := repeat('a', 64); vid uuid; aud uuid; aud_long uuid; img uuid; bvid uuid; baud uuid; asset uuid; doc jsonb;
  j jsonb; r jsonb; st text; c jsonb; e1 jsonb; e2 jsonb; e3 jsonb; ok int := 0; bad int := 0; res text := ''; rr record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ss_b', 'Som B', 'ssb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'ss-adm@test.invalid'),(u_b,'ss-b@test.invalid'),(u_view,'ss-view@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_ss_b', u_b, 'client_staff', 'workspace_admin'),
    ('numeiro', u_view, 'client_staff', 'viewer');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_ss_b', 'all'), ('media.r2', org, 'ws_ss_b', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'SS_C7870.MP4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); vid := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', vid, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'SS_lapela.wav', 'size', 3000, 'mime', 'audio/wav', 'sha256', sha)); aud := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', aud, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'SS_outro.wav', 'size', 3000, 'mime', 'audio/wav', 'sha256', sha)); aud_long := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', aud_long, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'SS_capa.png', 'size', 100, 'mime', 'image/png', 'sha256', sha)); img := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', img, null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_ss_b', null, '{}', jsonb_build_object('name', 'B.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); bvid := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_ss_b', bvid, null);
  j := media_upload_begin('ws_ss_b', null, '{}', jsonb_build_object('name', 'B.wav', 'size', 3000, 'mime', 'audio/wav', 'sha256', sha)); baud := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_ss_b', baud, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for rr in select 1 from generate_series(1, 6) loop
    j := media_worker_claim('w-ss', array['ingest']);
    perform media_worker_finish('w-ss', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha,
      'proxy_key', case when j->'job'->'input'->>'mime' like 'video/%' then 'x/proxy.mp4' end));
  end loop;
  execute 'reset role';
  update media_versions set media_info = jsonb_build_object('duration', 1615.2) where id = vid;
  update media_versions set media_info = jsonb_build_object('duration', 1615.23) where id = aud;
  update media_versions set media_info = jsonb_build_object('duration', 1500) where id = aud_long;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform media_audio_replace('numeiro', vid, aud); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem media.upload: recusado (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_audio_replace('numeiro', vid, aud); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não liga som em A (42501)', true, st = '42501');
  begin perform media_audio_replace('ws_ss_b', bvid, aud); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('áudio de A numa gravação de B: não encontrado', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform media_audio_replace('numeiro', vid, baud); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('áudio de B numa gravação de A: não encontrado', true, st = 'P0002');
  begin perform media_audio_replace('numeiro', vid, img); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('imagem não serve de som (22023)', true, st = '22023');
  begin perform media_audio_replace('numeiro', aud, aud); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('áudio não leva som substituto (22023)', true, st = '22023');
  begin perform media_audio_replace('numeiro', vid, aud_long); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('duração diferente recusada (22023)', true, st = '22023');
  r := media_audio_replace('numeiro', vid, aud);
  insert into t values ('liga o som substituto', true, r->>'audio_version_id' = aud::text);
  insert into t values ('a Biblioteca vê a ligação', true, media_audio_links('numeiro')->>vid::text = aud::text);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  insert into t values ('cliente B não vê ligações de A', true, coalesce(media_audio_links('ws_ss_b'), '{}') = '{}'::jsonb);
  begin perform media_audio_links('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê ligações de A (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('original intacto (pronta, mesmo sha)', true,
    (select state = 'pronta' and sha256 = sha from media_versions where id = vid));
  insert into t values ('audit da troca', true, exists (select 1 from audit_events where action = 'media.audio_replaced' and after->>'audio_version_id' = aud::text));

  -- a exportação e o palco veem o som
  doc := jsonb_build_object('source', jsonb_build_object('cams', jsonb_build_object('front', 'SS_C7870.MP4'), 'audio', 'front'));
  c := public._edit_resolve_cams('numeiro', doc);
  insert into t values ('câmaras levam audio_key e audio_version_id', true,
    c->'front'->>'audio_version_id' = aud::text and c->'front'->>'audio_key' = (select storage_path from media_versions where id = aud));

  -- export: a chave muda com o som
  select id into asset from media_assets where workspace_id = 'numeiro' and current_version_id = vid;
  insert into media_assets (id, workspace_id, kind, title, status, created_by) values (gen_random_uuid(), 'numeiro', 'video', 'SS doc', 'em_trabalho', u_adm) returning id into asset;
  insert into edit_documents (workspace_id, asset_id) values ('numeiro', asset);
  insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
    select 'numeiro', d.id, 1, doc || jsonb_build_object('schema', 1, 'segments', '[]'::jsonb), 'user', 'teste' from edit_documents d where d.asset_id = asset;
  update edit_documents d set current_version_id = (select id from edit_versions where document_id = d.id) where d.asset_id = asset;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin
    e1 := edit_export_request('numeiro', asset);
    perform media_audio_replace('numeiro', vid, null);
    e2 := edit_export_request('numeiro', asset);
    e3 := edit_export_request('numeiro', asset);
    perform media_audio_replace('numeiro', vid, aud);
    insert into t values ('trocar o som dá um export novo', true, e1->>'id' <> e2->>'id');
    insert into t values ('sem trocar: o mesmo export', true, e2->>'id' = e3->>'id');
  exception when others then
    insert into t values ('export com e sem som: ' || sqlerrm, true, false);
  end;
  r := edit_preview_sources('numeiro', asset);
  insert into t values ('palco recebe audio_version_id', true, r->'cams'->'front'->>'audio_version_id' = aud::text);
  r := media_audio_replace('numeiro', vid, null);
  execute 'reset role';
  insert into t values ('tirar o som substituto', true, (select audio_version_id is null from media_versions where id = vid));
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.media_audio_replace(text, uuid, uuid, text)', 'execute'));

  for rr in select * from t loop
    if rr.expected = rr.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || rr.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
