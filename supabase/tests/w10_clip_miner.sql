-- supabase/tests/w10_clip_miner.sql : Clip Miner, cortes de vídeos longos (W10-12, CLIP-01..07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_den uuid := gen_random_uuid();
  sha text := repeat('c', 64); j jsonb; k jsonb; st text; mv uuid; sv uuid; job uuid; doc jsonb; meta jsonb; a1 uuid; ej uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_cm_b', 'Cortes B', 'cmb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'cm-own@test.invalid'),(u_rev,'cm-rev@test.invalid'),(u_b,'cm-b@test.invalid'),(u_den,'cm-den@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_den, 'client_staff', 'manager'), ('ws_cm_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('numeiro', u_den, 'clips.mine', 'deny', 'teste: negação explícita');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'), ('clips.miner', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_cm_b', 'all'), ('edit.studio', org, 'ws_cm_b', 'all'), ('clips.miner', org, 'ws_cm_b', 'all'),
    ('notifications.prefs', org, 'numeiro', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  insert into t values ('capacidade registada e ativa', true,
    exists (select 1 from capabilities where key = 'clips.mine' and status = 'ativo')
    and (select count(*) from role_capabilities where capability = 'clips.mine') = 3
    and not exists (select 1 from role_capabilities where capability = 'clips.mine' and role in ('reviewer', 'contributor', 'viewer')));

  -- dois vídeos no R2: um longo (30 min) e um curto (30 s)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Podcast_ep12.mp4', 'size', 9000, 'mime', 'video/mp4', 'sha256', sha)); mv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', mv, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Curto.mp4', 'size', 900, 'mime', 'video/mp4', 'sha256', sha)); sv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', sv, null);
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('vídeo ainda a verificar: não encontrado (P0002)', true, st = 'P0002');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-cm', array['ingest']);
    perform media_worker_finish('w-cm', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha,
      'proxy_key', 'x/proxy.mp4', 'info', jsonb_build_object('duration', case when (j->'job'->'input'->>'size_bytes')::int = 9000 then 1800 else 30 end, 'width', 1920, 'height', 1080)));
  end loop;
  insert into t values ('claim com kind desconhecido não devolve nada', true, media_worker_claim('w-cm', array['nao_existe']) is null);
  execute 'reset role';

  -- permissões e isolamento
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não pede cortes (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_den, 'role','authenticated')::text, true);
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gestor com negação explícita não pede (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não pede (42501)', true, st = '42501');
  begin perform clips_request('ws_cm_b', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B sem R2 (55000)', true, st = '55000');
  begin perform clips_list('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não lista (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', '', true);
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão não pede', true, st in ('42501', '28000'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform clips_request('numeiro', mv, 3); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('menos de 5 cortes (22023)', true, st = '22023');
  begin perform clips_request('numeiro', sv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('vídeo curto recusado (22023)', true, st = '22023');
  begin perform clips_request('numeiro', gen_random_uuid()); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versão inexistente (P0002)', true, st = 'P0002');
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'clips.miner' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  begin perform clips_request('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada bloqueia mesmo com permissão (55000)', true, st = '55000');
  execute 'reset role';
  update feature_flags set stage = 'all' where key = 'clips.miner' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  k := clips_request('numeiro', mv);
  j := clips_request('numeiro', mv);
  insert into t values ('pedido idempotente', true, k->>'id' = j->>'id' and k->>'kind' = 'clips' and k->>'status' = 'queued');
  job := (k->>'id')::uuid;
  begin perform count(*) from media_job_clips; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tabela dos cortes fechada ao browser (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('job leva o vídeo e o número de cortes', true,
    (select input->'master'->>'name' = 'Podcast_ep12.mp4' and input->'master'->>'key' like 'numeiro/%' and (input->>'count')::int = 8
            and (input->'master'->'info'->>'duration')::int = 1800 from media_jobs where id = job));

  -- worker grava os cortes
  doc := jsonb_build_object('schema', 1, 'style', 'S15', 'size', jsonb_build_array(1080, 1920),
           'segments', jsonb_build_array(jsonb_build_object('id', 's01', 'in', 610, 'out', 614, 'section', 'hook'),
                                         jsonb_build_object('id', 's02', 'in', 590, 'out', 610, 'section', 'body'),
                                         jsonb_build_object('id', 's03', 'in', 614, 'out', 630, 'section', 'body')),
           'captions', jsonb_build_object('words', '[]'::jsonb), 'cameras', '[]'::jsonb, 'hook', jsonb_build_object('text', 'O dinheiro não compra calma'),
           'overlays', '[]'::jsonb,
           'source', jsonb_build_object('kind', 'long', 'time', 'session', 'cams', jsonb_build_object('front', 'Podcast_ep12.mp4'), 'audio', 'front'),
           'ai', jsonb_build_object('confidence', jsonb_build_object('hook', 0.7, 'body', 0.6), 'flags', jsonb_build_array('reframe: corte ao centro')));
  meta := jsonb_build_object('score', 82, 'start', 'f0120', 'end', 'f0131', 'title', 'O dinheiro não compra calma', 'thesis', 'Ter mais não acalma',
            'machine', 'C. mecanismo', 'polemic', jsonb_build_array('afirmacao_forte'), 'risks', jsonb_build_array(), 'justification', 'Tese clara em 40 s',
            'hooks', jsonb_build_array('a', 'b', 'c'), 'dignity', jsonb_build_object('blocked', false));
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-cm', array['clips']);
  insert into t values ('worker apanha o pedido', true, (j->'job'->>'id')::uuid = job);
  k := media_worker_clips_save('w-cm', job, 1, doc, meta);
  j := media_worker_clips_save('w-cm', job, 1, doc, meta);
  insert into t values ('gravar corte é idempotente', true, k->>'asset_id' = j->>'asset_id' and (j->>'repeated')::boolean);
  a1 := (k->>'asset_id')::uuid;
  perform media_worker_clips_save('w-cm', job, 2, doc, meta || '{"score": 55, "polemic": []}');
  begin perform media_worker_clips_save('w-cm', job, 3, '{"schema": 1, "segments": []}'::jsonb, meta); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('documento inválido recusado (22023)', true, st = '22023');
  begin perform media_worker_clips_save('w-cm', job, 3, jsonb_set(doc, '{source,cams,front}', '"Outro_cliente.mp4"'), meta); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('documento com outro vídeo recusado (22023)', true, st = '22023');
  begin perform media_worker_clips_save('w-cm', job, 3, doc, meta || '{"dignity": {"blocked": true, "reason": "grupo"}}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('corte bloqueado pela dignidade recusado (22023)', true, st = '22023');
  begin perform media_worker_clips_save('w-cm', job, 3, doc, meta || '{"title": "um dois três quatro cinco seis sete oito nove"}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('título com mais de 8 palavras recusado (22023)', true, st = '22023');
  begin perform media_worker_clips_save('w-cm', job, 3, doc, meta - 'start'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem IDs de frase recusado (22023)', true, st = '22023');
  begin perform media_worker_clips_save('w-cm', job, 9, doc, meta); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('posição fora do pedido recusada (22023)', true, st = '22023');
  begin perform media_worker_clips_save('outro', job, 3, doc, meta); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro worker não grava (PT409)', true, st = 'PT409');
  execute 'reset role';
  update media_assets set lifecycle = 'no_lixo', trashed_at = now() where id = (select asset_id from media_versions where id = mv);
  execute 'set local role engine_worker';
  begin perform media_worker_clips_save('w-cm', job, 3, doc, meta); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('vídeo longo no lixo: não grava mais cortes (P0002)', true, st = 'P0002');
  execute 'reset role';
  update media_assets set lifecycle = 'ativo', trashed_at = null where id = (select asset_id from media_versions where id = mv);
  execute 'set local role engine_worker';
  k := media_worker_finish('w-cm', job, true, jsonb_build_object('clips', 2, 'model', 'teste', 'prompt_version', 'clip-miner-1'));
  insert into t values ('pedido fecha com os cortes', true, k->>'state' = 'pronta' and (k->>'clips')::int = 2);
  execute 'reset role';
  begin
    execute 'set local role authenticated';
    perform media_worker_clips_save('w-cm', job, 3, doc, meta); st := 'ok';
  exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('browser não grava como worker (42501)', true, st = '42501');
  insert into t values ('versão 1 da IA, sem guião, ligada ao vídeo longo', true,
    (select count(*) from media_job_clips c join edit_documents d on d.asset_id = c.asset_id join edit_versions v on v.id = d.current_version_id
      join media_assets a on a.id = c.asset_id where c.job_id = job and v.source = 'ai' and v.version_no = 1 and a.content_id is null
       and a.tags @> array['corte'] and c.master_asset_id = (select asset_id from media_versions where id = mv)) = 2);
  insert into t values ('quem pediu é avisado', true, exists (select 1 from notifications where user_id = u_own and title like 'Cortes prontos: 2%'));
  insert into t values ('auditoria do pedido e dos cortes', true,
    exists (select 1 from audit_events where action = 'clips.requested' and entity_id = job::text)
    and (select count(*) from audit_events where action = 'clips.doc' and after->>'job_id' = job::text) = 2);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  k := clips_list('numeiro');
  insert into t values ('revisor vê os cortes com pontuação e justificação', true, jsonb_array_length(k) >= 1 and jsonb_array_length(k->0->'clips') = 2
    and (k->0->'clips'->0->'meta'->>'score')::int = 82 and k->0->'clips'->0->'meta'->>'justification' = 'Tese clara em 40 s' and k->0->>'master_name' = 'Podcast_ep12.mp4');
  begin perform clips_export('numeiro', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não exporta (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform clips_export('numeiro', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não exporta (42501)', true, st = '42501');
  begin perform clips_export('ws_cm_b', job); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('trocar o cliente não encontra o pedido', true, st in ('P0002', '42501', '55000'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := clips_export('numeiro', job);
  j := clips_export('numeiro', job);
  insert into t values ('exportar todos: um job por corte, idempotente', true, (k->>'queued')::int = 2 and jsonb_array_length(k->'failed') = 0
    and k->'jobs'->0->>'job_id' = j->'jobs'->0->>'job_id');
  ej := (select (x->>'job_id')::uuid from jsonb_array_elements(k->'jobs') x where (x->>'asset_id')::uuid = a1);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-cm', array['export']);
  while (j->'job'->>'id')::uuid <> ej loop
    perform media_worker_finish('w-cm', (j->'job'->>'id')::uuid, false, null, 'adiado no teste', false);
    j := media_worker_claim('w-cm', array['export']);
  end loop;
  perform media_worker_finish('w-cm', ej, true, jsonb_build_object('key', j->'job'->'input'->>'out_key', 'sha256', repeat('d', 64), 'size_bytes', 4000,
    'proxy_key', 'x/p.mp4', 'info', jsonb_build_object('duration', 40)));
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  k := media_review_list('numeiro');
  insert into t values ('corte exportado entra na revisão em lote (sem guião)', true,
    exists (select 1 from jsonb_array_elements(k->'items') x where (x->>'asset_id')::uuid = a1 and x->'guiao' = 'null'::jsonb and x->>'status' = 'in_review'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin k := media_review_list('ws_cm_b'); st := case when exists (select 1 from jsonb_array_elements(k->'items') x where (x->>'asset_id')::uuid = a1) then 'fuga' else 'ok' end;
  exception when others then st := sqlstate; end;
  insert into t values ('revisão de B não mostra cortes de A', true, st <> 'fuga');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
