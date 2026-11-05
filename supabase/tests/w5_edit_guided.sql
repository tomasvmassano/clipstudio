-- supabase/tests/w5_edit_guided.sql : modo guiado do editor (W5-07, EDL-10; rollback no fim).
-- O servidor só deixa quem tem apenas edit.guided gravar as mudanças do modo guiado; negativos entre modos e entre clientes.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_man uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  gid text := 'numeiro-2026-10-28-07';
  aid uuid; mus uuid := gen_random_uuid(); mus2 uuid := gen_random_uuid(); mus_b uuid := gen_random_uuid(); vid uuid := gen_random_uuid();
  j jsonb; cur uuid; d jsonb; st text; msg text; ok int := 0; bad int := 0; res text := ''; r record; lbl text;
  doc jsonb := '{"schema":1,"fps":30,"style":"S15","size":[1080,1920],
                 "segments":[{"id":"s1","in":5.36,"out":10.92,"section":"hook"},{"id":"s2","in":25.12,"out":35.52,"section":"body"},{"id":"s3","in":40,"out":44,"section":"body"}],
                 "captions":{"words":[{"id":"w1","w":"Se","s":5.4,"e":5.8},{"id":"w2","w":"corpo","s":26,"e":26.5}]},"cameras":[{"s":0,"e":60,"cam":"front","zoom":1}],
                 "hook":{"text":"Hook de teste"},"overlays":[],"audio":{"music":null,"sfx":[],"gains":[]},"notes":[]}';
