-- W3-02 Calendário e estados de produção (PRD M11 FR-11-01/02/03 parcial/05 parcial, workflow-registry "Produção"; AGENTS §6).
-- Estados de produção: not_started → scheduled → recorded → editing → ready (→ published no W6), cancelled; cada um com a sua capacidade.
-- Reagendar um guião (arrastar no calendário) com validação e conflito de edição. Vista de calendário com guiões, tarefas e sessões.
-- As automações de tarefas passam a poder reagir a "em edição" e "pronto". Só aditivo / alargamento compatível com main.
-- Rollback: bloco no fim.

insert into public.capabilities (key, module, risk, scopes, status) values
  ('calendar.read', 'Calendário', 'B', '{ws}', 'ativo'),
  ('calendar.schedule', 'Calendário', 'M', '{ws,proj}', 'ativo'),
  ('production.update', 'Calendário', 'M', '{ws,own}', 'ativo')
on conflict (key) do nothing;
insert into public.role_capabilities (scope, role, capability)
select 'ws', r, 'calendar.read' from unnest(array['workspace_owner','workspace_admin','manager','contributor','reviewer','viewer']) r
union all select 'ws', r, 'calendar.schedule' from unnest(array['workspace_owner','workspace_admin','manager']) r
union all select 'ws', r, 'production.update' from unnest(array['workspace_owner','workspace_admin','manager','contributor']) r
on conflict do nothing;

-- O código de equipa vê o calendário (sem reagendar).
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','references.read','tasks.read','calendar.read',
                            'analytics.read','agents.read','agents.rehearse']);
$$;

-- ───────────── estados de produção ─────────────
-- Superconjunto do comportamento anterior: recorded/not_started continuam iguais para o teleprompter e a API antiga.
create or replace function public.content_production(p_id text, p_to text, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); fr text; corr uuid := gen_random_uuid(); req boolean; cap text; ev text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  fr := g.production_status;
  if p_to not in ('not_started','scheduled','recorded','editing','ready','cancelled') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  cap := case
    when p_to = 'recorded' and fr in ('not_started','scheduled','recording','recorded') then 'recording.confirm'
    when p_to = 'recorded' and fr = 'editing' then 'production.update'
    when p_to = 'not_started' and fr in ('recorded','recording','not_started') then 'recording.confirm'
    when p_to = 'not_started' and fr in ('scheduled','cancelled') then 'calendar.schedule'
    when p_to = 'scheduled' and fr in ('not_started','scheduled') then 'calendar.schedule'
    when p_to = 'editing' and fr in ('recorded','ready','editing') then 'production.update'
    when p_to = 'ready' and fr in ('editing','ready') then 'production.update'
    when p_to = 'cancelled' and fr not in ('published') then 'calendar.schedule'
  end;
  if cap is null then
    perform public._content_require('scripts.read', g.client_id, p_token, 'production.transition', g.id);
    raise exception 'transicao_invalida' using errcode = '22023';
  end if;
  perform public._content_require(cap, g.client_id, p_token, 'production.' || p_to, g.id);
  if p_to in ('scheduled','recorded') then
    if g.editorial_status in ('rejected','archived') then raise exception 'nao_elegivel' using errcode = '22023'; end if;
    select require_approval_to_record into req from clients where id = g.client_id;
    if p_to = 'recorded' and req and g.editorial_status <> 'approved' then raise exception 'aprovacao_necessaria' using errcode = '22023'; end if;
  end if;
  if fr = p_to then return g; end if;
  update guioes set production_status = p_to,
                    gravado = p_to in ('recorded','editing','ready','published'),
                    gravado_em = case when p_to in ('recorded','editing','ready','published') then coalesce(gravado_em, now()) else null end,
                    updated_at = now()
   where id = p_id returning * into g;
  ev := case when p_to = 'recorded' and fr in ('not_started','scheduled','recording') then 'recording.confirmed'
             when p_to = 'not_started' and fr in ('recorded','recording') then 'recording.undone'
             else 'production.' || p_to end;
  perform public._content_log(g, 'production', fr, p_to, g.current_version_id, null, a, ev, corr);
  return g;
end $$;

-- O teleprompter não transita o que já foi gravado, está em edição, pronto, publicado ou cancelado.
create or replace function public._tp_eligible(g guioes, p_date date, p_req boolean) returns boolean language sql immutable set search_path = public as $$
  select g.editorial_status not in ('rejected','archived') and (not p_req or g.editorial_status = 'approved')
     and g.production_status <> 'cancelled'
     and (g.date = p_date or (g.date < p_date and g.production_status in ('not_started','scheduled','recording')));
$$;

-- ───────────── reagendar ─────────────
create or replace function public.content_reschedule(p_id text, p_date date, p_lock integer default null, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); today date; fr date; nn integer;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('calendar.schedule', g.client_id, p_token, 'script.reschedule', g.id);
  if p_lock is not null and p_lock <> g.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  if p_date is null then raise exception 'data_obrigatoria' using errcode = '22023'; end if;
  select (now() at time zone coalesce(timezone, 'UTC'))::date into today from clients where id = g.client_id;
  if p_date < today then raise exception 'data_passada' using errcode = '22023'; end if;
  if p_date > today + 400 then raise exception 'data_longe' using errcode = '22023'; end if;
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  if g.production_status in ('published','cancelled') then raise exception 'nao_reagendavel' using errcode = '22023'; end if;
  fr := g.date;
  if fr = p_date then return to_jsonb(g); end if;
  select coalesce(max(n), 0) + 1 into nn from guioes where client_id = g.client_id and date = p_date;
  update guioes set date = p_date, n = nn, lock_version = lock_version + 1, updated_at = now() where id = g.id returning * into g;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'script.rescheduled', 'guiao', g.id,
          jsonb_build_object('date', fr), jsonb_build_object('date', p_date, 'n', nn));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'script.rescheduled', 'content', g.id, jsonb_build_object('from', fr, 'to', p_date, 'version_id', g.current_version_id));
  return to_jsonb(g);
