-- supabase/tests/w3_templates.sql : templates, checklists e carga (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g text := 'numeiro-2026-10-28-07'; gb text := 'ws_test_b-2026-10-28-01';
  gn int; gd date; j jsonb; tp uuid; tpb uuid; n0 int; item uuid; ids uuid[];
  st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_test_b', 'Cliente B (teste)', 'clienteb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_test_b', '2026-10-28', 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_mgr,'t-mgr@test.invalid',now(),'authenticated','authenticated'),(u_con,'t-con@test.invalid',now(),'authenticated','authenticated'),
   (u_view,'t-view@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-b@test.invalid',now(),'authenticated','authenticated'),
   (u_ag,'t-ag@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_con,'client_staff','contributor'),('numeiro',u_view,'client_staff','viewer'),
   ('ws_test_b',u_b,'client_staff','workspace_admin'),('numeiro',u_ag,'agency_staff','manager'),('ws_test_b',u_ag,'agency_staff','manager');
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  select n, date into gn, gd from guioes where id = g;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform template_save('numeiro', jsonb_build_object('name','x y','items',jsonb_build_array(jsonb_build_object('title','A b','depends_on',jsonb_build_array(0)))));
  st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dependência de si próprio ou futura recusada (22023)', true, st = '22023');
  begin perform template_save('numeiro', jsonb_build_object('name','x y','items',jsonb_build_array(jsonb_build_object('title','A b','assignee_id',u_b)))); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('template não atribui a outro cliente (22023)', true, st = '22023');
  j := template_save('numeiro', jsonb_build_object('name','Produção reel','items',jsonb_build_array(
         jsonb_build_object('title','Gravar guião {n}','kind','recording','offset_days',0,'hour',9,'assignee_id',u_con),
         jsonb_build_object('title','Editar guião {n}','kind','edit','offset_days',1,'hour',18,'depends_on',jsonb_build_array(0)),
         jsonb_build_object('title','Rever corte','kind','review','offset_days',2,'depends_on',jsonb_build_array(1))),
       'checklist', jsonb_build_array('Luz ok','Microfone ligado','Luz ok','  ')));
  tp := (j->>'id')::uuid;
  insert into t values ('template guardado e checklist sem repetidos nem vazios', true,
    jsonb_array_length(j->'items') = 3 and j->'checklist' = '["Luz ok","Microfone ligado"]' and j->'items'->0->>'assignee_email' = 't-con@test.invalid');

  j := template_apply(tp, g);
  insert into t values ('aplicar cria 3 tarefas e a checklist', true, (j->>'tasks_created')::int = 3 and jsonb_array_length(j->'checklist') = 2);
  insert into t values ('título com o número do guião', true, exists (select 1 from tasks where content_id = g and title = 'Gravar guião ' || gn));
  insert into t values ('prazo relativo ao dia do guião, à hora do cliente', true,
    (select (due_at at time zone 'Asia/Dubai') from tasks where content_id = g and title = 'Gravar guião ' || gn) = gd + time '09:00'
    and (select (due_at at time zone 'Asia/Dubai') from tasks where content_id = g and title = 'Editar guião ' || gn) = gd + 1 + time '18:00');
  insert into t values ('dependências ligadas pela ordem', true,
    (select count(*) from task_dependencies d join tasks x on x.id = d.task_id where x.content_id = g) = 2);
  execute 'reset role';
  insert into t values ('responsável do template é notificado', true, exists (select 1 from notifications where user_id = u_con and title = 'Nova tarefa: Gravar guião ' || gn));
  execute 'set local role authenticated';
  n0 := (select count(*) from tasks where content_id = g);
  j := template_apply(tp, g);
  insert into t values ('aplicar de novo não duplica', true, (j->>'tasks_created')::int = 0 and (select count(*) from tasks where content_id = g) = n0
    and jsonb_array_length(j->'checklist') = 2);
  insert into t values ('template conta guiões onde foi aplicado', true, (templates_list('numeiro')->0->>'applied')::int = 1);

  -- checklist
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := checklist_list(g); item := (j->0->>'id')::uuid;
  j := checklist_toggle(item, true);
  insert into t values ('colaborador marca item da checklist', true, (j->0->>'done')::boolean and j->0->>'done_label' = 't-con@test.invalid');
  j := checklist_add(g, 'Capa escolhida');
  insert into t values ('colaborador acrescenta item', true, jsonb_array_length(j) = 3);
  begin perform template_apply(tp, g); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não aplica templates (42501)', true, st = '42501');
  begin perform template_save('numeiro', '{"name":"x y"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não cria templates (42501)', true, st = '42501');
  begin perform workload('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não vê carga da equipa (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  insert into t values ('viewer lê a checklist', true, jsonb_array_length(checklist_list(g)) = 3);
  begin perform checklist_toggle(item, false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não marca (42501)', true, st = '42501');

  -- carga
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  perform workload_set_limit('numeiro', 1);
  j := workload('numeiro');
  insert into t values ('carga por pessoa com as abertas', true,
    exists (select 1 from jsonb_array_elements(j->'people') p where p->>'email' = 't-con@test.invalid' and (p->>'open')::int = 1));
  perform task_create('numeiro', jsonb_build_object('title', 'Outra para o con', 'assignee_id', u_con));
  j := workload('numeiro');
  insert into t values ('acima do limite avisa mas a tarefa foi criada', true,
    exists (select 1 from jsonb_array_elements(j->'people') p where p->>'email' = 't-con@test.invalid' and (p->>'over_limit')::boolean and (p->>'open')::int = 2));
  insert into t values ('tarefas sem responsável contadas', true, (j->>'unassigned')::int >= 2);
  begin perform workload_set_limit('numeiro', 0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('limite inválido (22023)', true, st = '22023');

  -- clonar
  begin perform template_clone(tp, 'ws_test_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager de A não clona para B sem gerir B (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := template_clone(tp, 'ws_test_b'); tpb := (j->>'id')::uuid;
  insert into t values ('agência que gere A e B clona sem responsáveis', true,
    j->>'workspace_id' = 'ws_test_b' and j->'items'->0->>'assignee_id' is null and j->>'cloned_from' is null and jsonb_array_length(j->'checklist') = 2);
  begin perform template_apply(tpb, g); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('template de B não se aplica a guião de A (42501)', true, st = '42501');

  -- cliente B
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform templates_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista templates de A (42501)', true, st = '42501');
  begin perform template_apply(tp, gb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não aplica template de A (42501)', true, st = '42501');
  begin perform checklist_list(g); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê checklist de A (42501)', true, st = '42501');
  begin perform checklist_toggle(item, false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não marca checklist de A (42501)', true, st = '42501');
  begin perform workload('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê carga de A (42501)', true, st = '42501');
  insert into t values ('B só vê os seus templates (RLS)', true, (select count(*) from task_templates) = 1 and (select count(*) from content_checklist) = 0);
  execute 'reset role';

  -- código de equipa
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  insert into t values ('código lê checklist e templates', true, jsonb_array_length(checklist_list(g, tok)) = 3 and jsonb_array_length(templates_list('numeiro', tok)) = 1);
  begin perform checklist_toggle(item, false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não marca checklist (42501)', true, st = '42501');
  begin perform template_apply(tp, g, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não aplica templates (42501)', true, st = '42501');
  execute 'reset role';

  begin delete from content_checklist where id = item; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('itens da checklist não se apagam (42501)', true, st = '42501');
  begin insert into content_checklist (workspace_id, content_id, label) values ('numeiro', gb, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('checklist de guião de B em A (23514)', true, st = '23514');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
