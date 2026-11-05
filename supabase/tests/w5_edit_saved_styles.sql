-- supabase/tests/w5_edit_saved_styles.sql : estilos guardados no editor (W5-08, EDL-13; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_man uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  gid text := 'numeiro-2026-10-28-07';
  a1 uuid; a2 uuid; a_b uuid; mus uuid := gen_random_uuid(); j jsonb; c1 uuid; c2 uuid; st text; ok int := 0; bad int := 0; res text := ''; r record;
  doc jsonb := '{"schema":1,"fps":30,"style":"S13","size":[1080,1920],
                 "segments":[{"id":"s1","in":5,"out":10,"section":"hook"},{"id":"s2","in":20,"out":30,"section":"body"}],
                 "captions":{"words":[{"id":"w1","w":"Olá","s":5.2,"e":5.6}]},"cameras":[],"hook":{"text":"Hook"},"overlays":[],
                 "audio":{"music":null,"sfx":[],"gains":[]},"notes":[]}';
  looked jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ss_b', 'Estilos guardados B', 'ssb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_man,'ss-man@test.invalid'),(u_con,'ss-con@test.invalid'),(u_view,'ss-view@test.invalid'),(u_b,'ss-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_man, 'client_staff', 'manager'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_ss_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('media.library', org, 'ws_ss_b', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('edit.studio', org, 'ws_ss_b', 'all');
  perform _edit_seed('numeiro', 'system', 'teste');
  insert into media_assets (id, workspace_id, kind, title) values (mus, 'numeiro', 'audio', 'Beat do Numeiro');
  looked := jsonb_set(doc || '{"look":{"captions":{"color":"#FFFFFF","highlight":"#FFD400","size":64,"y":1400},"hook":{"color":"#FFD400","background":"#C8102E","y":400}}}',
                      '{audio,music}', jsonb_build_object('label', 'Beat do Numeiro', 'asset', mus, 'db', -20));
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_man, 'role','authenticated')::text, true);
  a1 := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW1/view', 'title', 'g07_hook1.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', gid))->>'id')::uuid;
  a2 := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW2/view', 'title', 'g07_hook2.mp4',
          'tags', jsonb_build_array('hook_2'), 'content_id', gid))->>'id')::uuid;
  j := edit_doc_save('numeiro', a1, null, looked, null, 'import');
  j := edit_doc_save('numeiro', a2, null, doc, null, 'import');
  c2 := (j->'version'->>'id')::uuid;

  j := edit_style_from_doc('numeiro', a1, null, null, 'Numeiro amarelo', null);
  insert into t values ('guardar como estilo: E01 v1 com aspeto, música e layout do vídeo', true,
    exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'E01' and (x->>'version')::int = 1 and x->>'name' = 'Numeiro amarelo'
            and x->'look'->'captions'->>'highlight' = '#FFD400' and x->'look'->'music'->>'asset' = mus::text and x->'look'->>'layout' = 'S13'));
  insert into t values ('estilo novo copia o layout ativo do S13 e fica ativo', true,
    exists (select 1 from jsonb_array_elements(edit_catalog('numeiro')->'styles') x where x->>'key' = 'E01' and x->>'status' = 'ativo'
            and jsonb_array_length(x->'spec'->'layers') = 4));
  begin perform edit_style_from_doc('numeiro', a1, null, null, '  ', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('estilo novo sem nome recusado (22023)', true, st = '22023');

  -- colaborador (modo guiado) vê e aplica, não guarda
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := edit_saved_styles('numeiro');
  insert into t values ('colaborador vê os estilos guardados (só os que têm aspeto)', true,
    jsonb_array_length(j->'styles') = 1 and j->'styles'->0->>'key' = 'E01' and not (j->>'can_manage')::boolean);
  begin perform edit_style_from_doc('numeiro', a1, null, null, 'x', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não guarda estilos (42501)', true, st = '42501');
  j := edit_style_apply('numeiro', a2, c2, 'E01');
  insert into t values ('aplicar a outro vídeo cria versão nova com o aspeto e a música', true,
    (j->'version'->>'version_no')::int = 2 and j->'version'->>'source' = 'user'
    and j->'version'->'doc'->'look'->'from' = '{"key":"E01","version":1}'::jsonb and j->'version'->'doc'->'look'->'hook'->>'background' = '#C8102E'
    and j->'version'->'doc'->'audio'->'music'->>'asset' = mus::text and j->'version'->'doc'->'segments' = doc->'segments' and j->'version'->>'note' like 'estilo Numeiro amarelo%');
  c2 := (j->'version'->>'id')::uuid;
  j := edit_style_apply('numeiro', a2, c2, 'E01');
  insert into t values ('aplicar outra vez não cria versão', true, (j->'version'->>'version_no')::int = 2);
  begin perform edit_style_apply('numeiro', a2, (select (x->>'id')::uuid from jsonb_array_elements(edit_doc_get('numeiro', a2)->'versions') x where (x->>'version_no')::int = 1), 'E01');
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aplicar sobre versão antiga: conflito (40001)', true, st = '40001');
  j := edit_doc_save('numeiro', a2, c2, jsonb_set((edit_doc_get('numeiro', a2)->'version'->'doc'), '{hook,text}', '"Hook do cliente"'));
  insert into t values ('depois de aplicar, o modo guiado continua a gravar', true, (j->'version'->>'version_no')::int = 3);
  c2 := (j->'version'->>'id')::uuid;

  -- gestor: versão nova do estilo, conflito, catálogo mantém o aspeto
  perform set_config('request.jwt.claims', json_build_object('sub', u_man, 'role','authenticated')::text, true);
  c1 := (edit_doc_get('numeiro', a1)->'version'->>'id')::uuid;
  j := edit_doc_save('numeiro', a1, c1, jsonb_set((edit_doc_get('numeiro', a1)->'version'->'doc'), '{look,captions,color}', '"#00FF00"'));
  j := edit_style_from_doc('numeiro', a1, null, 'E01', null, 1);
  insert into t values ('atualizar o estilo cria a v2 com o aspeto novo', true,
    exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'E01' and (x->>'version')::int = 2 and x->'look'->'captions'->>'color' = '#00FF00'));
  begin perform edit_style_from_doc('numeiro', a1, null, 'E01', null, 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('atualizar com versão vista antiga: conflito (40001)', true, st = '40001');
  j := edit_style_save('numeiro', 'E01', '{"notes":"retocado no catálogo"}', 2);
  insert into t values ('gravar no catálogo mantém o aspeto (v3)', true,
    exists (select 1 from jsonb_array_elements(edit_saved_styles('numeiro')->'styles') x where x->>'key' = 'E01' and (x->>'version')::int = 3
            and x->'look'->'captions'->>'color' = '#00FF00'));
  j := edit_style_from_doc('numeiro', a2, null, null, 'Segundo', null);
  insert into t values ('segundo estilo novo é E02', true, exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'E02'));

  -- música tirada da biblioteca e estilo arquivado
  execute 'reset role';
  update media_assets set lifecycle = 'no_lixo', trashed_at = now() where id = mus;
  execute 'set local role authenticated';
  begin perform edit_style_apply('numeiro', a2, c2, 'E01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('música do estilo já não está na biblioteca (22023)', true, st = '22023');
  perform edit_style_set_status('numeiro', 'E02', 'arquivado');
  begin perform edit_style_apply('numeiro', a2, c2, 'E02'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('estilo arquivado não se aplica (P0002)', true, st = 'P0002');
  begin perform edit_style_apply('numeiro', a2, c2, 'S01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('estilo do catálogo sem aspeto não se aplica (22023)', true, st = '22023');

  -- leitor e outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform edit_saved_styles('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não lê estilos do editor (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_saved_styles('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê os estilos de A (42501)', true, st = '42501');
  begin perform edit_style_apply('numeiro', a2, c2, 'E01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não aplica em A (42501)', true, st = '42501');
  begin perform edit_style_from_doc('ws_ss_b', a1, null, null, 'roubado', null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não guarda estilo a partir de um vídeo de A (P0002)', true, st = 'P0002');
  insert into t values ('B não tem estilos de A', true, jsonb_array_length(edit_saved_styles('ws_ss_b')->'styles') = 0);
  begin perform edit_style_apply('ws_ss_b', a2, c2, 'E01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não aplica o estilo de A pelo seu cliente (P0002)', true, st = 'P0002');

  execute 'reset role';
  insert into t values ('versões do estilo imutáveis (v1 com o aspeto antigo)', true,
    (select look->'captions'->>'color' from edit_style_versions where workspace_id = 'numeiro' and key = 'E01' and version = 1) = '#FFFFFF');
  insert into t values ('auditado: guardar e aplicar', true,
    (select count(*) from audit_events where action = 'edit.style_saved' and workspace_id = 'numeiro' and entity_id in ('E01', 'E02')) >= 3
    and (select count(*) from audit_events where action = 'edit.style_applied' and entity_id = a2::text) = 1);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