end $$;

-- ───────────── leitura do calendário ─────────────
create or replace function public.calendar_range(p_ws text, p_from date, p_to date, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare today date;
begin
  perform public._content_require('calendar.read', p_ws, p_token, 'calendar.read', null);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then raise exception 'intervalo_invalido' using errcode = '22023'; end if;
  select (now() at time zone coalesce(timezone, 'UTC'))::date into today from clients where id = p_ws;
  return jsonb_build_object(
    'today', today,
    'contents', case when public.ws_can('scripts.read', p_ws, p_token) then (
       select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'formato', g.formato,
                'hook', g.hooks->0->>'text', 'editorial_status', g.editorial_status, 'production_status', g.production_status,
                'lock_version', g.lock_version,
                'late', g.date < today and g.production_status in ('not_started','scheduled','recording') and g.editorial_status not in ('rejected','archived'),
                'open_tasks', (select count(*) from tasks t where t.content_id = g.id and t.status in ('todo','doing','blocked')))
              order by g.date, g.n), '[]')
       from guioes g where g.client_id = p_ws and g.date between p_from and p_to and g.editorial_status <> 'archived') else '[]'::jsonb end,
    'tasks', case when public.ws_can('tasks.read', p_ws, p_token) then (
       select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'kind', t.kind, 'status', t.status, 'priority', t.priority,
                'due_at', t.due_at, 'assignee_email', (select email from auth.users where id = t.assignee_id), 'content_id', t.content_id,
                'lock_version', t.lock_version, 'overdue', t.due_at < now() and t.status in ('todo','doing','blocked'))
              order by t.due_at), '[]')
       from tasks t where t.workspace_id = p_ws and t.due_at is not null and t.status <> 'cancelled'
         and (t.due_at at time zone coalesce((select timezone from clients where id = p_ws), 'UTC'))::date between p_from and p_to) else '[]'::jsonb end,
    'sessions', case when public.ws_can('recording.use', p_ws, p_token) then (
       select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'date', s.date, 'closed', s.closed_at is not null,
                'takes', (select count(*) from takes k where k.session_id = s.id)) order by s.date), '[]')
       from recording_sessions s where s.workspace_id = p_ws and s.date between p_from and p_to) else '[]'::jsonb end,
    'can', jsonb_build_object('schedule', public.ws_can('calendar.schedule', p_ws, p_token), 'production', public.ws_can('production.update', p_ws, p_token),
                              'record', public.ws_can('recording.confirm', p_ws, p_token), 'tasks', public.ws_can('tasks.manage', p_ws, p_token)));
end $$;

-- ───────────── automações: "em edição" e "pronto" também disparam ─────────────
alter table public.task_rules drop constraint if exists task_rules_on_event_check;
alter table public.task_rules add constraint task_rules_on_event_check check (on_event in (
  'script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
  'recording.confirmed','production.editing','production.ready','request.created','source.approved'));

create or replace function public._handoff_events() returns text[] language sql immutable set search_path = public as $$
  select array['script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
               'recording.confirmed','production.editing','production.ready','request.created','source.approved'];
$$;

do $mig$
declare d text;
begin
  -- troca a lista fixa de eventos pela função partilhada nas duas funções do W3-01
  d := pg_get_functiondef('public.task_rule_save(text,jsonb)'::regprocedure);
  d := replace(d, $q$evs text[] := array['script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
                            'recording.confirmed','request.created','source.approved'];$q$, $q$evs text[] := public._handoff_events();$q$);
  if position('public._handoff_events()' in d) = 0 then raise exception 'task_rule_save: lista de eventos não encontrada'; end if;
  execute d;
  d := pg_get_functiondef('public.domain_events_handoff()'::regprocedure);
  d := replace(d, $q$if new.type not in ('script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
                      'recording.confirmed','request.created','source.approved') then$q$, $q$if not (new.type = any (public._handoff_events())) then$q$);
  if position('public._handoff_events()' in d) = 0 then raise exception 'domain_events_handoff: lista de eventos não encontrada'; end if;
  execute d;
end $mig$;

revoke all on function public._handoff_events() from public, anon, authenticated;
revoke all on function public.content_reschedule(text,date,integer,text), public.calendar_range(text,date,date,text) from public;
grant execute on function public.content_reschedule(text,date,integer,text), public.calendar_range(text,date,date,text) to anon, authenticated;

/* Rollback:
drop function calendar_range, content_reschedule;
-- reaplicar content_production de 20261028200818_w2_conflict_code_pt409 (só recorded/not_started), _tp_eligible de
-- 20261028213636_w2_teleprompter_search_path, task_rule_save/domain_events_handoff de 20261029071504 e legacy_can de 20261029071504.
-- (os guiões em scheduled/editing/ready voltam a not_started/recorded antes:)
-- update guioes set production_status = case when production_status in ('editing','ready') then 'recorded' else 'not_started' end
--  where production_status in ('scheduled','editing','ready','cancelled');
alter table task_rules drop constraint task_rules_on_event_check;  -- e recriar com a lista do W3-01, depois de apagar regras com os eventos novos
drop function _handoff_events;
delete from role_capabilities where capability in ('calendar.read','calendar.schedule','production.update');
delete from capabilities where key in ('calendar.read','calendar.schedule','production.update');
*/
