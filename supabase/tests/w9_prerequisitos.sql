-- supabase/tests/w9_prerequisitos.sql : pré-requisitos configuráveis nas transições de produção (FR-17-05; ADR-0047).
-- Rollback no fim. Negativos exigem o SQLSTATE certo.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_ed uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g1 text := 'numeiro-2026-10-28-21'; g2 text := 'numeiro-2026-10-28-22'; g3 text := 'numeiro-2026-10-28-23';
  g guioes; j jsonb; st text; msg text; det text; tid uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pr_b', 'Pré B', 'prb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'p-adm@test.invalid'),(u_mgr,'p-mgr@test.invalid'),(u_b,'p-b@test.invalid'),(u_ed,'p-ed@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_mgr, 'client_staff', 'manager'),
    ('numeiro', u_ed, 'client_staff', 'contributor'), ('ws_pr_b', u_b, 'client_staff', 'workspace_admin');
  update guioes set owner_id = u_ed where id = g1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  insert into t values ('tabela fechada à API', true,
    not has_table_privilege('authenticated', 'public.workflow_prerequisites', 'select') and not has_table_privilege('anon', 'public.workflow_prerequisites', 'select'));

  execute 'set local role authenticated';
  -- sem regras: como hoje
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  g := content_production(g3, 'scheduled');
  insert into t values ('sem regras: agenda guião em revisão', true, g.production_status = 'scheduled');
  j := workflow_prereqs('numeiro');
  insert into t values ('matriz: 9 células, todas desligadas', true,
    jsonb_array_length(j->'rules') = 9 and not exists (select 1 from jsonb_array_elements(j->'rules') x where (x->>'enabled')::boolean)
    and not (j->'can'->>'manage')::boolean);
  begin perform workflow_prereq_set('numeiro', 'production.scheduled', 'script_approved', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager não configura (42501)', true, st = '42501');

  -- admin liga regras
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := workflow_prereq_set('numeiro', 'production.scheduled', 'script_approved', true);
  insert into t values ('admin liga agendar × guião aprovado', true,
    exists (select 1 from jsonb_array_elements(j->'rules') x where x->>'transition' = 'production.scheduled' and x->>'requirement' = 'script_approved' and (x->>'enabled')::boolean));
  perform workflow_prereq_set('numeiro', 'production.recorded', 'script_approved', true);
  perform workflow_prereq_set('numeiro', 'production.recorded', 'no_blocked_tasks', true);
  perform workflow_prereq_set('numeiro', 'production.ready', 'video_approved', true);
  begin perform workflow_prereq_set('numeiro', 'production.scheduled', 'video_approved', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('condição que não se aplica à transição (22023)', true, st = '22023');
  begin perform workflow_prereq_set('numeiro', 'production.published', 'script_approved', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('transição desconhecida (22023)', true, st = '22023');

  -- manager esbarra nas regras
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  begin perform content_production(g1, 'scheduled'); st := 'none';
  exception when others then get stacked diagnostics msg = message_text, det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('agendar sem aprovação recusado com causa e responsável', true,
    st = '22023' and msg = 'pre_requisito_em_falta' and det like '%não está aprovado (está em revisão)%' and det like '%p-ed@test.invalid%');
  insert into t values ('recusa não muda nada', true, (select production_status from guioes where id = g1) = 'not_started');
  begin perform content_production(g1, 'recorded'); st := 'none'; exception when others then get stacked diagnostics msg = message_text; st := sqlstate; end;
  insert into t values ('gravar sem aprovação recusado (regra antiga, mesma célula)', true, st = '22023' and msg = 'pre_requisito_em_falta');
  insert into t values ('gravado × aprovado vive em require_approval_to_record', true,
    (select x->>'enabled' from jsonb_array_elements(workflow_prereqs('numeiro')->'rules') x
      where x->>'transition' = 'production.recorded' and x->>'requirement' = 'script_approved')::boolean);
  j := workflow_prereqs('numeiro', g1);
  insert into t values ('o que falta a um guião, por transição', true,
    jsonb_array_length(j->'missing'->'scheduled') = 1 and jsonb_array_length(j->'missing'->'recorded') = 1 and jsonb_array_length(j->'missing'->'editing') = 0);

  g := content_transition(g1, 'approved');
  tid := (task_create('numeiro', jsonb_build_object('title', 'Falta o microfone', 'content_id', g1, 'assignee_id', u_ed))->>'id')::uuid;
  perform task_update(tid, jsonb_build_object('status', 'blocked', 'blocked_reason', 'Microfone avariado'));
  g := content_production(g1, 'scheduled');
  insert into t values ('aprovado: já agenda', true, g.production_status = 'scheduled');
  begin perform content_production(g1, 'recorded'); st := 'none';
  exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('tarefa bloqueada impede gravar, com o responsável', true, st = '22023' and det like '%1 tarefa(s) do guião bloqueada(s)%' and det like '%p-ed@test.invalid%');
  perform task_update(tid, jsonb_build_object('status', 'doing'));
  g := content_production(g1, 'recorded');
  insert into t values ('desbloqueada: grava', true, g.production_status = 'recorded');
  g := content_production(g1, 'recorded');
  insert into t values ('repetir a mesma transição é idempotente', true, g.production_status = 'recorded');
  g := content_production(g1, 'editing');
  begin perform content_production(g1, 'ready'); st := 'none';
  exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('pronto sem vídeo aprovado recusado', true, st = '22023' and det like '%ainda não há vídeo%');
  g := content_production(g1, 'recorded');
  insert into t values ('voltar atrás nunca é bloqueado', true, g.production_status = 'recorded');

  -- outro cliente e código
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform workflow_prereq_set('numeiro', 'production.ready', 'video_approved', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não configura A (42501)', true, st = '42501');
  begin perform workflow_prereqs('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê regras de A (42501)', true, st = '42501');
  j := workflow_prereqs('ws_pr_b');
  insert into t values ('regras de A não valem em B', true, not exists (select 1 from jsonb_array_elements(j->'rules') x where (x->>'enabled')::boolean));
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := workflow_prereqs('numeiro', null, tok);
  insert into t values ('código lê as regras do seu cliente', true, jsonb_array_length(j->'rules') = 9);
  begin perform workflow_prereq_set('numeiro', 'production.ready', 'video_approved', false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não configura (42501)', true, st = '42501');
  begin perform content_production(g2, 'recorded', tok); st := 'none'; exception when others then get stacked diagnostics msg = message_text; st := sqlstate; end;
  insert into t values ('código também esbarra na regra', true, st = '22023' and msg = 'pre_requisito_em_falta');
  execute 'reset role';

  insert into t values ('configuração auditada com antes e depois', true,
    exists (select 1 from audit_events where action = 'workflow.prerequisite_set' and actor_user_id = u_adm
            and entity_id = 'production.scheduled:script_approved' and before->>'enabled' = 'false' and after->>'enabled' = 'true'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
