-- W10-10 · Custos: consumo de IA por agente, modelo, execução e cliente (PRD M10 FR-10-01; FR-10-06 só como rótulo honesto;
-- ADR-0060). Espaços: agência (/custos, todos os clientes que a pessoa pode ver) e cliente (/c/<cliente>/custos).
-- Só aditivo (expand): 1 capacidade nova (costs.export), 1 flag nova de âmbito agência (costs.agency), 1 índice, funções novas
-- e o texto da flag costs.content. NÃO muda _authorize, ws_can, content_costs, content_costs_export nem nenhum grant existente.
--  * Leitura do cliente: costs.read no cliente (por defeito dono e admin do cliente; o código de equipa nunca) e a flag
--    costs.content ligada nesse cliente. Leitura da agência: costs.read_agency na organização (por defeito só o dono da agência)
--    e a flag costs.agency; a resposta só inclui os clientes ativos da organização em que a pessoa também tem costs.read
--    (uma negação explícita num cliente tira esse cliente da vista).
--  * Exportar (CSV montado no browser a partir da resposta): costs.export em TODOS os clientes da resposta, senão recusa
--    inteira (fail closed). Auditado com a tabela exportada e o período.
--  * Valores em EUR: o motor calcula o custo a partir dos tokens e da tabela de preços (agent_models, agent_tool_prices). São
--    estimativas; ainda não há custo confirmado por fatura do fornecedor nem câmbio guardado por execução (FR-10-06 por fazer).
--    Execuções sem custo conhecido ficam contadas à parte e nunca valem zero.
--  * Por execução: agent_jobs terminadas no período. Por agente e por modelo: chamadas registadas em agent_log (sem ensaios).
--    As duas somas podem diferir (pesquisas web contam na execução; o motor antigo registava chamadas sem execução na fila).
-- Rollback no fim.

insert into public.capabilities (key, module, risk, scopes, status, label) values
  ('costs.export', 'Custos', 'M', array['ws'], 'ativo', 'Exportar custos do cliente (CSV)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
-- Os mesmos papéis que já têm costs.read (e que já exportavam por content_costs_export): não alarga ninguém.
insert into public.role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'costs.export'), ('ws', 'workspace_admin', 'costs.export')
on conflict do nothing;

insert into public.feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('costs.agency', 'Custos da agência', 'Custos', 'org', 'owner',
   'Consumo de IA de todos os clientes a que a pessoa tem acesso, por cliente, agente, modelo e execução, com CSV. Só com costs.read_agency (FR-10-01).')
on conflict (key) do nothing;
update public.feature_flag_defs
   set label = 'Custos do cliente',
       description = 'Consumo de IA por agente, modelo e execução (FR-10-01) e custo por guião e publicação (FR-10-05), com CSV, só para quem tem costs.read.'
 where key = 'costs.content';

create index if not exists agent_jobs_ws_finished on public.agent_jobs (workspace_id, finished_at) where finished_at is not null;

