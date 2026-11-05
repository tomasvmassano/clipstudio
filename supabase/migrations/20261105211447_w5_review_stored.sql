-- W5-12 · Revisão dos vídeos exportados e revisão em lote (PRD EDL-02, EDL-03, EDL-11, FR-05-03; ADR-0052). Expand (aditivo).
-- Até aqui a revisão só mostrava vídeos com link da Google Drive: o vídeo exportado pelo editor (versão nova no R2) dizia
-- "já está na revisão" e não aparecia. Agora entra qualquer versão pronta que seja um link da Drive OU um ficheiro de vídeo
-- guardado (upload/export), com o player da própria app (versão leve assinada, media.read), e as notas do QC técnico que o
-- worker grava em media_info.qc no export. edit_package_export põe na fila o export de todos os vídeos de um pacote.

create or replace function public._review_eligible(v public.media_versions) returns boolean
language sql stable security definer set search_path = public as $$
  select v.id is not null and v.state = 'pronta' and (
    (v.source = 'link' and public._drive_file_id(v.external_url) is not null)
    or (v.source = 'upload' and v.storage_path is not null and coalesce(v.mime, '') like 'video/%'))
$$;

-- resumo do QC para a lista (o relatório inteiro vai no detalhe)
create or replace function public._review_qc(p_info jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(p_info->'qc') = 'object' then jsonb_build_object(
    'passed', p_info->'qc'->'passed', 'version', p_info->'qc'->>'version', 'error', p_info->'qc'->>'error',
    'failed', (select count(*) from jsonb_array_elements(coalesce(p_info->'qc'->'checks', '[]')) c where (c->>'ok')::boolean is false)) end
$$;

create or replace function public._review_item_json(a public.media_assets) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'asset_id', a.id, 'title', a.title, 'variant', public._review_variant(a.tags), 'style', public._review_style(a.tags),
    'version_id', v.id, 'version', v.version_no, 'drive_file_id', public._drive_file_id(v.external_url), 'url', v.external_url,
    'player', case when v.source = 'link' then 'drive' else 'ficheiro' end,
    'proxy', v.proxy_state = 'pronta' and v.proxy_path is not null,
    'duration', (v.media_info->>'duration')::numeric,
    'qc', public._review_qc(v.media_info),
    'status', public._review_status(v.id),
    'decided_at', (select r.decided_at from media_reviews r where r.version_id = v.id),
    'decided_by', (select r.decided_label from media_reviews r where r.version_id = v.id),
    'open_comments', (select count(*) from media_comments c where c.version_id = v.id and c.parent_id is null and c.resolved_at is null),
    'all_comments', (select count(*) from media_comments c where c.version_id = v.id),
    'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
                'hook', case when public._review_variant(a.tags) like 'hook_%'
                             then g.hooks -> (substr(public._review_variant(a.tags), 6)::int - 1) ->> 'text' end)
              from guioes g where g.id = a.content_id))
  from media_versions v where v.id = a.current_version_id
$$;

create or replace function public.media_review_list(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text[]; q text := nullif(btrim(p_filters->>'q'), '');
begin
  perform public._review_read(p_ws, p_token);
  st := coalesce((select array_agg(x) from jsonb_array_elements_text(p_filters->'status') x), array['in_review', 'changes_requested', 'approved', 'rejected']);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._review_item_json(a) order by g.date, g.n, public._review_variant(a.tags), a.title), '[]')
              from media_assets a join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
              where a.workspace_id = p_ws and a.lifecycle = 'ativo' and public._review_eligible(v) and g.deleted_at is null
                and public._review_status(v.id) = any (st)
                and (q is null or g.tema ilike '%' || q || '%' or a.title ilike '%' || q || '%')),
    'counts', (select coalesce(jsonb_object_agg(s, c), '{}') from (
                 select public._review_status(v.id) s, count(*) c
                   from media_assets a join guioes g on g.id = a.content_id join media_versions v on v.id = a.current_version_id
                  where a.workspace_id = p_ws and a.lifecycle = 'ativo' and public._review_eligible(v) and g.deleted_at is null
                  group by 1) z),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', p_ws, p_token), 'decide', public.ws_can('review.approve', p_ws, p_token),
                              'link', public.ws_can('media.upload', p_ws, p_token)));
end $$;

