-- supabase/tests/w10_videos_por_guiao.sql : vídeos por guião (EDL-15) e corpo partilhado (EDL-14). W10-33; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_view uuid := gen_random_uuid();
  g1 text; g2 text; a1 uuid; a2 uuid; a3 uuid; ab uuid; d uuid; v uuid; b jsonb; st text; seg jsonb; ok int := 0; bad int := 0; res text := ''; rr record; i int;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_vg_b', 'Vídeos B', 'vgb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'vg-adm@test.invalid'),(u_b,'vg-b@test.invalid'),(u_view,'vg-view@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_vg_b', u_b, 'client_staff', 'workspace_admin'),
    ('numeiro', u_view, 'client_staff', 'viewer');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_vg_b', 'all'), ('edit.studio', org, 'ws_vg_b', 'all');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 1 limit 1;
  insert into guioes (id, client_id, date, n, hooks, corpo) values ('vg_gb', 'ws_vg_b', current_date, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- três variantes do guião 1 (dois com o mesmo corpo, um diferente), uma do guião 2, e uma de outro cliente
  for i in 1..5 loop
    insert into media_assets (workspace_id, kind, title, status, created_by, content_id, tags)
    values (case when i = 5 then 'ws_vg_b' else 'numeiro' end, 'video', 'VG ' || i, 'em_trabalho', u_adm,
            case when i <= 3 then g1 when i = 4 then g2 else 'vg_gb' end, array['hook_' || least(i, 3)]) returning id into v;
    if i = 1 then a1 := v; elsif i = 2 then a2 := v; elsif i = 3 then a3 := v; elsif i = 5 then ab := v; end if;
    insert into edit_documents (workspace_id, asset_id, content_id) values (case when i = 5 then 'ws_vg_b' else 'numeiro' end, v, case when i <= 3 then g1 else null end) returning id into d;
    seg := jsonb_build_array(jsonb_build_object('id', 's1', 'in', 10 * i, 'out', 10 * i + 3, 'section', 'hook'),
                             jsonb_build_object('id', 's2', 'in', 100, 'out', case when i = 3 then 105 else 110 end, 'section', 'body'));
    insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
    values (case when i = 5 then 'ws_vg_b' else 'numeiro' end, d, 1,
            jsonb_build_object('schema', 1, 'style', 'S15', 'segments', seg, 'hook', jsonb_build_object('text', 'hook ' || i),
                               'source', jsonb_build_object('cams', jsonb_build_object('front', 'C1.MP4'))), 'import', 'pacote') returning id into v;
    update edit_documents set current_version_id = v where id = d;
  end loop;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  b := edit_board('numeiro');
  insert into t values ('agrupa por guião (2 guiões)', true, jsonb_array_length(b) = 2);
  select x into b from jsonb_array_elements(edit_board('numeiro')) x where x->>'content_id' = g1;
  insert into t values ('guião 1 com 3 variantes', true, jsonb_array_length(b->'variants') = 3);
  insert into t values ('número e tema do guião', true, (b->'guiao'->>'id') = g1 and b->'guiao' ? 'n');
  insert into t values ('texto do hook e duração', true,
    (select bool_and(x->>'hook_text' like 'hook %' and (x->>'duration')::numeric > 0) from jsonb_array_elements(b->'variants') x));
  insert into t values ('mesmo corpo = mesma assinatura; diferente = outra', true,
    (select count(distinct x->>'body_sig') from jsonb_array_elements(b->'variants') x) = 2);
  insert into t values ('primeiro corte e câmaras para a imagem', true,
    (select bool_and(x ? 'first_in' and x->'source'->'cams' ? 'front') from jsonb_array_elements(b->'variants') x));
  insert into t values ('p_content limita a um guião', true, jsonb_array_length(edit_board('numeiro', g1)) = 1);
  insert into t values ('não mostra vídeos de outro cliente', true,
    not exists (select 1 from jsonb_array_elements(edit_board('numeiro')) g, jsonb_array_elements(g->'variants') x where x->>'asset_id' = ab::text));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_board('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê A (42501)', true, st = '42501');
  insert into t values ('cliente B vê só o seu', true, jsonb_array_length(edit_board('ws_vg_b')) = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform edit_board('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor sem editor: recusado (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.edit_board(text, text, int, text)', 'execute'));

  for rr in select * from t loop
    if rr.expected = rr.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || rr.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
