-- supabase/tests/w2_references.sql : referências por cliente (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  reelA text := (select r.id from reels r join accounts a on a.id = r.account_id where a.client_id='numeiro' and a.role='reference' order by r.outlier desc nulls last limit 1);
  gid text := 'numeiro-2026-10-28-14'; j jsonb; d jsonb; r1 bigint; r2 bigint; rb bigint; sid bigint := (select min(id) from ideas where client_id='numeiro');
  st text; msg text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into accounts (id, client_id, role, platform, handle) values ('ws_test_b-ref', 'ws_test_b', 'reference', 'instagram', 'criador_b');
  insert into reels (id, platform, owner, role, url, views, outlier, account_id) values ('REELB1', 'instagram', 'criador_b', 'reference', 'https://www.instagram.com/reel/REELB1/', 10, 1, 'ws_test_b-ref');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),(u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),
   (u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_con,'client_staff','contributor'),('numeiro',u_mgr,'client_staff','manager'),
   ('numeiro',u_view,'client_staff','viewer'),('ws_test_b',u_b,'client_staff','workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  begin insert into reference_items (workspace_id, reel_id, titulo, created_kind) values ('numeiro', 'REELB1', 'x', 'user'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('base: reel de B não entra em referência de A (23514)', true, st = '23514');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  d := references_discover('numeiro');
  insert into t values ('descobrir lista os 6 criadores e reels de A', true, jsonb_array_length(d->'creators') = 6 and jsonb_array_length(d->'reels') > 0);
  insert into t values ('descobrir não mostra reels de B', true, not exists (select 1 from jsonb_array_elements(d->'reels') z where z->>'id' = 'REELB1'));
  j := reference_create('numeiro', jsonb_build_object('reel_id', reelA, 'tags', jsonb_build_array('autoridade'), 'colecoes', jsonb_build_array('hooks fortes')));
  r1 := (j->>'id')::bigint;
  insert into t values ('guardar reel como referência herda dados do reel', true, j->>'reel_id' = reelA and j->>'creator' is not null and j->'metrics'->>'source' = 'scraper' and j->'metrics'->>'collected_at' is not null);
  begin perform reference_create('numeiro', jsonb_build_object('reel_id', reelA)); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('mesmo reel duas vezes = PT409', true, st = 'PT409' and msg = 'duplicado:' || r1);
  insert into t values ('reel guardado sai do Descobrir', true, not exists (select 1 from jsonb_array_elements(references_discover('numeiro')->'reels') z where z->>'id' = reelA));
  j := reference_create('numeiro', '{"url":"https://www.tiktok.com/@alguem/video/123?lang=pt","titulo":"Vídeo manual","formato":"lista","tags":["ritmo"]}');
  r2 := (j->>'id')::bigint;
  insert into t values ('referência manual por URL deteta plataforma, sem métricas', true, j->>'platform' = 'tiktok' and j->'metrics' = 'null'::jsonb);
  begin perform reference_create('numeiro', '{"url":"http://tiktok.com/@alguem/video/123"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('URL repetido = PT409', true, st = 'PT409');
  begin perform reference_create('numeiro', '{"titulo":"sem link"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem URL nem reel (22023)', true, st = '22023');
  begin perform reference_create('numeiro', '{"reel_id":"REELB1"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não guarda reel de B (42501)', true, st = '42501');
  j := reference_update(r2, '{"favorito":true,"colecoes":["hooks fortes"],"estilo":"rápido"}');
  insert into t values ('favorito, coleção e estilo', true, (j->>'favorito')::boolean and j->'colecoes' = '["hooks fortes"]' and j->>'estilo' = 'rápido');
  insert into t values ('filtrar por coleção', true, jsonb_array_length(references_list('numeiro', null, null, 'hooks fortes')) = 2);
  insert into t values ('filtrar favoritos', true, jsonb_array_length(references_list('numeiro', null, null, null, true)) = 1);
  insert into t values ('pesquisar', true, jsonb_array_length(references_list('numeiro', 'manual')) = 1);
  j := reference_link(r1, gid, null, true);
  insert into t values ('ligar referência a guião', true, jsonb_array_length(j->'links') = 1);
  insert into t values ('contexto do guião mostra a referência', true, jsonb_array_length(content_context(gid)->'references') = 1);
  j := reference_link(r1, null, sid, true);
  insert into t values ('ligar referência a fonte', true, jsonb_array_length(j->'links') = 2);
  begin perform reference_link(r1, gid, sid, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('alvo duplo recusado (22023)', true, st = '22023');
  j := reference_update(r2, '{"archived":true}');
  insert into t values ('arquivar tira da biblioteca', true, jsonb_array_length(references_list('numeiro')) = 1 and jsonb_array_length(references_list('numeiro', null, null, null, false, true)) = 1);
  begin insert into reference_links (workspace_id, reference_id, content_id, added_kind) values ('numeiro', r1, 'numeiro-2026-10-28-15', 'user'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('escrita direta em ligações recusada (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  insert into t values ('contributor lê referências', true, jsonb_array_length(references_list('numeiro')) = 1);
  begin perform reference_create('numeiro', '{"url":"https://x.test/a"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não gere referências (42501)', true, st = '42501');
  j := reference_link(r1, 'numeiro-2026-10-28-15', null, true);
  insert into t values ('contributor liga referência ao guião que edita', true, jsonb_array_length(j->'links') = 3);
  begin perform reference_link(r1, null, sid, false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não mexe em ligações a fontes (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform references_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer sem references.read (42501)', true, st = '42501');
  insert into t values ('contexto do guião para viewer não expõe referências', true, jsonb_array_length(content_context(gid)->'references') = 0);

  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform references_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista referências de A (42501)', true, st = '42501');
  begin perform references_discover('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não descobre criadores de A (42501)', true, st = '42501');
  begin perform reference_update(r1, '{"favorito":false}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não edita referência de A (42501)', true, st = '42501');
  j := reference_create('ws_test_b', '{"reel_id":"REELB1"}'); rb := (j->>'id')::bigint;
  insert into t values ('B guarda o seu reel', true, rb is not null);
  insert into t values ('B só vê as suas (RLS)', true, (select count(*) from reference_items) = 1);
  begin perform reference_link(rb, gid, null, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não liga referência a guião de A (42501)', true, st = '42501');
  execute 'reset role';

  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código lê referências', true, jsonb_array_length(references_list('numeiro', null, null, null, false, false, tok)) = 1);
  begin perform reference_create('numeiro', '{"url":"https://x.test/b"}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não gere referências (42501)', true, st = '42501');
  begin perform references_list('ws_test_b', null, null, null, false, false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não lê B (42501)', true, st = '42501');
  execute 'reset role';
  begin update reference_items set workspace_id = 'ws_test_b' where id = r1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace de uma referência não muda (42501)', true, st = '42501');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
