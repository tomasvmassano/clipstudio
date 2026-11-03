-- Parte 2 de 4 de 20261030000100_w6_biz.sql (aplicada em produção como w6_biz_p2).

-- Números operacionais de um cliente num mês (só as métricas cujas capacidades estão em p_caps).
-- Devolve também _hours e _idx (amostras) para a agência calcular medianas reais; a RPC pública tira-as antes de responder.
create or replace function public._biz_ops(p_ws text, p_month date, p_caps text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; m0 date := p_month; m1 date := (p_month + interval '1 month')::date; f timestamptz; t timestamptz;
        dim int; elapsed int; c client_contracts; lag int; v_out jsonb := '{}'; a record; target int; contracted int; expected numeric;
        hours numeric[]; idx numeric[]; fpr record; r7 record; r30 record;
begin
  select timezone into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  f := m0::timestamp at time zone tz;
  t := least(m1::timestamp at time zone tz, now());
  dim := m1 - m0;
  elapsed := case when today >= m1 then dim when today < m0 then 0 else today - m0 + 1 end;
  c := public._biz_contract_at(p_ws, least(m1 - 1, today));
  lag := coalesce(c.deadline_days, 7);

  if 'scripts.read' = any(p_caps) then
    select nullif(v.config #>> '{pipeline,scripts_per_day}', '')::int into target
      from agent_config_versions v where v.workspace_id = p_ws and v.status = 'active' limit 1;
    v_out := v_out || jsonb_build_object('ops.today', (
      select jsonb_build_object('date', today, 'planned', count(*),
               'recorded', count(*) filter (where g.gravado or g.production_status in ('recorded', 'editing', 'ready', 'published')),
               'target', target)
        from guioes g where g.client_id = p_ws and g.date = today and g.editorial_status not in ('rejected', 'archived') and g.production_status <> 'cancelled'));

    v_out := v_out || jsonb_build_object('ops.approvals', (
      select jsonb_build_object('pending', count(*), 'over_48h', count(*) filter (where since < now() - interval '48 hours'))
        from (select coalesce((select max(ct.at) from content_transitions ct where ct.content_id = g.id and ct.kind = 'editorial' and ct.to_status = 'in_review'),
                              g.created_at) since
                from guioes g where g.client_id = p_ws and g.editorial_status = 'in_review') x));

    v_out := v_out || jsonb_build_object('ops.stalled', public._biz_stalled(p_ws));

    -- BIZ-01: atingimento de entrega
    select
      count(*) filter (where x.first_at >= f and x.first_at < t and x.pub_day <= x.deadline) on_time,
      count(*) filter (where x.first_at >= f and x.first_at < t and x.pub_day > x.deadline) late_pub,
      count(*) filter (where x.first_at is null and x.open and x.deadline >= m0 and x.deadline < least(today, m1)) overdue,
      count(*) filter (where x.first_at is null and x.open and x.deadline = today) due_today,
      count(*) filter (where ((x.first_at >= f and x.first_at < t and x.pub_day > x.deadline)
                              or (x.first_at is null and x.open and x.deadline >= m0 and x.deadline < least(today, m1))) and x.client_cause) late_client
      into a
      from (
        select g.id, g.date + lag deadline, fp.first_at, (fp.first_at at time zone tz)::date pub_day,
               g.editorial_status not in ('rejected', 'archived') and g.production_status <> 'cancelled' open,
               -- [pressuposto] atraso do cliente: aprovação feita pela equipa do cliente mais de 48 h depois do envio, guião ainda à espera
               -- de aprovação há mais de 48 h, ou gravação depois do dia planeado (a gravação é do criador)
               (exists (select 1 from content_transitions ap where ap.content_id = g.id and ap.kind = 'editorial' and ap.to_status = 'approved'
                          and public._biz_is_client_actor(p_ws, ap.actor_kind, ap.actor_user_id)
                          and ap.at - coalesce((select max(s.at) from content_transitions s where s.content_id = g.id and s.kind = 'editorial'
                                                  and s.to_status = 'in_review' and s.at <= ap.at), g.created_at) > interval '48 hours')
                or (g.editorial_status = 'in_review' and coalesce((select max(s.at) from content_transitions s where s.content_id = g.id and s.kind = 'editorial'
                                                                     and s.to_status = 'in_review'), g.created_at) < now() - interval '48 hours')
                or (g.gravado_em is not null and (g.gravado_em at time zone tz)::date > g.date)
                or (g.gravado_em is null and g.production_status in ('not_started', 'scheduled') and g.date < today)) client_cause
          from guioes g left join public._biz_first_pub(p_ws) fp on fp.content_id = g.id
         where g.client_id = p_ws) x;
    contracted := c.videos_per_month;
    expected := case when contracted is not null and c.status = 'ativo' then round(contracted::numeric * elapsed / dim, 1) end;
    v_out := v_out || jsonb_build_object('ops.attainment', jsonb_build_object(
      'contract', contracted is not null and c.status = 'ativo',
      'contracted', case when c.status = 'ativo' then contracted end, 'expected_to_date', expected, 'deadline_days', lag,
      'on_time', a.on_time, 'late_published', a.late_pub, 'overdue', a.overdue, 'due_today', a.due_today,
      'late_client', a.late_client, 'late_agency', a.late_pub + a.overdue - a.late_client,
      'pct', case when contracted > 0 and c.status = 'ativo' then round(100.0 * a.on_time / contracted, 1) end,
      'pace', case when expected >= 1 then round(100.0 * a.on_time / expected, 1) end,
      'target', 95, 'alert_below', 90,
      'alert', expected >= 1 and 100.0 * a.on_time / expected < 90));

    -- aprovação à primeira: primeira aprovação no mês sem changes_requested/rejected antes
    select count(*) n, count(*) filter (where not exists (select 1 from content_transitions b where b.content_id = x.content_id and b.kind = 'editorial'
                                                             and b.to_status in ('changes_requested', 'rejected') and b.at < x.at)) ok
      into fpr
      from (select content_id, min(at) at from content_transitions where workspace_id = p_ws and kind = 'editorial' and to_status = 'approved' group by content_id) x
     where x.at >= f and x.at < t;
    v_out := v_out || jsonb_build_object('ops.first_pass', jsonb_build_object('approved', fpr.n, 'first_pass', fpr.ok,
      'pct', case when fpr.n > 0 then round(100.0 * fpr.ok / fpr.n, 1) end));

    -- tempo de aprovação do cliente (aprovações feitas pela equipa do cliente ou pelo código de equipa)
    select array_agg(h order by h) into hours from (
      select round((extract(epoch from ap.at - coalesce((select max(s.at) from content_transitions s where s.content_id = ap.content_id and s.kind = 'editorial'
                                                           and s.to_status = 'in_review' and s.at <= ap.at), g.created_at)) / 3600)::numeric, 2) h
        from content_transitions ap join guioes g on g.id = ap.content_id
       where ap.workspace_id = p_ws and ap.kind = 'editorial' and ap.to_status = 'approved' and ap.at >= f and ap.at < t
         and coalesce(ap.reason, '') <> 'criado' and public._biz_is_client_actor(p_ws, ap.actor_kind, ap.actor_user_id)) y;
    v_out := v_out || jsonb_build_object('ops.approval_time', jsonb_build_object('n', coalesce(cardinality(hours), 0),
      'median_h', (select round(percentile_cont(0.5) within group (order by h)::numeric, 1) from unnest(hours) h), '_hours', to_jsonb(coalesce(hours, '{}'))));
  end if;

  if 'analytics.read' = any(p_caps) then
    -- PERF-04: views ÷ mediana dos 30 dias anteriores da mesma conta (mínimo 5 reels de base [pressuposto])
    with r as (
      select r.account_id, r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select array_agg(i order by i) into idx from (
      select round(cur.views::numeric / nullif(b.med, 0)::numeric, 3) i
        from r cur cross join lateral (select percentile_cont(0.5) within group (order by r2.views) med, count(*) n
                                         from r r2 where r2.account_id = cur.account_id and r2.at >= cur.at - interval '30 days' and r2.at < cur.at) b
       where cur.at >= f and cur.at < t and b.n >= 5 and b.med > 0) z;
    v_out := v_out || jsonb_build_object('ops.performance', jsonb_build_object('n', coalesce(cardinality(idx), 0),
      'median', (select round(percentile_cont(0.5) within group (order by i)::numeric, 2) from unnest(idx) i), '_idx', to_jsonb(coalesce(idx, '{}'))));

    -- supressão: mediana dos últimos 7 dias vs mediana dos 30 dias anteriores (mínimos 3 e 5 reels [pressuposto])
    with r as (
      select r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select count(*) n, percentile_cont(0.5) within group (order by views) med into r7 from r where at >= now() - interval '7 days';
    with r as (
      select r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select count(*) n, percentile_cont(0.5) within group (order by views) med into r30 from r where at >= now() - interval '37 days' and at < now() - interval '7 days';
    v_out := v_out || jsonb_build_object('ops.reach', jsonb_build_object('n7', r7.n, 'n30', r30.n,
      'median_7d', round(r7.med::numeric), 'median_30d', round(r30.med::numeric),
      'ratio', case when r7.n >= 3 and r30.n >= 5 and r30.med > 0 then round((r7.med / r30.med)::numeric * 100, 1) end));
  end if;
  return v_out;
end $$;

-- Números financeiros de um cliente num mês, já na moeda pedida. p_shared: custo repartido da agência para este cliente.
create or replace function public._biz_fin(p_ws text, p_month date, p_cur text, p_rate numeric, p_shared numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; m0 date := p_month; m1 date := (p_month + interval '1 month')::date; f timestamptz; t timestamptz; ref date;
        c client_contracts; mrr_o numeric; mrr numeric; ai numeric; direct numeric; direct_missing boolean; cost numeric; vids int; views bigint;
begin
  select timezone into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  f := m0::timestamp at time zone tz;
  t := least(m1::timestamp at time zone tz, now());
  ref := least(m1 - 1, today);
  c := public._biz_contract_at(p_ws, ref);
  mrr_o := public._biz_monthly(c, ref);
  mrr := public._biz_conv(mrr_o, c.currency, p_cur, p_rate);
  select round(coalesce(sum(cost_eur), 0), 2) into ai from agent_jobs where workspace_id = p_ws and finished_at >= f and finished_at < t
     and status in ('succeeded', 'failed', 'dead', 'cancelled');
  select coalesce(sum(public._biz_conv(amount, currency, p_cur, p_rate)), 0), bool_or(public._biz_conv(amount, currency, p_cur, p_rate) is null)
    into direct, direct_missing
    from agency_costs where workspace_id = p_ws and month = m0 and voided_at is null;
  cost := case when coalesce(direct_missing, false) or (ai > 0 and public._biz_conv(ai, 'EUR', p_cur, p_rate) is null) or p_shared is null then null
               else public._biz_conv(ai, 'EUR', p_cur, p_rate) + direct + p_shared end;
  vids := public._biz_published(p_ws, f, t);
  select coalesce(sum(r.views), 0) into views from reels r join accounts ac on ac.id = r.account_id
   where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client'
     and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) >= f and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) < t;
  return jsonb_build_object(
    'contract', c.id is not null,
    'contract_status', c.status,
    'amount', c.amount, 'contract_currency', c.currency, 'billing_period', c.billing_period,
    'fin.mrr', mrr, 'mrr_original', mrr_o,
    'fin.cost', cost, 'cost_ai', public._biz_conv(ai, 'EUR', p_cur, p_rate), 'cost_direct', direct, 'cost_shared', p_shared,
    'fin.margin', case when mrr > 0 and cost is not null then round(100 * (mrr - cost) / mrr, 1) end,
    'videos', vids, 'views', views,
    'fin.cost_per_video', case when vids > 0 and cost is not null then round(cost / vids, 2) end,
    'fin.cost_per_1k', case when views > 0 and cost is not null then round(cost / views * 1000, 2) end,
    'fin.payment', case when c.id is not null then jsonb_build_object('status', c.payment_status, 'due_on', c.payment_due_on,
                     'overdue_days', case when c.payment_status = 'vencido' and c.payment_due_on is not null and c.payment_due_on < today then today - c.payment_due_on end) end,
    'fin.renewal', case when c.renewal_on is not null then jsonb_build_object('on', c.renewal_on, 'days', c.renewal_on - today) end,
    'fx_missing', (mrr_o is not null and mrr is null) or cost is null);
end $$;

-- custo de IA por vídeo nos últimos 30 dias vs os 30 anteriores (para o alerta de +25% sem subida de volume)
create or replace function public._biz_ai_trend(p_ws text) returns jsonb language sql stable security definer set search_path = public as $$
  with w as (select
    (select coalesce(sum(cost_eur), 0) from agent_jobs where workspace_id = p_ws and finished_at >= now() - interval '30 days') c1,
    (select coalesce(sum(cost_eur), 0) from agent_jobs where workspace_id = p_ws and finished_at >= now() - interval '60 days' and finished_at < now() - interval '30 days') c0,
    public._biz_published(p_ws, now() - interval '30 days', now()) v1,
    public._biz_published(p_ws, now() - interval '60 days', now() - interval '30 days') v0)
  select jsonb_build_object('cpv_now', case when v1 > 0 then round(c1 / v1, 2) end, 'cpv_prev', case when v0 > 0 then round(c0 / v0, 2) end,
                            'videos_now', v1, 'videos_prev', v0,
                            'alert', v1 > 0 and v0 > 0 and c0 > 0 and (c1 / v1) > 1.25 * (c0 / v0) and v1 <= v0) from w
$$;

revoke execute on function public._biz_org(uuid), public._biz_require(text, text), public._biz_contract_at(text, date), public._biz_is_client_actor(text, text, uuid),
  public._biz_first_pub(text), public._biz_published(text, timestamptz, timestamptz), public._biz_stalled(text), public._biz_ops(text, date, text[]),
  public._biz_fin(text, date, text, numeric, numeric), public._biz_ai_trend(text) from public, anon, authenticated;
