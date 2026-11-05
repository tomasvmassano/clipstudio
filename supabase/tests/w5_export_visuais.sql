-- supabase/tests/w5_export_visuais.sql : visuais do documento resolvidos para o export (W5-17; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  a_ok uuid; a_sb uuid; a_b uuid; a_del uuid; m jsonb; doc jsonb; st text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_vis_b', 'Visuais B', 'visb', org);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  set local session_replication_role = replica;   -- fixtures: versões prontas direto, sem os guardas do fluxo de upload
  insert into media_assets (workspace_id, kind, title, tags, status, created_label) values ('numeiro', 'video', 'broll r2', '{}', 'final', 't') returning id into a_ok;
  insert into media_versions (workspace_id, asset_id, version_no, source, size_bytes, sha256, state, storage_bucket, storage_path, mime, storage_provider, media_info)
  values ('numeiro', a_ok, 1, 'upload', 100, repeat('a', 64), 'pendente', 'r2', 'numeiro/broll/a.mp4', 'video/mp4', 'r2', '{"duration": 3.2}');
  update media_assets set current_version_id = (select id from media_versions where asset_id = a_ok) where id = a_ok;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label) values ('numeiro', 'imagem', 'imagem supabase', '{}', 'final', 't') returning id into a_sb;
  insert into media_versions (workspace_id, asset_id, version_no, source, size_bytes, sha256, state, storage_bucket, storage_path, mime, storage_provider)
  values ('numeiro', a_sb, 1, 'upload', 100, repeat('a', 64), 'pendente', 'media', 'numeiro/x.png', 'image/png', 'supabase');
  update media_assets set current_version_id = (select id from media_versions where asset_id = a_sb) where id = a_sb;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label) values ('ws_vis_b', 'video', 'broll de B', '{}', 'final', 't') returning id into a_b;
  insert into media_versions (workspace_id, asset_id, version_no, source, size_bytes, sha256, state, storage_bucket, storage_path, mime, storage_provider)
  values ('ws_vis_b', a_b, 1, 'upload', 100, repeat('a', 64), 'pendente', 'r2', 'ws_vis_b/b.mp4', 'video/mp4', 'r2');
  update media_assets set current_version_id = (select id from media_versions where asset_id = a_b) where id = a_b;
  update media_versions set state = 'pronta' where asset_id in (a_ok, a_sb, a_b);
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, lifecycle, trashed_at) values ('numeiro', 'video', 'apagado', '{}', 'final', 't', 'no_lixo', now()) returning id into a_del;

  set local session_replication_role = origin;
  doc := jsonb_build_object('overlays', jsonb_build_array(
    jsonb_build_object('id', 'o1', 'kind', 'broll', 'asset', a_ok::text), jsonb_build_object('id', 'o2', 'kind', 'graphic', 'asset', a_sb::text),
    jsonb_build_object('id', 'o3', 'kind', 'broll', 'asset', a_b::text), jsonb_build_object('id', 'o4', 'kind', 'broll', 'asset', a_del::text),
    jsonb_build_object('id', 'o5', 'kind', 'text', 'label', 'só texto'), jsonb_build_object('id', 'o6', 'kind', 'broll', 'asset', a_ok::text)));
  m := public._edit_resolve_visuals('numeiro', doc);
  insert into t values ('ativo R2 pronto do cliente resolvido com chave', true, m->a_ok::text->>'key' = 'numeiro/broll/a.mp4' and m->a_ok::text->>'bucket' = 'r2'
    and (m->a_ok::text->'media_info'->>'duration')::numeric = 3.2);
  insert into t values ('imagem fora do R2 vai a null', true, m ? a_sb::text and m->a_sb::text = 'null'::jsonb);
  insert into t values ('ativo de outro cliente vai a null', true, m ? a_b::text and m->a_b::text = 'null'::jsonb);
  insert into t values ('ativo apagado vai a null', true, m->a_del::text = 'null'::jsonb);
  insert into t values ('texto não pede ficheiro; repetidos uma vez', true, (select count(*) from jsonb_object_keys(m)) = 4);
  insert into t values ('documento sem visuais dá mapa vazio', true, public._edit_resolve_visuals('numeiro', '{}') = '{}'::jsonb);
  insert into t values ('export leva os visuais no input', true, pg_get_functiondef('public.edit_export_request(text, uuid, uuid, text)'::regprocedure) like '%''visuals'', vis%');
  begin
    execute 'set local role authenticated';
    perform public._edit_resolve_visuals('numeiro', doc); st := 'ok';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('browser não chama a função interna (42501)', true, st = '42501');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
