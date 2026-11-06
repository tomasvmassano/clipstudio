-- supabase/tests/w10_pacote_estilo_alternativas.sql : pacote com o aspeto do estilo guardado (EDL-13) e alternativas da IA no
-- modo guiado (EDL-10). W10-07; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('a', 64); gid text := 'numeiro-2026-10-28-07'; g1 text; g2 text;
  f uuid; s uuid; mus uuid := gen_random_uuid(); a_st uuid; a1 uuid; a2 uuid; a3 uuid; v1 uuid; v2 uuid; v3 uuid; x3 uuid;
  j jsonb; k jsonb; st text; inp jsonb; ok int := 0; bad int := 0; res text := ''; r record;
  base jsonb := '{"schema":1,"fps":30,"style":"S15","size":[1080,1920],
    "segments":[{"id":"s01","in":10,"out":14,"section":"hook"},{"id":"s02","in":30,"out":40,"section":"body"},{"id":"s03","in":40.5,"out":50,"section":"body"}],
    "captions":{"words":[{"id":"w1","w":"Olá","s":10.5,"e":11},{"id":"w2","w":"corpo","s":31,"e":31.5},{"id":"w3","w":"segue","s":45,"e":45.5}]},
    "cameras":[{"s":10,"e":14,"cam":"front","zoom":1,"intro":true}],"hook":{"text":"Tema"},"overlays":[],
    "audio":{"music":null,"sfx":[],"gains":[]},"notes":[],"look":{"captions":{"color":"#FFFFFF","highlight":null}}}';
  alts jsonb := '{"hook_texts":["Outro hook no ecrã"],"sections":{
    "hook":{"replaces":["s01"],"options":[
      {"id":"alt_hook_1","segments":[{"id":"alt_hook_1_s01","in":60,"out":63,"section":"hook"}],"words":[{"id":"alt_hook_1_w001","w":"Novo","s":60.2,"e":60.6}],
       "text":"Novo","duration":3,"confidence":0.6,"note":"mais direto"},
      {"id":"alt_hook_2","segments":[{"id":"alt_hook_2_s01","in":70,"out":72.5,"section":"hook"}],"words":[{"id":"alt_hook_2_w001","w":"Outro","s":70.1,"e":70.5}],
       "text":"Outro","duration":2.5,"confidence":null,"note":""}]},
    "cta":{"replaces":["s03"],"options":[
      {"id":"alt_cta_1","segments":[{"id":"alt_cta_1_s01","in":80,"out":84,"section":"body"}],"words":[{"id":"alt_cta_1_w001","w":"Segue","s":80.3,"e":80.8}],
       "text":"Segue","duration":4,"confidence":0.5,"note":""}]}}}';
  sdoc jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pa_b', 'Pacote alternativas B', 'pab', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'pa-adm@test.invalid'),(u_con,'pa-con@test.invalid'),(u_view,'pa-view@test.invalid'),(u_b,'pa-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_pa_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_pa_b', 'all'), ('edit.studio', org, 'ws_pa_b', 'all');
  perform _edit_seed('numeiro', 'system', 'teste');
  insert into media_assets (id, workspace_id, kind, title) values (mus, 'numeiro', 'audio', 'Beat do Numeiro');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 1 limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  -- ─ 1. pacote com o aspeto do estilo guardado (EDL-13)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Sessao_FX30.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Sessao_FX3.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  -- estilo E01 guardado a partir de um vídeo com aspeto (highlight null = sem destaque) e música da biblioteca
  a_st := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW9/view', 'title', 'estilo.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', gid))->>'id')::uuid;
  sdoc := jsonb_set(base || '{"style":"S13","look":{"captions":{"color":"#FFFFFF","highlight":null,"size":64},"hook":{"color":"#FFD400","background":"#C8102E"}}}',
                   '{audio,music}', jsonb_build_object('label', 'Beat do Numeiro', 'asset', mus, 'db', -20));
  perform edit_doc_save('numeiro', a_st, null, sdoc, null, 'import');
  perform edit_style_from_doc('numeiro', a_st, null, null, 'Numeiro amarelo', null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-pa', array['ingest']);
    perform media_worker_finish('w-pa', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/proxy.mp4'));
  end loop;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g1], 'E01');
  j := edit_package_request('numeiro', f, s, array[g1], 'E01');
  insert into t values ('pacote com estilo guardado continua idempotente', true, k->>'id' = j->>'id');
  execute 'reset role';
  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('job leva o aspeto e a versão do estilo', true,
    inp->>'style' = 'E01' and (inp->>'style_version')::int = 1 and inp->'look'->>'layout' = 'S13'
    and inp->'look'->'hook'->>'background' = '#C8102E' and (inp->'look'->'captions'->>'size')::int = 64);
  insert into t values ('null do aspeto chega ao worker (highlight null = sem destaque)', true,
    inp->'look'->'captions' ? 'highlight' and jsonb_typeof(inp->'look'->'captions'->'highlight') = 'null');
  insert into t values ('música do estilo no job', true, inp->'look'->'music'->>'asset' = mus::text and (inp->'look'->'music'->>'db')::int = -20);
  insert into t values ('chave de idempotência leva a versão do estilo', true,
    (select idempotency_key like 'package:%:E01:v1' from media_jobs where id = (k->>'id')::uuid));
  insert into t values ('auditado com a versão do estilo', true,
    exists (select 1 from audit_events where action = 'edit.package_requested' and entity_id = k->>'id' and (after->>'style_version')::int = 1));

  -- música tirada da biblioteca: o aspeto continua, a música vai a null
  update media_assets set lifecycle = 'no_lixo', trashed_at = now() where id = mus;
  execute 'set local role authenticated';
  k := edit_package_request('numeiro', f, s, array[g2], 'E01');
  execute 'reset role';
  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('música que já não está na biblioteca fica de fora (aspeto fica)', true,
    inp ? 'look' and jsonb_typeof(inp->'look'->'music') = 'null' and inp->'look'->'hook'->>'color' = '#FFD400');
  insert into t values ('versão guardada do estilo mantém a música (não é alterada)', true,
    (select look->'music'->>'asset' from edit_style_versions where workspace_id = 'numeiro' and key = 'E01' and version = 1) = mus::text);

  -- estilo gravado de novo (v2): o mesmo pedido cria um job novo com a v2
  execute 'set local role authenticated';
  perform edit_style_save('numeiro', 'E01', '{"notes":"retocado"}', 1);
  j := edit_package_request('numeiro', f, s, array[g1], 'E01');
  execute 'reset role';
  insert into t values ('estilo v2: job novo com a versão nova na chave e no input', true,
    (select idempotency_key like 'package:%:E01:v2' and (input->>'style_version')::int = 2 and input ? 'look' from media_jobs where id = (j->>'id')::uuid));

  -- estilo arquivado e estilo do catálogo sem aspeto: input igual ao de antes
  execute 'set local role authenticated';
  perform edit_style_set_status('numeiro', 'E01', 'arquivado');
  j := edit_package_request('numeiro', f, s, array[g1, g2], 'E01');
  k := edit_package_request('numeiro', f, s, array[g1, g2], 'S15');
  execute 'reset role';
  insert into t values ('estilo arquivado ignorado (sem look, chave sem versão)', true,
    (select not (input ? 'look') and not (input ? 'style_version') and idempotency_key like 'package:%:E01' from media_jobs where id = (j->>'id')::uuid));
  insert into t values ('estilo do catálogo sem aspeto: sem look', true,
    (select not (input ? 'look') and idempotency_key like 'package:%:S15' from media_jobs where id = (k->>'id')::uuid));

  -- ─ 2. alternativas da IA no modo guiado (EDL-10)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  a1 := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW1/view', 'title', 'g07_hook1.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', gid))->>'id')::uuid;
  a2 := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW2/view', 'title', 'g07_hook2.mp4',
          'tags', jsonb_build_array('hook_2'), 'content_id', gid))->>'id')::uuid;
  a3 := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvW3/view', 'title', 'g07_hook3.mp4',
          'tags', jsonb_build_array('hook_3'), 'content_id', gid))->>'id')::uuid;
  j := edit_doc_save('numeiro', a1, null, base || jsonb_build_object('ai', jsonb_build_object('alternatives', alts)), null, 'ai');
  v1 := (j->'version'->>'id')::uuid;
  perform edit_doc_save('numeiro', a2, null, base, null, 'ai');
  j := edit_doc_save('numeiro', a3, null, base || jsonb_build_object('ai', jsonb_build_object('alternatives', alts)), null, 'ai');
  -- quem tem a linha do tempo tira o s03 do vídeo 3 (a CTA deixa de ter onde entrar)
  j := edit_doc_save('numeiro', a3, (j->'version'->>'id')::uuid,
                     jsonb_set(j->'version'->'doc', '{segments}', (j->'version'->'doc'->'segments') - 2));
  x3 := (j->'version'->>'id')::uuid;

  -- colaborador: só edit.guided
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := edit_doc_get('numeiro', a1);
  insert into t values ('edit_doc_get devolve as alternativas da IA', true,
    j->'ai_alternatives'->'hook_texts'->>0 = 'Outro hook no ecrã' and jsonb_array_length(j->'ai_alternatives'->'sections'->'hook'->'options') = 2
    and j->'can'->>'timeline' = 'false');
  insert into t values ('documento sem alternativas: ai_alternatives null', true, jsonb_typeof(edit_doc_get('numeiro', a2)->'ai_alternatives') = 'null');
  j := edit_alternative_apply('numeiro', a1, v1, 'hook', 'alt_hook_1');
  v2 := (j->'version'->>'id')::uuid;
  insert into t values ('modo guiado usa a alternativa: versão nova montada no servidor', true,
    (j->'version'->>'version_no')::int = 2 and j->'version'->>'source' = 'user' and j->'version'->>'note' like 'alternativa da IA no hook%'
    and (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'segments') with ordinality y(x, i)) = array['alt_hook_1_s01', 's02', 's03']);
  insert into t values ('legendas: sai a palavra do corte substituído, entra a da alternativa', true,
    (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'captions'->'words') with ordinality y(x, i))
      = array['w2', 'w3', 'alt_hook_1_w001']);
  insert into t values ('o resto do documento fica igual', true,
    (j->'version'->'doc') - array['segments', 'captions'] = (base || jsonb_build_object('ai', jsonb_build_object('alternatives', alts))) - array['segments', 'captions']);
  j := edit_alternative_apply('numeiro', a1, v1, 'hook', 'alt_hook_1');
  insert into t values ('repetir a mesma alternativa não cria versão nem dá conflito', true,
    (j->'version'->>'id')::uuid = v2 and jsonb_array_length(j->'versions') = 2);
  begin perform edit_alternative_apply('numeiro', a1, v1, 'hook', 'alt_hook_2'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outra alternativa sobre a versão antiga: conflito (40001)', true, st = '40001');
  j := edit_alternative_apply('numeiro', a1, v2, 'hook', 'alt_hook_2');
  v3 := (j->'version'->>'id')::uuid;
  insert into t values ('trocar de alternativa no hook tira a anterior', true,
    (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'segments') with ordinality y(x, i)) = array['alt_hook_2_s01', 's02', 's03']
    and not (j->'version'->'doc'->'captions'->'words' @> '[{"id":"alt_hook_1_w001"}]'));
  j := edit_alternative_apply('numeiro', a1, v3, 'cta', 'alt_cta_1');
  insert into t values ('CTA substitui só o corte da CTA', true,
    (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'segments') with ordinality y(x, i)) = array['alt_hook_2_s01', 's02', 'alt_cta_1_s01']
    and (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'captions'->'words') with ordinality y(x, i)) = array['w2', 'alt_hook_2_w001', 'alt_cta_1_w001']);
  v3 := (j->'version'->>'id')::uuid;
  insert into t values ('cortes substituídos ficam para repor no modo guiado', true,
    j->'cut_pool' @> '[{"seg":{"id":"s01"}}]' and j->'cut_pool' @> '[{"seg":{"id":"s03"}}]');
  j := edit_doc_save('numeiro', a1, v3, jsonb_set(j->'version'->'doc', '{hook,text}', '"Hook do cliente"'));
  insert into t values ('depois da alternativa o modo guiado continua a gravar', true, (j->'version'->>'version_no')::int = 5);
  v3 := (j->'version'->>'id')::uuid;

  begin perform edit_alternative_apply('numeiro', a1, v3, 'hook', 'alt_hook_9'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('alternativa inexistente (P0002)', true, st = 'P0002');
  begin perform edit_alternative_apply('numeiro', a1, v3, 'cta', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('opção de outra secção (P0002)', true, st = 'P0002');
  begin perform edit_alternative_apply('numeiro', a1, v3, 'visual', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('secção inválida (22023)', true, st = '22023');
  begin perform edit_alternative_apply('numeiro', a2, (edit_doc_get('numeiro', a2)->'version'->>'id')::uuid, 'hook', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('opção de outro documento não serve neste (P0002)', true, st = 'P0002');
  begin perform edit_alternative_apply('numeiro', a3, x3, 'cta', 'alt_cta_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('CTA sem o corte que substitui: recusa clara (22023)', true, st = '22023');
  j := edit_alternative_apply('numeiro', a3, x3, 'hook', 'alt_hook_1');
  insert into t values ('mesma opção noutro vídeo usa as alternativas desse vídeo', true,
    (select array_agg(x->>'id' order by i) from jsonb_array_elements(j->'version'->'doc'->'segments') with ordinality y(x, i)) = array['alt_hook_1_s01', 's02']);

  -- leitor, outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform edit_alternative_apply('numeiro', a1, v3, 'hook', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não usa alternativas (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_alternative_apply('numeiro', a1, v3, 'hook', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não usa alternativas em A (42501)', true, st = '42501');
  begin perform edit_alternative_apply('ws_pa_b', a1, v3, 'hook', 'alt_hook_1'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B com o vídeo de A pelo seu cliente (P0002)', true, st = 'P0002');
  begin perform edit_doc_get('numeiro', a1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê as alternativas de A (42501)', true, st = '42501');
  begin perform edit_package_request('numeiro', f, s, array[g1], 'E01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não pede o pacote de A (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1], 'E01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('modo guiado não pede pacote (42501)', true, st = '42501');
  execute 'reset role';

  begin
    execute 'set local role anon';
    perform edit_alternative_apply('numeiro', a1, v3, 'hook', 'alt_hook_1'); st := 'none';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('anon sem EXECUTE (42501)', true, st = '42501');
  insert into t values ('versão 1 da IA intacta', true,
    (select doc from edit_versions where id = v1) = base || jsonb_build_object('ai', jsonb_build_object('alternatives', alts)));
  insert into t values ('auditado: cada alternativa usada', true,
    (select count(*) from audit_events where action = 'edit.alternative_applied' and entity_id = a1::text and actor_user_id = u_con) = 3
    and exists (select 1 from audit_events where action = 'edit.alternative_applied' and entity_id = a1::text and after->>'option' = 'alt_cta_1'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
