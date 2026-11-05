-- supabase/tests/w5_media_r2.sql : vídeo no R2, verificação e proxy pelo worker, exportar (W5-07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha1 text := repeat('a', 64); sha2 text := repeat('b', 64); sha3 text := repeat('c', 64);
  j jsonb; k jsonb; c jsonb; st text; n int; vid uuid; vid2 uuid; vid3 uuid; aid uuid; fid uuid; job uuid; d uuid; ev uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_r2_b', 'R2 B', 'r2b', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'r2-own@test.invalid'),(u_rev,'r2-rev@test.invalid'),(u_b,'r2-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'), ('ws_r2_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('media.library', org, 'ws_r2_b', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('edit.studio', org, 'ws_r2_b', 'all'), ('notifications.prefs', org, 'numeiro', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  -- sem a flag: Supabase como antes
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'a.mp4', 'size', 1000, 'mime', 'video/mp4', 'sha256', sha1));
  insert into t values ('sem flag: bucket media, Supabase', true, j->>'bucket' = 'media' and j->>'storage' = 'supabase');
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'big.mp4', 'size', 10737418240, 'mime', 'video/mp4', 'sha256', sha2));
        st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem flag: 10 GB recusado', true, st = '22023');
  execute 'reset role';

  -- com a flag (cliente inteiro)
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('media.r2', org, 'numeiro', 'all');
  update media_policies set quota_bytes = null where workspace_id = 'numeiro';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'ClippingTest_FX30.mp4', 'size', 10737418240, 'mime', 'video/mp4', 'sha256', sha2));
  vid := (j->>'version_id')::uuid; aid := (j->>'asset_id')::uuid;
  insert into t values ('com flag: 10 GB vai para o R2', true, j->>'bucket' = 'r2' and j->>'storage' = 'r2');
  k := media_upload_target('numeiro', vid);
  insert into t values ('alvo R2: objeto desconhecido para a base', true, k->>'storage' = 'r2' and k->'object_exists' = 'null'::jsonb);
  c := media_upload_complete('numeiro', vid, null);
  insert into t values ('concluir R2 fica a verificar com job', true, c->>'state' = 'pendente' and (c->>'verifying')::boolean and c->'job'->>'kind' = 'ingest');
  c := media_upload_complete('numeiro', vid, null);
  execute 'reset role';
  insert into t values ('concluir repetido: um só job', true, (select count(*) from media_jobs where version_id = vid) = 1);
  insert into t values ('não fica pronta sem o worker', true, (select state from media_versions where id = vid) = 'pendente');
  execute 'set local role authenticated';
  begin perform media_upload_target('numeiro', vid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('depois de enviado já não dá novo alvo', true, st = '22023');
  begin perform media_worker_claim('falso-worker', array['ingest']); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não chama o worker (42501)', true, st = '42501');
  begin perform media_worker_finish('falso-worker', (select id from media_jobs limit 1), true, '{}'::jsonb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não fecha jobs (42501)', true, st = '42501');
  execute 'reset role';
  begin
    execute 'set local role authenticated';
    perform 1 from media_jobs; st := 'ok';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('tabela de jobs fechada à API', true, st = '42501');

  -- segundo upload (para o checksum errado)
  execute 'set local role authenticated';
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'ClippingTest_FX3.mp4', 'size', 2000, 'mime', 'video/mp4', 'sha256', sha3));
  vid2 := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', vid2, null);
  execute 'reset role';

  -- worker: primeiro o FX30 (ordem de criação), resultado certo; depois o FX3 com checksum errado
  execute 'set local role engine_worker';
  j := media_worker_claim('w-teste-1', array['ingest']);
  job := (j->'job'->>'id')::uuid;
  insert into t values ('worker apanha o job de verificação com a chave', true, j->'job'->>'version_id' = vid::text and j->'job'->'input'->>'key' like 'numeiro/%');
  k := media_worker_heartbeat('w-teste-1', job, '{"pct": 50}');
  insert into t values ('heartbeat mantém a lease', true, not (k->>'lost')::boolean);
  k := media_worker_heartbeat('outro-worker', job, null);
  insert into t values ('outro worker não mexe no job', true, (k->>'lost')::boolean);
  k := media_worker_finish('w-teste-1', job, true, jsonb_build_object('size_bytes', 10737418240, 'sha256', sha2, 'proxy_key', 'numeiro/' || aid || '/1/proxy.mp4',
        'info', jsonb_build_object('duration', 7200, 'width', 3840, 'height', 2160)));
  insert into t values ('verificado: pronta', true, k->>'state' = 'pronta');
  j := media_worker_claim('w-teste-1', array['ingest']);
  k := media_worker_finish('w-teste-1', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', 2000, 'sha256', sha1, 'proxy_key', 'x'));
  insert into t values ('checksum errado: falhou', true, k->>'state' = 'falhou');
  j := media_worker_claim('w-teste-1', array['ingest']);
  insert into t values ('fila vazia devolve null', true, j is null);
  execute 'reset role';
  insert into t values ('pronta com checksum conferido, proxy e versão atual', true,
    (select state = 'pronta' and checksum_verified and proxy_state = 'pronta' and proxy_path like '%proxy.mp4' and (media_info->>'duration')::int = 7200
       from media_versions where id = vid) and (select current_version_id from media_assets where id = aid) = vid);
  insert into t values ('falhou guarda o motivo', true, (select state = 'falhou' and failed_reason like 'checksum_diferente%' from media_versions where id = vid2));
  insert into t values ('auditado e evento de domínio', true,
    exists (select 1 from audit_events where action = 'media.version_ready' and entity_id = aid::text and actor_kind = 'system')
    and exists (select 1 from domain_events where type = 'asset.uploaded' and entity_id = aid::text));

  -- erro com repetição e espera crescente; desistência marca a versão
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'ClippingTest_FX3.mp4', 'size', 3000, 'mime', 'video/mp4', 'sha256', sha1));
  vid3 := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', vid3, null);
  execute 'reset role';
  execute 'set local role engine_worker';
  j := media_worker_claim('w-teste-1', array['ingest']); job := (j->'job'->>'id')::uuid;
  perform media_worker_finish('w-teste-1', job, false, null, 'rede caiu', true);
  execute 'reset role';
  insert into t values ('erro repetível volta à fila com espera', true,
    (select status = 'queued' and next_attempt_at > now() + interval '20 seconds' and last_error = 'rede caiu' from media_jobs where id = job));
  update media_jobs set next_attempt_at = now() where id = job;
  execute 'set local role engine_worker';
  j := media_worker_claim('w-teste-1', array['ingest']);
  k := media_worker_finish('w-teste-1', job, true, jsonb_build_object('size_bytes', 3000, 'sha256', sha1, 'proxy_key', 'numeiro/fx3/proxy.mp4'));
  execute 'reset role';
  insert into t values ('segunda tentativa conclui', true, k->>'state' = 'pronta' and (select attempts from media_jobs where id = job) = 2);

  -- proxy: com media.read sim; outro cliente não
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  k := media_proxy_access('numeiro', vid);
  insert into t values ('revisor lê o proxy', true, k->>'bucket' = 'r2' and k->>'path' like '%proxy.mp4');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_proxy_access('numeiro', vid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê proxy do numeiro (42501)', true, st = '42501');
  begin perform media_proxy_access('ws_r2_b', vid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versão de outro cliente pelo próprio (P0002)', true, st = 'P0002');
  execute 'reset role';

  -- exportar
  insert into media_assets (workspace_id, kind, title, tags, status, created_label) values ('numeiro', 'video', 'g01_hook1_S15', '{}', 'em_trabalho', 't') returning id into fid;
  insert into edit_documents (workspace_id, asset_id) values ('numeiro', fid) returning id into d;
  insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
  values ('numeiro', d, 1, jsonb_build_object('schema', 1, 'segments', jsonb_build_array(jsonb_build_object('id', 's1', 'in', 0, 'out', 5)),
          'source', jsonb_build_object('windows', '[[10, 20]]'::jsonb, 'cams', jsonb_build_object('front', 'FX30/ClippingTest_FX30.mp4', 'side', 'FX3/Outra.mp4'), 'audio', 'side')),
          'import', 't') returning id into ev;
  update edit_documents set current_version_id = ev where id = d;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_preview_sources('numeiro', fid);
  insert into t values ('fontes: front com proxy, side em falta', true, k->'cams'->'front'->>'state' = 'pronta' and k->'cams'->'side'->>'state' = 'em_falta');
  begin perform edit_export_request('numeiro', fid); st := 'ok'; exception when others then st := sqlstate || ' ' || sqlerrm; end;
  insert into t values ('exportar sem as gravações todas (22023)', true, st like '22023 camaras_em_falta%');
  execute 'reset role';
  insert into edit_versions (workspace_id, document_id, version_no, base_version_id, doc, source, created_label)
  select workspace_id, document_id, 2, id, jsonb_set(doc, '{source,cams,side}', '"FX3/ClippingTest_FX3.mp4"'), 'user', 't' from edit_versions where id = ev
  returning id into ev;
  update edit_documents set current_version_id = ev where id = d;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform edit_export_request('numeiro', fid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não exporta (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_export_request('numeiro', fid);
  c := edit_export_request('numeiro', fid);
  insert into t values ('pedir duas vezes dá o mesmo job', true, k->>'id' = c->>'id' and k->>'status' = 'queued');
  insert into t values ('lista de exports', true, jsonb_array_length(edit_export_list('numeiro', fid)) = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_export_list('numeiro', fid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não vê exports (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('job guarda as câmaras resolvidas e a chave de saída', true,
    (select input->'cams'->'front'->>'key' like 'numeiro/%' and input->'cams'->'side'->>'version_id' = vid3::text
       and input->>'out_key' = 'numeiro/' || fid || '/exports/' || ev || '.mp4' from media_jobs where id = (k->>'id')::uuid));

  execute 'set local role engine_worker';
  j := media_worker_claim('w-teste-1', array['export']);
  insert into t values ('worker apanha o export', true, j->'job'->>'kind' = 'export');
  k := media_worker_finish('w-teste-1', (j->'job'->>'id')::uuid, true, jsonb_build_object('key', 'outra/chave.mp4', 'size_bytes', 5, 'sha256', sha1));
  execute 'reset role';
  insert into t values ('chave de saída diferente é recusada', true, k->>'state' = 'falhou');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_export_request('numeiro', fid);
  insert into t values ('depois de falhar pode pedir de novo', true, k->>'status' = 'queued');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);   -- o worker não tem sessão de utilizador
  execute 'set local role engine_worker';
  j := media_worker_claim('w-teste-1', array['export']);
  k := media_worker_finish('w-teste-1', (j->'job'->>'id')::uuid, true, jsonb_build_object('key', j->'job'->'input'->>'out_key', 'size_bytes', 123456, 'sha256', sha3,
        'proxy_key', 'numeiro/x/proxy.mp4', 'info', '{"duration": 58.3}'::jsonb));
  execute 'reset role';
  insert into t values ('export cria versão nova pronta e atual', true,
    k->>'state' = 'pronta' and (select state = 'pronta' and storage_provider = 'r2' and checksum_verified and version_no = 1 from media_versions where id = (k->>'version_id')::uuid)
    and (select current_version_id from media_assets where id = fid) = (k->>'version_id')::uuid);
  insert into t values ('export avisa quem pediu', true, exists (select 1 from notifications where user_id = u_own and title like 'Exportação pronta:%'));

  -- outro cliente sem flag continua no Supabase
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_r2_b', null, '{}', jsonb_build_object('name', 'b.mp4', 'size', 1000, 'mime', 'video/mp4', 'sha256', sha1));
  insert into t values ('flag por cliente: B continua no Supabase', true, j->>'storage' = 'supabase');
  begin perform edit_export_request('ws_r2_b', fid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B sem R2 não exporta (55000)', true, st = '55000');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
