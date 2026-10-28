-- supabase/tests/w2_sources.sql : fontes, briefs e pedidos do talento (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-12'; gb text := 'ws_test_b-2026-10-28-01';
  j jsonb; s1 bigint; s2 bigint; sb bigint; g guioes; st text; msg text; b1 uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, corpo, hooks) values (gb, 'ws_test_b', '2026-10-28', 1, 'corpo B', '[]');
  insert into ideas (client_id, fonte_tipo, titulo, fonte_url) values ('ws_test_b', 'noticia', 'fonte secreta B', 'https://exemplo.pt/b') returning id into sb;
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),(u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),
   (u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_con,'client_staff','contributor'),('numeiro',u_mgr,'client_staff','manager'),
   ('numeiro',u_view,'client_staff','viewer'),('ws_test_b',u_b,'client_staff','workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- motor: URL repetido não falha, fica descartado
  insert into ideas (client_id, fonte_tipo, titulo, fonte_url) select 'numeiro', 'noticia', 'repetida', fonte_url || '?utm=x' from ideas where client_id='numeiro' and fonte_url is not null limit 1;
  insert into t values ('motor: URL repetido fica descartado com motivo', true,
    exists (select 1 from ideas where titulo = 'repetida' and status = 'descartada' and status_reason like 'duplicado de #%'));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := source_create('numeiro', '{"titulo":"Artigo novo","fonte_url":"https://www.Exemplo.pt/artigo/?utm_source=x","fonte_tipo":"artigo","tags":["casa"," renda "]}');
  s1 := (j->>'id')::bigint;
  insert into t values ('criar fonte por URL', true, j->>'status' = 'nova' and j->>'ingested_via' = 'url' and j->>'created_kind' = 'user');
  insert into t values ('URL normalizado e tags limpas', true, j->>'url_normalized' = 'exemplo.pt/artigo' and j->'tags' = '["casa","renda"]');
  begin perform source_create('numeiro', '{"titulo":"x","fonte_url":"http://exemplo.pt/artigo#topo"}'); st := 'none'; msg := '';
  exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('URL duplicado = PT409 com o id existente', true, st = 'PT409' and msg = 'duplicado:' || s1);
  begin perform source_create('numeiro', '{"titulo":"x","fonte_url":"ftp://nada"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('URL inválido (22023)', true, st = '22023');
  begin perform source_create('numeiro', '{"titulo":"  "}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('título obrigatório (22023)', true, st = '22023');
  j := source_update(s1, '{"status":"selecionada"}');
  insert into t values ('selecionar fonte', true, j->>'status' = 'selecionada');
  begin perform source_update(s1, '{"status":"descartada"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('descartar sem motivo (22023)', true, st = '22023');
  j := source_create('numeiro', '{"titulo":"Ideia sem URL","resumo":"resumo"}'); s2 := (j->>'id')::bigint;
  j := source_update(s2, '{"status":"descartada","status_reason":"fora de tema"}');
  insert into t values ('descartar com motivo', true, j->>'status' = 'descartada' and j->>'status_reason' = 'fora de tema');
  g := source_to_script(s1, '2026-10-28');
  insert into t values ('fonte → guião cria rascunho com o tema', true, g.editorial_status = 'draft' and g.tema = 'Artigo novo' and g.origem = 'fonte:' || s1);
  insert into t values ('fonte usada fica ligada e marcada usada', true,
    exists (select 1 from content_sources where content_id = g.id and source_id = s1) and (select status from ideas where id = s1) = 'usada');
  j := content_link_source(gid, s2, true);
  insert into t values ('ligar fonte a guião existente', true, jsonb_array_length(j->'sources') = 1);
  j := content_link_source(gid, s2, false);
  insert into t values ('desligar fonte', true, jsonb_array_length(j->'sources') = 0);
  begin perform content_link_source(gid, sb, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não liga fonte de B a guião de A (42501)', true, st = '42501');
  j := brief_save(gid, '{"objetivo":"gerar comentários","audiencia":"25-35","tese":"casa não é ativo","duracao_s":45,"plataformas":["instagram","tiktok"]}');
  b1 := (j->'brief'->>'id')::uuid;
  insert into t values ('brief guardado (v1)', true, (j->'brief'->>'version_no')::int = 1 and j->'brief'->'plataformas' = '["instagram","tiktok"]');
  begin perform brief_save(gid, '{"orcamento":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo de brief desconhecido (22023)', true, st = '22023');
  begin perform brief_save(gid, '{"duracao_s":99999}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('duração fora do limite recusada (23514)', true, st = '23514');
  begin insert into content_briefs (workspace_id, content_id, version_no, created_kind) values ('numeiro', gid, 9, 'user'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('escrita direta em briefs recusada (42501)', true, st = '42501');
  begin insert into content_sources (workspace_id, content_id, source_id, added_kind) values ('numeiro', gid, s1, 'user'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('escrita direta em ligações recusada (42501)', true, st = '42501');

  -- manager aprova: a versão aprovada fica com o brief em vigor
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  g := content_transition(gid, 'approved');
  insert into t values ('versão aprovada referencia o brief em vigor', true, (select brief_id from content_versions where id = g.approved_version_id) = b1);
  j := brief_save(gid, '{"objetivo":"gerar partilhas"}');
  insert into t values ('mudar o brief não mexe na aprovação, mas fica visível', true,
    (j->>'approved_brief_id')::uuid = b1 and (j->'brief'->>'id')::uuid <> b1 and (j->>'brief_versions')::int = 2
    and (select editorial_status from guioes where id = gid) = 'approved');

  -- viewer
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  insert into t values ('viewer lê fontes', true, jsonb_array_length(sources_list('numeiro')) >= 14);
  begin perform source_create('numeiro', '{"titulo":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não cria fonte (42501)', true, st = '42501');
  begin perform talent_request_create('numeiro', 'quero falar de rendas'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não faz pedidos (42501)', true, st = '42501');
  begin perform brief_save(gid, '{"objetivo":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não edita brief (42501)', true, st = '42501');

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform sources_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista fontes de A (42501)', true, st = '42501');
  begin perform source_update(s1, '{"status":"triagem"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não tria fonte de A (42501)', true, st = '42501');
  begin perform content_link_source(gb, s1, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não liga fonte de A ao seu guião (42501)', true, st = '42501');
  begin perform content_context(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê brief de A (42501)', true, st = '42501');
  insert into t values ('B não vê briefs de A (RLS)', true, (select count(*) from content_briefs where workspace_id = 'numeiro') = 0);
  insert into t values ('B vê as suas fontes', true, jsonb_array_length(sources_list('ws_test_b')) = 1);
  execute 'reset role';

  -- código de equipa
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  j := talent_request_create('numeiro', '  Quero um vídeo sobre   o preço das casas no Algarve ', tok);
  insert into t values ('talento faz pedido por texto', true, j->>'kind' = 'talent_request' and j->>'status' = 'nova' and j->>'created_kind' = 'legacy_code'
    and j->>'titulo' = 'Quero um vídeo sobre o preço das casas no Algarve');
  begin perform talent_request_create('numeiro', 'ok', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pedido demasiado curto (22023)', true, st = '22023');
  begin perform source_create('numeiro', '{"titulo":"x"}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não cria fontes (42501)', true, st = '42501');
  begin perform source_update(s1, '{"status":"triagem"}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não tria (42501)', true, st = '42501');
  insert into t values ('código lê fontes e pedidos', true, jsonb_array_length(sources_list('numeiro', null, 'talent_request', null, 50, tok)) = 1);
  begin perform talent_request_create('ws_test_b', 'pedido para B', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não pede em B (42501)', true, st = '42501');
  begin perform sources_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código recusado (42501)', true, st = '42501');
  execute 'reset role';

  begin update content_briefs set objetivo = 'x' where id = b1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('briefs imutáveis (42501)', true, st = '42501');
  begin update ideas set client_id = 'ws_test_b' where id = s1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace de uma fonte não muda (42501)', true, st = '42501');
  insert into t values ('eventos de fontes no outbox', true,
    (select count(*) from domain_events where type in ('source.created','source.approved','source.discarded','request.created','brief.updated') and workspace_id = 'numeiro') >= 6);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
