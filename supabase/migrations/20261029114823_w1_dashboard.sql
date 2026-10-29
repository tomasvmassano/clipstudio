-- W1-10: Início por cliente com período e comparação, widgets por função, e vista da agência (PRD FR-01-01, FR-01-02, R-04; ADR-0017).
-- Só aditiva: 2 capacidades, 2 tabelas fechadas à API (registo de widgets e layout por cliente e função) e funções de leitura.
-- Cada métrica só sai a quem tem a capacidade dela, em cada cliente; a agência só agrega clientes a que a pessoa tem acesso.
-- Rollback: bloco no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('dashboard.configure', 'Início (M01)', 'M', array['ws'], 'ativo', 'Configurar os widgets do Início'),
  ('dashboard.agency', 'Agência', 'B', array['org'], 'ativo', 'Ver o painel da agência')
on conflict (key) do nothing;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'dashboard.configure'), ('ws', 'workspace_admin', 'dashboard.configure'),
  ('org', 'agency_owner', 'dashboard.agency'), ('org', 'agency_admin', 'dashboard.agency'),
  ('org', 'agency_manager', 'dashboard.agency'), ('org', 'agency_member', 'dashboard.agency')
on conflict do nothing;

-- registo de widgets: chave estável, o que mostra, como se calcula e de que capacidades precisa (todas)
create table public.dashboard_widgets (
  key text primary key check (key ~ '^[a-z]+\.[a-z_]+$'),
  kind text not null check (kind in ('kpi', 'chart', 'panel')),
  label text not null,
  description text not null,
  capabilities text[] not null,
  snapshot boolean not null default false,
  sort int not null
);
alter table public.dashboard_widgets enable row level security;
revoke all on public.dashboard_widgets from anon, authenticated;

insert into public.dashboard_widgets (key, kind, label, description, capabilities, snapshot, sort) values
  ('kpi.sources', 'kpi', 'Fontes recebidas', 'Fontes (ideias, notícias, livros) que entraram no período, vindas dos agentes ou da equipa.', array['sources.read'], false, 10),
  ('kpi.scripts_created', 'kpi', 'Guiões criados', 'Guiões novos criados no período, pelo motor ou pela equipa.', array['scripts.read'], false, 20),
  ('kpi.pending_approval', 'kpi', 'À espera de aprovação', 'Guiões em revisão neste momento. É uma fotografia de agora, sem comparação.', array['scripts.read'], true, 30),
  ('kpi.approved', 'kpi', 'Aprovados', 'Guiões que passaram a aprovados no período (cada guião conta uma vez).', array['scripts.read'], false, 40),
  ('kpi.recorded', 'kpi', 'Gravados', 'Guiões marcados como gravados no período, no teleprompter ou na produção.', array['scripts.read'], false, 50),
  ('kpi.published', 'kpi', 'Publicados', 'Conteúdos publicados no período. Enquanto não houver publicação ligada, conta só o que for marcado como publicado.', array['analytics.read'], false, 60),
  ('kpi.views', 'kpi', 'Views', 'Soma das views dos reels das contas do cliente publicados no período, com os números da última recolha.', array['analytics.read'], false, 70),
  ('kpi.engagement', 'kpi', 'Engagement', '(Likes + comentários + partilhas) ÷ views dos reels publicados no período.', array['analytics.read'], false, 80),
  ('kpi.costs', 'kpi', 'Custo dos agentes', 'Custo das execuções dos agentes terminadas no período, em EUR. Execuções sem custo conhecido ficam à parte.', array['costs.read'], false, 90),
  ('kpi.tasks_done', 'kpi', 'Tarefas concluídas', 'Tarefas fechadas como feitas no período (produtividade da equipa).', array['tasks.read'], false, 100),
  ('chart.views_daily', 'chart', 'Views por dia', 'Views por dia de publicação, nos últimos 60 dias.', array['analytics.read'], false, 200),
  ('chart.format_mix', 'chart', 'Formatos de hoje', 'Peso de cada formato nos guiões de hoje.', array['scripts.read'], false, 210),
  ('chart.production', 'chart', 'Produção por dia', 'Validados, gravados e rejeitados por dia, nos últimos 10 dias.', array['analytics.read'], false, 220),
  ('chart.weekly_avg', 'chart', 'Média semanal de views', 'Média de views por reel em cada semana.', array['analytics.read'], false, 230),
  ('panel.agents', 'panel', 'Agentes', 'Estado de cada agente na última execução real (os ensaios ficam de fora).', array['analytics.read', 'agents.read'], false, 300),
  ('panel.scripts_today', 'panel', 'Guiões de hoje', 'Os guiões do dia, por número.', array['scripts.read'], false, 310),
  ('panel.activity', 'panel', 'Atividade recente', 'Últimas validações, gravações, rejeições e execuções do motor.', array['analytics.read'], false, 320);

