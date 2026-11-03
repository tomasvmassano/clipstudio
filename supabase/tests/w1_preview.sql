-- supabase/tests/w1_preview.sql : navegar como papel/pessoa, só leitura e avaliado no servidor (W1-17, BIZ-07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  j jsonb; st text; n int; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pv_b', 'Preview B', 'pvb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'pv-adm@test.invalid'),(u_view,'pv-view@test.invalid'),(u_con,'pv-con@test.invalid'),(u_b,'pv-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_view, 'client_staff', 'viewer'),
    ('numeiro', u_con, 'client_staff', 'contributor'), ('ws_pv_b', u_adm, 'client_staff', 'workspace_admin'), ('ws_pv_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason, created_by) values ('numeiro', u_view, 'sources.read', 'deny', 'teste', u_adm);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);

  insert into t values ('sem pré-visualização: admin edita', true, authorize('scripts.edit', 'numeiro') and authorize('permissions.manage', 'numeiro'));
  j := access_preview_start('numeiro', null, 'contributor');
  insert into t values ('começa como papel, 30 min, com as capacidades do papel', true,
    j->>'kind' = 'role' and j->>'label' = 'contributor' and (j->'capabilities') ? 'scripts.create' and not (j->'capabilities') ? 'scripts.approve'
    and (j->>'expires_at')::timestamptz between now() + interval '29 minutes' and now() + interval '31 minutes');
  insert into t values ('lê o que o papel lê', true, authorize('scripts.read', 'numeiro') and authorize('tasks.read', 'numeiro'));
  insert into t values ('não escreve, mesmo o que o papel pode', true, not authorize('scripts.create', 'numeiro') and not authorize('tasks.work', 'numeiro'));
  insert into t values ('não lê o que o papel não lê', true, not authorize('audit.read', 'numeiro') and not authorize('costs.read', 'numeiro'));
  insert into t values ('não gere permissões durante a pré-visualização', true, not authorize('permissions.manage', 'numeiro'));
  begin perform task_create('numeiro', jsonb_build_object('title', 'x')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('escrita real recusada (42501)', true, st = '42501');
  select count(*) into n from guioes where client_id = 'numeiro';
  insert into t values ('RLS continua a mostrar os guiões', true, n > 0);
  insert into t values ('outro cliente não é afetado', true, authorize('scripts.edit', 'ws_pv_b'));
  j := access_preview_mine();
  insert into t values ('as minhas pré-visualizações', true, jsonb_array_length(j) = 1 and j->0->>'workspace_id' = 'numeiro');

  -- trocar para uma pessoa: as negações dela contam
  j := access_preview_start('numeiro', u_view, null);
  insert into t values ('como pessoa: papel e negação dela', true,
    j->>'kind' = 'user' and j->>'role' = 'viewer' and (j->'capabilities') ? 'scripts.read' and not (j->'capabilities') ? 'sources.read');
  insert into t values ('como pessoa: lê scripts, não lê fontes negadas', true, authorize('scripts.read', 'numeiro') and not authorize('sources.read', 'numeiro'));
  execute 'reset role';
  insert into t values ('uma só pré-visualização por cliente', true, (select count(*) from access_previews where user_id = u_adm) = 1);
  execute 'set local role authenticated';

  -- quem é simulado não é afetado; os outros também não
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  insert into t values ('o colaborador continua a escrever', true, authorize('scripts.create', 'numeiro'));
  begin perform access_preview_start('numeiro', null, 'viewer'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem não gere permissões não começa (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform access_preview_start('numeiro', null, 'viewer'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não começa no numeiro (42501)', true, st = '42501');
  begin perform access_preview_start('ws_pv_b', u_view, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não pré-visualiza pessoa de outro cliente (22023)', true, st = '22023');

  -- validações e saída
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform access_preview_start('numeiro', null, 'deus'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('papel desconhecido (22023)', true, st = '22023');
  begin perform access_preview_start('numeiro', u_adm, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se pré-visualiza a si próprio (22023)', true, st = '22023');
  perform access_preview_stop('numeiro');
  insert into t values ('sair devolve tudo', true, authorize('scripts.edit', 'numeiro') and authorize('permissions.manage', 'numeiro'));
  perform access_preview_stop('numeiro');   -- repetir não falha
  execute 'reset role';
  insert into access_previews (user_id, workspace_id, target_role, target_label, started_at, expires_at)
  values (u_adm, 'numeiro', 'viewer', 'viewer', now() - interval '40 minutes', now() - interval '10 minutes');
  execute 'set local role authenticated';
  insert into t values ('expirada não estreita', true, authorize('scripts.edit', 'numeiro'));
  j := access_preview_mine();
  insert into t values ('expirada sai da lista', true, jsonb_array_length(j) = 0);
  execute 'reset role';
  insert into t values ('auditado: começou e saiu', true,
    (select count(*) from audit_events where actor_user_id = u_adm and action = 'access.preview_started') = 2
    and exists (select 1 from audit_events where actor_user_id = u_adm and action = 'access.preview_stopped'));
  insert into t values ('tabela fechada', true, not has_table_privilege('authenticated', 'public.access_previews', 'select'));
  insert into t values ('base sem pré-visualização igual para outro utilizador', true,
    _authorize('scripts.create', 'numeiro', u_con) = _authorize_base('scripts.create', 'numeiro', u_con));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
