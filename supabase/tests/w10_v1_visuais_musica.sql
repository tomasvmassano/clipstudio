-- supabase/tests/w10_v1_visuais_musica.sql : a versão 1 do pacote com visuais e música da IA (EDL-07, ADR-0068). W10-18; rollback no fim.
-- O servidor escolhe o que a IA pode usar: só ativos deste cliente, prontos no R2 e com a etiqueta ia-*; a lista de frases em vigor.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('a', 64); g1 text; f uuid; s uuid; img uuid; att uuid; mus uuid; aid uuid;
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  j jsonb; k jsonb; k2 jsonb; st text; inp jsonb; fill jsonb; ok int := 0; bad int := 0; res text := ''; r record; job uuid; a_new uuid;
  vdoc jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_vm_b', 'Visuais B', 'vmb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'vm-adm@test.invalid'),(u_con,'vm-con@test.invalid'),(u_b,'vm-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('ws_vm_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_vm_b', 'all'), ('edit.studio', org, 'ws_vm_b', 'all'), ('media.r2', org, 'ws_vm_b', 'all');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  -- biblioteca: (cliente, tipo, título, etiquetas, mime, sítio, estado, no lixo)
  for r in select * from (values
      ('numeiro', 'imagem', 'Ferrari vermelho',   array['ia-imagem','dubai'], 'image/jpeg', 'r2', 'pronta', false),   -- entra
      ('numeiro', 'imagem', 'Sem etiqueta',       array['dubai'],             'image/jpeg', 'r2', 'pronta', false),   -- sem ia-imagem
      ('numeiro', 'imagem', 'No Supabase',        array['ia-imagem'],         'image/png',  'supabase', 'pronta', false),
      ('numeiro', 'imagem', 'Por carregar',       array['ia-imagem'],         'image/png',  'r2', 'pendente', false),
      ('numeiro', 'imagem', 'No lixo',            array['ia-imagem'],         'image/png',  'r2', 'pronta', true),
      ('numeiro', 'imagem', 'Imagem como música', array['ia-musica'],         'image/png',  'r2', 'pronta', false),   -- tipo errado
      ('numeiro', 'video',  'Loop areia',         array['ia-atencao'],        'video/mp4',  'r2', 'pronta', false),   -- entra
      ('numeiro', 'audio',  'Batida',             array['ia-musica'],         'audio/mpeg', 'r2', 'pronta', false),   -- entra
      ('ws_vm_b', 'imagem', 'Imagem de B',        array['ia-imagem'],         'image/jpeg', 'r2', 'pronta', false),
      ('ws_vm_b', 'audio',  'Música de B',        array['ia-musica'],         'audio/mpeg', 'r2', 'pronta', false)) v(ws, kind, title, tags, mime, prov, state, trash)
  loop
    aid := gen_random_uuid();
    insert into media_assets (id, workspace_id, kind, title, tags, lifecycle, trashed_at)
    values (aid, r.ws, r.kind, r.title, r.tags, case when r.trash then 'no_lixo' else 'ativo' end, case when r.trash then now() end);
    insert into media_versions (id, workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256, storage_provider)
    values (aid, r.ws, aid, 1, 'upload', 'pendente', case when r.prov = 'r2' then 'r2' else 'media' end, r.ws || '/' || aid || '/1/f', r.title, 100, r.mime, sha, r.prov);
    if r.state <> 'pendente' then update media_versions set state = r.state, completed_at = now() where id = aid; end if;
    if r.state = 'pronta' then update media_assets set current_version_id = aid where id = aid; end if;
    if r.title = 'Ferrari vermelho' then img := aid; elsif r.title = 'Loop areia' then att := aid; elsif r.title = 'Batida' then mus := aid; end if;
  end loop;
  -- link externo com etiqueta: fica de fora
  aid := gen_random_uuid();
  insert into media_assets (id, workspace_id, kind, title, tags) values (aid, 'numeiro', 'link_externo', 'Link', array['ia-imagem']);
  insert into media_versions (id, workspace_id, asset_id, version_no, source, state, external_url) values (aid, 'numeiro', aid, 1, 'link', 'pronta', 'https://example.com/a.jpg');
  update media_assets set current_version_id = aid where id = aid;
  -- frases-persona em vigor (v2), uma com consentimento de terceiro: o motor só recebe o nome
  insert into persona_lists (workspace_id, version, phrases, created_label) values
    ('numeiro', 1, '[{"id":"a","text":"Frase antiga"}]', 'teste'),
    ('numeiro', 2, '[{"id":"a","text":"O homem mais rico de Portugal"},{"id":"b","text":"O namorado da Ana","involves":{"name":"Ana","consent_by":"Ana","consent_at":"2026-11-01"}}]', 'teste');

  -- gravações da sessão no R2
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'VM_FX30.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'VM_FX3.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-vm', array['ingest']);
    perform media_worker_finish('w-vm', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/proxy.mp4'));
  end loop;
  execute 'reset role';

  -- ─ 1. flag desligada (default 'owner', admin do cliente não é dono da agência): input e chave como hoje
  insert into t values ('flag registada com default owner', true, (select default_stage = 'owner' and scope = 'ws' from feature_flag_defs where key = 'edit.ai_visuals'));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g1], 'S15');
  execute 'reset role';
  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('flag desligada: sem fill no job', true, not inp ? 'fill');
  insert into t values ('flag desligada: chave igual à de hoje', true, (select idempotency_key not like '%:ia1' and idempotency_key like '%:S15' from media_jobs where id = (k->>'id')::uuid));

  -- ─ 2. flag ligada para o cliente: fill montado no servidor
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('edit.ai_visuals', org, 'numeiro', 'all');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k2 := edit_package_request('numeiro', f, s, array[g1], 'S15');
  j := edit_package_request('numeiro', f, s, array[g1], 'S15');
  execute 'reset role';
  insert into t values ('flag ligada: job novo (chave com :ia1)', true, k2->>'id' <> k->>'id'
    and (select idempotency_key like '%:S15:ia1' from media_jobs where id = (k2->>'id')::uuid));
  insert into t values ('flag ligada: idempotente', true, j->>'id' = k2->>'id');
  select input->'fill' into fill from media_jobs where id = (k2->>'id')::uuid;
  insert into t values ('receitas do preset do numeiro (master, imagem + frase, atenção + frase)', true,
    fill->'recipes' = '["master","imagem_frase","atencao_frase"]' and (fill->>'preset_version')::int = (select max(version) from edit_presets where workspace_id = 'numeiro'));
  insert into t values ('imagens: só a etiquetada, pronta, no R2, ativa, deste cliente', true,
    jsonb_array_length(fill->'library'->'images') = 1 and fill->'library'->'images'->0->>'id' = img::text
    and fill->'library'->'images'->0->>'mime' = 'image/jpeg' and fill->'library'->'images'->0->'tags' ? 'dubai');
  insert into t values ('vídeo de atenção: só vídeo com ia-atencao', true,
    jsonb_array_length(fill->'library'->'attention') = 1 and fill->'library'->'attention'->0->>'id' = att::text);
  insert into t values ('música: só áudio com ia-musica (imagem com a etiqueta não entra)', true,
    jsonb_array_length(fill->'library'->'music') = 1 and fill->'library'->'music'->0->>'id' = mus::text);
  insert into t values ('nada de B no job de A', true,
    not exists (select 1 from jsonb_array_elements(fill->'library'->'images' || fill->'library'->'music' || fill->'library'->'attention') e
                 join media_assets a on a.id::text = e->>'id' where a.workspace_id <> 'numeiro'));
  insert into t values ('frases da lista em vigor (v2), só texto e nome', true,
    (fill->'persona'->>'version')::int = 2 and jsonb_array_length(fill->'persona'->'phrases') = 2
    and fill->'persona'->'phrases'->1 = '{"text":"O namorado da Ana","involves":"Ana"}'
    and fill->'persona'->'phrases'->0 = '{"text":"O homem mais rico de Portugal"}');
  insert into t values ('auditado com as contagens e a versão das frases', true, exists (select 1 from audit_events
    where action = 'edit.package_requested' and entity_id = k2->>'id' and after->'fill'->>'images' = '1' and after->'fill'->>'persona_version' = '2'));
  insert into t values ('_edit_package_fill fechada a authenticated', true, not has_function_privilege('authenticated', 'public._edit_package_fill(text)', 'execute'));

  -- ─ 3. o worker grava a versão 1 com visuais (caixa por visual) e doc.ai.visuals: _edit_doc_problem aceita
  vdoc := '{"schema":1,"fps":30,"style":"S15","size":[1080,1920],
    "segments":[{"id":"s01","in":10,"out":14,"section":"hook"},{"id":"s02","in":30,"out":40,"section":"body"}],
    "captions":{"words":[{"id":"w1","w":"Olá","s":10.5,"e":11}]},"cameras":[],"hook":{"text":"Tema"},
    "overlays":[{"id":"ai_img","kind":"graphic","label":"Ferrari vermelho","asset":"IMG","s":30,"e":33,"box":[108,500,864,560]},
                {"id":"ai_frase","kind":"text","label":"O homem mais rico de Portugal","asset":null,"s":30,"e":33,"box":[120,230,840,220]}],
    "audio":{"music":{"label":"Batida","asset":"MUS","db":-18},"sfx":[],"gains":[]},"notes":[],
    "ai":{"visuals":{"version":1,"recipe":"imagem_frase","picks":[{"slot":"imagem","overlays":["ai_img"],"asset":"IMG","label":"Ferrari vermelho","why":"x"}],"empty":[],"persona_version":2,"phrase_options":[]}}}';
  vdoc := replace(replace(vdoc::text, 'IMG', img::text), 'MUS', mus::text)::jsonb;
  execute 'set local role engine_worker';
  j := media_worker_claim('w-vm', array['package']);
  job := (j->'job'->>'id')::uuid;
  j := media_worker_package_save('w-vm', job, g1, 2, vdoc);
  a_new := (j->>'asset_id')::uuid;
  execute 'reset role';
  insert into t values ('worker grava a v1 com visuais e caixas', true,
    (select v.doc->'overlays'->0->'box' = '[108,500,864,560]' and v.doc->'ai'->'visuals'->>'recipe' = 'imagem_frase' and v.source = 'ai'
       from edit_documents d join edit_versions v on v.id = d.current_version_id where d.asset_id = a_new));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := edit_doc_get('numeiro', a_new);
  insert into t values ('editor lê o porquê da IA no documento', true, j->'version'->'doc'->'ai'->'visuals'->'picks'->0->>'why' = 'x');
  -- quem edita tira um visual e troca a posição de outro: versão nova normal
  vdoc := jsonb_set(j->'version'->'doc', '{overlays}', jsonb_build_array(jsonb_set(j->'version'->'doc'->'overlays'->1, '{box}', '[120,1300,840,200]')));
  k := edit_doc_save('numeiro', a_new, (j->'version'->>'id')::uuid, vdoc, 'tirei a imagem', 'user');
  execute 'reset role';
  insert into t values ('tirar e mudar a posição grava versão nova; v1 intacta', true,
    jsonb_array_length(k->'version'->'doc'->'overlays') = 1 and k->'version'->'doc'->'overlays'->0->'box' = '[120,1300,840,200]'
    and (select jsonb_array_length(doc->'overlays') from edit_versions where id = (j->'version'->>'id')::uuid) = 2);

  -- ─ 3b. com preset do cliente: as receitas seguem as saídas do preset (só imagem, sem vídeo de atenção)
  insert into edit_presets (workspace_id, version, outputs, actor_kind, actor_label) values ('numeiro', (select max(version) + 1 from edit_presets where workspace_id = 'numeiro'),
    '[{"kind":"master","per_hook":true,"captions":"burned"},{"kind":"split_image_persona","captions":"burned"}]', 'system', 'teste');
  insert into t values ('receitas do preset do cliente', true,
    public._edit_package_fill('numeiro')->'recipes' = '["master","imagem_frase"]');
  insert into t values ('cliente sem preset: ponto de partida do EDL-01', true, (select count(*) = 0 from edit_presets where workspace_id = 'ws_vm_b')
    and public._edit_package_fill('ws_vm_b')->'recipes' = '["master","imagem_frase","atencao_frase"]');
  -- ─ 4. negativos
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1], 'S15'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não pede o pacote de A (42501)', true, st = '42501');
  begin perform edit_doc_get('numeiro', a_new); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê a v1 de A', true, st <> 'none');
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1], 'S15'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('modo guiado não pede pacote (42501)', true, st = '42501');
  execute 'reset role';
  begin
    execute 'set local role anon';
    perform edit_package_request('numeiro', f, s, array[g1], 'S15', tok); st := 'none';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('código de equipa não pede pacote', true, st <> 'none');
  begin
    execute 'set local role anon';
    perform public._edit_package_fill('numeiro'); st := 'none';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('anon sem EXECUTE em _edit_package_fill (42501)', true, st = '42501');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
