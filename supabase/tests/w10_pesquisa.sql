-- supabase/tests/w10_pesquisa.sql : pesquisa global com media da biblioteca, comentários da revisão de vídeos e as minhas
-- notificações (FR-16-01, FR-16-05, MIG-08; ADR-0054). Cliente A = numeiro, cliente B = ws_ps_b. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_ca uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid(); u_rv uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid();
  u_ag uuid := gen_random_uuid(); u_gone uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date; drive text := 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQ/view';
  g1 text; gdel text; ggone text; gb text;
  a_ok uuid; a_trash uuid; a_del uuid; a_b uuid; v_ok uuid; v_trash uuid; v_del uuid; v_b uuid;
  c_ok uuid; c_trash uuid; c_del uuid; c_b uuid; n_ca uuid; n_rv uuid; n_del uuid; n_b uuid; n_agb uuid;
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ps_b', 'Pesquisa B', 'psb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_ca,'ps-ca@test.invalid'),(u_cb,'ps-cb@test.invalid'),(u_rv,'ps-rv@test.invalid'),(u_vw,'ps-vw@test.invalid'),
    (u_ag,'ps-ag@test.invalid'),(u_gone,'ps-gone@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_rv, 'client_staff', 'reviewer'),
    ('numeiro', u_vw, 'client_staff', 'viewer'), ('numeiro', u_gone, 'client_staff', 'contributor'),
    ('numeiro', u_ag, 'agency_staff', 'manager'), ('ws_ps_b', u_ag, 'agency_staff', 'contributor'),
    ('ws_ps_b', u_cb, 'client_staff', 'workspace_admin');
  -- revisor sem media.read (negação explícita) e leitor sem scripts.read
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values
    ('numeiro', u_rv, 'media.read', 'deny', 'teste'), ('numeiro', u_vw, 'scripts.read', 'deny', 'teste');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['busca.global','media.library']) k, unnest(array['numeiro','ws_ps_b']) w;

  -- guiões: A visível, A que vai ser eliminado (com vídeo e comentário), B
  g1 := (select id from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1);
  gdel := (select id from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 1 limit 1);
  ggone := (select id from guioes where client_id = 'numeiro' and deleted_at is null order by date, n offset 2 limit 1);
  update guioes set tema = 'Pelicano em A' where id = g1;
  update guioes set tema = 'Pelicano eliminado' where id = ggone;
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, editorial_status) values
    ('ws_ps_b-g1', 'ws_ps_b', d, 1, 'Pelicano de B', '[{"text":"Hook","mecanismo":""}]', 'Corpo B.', 'in_review');
  gb := 'ws_ps_b-g1';

  -- media: A ativo (vídeo da revisão), A no lixo, A ligado ao guião que vai ser eliminado, B ativo
  insert into media_assets (workspace_id, kind, title, tags, content_id) values ('numeiro', 'video', 'Pelicano final A', '{pelicanotag}', g1) returning id into a_ok;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, external_url, original_name)
    values ('numeiro', a_ok, 1, 'link', 'pronta', drive, 'Ficheiro_Capivara.mp4') returning id into v_ok;
  update media_assets set current_version_id = v_ok where id = a_ok;
  insert into media_assets (workspace_id, kind, title, tags, content_id) values ('numeiro', 'video', 'Pelicano antigo', '{pelicanotag}', g1) returning id into a_trash;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, external_url) values ('numeiro', a_trash, 1, 'link', 'pronta', drive) returning id into v_trash;
  update media_assets set current_version_id = v_trash where id = a_trash;
  insert into media_assets (workspace_id, kind, title, content_id) values ('numeiro', 'video', 'Vídeo do guião apagado', gdel) returning id into a_del;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, external_url) values ('numeiro', a_del, 1, 'link', 'pronta', drive) returning id into v_del;
  update media_assets set current_version_id = v_del where id = a_del;
  insert into media_assets (workspace_id, kind, title, tags, content_id) values ('ws_ps_b', 'video', 'Pelicano de B', '{pelicanotag}', gb) returning id into a_b;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, external_url, original_name)
    values ('ws_ps_b', a_b, 1, 'link', 'pronta', drive, 'Ficheiro_Capivara.mp4') returning id into v_b;
  update media_assets set current_version_id = v_b where id = a_b;

  insert into media_comments (workspace_id, asset_id, version_id, body, author_id, author_label) values
    ('numeiro', a_ok, v_ok, 'O pelicano entra cedo demais', u_ca, 'Ana') returning id into c_ok;
  insert into media_comments (workspace_id, asset_id, version_id, body, author_label) values
    ('numeiro', a_trash, v_trash, 'Pelicano no vídeo que foi para o lixo', 'Ana') returning id into c_trash;
  insert into media_comments (workspace_id, asset_id, version_id, body, author_label) values
    ('numeiro', a_del, v_del, 'Pelicano no vídeo do guião eliminado', 'Ana') returning id into c_del;
  insert into media_comments (workspace_id, asset_id, version_id, body, author_label) values
    ('ws_ps_b', a_b, v_b, 'Pelicano comentado em B', 'Beto') returning id into c_b;

  -- lixo e guiões eliminados (depois de criados os ativos: um ativo novo não se liga a um guião eliminado)
  update media_assets set lifecycle = 'no_lixo', trashed_at = now(), purge_after = now() + interval '30 days' where id = a_trash;
  update guioes set editorial_status = 'archived', archived_from = editorial_status, deleted_at = now() where id in (gdel, ggone);

  -- notificações: minhas (A), do revisor (A), de um guião eliminado (A), de B, do staff em B
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_ca, 'numeiro', 'task_assigned', 'task', gen_random_uuid()::text, 'Pelicano para ti', 'Tarefa nova', 'ps1') returning id into n_ca;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_rv, 'numeiro', 'task_assigned', 'task', gen_random_uuid()::text, 'Pelicano do revisor', null, 'ps2') returning id into n_rv;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_ca, 'numeiro', 'task_assigned', 'content', ggone, 'Guião pelicano atribuído', null, 'ps3') returning id into n_del;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_cb, 'ws_ps_b', 'task_assigned', 'task', gen_random_uuid()::text, 'Pelicano em B', null, 'ps4') returning id into n_b;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_ag, 'ws_ps_b', 'task_assigned', 'media_asset', a_b::text, 'Pelicano para o staff', 'Comentário em vídeo', 'ps5') returning id into n_agb;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key) values
    (u_gone, 'numeiro', 'task_assigned', 'task', gen_random_uuid()::text, 'Pelicano antes de sair', null, 'ps6');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  create temp table hits(who text, q text, kind text, id text, ws text, item jsonb) on commit drop;
  grant all on t, hits to authenticated, anon;
  execute 'set local role authenticated';

  -- ── cliente A (admin) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into hits select 'ca', 'pelicano', g->>'kind', i->>'id', i->>'ws', i from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i;
  insert into t values ('formato igual: mode text, grupos com kind/label/more/items', true,
    j->>'mode' = 'text' and (select bool_and(g ? 'kind' and g ? 'label' and g ? 'more' and g ? 'items') from jsonb_array_elements(j->'groups') g));
  insert into t values ('A: media ativa encontrada pelo título, com etiquetas e nome do ficheiro', true,
    exists (select 1 from hits where who='ca' and kind='media' and id = a_ok::text and ws = 'numeiro'
            and item->>'file_name' = 'Ficheiro_Capivara.mp4' and item->>'media_kind' = 'video' and item->'tags' ? 'pelicanotag'));
  insert into t values ('A: media no lixo não aparece', true, not exists (select 1 from hits where who='ca' and id = a_trash::text));
  insert into t values ('A: comentário do vídeo em revisão, com asset_id e versão', true,
    exists (select 1 from hits where who='ca' and kind='comment' and id = c_ok::text and item->>'asset_id' = a_ok::text
            and (item->>'version')::int = 1 and item->>'author' = 'Ana' and item->>'resolved' = 'false'));
  insert into t values ('A: comentário de vídeo no lixo não aparece', true, not exists (select 1 from hits where who='ca' and id = c_trash::text));
  insert into t values ('A: comentário de vídeo de guião eliminado não aparece', true, not exists (select 1 from hits where who='ca' and id = c_del::text));
  insert into t values ('A: guião eliminado não aparece', true, not exists (select 1 from hits where who='ca' and id = ggone));
  insert into t values ('A: guião visível aparece (os grupos antigos continuam)', true, exists (select 1 from hits where who='ca' and kind='script' and id = g1));
  insert into t values ('A: a minha notificação aparece, com destino', true,
    exists (select 1 from hits where who='ca' and kind='notification' and id = n_ca::text and item->>'entity_type' = 'task' and item->>'read' = 'false'));
  insert into t values ('A: notificação de outra pessoa não aparece', true, not exists (select 1 from hits where who='ca' and id = n_rv::text));
  insert into t values ('A: notificação de um guião eliminado não aparece', true, not exists (select 1 from hits where who='ca' and id = n_del::text));
  insert into t values ('A: nada de B (media, comentários, notificações, guiões)', true,
    not exists (select 1 from hits where who='ca' and (ws is distinct from 'numeiro' or id in (a_b::text, c_b::text, n_b::text, n_agb::text, gb))));
  j := search_global('capivara');
  insert into t values ('A: media pelo nome original do ficheiro, só a de A', true,
    (select array_agg(i->>'id') from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i) = array[a_ok::text]);
  j := search_global('#pelicanotag');
  insert into t values ('A: #etiqueta encontra a media ativa de A e conta só a de A', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where g->>'kind' = 'media' and i->>'id' = a_ok::text)
    and not exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where i->>'id' in (a_b::text, a_trash::text))
    and (select (i->>'count')::int from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where g->>'kind' = 'tag' and i->>'id' = 'pelicanotag') = 1);
  j := search_global(a_ok::text);
  insert into t values ('A: ID da media de A encontra-a', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where i->>'id' = a_ok::text));
  j := search_global(a_b::text);
  insert into t values ('A: ID da media de B não encontra nada', true, jsonb_array_length(j->'groups') = 0);
  j := search_global(c_b::text);
  insert into t values ('A: ID do comentário de B não encontra nada', true, jsonb_array_length(j->'groups') = 0);
  j := search_global(n_b::text);
  insert into t values ('A: ID da notificação de B não encontra nada', true, jsonb_array_length(j->'groups') = 0);
  j := search_global(n_rv::text);
  insert into t values ('A: ID da notificação do revisor não encontra nada', true, jsonb_array_length(j->'groups') = 0);
  begin perform search_global('pelicano', 'ws_ps_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A a forçar p_ws de B: 42501', true, st = '42501');

  -- ── cliente B (admin) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into hits select 'cb', 'pelicano', g->>'kind', i->>'id', i->>'ws', i from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i;
  insert into t values ('B: vê a sua media, o seu comentário e a sua notificação', true,
    exists (select 1 from hits where who='cb' and kind='media' and id = a_b::text)
    and exists (select 1 from hits where who='cb' and kind='comment' and id = c_b::text)
    and exists (select 1 from hits where who='cb' and kind='notification' and id = n_b::text));
  insert into t values ('B: nada de A', true, not exists (select 1 from hits where who='cb' and ws is distinct from 'ws_ps_b'));
  insert into t values ('B: notificação do staff em B não é dela', true, not exists (select 1 from hits where who='cb' and id = n_agb::text));

  -- ── revisor de A sem media.read ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_rv, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into t values ('revisor sem media.read: sem media nem comentários', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' in ('media', 'comment')));
  insert into t values ('revisor sem media.read: vê a sua notificação', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where g->>'kind' = 'notification' and i->>'id' = n_rv::text)
    and not exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where i->>'id' = n_ca::text));

  -- ── leitor de A sem scripts.read: media sim, comentários não (a revisão pede scripts.read) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into t values ('leitor sem scripts.read: media sim, comentários e guiões não', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' = 'media')
    and not exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' in ('comment', 'script')));

  -- ── staff da agência em A e B ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into hits select 'ag', 'pelicano', g->>'kind', i->>'id', i->>'ws', i from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i;
  insert into t values ('staff A+B: media dos dois clientes', true,
    exists (select 1 from hits where who='ag' and id = a_ok::text) and exists (select 1 from hits where who='ag' and id = a_b::text));
  insert into t values ('staff A+B: só as suas notificações', true,
    exists (select 1 from hits where who='ag' and id = n_agb::text)
    and not exists (select 1 from hits where who='ag' and kind = 'notification' and id <> n_agb::text));
  j := search_global('pelicano', 'numeiro', 20);
  insert into t values ('staff com p_ws=A: só A', true,
    (select bool_and(i->>'ws' = 'numeiro') from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i));

  -- ── flag media.library desligada em B: sem media nem comentários de B, notificações continuam ──
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'media.library' and workspace_id = 'ws_ps_b';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into t values ('flag media.library desligada: sem media nem comentários', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' in ('media', 'comment')));
  insert into t values ('flag media.library desligada: notificações continuam', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' = 'notification'));

  -- ── acesso suspenso: deixa de pesquisar (incluindo as notificações antigas) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_gone, 'role','authenticated')::text, true);
  j := search_global('pelicano', null, 20);
  insert into t values ('membro ativo vê a sua notificação', true,
    exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' = 'notification'));
  execute 'reset role';
  update workspace_access set status = 'suspended' where user_id = u_gone;
  execute 'set local role authenticated';
  begin j := search_global('pelicano', null, 20); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro suspenso: pesquisa recusada', true, st in ('55000', '42501'));

  -- ── código de equipa: só o que legacy_can permite (sem media, comentários nem notificações) ──
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := search_global('pelicano', null, 20, tok);
  insert into t values ('código de equipa: guiões sim', true, exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' = 'script'));
  insert into t values ('código de equipa: sem media, comentários nem notificações', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' in ('media', 'comment', 'notification')));
  j := search_global(a_ok::text, null, 20, tok);
  insert into t values ('código de equipa: ID da media não encontra nada', true, jsonb_array_length(j->'groups') = 0);
  j := search_global('#pelicanotag', null, 20, tok);
  insert into t values ('código de equipa: #etiqueta sem media', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') g where g->>'kind' = 'media')
    and not exists (select 1 from jsonb_array_elements(j->'groups') g, jsonb_array_elements(g->'items') i where g->>'kind' = 'tag' and i->>'id' = 'pelicanotag'));
  begin perform search_global('pelicano', null, 20, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anon sem código: 28000', true, st = '28000');

  execute 'reset role';
  insert into t values ('_sdoc_media sem execute para authenticated/anon', true,
    not has_function_privilege('authenticated', 'public._sdoc_media(text, text[], text)', 'execute')
    and not has_function_privilege('anon', 'public._sdoc_media(text, text[], text)', 'execute'));
  insert into t values ('tabelas continuam fechadas à API', true,
    not has_table_privilege('authenticated', 'public.media_comments', 'select') and not has_table_privilege('anon', 'public.media_assets', 'select'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
