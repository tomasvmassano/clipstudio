-- supabase/tests/w5_recording_marks.sql : tempos de gravação do teleprompter (W5-01; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date; s jsonb; sid uuid; sb uuid; j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
  g1 text := 'numeiro-2026-10-28-01'; g2 text := 'numeiro-2026-10-28-02'; t0 timestamptz := now() - interval '20 minutes';
  mk jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_rm_b', 'Marcas B', 'rmb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values ('ws_rm_b-1', 'ws_rm_b', d, 1, '[{"text":"h","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'rm-con@test.invalid'),(u_view,'rm-view@test.invalid'),(u_b,'rm-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_rm_b', u_b, 'client_staff', 'workspace_admin');
  update guioes set date = d where client_id = 'numeiro';
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  s := recording_session_open('numeiro', d); sid := (s->>'id')::uuid;

  mk := jsonb_build_array(
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'open', 'content', g1, 'at', t0, 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'play', 'content', g1, 'block', 'hook_1', 'at', t0 + interval '2 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'block', 'content', g1, 'block', 'body', 'at', t0 + interval '9 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'pause', 'content', g1, 'block', 'body', 'at', t0 + interval '50 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'recorded', 'content', g1, 'at', t0 + interval '55 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'open', 'content', g2, 'at', t0 + interval '56 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'play', 'content', g2, 'block', 'hook_1', 'at', t0 + interval '60 s', 'device', 'ipad'),
    jsonb_build_object('ref', gen_random_uuid(), 'kind', 'exit', 'at', t0 + interval '70 s', 'device', 'ipad'));
  j := recording_marks_add(sid, mk);
  insert into t values ('lote de marcas guardado', true, (j->>'inserted')::int = 8);
  j := recording_marks_add(sid, mk);
  insert into t values ('reenviar o mesmo lote não duplica (offline)', true, (j->>'inserted')::int = 0 and (j->>'duplicates')::int = 8);
  j := recording_timeline(sid);
  insert into t values ('janelas por bloco: hook 1 7 s, corpo 41 s', true,
    exists (select 1 from jsonb_array_elements(j->'items') x, jsonb_array_elements(x->'segments') sg
             where x->>'content_id' = g1 and sg->>'block' = 'hook_1' and (sg->>'seconds')::numeric = 7)
    and exists (select 1 from jsonb_array_elements(j->'items') x, jsonb_array_elements(x->'segments') sg
             where x->>'content_id' = g1 and sg->>'block' = 'body' and (sg->>'seconds')::numeric = 41));
  insert into t values ('pausa fecha a janela e confirmação fica registada', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->>'content_id' = g1 and (x->>'read_seconds')::int = 48 and x->>'recorded_at' is not null));
  insert into t values ('segundo guião com janela até sair', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->>'content_id' = g2 and (x->>'read_seconds')::int = 10));
  insert into t values ('guiões ordenados por quando foram lidos', true, j->'items'->0->>'content_id' = g1 and j->'items'->1->>'content_id' = g2);

  begin perform recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'dançar', 'at', now()))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tipo de marca inválido (22023)', true, st = '22023');
  begin perform recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'play', 'at', now() + interval '1 hour'))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('marca no futuro recusada (22023)', true, st = '22023');
  begin perform recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'play', 'content', 'ws_rm_b-1', 'at', now()))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião fora da sessão (22023)', true, st = '22023');
  begin perform recording_marks_add(sid, (select jsonb_agg(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'pause', 'at', now())) from generate_series(1, 201))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('no máximo 200 por lote (22023)', true, st = '22023');

  -- leitor (sem recording.use) lê a linha do tempo mas não escreve
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  insert into t values ('leitor lê a linha do tempo', true, (recording_timeline(sid)->>'marks')::int = 8);
  -- outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform recording_timeline(sid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não lê os tempos (42501)', true, st = '42501');
  begin perform recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'pause', 'at', now()))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não escreve (42501)', true, st = '42501');
  -- código de equipa
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'pause', 'content', g2, 'at', now(), 'device', 'tel')), tok);
  insert into t values ('código de equipa regista marcas', true, (j->>'inserted')::int = 1);
  perform recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'not_recorded', 'content', g1, 'at', now(), 'device', 'tel')), tok);
  insert into t values ('desfazer gravado tira a confirmação da linha do tempo', true,
    exists (select 1 from jsonb_array_elements(recording_timeline(sid, tok)->'items') x where x->>'content_id' = g1 and x->>'recorded_at' is null));
  execute 'reset role';
  begin update recording_marks set kind = 'play' where session_id = sid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('marcas não se alteram (42501)', true, st = '42501');
  insert into t values ('tabela fechada a leitura direta', true, not has_table_privilege('authenticated', 'public.recording_marks', 'select'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
