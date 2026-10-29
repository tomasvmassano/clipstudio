-- supabase/tests/w6_biz.sql : vista de negócio da agência (BIZ-01..BIZ-06), dois níveis de acesso e isolamento (rollback no fim).
-- Usa o mês anterior (já fechado) para os números não dependerem do dia em que o teste corre.
do $$
declare
  org uuid := (select id from organizations where slug = 'clipstudio');
  u_own uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_mem uuid := gen_random_uuid();
  u_ca uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  m0 date := (date_trunc('month', current_date) - interval '1 month')::date;
  ts0 timestamptz := (date_trunc('month', current_date) - interval '1 month')::timestamp at time zone 'UTC';
  j jsonb; j2 jsonb; ca jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; ref uuid := gen_random_uuid(); cid uuid;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own, 'bz-own@test.invalid'), (u_adm, 'bz-adm@test.invalid'), (u_mem, 'bz-mem@test.invalid'), (u_ca, 'bz-ca@test.invalid'), (u_cb, 'bz-cb@test.invalid')) v(x, e);
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_bz_a', 'Biz A', 'bza', org, 'UTC'), ('ws_bz_b', 'Biz B', 'bzb', org, 'UTC');
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_adm, 'agency_admin'), (org, u_mem, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_bz_a', u_mem, 'agency_staff', 'manager'), ('ws_bz_a', u_ca, 'client_staff', 'workspace_admin'), ('ws_bz_b', u_cb, 'client_staff', 'workspace_admin');
  insert into accounts (id, client_id, role, platform, handle) values ('ws_bz_a-ig', 'ws_bz_a', 'client', 'instagram', 'bza'), ('ws_bz_b-ig', 'ws_bz_b', 'client', 'instagram', 'bzb');

  -- dados com tempos controlados: sem os gatilhos de criação (que marcariam tudo com now())
  set local session_replication_role = replica;
  insert into guioes (id, client_id, date, n, hooks, corpo, editorial_status, production_status, gravado, gravado_em, created_at) values
    ('bzA1', 'ws_bz_a', m0 + 1, 1, '[]', 'c', 'approved', 'recorded', true, ts0 + interval '1 day', ts0),
    ('bzA2', 'ws_bz_a', m0 + 1, 2, '[]', 'c', 'approved', 'recorded', true, ts0 + interval '1 day', ts0),
    ('bzA3', 'ws_bz_a', m0 + 5, 3, '[]', 'c', 'approved', 'recorded', true, ts0 + interval '5 days', ts0),
    ('bzA4', 'ws_bz_a', current_date + 30, 4, '[]', 'c', 'in_review', 'not_started', false, null, now() - interval '6 hours'),
    ('bzA5', 'ws_bz_a', current_date + 30, 5, '[]', 'c', 'in_review', 'not_started', false, null, now() - interval '70 hours'),
    ('bzB1', 'ws_bz_b', m0 + 1, 1, '[]', 'segredo de B', 'approved', 'recorded', true, ts0 + interval '1 day', ts0);
  insert into guioes (id, client_id, date, n, hooks, corpo, editorial_status, production_status, created_at)
    select 'bzH' || g, 'ws_bz_a', current_date + 40, 10 + g, '[]', 'c', 'approved', 'not_started', now() - interval '11 days' from generate_series(1, 10) g;
  insert into content_transitions (workspace_id, content_id, kind, from_status, to_status, actor_user_id, actor_kind, at)
    select 'ws_bz_a', 'bzH' || g, 'editorial', 'draft', 'in_review', null, 'engine', now() - interval '10 days' from generate_series(1, 10) g
    union all select 'ws_bz_a', 'bzH' || g, 'editorial', 'in_review', 'approved', u_mem, 'user', now() - interval '10 days' + interval '1 hour' from generate_series(1, 10) g
    union all values ('ws_bz_a', 'bzA2', 'editorial', 'draft', 'in_review', null::uuid, 'engine', ts0),
                     ('ws_bz_a', 'bzA2', 'editorial', 'in_review', 'approved', u_ca, 'user', ts0 + interval '3 days'),
                     ('ws_bz_a', 'bzA4', 'editorial', 'draft', 'in_review', null, 'engine', now() - interval '5 hours'),
                     ('ws_bz_a', 'bzA5', 'editorial', 'draft', 'in_review', null, 'engine', now() - interval '60 hours');
  insert into publicacoes (guiao_id, account_id, published_at) values
    ('bzA1', 'ws_bz_a-ig', ts0 + interval '2 days 12 hours'),     -- prazo m0+1+2: no prazo
    ('bzA1', 'ws_bz_a-ig', ts0 + interval '2 days 13 hours'),     -- segunda plataforma: o mesmo vídeo
    ('bzA2', 'ws_bz_a-ig', ts0 + interval '10 days'),             -- atrasado, aprovação do cliente demorou 72 h
    ('bzB1', 'ws_bz_b-ig', ts0 + interval '2 days');
  -- reels de A: 30 dias anteriores com 1000 views, últimos 7 dias com 100 (possível supressão)
  insert into reels (client_id, id, account_id, owner, role, url, views, taken_at)
    select 'ws_bz_a', 'BZ30_' || g, 'ws_bz_a-ig', 'bza', 'client', 'u', 1000, now() - make_interval(days => 8 + g) from generate_series(1, 6) g
    union all select 'ws_bz_a', 'BZ7_' || g, 'ws_bz_a-ig', 'bza', 'client', 'u', 100, now() - make_interval(days => g) from generate_series(1, 3) g;
  set local session_replication_role = origin;

  -- contratos em vigor desde há 4 meses (versão 1, a partir de dados antigos)
  insert into client_contracts (workspace_id, version, amount, currency, videos_per_month, deadline_days, effective_from, payment_status, payment_due_on, created_label) values
    ('ws_bz_a', 1, 3000, 'EUR', 10, 2, m0 - 90, 'em_dia', null, 'fixture'),
    ('ws_bz_b', 1, 1000, 'AED', 5, 2, m0 - 90, 'vencido', current_date - 20, 'fixture');
  insert into agency_costs (organization_id, workspace_id, month, kind, label, amount, currency, allocation) values
    (org, 'ws_bz_a', m0, 'humano', 'Editor A', 600, 'EUR', 'direto'),
    (org, null, m0, 'ferramentas', 'Ferramentas partilhadas', 300, 'EUR', 'igual');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── dono: vê tudo, com finanças ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role', 'authenticated')::text, true);
  j := biz_overview(m0, 'EUR');
  select x into ca from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_a';
  insert into t values ('dono vê A e B', true, exists (select 1 from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_b') and ca is not null);
  insert into t values ('dono tem finanças', true, (j ->> 'finance')::boolean and (j ->> 'can_manage')::boolean);
  insert into t values ('BIZ-01 no prazo, atrasado e em atraso', true, (ca #>> '{ops,ops.attainment,on_time}')::int = 1
    and (ca #>> '{ops,ops.attainment,late_published}')::int = 1 and (ca #>> '{ops,ops.attainment,overdue}')::int = 1);
  insert into t values ('BIZ-01 atingimento = no prazo ÷ contratados', true, (ca #>> '{ops,ops.attainment,pct}')::numeric = 10.0 and (ca #>> '{ops,ops.attainment,contracted}')::int = 10);
  insert into t values ('BIZ-01 atraso do cliente à parte', true, (ca #>> '{ops,ops.attainment,late_client}')::int = 1 and (ca #>> '{ops,ops.attainment,late_agency}')::int = 1);
  insert into t values ('BIZ-01 mês fechado: ritmo = atingimento e alerta abaixo de 90%', true,
    (ca #>> '{ops,ops.attainment,pace}')::numeric = 10.0 and (ca #>> '{ops,ops.attainment,alert}')::boolean);
  insert into t values ('aprovação à primeira e tempo de aprovação do cliente', true, (ca #>> '{ops,ops.first_pass,approved}')::int = 1
    and (ca #>> '{ops,ops.approval_time,median_h}')::numeric = 72.0 and not (ca #> '{ops,ops.approval_time}' ? '_hours'));
  insert into t values ('itens parados acima do p70 da etapa', true, (ca #>> '{ops,ops.stalled,over_p70}')::int = 2);
  insert into t values ('aprovações à espera há mais de 48 h', true, (ca #>> '{ops,ops.approvals,pending}')::int = 2 and (ca #>> '{ops,ops.approvals,over_48h}')::int = 1);
  insert into t values ('supressão: views 7 d a 10% dos 30 d', true, (ca #>> '{ops,ops.reach,ratio}')::numeric = 10.0);
  insert into t values ('saúde do cliente marcada como indisponível', true, exists (select 1 from jsonb_array_elements(j -> 'metrics') x
    where x ->> 'key' = 'ops.health' and not (x ->> 'available')::boolean and length(x ->> 'unavailable_reason') > 20));
  insert into t values ('sem taxa de câmbio: B em AED fica sem conversão', true, (select x #> '{fin,fin.mrr}' from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_b') = 'null'::jsonb
    and (j ->> 'fx_missing')::boolean and j -> 'fx' = 'null'::jsonb);
  insert into t values ('custo de A: direto + parte igual da agência', true, (ca #>> '{fin,fin.cost}')::numeric = 700 and (ca #>> '{fin,cost_shared}')::numeric = 100);
  insert into t values ('margem de A = (3000 - 700) ÷ 3000', true, (ca #>> '{fin,fin.margin}')::numeric = 76.7);
  insert into t values ('custo por vídeo: 2 vídeos (3 publicações)', true, (ca #>> '{fin,videos}')::int = 2 and (ca #>> '{fin,fin.cost_per_video}')::numeric = 350);

  j := biz_fx_save(4, current_date, 'teste');
  j := biz_overview(m0, 'EUR');
  select x into ca from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_b';
  insert into t values ('com taxa: 1000 AED = 250 EUR, taxa e data visíveis', true, (ca #>> '{fin,fin.mrr}')::numeric = 250
    and (j #>> '{fx,rate}')::numeric = 4 and (j #>> '{fx,as_of}')::date = current_date);
  insert into t values ('MRR total na moeda base', true, (j #>> '{totals,fin.mrr}')::numeric = 3250);
  insert into t values ('fatura vencida há mais de 15 dias é crítica', true, exists (select 1 from jsonb_array_elements(j #> '{attention,cards}') x
    where x ->> 'key' = 'invoice' and x ->> 'client_id' = 'ws_bz_b' and x ->> 'severity' = 'critico'));
  insert into t values ('concentração > 20% do MRR em 3 meses', true, exists (select 1 from jsonb_array_elements(j #> '{totals,concentration}') x where x ->> 'client_id' = 'ws_bz_a')
    and not exists (select 1 from jsonb_array_elements(j #> '{totals,concentration}') x where x ->> 'client_id' = 'ws_bz_b'));
  insert into t values ('faixa: no máximo 5 cartões, ordenados por gravidade', true, jsonb_array_length(j #> '{attention,cards}') <= 5
    and j #>> '{attention,cards,0,severity}' = 'critico'
    and (jsonb_array_length(j #> '{attention,cards}') + (j #>> '{attention,more}')::int) >= 5);
  insert into t values ('cada cartão tem ação direta', true, (select bool_and(x ->> 'action_href' like '/%' and length(x ->> 'action_label') > 2) from jsonb_array_elements(j #> '{attention,cards}') x));
  j := biz_overview(m0, 'AED');
  insert into t values ('alternância para AED', true, (select (x #>> '{fin,fin.mrr}')::numeric from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_a') = 12000);
  begin perform biz_overview(m0, 'USD'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('moeda inválida (22023)', true, st = '22023');
  begin perform biz_overview(current_date + 70, 'EUR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('mês futuro (22023)', true, st = '22023');

  -- contratos: versões, concorrência, validação, auditoria
  j := biz_contract_save('ws_bz_a', '{"payment_status":"pendente","renewal_on":"2030-01-01"}', 1);
  insert into t values ('gravar cria versão 2 e mantém o resto', true, (select (x #>> '{contract,version}')::int = 2 and (x #>> '{contract,amount}')::numeric = 3000
    and x #>> '{contract,payment_status}' = 'pendente' from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_a'));
  insert into t values ('histórico com as duas versões', true, jsonb_array_length(biz_contract_history('ws_bz_a')) = 2);
  begin perform biz_contract_save('ws_bz_a', '{"amount":1}', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão desatualizada (40001)', true, st = '40001');
  begin perform biz_contract_save('ws_bz_a', '{"currency":"USD"}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('moeda fora de EUR/AED (22023)', true, st = '22023');
  begin perform biz_contract_save('ws_bz_a', '{"discount":1}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo desconhecido (22023)', true, st = '22023');
  begin perform biz_contract_save('ws_bz_a', '{"amount":"abc"}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('valor inválido (22023)', true, st = '22023');
  begin perform biz_contract_save('ws_x_nao', '{"amount":1,"currency":"EUR"}', 0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente inexistente (P0002)', true, st = 'P0002');

  -- custos: idempotência e anulação
  j := biz_cost_save(jsonb_build_object('workspace_id', 'ws_bz_a', 'month', m0, 'kind', 'ferramentas', 'label', 'Licença', 'amount', 50, 'currency', 'EUR'), ref);
  j := biz_cost_save(jsonb_build_object('workspace_id', 'ws_bz_a', 'month', m0, 'kind', 'ferramentas', 'label', 'Licença', 'amount', 50, 'currency', 'EUR'), ref);
  insert into t values ('repetir o pedido não duplica o custo', true, (select count(*) from jsonb_array_elements(j -> 'costs') x where x ->> 'label' = 'Licença') = 1);
  cid := (select (x ->> 'id')::uuid from jsonb_array_elements(j -> 'costs') x where x ->> 'label' = 'Licença');
  j := biz_cost_void(cid, 'lançado por engano');
  j := biz_cost_void(cid, 'outra vez');
  insert into t values ('custo anulado fica no histórico com motivo', true, (select x ->> 'void_reason' from jsonb_array_elements(j -> 'costs') x where x ->> 'id' = cid::text) = 'lançado por engano');
  j := biz_overview(m0, 'EUR');
  insert into t values ('custo anulado não entra na margem', true, (select (x #>> '{fin,fin.cost}')::numeric from jsonb_array_elements(j -> 'clients') x where x ->> 'id' = 'ws_bz_a') = 700);
  begin perform biz_cost_save(jsonb_build_object('month', m0, 'kind', 'humano', 'label', 'X', 'amount', 1, 'currency', 'EUR', 'allocation', 'direto'), gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('custo direto sem cliente (22023)', true, st = '22023');
  execute 'reset role';
  insert into t values ('gravações auditadas com antes e depois', true, exists (select 1 from audit_events where action = 'biz.contract_saved' and workspace_id = 'ws_bz_a'
    and before ->> 'version' = '1' and after ->> 'version' = '2') and exists (select 1 from audit_events where action = 'biz.cost_voided')
    and exists (select 1 from audit_events where action = 'biz.fx_saved' and organization_id = org));
  begin update client_contracts set amount = 1 where workspace_id = 'ws_bz_a'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões de contrato não se alteram (42501)', true, st = '42501');
  begin update agency_costs set amount = 1 where id = cid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('custos não se alteram, só se anulam (42501)', true, st = '42501');
  insert into t values ('tabelas fechadas à API', true, not has_table_privilege('authenticated', 'public.client_contracts', 'select')
    and not has_table_privilege('authenticated', 'public.agency_costs', 'select') and not has_table_privilege('anon', 'public.fx_rates', 'select')
    and not has_table_privilege('authenticated', 'public.biz_metrics', 'select'));
  insert into t values ('dinheiro em numeric, não float', true, (select bool_and(data_type = 'numeric') from information_schema.columns
    where table_schema = 'public' and ((table_name = 'client_contracts' and column_name = 'amount') or (table_name = 'agency_costs' and column_name = 'amount') or (table_name = 'fx_rates' and column_name = 'rate'))));
  insert into t values ('finanças e contratos só para o dono por defeito', true,
    (select array_agg(role order by role) from role_capabilities where capability = 'biz.finance') = array['agency_owner']
    and (select array_agg(role order by role) from role_capabilities where capability = 'contracts.manage') = array['agency_owner']);
  execute 'set local role authenticated';

  -- ── staff da agência (só A): flag por defeito "só o dono" ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_mem, 'role', 'authenticated')::text, true);
  begin perform biz_overview(m0, 'EUR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag só para o dono: staff recebe erro explícito (55000)', true, st = '55000');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('biz.view', org, null, 'agency');
  execute 'set local role authenticated';
  j := biz_overview(m0, 'EUR');
  insert into t values ('staff só vê o cliente atribuído', true, (j ->> 'count')::int = 1 and j #>> '{clients,0,id}' = 'ws_bz_a');
  insert into t values ('staff não recebe nenhum campo nem total financeiro', true, not (j ->> 'finance')::boolean
    and j::text not like '%fin.%' and j::text not like '%mrr%' and j::text not like '%amount%' and not (j ? 'fx') and not (j #> '{clients,0}' ? 'fin')
    and not (j -> 'totals' ? 'concentration') and not (j -> 'totals' ? 'at_risk'));
  insert into t values ('staff vê o operacional de A', true, (j #>> '{clients,0,ops,ops.attainment,on_time}')::int = 1 and (j #>> '{totals,ops.attainment,pct}')::numeric = 10.0);
  insert into t values ('faixa do staff sem cartões financeiros nem de B', true, not exists (select 1 from jsonb_array_elements(j #> '{attention,cards}') x
    where x ->> 'level' = 'financeiro' or x ->> 'client_id' <> 'ws_bz_a'));
  insert into t values ('nada de B na resposta do staff', true, j::text not like '%ws_bz_b%' and j::text not like '%Biz B%');
  begin perform biz_contracts(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não lê contratos (42501)', true, st = '42501');
  begin perform biz_contract_history('ws_bz_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não lê o histórico de contratos (42501)', true, st = '42501');
  begin perform biz_contract_save('ws_bz_a', '{"amount":1}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não muda contratos (42501)', true, st = '42501');
  begin perform biz_costs(m0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não lê custos (42501)', true, st = '42501');
  begin perform biz_cost_save(jsonb_build_object('workspace_id', 'ws_bz_a', 'month', m0, 'kind', 'humano', 'label', 'X1', 'amount', 1, 'currency', 'EUR'), gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não lança custos (42501)', true, st = '42501');
  begin perform biz_fx_save(4, current_date, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff não muda o câmbio (42501)', true, st = '42501');

  -- negação explícita de analytics.read em A tira as métricas de desempenho
  execute 'reset role';
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('ws_bz_a', u_mem, 'analytics.read', 'deny', 'teste');
  execute 'set local role authenticated';
  j := biz_overview(m0, 'EUR');
  insert into t values ('negação explícita: sem desempenho, contado em falta', true, not (j #> '{clients,0,ops}' ? 'ops.performance')
    and not (j #> '{clients,0,ops}' ? 'ops.reach') and (j #>> '{missing,ops.performance}')::int = 1 and j #> '{clients,0,ops}' ? 'ops.attainment');

  -- admin da agência sem clientes atribuídos: não vê nenhum
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  j := biz_overview(m0, 'EUR');
  insert into t values ('admin sem atribuições não vê clientes nem finanças', true, (j ->> 'count')::int = 0 and not (j ->> 'finance')::boolean and j::text not like '%mrr%');

  -- staff suspenso perde o acesso logo
  execute 'reset role';
  update agency_memberships set status = 'suspended' where user_id = u_mem;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mem, 'role', 'authenticated')::text, true);
  begin perform biz_overview(m0, 'EUR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff suspenso não abre a vista (42501)', true, st = '42501');

  -- equipa do cliente: nunca vê a vista da agência nem finanças
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
  begin perform biz_overview(m0, 'EUR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A não vê a vista (42501)', true, st = '42501');
  begin perform biz_contracts(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A não lê contratos (42501)', true, st = '42501');
  begin perform biz_contract_save('ws_bz_a', '{"amount":1}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A não muda o próprio contrato (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role', 'authenticated')::text, true);
  begin perform biz_contract_history('ws_bz_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê o contrato de A (42501)', true, st = '42501');
  begin perform biz_costs(m0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê custos (42501)', true, st = '42501');
  execute 'reset role';

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform biz_overview(m0, 'EUR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não chama a vista', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
