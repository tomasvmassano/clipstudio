-- supabase/tests/w10_qc_irmas.sql : variantes irmãs para o pHash do QC no export (W10-09; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  a_ok uuid; a_sb uuid; a_b uuid; a_del uuid; a_raw uuid; g text; m jsonb; st text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  set local session_replication_role = replica;
  -- guião g com 3 variantes: a_ok (export R2), a_sb (export R2 noutro asset), um raw do mesmo guião, um export de B com o mesmo content_id
  insert into clients (id, name, handle, organization_id) values ('ws_sib_b', 'Irmãs B', 'sibb', org);
  select id into g from guioes where client_id = 'numeiro' order by date, n limit 1;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, content_id) values ('numeiro', 'video', 'h1', '{}', 'final', 't', g) returning id into a_ok;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, content_id) values ('numeiro', 'video', 'h2', '{}', 'final', 't', g) returning id into a_sb;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, content_id) values ('numeiro', 'video', 'raw', '{}', 'final', 't', g) returning id into a_raw;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, content_id) values ('ws_sib_b', 'video', 'b', '{}', 'final', 't', g) returning id into a_b;
  insert into media_assets (workspace_id, kind, title, tags, status, created_label, content_id, lifecycle, trashed_at) values ('numeiro', 'video', 'lixo', '{}', 'final', 't', g, 'no_lixo', now()) returning id into a_del;
  insert into edit_documents (workspace_id, asset_id, content_id) values ('numeiro', a_ok, g), ('numeiro', a_sb, g), ('numeiro', a_del, g), ('ws_sib_b', a_b, g);
  insert into media_versions (workspace_id, asset_id, version_no, source, size_bytes, sha256, state, storage_bucket, storage_path, mime, storage_provider) values
    ('numeiro', a_ok, 1, 'upload', 100, repeat('a', 64), 'pronta', 'r2', 'numeiro/' || a_ok || '/exports/x.mp4', 'video/mp4', 'r2'),
    ('numeiro', a_sb, 1, 'upload', 100, repeat('a', 64), 'pronta', 'r2', 'numeiro/' || a_sb || '/exports/y.mp4', 'video/mp4', 'r2'),
    ('numeiro', a_raw, 1, 'upload', 100, repeat('a', 64), 'pronta', 'r2', 'numeiro/raw/z.mp4', 'video/mp4', 'r2'),
    ('numeiro', a_del, 1, 'upload', 100, repeat('a', 64), 'pronta', 'r2', 'numeiro/' || a_del || '/exports/d.mp4', 'video/mp4', 'r2'),
    ('ws_sib_b', a_b, 1, 'upload', 100, repeat('a', 64), 'pronta', 'r2', 'ws_sib_b/' || a_b || '/exports/b.mp4', 'video/mp4', 'r2');
  update media_assets x set current_version_id = (select id from media_versions where asset_id = x.id) where id in (a_ok, a_sb, a_raw, a_del, a_b);
  set local session_replication_role = origin;

  m := public._edit_resolve_siblings('numeiro', a_ok);
  insert into t values ('só a outra variante exportada do mesmo guião', true, jsonb_array_length(m) = 1 and (m->0->>'asset_id')::uuid = a_sb
    and m->0->>'key' like 'numeiro/%/exports/%' and m->0 ? 'version_id');
  insert into t values ('irmã de outro cliente nunca entra', true, not exists (select 1 from jsonb_array_elements(m) x where (x->>'asset_id')::uuid = a_b));
  insert into t values ('sem guião ligado: lista vazia', true, public._edit_resolve_siblings('numeiro', gen_random_uuid()) = '[]'::jsonb);
  insert into t values ('pedido por outro cliente não vê as irmãs', true, public._edit_resolve_siblings('ws_sib_b', a_ok) = '[]'::jsonb);
  insert into t values ('export leva as irmãs no input', true, pg_get_functiondef('public.edit_export_request(text, uuid, uuid, text)'::regprocedure) like '%''siblings'', sib%');
  begin
    execute 'set local role authenticated';
    perform public._edit_resolve_siblings('numeiro', a_ok); st := 'ok';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('browser não chama a função interna (42501)', true, st = '42501');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