create table public.dashboard_layouts (
  workspace_id text not null references public.clients(id),
  role text not null check (role in ('workspace_owner', 'workspace_admin', 'manager', 'reviewer', 'contributor', 'viewer')),
  widgets text[] not null check (cardinality(widgets) between 1 and 30),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, role)
);
alter table public.dashboard_layouts enable row level security;
revoke all on public.dashboard_layouts from anon, authenticated;

-- layout por omissão de cada função (o cliente pode mudar com dashboard.configure)
create or replace function public._dashboard_default(p_role text) returns text[] language sql immutable set search_path = public as $$
  select case p_role
    when 'workspace_owner' then array['kpi.scripts_created','kpi.pending_approval','kpi.recorded','kpi.views','kpi.engagement','kpi.sources','kpi.approved','kpi.costs',
                                      'chart.views_daily','chart.format_mix','chart.production','chart.weekly_avg','panel.agents','panel.scripts_today','panel.activity']
    when 'workspace_admin' then array['kpi.scripts_created','kpi.pending_approval','kpi.recorded','kpi.views','kpi.engagement','kpi.sources','kpi.approved','kpi.costs',
                                      'chart.views_daily','chart.format_mix','chart.production','chart.weekly_avg','panel.agents','panel.scripts_today','panel.activity']
    when 'manager' then array['kpi.scripts_created','kpi.pending_approval','kpi.recorded','kpi.views','kpi.sources','kpi.approved','kpi.tasks_done','kpi.engagement',
                              'chart.views_daily','chart.format_mix','chart.production','chart.weekly_avg','panel.agents','panel.scripts_today','panel.activity']
    when 'reviewer' then array['kpi.pending_approval','kpi.approved','kpi.scripts_created','kpi.recorded','chart.production','panel.scripts_today','panel.activity']
    when 'contributor' then array['kpi.scripts_created','kpi.pending_approval','kpi.recorded','kpi.tasks_done','chart.format_mix','chart.production','panel.scripts_today','panel.activity']
    else array['kpi.views','kpi.engagement','kpi.published','kpi.recorded','chart.views_daily','chart.weekly_avg']
  end
$$;

-- métricas de um cliente numa janela [f, t) (sem verificar acesso: só chamada pelas funções abaixo)
create or replace function public._dashboard_window(p_ws text, f timestamptz, t timestamptz) returns jsonb
language sql stable security definer set search_path = public as $$
  with rv as (
    select r.views, r.likes, r.comments, r.shares from reels r join accounts a on a.id = r.account_id
     where r.client_id = p_ws and a.client_id = p_ws and a.role = 'client'
       and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) >= f and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) < t),
  jobs as (select cost_eur from agent_jobs where workspace_id = p_ws and status in ('succeeded', 'failed', 'dead', 'cancelled')
             and finished_at >= f and finished_at < t)
  select jsonb_build_object(
    'kpi.sources', (select count(*) from ideas where client_id = p_ws and kind = 'source' and created_at >= f and created_at < t),
    'kpi.scripts_created', (select count(*) from guioes where client_id = p_ws and created_at >= f and created_at < t),
    'kpi.approved', (select count(distinct content_id) from content_transitions where workspace_id = p_ws and kind = 'editorial' and to_status = 'approved' and at >= f and at < t),
    'kpi.recorded', (select count(*) from (select id from guioes where client_id = p_ws and gravado_em >= f and gravado_em < t
                                            union select content_id from content_transitions where workspace_id = p_ws and kind = 'production'
                                                     and to_status = 'recorded' and at >= f and at < t) x),
    'kpi.published', (select count(*) from (select p.guiao_id from publicacoes p join guioes g on g.id = p.guiao_id where g.client_id = p_ws and p.published_at >= f and p.published_at < t
                                             union select content_id from content_transitions where workspace_id = p_ws and kind = 'production'
                                                      and to_status = 'published' and at >= f and at < t) x),
    'kpi.views', (select coalesce(sum(views), 0) from rv),
    'kpi.engagement', (select case when sum(views) > 0 then round(100.0 * sum(coalesce(likes, 0) + coalesce(comments, 0) + coalesce(shares, 0)) / sum(views), 2) end from rv),
    'kpi.costs', (select round(coalesce(sum(cost_eur), 0), 2) from jobs),
    'costs_unknown', (select count(*) from jobs where cost_eur is null),
    'kpi.tasks_done', (select count(*) from tasks where workspace_id = p_ws and status = 'done' and completed_at >= f and completed_at < t),
    'reels', (select count(*) from rv))
