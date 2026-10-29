-- supabase/tests/w3_calendar.sql : calendário, reagendar e estados de produção (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  today date := (now() at time zone 'Asia/Dubai')::date;
  g1 text := 'numeiro-2026-10-28-01'; g2 text := 'numeiro-2026-10-28-02'; g3 text := 'numeiro-2026-10-28-03'; g4 text := 'numeiro-2026-10-28-04';
  ga text := 'numeiro-2026-10-28-10'; gb text := 'ws_test_b-2026-10-28-01';
  j jsonb; g guioes; lk int; rid uuid; s jsonb;
  st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_test_b', today + 1, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),(u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),
   (u_rev,'t-rev@test.invalid',now(),'authenticated','authenticated'),(u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),
   (u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_con,'client_staff','contributor'),('numeiro',u_rev,'client_staff','reviewer'),
   ('numeiro',u_view,'client_staff','viewer'),('ws_test_b',u_b,'client_staff','workspace_admin');
  update guioes set editorial_status = 'archived', archived_from = 'in_review' where id = ga;
  update guioes set date = today - 1 where id in (g3, g4);  -- por gravar de ontem
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- leitura
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := calendar_range('numeiro', today - 3, today + 3);
  insert into t values ('calendário traz os guiões do intervalo, sem arquivados', true,
    jsonb_array_length(j->'contents') = 29 and not exists (select 1 from jsonb_array_elements(j->'contents') c where c->>'id' = ga));
  insert into t values ('guiões de dias passados por gravar marcados atrasados', true,
    (select bool_and((c->>'late')::boolean) from jsonb_array_elements(j->'contents') c where (c->>'date')::date < today));
  insert into t values ('calendário diz o que posso fazer', true, (j->'can'->>'schedule')::boolean and (j->'can'->>'production')::boolean);
  begin perform calendar_range('numeiro', '2026-01-01', '2026-06-01'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('intervalo grande demais (22023)', true, st = '22023');

  -- reagendar
  lk := (select lock_version from guioes where id = g1);
  j := content_reschedule(g1, today + 2, lk);
  insert into t values ('reagendar muda a data e numera no dia novo', true, (j->>'date')::date = today + 2 and (j->>'n')::int = 1 and (j->>'lock_version')::int = lk + 1);
  begin perform content_reschedule(g1, today + 3, lk); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('reagendar com versão antiga = PT409', true, st = 'PT409');
  begin perform content_reschedule(g2, today - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se reagenda para o passado (22023)', true, st = '22023');
  begin perform content_reschedule(ga, today + 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('arquivado não se reagenda (22023)', true, st = '22023');
  j := content_reschedule(g2, today + 2);
  insert into t values ('segundo guião no mesmo dia recebe n seguinte', true, (j->>'n')::int = 2);
  execute 'reset role';
  insert into t values ('reagendar fica auditado', true, exists (select 1 from audit_events where entity_id = g1 and action = 'script.rescheduled'));
  execute 'set local role authenticated';

  -- estados de produção
  g := content_production(g3, 'scheduled');
  insert into t values ('manager agenda', true, g.production_status = 'scheduled');
  j := task_rule_save('numeiro', jsonb_build_object('on_event','production.editing','complete_on',jsonb_build_array('production.ready'),
                                                     'kind','edit','title','Editar guião {n}','assignee_id',u_con));
  rid := (j->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform content_reschedule(g4, today + 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não reagenda (42501)', true, st = '42501');
  g := content_production(g3, 'recorded');
  insert into t values ('agendado → gravado', true, g.production_status = 'recorded' and g.gravado);
  g := content_production(g3, 'editing');
  insert into t values ('gravado → em edição mantém gravado', true, g.production_status = 'editing' and g.gravado);
  insert into t values ('em edição cria tarefa pela automação', true, exists (select 1 from tasks where rule_id = rid and content_id = g3 and status = 'todo' and assignee_id = u_con));
  g := content_production(g3, 'ready');
  insert into t values ('em edição → pronto fecha a tarefa', true, g.production_status = 'ready' and (select status from tasks where rule_id = rid and content_id = g3) = 'done');
  begin perform content_production(g3, 'recorded'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pronto → gravado não existe (22023)', true, st = '22023');
  begin perform content_production(g4, 'cancelled'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não cancela (42501)', true, st = '42501');
  begin perform content_production(g4, 'editing'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('por gravar → em edição não existe (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform content_production(g3, 'editing'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('reviewer não muda produção (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  insert into t values ('viewer vê o calendário', true, jsonb_array_length(calendar_range('numeiro', today - 3, today + 3)->'contents') > 0);
  begin perform content_production(g4, 'scheduled'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não agenda (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  g := content_production(g4, 'cancelled');
  insert into t values ('manager cancela', true, g.production_status = 'cancelled');
  begin perform content_reschedule(g4, today + 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cancelado não se reagenda (22023)', true, st = '22023');
  g := content_production(g4, 'not_started');
  insert into t values ('cancelado → por gravar', true, g.production_status = 'not_started');
  insert into t values ('transições de produção no histórico', true,
    (select count(*) from content_transitions where content_id = g3 and kind = 'production') = 4);

  -- teleprompter: em edição/pronto não transitam
  s := recording_session_open('numeiro', today);
  insert into t values ('fila de hoje sem os prontos, com os por gravar de ontem', true,
    not exists (select 1 from jsonb_array_elements(s->'items') i where i->>'content_id' = g3)
    and exists (select 1 from jsonb_array_elements(s->'items') i where i->>'content_id' = g4));

  -- tarefas no calendário
  perform task_create('numeiro', jsonb_build_object('title', 'Entregar capa', 'due_at', (today + 1)::timestamp + interval '10 hours'));
  insert into t values ('tarefas com prazo aparecem no dia', true,
    exists (select 1 from jsonb_array_elements(calendar_range('numeiro', today, today + 2)->'tasks') x where x->>'title' = 'Entregar capa'));

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform calendar_range('numeiro', today, today + 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê o calendário de A (42501)', true, st = '42501');
  begin perform content_reschedule(g4, today + 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não reagenda guião de A (42501)', true, st = '42501');
  begin perform content_production(g4, 'scheduled'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não mexe na produção de A (42501)', true, st = '42501');
  j := calendar_range('ws_test_b', today, today + 7);
  insert into t values ('calendário de B só com o de B', true, jsonb_array_length(j->'contents') = 1 and j->'contents'->0->>'id' = gb);
  execute 'reset role';

  -- código de equipa
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código vê o calendário', true, jsonb_array_length(calendar_range('numeiro', today, today + 3, tok)->'contents') >= 2);
  insert into t values ('código não pode reagendar (can)', true, not (calendar_range('numeiro', today, today + 3, tok)->'can'->>'schedule')::boolean);
  begin perform content_reschedule(g2, today + 4, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não reagenda (42501)', true, st = '42501');
  begin perform content_production(g2, 'editing', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não passa a em edição (22023 ou 42501)', true, st in ('22023','42501'));
  g := content_production(g2, 'recorded', tok);
  insert into t values ('código continua a marcar gravado', true, g.production_status = 'recorded');
  g := content_production(g2, 'not_started', tok);
  insert into t values ('código continua a desfazer gravado', true, g.production_status = 'not_started');
  begin perform calendar_range('ws_test_b', today, today + 3, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não vê B (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