begin
  insert into clients (id, name, handle, organization_id) values ('ws_eg_b', 'Guiado B', 'egb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_man,'eg-man@test.invalid'),(u_con,'eg-con@test.invalid'),(u_rev,'eg-rev@test.invalid'),(u_b,'eg-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_man, 'client_staff', 'manager'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_rev, 'client_staff', 'reviewer'), ('ws_eg_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('media.library', org, 'ws_eg_b', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('edit.studio', org, 'ws_eg_b', 'all');
  insert into media_assets (id, workspace_id, kind, title) values
    (mus, 'numeiro', 'audio', 'Música A'), (mus2, 'numeiro', 'audio', 'Música B'), (vid, 'numeiro', 'video', 'Não é áudio'), (mus_b, 'ws_eg_b', 'audio', 'Música do cliente B');
  lbl := 'eg-con@test.invalid';
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';

  -- gestor (linha do tempo) importa v1 e grava v2 com o corte s3 tirado
  perform set_config('request.jwt.claims', json_build_object('sub', u_man, 'role','authenticated')::text, true);
  aid := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWx/view', 'title', 'g07_hook1.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', gid))->>'id')::uuid;
  j := edit_doc_save('numeiro', aid, null, doc, null, 'import');
  j := edit_doc_save('numeiro', aid, (j->'version'->>'id')::uuid, jsonb_set(doc, '{segments}', (doc->'segments') - 2), 'sem s3');
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  insert into t values ('abrir: escolha da IA (v1) e corte tirado para repor', true,
    (j->'ai_choice'->>'version_no')::int = 1 and j->'ai_choice'->>'hook' = 'Hook de teste'
    and jsonb_array_length(j->'cut_pool') = 1 and j->'cut_pool'->0->'seg'->>'id' = 's3' and j->'cut_pool'->0->>'after' = 's2');
  insert into t values ('abrir: hooks do guião como alternativas', true, jsonb_typeof(j->'guiao'->'hooks') = 'array');

  -- colaborador (só edit.guided)
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(jsonb_set(d, '{captions,words,1,w}', '"corpinho"'), '{hook,text}', '"Hook do cliente"'), 'palavras');
  insert into t values ('guiado: corrige uma palavra e o hook', true, (j->'version'->>'version_no')::int = 3
    and j->'version'->'doc'->'captions'->'words'->1->>'w' = 'corpinho' and j->'version'->'doc'->'hook'->>'text' = 'Hook do cliente');
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{segments}', (d->'segments') || (doc->'segments'->2)), 'repor s3');
  insert into t values ('guiado: repõe um corte de uma versão anterior', true, jsonb_array_length(j->'version'->'doc'->'segments') = 3 and jsonb_array_length(j->'cut_pool') = 0);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{segments}', (d->'segments') - 0));
  insert into t values ('guiado: tira um corte', true, jsonb_array_length(j->'version'->'doc'->'segments') = 2);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{audio,music}', jsonb_build_object('label', 'Música A', 'asset', mus, 'db', -18)));
  insert into t values ('guiado: põe música da biblioteca do cliente', true, j->'version'->'doc'->'audio'->'music'->>'asset' = mus::text);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{notes}', jsonb_build_array(jsonb_build_object('id', 'n1', 's', 26, 'text', 'Mais curto aqui', 'by', lbl, 'done', false))));
  insert into t values ('guiado: junta nota com o próprio nome', true, j->'version'->'doc'->'notes'->0->>'by' = lbl);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';

  -- negativos: cada mudança fora do modo guiado é recusada (42501 modo_guiado) e não cria versão
  for r in select * from (values
      ('aparar um corte', jsonb_set(d, '{segments,0,out}', '35.0')),
      ('criar um corte novo', jsonb_set(d, '{segments}', (d->'segments') || '[{"id":"zz","in":50,"out":52,"section":"body"}]'::jsonb)),
      ('reordenar cortes', jsonb_set(d, '{segments}', jsonb_build_array(d->'segments'->1, d->'segments'->0))),
      ('mudar o tempo de uma palavra', jsonb_set(d, '{captions,words,0,s}', '5.5')),
      ('tirar uma palavra', jsonb_set(d, '{captions,words}', (d->'captions'->'words') - 0)),
      ('palavra vazia', jsonb_set(d, '{captions,words,0,w}', '""')),
      ('juntar um visual', jsonb_set(d, '{overlays}', '[{"id":"o1","kind":"text","label":"x","s":26,"e":27}]')),
      ('mudar câmaras', jsonb_set(d, '{cameras,0,zoom}', '1.3')),
      ('mudar o estilo de layout', jsonb_set(d, '{style}', '"S13"')),
      ('mudar o aspeto', d || '{"look":{"captions":{"color":"#FF0000"}}}'),
      ('volume por trecho', jsonb_set(d, '{audio,gains}', '[{"s":26,"e":30,"db":-30}]')),
      ('música que não é áudio', jsonb_set(d, '{audio,music}', jsonb_build_object('label', 'x', 'asset', vid, 'db', -18))),
      ('música de outro cliente', jsonb_set(d, '{audio,music}', jsonb_build_object('label', 'x', 'asset', mus_b, 'db', -18))),
      ('música sem ativo', jsonb_set(d, '{audio,music}', '{"label":"x","asset":null,"db":-18}')),
      ('apagar uma nota', jsonb_set(d, '{notes}', '[]')),
      ('reescrever uma nota', jsonb_set(d, '{notes,0,text}', '"outra coisa"')),
      ('nota em nome de outra pessoa', jsonb_set(d, '{notes}', (d->'notes') || '[{"id":"n2","s":27,"text":"x","by":"Tomás","done":false}]'::jsonb)),
      ('nota nova já feita', jsonb_set(d, '{notes}', (d->'notes') || jsonb_build_array(jsonb_build_object('id', 'n3', 's', 27, 'text', 'x', 'by', lbl, 'done', true)))),
      ('mudar a caixa do hook', jsonb_set(d, '{hook,box}', '[0,0,10,10]'))
    ) x(name, nd) loop
    begin perform edit_doc_save('numeiro', aid, cur, r.nd); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
    insert into t values ('guiado recusa: ' || r.name, true, st = '42501' and msg like 'modo_guiado:%');
  end loop;
  begin perform edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{hook,text}', '"x"'), null, 'agent'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guiado não grava como agente (42501)', true, st = '42501');
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{notes,0,done}', 'true'));
  insert into t values ('guiado: marca nota como feita', true, (j->'version'->'doc'->'notes'->0->>'done')::boolean);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{audio,music}', 'null'));
  insert into t values ('guiado: tira a música', true, j->'version'->'doc'->'audio'->'music' = 'null'::jsonb);
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';

  -- revisor também é guiado
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{segments,0,in}', '25.5')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisor recusa aparar (42501)', true, st = '42501');
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(d, '{hook,text}', '"Hook do revisor"'));
  insert into t values ('revisor muda o hook', true, j->'version'->'doc'->'hook'->>'text' = 'Hook do revisor');
  cur := (j->'version'->>'id')::uuid; d := j->'version'->'doc';

  -- gestor (linha do tempo) continua a poder tudo
  perform set_config('request.jwt.claims', json_build_object('sub', u_man, 'role','authenticated')::text, true);
  j := edit_doc_save('numeiro', aid, cur, jsonb_set(jsonb_set(d, '{segments,0,out}', '35.0'), '{style}', '"S13"'));
  insert into t values ('linha do tempo: apara e muda o layout', true, (j->'version'->'doc'->'segments'->0->>'out')::numeric = 35.0);
  begin perform edit_doc_save('numeiro', aid, (j->'version'->>'id')::uuid, (j->'version'->'doc') || '{"look":{"captions":{"color":"red"}}}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aspeto com cor inválida recusado (22023)', true, st = '22023');
  begin perform edit_doc_save('numeiro', aid, (j->'version'->>'id')::uuid, (j->'version'->'doc') || '{"look":{"hook":{"y":100}}}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aspeto fora do retângulo seguro recusado (22023)', true, st = '22023');

  -- outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_doc_save('numeiro', aid, (j->'version'->>'id')::uuid, j->'version'->'doc'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não grava em A (42501)', true, st = '42501');
  begin perform edit_doc_save('ws_eg_b', aid, (j->'version'->>'id')::uuid, j->'version'->'doc'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B pelo seu cliente não encontra o ativo de A (P0002)', true, st = 'P0002');

  execute 'reset role';
  insert into t values ('recusas não criaram versões', true, (select count(*) from edit_versions v join edit_documents x on x.id = v.document_id where x.asset_id = aid) = 11);
  insert into t values ('gravação guiada auditada com o modo', true,
    (select count(*) from audit_events where action = 'edit.version_saved' and entity_id = aid::text and after->>'mode' = 'guiado') = 8);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