$$;
revoke execute on function public._dashboard_window(text, timestamptz, timestamptz) from public, anon, authenticated;

-- KPIs de um cliente no período e no período anterior do mesmo tamanho, só os que p_caps deixa ver
create or replace function public._dashboard_kpis(p_ws text, p_from date, p_to date, p_caps text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; len int; cur jsonb; prev jsonb; w record; v_out jsonb := '{}';
begin
  select timezone into tz from clients where id = p_ws;
  len := p_to - p_from + 1;
  cur := _dashboard_window(p_ws, (p_from::timestamp at time zone tz), ((p_to + 1)::timestamp at time zone tz));
  prev := _dashboard_window(p_ws, ((p_from - len)::timestamp at time zone tz), (p_from::timestamp at time zone tz));
  for w in select * from dashboard_widgets where kind = 'kpi' loop
    if w.capabilities <@ p_caps then
      v_out := v_out || jsonb_build_object(w.key, case when w.key = 'kpi.pending_approval'
        then jsonb_build_object('value', (select count(*) from guioes where client_id = p_ws and editorial_status = 'in_review'), 'prev', null)
        else jsonb_build_object('value', cur->w.key, 'prev', prev->w.key) end);
    end if;
  end loop;
  if v_out ? 'kpi.costs' then v_out := v_out || jsonb_build_object('costs_unknown', cur->'costs_unknown'); end if;
  if v_out ? 'kpi.views' then v_out := v_out || jsonb_build_object('reels', cur->'reels'); end if;
  return v_out;
end $$;
revoke execute on function public._dashboard_kpis(text, date, date, text[]) from public, anon, authenticated;

create or replace function public._dashboard_range(p_from date, p_to date) returns void language plpgsql immutable set search_path = public as $$
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  if p_to - p_from > 365 then raise exception 'periodo_demasiado_longo' using errcode = '22023'; end if;
end $$;

-- capacidades de um ator num cliente (utilizador ou código de equipa antigo)
create or replace function public._dashboard_caps(p_ws text, p_token text) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct c), '{}') from (select unnest(capabilities) c from dashboard_widgets) x where public.ws_can(c, p_ws, p_token)
$$;
revoke execute on function public._dashboard_caps(text, text) from public, anon, authenticated;

create or replace function public._dashboard_role(p_ws text, p_token text) returns text
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then 'contributor'
              else coalesce((select a.workspace_role from workspace_access a where a.workspace_id = p_ws and a.user_id = auth.uid() and a.status = 'active'
                              and (a.expires_at is null or a.expires_at > now())), 'workspace_owner') end
$$;
revoke execute on function public._dashboard_role(text, text) from public, anon, authenticated;

