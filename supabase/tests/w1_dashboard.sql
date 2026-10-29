-- supabase/tests/w1_dashboard.sql : Início por cliente, widgets por função e painel da agência (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_view uuid := gen_random_uuid();
  u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d0 date := current_date - 6; d1 date := current_date;
  j jsonb; j2 jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_d_a', 'Dash A', 'da', org, 'UTC'), ('ws_d_b', 'Dash B', 'db', org, 'UTC');
  insert into accounts (id, client_id, role, platform, handle) values ('ws_d_a-ig', 'ws_d_a', 'client', 'instagram', 'da'), ('ws_d_b-ig', 'ws_d_b', 'client', 'instagram', 'db');
  insert into reels (client_id, id, account_id, owner, role, url, views, likes, comments, shares, taken_at) values
    ('ws_d_a', 'DA1', 'ws_d_a-ig', 'da', 'client', 'u', 1000, 80, 15, 5, now() - interval '1 day'),
    ('ws_d_a', 'DA2', 'ws_d_a-ig', 'da', 'client', 'u', 500, 20, 5, 0, now() - interval '2 days'),
    ('ws_d_a', 'DA3', 'ws_d_a-ig', 'da', 'client', 'u', 300, 0, 0, 0, now() - interval '10 days'),
    ('ws_d_b', 'DB1', 'ws_d_b-ig', 'db', 'client', 'u', 7000, 700, 0, 0, now() - interval '1 day');
  insert into ideas (client_id, kind, titulo) values ('ws_d_a', 'source', 'fonte A1'), ('ws_d_a', 'source', 'fonte A2'), ('ws_d_b', 'source', 'fonte B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'d-own@test.invalid'),(u_ag,'d-ag@test.invalid'),(u_adm,'d-adm@test.invalid'),(u_view,'d-view@test.invalid'),
    (u_rev,'d-rev@test.invalid'),(u_b,'d-b@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_admin');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_d_a', u_ag, 'agency_staff', 'manager'), ('ws_d_a', u_adm, 'client_staff', 'workspace_admin'), ('ws_d_a', u_view, 'client_staff', 'viewer'),
    ('ws_d_a', u_rev, 'client_staff', 'reviewer'), ('ws_d_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('ws_d_a', u_rev, 'analytics.read', 'deny', 'teste');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := dashboard_get('ws_d_a', d0, d1);
  insert into t values ('admin: views do período e do anterior', true, (j #>> '{kpis,kpi.views,value}')::int = 1500 and (j #>> '{kpis,kpi.views,prev}')::int = 300);
  insert into t values ('admin: engagement = interações ÷ views', true, (j #>> '{kpis,kpi.engagement,value}')::numeric = 8.33);
  insert into t values ('admin: fontes recebidas', true, (j #>> '{kpis,kpi.sources,value}')::int = 2 and (j #>> '{kpis,kpi.sources,prev}')::int = 0);
  insert into t values ('admin: vê custos e pode configurar', true, j->'kpis' ? 'kpi.costs' and (j->>'can_configure')::boolean);
  insert into t values ('admin: layout por omissão da função, com explicação', true, j->>'role' = 'workspace_admin' and not (j->>'customized')::boolean
    and j->'widgets'->0->>'key' = 'kpi.scripts_created' and length(j->'widgets'->0->>'description') > 20);
  insert into t values ('período anterior do mesmo tamanho', true, (j #>> '{period,prev_from}')::date = d0 - 7 and (j #>> '{period,prev_to}')::date = d0 - 1);
  insert into t values ('nada de B nos números de A', true, (j #>> '{kpis,kpi.views,value}')::int < 7000);
  begin perform dashboard_get('ws_d_a', d1, d0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('período ao contrário (22023)', true, st = '22023');
  begin perform dashboard_get('ws_d_a', d1 - 400, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('período acima de um ano (22023)', true, st = '22023');
  begin perform dashboard_get('ws_d_b', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de A não vê o Início de B (42501)', true, st = '42501');

  -- configurar o layout do viewer
  j := dashboard_layout_set('ws_d_a', 'viewer', array['kpi.sources', 'kpi.views', 'kpi.costs']);
  insert into t values ('layout gravado para a função', true, (select bool_or(x->>'role' = 'viewer' and (x->>'customized')::boolean) from jsonb_array_elements(j->'roles') x));
  execute 'reset role';
  insert into t values ('mudança auditada com antes e depois', true, exists (select 1 from audit_events where workspace_id = 'ws_d_a' and action = 'dashboard.layout_set'
    and after->'widgets' = '["kpi.sources", "kpi.views", "kpi.costs"]'::jsonb and before ? 'widgets'));
  execute 'set local role authenticated';
  begin perform dashboard_layout_set('ws_d_a', 'viewer', array['kpi.nada']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('widget desconhecido (22023)', true, st = '22023');
  begin perform dashboard_layout_set('ws_d_a', 'viewer', array['kpi.views', 'kpi.views']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('widget repetido (22023)', true, st = '22023');
  begin perform dashboard_layout_set('ws_d_a', 'agency_owner', array['kpi.views']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('função inválida (22023)', true, st = '22023');
  begin perform dashboard_layout_set('ws_d_b', 'viewer', array['kpi.views']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de A não configura B (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  j := dashboard_get('ws_d_a', d0, d1);
  insert into t values ('viewer vê o layout novo pela ordem gravada', true, j->'widgets'->0->>'key' = 'kpi.sources' and j->'widgets'->1->>'key' = 'kpi.views' and (j->>'customized')::boolean);
  insert into t values ('widget de custos no layout mas sem costs.read: não aparece nem o número', true,
    not exists (select 1 from jsonb_array_elements(j->'widgets') x where x->>'key' = 'kpi.costs') and not (j->'kpis' ? 'kpi.costs'));
  insert into t values ('viewer não configura', true, not (j->>'can_configure')::boolean);
  begin perform dashboard_layout_set('ws_d_a', 'viewer', array['kpi.views']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não muda layouts (42501)', true, st = '42501');
  begin perform dashboard_layouts_get('ws_d_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não lê a configuração (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  j := dashboard_get('ws_d_a', d0, d1);
  insert into t values ('negação de analytics.read tira views, engagement e gráficos', true,
    not (j->'kpis' ? 'kpi.views') and not (j->'kpis' ? 'kpi.engagement') and not exists (select 1 from jsonb_array_elements(j->'widgets') x where x->>'key' like 'chart.views%'
    or x->>'key' = 'panel.activity') and j->'kpis' ? 'kpi.pending_approval');

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := dashboard_layout_reset('ws_d_a', 'viewer');
  execute 'reset role';
  insert into t values ('repor volta ao layout por omissão, auditado', true,
    (select bool_and(not (x->>'customized')::boolean) from jsonb_array_elements(j->'roles') x)
    and exists (select 1 from audit_events where workspace_id = 'ws_d_a' and action = 'dashboard.layout_reset'));
  execute 'set local role authenticated';
  begin perform agency_dashboard(d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não vê o painel da agência (42501)', true, st = '42501');

  -- agência
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := agency_dashboard(d0, d1);
  insert into t values ('admin da agência só vê os clientes atribuídos', true, (j->>'count')::int = 1 and j->'clients'->0->>'id' = 'ws_d_a');
  insert into t values ('totais só desses clientes', true, (j #>> '{totals,kpi.views,value}')::int = 1500);
  insert into t values ('manager na agência: sem custos, contado como em falta', true, not (j->'clients'->0->'kpis' ? 'kpi.costs') and (j #>> '{missing,kpi.costs}')::int = 1);
  begin perform dashboard_get('ws_d_b', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem atribuição a B não abre B (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := agency_dashboard(d0, d1);
  insert into t values ('dono da agência vê A e B', true, exists (select 1 from jsonb_array_elements(j->'clients') x where x->>'id' = 'ws_d_a')
    and exists (select 1 from jsonb_array_elements(j->'clients') x where x->>'id' = 'ws_d_b'));
  insert into t values ('totais somam os clientes e o engagement é ponderado', true,
    (j #>> '{totals,kpi.views,value}')::numeric >= 8500 and (j #>> '{totals,kpi.sources,value}')::int >= 3 and (j #>> '{totals,kpi.engagement,value}') is not null);
  j2 := dashboard_get('ws_d_b', d0, d1);
  insert into t values ('dono da agência abre o Início de B com layout de dono', true, j2->>'role' = 'workspace_owner' and (j2 #>> '{kpis,kpi.views,value}')::int = 7000);
  j2 := dashboard_get('numeiro', d0, d1);
  insert into t values ('meta do dia vem da configuração ativa', true,
    (j2->>'target_per_day') is not distinct from (select nullif(config #>> '{pipeline,scripts_per_day}', '') from agent_config_versions where workspace_id = 'numeiro' and status = 'active' limit 1));
  insert into t values ('à espera de aprovação é a contagem de agora', true,
    (j2 #>> '{kpis,kpi.pending_approval,value}')::int = (select count(*) from guioes where client_id = 'numeiro' and editorial_status = 'in_review')
    and (j2 #> '{kpis,kpi.pending_approval,prev}') = 'null'::jsonb);
  begin perform 1 from dashboard_layouts limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabelas fechadas à API (42501)', true, st = '42501');
  execute 'reset role';

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := dashboard_get('numeiro', d0, d1, tok);
  insert into t values ('código de equipa: Início do próprio cliente, layout de contributor, sem custos', true, j->>'role' = 'contributor' and not (j->'kpis' ? 'kpi.costs'));
  begin perform dashboard_get('ws_d_a', d0, d1, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código do Numeiro não abre A (42501)', true, st = '42501');
  begin perform dashboard_get('ws_d_a', d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código (42501)', true, st = '42501');
  begin perform agency_dashboard(d0, d1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não chama o painel da agência', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
