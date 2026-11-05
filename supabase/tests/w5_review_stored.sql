-- supabase/tests/w5_review_stored.sql : revisão dos vídeos exportados e exportar o pacote (W5-12; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('a', 64); a1 uuid; ej jsonb; d jsonb; qc jsonb; tz text; j jsonb; k jsonb; st text; f uuid; s uuid; job uuid; g1 text; g2 text; doc jsonb;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_rs_b', 'Revisão B', 'rsb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'rs-own@test.invalid'),(u_rev,'rs-rev@test.invalid'),(u_b,'rs-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'), ('ws_rs_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_rs_b', 'all'), ('edit.studio', org, 'ws_rs_b', 'all'), ('notifications.prefs', org, 'numeiro', 'all');
  select id into g1 from guioes where client_id = 'numeiro' order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' order by date, n offset 1 limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  -- duas gravações prontas no R2 (o worker já as verificou)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Sessao_FX30.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Sessao_FX3.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  begin perform edit_package_request('numeiro', f, s, array[g1]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravações ainda a verificar: não encontradas (P0002)', true, st = 'P0002');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-pk', array['ingest']);
    perform media_worker_finish('w-pk', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/proxy.mp4'));
  end loop;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não pede pacote (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não pede (42501)', true, st = '42501');
  begin perform edit_package_request('ws_rs_b', f, s, array[g1]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B sem R2 (55000)', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, f, array[g1]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('a mesma gravação duas vezes (22023)', true, st = '22023');
  begin perform edit_package_request('numeiro', f, s, array['outro-cliente-x']); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('guião de outro cliente (P0002)', true, st = 'P0002');
  k := edit_package_request('numeiro', f, s, array[g1, g2]);
  j := edit_package_request('numeiro', f, s, array[g1, g2]);
  insert into t values ('pedido idempotente', true, k->>'id' = j->>'id' and k->>'kind' = 'package' and k->>'status' = 'queued');
  job := (k->>'id')::uuid;
  execute 'reset role';
  insert into t values ('job leva as gravações e os textos dos guiões', true,
    (select input->'front'->>'name' = 'Sessao_FX30.mp4' and input->'side'->>'key' like 'numeiro/%' and jsonb_array_length(input->'guioes') = 2
            and input->'guioes'->0->>'id' = g1 and input->'guioes'->0 ? 'corpo' from media_jobs where id = job));

  -- worker grava os documentos
  doc := jsonb_build_object('schema', 1, 'style', 'S15', 'segments', jsonb_build_array(jsonb_build_object('id', 's01', 'in', 10, 'out', 14, 'section', 'hook'),
           jsonb_build_object('id', 's02', 'in', 30, 'out', 40, 'section', 'body')),
           'captions', jsonb_build_object('words', '[]'::jsonb), 'cameras', '[]'::jsonb, 'hook', jsonb_build_object('text', 'Tema'),
           'source', jsonb_build_object('cams', jsonb_build_object('front', 'Sessao_FX30.mp4', 'side', 'Sessao_FX3.mp4'), 'audio', 'side'),
           'ai', jsonb_build_object('confidence', jsonb_build_object('hook', 0.8, 'body', 0.7), 'flags', jsonb_build_array('ver o fim')));
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-pk', array['package']);
  insert into t values ('worker apanha o pacote', true, (j->'job'->>'id')::uuid = job);
  k := media_worker_package_save('w-pk', job, g1, 1, doc);
  j := media_worker_package_save('w-pk', job, g1, 1, doc);
  insert into t values ('gravar documento é idempotente', true, k->>'asset_id' = j->>'asset_id' and (j->>'repeated')::boolean);
  perform media_worker_package_save('w-pk', job, g1, 2, doc);
  begin perform media_worker_package_save('w-pk', job, g2, 1, '{"schema": 1, "segments": []}'::jsonb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('documento inválido recusado (22023)', true, st = '22023');
  begin perform media_worker_package_save('outro', job, g2, 1, doc); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro worker não grava (PT409)', true, st = 'PT409');
  k := media_worker_finish('w-pk', job, true, jsonb_build_object('documents', 2));
  insert into t values ('pacote fecha com os documentos', true, k->>'state' = 'pronta' and (k->>'documents')::int = 2);
  execute 'reset role';
  begin
    execute 'set local role authenticated';
    perform media_worker_package_save('w-pk', job, g2, 1, doc); st := 'ok';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('browser não grava como worker (42501)', true, st = '42501');
  insert into t values ('versão 1 da IA ligada ao guião', true,
    (select count(*) from media_job_outputs o join edit_documents d on d.asset_id = o.asset_id join edit_versions v on v.id = d.current_version_id
      join media_assets a on a.id = o.asset_id where o.job_id = job and v.source = 'ai' and v.version_no = 1 and a.content_id = g1 and a.kind = 'video') = 2);
  insert into t values ('quem pediu é avisado', true, exists (select 1 from notifications where user_id = u_own and title like 'Pacote de edição pronto: 2 vídeos%'));


  -- exportar o pacote inteiro
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform edit_package_export('numeiro', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não exporta o pacote (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_export('numeiro', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não exporta (42501)', true, st = '42501');
  begin perform edit_package_export('ws_rs_b', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pacote de outro cliente não existe no seu (P0002 ou 55000)', true, st in ('P0002', '42501', '55000'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  ej := edit_package_export('numeiro', job);
  insert into t values ('pacote: 2 exports na fila, sem falhas', true, (ej->>'queued')::int = 2 and jsonb_array_length(ej->'failed') = 0);
  k := edit_package_export('numeiro', job);
  insert into t values ('exportar o pacote outra vez devolve os mesmos jobs', true, k->'jobs' = ej->'jobs');
  begin perform edit_package_export('numeiro', gen_random_uuid()); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pacote inexistente (P0002)', true, st = 'P0002');
  a1 := (ej->'jobs'->0->>'asset_id')::uuid;
  k := media_review_list('numeiro', '{}');
  insert into t values ('antes do export o vídeo não está na revisão', true,
    not exists (select 1 from jsonb_array_elements(k->'items') x where (x->>'asset_id')::uuid = a1));
  execute 'reset role';

  insert into t values ('um export por vídeo do pacote', true,
    (select count(*) from media_jobs where kind = 'export' and asset_id in (select asset_id from media_job_outputs where job_id = job)) = 2);
  -- worker exporta com o QC nas notas
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  qc := jsonb_build_object('version', 'qc-test', 'passed', false, 'checks', jsonb_build_array(
          jsonb_build_object('key', 'resolution', 'ok', true, 'label', 'Formato'),
          jsonb_build_object('key', 'loudness', 'ok', false, 'value', -20.1, 'expected', '-14 ± 2 LUFS', 'label', 'Loudness')));
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-rs', array['export']);
    perform media_worker_finish('w-rs', (j->'job'->>'id')::uuid, true, jsonb_build_object('key', j->'job'->'input'->>'out_key', 'sha256', sha,
      'size_bytes', 1234, 'proxy_key', (j->'job'->'input'->>'out_key') || '_proxy.mp4', 'info', jsonb_build_object('duration', 41.5, 'qc', qc)));
  end loop;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  k := media_review_list('numeiro', '{"status": ["in_review"]}');
  select x into j from jsonb_array_elements(k->'items') x where (x->>'asset_id')::uuid = a1;
  insert into t values ('vídeo exportado entra na revisão com o player da app', true, j->>'player' = 'ficheiro' and (j->>'proxy')::boolean
    and j->>'status' = 'in_review' and j->>'variant' like 'hook_%' and (j->>'duration')::numeric = 41.5);
  insert into t values ('lista leva o resumo do QC (1 aviso)', true, (j->'qc'->>'failed')::int = 1 and (j->'qc'->>'passed')::boolean is false);
  insert into t values ('contagem inclui os exportados', true, (k->'counts'->>'in_review')::int >= 2);
  d := media_review_detail('numeiro', a1);
  insert into t values ('detalhe leva o relatório inteiro do QC', true, d->'version'->>'player' = 'ficheiro'
    and jsonb_array_length(d->'version'->'qc'->'checks') = 2 and d->'version'->'qc'->'checks'->1->>'label' = 'Loudness');
  k := media_proxy_access('numeiro', (d->'version'->>'id')::uuid);
  insert into t values ('revisor recebe a versão leve para ver', true, k->>'path' like 'numeiro/%_proxy.mp4');
  perform media_review_comment('numeiro', (d->'version'->>'id')::uuid, 'Aos 3 s o som baixa', 3000);
  insert into t values ('comentário no momento do vídeo exportado', true,
    (media_review_detail('numeiro', a1)->'comments'->0->>'t_ms')::int = 3000);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_review_list('numeiro', '{}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não vê a revisão (42501)', true, st = '42501');
  begin perform media_review_detail('numeiro', a1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não abre o vídeo (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform media_review_decide('numeiro', (d->'version'->>'id')::uuid, 'approved');
  insert into t values ('aprovado preso à versão exportada', true, (media_review_detail('numeiro', a1)->'version'->>'status') = 'approved');
  select (now() at time zone coalesce(timezone, 'UTC'))::date::text into tz from clients where id = 'numeiro';
  k := calendar_range('numeiro', (select date from guioes where id = g1) - 1, (select date from guioes where id = g1) + 1);
  insert into t values ('calendário mostra o outro vídeo exportado por rever', true,
    exists (select 1 from jsonb_array_elements(k->'reviews') x where x->>'content_id' = g1 and (x->>'asset_id')::uuid <> a1));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
