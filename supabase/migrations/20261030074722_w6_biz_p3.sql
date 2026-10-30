-- Parte 3 de 4 de 20261030000100_w6_biz.sql (aplicada em produção como w6_biz_p3).

-- ───────────── RPC pública da vista ─────────────
-- Uma resposta por pessoa: clientes a que tem acesso (dono: todos os ativos), métricas operacionais por capacidade no cliente,
-- e os campos e totais financeiros só com biz.finance. Sem biz.finance não sai nenhuma chave financeira (BIZ-04).
create or replace function public.biz_overview(p_month date, p_currency text default 'EUR') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid; m date; fin boolean; fx fx_rates; rate numeric; cl record; caps text[]; ops jsonb; fj jsonb;
        rows jsonb := '[]'; n int := 0; missing jsonb := '{}'; k text;
        att_on int := 0; att_con int := 0; att_exp numeric := 0; fp_n int := 0; fp_ok int := 0; hours numeric[] := '{}'; idx numeric[] := '{}';
        over70 int := 0; pend int := 0; pend48 int := 0;
        shared jsonb := '{}'; alloc numeric; tot_mrr numeric := 0; tot_cost numeric := 0; tot_vids int := 0; tot_views bigint := 0; fx_missing boolean := false;
        risk int := 0; cards jsonb := '[]'; unavailable jsonb; conc jsonb := '[]'; s record; mm date; share numeric; trend jsonb; ai jsonb;
        sev int; nm text; href text;
