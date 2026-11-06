-- supabase/tests/w10_custos.sql : consumo de IA por agente, modelo, execução e cliente (FR-10-01), vista do cliente e da agência,
-- exportação CSV com costs.export (fail closed), matriz de permissões e negativos entre clientes. Rollback no fim (raise).
-- Números conhecidos (janela de 7 dias): A atual = j1 1,20 + j2 0,30 + j3 desconhecido (falhou); A anterior = j4 0,50; fora = j5 9,99.
-- B atual = jb 4,00. agent_log de A (atual): escritor/opus 0,70 + 0,40, crítico/sonnet 0,10, crítico sem custo (só tokens), ensaio 5,00 (ignorado).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid(); u_ag2 uuid := gen_random_uuid();
  tok text := 'cu-a-team-code-0123456789abcdef';
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; cva uuid; cvb uuid;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('cu_a', 'Custos A', 'cua', org, 'Asia/Dubai'), ('cu_b', 'Custos B', 'cub', org, 'Europe/Lisbon');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'cu-own@test.invalid'),(u_ag,'cu-ag@test.invalid'),(u_adm,'cu-adm@test.invalid'),(u_v,'cu-v@test.invalid'),
    (u_b,'cu-b@test.invalid'),(u_ag2,'cu-ag2@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_ag2, 'agency_admin');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('cu_a', u_ag, 'agency_staff', 'manager'), ('cu_a', u_adm, 'client_staff', 'workspace_admin'), ('cu_a', u_v, 'client_staff', 'viewer'),
    ('cu_b', u_b, 'client_staff', 'workspace_admin'), ('cu_a', u_ag2, 'agency_staff', 'workspace_admin'), ('cu_b', u_ag2, 'agency_staff', 'manager');
  insert into studio_tokens (token, client_id, label) values (tok, 'cu_a', 'Equipa CU');
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('costs.content', org, 'cu_a', 'all'), ('costs.content', org, 'cu_b', 'all');

  insert into agent_config_versions (workspace_id, version_no, status, config, created_label)
  select w, 1, 'draft', config, 'fixture' from agent_config_versions, unnest(array['cu_a','cu_b']) w where workspace_id = 'numeiro' limit 2;
  cva := (select id from agent_config_versions where workspace_id = 'cu_a'); cvb := (select id from agent_config_versions where workspace_id = 'cu_b');
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, requested_label, cost_eur, tokens_in, tokens_out, started_at, finished_at, run_id) values
    ('cu_a', 'daily_pipeline', 'cu-j1', 'succeeded', cva, 'user', 'segredo@agencia.invalid', 1.2, 1000, 500, now() - interval '1 day 1 hour', now() - interval '1 day', 'cu-run1'),
    ('cu_a', 'scouts', 'cu-j2', 'succeeded', cva, 'system', null, 0.3, 200, 100, null, now() - interval '2 days', 'cu-run2'),
    ('cu_a', 'daily_pipeline', 'cu-j3', 'failed', cva, 'system', null, null, null, null, null, now() - interval '3 days', null),
    ('cu_a', 'daily_pipeline', 'cu-j4', 'succeeded', cva, 'system', null, 0.5, 10, 10, null, now() - interval '10 days', null),
    ('cu_a', 'daily_pipeline', 'cu-j5', 'succeeded', cva, 'system', null, 9.99, 10, 10, null, now() - interval '40 days', null),
    ('cu_a', 'daily_pipeline', 'cu-j6', 'running', cva, 'system', null, 7.77, 10, 10, now(), null, null),
    ('cu_b', 'daily_pipeline', 'cu-jb', 'succeeded', cvb, 'system', null, 4.0, 10, 10, null, now() - interval '1 day', 'cu-runb');
  insert into agent_log (run_id, client_id, slot, agent, model, cost_eur, tokens_in, tokens_out, simulated, created_at) values
    ('cu-run1', 'cu_a', 0, 'writer', 'claude-opus-5-5', 0.7, 300, 200, false, now() - interval '1 day'),
    ('cu-run1', 'cu_a', 1, 'writer', 'claude-opus-5-5', 0.4, 300, 200, false, now() - interval '1 day'),
    ('cu-run1', 'cu_a', 0, 'critic', 'claude-sonnet-5-5', 0.1, 50, 20, false, now() - interval '1 day'),
    ('cu-run1', 'cu_a', 1, 'critic', 'claude-sonnet-5-5', null, 50, 20, false, now() - interval '1 day'),
    ('cu-run1', 'cu_a', 0, 'writer', 'claude-opus-5-5', 5.0, 1, 1, true, now() - interval '1 day'),
    ('cu-old', 'cu_a', 0, 'writer', 'claude-opus-5-5', 0.25, 1, 1, false, now() - interval '9 days'),
    ('cu-run1', 'cu_a', 0, 'writer', null, null, null, null, false, now() - interval '1 day'),
    ('cu-runb', 'cu_b', 0, 'segredo_b', 'claude-haiku-5-5', 3.0, 1, 1, false, now() - interval '1 day');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ═════ cliente: admin de A ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := costs_ai_usage('cu_a', 7);
  insert into t values ('admin A: âmbito do cliente, 7 dias, fuso do cliente', true,
    j->>'scope' = 'workspace' and (j->>'days')::int = 7 and j->>'timezone' = 'Asia/Dubai' and (j->>'to')::date = (now() at time zone 'Asia/Dubai')::date);
  insert into t values ('total = execuções terminadas com custo conhecido (1,50); em curso e fora da janela não contam', true, (j->'totals'->>'cost')::numeric = 1.5);
  insert into t values ('período anterior 0,50 com 1 execução', true, (j->'totals'->>'prev_cost')::numeric = 0.5 and (j->'totals'->>'prev_jobs')::int = 1);
  insert into t values ('3 execuções, 1 sem custo conhecido, 1 falhada', true,
    (j->'totals'->>'jobs')::int = 3 and (j->'totals'->>'jobs_unknown')::int = 1 and (j->'totals'->>'jobs_failed')::int = 1);
  insert into t values ('tokens das execuções', true, (j->'totals'->>'tokens_in')::int = 1200 and (j->'totals'->>'tokens_out')::int = 600);
  insert into t values ('só A na resposta', true, jsonb_array_length(j->'workspaces') = 1 and j->'workspaces'->0->>'id' = 'cu_a');
  insert into t values ('estimativa rotulada, sem custo confirmado', true,
    j->'basis'->>'kind' = 'estimated' and not (j->'basis'->>'confirmed_available')::boolean and jsonb_array_length(j->'basis'->'prices') >= 3);
  insert into t values ('por agente: Escritor 1,10 (ensaio ignorado), 2 chamadas; anterior 0,25', true,
    (select (x->>'cost')::numeric = 1.1 and (x->>'calls')::int = 2 and (x->>'prev_cost')::numeric = 0.25 and x->>'name' = 'Escritor'
       from jsonb_array_elements(j->'agents') x where x->>'key' = 'writer'));
  insert into t values ('por agente: Crítico 0,10 com 1 chamada sem custo (nunca zero escondido)', true,
    (select (x->>'cost')::numeric = 0.1 and (x->>'calls')::int = 2 and (x->>'calls_unknown')::int = 1 from jsonb_array_elements(j->'agents') x where x->>'key' = 'critic'));
  insert into t values ('por modelo: Opus 1,10 e Sonnet 0,10; linhas sem tokens nem custo ignoradas', true,
    (select (x->>'cost')::numeric = 1.1 and x->>'name' = 'Claude Opus 5.5' from jsonb_array_elements(j->'models') x where x->>'key' = 'claude-opus-5-5')
    and (select (x->>'cost')::numeric = 0.1 from jsonb_array_elements(j->'models') x where x->>'key' = 'claude-sonnet-5-5')
    and not exists (select 1 from jsonb_array_elements(j->'models') x where x->>'key' = 'sem modelo'));
  insert into t values ('execuções mais caras primeiro, desconhecidas no fim, com duração e custo das chamadas', true,
    j->'runs'->0->>'kind' = 'daily_pipeline' and (j->'runs'->0->>'cost_eur')::numeric = 1.2 and (j->'runs'->0->>'duration_s')::int = 3600
    and (j->'runs'->0->>'calls_cost')::numeric = 1.2 and not (j->'runs'->2->>'cost_known')::boolean and jsonb_array_length(j->'runs') = 3);
  insert into t values ('execuções sem quem pediu (email da agência)', true, position('segredo@agencia' in j::text) = 0 and not (j->'runs'->0 ? 'requested_label'));
  insert into t values ('nada de B na vista de A', true, position('segredo_b' in j::text) = 0 and position('cu_b' in j::text) = 0);
  insert into t values ('admin A pode exportar', true, (j->>'can_export')::boolean);
  j := costs_ai_usage('cu_a', null, current_date - 30, current_date);
  insert into t values ('período personalizado de 31 dias inclui o anterior de 7', true, (j->>'days')::int = 31 and (j->'totals'->>'cost')::numeric = 2.0);
  begin perform costs_ai_usage('cu_a', null, current_date, current_date - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('período invertido recusado', true, st = '22023');
  begin perform costs_ai_usage('cu_a', null, current_date - 400, current_date); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('período acima de 366 dias recusado', true, st = '22023');
  begin perform costs_ai_usage('cu_a', 14); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('janela fora de 7/30/90 recusada', true, st = '22023');
  begin perform costs_ai_usage('cu_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin A não lê B (troca de id)', true, st = '42501');
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente nunca vê a vista da agência', true, st = '42501');
  j := costs_ai_usage_export('runs', 'cu_a', 7);
  execute 'reset role';
  insert into t values ('exportação auditada com a tabela e o período', true, exists (select 1 from audit_events where action = 'costs.ai_exported' and workspace_id = 'cu_a'
    and actor_user_id = u_adm and after->>'table' = 'runs' and (after->>'rows')::int = 3));
  execute 'set local role authenticated';
  begin perform costs_ai_usage_export('tudo', 'cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabela desconhecida recusada', true, st = '22023');
  begin perform costs_ai_usage_export('agents', 'cu_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin A não exporta B', true, st = '42501');

  -- negação explícita de costs.export: lê mas não exporta
  execute 'reset role';
  insert into permission_grants (user_id, workspace_id, capability, effect, created_by) values (u_adm, 'cu_a', 'costs.export', 'deny', u_own);
  execute 'set local role authenticated';
  insert into t values ('deny costs.export: continua a ler, sem exportar', true, not (costs_ai_usage('cu_a', 7)->>'can_export')::boolean);
  begin perform costs_ai_usage_export('agents', 'cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('deny costs.export: exportação recusada', true, st = '42501');

  -- ═════ cliente: leitor de A, admin de B ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor de A não vê custos', true, st = '42501');
  begin perform costs_ai_usage_export('agents', 'cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor de A não exporta', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := costs_ai_usage('cu_b', 7);
  insert into t values ('admin B vê só B (4,00), nada de A', true, (j->'totals'->>'cost')::numeric = 4.0 and position('cu_a' in j::text) = 0 and position('Escritor' in j::text) = 0);
  begin perform costs_ai_usage('cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin B não lê A', true, st = '42501');

  -- ═════ agência: membro com A só (manager), sem costs.read ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro da agência (manager em A) sem costs.read não vê A', true, st = '42501');
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro da agência sem costs.read_agency não vê a vista da agência', true, st = '42501');
  execute 'reset role';
  insert into permission_grants (user_id, workspace_id, capability, effect, created_by) values (u_ag, 'cu_a', 'costs.read', 'allow', u_own);
  execute 'set local role authenticated';
  insert into t values ('exceção individual costs.read em A: vê A', true, (costs_ai_usage('cu_a', 7)->'totals'->>'cost')::numeric = 1.5);
  insert into t values ('exceção de leitura não dá exportação', true, not (costs_ai_usage('cu_a', 7)->>'can_export')::boolean);
  begin perform costs_ai_usage('cu_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro com exceção em A continua sem B', true, st = '42501');
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('exceção num cliente não abre a vista da agência', true, st = '42501');

  -- ═════ agência: admin da agência (admin em A, manager em B), sem costs.read_agency ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag2, 'role','authenticated')::text, true);
  insert into t values ('admin da agência como workspace_admin em A vê A', true, (costs_ai_usage('cu_a', 7)->'totals'->>'cost')::numeric = 1.5);
  begin perform costs_ai_usage('cu_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência como manager em B não vê B', true, st = '42501');
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência sem delegação não vê custos globais', true, st = '42501');

  -- ═════ agência: dono ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := costs_ai_usage(null, 7);
  insert into t values ('dono: vista da agência com A e B', true, j->>'scope' = 'agency'
    and exists (select 1 from jsonb_array_elements(j->'workspaces') x where x->>'id' = 'cu_a' and (x->>'cost')::numeric = 1.5 and (x->>'prev_cost')::numeric = 0.5)
    and exists (select 1 from jsonb_array_elements(j->'workspaces') x where x->>'id' = 'cu_b' and (x->>'cost')::numeric = 4.0));
  insert into t values ('dono: total = soma dos clientes visíveis', true,
    (j->'totals'->>'cost')::numeric = (select sum((x->>'cost')::numeric) from jsonb_array_elements(j->'workspaces') x));
  insert into t values ('dono: execuções de vários clientes com o nome do cliente', true,
    j->'runs'->0->>'workspace_name' = 'Custos B' and (j->'runs'->0->>'cost_eur')::numeric = 4.0);
  j := costs_ai_usage_export('workspaces', null, 7);
  execute 'reset role';
  insert into t values ('dono exporta a vista da agência', true, jsonb_array_length(j->'workspaces') >= 2
    and exists (select 1 from audit_events where action = 'costs.ai_exported' and entity_id = 'agency' and organization_id = org and actor_user_id = u_own));
  -- negação explícita do dono num cliente tira-o da vista e da exportação
  insert into permission_grants (user_id, workspace_id, capability, effect, created_by) values (u_own, 'cu_b', 'costs.read', 'deny', u_own);
  execute 'set local role authenticated';
  j := costs_ai_usage(null, 7);
  insert into t values ('deny costs.read em B: B sai da vista da agência', true,
    not exists (select 1 from jsonb_array_elements(j->'workspaces') x where x->>'id' = 'cu_b') and position('segredo_b' in j::text) = 0);
  -- flag da agência desligada
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('costs.agency', org, null, 'off');
  execute 'set local role authenticated';
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag costs.agency desligada: 55000', true, st = '55000');
  -- flag do cliente desligada
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'costs.content' and workspace_id = 'cu_a';
  execute 'set local role authenticated';
  begin perform costs_ai_usage('cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag costs.content desligada no cliente: 55000', true, st = '55000');
  execute 'reset role';
  update feature_flags set stage = 'all' where key = 'costs.content' and workspace_id = 'cu_a';

  -- ═════ sessão revogada: admin de A suspenso ═════
  update workspace_access set status = 'suspended' where workspace_id = 'cu_b' and user_id = u_b;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('cu_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('acesso suspenso perde os custos no pedido seguinte', true, st = '42501');

  -- ═════ código de equipa e anónimo ═════
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform costs_ai_usage('cu_a', 7, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa nunca vê custos', true, st = '42501');
  begin perform costs_ai_usage_export('agents', 'cu_a', 7, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa nunca exporta', true, st = '42501');
  begin perform costs_ai_usage(null, 7, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa nunca vê a vista da agência', true, st = '42501');
  begin perform costs_ai_usage('cu_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo recusado', true, st = '42501');
  execute 'reset role';

  insert into t values ('capacidade costs.export registada para os mesmos papéis que costs.read', true,
    exists (select 1 from capabilities where key = 'costs.export' and status = 'ativo')
    and (select array_agg(role order by role) from role_capabilities where capability = 'costs.export')
      = (select array_agg(role order by role) from role_capabilities where capability = 'costs.read' and scope = 'ws'));
  insert into t values ('flag costs.agency registada no âmbito da agência', true, exists (select 1 from feature_flag_defs where key = 'costs.agency' and scope = 'org' and default_stage = 'owner'));
  insert into t values ('funções internas fechadas', true, not has_function_privilege('authenticated', 'public._costs_ai_report(text[], date, date, text)', 'execute')
    and not has_function_privilege('authenticated', 'public._costs_ai_scope(text, text, text)', 'execute')
    and not has_function_privilege('anon', 'public._costs_ai_args(text[], text, int, date, date)', 'execute'));
  insert into t values ('agent_jobs continua fechada à leitura direta', true, not has_table_privilege('authenticated', 'public.agent_jobs', 'select'));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  insert into t values ('agent_log não devolve linhas a uma sessão (RLS)', true, (select count(*) from agent_log where client_id in ('cu_a', 'cu_b')) = 0);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
