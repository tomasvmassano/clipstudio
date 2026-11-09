-- supabase/tests/w10_refazer_versao_leve.sql : refazer a versão leve de um vídeo pronto (FR-08-01, ADR-0075). W10-28; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_view uuid := gen_random_uuid();
  sha text := repeat('a', 64); f uuid; bf uuid; img uuid; key text;
  j jsonb; j2 jsonb; c jsonb; c2 jsonb; s jsonb; st text; vr media_versions; jid uuid; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pr_b', 'Proxy B', 'prb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'pr-adm@test.invalid'),(u_b,'pr-b@test.invalid'),(u_view,'pr-view@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_pr_b', u_b, 'client_staff', 'workspace_admin'),
    ('numeiro', u_view, 'client_staff', 'viewer');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_pr_b', 'all'), ('media.r2', org, 'ws_pr_b', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'PR_C7870.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'PR_capa.png', 'size', 100, 'mime', 'image/png', 'sha256', sha)); img := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', img, null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_pr_b', null, '{}', jsonb_build_object('name', 'B1.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); bf := (j->>'version_id')::uuid;
  perform media_upload_complete('ws_pr_b', bf, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  -- o carregamento acaba com o original pronto e a versão leve falhada (o que aconteceu ao C7870)
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 3) loop
    j := media_worker_claim('w-pr', array['ingest']);
    perform media_worker_finish('w-pr', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_error', 'sem memória'));
  end loop;
  execute 'reset role';
  select * into vr from media_versions where id = f;
  insert into t values ('pré: original pronto e versão leve falhada', true, vr.state = 'pronta' and vr.proxy_state = 'falhou');
  key := regexp_replace(vr.storage_path, '/[^/]+$', '') || '/proxy.mp4';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform media_proxy_redo('numeiro', f); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem media.upload: recusado (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_proxy_redo('numeiro', f); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não pede em A (42501)', true, st = '42501');
  begin perform media_proxy_redo('ws_pr_b', f); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão de A pedida no espaço B: não encontrada', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform media_proxy_redo('numeiro', img); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('imagem não tem versão leve (22023)', true, st = '22023');
  j := media_proxy_redo('numeiro', f);
  j2 := media_proxy_redo('numeiro', f);
  execute 'reset role';
  jid := (j->>'id')::uuid;
  insert into t values ('pedido cria um job ingest só versão leve', true,
    (select kind = 'ingest' and input->>'proxy_only' = 'true' and status = 'queued' and idempotency_key = 'proxy:' || f || ':1' from media_jobs where id = jid));
  insert into t values ('repetir com o job na fila: o mesmo job', true, j2->>'id' = j->>'id' and (j2->>'repeated')::boolean);
  insert into t values ('versão leve fica pendente', true, (select proxy_state = 'pendente' and proxy_error is null from media_versions where id = f));
  insert into t values ('audit do pedido', true, exists (select 1 from audit_events where action = 'media.proxy_redo_requested' and after->>'job_id' = jid::text));

  -- o worker: grava a versão leve, depois fecha o job
  execute 'set local role engine_worker';
  c := media_worker_claim('w-pr', array['ingest']);
  insert into t values ('worker apanha o job', true, (c->'job'->>'id')::uuid = jid);
  begin perform media_worker_proxy_save('w-pr', jid, jsonb_build_object('proxy_key', 'ws_pr_b/x/1/proxy.mp4')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('chave de outro ficheiro recusada (22023)', true, st = '22023');
  s := media_worker_proxy_save('w-outro', jid, jsonb_build_object('proxy_key', key));
  insert into t values ('outro worker: lost', true, (s->>'lost')::boolean);
  s := media_worker_proxy_save('w-pr', jid, jsonb_build_object('proxy_key', key, 'info', jsonb_build_object('duration', 3)));
  perform media_worker_finish('w-pr', jid, true, jsonb_build_object('proxy_key', key, 'proxy_saved', true));
  execute 'reset role';
  select * into vr from media_versions where id = f;
  insert into t values ('versão leve pronta e gravada', true, (s->>'saved')::boolean and vr.proxy_state = 'pronta' and vr.proxy_path = key);
  insert into t values ('original intacto (pronta, mesmo sha)', true, vr.state = 'pronta' and vr.sha256 = sha);
  insert into t values ('job fechado', true, (select status = 'done' from media_jobs where id = jid));
  insert into t values ('audit do worker', true, exists (select 1 from audit_events where action = 'media.proxy_redone' and after->>'job_id' = jid::text));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform media_proxy_redo('numeiro', f); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão leve pronta: não se repete (22023)', true, st = '22023');
  execute 'reset role';

  -- um job ingest normal não pode usar a função do modo só versão leve
  execute 'set local role engine_worker';
  insert into t values ('authenticated sem EXECUTE no worker', true, not has_function_privilege('authenticated', 'public.media_worker_proxy_save(text, uuid, jsonb)', 'execute'));
  execute 'reset role';
  insert into t values ('anon sem EXECUTE no pedido', true, not has_function_privilege('anon', 'public.media_proxy_redo(text, uuid, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