create or replace function public.media_review_detail(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a media_assets; v media_versions; uid uuid;
begin
  uid := public._review_read(p_ws, p_token);
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo';
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from media_versions where id = coalesce(p_version, a.current_version_id) and asset_id = a.id and state = 'pronta';
  if v.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'item', public._review_item_json(a),
    'version', jsonb_build_object('id', v.id, 'version', v.version_no, 'drive_file_id', public._drive_file_id(v.external_url),
                                  'url', v.external_url, 'status', public._review_status(v.id), 'current', v.id = a.current_version_id,
                                  'player', case when v.source = 'link' then 'drive' else 'ficheiro' end,
                                  'proxy', v.proxy_state = 'pronta' and v.proxy_path is not null,
                                  'duration', (v.media_info->>'duration')::numeric,
                                  'qc', case when jsonb_typeof(v.media_info->'qc') = 'object' then v.media_info->'qc' end,
                                  'decided_by', (select r.decided_label from media_reviews r where r.version_id = v.id),
                                  'decided_at', (select r.decided_at from media_reviews r where r.version_id = v.id)),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version_no, 'status', public._review_status(x.id))
                   order by x.version_no desc), '[]') from media_versions x where x.asset_id = a.id and x.state = 'pronta'),
    'comments', (select coalesce(jsonb_agg(public._review_comment_json(c) order by c.t_ms nulls first, c.created_at), '[]')
                 from media_comments c where c.version_id = v.id),
    'decisions', (select coalesce(jsonb_agg(jsonb_build_object('from', d.from_status, 'to', d.to_status, 'reason', d.reason,
                   'by', coalesce(d.actor_label, 'alguém'), 'at', d.created_at) order by d.created_at), '[]')
                  from media_decisions d where d.version_id = v.id),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', p_ws, p_token), 'decide', public.ws_can('review.approve', p_ws, p_token)),
    'me', uid);
end $$;

-- Exportar o pacote inteiro (EDL-02): um export por vídeo do pacote, pelas mesmas regras de edit_export_request
-- (edit.export, R2 ligado, câmaras na biblioteca; idempotente pela versão do documento). Um vídeo que falhe não trava os outros.
create or replace function public.edit_package_export(p_ws text, p_job uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; o record; r jsonb; queued int := 0; fails jsonb := '[]'; jobs jsonb := '[]';
begin
  perform public._edit_require(p_ws, p_token, 'edit.export', p_job::text, true);
  if not public.ws_can('edit.export', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package_export');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into j from media_jobs where id = p_job and workspace_id = p_ws and kind = 'package';
  if j.id is null then raise exception 'pacote_nao_encontrado' using errcode = 'P0002'; end if;
  if j.status <> 'done' then raise exception 'pacote_por_acabar' using errcode = '22023', detail = 'O pacote ainda não acabou.'; end if;
  for o in select x.asset_id, a.title from media_job_outputs x join media_assets a on a.id = x.asset_id
            where x.job_id = j.id and a.lifecycle = 'ativo' order by x.guiao_id, x.hook loop
    begin
      r := public.edit_export_request(p_ws, o.asset_id, null, p_token);
      queued := queued + 1;
      jobs := jobs || jsonb_build_array(jsonb_build_object('asset_id', o.asset_id, 'job_id', r->>'id', 'status', r->>'status'));
    exception when others then
      fails := fails || jsonb_build_array(jsonb_build_object('asset_id', o.asset_id, 'title', o.title,
                 'error', coalesce(nullif(sqlerrm, ''), 'erro')));
    end;
  end loop;
  perform public._media_audit(p_ws, 'edit.package_export', 'media_job', p_job::text, null,
    jsonb_build_object('queued', queued, 'failed', jsonb_array_length(fails)));
  return jsonb_build_object('queued', queued, 'jobs', jobs, 'failed', fails);
end $$;

revoke all on function public._review_eligible(public.media_versions), public._review_qc(jsonb) from public, anon, authenticated;
revoke all on function public.edit_package_export(text, uuid, text) from public;
revoke all on function public.edit_package_export(text, uuid, text) from anon;
grant execute on function public.edit_package_export(text, uuid, text) to authenticated;

-- calendário: a mesma regra de elegibilidade nas revisões
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
            where a.workspace_id = p_ws and a.lifecycle = 'ativo' and public._review_eligible(v) and g.deleted_at is null
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

/* Rollback (compatível): repor _review_item_json, media_review_list e media_review_detail de 20261103153227_w5_media_review.sql e
   calendar_range de 20261105202133_w9_calendario.sql; drop function public.edit_package_export(text, uuid, text),
   public._review_qc(jsonb), public._review_eligible(public.media_versions). */
