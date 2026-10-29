-- supabase/tests/w3_tasks.sql : tarefas, handoffs e caixa de entrada (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_con2 uuid := gen_random_uuid();
  u_view uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g text := 'numeiro-2026-10-28-02'; gb text := 'ws_test_b-2026-10-28-01';
  j jsonb; t1 uuid; t2 uuid; t3 uuid; tb uuid; rid uuid; ref uuid := gen_random_uuid(); lk int; n0 int; ev jsonb;
  st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_test_b', '2026-10-28', 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),(u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),
   (u_con2,'t-con2@test.invalid',now(),'authenticated','authenticated'),(u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),
   (u_rev,'t-rev@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_con,'client_staff','contributor'),('numeiro',u_con2,'client_staff','contributor'),
   ('numeiro',u_view,'client_staff','viewer'),('numeiro',u_rev,'client_staff','reviewer'),('ws_test_b',u_b,'client_staff','workspace_admin');
  update guioes set editorial_status = 'draft' where id = g;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- criar e atribuir
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := task_create('numeiro', jsonb_build_object('title', 'Gravar B-roll', 'assignee_id', u_con, 'priority', 'high',
                                                  'due_at', now() + interval '1 day', 'content_id', g, 'client_ref', ref));
  t1 := (j->>'id')::uuid;
  insert into t values ('manager cria tarefa com responsável, prazo e guião', true, j->>'assignee_email' = 't-con@test.invalid' and j->'content'->>'id' = g and j->>'status' = 'todo');
  j := task_create('numeiro', jsonb_build_object('title', 'Gravar B-roll', 'client_ref', ref));
  insert into t values ('mesmo client_ref não duplica', true, (j->>'id')::uuid = t1);
  begin perform task_create('numeiro', jsonb_build_object('title', 'x y', 'assignee_id', u_view)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não atribui a quem só lê (22023)', true, st = '22023');
  begin perform task_create('numeiro', jsonb_build_object('title', 'x y', 'assignee_id', u_b)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não atribui a quem é de outro cliente (22023)', true, st = '22023');
  begin perform task_create('numeiro', jsonb_build_object('title', 'x y', 'content_id', gb)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não liga a guião de outro cliente (23514)', true, st = '23514');
  j := task_create('numeiro', jsonb_build_object('title', 'Editar vídeo', 'assignee_id', u_con, 'depends_on', jsonb_build_array(t1)));
  t2 := (j->>'id')::uuid;
  insert into t values ('dependência criada', true, (j->>'open_deps')::int = 1);

  -- responsável trabalha só no que é seu
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  insert into t values ('responsável foi notificado', true, exists (select 1 from notifications where user_id = u_con and kind = 'task_assigned' and entity_id = t1::text));
  j := task_update(t1, '{"status":"doing"}');
  insert into t values ('responsável muda o estado', true, j->>'status' = 'doing');
  begin perform task_update(t1, '{"title":"Outro"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('responsável não muda o título (42501)', true, st = '42501');
  begin perform task_update(t1, '{"status":"blocked"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('bloquear exige motivo (22023)', true, st = '22023');
  j := task_update(t1, '{"status":"blocked","blocked_reason":"Falta o microfone"}');
  insert into t values ('bloqueio com motivo', true, j->>'status' = 'blocked' and j->>'blocked_reason' = 'Falta o microfone');
  begin perform task_update(t2, '{"status":"done"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não conclui com dependência aberta (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_con2, 'role','authenticated')::text, true);
  begin perform task_update(t1, '{"status":"doing"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem não é responsável não mexe (42501)', true, st = '42501');

  -- manager: notificação de bloqueio, reatribuição, conflito, dependências
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  insert into t values ('quem criou é avisado do bloqueio', true, exists (select 1 from notifications where user_id = u_mgr and kind = 'task_blocked' and entity_id = t1::text));
  lk := (task_get(t1)->>'lock_version')::int;
  begin perform task_update(t1, '{"priority":"low"}', lk - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('edição com versão antiga = PT409', true, st = 'PT409');
  perform task_update(t1, jsonb_build_object('assignee_id', u_con2), lk);
  execute 'reset role';
  insert into t values ('reatribuir avisa os dois', true,
    exists (select 1 from notifications where user_id = u_con2 and kind = 'task_assigned' and entity_id = t1::text)
    and exists (select 1 from notifications where user_id = u_con and kind = 'task_unassigned' and entity_id = t1::text));
  execute 'set local role authenticated';
  begin perform task_depend(t1, t2, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dependência circular (22023)', true, st = '22023');
  j := task_create('numeiro', jsonb_build_object('title', 'Publicar'));
  t3 := (j->>'id')::uuid;
  perform task_depend(t3, t2, true);
  insert into t values ('dependência adicionada depois', true, (task_get(t3)->>'open_deps')::int = 1);

  -- comentários e menções
  perform set_config('request.jwt.claims', json_build_object('sub', u_con2, 'role','authenticated')::text, true);
  j := task_comment(t1, 'Já tenho o microfone, @rev confirma?', array[u_rev]);
  insert into t values ('comentário fica na tarefa', true, jsonb_array_length(j->'comments_list') = 1 and j->'comments_list'->0->'mentions' = '["t-rev@test.invalid"]');
  execute 'reset role';
  insert into t values ('menção notifica o mencionado', true, exists (select 1 from notifications where user_id = u_rev and kind = 'task_mention'));
  execute 'set local role authenticated';
  begin perform task_comment(t1, 'olá', array[u_b]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não menciona quem é de outro cliente (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  insert into t values ('viewer lê tarefas', true, jsonb_array_length(tasks_list('numeiro', 'open')) >= 3);
  begin perform task_comment(t1, 'olá'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não comenta (42501)', true, st = '42501');
  begin perform task_create('numeiro', '{"title":"x y"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não cria (42501)', true, st = '42501');

  -- regras de handoff
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform task_rule_save('numeiro', jsonb_build_object('on_event','script.submitted','title','Rever','assignee_id',u_b)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('regra não atribui a outro cliente (22023)', true, st = '22023');
  begin perform task_rule_save('numeiro', '{"on_event":"script.submitted","title":"Rever","complete_on":["apagar.tudo"]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('regra com evento desconhecido (22023)', true, st = '22023');
  j := task_rule_save('numeiro', jsonb_build_object('on_event','script.submitted','complete_on',jsonb_build_array('script.approved','script.rejected'),
                                                     'kind','review','title','Rever guião {n}','assignee_id',u_rev,'due_hours',24,'priority','high'));
  rid := (j->>'id')::uuid;
  perform content_transition(g, 'in_review', null, null, null);
  select to_jsonb(x) into j from tasks x where rule_id = rid;
  insert into t values ('submeter guião cria tarefa de revisão pela regra', true,
    j->>'title' = 'Rever guião 2' and (j->>'assignee_id')::uuid = u_rev and j->>'content_id' = g and j->>'kind' = 'review' and j->>'due_at' is not null);
  execute 'reset role';
  select to_jsonb(e) into ev from domain_events e where type = 'script.submitted' and entity_id = g order by id desc limit 1;
  n0 := (select count(*) from tasks where rule_id = rid);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload) values ('numeiro', 'script.submitted', 'content', g, ev->'payload');
  insert into t values ('evento repetido não duplica a tarefa', true, (select count(*) from tasks where rule_id = rid) = n0 and n0 = 1);
  execute 'set local role authenticated';
  perform content_transition(g, 'approved', null, null, null);
  insert into t values ('aprovar fecha a tarefa de revisão', true, (select status from tasks where rule_id = rid) = 'done');
  insert into t values ('fecho automático fica no histórico', true,
    exists (select 1 from task_events e join tasks x on x.id = e.task_id where x.rule_id = rid and e.action = 'task.auto_completed' and e.actor_kind = 'system'));
  insert into t values ('regras listadas com tarefas abertas', true, (task_rules_list('numeiro')->0->>'tasks_open')::int = 0);

  -- caixa de entrada do revisor
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  j := inbox();
  insert into t values ('caixa: notificação da tarefa automática e da menção', true,
    exists (select 1 from jsonb_array_elements(j->'notifications') n where n->>'kind' = 'task_auto')
    and exists (select 1 from jsonb_array_elements(j->'notifications') n where n->>'kind' = 'task_mention'));
  insert into t values ('caixa: aprovações pendentes do cliente', true, jsonb_array_length(j->'approvals') > 0
    and not exists (select 1 from jsonb_array_elements(j->'approvals') a where a->>'workspace_id' <> 'numeiro'));
  perform notifications_read(null);
  insert into t values ('marcar lido não aprova nada', true, (select count(*) from notifications where user_id = u_rev and read_at is null) = 0
    and (select count(*) from guioes where client_id = 'numeiro' and editorial_status = 'in_review') = jsonb_array_length(j->'approvals'));

  -- membro suspenso perde acesso; tarefa aparece "sem responsável"
  execute 'reset role';
  update workspace_access set status = 'suspended' where user_id = u_con2 and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_con2, 'role','authenticated')::text, true);
  j := inbox();
  insert into t values ('suspenso não vê notificações nem tarefas do cliente', true, jsonb_array_length(j->'notifications') = 0 and jsonb_array_length(j->'tasks') = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := tasks_list('numeiro', 'unassigned');
  insert into t values ('tarefa de quem saiu aparece para reatribuir', true,
    exists (select 1 from jsonb_array_elements(j) x where (x->>'id')::uuid = t1 and (x->>'assignee_has_access')::boolean = false));
  insert into t values ('caixa do manager mostra tarefas sem dono', true, exists (select 1 from jsonb_array_elements(inbox()->'unassigned') x where (x->>'id')::uuid = t1));
  begin perform task_comment(t1, 'olá', array[u_con2]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não menciona quem perdeu acesso (22023)', true, st = '22023');

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform tasks_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista tarefas de A (42501)', true, st = '42501');
  begin perform task_get(t1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não abre tarefa de A (42501)', true, st = '42501');
  begin perform task_update(t1, '{"status":"done"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não altera tarefa de A (42501)', true, st = '42501');
  begin perform task_rules_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê regras de A (42501)', true, st = '42501');
  j := task_create('ws_test_b', '{"title":"Tarefa de B"}'); tb := (j->>'id')::uuid;
  begin perform task_depend(tb, t1, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não depende de tarefa de A (42501)', true, st = '42501');
  insert into t values ('B só vê as suas (RLS)', true, (select count(*) from tasks) = 1 and (select count(*) from notifications) = 0);
  insert into t values ('caixa de B sem nada de A', true, not exists (select 1 from jsonb_array_elements(inbox()->'approvals') a where a->>'workspace_id' = 'numeiro'));
  execute 'reset role';

  -- código de equipa: só lê
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código lê tarefas', true, jsonb_array_length(tasks_list('numeiro', 'open', null, tok)) >= 2);
  begin perform task_create('numeiro', '{"title":"x y"}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não cria tarefas (42501)', true, st = '42501');
  begin perform inbox(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não tem caixa de entrada (42501)', true, st = '42501');
  begin perform tasks_list('ws_test_b', 'open', null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não lê B (42501)', true, st = '42501');
  execute 'reset role';

  -- integridade
  begin delete from tasks where id = t3; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tarefas não se apagam (42501)', true, st = '42501');
  begin update task_comments set body = 'x' where task_id = t1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários são append-only (42501)', true, st = '42501');
  begin update tasks set workspace_id = 'ws_test_b' where id = t3; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace da tarefa não muda (42501)', true, st = '42501');
  insert into t values ('histórico regista criação e mudanças', true,
    (select count(*) from task_events where task_id = t1 and action in ('task.created','task.updated','task.commented')) >= 5);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
