-- Parte 2 de 2 de 20261030120300_w7_learn_team_privacy_costs.sql (aplicada em produção como w7_learn_team_privacy_costs_p2).

create or replace function public.privacy_request_resolve(p_id uuid, p_status text, p_resolution text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid := (select organization_id from agency_memberships where user_id = uid and status = 'active' order by created_at limit 1);
        r privacy_requests;
begin
  if org is null or not public._org_can('privacy.manage', org, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into r from privacy_requests where id = p_id for update;
  if r.id is null or not public._privacy_in_org(r.user_id, org) then raise exception 'pedido_nao_encontrado' using errcode = 'P0002'; end if;
  if p_status not in ('tratado', 'recusado') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if char_length(btrim(coalesce(p_resolution, ''))) < 5 then
    raise exception 'resolucao_obrigatoria' using errcode = '22023', detail = 'Explica o que foi feito (pelo menos 5 caracteres).'; end if;
  if r.status <> 'pendente' then raise exception 'pedido_fechado' using errcode = '22023'; end if;
  update privacy_requests set status = p_status, resolution = left(btrim(p_resolution), 1000), resolved_at = now(), resolved_by = uid
   where id = p_id returning * into r;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), org, 'privacy.request_resolved', 'privacy_request', r.id::text,
          jsonb_build_object('status', 'pendente'), jsonb_build_object('status', r.status, 'resolution', r.resolution));
  return public.privacy_requests_admin();
end $$;

-- ───────────── FR-10-05: custo por guião, vídeo e publicação ─────────────
create or replace function public._costs_rows(p_ws text, p_months int)
returns table (content_id text, m date, cost numeric, method text, job_id uuid)
language sql stable security definer set search_path = public as $$
  with tz as (select coalesce(timezone, 'Asia/Dubai') tz from clients where id = p_ws),
  jobs as (
    select j.id, j.run_id, j.cost_eur, date_trunc('month', j.finished_at at time zone (select tz from tz))::date m
    from agent_jobs j
    where j.workspace_id = p_ws and j.finished_at is not null
      and j.finished_at >= (date_trunc('month', now() at time zone (select tz from tz)) - make_interval(months => p_months - 1)) at time zone (select tz from tz)),
  outs as (select o.job_id, o.slot, o.content_id from agent_job_outputs o join jobs on jobs.id = o.job_id where o.workspace_id = p_ws),
  logc as (select l.run_id, l.slot, sum(l.cost_eur) c from agent_log l
           where l.client_id = p_ws and l.run_id in (select run_id from jobs where run_id is not null) and l.cost_eur is not null group by l.run_id, l.slot),
  per as (
    select o.content_id, j.m, j.id job_id, j.cost_eur,
      (select count(*) from outs o3 where o3.job_id = j.id) n_out,
      (select sum(lc.c) from outs o2 join logc lc on lc.run_id = j.run_id and lc.slot = o2.slot where o2.job_id = j.id) slot_total,
      (select lc.c from logc lc where lc.run_id = j.run_id and lc.slot = o.slot) slot_cost
    from outs o join jobs j on j.id = o.job_id)
  select content_id, m,
    case when cost_eur is null then null
         when slot_total > 0 then round(cost_eur * coalesce(slot_cost, 0) / slot_total, 4)
         else round(cost_eur / n_out, 4) end,
    case when cost_eur is null then 'desconhecido' when slot_total > 0 then 'por_posicao' else 'partes_iguais' end,
    job_id
  from per
$$;

