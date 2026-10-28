-- supabase/tests/w2_content.sql : modelo canónico de conteúdo (rollback no fim).
-- Negativos exigem o SQLSTATE certo; outro erro conta como falha.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-05'; gb text := 'ws_test_b-2026-10-28-01';
  g guioes; v1 uuid; v2 uuid; h jsonb; st text; n int; nid text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, corpo, hooks) values (gb, 'ws_test_b', '2026-10-28', 1, 'corpo secreto B', '[]');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),(u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),
   (u_adm,'t-adm@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_con,'client_staff','contributor'),('numeiro',u_mgr,'client_staff','manager'),
   ('numeiro',u_adm,'client_staff','workspace_admin'),('ws_test_b',u_b,'client_staff','workspace_admin');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  insert into t values ('insert do motor cria versão 1 e transição', true,
    (select count(*) from content_versions where content_id = gb) = 1 and (select actor_kind from content_transitions where content_id = gb) = 'engine');

  execute 'set local role authenticated';
  -- contributor
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  select * into g from guioes where id = gid; v1 := g.current_version_id;
  g := content_save(gid, '{"corpo":"corpo editado pelo contributor"}'::jsonb, g.lock_version);
  insert into t values ('contributor edita cópia de trabalho', true, g.corpo = 'corpo editado pelo contributor');
  begin perform content_save(gid, '{"corpo":"x"}'::jsonb, g.lock_version - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lock antigo = conflito (PT409)', true, st = 'PT409');
  begin perform content_save(gid, '{"date":"2026-01-01"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo fora da lista recusado (22023)', true, st = '22023');
  begin perform content_transition(gid, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não aprova (42501)', true, st = '42501');
  begin perform content_transition(gid, 'archived'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não arquiva (42501)', true, st = '42501');
  g := content_create('numeiro', '{"corpo":"guião novo manual","hooks":[{"text":"H1","mecanismo":"x"}],"date":"2026-10-28"}'::jsonb); nid := g.id;
  insert into t values ('criar entra como rascunho', true, g.editorial_status = 'draft' and g.current_version_id is not null);
  insert into t values ('criar atribui n seguinte', true, g.n = 31);
  g := content_transition(nid, 'in_review');
  insert into t values ('contributor submete rascunho', true, g.editorial_status = 'in_review');
  begin perform content_save(gb, '{"corpo":"x"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não edita conteúdo de B (42501)', true, st = '42501');
  begin perform content_history(gb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não lê histórico de B (42501)', true, st = '42501');
  begin perform content_create('ws_test_b', '{"corpo":"x"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não cria em B (42501)', true, st = '42501');
  insert into t values ('A não vê versões de B (RLS)', true, (select count(*) from content_versions where workspace_id = 'ws_test_b') = 0);
  begin insert into content_versions (workspace_id, content_id, version_no, corpo, created_kind) values ('numeiro', gid, 99, 'x', 'user'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('escrita direta em versões recusada (42501)', true, st = '42501');
  begin perform 1 from domain_events; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outbox fechada à API (42501)', true, st = '42501');

  -- manager
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  g := content_transition(gid, 'approved');
  insert into t values ('aprovar cria versão da cópia editada', true, g.approved_version_id is not null and g.approved_version_id <> v1);
  insert into t values ('aprovação sincroniza validado', true, g.validado and g.editorial_status = 'approved');
  v2 := g.approved_version_id;
  insert into t values ('versão aprovada tem o texto aprovado', true, (select corpo from content_versions where id = v2) = 'corpo editado pelo contributor');
  g := content_save(gid, '{"corpo":"mudança depois de aprovado"}'::jsonb);
  insert into t values ('editar aprovado abre rascunho', true, g.editorial_status = 'draft' and not g.validado);
  insert into t values ('aprovação fica presa à versão antiga', true, g.approved_version_id = v2);
  insert into t values ('versão aprovada não mudou', true, (select corpo from content_versions where id = v2) = 'corpo editado pelo contributor');
  g := content_transition(gid, 'approved');
  insert into t values ('reaprovar aponta para versão nova', true, g.approved_version_id <> v2);
  begin perform content_transition(nid, 'rejected', '  '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('rejeitar sem motivo recusado (22023)', true, st = '22023');
  g := content_transition(nid, 'rejected', 'tema repetido');
  insert into t values ('rejeitar com motivo', true, g.editorial_status = 'rejected' and g.status = 'rejeitado' and g.motivo_rejeicao = 'tema repetido');
  begin perform content_production(nid, 'recorded'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('rejeitado não se grava (22023)', true, st = '22023');
  g := content_production(gid, 'recorded');
  insert into t values ('gravar sincroniza gravado', true, g.production_status = 'recorded' and g.gravado);
  g := content_production(gid, 'recorded');
  insert into t values ('gravar duas vezes é idempotente', true, (select count(*) from content_transitions where content_id = gid and kind = 'production') = 1);
  h := content_history(gid);
  insert into t values ('histórico tem 3 versões e transições', true, jsonb_array_length(h->'versions') = 3 and jsonb_array_length(h->'transitions') >= 5);
  g := content_restore_version(gid, v1);
  insert into t values ('restaurar versão antiga volta ao texto original', true, g.corpo = (select corpo from content_versions where id = v1) and g.editorial_status = 'draft');
  insert into t values ('restaurar não apaga versões', true, (select count(*) from content_versions where content_id = gid) = 3);

  -- admin: arquivar e recuperar
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  g := content_transition(nid, 'archived');
  insert into t values ('admin arquiva', true, g.editorial_status = 'archived' and g.archived_from = 'rejected');
  begin perform content_save(nid, '{"corpo":"x"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('arquivado não se edita (22023)', true, st = '22023');
  g := content_transition(nid, 'restore');
  insert into t values ('recuperar volta ao estado anterior', true, g.editorial_status = 'rejected');
  g := content_duplicate(gid);
  insert into t values ('duplicar cria rascunho novo', true, g.id <> gid and g.editorial_status = 'draft' and g.origem = 'duplicado:' || gid);

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_transition(gid, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin B não aprova em A (42501)', true, st = '42501');
  insert into t values ('B só vê as suas versões', true, (select count(*) from content_versions where workspace_id = 'numeiro') = 0);
  execute 'reset role';

  -- código de equipa (anon)
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin perform content_save(gid, '{"corpo":"x"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código recusado (28000)', true, st = '28000');
  g := guiao_update('numeiro-2026-10-28-06', '{"hooks":[{"text":"hook do Numeiro","mecanismo":"m"}]}'::jsonb, tok);
  insert into t values ('código edita pela API antiga', true, g.hooks->0->>'text' = 'hook do Numeiro');
  g := guiao_update('numeiro-2026-10-28-06', '{"validado":true}'::jsonb, tok);
  insert into t values ('código valida pela API antiga', true, g.editorial_status = 'approved' and g.approved_version_id is not null);
  g := guiao_update('numeiro-2026-10-28-06', '{"corpo":"mudei depois"}'::jsonb, tok);
  g := guiao_update('numeiro-2026-10-28-06', '{"validado":true}'::jsonb, tok);
  insert into t values ('código reaprova depois de editar', true, g.editorial_status = 'approved');
  begin perform content_transition(gb, 'approved', null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não aprova B (42501)', true, st = '42501');
  begin perform content_transition('numeiro-2026-10-28-07', 'archived', null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não arquiva (42501)', true, st = '42501');
  execute 'reset role';

  -- regras de base de dados
  update clients set require_approval_to_record = true where id = 'numeiro';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform content_production('numeiro-2026-10-28-08', 'recorded'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace exige aprovação para gravar (22023)', true, st = '22023');
  execute 'reset role';
  begin update content_versions set corpo = 'x' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões imutáveis até para o dono da base (42501)', true, st = '42501');
  begin update guioes set client_id = 'ws_test_b' where id = gid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace de um guião não muda (42501)', true, st = '42501');
  insert into t values ('eventos no outbox', true,
    (select count(*) from domain_events where entity_id = gid and type in ('script.approved','script.reopened','recording.confirmed')) >= 4);
  insert into t values ('aprovação auditada', true, exists (select 1 from audit_events where entity_id = gid and action = 'script.approved' and actor_user_id = u_mgr));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
