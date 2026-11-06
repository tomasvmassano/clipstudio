-- supabase/tests/w10_marcas_janelas.sql : o pacote automático leva as marcas do teleprompter (ING-03, EDL-01). W10-17; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_own uuid := gen_random_uuid();
  sha text := repeat('a', 64); d date := (now() at time zone 'Asia/Dubai')::date; t0 timestamptz := now() - interval '3 hours';
  g1 text; g2 text; g3 text; g4 text; f uuid; s uuid; s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); sb uuid := gen_random_uuid();
  j jsonb; k jsonb; inp jsonb; m jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n_before int;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_mj_b', 'Marcas janelas B', 'mjb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values ('ws_mj_b-1', 'ws_mj_b', d, 1, '[{"text":"h","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'mj-adm@test.invalid'),(u_b,'mj-b@test.invalid'),(u_own,'mj-own@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('ws_mj_b', u_b, 'client_staff', 'workspace_admin');
  insert into agency_memberships (organization_id, user_id, agency_role, status) values (org, u_own, 'agency_owner', 'active');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values ('numeiro', u_own, 'agency_staff', 'workspace_admin')
  on conflict do nothing;
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all');
  perform _edit_seed('numeiro', 'system', 'teste');
  select id into g1 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 1 limit 1;
  select id into g3 from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 2 limit 1;

  -- sessão 1 (numeiro): g1 e g2 lidos no iPad (relógio 40 s atrasado face ao servidor); g1 com takes e "Gravaste? sim"
  insert into recording_sessions (id, workspace_id, date, opened_kind, opened_at, closed_at) values (s1, 'numeiro', d - 1, 'user', t0, t0 + interval '2 hours');
  insert into recording_session_items (session_id, workspace_id, content_id, position) values (s1, 'numeiro', g1, 1), (s1, 'numeiro', g2, 2), (s1, 'numeiro', g3, 3);
  insert into recording_marks (workspace_id, session_id, content_id, block_key, kind, client_at, server_at, device_id, client_ref, actor_kind)
  select 'numeiro', s1, c, b, kd, t0 + make_interval(secs => sec), t0 + make_interval(secs => sec + 40 + lat), 'ipad', gen_random_uuid(), 'user' from (values
    (g1, null, 'open', 0, 0), (g1, 'hook_1', 'play', 2, 0.2), (g1, 'hook_2', 'block', 9, 0.3), (g1, 'body', 'block', 15, 0.1),
    (g1, 'body', 'pause', 50, 0.2), (g1, null, 'recorded', 55, 900),            -- enviado mais tarde (offline): não mexe no desvio mínimo
    (g2, null, 'open', 300, 0.4), (g2, 'hook_1', 'play', 302, 0.2), (g2, 'body', 'block', 310, 0.2), (null, null, 'exit', 340, 0.2)) v(c, b, kd, sec, lat);
  insert into takes (workspace_id, session_id, content_id, block_key, take_number, client_ref, created_kind, created_at) values
    ('numeiro', s1, g1, 'hook_1', 1, gen_random_uuid(), 'user', t0 + interval '8 s'), ('numeiro', s1, g1, 'hook_1', 2, gen_random_uuid(), 'user', t0 + interval '9 s');
  -- sessão 2 (numeiro, mais recente): só g3 lido -> perde para a sessão 1 quando se pedem g1+g2+g3
  insert into recording_sessions (id, workspace_id, date, opened_kind, opened_at, closed_at) values (s2, 'numeiro', d, 'user', t0 + interval '1 day', null);
  insert into recording_session_items (session_id, workspace_id, content_id, position) values (s2, 'numeiro', g3, 1);
  insert into recording_marks (workspace_id, session_id, content_id, block_key, kind, client_at, device_id, client_ref, actor_kind) values
    ('numeiro', s2, g3, 'hook_1', 'play', t0 + interval '1 day', 'mac', gen_random_uuid(), 'user'),
    ('numeiro', s2, null, null, 'exit', t0 + interval '1 day 30 s', 'mac', gen_random_uuid(), 'user');
  -- sessão de B com o guião de B
  insert into recording_sessions (id, workspace_id, date, opened_kind) values (sb, 'ws_mj_b', d, 'user');
  insert into recording_session_items (session_id, workspace_id, content_id, position) values (sb, 'ws_mj_b', 'ws_mj_b-1', 1);
  insert into recording_marks (workspace_id, session_id, content_id, block_key, kind, client_at, device_id, client_ref, actor_kind) values
    ('ws_mj_b', sb, 'ws_mj_b-1', 'hook_1', 'play', now() - interval '1 hour', 'x', gen_random_uuid(), 'user'),
    ('ws_mj_b', sb, null, null, 'exit', now() - interval '59 minutes', 'x', gen_random_uuid(), 'user');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  -- ─ 1. _package_marks: sessão escolhida, leituras, takes, confirmação, desvio do dispositivo
  m := _package_marks('numeiro', array[g1, g2, g3]);
  insert into t values ('escolhe a sessão com mais destes guiões lidos', true, m->'session'->>'id' = s1::text and m->>'reason' is null);
  insert into t values ('leituras por bloco do g1 (hook 1, hook 2, corpo)', true,
    (select array_agg(x->>'block' order by x->>'start') from jsonb_array_elements(m->'items'->g1->'segments') x) = array['hook_1', 'hook_2', 'body']
    and (m->'items'->g1->'segments'->2->>'end')::timestamptz = t0 + interval '50 s');
  insert into t values ('takes e "Gravaste? sim" do g1', true,
    jsonb_array_length(m->'items'->g1->'takes') = 2 and (m->'items'->g1->>'recorded_at')::timestamptz = t0 + interval '55 s');
  insert into t values ('g2 com leituras até sair; g3 não foi lido nesta sessão', true,
    jsonb_array_length(m->'items'->g2->'segments') = 2 and not (m->'items' ? g3));
  insert into t values ('desvio mínimo do iPad ~40 s (o envio offline não conta)', true,
    (m->'devices'->'ipad'->>'skew_s')::numeric between 40 and 40.2 and (m->'devices'->'ipad'->>'n')::int = 10);
  m := _package_marks('numeiro', array[g3]);
  insert into t values ('só g3: a sessão 2', true, m->'session'->>'id' = s2::text and m->'items' ? g3);
  -- isolamento: nunca devolve marcas de outro cliente
  m := _package_marks('numeiro', array['ws_mj_b-1']);
  insert into t values ('guião de B pedido no numeiro: sem sessão', true, m->>'reason' = 'sem_sessao' and m->'items' = '{}'::jsonb);
  m := _package_marks('ws_mj_b', array[g1, g2]);
  insert into t values ('guiões do numeiro pedidos em B: sem sessão', true, m->>'reason' = 'sem_sessao' and m->'session' = 'null'::jsonb);
  m := _package_marks('numeiro', array[]::text[]);
  insert into t values ('sem guiões: sem sessão', true, m->>'reason' = 'sem_sessao');

  -- ─ 2. gravações prontas no R2 para pedir pacotes
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Frente.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); f := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', f, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Lado.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); s := (j->>'version_id')::uuid;
  perform media_upload_complete('numeiro', s, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 2) loop
    j := media_worker_claim('w-mj', array['ingest']);
    perform media_worker_finish('w-mj', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha));
  end loop;
  execute 'reset role';

  -- ─ 3. flag na fase por omissão ('owner'): staff do cliente pede -> job igual ao de hoje (sem marcas)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g1, g2], 'S15');
  execute 'reset role';
  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('flag desligada para quem pede: input sem marcas (como hoje)', true, not (inp ? 'marks') and inp ? 'guioes' and inp->>'style' = 'S15');

  -- dono da agência (fase owner): leva as marcas
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g1, g2, g3], 'S15');
  j := edit_package_request('numeiro', f, s, array[g1, g2, g3], 'S15');
  execute 'reset role';
  select input into inp from media_jobs where id = (k->>'id')::uuid;
  insert into t values ('dono da agência: input com as marcas da sessão certa', true,
    inp->'marks'->'session'->>'id' = s1::text and jsonb_array_length(inp->'marks'->'items'->g1->'segments') = 3);
  insert into t values ('pedido repetido: o mesmo job (idempotente)', true, k->>'id' = j->>'id');
  -- as marcas não mudam a chave; o sufixo ':ia1' só vem dos visuais da IA (W10-18) quando a flag edit.ai_visuals está ligada
  insert into t values ('chave de idempotência igual à de hoje', true,
    (select regexp_replace(idempotency_key, ':ia1$', '') from media_jobs where id = (k->>'id')::uuid) = 'package:' || f || ':' || s || ':' || md5(array_to_string(array[g1, g2, g3], ',')) || ':S15');

  -- flag 'off' para o cliente: nem o dono leva marcas
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('edit.package_marks', org, 'numeiro', 'off');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g2], 'S15');
  execute 'reset role';
  insert into t values ('flag off no cliente: sem marcas', true, not ((select input from media_jobs where id = (k->>'id')::uuid) ? 'marks'));

  -- flag 'all': staff do cliente leva marcas; guião sem leituras -> sem_sessao (o worker vai pela transcrição)
  update feature_flags set stage = 'all' where key = 'edit.package_marks' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  k := edit_package_request('numeiro', f, s, array[g1], 'S15');
  execute 'reset role';
  insert into t values ('flag all: staff do cliente também', true, (select input->'marks'->'session'->>'id' from media_jobs where id = (k->>'id')::uuid) = s1::text);
  select id into g4 from guioes where client_id = 'numeiro' and deleted_at is null and id not in (g1, g2, g3) order by date, n limit 1;
  execute 'set local role authenticated';
  k := edit_package_request('numeiro', f, s, array[g4], 'S15');
  execute 'reset role';
  insert into t values ('guião sem leituras: marks.reason = sem_sessao', true,
    (select input->'marks'->>'reason' from media_jobs where id = (k->>'id')::uuid) = 'sem_sessao');

  -- ─ 4. o trigger não mexe noutros jobs nem em marcas já postas
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts)
  values ('numeiro', 'package', 'mj-test-1', jsonb_build_object('guioes', jsonb_build_array(jsonb_build_object('id', g1)), 'marks', jsonb_build_object('v', 1, 'x', 1)), u_adm, 2)
  returning input into inp;
  insert into t values ('marks já no input ficam como estão', true, inp->'marks' = '{"v":1,"x":1}'::jsonb);
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts)
  values ('numeiro', 'package', 'mj-test-2', jsonb_build_object('guioes', jsonb_build_array('lixo', jsonb_build_object('id', g1))), null, 2)
  returning input into inp;
  insert into t values ('guiões mal formados não rebentam o pedido', true, inp->'marks'->'session'->>'id' = s1::text);
  select count(*) into n_before from media_jobs where kind <> 'package' and input ? 'marks';
  insert into t values ('jobs que não são pacote não levam marcas', true, n_before = 0);

  -- ─ 5. permissões: funções internas fechadas; B não pede o pacote de A
  begin execute 'set local role authenticated'; perform _package_marks('numeiro', array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('authenticated sem EXECUTE em _package_marks (42501)', true, st = '42501');
  begin execute 'set local role anon'; perform _package_marks('numeiro', array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('anon sem EXECUTE em _package_marks (42501)', true, st = '42501');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', f, s, array[g1], 'S15'); st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('admin de B não pede o pacote de A (42501)', true, st = '42501');
  insert into t values ('flag registada', true, exists (select 1 from feature_flag_defs where key = 'edit.package_marks' and default_stage = 'owner'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