-- Clientes da resposta. p_need = 'costs.read' (ler) ou 'costs.export' (exportar). Recusa com 42501, flag desligada com 55000.
create or replace function public._costs_ai_scope(p_ws text, p_token text, p_need text) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid; wss text[];
begin
  if p_need not in ('costs.read', 'costs.export') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_ws is not null then
    perform public._learn_require('costs.content', 'costs.read', p_ws, p_token, p_need);
    if p_need = 'costs.export' then perform public._content_require('costs.export', p_ws, p_token, 'costs.ai_export', p_ws); end if;
    return array[p_ws];
  end if;
  -- espaço da agência: só sessão individual de staff da agência; o código de equipa e a equipa do cliente nunca (R-13)
  if uid is not null then
    select organization_id into org from agency_memberships where user_id = uid and status = 'active' order by created_at limit 1;
  end if;
  if org is null or not public._org_can('costs.read_agency', org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', 'costs.ai_agency', 'capability', 'costs.read_agency');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not public._flag_on('costs.agency', null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
  select coalesce(array_agg(c.id order by c.name), '{}') into wss from clients c
   where c.organization_id = org and c.status = 'active' and public._authorize('costs.read', c.id, uid);
  if p_need = 'costs.export' and exists (select 1 from unnest(wss) w where not public._authorize('costs.export', w, uid)) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'Não podes exportar os custos de todos os clientes desta vista.';
  end if;
  return wss;
end $$;

-- Relatório para uma lista de clientes já autorizada. Período [p_from, p_to] em dias do fuso p_tz; o anterior tem o mesmo tamanho.
create or replace function public._costs_ai_report(p_wss text[], p_from date, p_to date, p_tz text) returns jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select (p_from::timestamp at time zone p_tz) lo, ((p_to + 1)::timestamp at time zone p_tz) hi,
           ((p_from - (p_to - p_from + 1))::timestamp at time zone p_tz) plo, (p_to - p_from + 1) days),
  ws as (select c.id, c.name, c.currency from clients c where c.id = any (p_wss)),
  jobs as (
    select j.id, j.workspace_id, j.kind, j.status, j.cost_eur, j.tokens_in, j.tokens_out, j.attempts, j.run_id,
           j.started_at, j.finished_at, j.finished_at >= b.lo cur
    from agent_jobs j, b
    where j.workspace_id = any (p_wss) and j.finished_at is not null and j.finished_at >= b.plo and j.finished_at < b.hi),
  calls as (
    select l.client_id ws, l.run_id, coalesce(nullif(l.agent, ''), 'sem agente') agent, coalesce(nullif(l.model, ''), 'sem modelo') model,
           l.cost_eur, l.tokens_in, l.tokens_out, l.created_at >= b.lo cur
    from agent_log l, b
    where l.client_id = any (p_wss) and not l.simulated and l.created_at >= b.plo and l.created_at < b.hi
      and (l.cost_eur is not null or l.tokens_in is not null or l.tokens_out is not null)),
  agg_calls as (
    select 'agent' dim, agent k, count(*) filter (where cur) calls, count(*) filter (where cur and cost_eur is null) calls_unknown,
           round(coalesce(sum(cost_eur) filter (where cur), 0), 4) cost, round(coalesce(sum(cost_eur) filter (where not cur), 0), 4) prev_cost,
           count(*) filter (where not cur) prev_calls,
           coalesce(sum(tokens_in) filter (where cur), 0) tokens_in, coalesce(sum(tokens_out) filter (where cur), 0) tokens_out
    from calls group by agent
    union all
    select 'model', model, count(*) filter (where cur), count(*) filter (where cur and cost_eur is null),
           round(coalesce(sum(cost_eur) filter (where cur), 0), 4), round(coalesce(sum(cost_eur) filter (where not cur), 0), 4),
           count(*) filter (where not cur),
           coalesce(sum(tokens_in) filter (where cur), 0), coalesce(sum(tokens_out) filter (where cur), 0)
    from calls group by model)
  select jsonb_build_object(
    'currency', 'EUR', 'timezone', p_tz,
    'from', p_from, 'to', p_to, 'days', (select days from b),
    'prev_from', p_from - (select days from b), 'prev_to', p_from - 1,
    'basis', jsonb_build_object(
      'kind', 'estimated', 'confirmed_available', false,
      'note', 'Estimativa: o motor calcula o custo de cada chamada a partir dos tokens e da tabela de preços pública do fornecedor, convertida para EUR ao câmbio guardado com o preço. Ainda não há custo confirmado por fatura nem câmbio guardado por execução.',
      'prices', coalesce((select jsonb_agg(jsonb_build_object('model', m.key, 'label', m.label, 'eur_per_mtok_in', m.eur_per_mtok_in,
                 'eur_per_mtok_out', m.eur_per_mtok_out, 'fx_usd_per_eur', m.fx_usd_per_eur, 'source', m.price_source,
                 'updated_at', m.prices_updated_at) order by m.key) from agent_models m), '[]'),
      'tools', coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'eur_per_use', t.eur_per_use,
                 'fx_usd_per_eur', t.fx_usd_per_eur, 'source', t.price_source, 'updated_at', t.updated_at) order by t.key) from agent_tool_prices t), '[]')),
    -- câmbio EUR→AED mais recente da organização (BIZ-05), para mostrar em AED com a taxa e a data à vista
    'fx', (select jsonb_build_object('quote', f.quote, 'rate', f.rate, 'as_of', f.as_of, 'source', f.source)
             from fx_rates f where f.organization_id = (select organization_id from clients where id = p_wss[1])
            order by f.as_of desc, f.id desc limit 1),
    'totals', jsonb_build_object(
      'cost', (select round(coalesce(sum(cost_eur) filter (where cur), 0), 4) from jobs),
      'prev_cost', (select round(coalesce(sum(cost_eur) filter (where not cur), 0), 4) from jobs),
      'jobs', (select count(*) filter (where cur) from jobs),
      'prev_jobs', (select count(*) filter (where not cur) from jobs),
      'jobs_unknown', (select count(*) filter (where cur and cost_eur is null) from jobs),
      'jobs_failed', (select count(*) filter (where cur and status in ('failed', 'dead')) from jobs),
      'tokens_in', (select coalesce(sum(tokens_in) filter (where cur), 0) from jobs),
      'tokens_out', (select coalesce(sum(tokens_out) filter (where cur), 0) from jobs),
      'calls_cost', (select round(coalesce(sum(cost_eur) filter (where cur), 0), 4) from calls),
      'calls', (select count(*) filter (where cur) from calls),
      'calls_unknown', (select count(*) filter (where cur and cost_eur is null) from calls)),
    'workspaces', coalesce((select jsonb_agg(jsonb_build_object('id', ws.id, 'name', ws.name, 'currency', ws.currency,
        'cost', (select round(coalesce(sum(cost_eur) filter (where cur), 0), 4) from jobs where workspace_id = ws.id),
        'prev_cost', (select round(coalesce(sum(cost_eur) filter (where not cur), 0), 4) from jobs where workspace_id = ws.id),
        'jobs', (select count(*) filter (where cur) from jobs where workspace_id = ws.id),
        'prev_jobs', (select count(*) filter (where not cur) from jobs where workspace_id = ws.id),
        'jobs_unknown', (select count(*) filter (where cur and cost_eur is null) from jobs where workspace_id = ws.id),
        'tokens_in', (select coalesce(sum(tokens_in) filter (where cur), 0) from jobs where workspace_id = ws.id),
        'tokens_out', (select coalesce(sum(tokens_out) filter (where cur), 0) from jobs where workspace_id = ws.id),
        'calls_cost', (select round(coalesce(sum(cost_eur) filter (where cur), 0), 4) from calls where calls.ws = ws.id))
      order by ws.name) from ws), '[]'),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('key', a.k, 'name', coalesce(d.name, a.k), 'calls', a.calls, 'calls_unknown', a.calls_unknown,
        'cost', a.cost, 'prev_cost', a.prev_cost, 'prev_calls', a.prev_calls, 'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out)
      order by a.cost desc, a.k) from agg_calls a left join agent_definitions d on d.key = a.k where a.dim = 'agent' and a.calls > 0), '[]'),
    'models', coalesce((select jsonb_agg(jsonb_build_object('key', a.k, 'name', coalesce(m.label, a.k), 'calls', a.calls, 'calls_unknown', a.calls_unknown,
        'cost', a.cost, 'prev_cost', a.prev_cost, 'prev_calls', a.prev_calls, 'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out)
      order by a.cost desc, a.k) from agg_calls a left join agent_models m on m.key = a.k where a.dim = 'model' and a.calls > 0), '[]'),
    -- as 50 execuções mais caras do período (as de custo desconhecido no fim); sem quem pediu (pode ser um email da agência)
    'runs', coalesce((select jsonb_agg(r.j order by r.o) from (
        select row_number() over (order by j.cost_eur desc nulls last, j.finished_at desc) o,
               jsonb_build_object('id', j.id, 'workspace_id', j.workspace_id, 'workspace_name', ws.name, 'kind', j.kind, 'status', j.status,
                 'cost_eur', j.cost_eur, 'cost_known', j.cost_eur is not null, 'tokens_in', j.tokens_in, 'tokens_out', j.tokens_out,
                 'attempts', j.attempts, 'started_at', j.started_at, 'finished_at', j.finished_at,
                 'duration_s', case when j.started_at is not null then round(extract(epoch from j.finished_at - j.started_at)) end,
                 'calls_cost', (select round(sum(c.cost_eur), 4) from calls c where c.cur and c.ws = j.workspace_id and c.run_id = j.run_id)) j
        from jobs j join ws on ws.id = j.workspace_id where j.cur
        order by j.cost_eur desc nulls last, j.finished_at desc limit 50) r), '[]'))
