-- supabase/tests/w1_clients.sql : criar e gerir clientes e a equipa de cada cliente (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_stf uuid := gen_random_uuid(); u_out uuid := gen_random_uuid();
  u_co uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cm uuid := gen_random_uuid(); u_cv uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  a text; b text; c2 text; j jsonb; st text; t1 uuid; t2 uuid; inv uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'c-own@test.invalid'),(u_adm,'c-adm@test.invalid'),(u_stf,'c-stf@test.invalid'),(u_out,'c-out@test.invalid'),
    (u_co,'c-co@test.invalid'),(u_ca,'c-ca@test.invalid'),(u_cm,'c-cm@test.invalid'),(u_cv,'c-cv@test.invalid'),(u_b,'c-b@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_adm, 'agency_admin'), (org, u_stf, 'agency_member');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- criar
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := workspace_create('Clínica Teste Ç', '@Clinica.Teste', 'Europe/Lisbon', 'aed'); a := j->>'id';
  insert into t values ('dono cria cliente com id legível, handle e moeda normalizados', true,
    a = 'clinica-teste-c' and (select handle = 'clinica.teste' and currency = 'AED' and timezone = 'Europe/Lisbon' and status = 'active' from clients where id = a));
  insert into t values ('mesmo nome leva sufixo', true, workspace_create('Clínica Teste Ç')->>'id' = 'clinica-teste-c-2');
  begin perform workspace_create('X'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('nome curto recusado (22023)', true, st = '22023');
  begin perform workspace_create('Bom nome', null, 'Marte/Olympus'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('fuso inexistente recusado (22023)', true, st = '22023');
  begin perform workspace_create('Bom nome', 'com espaço'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('handle inválido recusado (22023)', true, st = '22023');
  insert into t values ('dono entra logo no cliente novo', true, exists (select 1 from jsonb_array_elements(my_context()->'workspaces') w where w->>'id' = a));
  insert into t values ('contexto traz as capacidades da agência', true,
    (select bool_or(x->'capabilities' ? 'workspaces.create') from jsonb_array_elements(my_context()->'agency') x));

  -- estrutura para copiar: configuração com voz privada, template e automação com responsável
  execute 'reset role';
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    (a, u_co, 'client_staff', 'workspace_owner'), (a, u_ca, 'client_staff', 'workspace_admin'), (a, u_cm, 'client_staff', 'manager'),
    (a, u_cv, 'client_staff', 'viewer');
  insert into agent_config_versions (workspace_id, version_no, status, config, validation, activated_at)
    values (a, 1, 'active', '{"language":"pt-PT","voice":"Voz privada de A","lexicon":["segredo"],"news_beats":["x"],"guardrails":["Regra"],"formats":{"f":{"share":1,"min":0.5,"max":1,"palavras":[50,100]}},"pipeline":{"scripts_per_day":3,"hooks_per_slot":3,"critic_threshold":7,"concurrency":1},"budget_eur_day":9,"schedule":{"enabled":true,"time":"19:00"}}',
            '{"ok":true}', now());
  execute 'set local role authenticated';
  perform template_save(a, jsonb_build_object('name','Produção A','items',jsonb_build_array(jsonb_build_object('title','Editar vídeo','assignee_id',u_cm))));
  perform task_rule_save(a, jsonb_build_object('on_event','script.submitted','title','Rever guião','assignee_id',u_cm));
  j := workspace_create('Cliente Novo', null, 'Asia/Dubai', 'EUR', a); b := j->>'id';
  insert into t values ('copiar traz configuração, templates e automações', true,
    (j->'copied'->>'agentes')::boolean and (j->'copied'->>'templates')::int = 1 and (j->'copied'->>'automacoes')::int = 1);
  execute 'reset role';
  insert into t values ('configuração copiada sem voz, léxico, notícias nem orçamento, e em rascunho', true,
    (select status = 'draft' and config->>'voice' = '' and not config ? 'lexicon' and not config ? 'news_beats' and not config ? 'budget_eur_day'
            and not (config->'schedule'->>'enabled')::boolean and not (validation->>'ok')::boolean from agent_config_versions where workspace_id = b));
  insert into t values ('template e automação copiados sem pessoas de A', true,
    (select count(*) from task_templates where workspace_id = b) = 1
    and not exists (select 1 from task_templates x, jsonb_array_elements(x.items) i where x.workspace_id = b and i->>'assignee_id' is not null)
    and (select assignee_id is null from task_rules where workspace_id = b));
  insert into t values ('criação fica na auditoria', true, exists (select 1 from audit_events where action = 'workspace.created' and entity_id = b and after->>'copied_from' = a));
  execute 'set local role authenticated';

  -- quem não pode criar
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform workspace_create('Do admin'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência não cria (42501)', true, st = '42501');
  begin j := workspaces_list(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência sem clientes atribuídos não vê nenhum', true, st = 'none' and jsonb_array_length(j->'clients') = 0 and not (j->'can'->>'create')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform workspace_create('Do cliente'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente não cria clientes (42501)', true, st = '42501');
  begin perform workspaces_list(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não lista clientes (42501)', true, st = '42501');
  begin perform workspace_create('Cópia', null, 'Asia/Dubai', 'EUR', a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não cria cópias do seu workspace (42501)', true, st = '42501');

  -- lista do dono e atribuição de staff
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := workspaces_list();
  insert into t values ('dono vê os clientes novos e o staff da agência', true,
    exists (select 1 from jsonb_array_elements(j->'clients') x where x->>'id' = a and (x->>'members')::int = 4)
    and exists (select 1 from jsonb_array_elements(j->'agency_staff') x where (x->>'user_id')::uuid = u_stf));
  begin perform agency_staff_assign(a, u_out, 'manager'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('só staff da agência é atribuível (22023)', true, st = '22023');
  begin perform agency_staff_assign(a, u_ca, 'manager'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não transforma equipa do cliente em staff', true, st = '22023');
  perform agency_staff_assign(a, u_adm, 'manager');
  perform agency_staff_assign(a, u_stf, 'workspace_owner');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := workspaces_list();
  insert into t values ('admin da agência passa a ver só o cliente atribuído', true,
    jsonb_array_length(j->'clients') = 1 and j->'clients'->0->>'id' = a and j->'agency_staff' = 'null'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform agency_staff_assign(a, u_stf, 'viewer'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não atribui staff da agência (42501)', true, st = '42501');

  -- editar
  j := workspace_update(a, '{"name":"Clínica Nova","timezone":"Asia/Dubai","require_approval_to_record":true}');
  insert into t values ('admin do cliente edita os dados gerais', true, j->>'name' = 'Clínica Nova' and (j->>'require_approval_to_record')::boolean);
  execute 'reset role';
  insert into t values ('edição com antes e depois na auditoria', true,
    exists (select 1 from audit_events where action = 'workspace.updated' and entity_id = a and before->>'name' = 'Clínica Teste Ç' and after->>'name' = 'Clínica Nova'));
  execute 'set local role authenticated';
  begin perform workspace_update(a, '{"organization_id":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo desconhecido recusado (22023)', true, st = '22023');
  begin perform workspace_update(b, '{"name":"Roubado"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de A não edita B (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cv, 'role','authenticated')::text, true);
  begin perform workspace_update(a, '{"name":"Leitor"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não edita (42501)', true, st = '42501');

  -- equipa
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := member_update(a, u_cv, '{"role":"contributor","job_title":"Editor"}');
  insert into t values ('admin promove até ao seu nível', true, j->>'role' = 'contributor' and j->>'job_title' = 'Editor');
  begin perform member_update(a, u_cv, '{"role":"workspace_owner"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não promove acima do seu nível (42501)', true, st = '42501');
  begin perform member_update(a, u_co, '{"status":"suspended"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não mexe em quem está acima (42501)', true, st = '42501');
  begin perform member_update(a, u_ca, '{"role":"viewer"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não mexe em si próprio (42501)', true, st = '42501');
  begin perform member_update(a, u_adm, '{"role":"viewer"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente não mexe em staff da agência (42501)', true, st = '42501');
  begin perform member_update(a, u_cv, '{"workspace_id":"b"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo de membro desconhecido recusado (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cm, 'role','authenticated')::text, true);
  begin perform member_update(a, u_cv, '{"role":"viewer"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não gere a equipa (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_stf, 'role','authenticated')::text, true);
  begin perform member_update(a, u_co, '{"role":"workspace_admin"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('último dono do cliente não perde o papel (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform member_update(a, u_cv, '{"role":"viewer"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem é de fora não gere A (42501)', true, st = '42501');

  -- suspender corta o acesso; reativar devolve
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  perform member_update(a, u_cv, '{"status":"suspended"}');
  execute 'reset role';
  insert into t values ('suspenso perde o acesso', true, not _authorize('scripts.read', a, u_cv));
  execute 'set local role authenticated';
  perform member_update(a, u_cv, '{"status":"active"}');
  execute 'reset role';
  insert into t values ('reativado volta a ter acesso', true, _authorize('scripts.read', a, u_cv));
  execute 'set local role authenticated';

  -- remover com tarefas abertas
  execute 'reset role';
  insert into tasks (workspace_id, title, assignee_id, created_kind) values (a, 'Tarefa um', u_cm, 'user') returning id into t1;
  insert into tasks (workspace_id, title, assignee_id, created_kind) values (a, 'Tarefa dois', u_cm, 'user') returning id into t2;
  insert into tasks (workspace_id, title, assignee_id, status, created_kind) values (a, 'Feita', u_cm, 'done', 'user');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform member_remove(a, u_cm, u_out); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('reatribuir a quem não tem acesso recusado (22023)', true, st = '22023');
  j := member_remove(a, u_cm, u_cv);
  insert into t values ('remover passa as tarefas abertas', true, (j->>'tasks_reassigned')::int = 2);
  execute 'reset role';
  insert into t values ('tarefas abertas com o novo responsável e histórico', true,
    (select count(*) from tasks where id in (t1, t2) and assignee_id = u_cv) = 2
    and (select count(*) from task_events where task_id in (t1, t2) and action = 'reassigned') = 2
    and exists (select 1 from tasks where workspace_id = a and title = 'Feita' and assignee_id = u_cm));
  insert into t values ('quem recebe é notificado', true, (select count(*) from notifications where user_id = u_cv and kind = 'task_assigned') = 2);
  insert into t values ('removido perde o acesso mas fica no histórico', true,
    not _authorize('tasks.read', a, u_cm) and (select status from workspace_access where workspace_id = a and user_id = u_cm) = 'removed'
    and exists (select 1 from audit_events where action = 'member.removed' and entity_id = u_cm::text));
  execute 'set local role authenticated';
  insert into t values ('removido sai da lista da equipa', true,
    not exists (select 1 from jsonb_array_elements(workspace_team(a)->'members') m where (m->>'user_id')::uuid = u_cm));
  begin perform member_remove(a, u_cm); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('remover duas vezes dá não encontrado', true, st = 'P0002');
  inv := invite_member(a, 'c-cm@test.invalid', 'reviewer');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cm, 'role','authenticated')::text, true);
  perform accept_invitations();
  execute 'reset role';
  insert into t values ('novo convite reativa quem foi removido com o papel do convite', true,
    (select status = 'active' and workspace_role = 'reviewer' from workspace_access where workspace_id = a and user_id = u_cm));
  execute 'set local role authenticated';

  -- arquivar e recuperar
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform workspace_archive(a, 'fim do contrato'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente não arquiva (42501)', true, st = '42501');
  execute 'reset role';
  perform _agent_enqueue(a, 'scouts', 'arquivo-teste', now(), '{"kind":"system"}', '{}');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform workspace_archive(a, ''); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('arquivar pede motivo (22023)', true, st = '22023');
  j := workspace_archive(a, 'fim do contrato');
  insert into t values ('arquivar cancela execuções em fila', true, j->>'status' = 'archived' and (j->>'jobs_cancelled')::int = 1);
  insert into t values ('arquivado continua na lista do dono', true,
    exists (select 1 from jsonb_array_elements(workspaces_list()->'clients') x where x->>'id' = a and x->>'status' = 'archived'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  insert into t values ('equipa do cliente arquivado perde o acesso', true, not authorize('scripts.read', a)
    and not exists (select 1 from jsonb_array_elements(my_context()->'workspaces') w where w->>'id' = a));
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  insert into t values ('admin da agência não vê arquivados', true, jsonb_array_length(workspaces_list()->'clients') = 0);
  begin perform workspace_restore(a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência não recupera (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform workspace_restore(a);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  insert into t values ('recuperar devolve o acesso', true, authorize('scripts.read', a));
  execute 'reset role';
  execute 'set local role anon';
  begin perform workspace_create('Anónimo'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não cria (42501)', true, st = '42501');
  begin perform workspaces_list(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não lista (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
