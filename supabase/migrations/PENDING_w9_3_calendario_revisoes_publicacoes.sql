-- W9-03 · Calendário com revisões de vídeo e publicações planeadas (PRD FR-11-02; ADR-0008, ADR-0036, ADR-0043, ADR-0047).
-- calendar_range passa a devolver, além de guiões, tarefas e sessões:
--   reviews      vídeos em revisão ou com alterações pedidas (versão atual, link da Drive), no dia do prazo: a tarefa aberta de
--                revisão/edição do guião com prazo mais cedo; sem tarefa, o dia do guião (due_source = 'guiao'). Só com sessão
--                individual, media.read e a flag media.library (as mesmas regras de media_review_list).
--   publications publicações planeadas e aprovadas (não canceladas) no dia local; scripts.read e a flag pub.planning (como
--                pub_calendar, que continua a ser a vista completa das publicações).
--   layers       que camadas a pessoa tem, para a UI só mostrar os filtros que existem.
-- Expand: só acrescenta chaves ao JSON (o main ignora-as). Guiões eliminados (W9-01) ficam de fora. Rollback no fim.

CREATE OR REPLACE FUNCTION public.calendar_range(p_ws text, p_from date, p_to date, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare today date; tz text; rv_on boolean; pub_on boolean;
begin
  perform public._content_require('calendar.read', p_ws, p_token, 'calendar.read', null);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then raise exception 'intervalo_invalido' using errcode = '22023'; end if;
  select (now() at time zone coalesce(timezone, 'UTC'))::date, coalesce(timezone, 'UTC') into today, tz from clients where id = p_ws;
  -- W9-03 (FR-11-02): revisões de vídeo e publicações planeadas, cada camada com a leitura e a flag de que já depende
  rv_on := auth.uid() is not null and public.ws_can('media.read', p_ws, p_token) and public._flag_on('media.library', p_ws, p_token);
  pub_on := public.ws_can('scripts.read', p_ws, p_token) and public._flag_on('pub.planning', p_ws, p_token);
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
    'reviews', case when rv_on then (
       select coalesce(jsonb_agg(r.j order by r.due_day, r.n, r.variant), '[]') from (
         select x.due_day, x.n, x.variant, jsonb_build_object('asset_id', x.asset_id, 'title', x.title, 'variant', x.variant, 'version', x.version_no,
                  'status', x.status, 'content_id', x.content_id, 'n', x.n, 'tema', x.tema, 'due_day', x.due_day, 'due_at', x.due_at,
                  'due_source', case when x.due_at is null then 'guiao' else 'tarefa' end, 'task_id', x.task_id, 'assignee_email', x.assignee_email,
                  'overdue', x.due_day < today, 'open_comments', x.open_comments) j
         from (
           select a.id asset_id, a.title, public._review_variant(a.tags) variant, v.version_no, public._review_status(v.id) status,
                  g.id content_id, g.n, g.tema, t.id task_id, t.due_at, (select email from auth.users where id = t.assignee_id) assignee_email,
                  coalesce((t.due_at at time zone tz)::date, g.date) due_day,
                  (select count(*) from media_comments c where c.version_id = v.id and c.parent_id is null and c.resolved_at is null) open_comments
             from media_assets a join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
             left join lateral (select * from tasks k where k.workspace_id = p_ws and k.content_id = g.id and k.status in ('todo','doing','blocked')
                                 and k.kind in ('review','edit') and k.due_at is not null order by k.due_at limit 1) t on true
            where a.workspace_id = p_ws and a.lifecycle = 'ativo' and v.state = 'pronta' and v.source = 'link'
              and public._drive_file_id(v.external_url) is not null and g.deleted_at is null
              and public._review_status(v.id) in ('in_review', 'changes_requested')) x
        where x.due_day between p_from and p_to) r) else '[]'::jsonb end,
    'publications', case when pub_on then (
       select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status, 'platform', p.platform, 'kind', p.kind,
                'account_handle', (select handle from accounts where id = p.account_id), 'scheduled_at', p.scheduled_at,
                'local_day', (p.scheduled_at at time zone tz)::date, 'local_time', to_char(p.scheduled_at at time zone tz, 'HH24:MI'),
                'content_id', p.content_id, 'n', g.n, 'tema', g.tema, 'overdue', p.status = 'planeada' and p.scheduled_at < now())
              order by p.scheduled_at, p.id), '[]')
       from pub_publications p join guioes g on g.id = p.content_id
      where p.workspace_id = p_ws and p.status <> 'cancelada' and g.deleted_at is null
        and (p.scheduled_at at time zone tz)::date between p_from and p_to) else '[]'::jsonb end,
    'layers', jsonb_build_object('reviews', rv_on, 'publications', pub_on),
    'can', jsonb_build_object('schedule', public.ws_can('calendar.schedule', p_ws, p_token), 'production', public.ws_can('production.update', p_ws, p_token),
                              'record', public.ws_can('recording.confirm', p_ws, p_token), 'tasks', public.ws_can('tasks.manage', p_ws, p_token)));
end $function$;


/* Rollback (compatível): repor calendar_range a partir de 20261029074048_w3_calendar_production.sql (sem reviews,
   publications nem layers). */
