-- supabase/tests/w9_calendario.sql : calendário com revisões de vídeo e publicações (FR-11-02; ADR-0051). Rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g1 text := 'numeiro-2026-10-28-11'; g2 text := 'numeiro-2026-10-28-12'; g3 text := 'numeiro-2026-10-28-13'; gb text := 'ws_cal_b-1';
  d date := (now() at time zone 'Asia/Dubai')::date; a1 jsonb; a2 jsonb; ab jsonb; j jsonb; st text; p1 uuid; p2 uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_cal_b', 'Cal B', 'calb', org, 'Asia/Dubai');
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_cal_b', d, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into accounts (id, client_id, role, platform, handle, label) values ('ws_cal_b-ig', 'ws_cal_b', 'client', 'instagram', 'calb', 'Cal B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'c-con@test.invalid'),(u_mgr,'c-mgr@test.invalid'),(u_b,'c-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_mgr, 'client_staff', 'manager'), ('ws_cal_b', u_b, 'client_staff', 'workspace_admin');
  update clients set timezone = 'Asia/Dubai' where id = 'numeiro';
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- publicações: uma planeada amanhã às 12:00 (Dubai), uma cancelada, uma de B
  insert into pub_publications (workspace_id, content_id, content_version_id, account_id, platform, scheduled_at)
  values ('numeiro', g3, (select current_version_id from guioes where id = g3), 'numeiro-ig', 'instagram', ((d + 1) + time '12:00') at time zone 'Asia/Dubai')
  returning id into p1;
  insert into pub_publications (workspace_id, content_id, content_version_id, account_id, platform, scheduled_at)
  values ('numeiro', g3, (select current_version_id from guioes where id = g3), 'numeiro-ig', 'instagram', ((d + 2) + time '12:00') at time zone 'Asia/Dubai')
  returning id into p2;
  update pub_publications set status = 'cancelada', cancelled_reason = 'teste' where id = p2;
  insert into pub_publications (workspace_id, content_id, content_version_id, account_id, platform, scheduled_at)
  values ('ws_cal_b', gb, (select current_version_id from guioes where id = gb), 'ws_cal_b-ig', 'instagram', ((d + 1) + time '13:00') at time zone 'Asia/Dubai');

  -- flags desligadas: sem camadas novas
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := calendar_range('numeiro', d - 1, d + 6);
  insert into t values ('flags desligadas: sem revisões nem publicações', true,
    jsonb_array_length(j->'reviews') = 0 and jsonb_array_length(j->'publications') = 0
    and not (j->'layers'->>'reviews')::boolean and not (j->'layers'->>'publications')::boolean);
  insert into t values ('chaves antigas intactas', true, j ? 'contents' and j ? 'tasks' and j ? 'sessions' and j ? 'can');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['media.library', 'pub.planning']) k, unnest(array['numeiro', 'ws_cal_b']) w;
  execute 'set local role authenticated';

  -- vídeos em revisão
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  a1 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWx/view', 'title', 'g11_hook1.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', g1));
  a2 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1ZyXwVuTsRqPoNmLkJiHgFeDc/view', 'title', 'g12_hook2.mp4',
          'tags', jsonb_build_array('hook_2'), 'content_id', g2));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  ab := media_link_add('ws_cal_b', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1QqQqQqQqQqQqQqQqQqQqQqQq/view', 'title', 'B.mp4', 'content_id', gb));
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  perform task_create('numeiro', jsonb_build_object('title', 'Rever vídeo 11', 'kind', 'review', 'content_id', g1,
    'due_at', ((d + 3) + time '18:00') at time zone 'Asia/Dubai'));

  j := calendar_range('numeiro', d - 1, d + 6);
  insert into t values ('camadas ligadas para o manager', true, (j->'layers'->>'reviews')::boolean and (j->'layers'->>'publications')::boolean);
  insert into t values ('vídeo com tarefa de revisão aparece no dia do prazo', true,
    exists (select 1 from jsonb_array_elements(j->'reviews') x where x->>'asset_id' = a1->>'id' and (x->>'due_day')::date = d + 3
            and x->>'due_source' = 'tarefa' and x->>'variant' = 'hook_1' and x->>'status' = 'in_review'));
  insert into t values ('vídeo sem tarefa aparece no dia do guião', true,
    exists (select 1 from jsonb_array_elements(j->'reviews') x where x->>'asset_id' = a2->>'id' and (x->>'due_day')::date = d and x->>'due_source' = 'guiao'));
  insert into t values ('publicação planeada no dia e hora locais', true,
    exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p1 and (x->>'local_day')::date = d + 1
            and x->>'local_time' = '12:00' and x->>'account_handle' = 'itsnumeiro' and x->>'status' = 'planeada'));
  insert into t values ('cancelada não aparece', true, not exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p2));
  insert into t values ('nada de B no calendário de A', true,
    not exists (select 1 from jsonb_array_elements(j->'publications') x where x->>'content_id' = gb)
    and not exists (select 1 from jsonb_array_elements(j->'reviews') x where x->>'asset_id' = ab->>'id'));
  j := calendar_range('numeiro', d + 4, d + 6);
  insert into t values ('fora do intervalo não aparece', true, jsonb_array_length(j->'reviews') = 0 and jsonb_array_length(j->'publications') = 0);

  -- aprovado sai das revisões
  perform media_review_decide('numeiro', (a2->'current'->>'id')::uuid, 'approved');
  j := calendar_range('numeiro', d - 1, d + 6);
  insert into t values ('vídeo aprovado sai das revisões', true, not exists (select 1 from jsonb_array_elements(j->'reviews') x where x->>'asset_id' = a2->>'id'));

  -- B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform calendar_range('numeiro', d, d + 6); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê o calendário de A (42501)', true, st = '42501');
  j := calendar_range('ws_cal_b', d - 1, d + 6);
  insert into t values ('B vê só as suas', true, jsonb_array_length(j->'publications') = 1 and jsonb_array_length(j->'reviews') = 1
    and (j->'publications'->0->>'content_id') = gb);

  -- código de equipa: publicações sim (scripts.read), revisões de vídeo não (precisam de sessão individual)
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := calendar_range('numeiro', d - 1, d + 6, tok);
  insert into t values ('código: sem revisões de vídeo', true, jsonb_array_length(j->'reviews') = 0 and not (j->'layers'->>'reviews')::boolean);
  insert into t values ('código: publicações do seu cliente', true,
    exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p1)
    and not exists (select 1 from jsonb_array_elements(j->'publications') x where x->>'content_id' = gb));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