$$;

-- Período: p_from e p_to (personalizado, até 366 dias) ou os últimos p_days dias (7, 30 ou 90) até hoje no fuso da vista.
create or replace function public._costs_ai_args(p_wss text[], p_ws text, p_days int, p_from date, p_to date, out tz text, out d_from date, out d_to date)
language plpgsql stable security definer set search_path = public as $$
begin
  tz := case when p_ws is not null then (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws)
             else coalesce((select nullif(timezone, '') from profiles where user_id = auth.uid()), 'Asia/Dubai') end;
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'Asia/Dubai'; end if;
  if p_from is not null or p_to is not null then
    if p_from is null or p_to is null or p_from > p_to then
      raise exception 'periodo_invalido' using errcode = '22023', detail = 'Escolhe uma data de início anterior ou igual à data de fim.'; end if;
    if p_to - p_from + 1 > 366 then
      raise exception 'periodo_invalido' using errcode = '22023', detail = 'O período pode ter no máximo 366 dias.'; end if;
    d_from := p_from; d_to := p_to;
  else
    if coalesce(p_days, 30) not in (7, 30, 90) then
      raise exception 'periodo_invalido' using errcode = '22023', detail = 'Período de 7, 30 ou 90 dias.'; end if;
    d_to := (now() at time zone tz)::date;
    d_from := d_to - (coalesce(p_days, 30) - 1);
  end if;