begin
  org := public._biz_require('biz.read', 'biz.overview');
  m := public._biz_month(p_month);
  if p_currency is null or p_currency not in ('EUR', 'AED') then raise exception 'moeda_invalida' using errcode = '22023', detail = 'Moedas: EUR ou AED.'; end if;
  fin := public._org_can('biz.finance', org, uid);
  if fin then
    select * into fx from fx_rates where organization_id = org order by as_of desc, id desc limit 1;
    rate := fx.rate;
    -- custos da agência repartidos [pressuposto: por todos os clientes ativos; "por_videos" pelos vídeos publicados no mês, igual se não houver nenhum]
    with act as (select c.id, public._biz_published(c.id, (m::timestamp at time zone c.timezone), least(((m + interval '1 month')::date)::timestamp at time zone c.timezone, now())) v
                   from clients c where c.organization_id = org and c.status = 'active'),
         tot as (select count(*) n, sum(v) v from act),
         sc as (select public._biz_conv(amount, currency, p_currency, rate) amt, allocation from agency_costs
                 where organization_id = org and workspace_id is null and month = m and voided_at is null)
    select coalesce(jsonb_object_agg(act.id, (select case when bool_or(sc.amt is null) then null else coalesce(round(sum(
             case when sc.allocation = 'por_videos' and tot.v > 0 then sc.amt * act.v / tot.v else sc.amt / tot.n end), 2), 0) end from sc)), '{}')
      into shared from act, tot;
  end if;

  for cl in select c.* from clients c where c.organization_id = org and c.status = 'active'
              and (public._org_can('workspaces.read', org, uid) and public.is_agency_owner(uid)
                   or exists (select 1 from workspace_access a where a.workspace_id = c.id and a.user_id = uid and a.status = 'active'
                                and a.affiliation_type = 'agency_staff' and (a.expires_at is null or a.expires_at > now())))
            order by lower(c.name) loop
    caps := array(select x from unnest(array['scripts.read', 'analytics.read']) x where public._authorize(x, cl.id, uid));
    if cardinality(caps) = 0 and not fin then continue; end if;
    n := n + 1;
    ops := public._biz_ops(cl.id, m, caps);
    for k in select key from biz_metrics where level = 'operacional' and available loop
      if not ops ? k then missing := jsonb_set(missing, array[k], to_jsonb(coalesce((missing ->> k)::int, 0) + 1)); end if;
    end loop;
    if ops ? 'ops.attainment' then
      att_on := att_on + (ops #>> '{ops.attainment,on_time}')::int;
      if (ops #>> '{ops.attainment,contract}')::boolean then
        att_con := att_con + coalesce((ops #>> '{ops.attainment,contracted}')::int, 0);
        att_exp := att_exp + coalesce((ops #>> '{ops.attainment,expected_to_date}')::numeric, 0);
      end if;
      fp_n := fp_n + (ops #>> '{ops.first_pass,approved}')::int; fp_ok := fp_ok + (ops #>> '{ops.first_pass,first_pass}')::int;
      hours := hours || array(select jsonb_array_elements_text(ops #> '{ops.approval_time,_hours}')::numeric);
      over70 := over70 + (ops #>> '{ops.stalled,over_p70}')::int;
      pend := pend + (ops #>> '{ops.approvals,pending}')::int; pend48 := pend48 + (ops #>> '{ops.approvals,over_48h}')::int;
      ops := jsonb_set(ops, '{ops.approval_time}', (ops -> 'ops.approval_time') - '_hours');
    end if;
    if ops ? 'ops.performance' then
      idx := idx || array(select jsonb_array_elements_text(ops #> '{ops.performance,_idx}')::numeric);
      ops := jsonb_set(ops, '{ops.performance}', (ops -> 'ops.performance') - '_idx');
    end if;

    -- cartões operacionais (BIZ-02). rank: 3 crítico, 2 alto, 1 aviso
    nm := cl.name;
    if (ops #>> '{ops.attainment,alert}')::boolean then
      sev := case when (ops #>> '{ops.attainment,pace}')::numeric < 75 then 3 else 2 end;
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'delivery', 'rank', sev, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('Entrega em risco: %s%% do ritmo', public._biz_pt((ops #>> '{ops.attainment,pace}')::numeric)),
        'detail', format('%s no prazo de %s esperados até hoje; %s com prazo hoje por publicar; %s em atraso (%s do cliente).',
                         ops #>> '{ops.attainment,on_time}', public._biz_pt(round((ops #>> '{ops.attainment,expected_to_date}')::numeric)), ops #>> '{ops.attainment,due_today}',
                         ops #>> '{ops.attainment,overdue}', ops #>> '{ops.attainment,late_client}'),
        'action_label', 'Abrir calendário', 'action_href', '/c/' || cl.id || '/calendario'));
    end if;
    if coalesce((ops #>> '{ops.stalled,over_p70}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'stalled', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s parados acima do p70', ops #>> '{ops.stalled,over_p70}', case when (ops #>> '{ops.stalled,over_p70}')::int = 1 then 'item' else 'itens' end),
        'detail', 'Estão há mais tempo na etapa do que 70% das passagens dos últimos 90 dias.',
        'action_label', 'Ver guiões', 'action_href', '/c/' || cl.id || '/guioes'));
    elsif coalesce((ops #>> '{ops.stalled,over_p50}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'stalled', 'rank', 1, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s a ficar parados', ops #>> '{ops.stalled,over_p50}', case when (ops #>> '{ops.stalled,over_p50}')::int = 1 then 'item' else 'itens' end),
        'detail', 'Já passaram a mediana do tempo da etapa (aviso a partir do p50).',
        'action_label', 'Ver guiões', 'action_href', '/c/' || cl.id || '/guioes'));
    end if;
    if coalesce((ops #>> '{ops.approvals,over_48h}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'approval', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s à espera de aprovação há mais de 48 h', ops #>> '{ops.approvals,over_48h}',
                        case when (ops #>> '{ops.approvals,over_48h}')::int = 1 then 'guião' else 'guiões' end),
        'detail', 'Pede a aprovação ao cliente ou revê as prioridades da revisão.',
        'action_label', 'Abrir revisão', 'action_href', '/c/' || cl.id || '/revisao'));
    end if;
    if (ops #>> '{ops.reach,ratio}')::numeric < 60 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'suppression', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('Possível supressão: views a %s%% do normal', public._biz_pt((ops #>> '{ops.reach,ratio}')::numeric)),
        'detail', format('Mediana de %s views nos últimos 7 dias contra %s nos 30 anteriores.', ops #>> '{ops.reach,median_7d}', ops #>> '{ops.reach,median_30d}'),
        'action_label', 'Abrir desempenho', 'action_href', '/c/' || cl.id || '/desempenho'));
    end if;

    fj := null;
    if fin then
      alloc := case when shared ? cl.id then (shared ->> cl.id)::numeric else 0 end;
      if shared ? cl.id and shared -> cl.id = 'null'::jsonb then alloc := null; end if;
      fj := public._biz_fin(cl.id, m, p_currency, rate, alloc);
      if (fj ->> 'fx_missing')::boolean then fx_missing := true; end if;
      tot_mrr := tot_mrr + coalesce((fj ->> 'fin.mrr')::numeric, 0);
      tot_cost := case when tot_cost is null or (fj ->> 'fin.cost') is null then null else tot_cost + (fj ->> 'fin.cost')::numeric end;
      tot_vids := tot_vids + (fj ->> 'videos')::int; tot_views := tot_views + (fj ->> 'views')::bigint;
      -- [pressuposto] cliente em risco: fatura vencida há mais de 15 dias, margem abaixo de 50%, ou renovação em 30 dias com entrega abaixo de 90%
      if coalesce((fj #>> '{fin.payment,overdue_days}')::int, 0) > 15 or (fj ->> 'fin.margin')::numeric < 50
         or (coalesce((fj #>> '{fin.renewal,days}')::int, 999) between 0 and 30 and (ops #>> '{ops.attainment,pace}')::numeric < 90) then
        risk := risk + 1;
      end if;
      if (fj ->> 'fin.margin')::numeric < 50 then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'margin', 'rank', 2, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', format('Margem de entrega a %s%%', public._biz_pt((fj ->> 'fin.margin')::numeric)), 'detail', 'Abaixo dos 50%: revê custos e volume contratado.',
          'action_label', 'Ver custos', 'action_href', '/negocio/contratos?ws=' || cl.id));
      end if;
      if coalesce((fj #>> '{fin.payment,overdue_days}')::int, 0) > 15 then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'invoice', 'rank', 3, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', format('Pagamento vencido há %s dias', fj #>> '{fin.payment,overdue_days}'), 'detail', 'Registado como vencido no contrato.',
          'action_label', 'Abrir contrato', 'action_href', '/negocio/contratos?ws=' || cl.id));
      end if;
      ai := public._biz_ai_trend(cl.id);
      if (ai ->> 'alert')::boolean then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'ai_cost', 'rank', 1, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', 'Custo de IA por vídeo subiu mais de 25%',
          'detail', format('%s EUR por vídeo nos últimos 30 dias contra %s EUR nos 30 anteriores, sem mais vídeos.', replace(ai ->> 'cpv_now', '.', ','), replace(ai ->> 'cpv_prev', '.', ',')),
          'action_label', 'Ver agentes', 'action_href', '/c/' || cl.id || '/agentes/configuracao'));
      end if;
    end if;

    rows := rows || jsonb_build_array(jsonb_build_object('id', cl.id, 'name', cl.name, 'handle', cl.handle, 'logo_path', cl.logo_path,
      'brand_color', cl.brand_color, 'timezone', cl.timezone, 'ops', ops) || case when fin then jsonb_build_object('fin', fj) else '{}' end);
  end loop;

  if fin then
    -- concentração: cliente com mais de 20% do MRR em cada um dos últimos 3 fins de mês (mostrado como tendência)
    for s in select c.id, c.name from clients c where c.organization_id = org and c.status = 'active' loop
      trend := '[]';
      for mm in select (date_trunc('month', m) - make_interval(months => g) + interval '1 month' - interval '1 day')::date from generate_series(2, 0, -1) g loop
        mm := least(mm, (now() at time zone 'Asia/Dubai')::date);
        select round(100 * sum(case when c2.id = s.id then v end) / nullif(sum(v), 0), 1) into share
          from (select c2.id, public._biz_conv(public._biz_monthly(public._biz_contract_at(c2.id, mm), mm), (public._biz_contract_at(c2.id, mm)).currency, p_currency, rate) v
                  from clients c2 where c2.organization_id = org and c2.status = 'active') c2;
        trend := trend || jsonb_build_array(jsonb_build_object('date', mm, 'share', share));
      end loop;
      if (select bool_and(coalesce((x ->> 'share')::numeric, 0) > 20) from jsonb_array_elements(trend) x) then
        conc := conc || jsonb_build_array(jsonb_build_object('client_id', s.id, 'client_name', s.name, 'trend', trend));
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'concentration', 'rank', 1, 'level', 'financeiro', 'client_id', s.id, 'client_name', s.name,
          'title', format('%s%% do MRR há 3 meses', public._biz_pt((trend -> 2 ->> 'share')::numeric)),
          'detail', format('Peso no MRR: %s%%, %s%%, %s%% nos últimos 3 fins de mês.', public._biz_pt((trend -> 0 ->> 'share')::numeric), public._biz_pt((trend -> 1 ->> 'share')::numeric), public._biz_pt((trend -> 2 ->> 'share')::numeric)),
          'trend', trend, 'action_label', 'Ver contratos', 'action_href', '/negocio/contratos?ws=' || s.id));
      end if;
    end loop;
  end if;

  unavailable := jsonb_build_array(
    jsonb_build_object('key', 'health_drop', 'label', 'Saúde do cliente a cair', 'reason', 'Ainda não há score de saúde: precisa de cerca de 6 meses de histórico e de sentimento (BIZ-09).'),
    jsonb_build_object('key', 'near_zero', 'label', 'Posts perto de zero a duplicar', 'reason', 'Ainda não há leituras das publicações por idade (PERF-03).'))
    || case when fin then jsonb_build_array(jsonb_build_object('key', 'renewal_health', 'label', 'Renovação em 30 dias com saúde amarela ou vermelha',
         'reason', 'Depende da saúde do cliente (BIZ-09). A data de renovação aparece na tabela.')) else '[]' end;

  return jsonb_build_object(
    'month', m, 'currency', p_currency, 'finance', fin, 'can_manage', fin and public._org_can('contracts.manage', org, uid), 'count', n,
    'metrics', (select jsonb_agg(jsonb_build_object('key', key, 'level', level, 'label', label, 'description', description, 'capability', capability,
                  'available', available, 'unavailable_reason', unavailable_reason) order by sort) from biz_metrics where fin or level = 'operacional'),
    'clients', rows, 'missing', missing,
    'totals', jsonb_build_object(
      'ops.attainment', jsonb_build_object('on_time', att_on, 'contracted', att_con, 'expected_to_date', round(att_exp, 1),
                          'pct', case when att_con > 0 then round(100.0 * att_on / att_con, 1) end,
                          'pace', case when att_exp >= 1 then round(100.0 * att_on / att_exp, 1) end, 'target', 95, 'alert_below', 90),
      'ops.first_pass', jsonb_build_object('approved', fp_n, 'first_pass', fp_ok, 'pct', case when fp_n > 0 then round(100.0 * fp_ok / fp_n, 1) end),
      'ops.approval_time', jsonb_build_object('n', cardinality(hours), 'median_h', (select round(percentile_cont(0.5) within group (order by h)::numeric, 1) from unnest(hours) h)),
      'ops.performance', jsonb_build_object('n', cardinality(idx), 'median', (select round(percentile_cont(0.5) within group (order by i)::numeric, 2) from unnest(idx) i)),
      'ops.stalled', jsonb_build_object('over_p70', over70),
      'ops.approvals', jsonb_build_object('pending', pend, 'over_48h', pend48))
      || case when fin then jsonb_build_object(
        'fin.mrr', tot_mrr, 'fin.cost', tot_cost,
        'fin.margin', case when tot_mrr > 0 and tot_cost is not null then round(100 * (tot_mrr - tot_cost) / tot_mrr, 1) end,
        'fin.cost_per_video', case when tot_vids > 0 and tot_cost is not null then round(tot_cost / tot_vids, 2) end,
        'fin.cost_per_1k', case when tot_views > 0 and tot_cost is not null then round(tot_cost / tot_views * 1000, 2) end,
        'at_risk', risk, 'concentration', conc) else '{}' end,
    'attention', jsonb_build_object(
      'cards', coalesce((select jsonb_agg(x - 'rank' || jsonb_build_object('severity', case (x ->> 'rank')::int when 3 then 'critico' when 2 then 'alto' else 'aviso' end)
                          order by (x ->> 'rank')::int desc, x ->> 'level' desc, x ->> 'client_name')
                         from (select x from jsonb_array_elements(cards) x order by (x ->> 'rank')::int desc, x ->> 'level' desc, x ->> 'client_name' limit 5) y), '[]'),
      'more', greatest(jsonb_array_length(cards) - 5, 0),
      'unavailable', unavailable))
    || case when fin then jsonb_build_object('fx', case when fx.id is not null then jsonb_build_object('base', 'EUR', 'quote', 'AED', 'rate', fx.rate, 'as_of', fx.as_of, 'source', fx.source) end,
                                             'fx_missing', fx_missing) else '{}' end;
end $$;

-- ───────────── contratos, câmbio e custos (só o dono por defeito) ─────────────
create or replace function public.biz_contracts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.contracts');
begin
  return jsonb_build_object(
    'can_manage', public._org_can('contracts.manage', org, auth.uid()),
    'fx', (select jsonb_build_object('rate', rate, 'as_of', as_of, 'source', source, 'created_label', created_label)
             from fx_rates where organization_id = org order by as_of desc, id desc limit 1),
    'fx_history', coalesce((select jsonb_agg(jsonb_build_object('rate', rate, 'as_of', as_of, 'source', source, 'created_at', created_at, 'created_label', created_label)
                              order by as_of desc, id desc) from (select * from fx_rates where organization_id = org order by as_of desc, id desc limit 10) h), '[]'),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'currency', c.currency,
        'versions', (select count(*) from client_contracts k where k.workspace_id = c.id),
        'contract', (select to_jsonb(k) - 'created_by' from client_contracts k where k.workspace_id = c.id order by k.version desc limit 1))
        order by lower(c.name)) from clients c where c.organization_id = org and c.status = 'active'), '[]'));
end $$;

create or replace function public.biz_contract_history(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.contract_history');
begin
  if not exists (select 1 from clients where id = p_ws and organization_id = org) then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  return coalesce((select jsonb_agg(to_jsonb(k) - 'created_by' order by k.version desc) from client_contracts k where k.workspace_id = p_ws), '[]');
end $$;

-- Gravar o contrato cria uma versão nova (as anteriores ficam). p_expected: versão que a pessoa estava a ver (0 sem contrato).
create or replace function public.biz_contract_save(p_ws text, p_fields jsonb, p_expected int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.contract_save'); uid uuid := auth.uid(); old client_contracts; nw client_contracts; k text; cur int;
begin
  if not exists (select 1 from clients where id = p_ws and organization_id = org and status = 'active') then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campo_invalido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('status', 'amount', 'currency', 'billing_period', 'scripts_per_month', 'videos_per_month', 'platforms', 'deadline_days',
                 'starts_on', 'renewal_on', 'effective_from', 'payment_status', 'payment_due_on', 'notes') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k);
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtext('biz_contract:' || p_ws));
  select * into old from client_contracts where workspace_id = p_ws order by version desc limit 1;
  cur := coalesce(old.version, 0);
  if p_expected is distinct from cur then
    raise exception 'conflito_versao' using errcode = '40001', detail = 'Alguém mudou este contrato entretanto. Recarrega e volta a gravar.';
  end if;
  if old.id is null and (nullif(p_fields ->> 'amount', '') is null or nullif(p_fields ->> 'currency', '') is null) then
    raise exception 'campo_obrigatorio' using errcode = '22023', detail = 'Indica o valor e a moeda do contrato.';
  end if;
  begin
    insert into client_contracts (workspace_id, version, status, amount, currency, billing_period, scripts_per_month, videos_per_month, platforms,
                                  deadline_days, starts_on, renewal_on, effective_from, payment_status, payment_due_on, notes, created_by, created_label)
    values (p_ws, cur + 1,
      case when p_fields ? 'status' then p_fields ->> 'status' else coalesce(old.status, 'ativo') end,
      case when p_fields ? 'amount' then (p_fields ->> 'amount')::numeric else old.amount end,
      case when p_fields ? 'currency' then p_fields ->> 'currency' else old.currency end,
      case when p_fields ? 'billing_period' then p_fields ->> 'billing_period' else coalesce(old.billing_period, 'mensal') end,
      case when p_fields ? 'scripts_per_month' then nullif(p_fields ->> 'scripts_per_month', '')::int else old.scripts_per_month end,
      case when p_fields ? 'videos_per_month' then nullif(p_fields ->> 'videos_per_month', '')::int else old.videos_per_month end,
      case when p_fields ? 'platforms' then array(select distinct x from jsonb_array_elements_text(p_fields -> 'platforms') x order by 1) else coalesce(old.platforms, '{}') end,
      case when p_fields ? 'deadline_days' then coalesce(nullif(p_fields ->> 'deadline_days', '')::int, 7) else coalesce(old.deadline_days, 7) end,
      case when p_fields ? 'starts_on' then nullif(p_fields ->> 'starts_on', '')::date else old.starts_on end,
      case when p_fields ? 'renewal_on' then nullif(p_fields ->> 'renewal_on', '')::date else old.renewal_on end,
      case when p_fields ? 'effective_from' then coalesce(nullif(p_fields ->> 'effective_from', '')::date, current_date) else current_date end,
      case when p_fields ? 'payment_status' then p_fields ->> 'payment_status' else coalesce(old.payment_status, 'em_dia') end,
      case when p_fields ? 'payment_due_on' then nullif(p_fields ->> 'payment_due_on', '')::date else old.payment_due_on end,
      case when p_fields ? 'notes' then nullif(trim(p_fields ->> 'notes'), '') else old.notes end,
      uid, (select email from auth.users where id = uid))
    returning * into nw;
  exception
    when check_violation or not_null_violation then
      raise exception 'contrato_invalido' using errcode = '22023', detail = 'Valores fora do permitido: valor de 0 a 10 000 000, moeda EUR ou AED, volumes de 0 a 10 000, prazo de 0 a 60 dias, renovação depois do início.';
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
      raise exception 'contrato_invalido' using errcode = '22023', detail = 'Há um número ou uma data com formato inválido.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', nw.created_label, org, p_ws, 'biz.contract_saved', 'client_contract', nw.id::text, to_jsonb(old) - 'created_by', to_jsonb(nw) - 'created_by');
  return public.biz_contracts();
end $$;
