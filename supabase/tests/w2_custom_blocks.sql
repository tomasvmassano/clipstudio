-- supabase/tests/w2_custom_blocks.sql : blocos personalizados no teleprompter (FR-03-02; rollback no fim).
do $$
declare
  u_con uuid := gen_random_uuid();
  d date := (now() at time zone 'Asia/Dubai')::date; s jsonb; sid uuid; g text; t jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) values (u_con, 'cb-con@test.invalid', now(), 'authenticated', 'authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values ('numeiro', u_con, 'client_staff', 'contributor');
  update guioes set date = d where client_id = 'numeiro';
  g := (select id from guioes where client_id = 'numeiro' and editorial_status not in ('rejected','archived') order by n limit 1);
  update guioes set corpo = E'Abertura sem marca.\n## Prova social\nTexto da prova.\n## Pergunta à câmara\nE tu?\n## Prova social\nOutra vez.', cta = 'Segue.' where id = g;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  insert into t values ('chaves pela ordem: hooks, body, personalizados, cta', true,
    _content_block_keys((select hooks from guioes where id = g), (select corpo from guioes where id = g), 'Segue.')
      = array['hook_1','hook_2','hook_3','body','x_prova_social','x_pergunta_a_camara','x_prova_social_2','cta']);
  insert into t values ('sem texto antes da primeira marca não há body', true,
    _content_block_keys('[]', E'## Um\nlinha', null) = array['x_um']);
  insert into t values ('sem marcas fica como antes', true, _content_block_keys('[{"text":"h"}]', E'linha 1\nlinha 2', '') = array['hook_1','body']);
  insert into t values ('chaves aceites', true, _block_key_ok('x_prova_social') and _block_key_ok('hook_3') and not _block_key_ok('x_') and not _block_key_ok('X_A')
    and not _block_key_ok('custom'));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  s := recording_session_open('numeiro', d); sid := (s->>'id')::uuid;
  t := take_create(sid, g, 'x_pergunta_a_camara', gen_random_uuid());
  insert into t values ('take num bloco personalizado', true, t->>'block_key' = 'x_pergunta_a_camara' and (t->>'take_number')::int = 1);
  begin perform take_create(sid, g, 'x_nao_existe', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('bloco que não está no texto é recusado (22023)', true, st = '22023');
  begin perform take_create(sid, g, 'x_Mau', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('chave mal formada é recusada (22023)', true, st = '22023');
  s := recording_queue_set(sid, jsonb_build_array(jsonb_build_object('content_id', g, 'skipped_blocks', '["x_prova_social_2"]'::jsonb)));
  insert into t values ('saltar um bloco personalizado', true,
    exists (select 1 from jsonb_array_elements(s->'items') x where x->>'content_id' = g and x->'skipped_blocks' = '["x_prova_social_2"]'::jsonb));
  perform recording_progress(sid, g, 'x_prova_social', 0.4);
  insert into t values ('retoma num bloco personalizado', true, (select last_block from recording_sessions where id = sid) = 'x_prova_social');
  s := recording_marks_add(sid, jsonb_build_array(jsonb_build_object('ref', gen_random_uuid(), 'kind', 'block', 'content', g, 'block', 'x_prova_social', 'at', now())));
  insert into t values ('marca de tempo num bloco personalizado', true, (s->>'inserted')::int = 1);
  t := take_create(sid, g, 'body', gen_random_uuid());
  insert into t values ('body continua a funcionar', true, t->>'block_key' = 'body');
  execute 'reset role';
  update guioes set corpo = E'## Só marcas\ntexto' where id = g;
  execute 'set local role authenticated';
  begin perform take_create(sid, g, 'body', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem body no texto, take de body é recusado (22023)', true, st = '22023');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
