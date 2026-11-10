-- supabase/tests/w10_exportados.sql : página Exportados (W10-44, EDL-11; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_ed uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := (select id from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1);
  sha text := repeat('c', 64);
  a1 uuid := gen_random_uuid(); v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid(); ab uuid := gen_random_uuid(); vb uuid := gen_random_uuid();
  at uuid := gen_random_uuid(); vt uuid := gen_random_uuid();
  f jsonb; it jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ex_b', 'Exportados B', 'exb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_ed,'ex-ed@test.invalid'),(u_view,'ex-view@test.invalid'),(u_b,'ex-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ed, 'client_staff', 'manager'), ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_ex_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('media.library', org, 'numeiro', 'all');

  insert into media_assets (id, workspace_id, kind, title, tags, content_id) values
    (a1, 'numeiro', 'video', 'Guião hook 1', '{hook_1}', gid), (ab, 'ws_ex_b', 'video', 'B', '{}', null),
    (at, 'numeiro', 'video', 'No lixo', '{}', null);
  insert into media_versions (id, workspace_id, asset_id, version_no, source, storage_path, size_bytes, mime, sha256, original_name) values
    (v1, 'numeiro', a1, 1, 'upload', 'numeiro/ex/1.mp4', 1000, 'video/mp4', sha, '1.mp4'),
    (v2, 'numeiro', a1, 2, 'upload', 'numeiro/ex/2.mp4', 2000, 'video/mp4', sha, '2.mp4'),
    (vb, 'ws_ex_b', ab, 1, 'upload', 'ws_ex_b/ex/1.mp4', 1000, 'video/mp4', sha, 'b.mp4'),
    (vt, 'numeiro', at, 1, 'upload', 'numeiro/ex/t.mp4', 1000, 'video/mp4', sha, 't.mp4');
  update media_versions set state = 'pronta', media_info = '{"duration": 42.5}' where id in (v1, v2, vb, vt);
  update media_assets set lifecycle = 'no_lixo', trashed_at = now() where id = at;
  insert into media_jobs (workspace_id, kind, idempotency_key, asset_id, status, result, created_label, finished_at, created_at) values
    ('numeiro', 'export', 'ex-1', a1, 'done', jsonb_build_object('version_id', v1, 'version_no', 1), 'ed', now() - interval '2 hours', now() - interval '3 hours'),
    ('numeiro', 'export', 'ex-2', a1, 'done', jsonb_build_object('version_id', v2, 'version_no', 2), 'ed', now() - interval '1 hour', now() - interval '90 minutes'),
    ('numeiro', 'export', 'ex-3', a1, 'running', null, 'ed', null, now()),
    ('numeiro', 'export', 'ex-4', a1, 'cancelled', null, 'ed', now(), now()),
    ('numeiro', 'export', 'ex-old', a1, 'done', jsonb_build_object('version_id', v1), 'ed', now() - interval '40 days', now() - interval '40 days'),
    ('numeiro', 'export', 'ex-trash', at, 'done', jsonb_build_object('version_id', vt), 'ed', now(), now()),
    ('ws_ex_b', 'export', 'ex-b', ab, 'done', jsonb_build_object('version_id', vb), 'b', now(), now());
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  f := edit_exports_feed('numeiro');
  insert into t values ('lista prontos e a exportar (3), sem cancelado, antigo, lixo nem outro cliente', true, jsonb_array_length(f->'items') = 3);
  insert into t values ('mais recente primeiro (a exportar)', true, f->'items'->0->>'status' = 'running');
  select x into it from jsonb_array_elements(f->'items') x where x->>'version_id' = v2::text;
  insert into t values ('v2 é a mais recente; v1 não', true, (it->>'latest')::boolean
    and not (select (x->>'latest')::boolean from jsonb_array_elements(f->'items') x where x->>'version_id' = v1::text));
  insert into t values ('guião, duração e tamanho', true, (it->'content'->>'id') = gid and (it->>'duration')::numeric = 42.5 and (it->>'size_bytes')::int = 2000);
  insert into t values ('gestor pode descarregar', true, (f->>'can_download')::boolean);
  insert into t values ('40 dias com p_days 60', true, jsonb_array_length(edit_exports_feed('numeiro', 60)->'items') = 4);
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  f := edit_exports_feed('numeiro');
  insert into t values ('leitor vê a lista', true, jsonb_array_length(f->'items') = 3);
  insert into t values ('leitor não descarrega (media.download)', true, not (f->>'can_download')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_exports_feed('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente: 42501', true, st = '42501');
  begin perform edit_exports_feed('ws_ex_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('biblioteca desligada: 55000', true, st = '55000');
  perform set_config('request.jwt.claims', '{}', true);
  begin perform edit_exports_feed('numeiro', 14, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa: recusado (28000)', true, st = '28000');
  execute 'reset role';
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.edit_exports_feed(text, int, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
