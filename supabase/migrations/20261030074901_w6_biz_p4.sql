-- Parte 4 de 4 de 20261030000100_w6_biz.sql (aplicada em produção como w6_biz_p4).

create or replace function public.biz_fx_save(p_rate numeric, p_as_of date, p_source text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.fx_save'); uid uuid := auth.uid(); r fx_rates;
begin
  if p_rate is null or p_rate <= 0 or p_rate >= 1000 then raise exception 'taxa_invalida' using errcode = '22023', detail = 'A taxa tem de ser maior que 0 (AED por 1 EUR).'; end if;
  if p_as_of is null or p_as_of > current_date + 1 then raise exception 'data_invalida' using errcode = '22023', detail = 'Indica a data da taxa (não pode ser futura).'; end if;
  insert into fx_rates (organization_id, rate, as_of, source, created_by, created_label)
  values (org, round(p_rate, 6), p_as_of, nullif(left(trim(coalesce(p_source, '')), 120), ''), uid, (select email from auth.users where id = uid))
  returning * into r;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', r.created_label, org, 'biz.fx_saved', 'fx_rate', r.id::text, null, to_jsonb(r) - 'created_by');
  return public.biz_contracts();
end $$;

create or replace function public.biz_costs(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.costs'); m date := public._biz_month(p_month);
begin
  return jsonb_build_object('month', m, 'can_manage', public._org_can('contracts.manage', org, auth.uid()),
    'costs', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'workspace_id', k.workspace_id, 'client_name', c.name, 'month', k.month, 'kind', k.kind,
        'label', k.label, 'amount', k.amount, 'currency', k.currency, 'allocation', k.allocation, 'created_at', k.created_at, 'created_label', k.created_label,
        'voided_at', k.voided_at, 'void_reason', k.void_reason) order by k.voided_at nulls first, k.created_at desc)
      from agency_costs k left join clients c on c.id = k.workspace_id where k.organization_id = org and k.month = m), '[]'));
end $$;

-- Acrescentar um custo. p_client_ref torna a gravação idempotente (repetir o pedido não duplica).
create or replace function public.biz_cost_save(p_fields jsonb, p_client_ref uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.cost_save'); uid uuid := auth.uid(); r agency_costs; m date; ws text; k text;
begin
  if p_client_ref is null then raise exception 'referencia_obrigatoria' using errcode = '22023'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campo_invalido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('workspace_id', 'month', 'kind', 'label', 'amount', 'currency', 'allocation') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k);
    end if;
  end loop;
  select * into r from agency_costs where organization_id = org and client_ref = p_client_ref;
  if r.id is not null then return public.biz_costs(r.month); end if;
  begin
    m := public._biz_month((p_fields ->> 'month')::date);
  exception when invalid_datetime_format or datetime_field_overflow or invalid_text_representation then
    raise exception 'periodo_invalido' using errcode = '22023', detail = 'Mês inválido.';
  end;
  ws := nullif(p_fields ->> 'workspace_id', '');
  if ws is not null and not exists (select 1 from clients where id = ws and organization_id = org) then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  begin
    insert into agency_costs (organization_id, workspace_id, month, kind, label, amount, currency, allocation, client_ref, created_by, created_label)
    values (org, ws, m, p_fields ->> 'kind', trim(coalesce(p_fields ->> 'label', '')), (p_fields ->> 'amount')::numeric, p_fields ->> 'currency',
            coalesce(nullif(p_fields ->> 'allocation', ''), case when ws is null then 'igual' else 'direto' end), p_client_ref, uid, (select email from auth.users where id = uid))
    returning * into r;
  exception
    when check_violation or not_null_violation then
      raise exception 'custo_invalido' using errcode = '22023', detail = 'Indica tipo, descrição (2 a 120 caracteres), valor e moeda. Custo de um cliente é direto; da agência reparte-se por igual ou por vídeos.';
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'custo_invalido' using errcode = '22023', detail = 'Valor inválido.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', r.created_label, org, ws, 'biz.cost_saved', 'agency_cost', r.id::text, null, to_jsonb(r) - 'created_by');
  return public.biz_costs(m);
end $$;

create or replace function public.biz_cost_void(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.cost_void'); uid uuid := auth.uid(); old agency_costs; r agency_costs;
begin
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  select * into old from agency_costs where id = p_id and organization_id = org for update;
  if old.id is null then raise exception 'custo_nao_encontrado' using errcode = 'P0002'; end if;
  if old.voided_at is not null then return public.biz_costs(old.month); end if;
  update agency_costs set voided_at = now(), voided_by = uid, void_reason = left(trim(p_reason), 300) where id = p_id returning * into r;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), org, r.workspace_id, 'biz.cost_voided', 'agency_cost', r.id::text,
          to_jsonb(old) - 'created_by', to_jsonb(r) - 'created_by');
  return public.biz_costs(r.month);
end $$;

revoke all on function public.biz_overview(date, text), public.biz_contracts(), public.biz_contract_history(text), public.biz_contract_save(text, jsonb, int),
  public.biz_fx_save(numeric, date, text), public.biz_costs(date), public.biz_cost_save(jsonb, uuid), public.biz_cost_void(uuid, text) from public, anon;
grant execute on function public.biz_overview(date, text), public.biz_contracts(), public.biz_contract_history(text), public.biz_contract_save(text, jsonb, int),
  public.biz_fx_save(numeric, date, text), public.biz_costs(date), public.biz_cost_save(jsonb, uuid), public.biz_cost_void(uuid, text) to authenticated;

/* Rollback (compatível, nada existente depende disto):
drop function public.biz_cost_void(uuid, text), public.biz_cost_save(jsonb, uuid), public.biz_costs(date), public.biz_fx_save(numeric, date, text),
  public.biz_contract_save(text, jsonb, int), public.biz_contract_history(text), public.biz_contracts(), public.biz_overview(date, text),
  public._biz_ai_trend(text), public._biz_fin(text, date, text, numeric, numeric), public._biz_ops(text, date, text[]), public._biz_stalled(text),
  public._biz_published(text, timestamptz, timestamptz), public._biz_first_pub(text), public._biz_is_client_actor(text, text, uuid),
  public._biz_monthly(client_contracts, date), public._biz_contract_at(text, date), public._biz_month(date), public._biz_conv(numeric, text, text, numeric),
  public._biz_require(text, text), public._biz_pt(numeric), public._biz_org(uuid);
delete from feature_flags where key = 'biz.view'; delete from feature_flag_defs where key = 'biz.view';
delete from role_capabilities where capability in ('biz.read', 'biz.finance', 'contracts.manage');
-- contract posterior (destrutivo, só depois de backup): drop table public.biz_metrics, public.agency_costs, public.fx_rates, public.client_contracts;
--   drop function public.agency_costs_guard(); delete from capabilities where key in ('biz.read', 'biz.finance', 'contracts.manage');
*/