create or replace function public.dashboard_get(p_ws text, p_from date, p_to date, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare caps text[]; v_role text; layout text[]; target int;
begin
  perform _dashboard_range(p_from, p_to);
  caps := _dashboard_caps(p_ws, p_token);
  if cardinality(caps) = 0 then raise exception 'sem_permissao' using errcode = '42501'; end if;
  v_role := _dashboard_role(p_ws, p_token);   -- código antigo usa o layout de contributor; dono da agência sem papel usa o de dono
  layout := coalesce((select l.widgets from dashboard_layouts l where l.workspace_id = p_ws and l.role = v_role), _dashboard_default(v_role));
  select nullif(v.config #>> '{pipeline,scripts_per_day}', '')::int into target
    from agent_config_versions v where v.workspace_id = p_ws and v.status = 'active' limit 1;
  return jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', p_from - (p_to - p_from + 1), 'prev_to', p_from - 1),
    'role', v_role,
    'customized', exists (select 1 from dashboard_layouts l where l.workspace_id = p_ws and l.role = v_role),
    'can_configure', auth.uid() is not null and _authorize('dashboard.configure', p_ws, auth.uid()),
    'widgets', (select coalesce(jsonb_agg(jsonb_build_object('key', w.key, 'kind', w.kind, 'label', w.label, 'description', w.description, 'snapshot', w.snapshot)
                                          order by array_position(layout, w.key)), '[]')
                from dashboard_widgets w where w.key = any(layout) and w.capabilities <@ caps),
    'kpis', _dashboard_kpis(p_ws, p_from, p_to, caps),
    'target_per_day', case when 'scripts.read' = any(caps) then target end);
end $$;
grant execute on function public.dashboard_get(text, date, date, text) to anon, authenticated;

-- configuração: layouts de todas as funções do cliente e o registo de widgets
create or replace function public.dashboard_layouts_get(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.authorize('dashboard.configure', p_ws) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'widgets', (select jsonb_agg(jsonb_build_object('key', key, 'kind', kind, 'label', label, 'description', description,
                  'capabilities', capabilities, 'snapshot', snapshot) order by sort) from dashboard_widgets),
    'roles', (select jsonb_agg(jsonb_build_object('role', r, 'widgets', coalesce(l.widgets, _dashboard_default(r)), 'customized', l.role is not null,
                  'updated_at', l.updated_at) order by o)
              from unnest(array['workspace_owner','workspace_admin','manager','reviewer','contributor','viewer']) with ordinality u(r, o)
              left join dashboard_layouts l on l.workspace_id = p_ws and l.role = u.r));
end $$;
revoke execute on function public.dashboard_layouts_get(text) from public, anon;
grant execute on function public.dashboard_layouts_get(text) to authenticated;

create or replace function public.dashboard_layout_set(p_ws text, p_role text, p_widgets text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); before text[]; bad text;
begin
  if not public.authorize('dashboard.configure', p_ws) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_role not in ('workspace_owner','workspace_admin','manager','reviewer','contributor','viewer') then raise exception 'funcao_invalida' using errcode = '22023'; end if;
  if p_widgets is null or cardinality(p_widgets) = 0 then raise exception 'widgets_vazios' using errcode = '22023'; end if;
  if cardinality(p_widgets) > 30 or cardinality(p_widgets) <> (select count(distinct x) from unnest(p_widgets) x) then
    raise exception 'widgets_invalidos' using errcode = '22023'; end if;
  select x into bad from unnest(p_widgets) x where not exists (select 1 from dashboard_widgets w where w.key = x) limit 1;
  if bad is not null then raise exception 'widget_desconhecido:%', left(bad, 60) using errcode = '22023'; end if;
  select widgets into before from dashboard_layouts where workspace_id = p_ws and role = p_role;
  insert into dashboard_layouts (workspace_id, role, widgets, updated_by) values (p_ws, p_role, p_widgets, uid)
  on conflict (workspace_id, role) do update set widgets = excluded.widgets, updated_by = uid, updated_at = now();
  insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', p_ws, 'dashboard.layout_set', 'dashboard_layout', p_role,
          jsonb_build_object('widgets', coalesce(before, _dashboard_default(p_role))), jsonb_build_object('widgets', p_widgets));
  return public.dashboard_layouts_get(p_ws);
end $$;
revoke execute on function public.dashboard_layout_set(text, text, text[]) from public, anon;
grant execute on function public.dashboard_layout_set(text, text, text[]) to authenticated;

create or replace function public.dashboard_layout_reset(p_ws text, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); before text[];
begin
  if not public.authorize('dashboard.configure', p_ws) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  delete from dashboard_layouts where workspace_id = p_ws and role = p_role returning widgets into before;
  if before is not null then
    insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, entity_id, before, after)
    values (uid, 'user', p_ws, 'dashboard.layout_reset', 'dashboard_layout', p_role, jsonb_build_object('widgets', before),
            jsonb_build_object('widgets', _dashboard_default(p_role)));
  end if;
  return public.dashboard_layouts_get(p_ws);
end $$;
revoke execute on function public.dashboard_layout_reset(text, text) from public, anon;
grant execute on function public.dashboard_layout_reset(text, text) to authenticated;

