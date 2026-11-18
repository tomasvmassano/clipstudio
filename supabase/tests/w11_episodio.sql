-- supabase/tests/w11_episodio.sql : edição do episódio completo (W11-01, CHG-013, POD-01..06; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_den uuid := gen_random_uuid();
  sha text := repeat('c', 64); j jsonb; k jsonb; st text; mv uuid; sv uuid; wv uuid; job uuid; job2 uuid; pre text; res_ok jsonb; a1 uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ep_b', 'Episódios B', 'epb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'ep-own@test.invalid'),(u_rev,'ep-rev@test.invalid'),(u_b,'ep-b@test.invalid'),(u_den,'ep-den@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_den, 'client_staff', 'manager'), ('ws_ep_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('numeiro', u_den, 'edit.episode', 'deny', 'teste: negação explícita');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'), ('edit.episode', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_ep_b', 'all'), ('edit.studio', org, 'ws_ep_b', 'all'), ('edit.episode', org, 'ws_ep_b', 'all'),
    ('notifications.prefs', org, 'numeiro', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  insert into t values ('capacidade registada e ativa; perfis planeados', true,
    exists (select 1 from capabilities where key = 'edit.episode' and status = 'ativo')
    and (select count(*) from role_capabilities where capability = 'edit.episode') = 3
    and not exists (select 1 from role_capabilities where capability = 'edit.episode' and role in ('reviewer', 'contributor', 'viewer'))
    and (select count(*) from capabilities where key in ('edit.style_learn', 'edit.style_approve') and status = 'planeado') = 2);

  -- três vídeos no R2: duas câmaras do episódio (30 min) e um curto (30 s)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Ep12_frente.mp4', 'size', 9000, 'mime', 'video/mp4', 'sha256', sha)); mv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', mv, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Ep12_largo.mp4', 'size', 9001, 'mime', 'video/mp4', 'sha256', sha)); wv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', wv, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Curto.mp4', 'size', 900, 'mime', 'video/mp4', 'sha256', sha)); sv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', sv, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 3) loop
    j := media_worker_claim('w-ep', array['ingest']);
    perform media_worker_finish('w-ep', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha,
      'proxy_key', 'x/proxy.mp4', 'info', jsonb_build_object('duration', case when (j->'job'->'input'->>'size_bytes')::int >= 9000 then 1800 else 30 end, 'width', 1920, 'height', 1080)));
  end loop;
  execute 'reset role';

  -- permissões e isolamento
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform episode_request('numeiro', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não pede (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_den, 'role','authenticated')::text, true);
  begin perform episode_request('numeiro', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gestor com negação explícita não pede (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform episode_request('numeiro', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não pede no A (42501)', true, st = '42501');
  begin perform episode_request('ws_ep_b', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B sem R2 (55000)', true, st = '55000');
  begin perform episode_list('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não lista (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', '', true);
  begin perform episode_request('numeiro', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão não pede', true, st in ('42501', '28000'));

  -- validação
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform episode_request('numeiro', jsonb_build_object('front', sv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('episódio curto recusado (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('Front Cam', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('nome de câmara inválido (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', mv, 'side', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('a mesma gravação em duas câmaras (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', mv), 'side'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('som numa câmara que não existe (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', mv), null, 'wide'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('largo numa câmara que não existe (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', mv), null, null, '{"audio": {"lufs": -60}}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('perfil com loudness fora do intervalo (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', mv), null, null, '{"segredo": 1}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('perfil com chave desconhecida (22023)', true, st = '22023');
  begin perform episode_request('numeiro', jsonb_build_object('front', gen_random_uuid())); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versão inexistente (P0002)', true, st = 'P0002');
  begin perform episode_request('numeiro', '{}'::jsonb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem câmaras (22023)', true, st = '22023');
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'edit.episode' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  begin perform episode_request('numeiro', jsonb_build_object('front', mv)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada bloqueia mesmo com permissão (55000)', true, st = '55000');
  execute 'reset role';
  update feature_flags set stage = 'all' where key = 'edit.episode' and workspace_id = 'numeiro';
  execute 'set local role authenticated';

  -- pedido válido (duas câmaras, largo, perfil) e idempotência
  k := episode_request('numeiro', jsonb_build_object('front', mv, 'wide', wv), 'front', 'wide', '{"pacing": {"max_pause_s": 0.6}, "audio": {"lufs": -16}}');
  j := episode_request('numeiro', jsonb_build_object('front', mv, 'wide', wv), 'front', 'wide', '{"pacing": {"max_pause_s": 0.6}, "audio": {"lufs": -16}}');
  insert into t values ('pedido idempotente', true, k->>'id' = j->>'id' and k->>'kind' = 'episode' and k->>'status' = 'queued');
  job := (k->>'id')::uuid;
  k := episode_request('numeiro', jsonb_build_object('front', mv));
  job2 := (k->>'id')::uuid;
  insert into t values ('perfil diferente = pedido novo', true, job2 <> job);
  begin perform count(*) from media_jobs; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('jobs fechados ao browser (42501)', true, st = '42501');
  k := episode_list('numeiro');
  insert into t values ('lista mostra os pedidos com as câmaras', true,
    jsonb_array_length(k) = 2 and exists (select 1 from jsonb_array_elements(k) x where (x->>'id')::uuid = job and x->'cams'->>'wide' = 'Ep12_largo.mp4'
                                          and (x->>'profile')::boolean and x->>'status' = 'queued'));
  begin perform episode_file_access('numeiro', job, 'master.mp4'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ficheiro antes de acabar (22023)', true, st = '22023');
  execute 'reset role';
  select input->>'out_prefix' into pre from media_jobs where id = job;
  insert into t values ('job leva câmaras, som, largo, perfil e destino', true,
    (select input->'cams'->'front'->>'key' like 'numeiro/%' and input->>'audio' = 'front' and input->>'wide' = 'wide'
            and (input->'profile'->'pacing'->>'max_pause_s')::numeric = 0.6 and pre = 'numeiro/episodes/' || job from media_jobs where id = job));

  -- worker: resultado inválido falha; resultado certo cria o vídeo na Biblioteca
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-ep', array['episode']);
  while (j->'job'->>'id')::uuid <> job2 loop
    perform media_worker_finish('w-ep', (j->'job'->>'id')::uuid, false, null, 'adiado no teste', true);
    j := media_worker_claim('w-ep', array['episode']);
  end loop;
  k := media_worker_finish('w-ep', job2, true, jsonb_build_object('files', jsonb_build_object(
         'master.mp4', jsonb_build_object('key', 'ws_ep_b/roubado.mp4', 'sha256', sha, 'size_bytes', 10))));
  execute 'reset role';
  insert into t values ('master fora do destino do pedido: falha', true, k->>'state' = 'falhou'
    and (select status = 'failed' and last_error = 'resultado_invalido' from media_jobs where id = job2));
  update media_jobs set status = 'queued', next_attempt_at = now(), locked_by = null where id = job;
  execute 'set local role engine_worker';
  j := media_worker_claim('w-ep', array['episode']);
  insert into t values ('worker apanha o pedido', true, (j->'job'->>'id')::uuid = job and j->'job'->'input'->>'out_prefix' = pre);
  res_ok := jsonb_build_object('files', jsonb_build_object(
      'master.mp4', jsonb_build_object('key', pre || '/master.mp4', 'sha256', repeat('e', 64), 'size_bytes', 123456, 'info', jsonb_build_object('width', 1920, 'height', 1080, 'duration', 1500)),
      'legendas.srt', jsonb_build_object('key', pre || '/legendas.srt', 'sha256', repeat('f', 64), 'size_bytes', 900),
      'audio.mp3', jsonb_build_object('key', pre || '/audio.mp3', 'sha256', repeat('a', 64), 'size_bytes', 9000)),
    'summary', jsonb_build_object('cuts', 210, 'removed_pct', 16.7, 'before_s', 1800, 'after_s', 1500), 'titles', jsonb_build_array('NOVO: x'), 'language', 'pt');
  begin perform media_worker_finish('outro', job, true, res_ok); st := 'ok'; exception when others then st := sqlstate; end;
  k := media_worker_finish('w-ep', job, true, res_ok);
  a1 := (k->>'asset_id')::uuid;
  insert into t values ('episódio fecha e o master entra na Biblioteca', true, k->>'state' = 'pronta' and a1 is not null);
  execute 'reset role';
  insert into t values ('master: vídeo novo, versão pronta no R2, no destino do pedido', true,
    (select a.workspace_id = 'numeiro' and a.title like 'Episódio editado · %' and 'episodio' = any(a.tags) and v.state = 'pronta' and v.storage_provider = 'r2'
            and v.storage_path = pre || '/master.mp4' and v.sha256 = repeat('e', 64) and a.current_version_id = v.id
       from media_assets a join media_versions v on v.asset_id = a.id where a.id = a1));
  insert into t values ('job guarda o vídeo e o resumo; auditoria e notificação', true,
    (select status = 'done' and (result->>'asset_id')::uuid = a1 and (result->'summary'->>'cuts')::int = 210 from media_jobs where id = job)
    and exists (select 1 from audit_events where action = 'episode.edited' and entity_id = a1::text)
    and exists (select 1 from notifications where user_id = u_own and dedup_key = 'episode:' || job));

  -- descarregar os ficheiros
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := episode_file_access('numeiro', job, 'legendas.srt');
  insert into t values ('link do .srt para o caminho do pedido', true, k->>'path' = pre || '/legendas.srt' and k->>'bucket' = 'r2' and (k->>'ttl_seconds')::int = 120
    and k->>'mime' = 'application/x-subrip');
  begin perform episode_file_access('numeiro', job, 'capitulos.txt'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ficheiro que não foi gerado (P0002)', true, st = 'P0002');
  begin perform episode_file_access('numeiro', job, '../../segredo'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('nome de ficheiro desconhecido (22023)', true, st = '22023');
  k := episode_list('numeiro');
  insert into t values ('lista mostra ficheiros, resumo e vídeo', true,
    exists (select 1 from jsonb_array_elements(k) x where (x->>'id')::uuid = job and x->'files' @> '["audio.mp3", "legendas.srt", "master.mp4"]'
                                                      and (x->>'master_asset_id')::uuid = a1 and (x->'summary'->>'removed_pct')::numeric = 16.7));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform episode_file_access('numeiro', job, 'legendas.srt'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não descarrega (42501)', true, st = '42501');
  begin perform episode_file_access('ws_ep_b', job, 'legendas.srt'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('job de A pelo espaço de B: não encontrado (P0002)', true, st = 'P0002');
  execute 'reset role';
  insert into t values ('autorização de 60 s criada e acesso auditado', true,
    exists (select 1 from media_access_grants where object_path = pre || '/legendas.srt' and user_id = u_own and purpose = 'download')
    and exists (select 1 from audit_events where action = 'episode.file_accessed' and entity_id = job::text));

  -- os outros ramos de media_worker_finish ficam iguais (export continua a ser o ramo por omissão)
  insert into t values ('kind episode no check; clips continua', true,
    (select pg_get_constraintdef(oid) like '%episode%' and pg_get_constraintdef(oid) like '%clips%' from pg_constraint where conname = 'media_jobs_kind_check'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
