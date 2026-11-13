-- supabase/tests/w10_cortes_youtube.sql : cortes a partir do link do YouTube + ficheiro, modo leve e número pela duração (W10-45, CHG-012; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  sha text := repeat('d', 64); j jsonb; st text; mv uuid; job uuid; l jsonb;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_cy_b', 'Cortes YT B', 'cyb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'cy-own@test.invalid'),(u_rev,'cy-rev@test.invalid'),(u_b,'cy-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'), ('ws_cy_b', u_b, 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'), ('clips.miner', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_cy_b', 'all'), ('edit.studio', org, 'ws_cy_b', 'all'), ('media.r2', org, 'ws_cy_b', 'all'), ('clips.miner', org, 'ws_cy_b', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  insert into t values ('link: watch?v=', true, _youtube_id('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s') = 'dQw4w9WgXcQ');
  insert into t values ('link: youtu.be', true, _youtube_id('youtu.be/dQw4w9WgXcQ?si=abc') = 'dQw4w9WgXcQ');
  insert into t values ('link: shorts e live', true, _youtube_id('https://youtube.com/shorts/dQw4w9WgXcQ') = 'dQw4w9WgXcQ'
    and _youtube_id('https://www.youtube.com/live/dQw4w9WgXcQ') = 'dQw4w9WgXcQ');
  insert into t values ('link: outro site não', true, _youtube_id('https://vimeo.com/123') is null and _youtube_id('https://evil.com/?v=dQw4w9WgXcQ') is null);

  -- um vídeo de 60 min no R2, verificado
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Vlog_praia.mp4', 'size', 9100, 'mime', 'video/mp4', 'sha256', sha)); mv := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', mv, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-cy', array['ingest']);
  perform media_worker_finish('w-cy', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', 9100, 'sha256', sha,
    'proxy_key', 'x/proxy.mp4', 'info', jsonb_build_object('duration', 3600, 'width', 1920, 'height', 1080)));
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);

  begin perform clips_request2('numeiro', mv, null, 'leve', 'https://vimeo.com/1'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('link que não é do YouTube: 22023', true, st = '22023');
  begin perform clips_request2('numeiro', mv, 25); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('mais de 20 cortes: 22023', true, st = '22023');
  begin perform clips_request2('numeiro', mv, null, 'pesado'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('modo desconhecido: 22023', true, st = '22023');
  j := clips_request2('numeiro', mv, null, 'leve', 'https://youtu.be/dQw4w9WgXcQ');
  job := (j->>'id')::uuid;
  insert into t values ('automático: 60 min dá 15 cortes', true, (j->>'count')::int = 15);
  insert into t values ('modo leve e link guardado', true, j->>'mode' = 'leve' and j->'youtube'->>'id' = 'dQw4w9WgXcQ');
  insert into t values ('pedido igual devolve o mesmo job', true, (clips_request2('numeiro', mv, null, 'leve', 'https://youtu.be/dQw4w9WgXcQ')->>'id')::uuid = job);
  insert into t values ('modo completo é outro pedido', true, (clips_request2('numeiro', mv, 12, 'completo')->>'id')::uuid <> job);
  l := clips_list('numeiro');
  insert into t values ('lista mostra modo, link e número', true,
    exists (select 1 from jsonb_array_elements(l) x where (x->>'id')::uuid = job and x->>'mode' = 'leve' and x->'youtube'->>'id' = 'dQw4w9WgXcQ' and (x->>'count')::int = 15));
  insert into t values ('pedido antigo (clips_request) continua a funcionar', true, (clips_request('numeiro', mv, 8)->>'id') is not null);

  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform clips_request2('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor sem clips.mine: 42501', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform clips_request2('numeiro', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente: 42501', true, st = '42501');
  begin perform clips_request2('ws_cy_b', mv); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('vídeo de outro cliente no próprio espaço: P0002', true, st = 'P0002');
  execute 'reset role';
  insert into t values ('job com input do motor', true,
    (select input->>'mode' = 'leve' and (input->>'count_auto')::boolean and input->'language' = 'null'::jsonb from media_jobs where id = job));
  insert into t values ('auditado', true, exists (select 1 from audit_events where action = 'clips.requested' and entity_id = job::text and after->>'youtube' = 'dQw4w9WgXcQ'));
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.clips_request2(text, uuid, int, text, text, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