create or replace function public._costs_report(p_ws text, p_months int) returns jsonb
language sql stable security definer set search_path = public as $$
  with tz as (select coalesce(timezone, 'Asia/Dubai') tz from clients where id = p_ws),
  months as (select (date_trunc('month', now() at time zone (select tz from tz)) - make_interval(months => i))::date m from generate_series(0, p_months - 1) i),
  jobs as (
    select j.id, j.cost_eur, date_trunc('month', j.finished_at at time zone (select tz from tz))::date m,
           exists (select 1 from agent_job_outputs o where o.job_id = j.id) has_out
    from agent_jobs j where j.workspace_id = p_ws and j.finished_at is not null
      and j.finished_at >= (select min(m) from months)::timestamp at time zone (select tz from tz)),
  cr as (select * from public._costs_rows(p_ws, p_months)),
  sc as (select content_id, sum(cost) cost, bool_or(cost is null) has_unknown, min(method) method, count(distinct job_id) jobs from cr group by content_id),
  pubs as (
    select distinct on (content_id, account_id, ext) content_id, account_id, ext, published_at from (
      select p.guiao_id content_id, p.account_id, coalesce(p.reel_id, p.url, p.id::text) ext, p.published_at
      from publicacoes p join guioes g on g.id = p.guiao_id and g.client_id = p_ws
      union all
      select l.content_id, l.account_id, l.external_id, l.published_at from publication_lineage l where l.workspace_id = p_ws and l.content_id is not null) z
    where content_id in (select content_id from sc)
    order by content_id, account_id, ext, published_at nulls last),
  npub as (select content_id, count(*) n from pubs group by content_id),
  pubcost as (select p.*, date_trunc('month', p.published_at at time zone (select tz from tz))::date m, sc.cost / np.n cost
              from pubs p join sc on sc.content_id = p.content_id join npub np on np.content_id = p.content_id where not sc.has_unknown)
  select jsonb_build_object(
    'currency', 'EUR', 'months', p_months,
    'allocation', 'O custo de cada execução do motor é repartido pelos guiões que gerou: pelo custo por posição registado no agent_log quando existe, senão em partes iguais. O custo de uma publicação é o custo do guião repartido pelas suas publicações. Execuções sem custo conhecido ficam à parte, nunca contam como zero.',
    'video', jsonb_build_object('available', false, 'reason', 'Ainda não há custos de edição nem de render registados por vídeo (a edição automática ainda não está alojada). Quando houver, entram aqui.'),
    'by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(mo.m, 'YYYY-MM'),
        'ai_total', (select round(coalesce(sum(cost_eur), 0), 2) from jobs where jobs.m = mo.m),
        'jobs_unknown', (select count(*) from jobs where jobs.m = mo.m and cost_eur is null),
        'unattributed', (select round(coalesce(sum(cost_eur), 0), 2) from jobs where jobs.m = mo.m and not has_out),
        'attributed', (select round(coalesce(sum(cost), 0), 2) from cr where cr.m = mo.m),
        'scripts', (select count(distinct content_id) from cr where cr.m = mo.m and cost is not null),
        'cost_per_script', (select case when count(distinct content_id) > 0 then round(sum(cost) / count(distinct content_id), 4) end from cr where cr.m = mo.m and cost is not null),
        'publications', (select count(*) from pubcost where pubcost.m = mo.m),
        'cost_per_publication', (select round(avg(cost), 4) from pubcost where pubcost.m = mo.m)) order by mo.m desc) from months mo), '[]'),
    'scripts', coalesce((select jsonb_agg(jsonb_build_object('content_id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'editorial_status', g.editorial_status,
        'cost_eur', case when sc.has_unknown then null else round(sc.cost, 4) end, 'cost_known', not sc.has_unknown, 'method', sc.method, 'jobs', sc.jobs,
        'publications', coalesce(np.n, 0),
        'cost_per_publication', case when not sc.has_unknown and np.n > 0 then round(sc.cost / np.n, 4) end) order by g.date desc, g.n desc)
      from sc join guioes g on g.id = sc.content_id and g.client_id = p_ws left join npub np on np.content_id = sc.content_id), '[]'))
$$;

create or replace function public.content_costs(p_ws text, p_months int default 6, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._learn_require('costs.content', 'costs.read', p_ws, p_token, 'costs.content');
  return public._costs_report(p_ws, least(24, greatest(1, coalesce(p_months, 6))));
end $$;

-- Exportar (CSV montado no browser a partir disto): igual à leitura, mais auditoria.
create or replace function public.content_costs_export(p_ws text, p_months int default 6, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; a jsonb := public._content_actor(p_token);
begin
  perform public._learn_require('costs.content', 'costs.read', p_ws, p_token, 'costs.export');
  res := public._costs_report(p_ws, least(24, greatest(1, coalesce(p_months, 6))));
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'costs.exported', 'costs', p_ws,
          jsonb_build_object('months', res->'months', 'scripts', jsonb_array_length(res->'scripts')));
  return res;
end $$;

revoke all on function public._job_title_templates(), public._invitation_apply_title(), public._data_export_on(uuid), public._privacy_req_json(privacy_requests),
  public._privacy_in_org(uuid, uuid), public._costs_rows(text, int), public._costs_report(text, int) from public, anon, authenticated;
revoke all on function public.job_title_templates(text), public.invite_member_with_title(text, text, text, text, text, text[]),
  public.my_data_status(), public.my_data_export(), public.my_data_deletion_request(text), public.privacy_requests_admin(),
  public.privacy_request_resolve(uuid, text, text), public.content_costs(text, int, text), public.content_costs_export(text, int, text) from public, anon;
grant execute on function public.job_title_templates(text), public.invite_member_with_title(text, text, text, text, text, text[]),
  public.my_data_status(), public.my_data_export(), public.my_data_deletion_request(text), public.privacy_requests_admin(),
  public.privacy_request_resolve(uuid, text, text) to authenticated;
-- custos aceitam o código de equipa na assinatura (mesmo padrão), mas legacy_can nunca inclui costs.read: recusa sempre.
grant execute on function public.content_costs(text, int, text), public.content_costs_export(text, int, text) to anon, authenticated;

/* Rollback (compatível: invite_member, accept_invitations, grant_set e _authorize não mudaram):
   drop trigger invitations_apply_title on public.invitations;
   drop function public.content_costs_export(text, int, text), public.content_costs(text, int, text), public._costs_report(text, int), public._costs_rows(text, int),
     public.privacy_request_resolve(uuid, text, text), public.privacy_requests_admin(), public._privacy_in_org(uuid, uuid), public.my_data_deletion_request(text),
     public.my_data_export(), public.my_data_status(), public._privacy_req_json(privacy_requests), public._data_export_on(uuid),
     public._invitation_apply_title(), public.invite_member_with_title(text, text, text, text, text, text[]), public.job_title_templates(text),
     public._job_title_templates();
   delete from feature_flags where key in ('team.job_titles', 'profile.data_export', 'costs.content');
   delete from feature_flag_defs where key in ('team.job_titles', 'profile.data_export', 'costs.content');
   delete from role_capabilities where capability = 'privacy.manage';
   -- as exceções já criadas por convites com cargo ficam (são exceções normais, revogáveis na consola)
-- contract posterior (só depois de exportar): drop table public.privacy_requests;
   alter table public.invitations drop column suggested_grants, drop column job_title_key, drop column job_title; */
