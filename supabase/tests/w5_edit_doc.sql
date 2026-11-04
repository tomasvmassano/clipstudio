-- supabase/tests/w5_edit_doc.sql : documento de edição versionado (W5-06, EDL-07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_man uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  gid text := 'numeiro-2026-10-28-07'; fid text := '1AbCdEfGhIjKlMnOpQrStUvWx';
  a1 jsonb; aid uuid; j jsonb; v1 uuid; v2 uuid; st text; ok int := 0; bad int := 0; res text := ''; r record;
  doc jsonb := '{"schema":1,"fps":30,"style":"S15","segments":[{"id":"s1","in":5.36,"out":10.92,"section":"hook"},{"id":"s2","in":25.12,"out":35.52,"section":"body"}],
                 "captions":{"words":[{"w":"Se","s":5.4,"e":5.8}]},"cameras":[],"hook":{"text":"Hook de teste"},"overlays":[],"audio":{"music":null,"sfx":[]}}';
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ed_b', 'Edit B', 'edb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_man,'ed-man@test.invalid'),(u_con,'ed-con@test.invalid'),(u_view,'ed-view@test.invalid'),(u_b,'ed-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_man, 'client_staff', 'manager'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_ed_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('media.library', org, 'numeiro', 'all'), ('media.library', org, 'ws_ed_b', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_man, 'role','authenticated')::text, true);
  a1 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid || '/view', 'title', 'g07_hook1_S15.mp4',
          'tags', jsonb_build_array('hook_1', 's15'), 'content_id', gid));
  aid := (a1->>'id')::uuid;

  begin perform edit_doc_get('numeiro', aid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('editor desligado: 55000', true, st = '55000');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('edit.studio', org, 'numeiro', 'all');
  execute 'set local role authenticated';

  j := edit_doc_get('numeiro', aid);
  insert into t values ('sem documento ainda, com o vídeo e o guião', true,
    j->'document' = 'null'::jsonb and j->'asset'->>'variant' = 'hook_1' and j->'asset'->>'drive_file_id' = fid and j->'guiao'->>'id' = gid
    and (j->'can'->>'timeline')::boolean and (j->'can'->>'export')::boolean);
  j := edit_doc_save('numeiro', aid, null, doc, 'importado do plano', 'import');
  v1 := (j->'version'->>'id')::uuid;
  insert into t values ('importa como versão 1', true, (j->'version'->>'version_no')::int = 1 and j->'version'->>'source' = 'import' and j->'version'->'doc'->'hook'->>'text' = 'Hook de teste');
  begin perform edit_doc_save('numeiro', aid, null, doc, null, 'import'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gravar sem base quando já há versão: conflito (40001)', true, st = '40001');
  j := edit_doc_save('numeiro', aid, v1, jsonb_set(doc, '{hook,text}', '"Hook corrigido"'), 'corrigi o hook');
  v2 := (j->'version'->>'id')::uuid;
  insert into t values ('versão 2 a partir da 1, a atual passa a ser a 2', true,
    (j->'version'->>'version_no')::int = 2 and j->'version'->>'base_version_id' = v1::text and j->'document'->>'current_version_id' = v2::text
    and jsonb_array_length(j->'versions') = 2 and j->'version'->>'created_label' is not null);
  j := edit_doc_save('numeiro', aid, v2, jsonb_set(doc, '{hook,text}', '"Hook corrigido"'));
  insert into t values ('repetir a mesma gravação não cria versão', true, (j->'version'->>'version_no')::int = 2);
  begin perform edit_doc_save('numeiro', aid, v1, doc); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gravar sobre versão antiga: conflito (40001)', true, st = '40001');
  j := edit_doc_get('numeiro', aid, v1);
  insert into t values ('abre a versão antiga intacta', true, j->'version'->'doc'->'hook'->>'text' = 'Hook de teste');
  begin perform edit_doc_save('numeiro', aid, v2, '{"schema":1,"segments":[]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('documento sem segmentos recusado (22023)', true, st = '22023');
  begin perform edit_doc_save('numeiro', aid, v2, jsonb_set(doc, '{segments,0,out}', '5.4')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('segmento com menos de 0,1 s recusado (22023)', true, st = '22023');
  begin perform edit_doc_save('numeiro', aid, v2, jsonb_set(doc, '{schema}', '2')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('formato desconhecido recusado (22023)', true, st = '22023');

  -- colaborador: modo guiado grava como pessoa, não importa; leitor não abre; outro cliente não vê
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := edit_doc_get('numeiro', aid);
  insert into t values ('colaborador: guiado sim, linha do tempo e exportar não', true,
    (j->'can'->>'guided')::boolean and not (j->'can'->>'timeline')::boolean and not (j->'can'->>'export')::boolean);
  j := edit_doc_save('numeiro', aid, v2, jsonb_set(doc, '{hook,text}', '"Hook do colaborador"'));
  insert into t values ('colaborador grava versão 3', true, (j->'version'->>'version_no')::int = 3 and j->'version'->>'source' = 'user');
  begin perform edit_doc_save('numeiro', aid, (j->'version'->>'id')::uuid, doc, null, 'ai'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não grava como IA (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform edit_doc_get('numeiro', aid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não abre o editor (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_doc_get('numeiro', aid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não abre A (42501)', true, st = '42501');
  begin perform edit_doc_get('ws_ed_b', aid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B pelo seu cliente não encontra o ativo de A', true, st in ('P0002', '55000'));

  -- imutabilidade e tabelas fechadas
  execute 'reset role';
  begin update edit_versions set note = 'x' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se alteram (42501)', true, st = '42501');
  begin delete from edit_versions where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se apagam (42501)', true, st = '42501');
  insert into t values ('tabelas fechadas', true, not has_table_privilege('authenticated', 'public.edit_versions', 'select')
    and not has_table_privilege('authenticated', 'public.edit_documents', 'select'));
  insert into t values ('gravação auditada', true, (select count(*) from audit_events where action = 'edit.version_saved' and entity_id = aid::text) = 3);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