-- painel da agência: só clientes ativos a que a pessoa tem acesso; cada número só com a capacidade nesse cliente
create or replace function public.agency_dashboard(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; v_rows jsonb := '[]'; c record; caps text[]; k jsonb; tot jsonb := '{}'; missing jsonb := '{}'; key text;
        ev numeric := 0; evw numeric := 0; ep numeric := 0; epw numeric := 0; n int := 0;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  perform _dashboard_range(p_from, p_to);
  select m.organization_id into v_org from agency_memberships m where m.user_id = uid and public._org_can('dashboard.agency', m.organization_id, uid) limit 1;
  if v_org is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  for c in select cl.* from clients cl where cl.organization_id = v_org and cl.status = 'active'
             and (public.is_agency_owner(uid) or exists (select 1 from workspace_access a where a.workspace_id = cl.id and a.user_id = uid and a.status = 'active'
                                                          and (a.expires_at is null or a.expires_at > now())))
           order by lower(cl.name) loop
    caps := (select coalesce(array_agg(distinct x), '{}') from (select unnest(capabilities) x from dashboard_widgets) y where _authorize(x, c.id, uid));
    if cardinality(caps) = 0 then continue; end if;
    n := n + 1;
    k := _dashboard_kpis(c.id, p_from, p_to, caps);
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'logo_path', c.logo_path,
              'brand_color', c.brand_color, 'timezone', c.timezone, 'kpis', k));
    for key in select w.key from dashboard_widgets w where w.kind = 'kpi' and w.key <> 'kpi.engagement' loop
      if k ? key then
        tot := jsonb_set(tot, array[key], jsonb_build_object(
          'value', coalesce((tot #>> array[key, 'value'])::numeric, 0) + coalesce((k #>> array[key, 'value'])::numeric, 0),
          'prev', case when key = 'kpi.pending_approval' then null
                       else coalesce((tot #>> array[key, 'prev'])::numeric, 0) + coalesce((k #>> array[key, 'prev'])::numeric, 0) end));
      else missing := jsonb_set(missing, array[key], to_jsonb(coalesce((missing ->> key)::int, 0) + 1)); end if;
    end loop;
    -- engagement da agência: média ponderada pelas views de cada cliente
    if k ? 'kpi.engagement' and k ? 'kpi.views' then
      ev := ev + coalesce((k #>> '{kpi.engagement,value}')::numeric, 0) * coalesce((k #>> '{kpi.views,value}')::numeric, 0);
      evw := evw + coalesce((k #>> '{kpi.views,value}')::numeric, 0);
      ep := ep + coalesce((k #>> '{kpi.engagement,prev}')::numeric, 0) * coalesce((k #>> '{kpi.views,prev}')::numeric, 0);
      epw := epw + coalesce((k #>> '{kpi.views,prev}')::numeric, 0);
    else missing := jsonb_set(missing, '{kpi.engagement}', to_jsonb(coalesce((missing ->> 'kpi.engagement')::int, 0) + 1)); end if;
  end loop;
  if n > 0 and not (missing ? 'kpi.engagement' and (missing ->> 'kpi.engagement')::int = n) then
    tot := tot || jsonb_build_object('kpi.engagement', jsonb_build_object('value', case when evw > 0 then round(ev / evw, 2) end,
                                                                          'prev', case when epw > 0 then round(ep / epw, 2) end));
  end if;
  return jsonb_build_object('period', jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', p_from - (p_to - p_from + 1), 'prev_to', p_from - 1),
    'clients', v_rows, 'totals', tot, 'missing', missing, 'count', n);
end $$;
revoke execute on function public.agency_dashboard(date, date) from public, anon;
grant execute on function public.agency_dashboard(date, date) to authenticated;

/* Rollback:
drop function agency_dashboard(date, date); drop function dashboard_layout_reset(text, text); drop function dashboard_layout_set(text, text, text[]);
drop function dashboard_layouts_get(text); drop function dashboard_get(text, date, date, text); drop function _dashboard_role(text, text);
drop function _dashboard_caps(text, text); drop function _dashboard_range(date, date); drop function _dashboard_kpis(text, date, date, text[]);
drop function _dashboard_window(text, timestamptz, timestamptz); drop function _dashboard_default(text);
drop table dashboard_layouts; drop table dashboard_widgets;
delete from role_capabilities where capability in ('dashboard.configure', 'dashboard.agency');
delete from capabilities where key in ('dashboard.configure', 'dashboard.agency');
*/