end $$;

-- Ler. p_ws nulo = vista da agência.
create or replace function public.costs_ai_usage(p_ws text default null, p_days int default 30, p_from date default null, p_to date default null,
                                                 p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare wss text[] := public._costs_ai_scope(p_ws, p_token, 'costs.read'); a record;
begin
  select * into a from public._costs_ai_args(wss, p_ws, p_days, p_from, p_to);
  return public._costs_ai_report(wss, a.d_from, a.d_to, a.tz)
         || jsonb_build_object('scope', case when p_ws is null then 'agency' else 'workspace' end,
                               'can_export', not exists (select 1 from unnest(wss) w where not public.ws_can('costs.export', w, p_token)) and cardinality(wss) > 0);
end $$;

-- Exportar a tabela visível: igual à leitura, com costs.export em todos os clientes da resposta, e auditado.
create or replace function public.costs_ai_usage_export(p_table text, p_ws text default null, p_days int default 30, p_from date default null,
                                                        p_to date default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare wss text[]; a record; res jsonb; who jsonb; org uuid;
begin
  if p_table is null or p_table not in ('workspaces', 'agents', 'models', 'runs') then
    raise exception 'tabela_invalida' using errcode = '22023', detail = 'Tabela desconhecida para exportar.'; end if;
  wss := public._costs_ai_scope(p_ws, p_token, 'costs.export');
  select * into a from public._costs_ai_args(wss, p_ws, p_days, p_from, p_to);
  res := public._costs_ai_report(wss, a.d_from, a.d_to, a.tz)
         || jsonb_build_object('scope', case when p_ws is null then 'agency' else 'workspace' end, 'can_export', true);
  who := public._content_actor(p_token);
  org := case when p_ws is null then (select organization_id from agency_memberships where user_id = auth.uid() and status = 'active' order by created_at limit 1) end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
  values ((who->>'uid')::uuid, who->>'kind', who->>'label', org, p_ws, 'costs.ai_exported', 'costs', coalesce(p_ws, 'agency'),
          jsonb_build_object('table', p_table, 'from', a.d_from, 'to', a.d_to, 'workspaces', cardinality(wss),
                             'rows', jsonb_array_length(res->p_table)));
  return res;
end $$;

revoke all on function public._costs_ai_scope(text, text, text), public._costs_ai_report(text[], date, date, text),
  public._costs_ai_args(text[], text, int, date, date) from public, anon, authenticated;
revoke all on function public.costs_ai_usage(text, int, date, date, text), public.costs_ai_usage_export(text, text, int, date, date, text) from public;
-- anon só passa com código de equipa válido num cliente, e legacy_can nunca inclui costs.*: recusa sempre (mesmo padrão de content_costs).
grant execute on function public.costs_ai_usage(text, int, date, date, text), public.costs_ai_usage_export(text, text, int, date, date, text) to anon, authenticated;

/* Rollback (compatível: nada do que existia mudou de assinatura nem de regra):
   drop function public.costs_ai_usage_export(text, text, int, date, date, text), public.costs_ai_usage(text, int, date, date, text),
     public._costs_ai_args(text[], text, int, date, date), public._costs_ai_report(text[], date, date, text), public._costs_ai_scope(text, text, text);
   drop index if exists public.agent_jobs_ws_finished;
   update public.feature_flag_defs set label = 'Custos por guião e publicação',
     description = 'Custo dos agentes por guião e por publicação, tendência mensal e exportação CSV, só para quem tem costs.read (FR-10-05).'
    where key = 'costs.content';
   delete from public.feature_flags where key = 'costs.agency'; delete from public.feature_flag_defs where key = 'costs.agency';
   delete from public.permission_grants where capability = 'costs.export';
   delete from public.role_capabilities where capability = 'costs.export'; delete from public.capabilities where key = 'costs.export';
   -- os registos 'costs.ai_exported' no histórico ficam (append-only) */
