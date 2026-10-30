-- Parte 2 de 2 de 20261030020100_w6_ops.sql (aplicada em produção como w6_ops_p2).

-- Ver (acknowledge), adiar (snooze) ou voltar a mostrar um item. Só sobre itens que a pessoa vê agora; idempotente
-- (repetir não muda nada nem volta a auditar). Ver marca como lidas as notificações do item; nunca aprova nem fecha.
create or replace function public.inbox_item_act(p_key text, p_action text, p_until timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); item jsonb; ws text; s inbox_item_states; b jsonb; af jsonb; ack timestamptz; snz timestamptz;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_action not in ('ack','snooze','unsnooze') then raise exception 'acao_invalida' using errcode = '22023', detail = 'Ação desconhecida.'; end if;
  if p_key is null or char_length(p_key) > 200 then raise exception 'item_nao_encontrado' using errcode = 'P0002'; end if;
  select x into item from jsonb_array_elements(public._ops_queue(null)) x where x->>'key' = p_key;
  if item is null then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', 'inbox.' || p_action, 'entity_id', p_key);
    raise exception 'item_nao_encontrado' using errcode = 'P0002', detail = 'Este item já não está na tua caixa.';
  end if;
  ws := item->>'workspace_id';
  if not (item->>'enabled')::boolean then
    raise exception 'funcionalidade_desligada' using errcode = '0A000', detail = 'A área de trabalho ainda não está ligada neste cliente.';
  end if;
  if p_action = 'snooze' and (p_until is null or p_until < now() + interval '1 minute' or p_until > now() + interval '30 days') then
    raise exception 'adiamento_invalido' using errcode = '22023', detail = 'Adia para daqui a pelo menos 1 minuto e no máximo 30 dias.';
  end if;
  select * into s from inbox_item_states where user_id = uid and item_key = p_key for update;
  if s.user_id is not null and s.rev is distinct from item->>'rev' then
    s.acknowledged_at := null; s.snoozed_until := null;   -- o item mudou: o estado antigo já não se aplica
  end if;
  ack := s.acknowledged_at; snz := case when s.snoozed_until > now() then s.snoozed_until end;
  b := jsonb_build_object('acknowledged_at', ack, 'snoozed_until', snz, 'unread', (item->>'unread')::int);
  if p_action = 'ack' then
    if ack is not null and (item->>'unread')::int = 0 then return jsonb_build_object('key', p_key, 'changed', false) || b; end if;
    ack := now();
    update notifications set read_at = now() where user_id = uid and read_at is null
       and id in (select (x #>> '{}')::uuid from jsonb_array_elements(item->'notification_ids') x);
  elsif p_action = 'snooze' then
    if snz is not distinct from p_until then return jsonb_build_object('key', p_key, 'changed', false) || b; end if;
    snz := p_until;
  else
    if snz is null then return jsonb_build_object('key', p_key, 'changed', false) || b; end if;
    snz := null;
  end if;
  insert into inbox_item_states (user_id, workspace_id, item_key, rev, acknowledged_at, snoozed_until, updated_at)
  values (uid, ws, p_key, item->>'rev', ack, snz, now())
  on conflict (user_id, item_key) do update set workspace_id = excluded.workspace_id, rev = excluded.rev,
    acknowledged_at = excluded.acknowledged_at, snoozed_until = excluded.snoozed_until, updated_at = now();
  af := jsonb_build_object('acknowledged_at', ack, 'snoozed_until', snz, 'unread', case when p_action = 'ack' then 0 else (item->>'unread')::int end);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), ws, 'inbox.' || p_action, 'inbox_item', p_key, b, af);
  return jsonb_build_object('key', p_key, 'changed', true) || af;
end $$;

-- Passar uma tarefa a outra pessoa (OPS-03). Quem gere passa qualquer tarefa; quem a tem passa a sua com tasks.delegate.
-- O destino tem de poder trabalhar tarefas neste cliente. Idempotente: repetir para a mesma pessoa não muda nem notifica.
-- "Em curso" volta a "Por fazer": quem recebe ainda não começou (OPS-02, working só por início explícito).
create or replace function public.task_delegate(p_task uuid, p_to uuid, p_note text default null, p_lock integer default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a jsonb; t tasks; o tasks; note text := nullif(btrim(p_note), '');
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  a := public._content_actor(null);
  select * into t from tasks where id = p_task for update;
  if t.id is null then raise exception 'tarefa_nao_encontrada' using errcode = 'P0002'; end if;
  -- repetição (rede, duplo clique) de uma passagem que esta pessoa já fez: devolve sem mudar nem notificar
  if t.assignee_id = p_to and public._authorize('tasks.read', t.workspace_id, uid)
     and (select e.actor_id from task_events e where e.task_id = t.id and e.action = 'task.delegated' order by e.id desc limit 1) = uid
     and (select (e.after->>'assignee_id')::uuid from task_events e where e.task_id = t.id and e.action = 'task.delegated' order by e.id desc limit 1) = p_to then
    return public._task_row(t) || jsonb_build_object('changed', false);
  end if;
  if not public._authorize('tasks.manage', t.workspace_id, uid)
     and not (t.assignee_id = uid and public._authorize('tasks.delegate', t.workspace_id, uid) and public._authorize('tasks.work', t.workspace_id, uid)) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', t.workspace_id, 'action', 'task.delegate', 'entity_id', t.id);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not public._flag_on('ops.workspace', t.workspace_id, null) then
    raise exception 'funcionalidade_desligada' using errcode = '0A000', detail = 'A área de trabalho ainda não está ligada neste cliente.';
  end if;
  if t.status not in ('todo','doing','blocked') then raise exception 'tarefa_fechada' using errcode = '22023', detail = 'Esta tarefa já está fechada.'; end if;
  if p_to is null then raise exception 'responsavel_obrigatorio' using errcode = '22023', detail = 'Escolhe a pessoa.'; end if;
  if note is not null and char_length(note) > 500 then raise exception 'nota_longa' using errcode = '22023', detail = 'A nota tem de ter até 500 caracteres.'; end if;
  if t.assignee_id = p_to then return public._task_row(t) || jsonb_build_object('changed', false); end if;
  if p_lock is not null and p_lock <> t.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  if not public._authorize('tasks.work', t.workspace_id, p_to) then
    raise exception 'responsavel_sem_acesso' using errcode = '22023', detail = 'Essa pessoa não pode trabalhar tarefas neste cliente.';
  end if;
  o := t;
  update tasks set assignee_id = p_to, status = case when status = 'doing' then 'todo' else status end where id = t.id returning * into t;
  perform public._task_log(t, a, 'task.delegated', jsonb_build_object('assignee_id', o.assignee_id, 'status', o.status),
                           jsonb_build_object('assignee_id', t.assignee_id, 'status', t.status, 'note', note));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (t.workspace_id, 'task.delegated', 'task', t.id::text, jsonb_build_object('from', o.assignee_id, 'to', t.assignee_id));
  perform public._notify(t.assignee_id, t.workspace_id, 'task_delegated', 'task', t.id::text,
                         coalesce(a->>'label', 'Alguém') || ' passou-te a tarefa: ' || t.title, note, 'delegated:' || t.id || ':' || t.lock_version);
  if o.assignee_id is not null then
    perform public._notify(o.assignee_id, t.workspace_id, 'task_unassigned', 'task', t.id::text,
                           'Tarefa passou para outra pessoa: ' || t.title, a->>'label', 'unassigned:' || t.id || ':' || t.lock_version);
  end if;
  return public._task_row(t) || jsonb_build_object('changed', true);
end $$;

-- ───────────── presença e quem trabalha em quê (OPS-02, OPS-04, OPS-10) ─────────────
-- Sinal de vida enviado pela app aberta neste cliente (cada 60 s, separador visível). Só quem é membro do cliente
-- aparece; dono da agência sem atribuição não fica visível ao cliente. Escritas limitadas a uma a cada 20 s.
create or replace function public.presence_ping(p_ws text, p_active boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); prev timestamptz; share boolean;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('tasks.read', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._flag_on('ops.team_presence', p_ws, null) then return jsonb_build_object('ok', false, 'reason', 'desligada'); end if;
  if not exists (select 1 from workspace_access a where a.workspace_id = p_ws and a.user_id = uid and a.status = 'active'
                   and (a.expires_at is null or a.expires_at > now())) then
    return jsonb_build_object('ok', false, 'reason', 'sem_atribuicao');
  end if;
  select share_activity into share from member_availability where user_id = uid;
  select last_seen_at into prev from member_presence where user_id = uid and workspace_id = p_ws for update;
  if prev is not null and prev > now() - interval '20 seconds' then return jsonb_build_object('ok', true, 'share_activity', coalesce(share, false)); end if;
  insert into member_presence (user_id, workspace_id, last_seen_at, last_active_at)
  values (uid, p_ws, now(), case when p_active and coalesce(share, false) then now() end)
  on conflict (user_id, workspace_id) do update set last_seen_at = now(),
    last_active_at = case when p_active and coalesce(share, false) then now() else member_presence.last_active_at end;
  if prev is null or prev < now() - interval '2 minutes' then perform public._presence_nudge(p_ws); end if;
  return jsonb_build_object('ok', true, 'share_activity', coalesce(share, false));
end $$;

-- O meu estado manual e o consentimento para mostrar atividade. Desligar o consentimento apaga a última atividade guardada.
create or replace function public.availability_set(p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o member_availability; st text; un timestamptz; sh boolean; k text; w text;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if jsonb_typeof(p_patch) <> 'object' then raise exception 'campo_invalido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('status','until','share_activity') then raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k); end if;
  end loop;
  select * into o from member_availability where user_id = uid for update;
  st := case when p_patch ? 'status' then nullif(p_patch->>'status', '') else o.status end;
  un := case when p_patch ? 'until' then nullif(p_patch->>'until', '')::timestamptz when p_patch ? 'status' then null else o.until end;
  sh := coalesce(case when p_patch ? 'share_activity' then (p_patch->>'share_activity')::boolean end, o.share_activity, false);
  if st is not null and st not in ('available','busy','away','dnd') then raise exception 'estado_invalido' using errcode = '22023', detail = 'Estado desconhecido.'; end if;
  if un is not null and (st is null or un < now() + interval '1 minute' or un > now() + interval '30 days') then
    raise exception 'prazo_invalido' using errcode = '22023', detail = 'O fim do estado tem de ser entre daqui a 1 minuto e 30 dias.';
  end if;
  if o.user_id is not null and o.status is not distinct from st and o.until is not distinct from un and o.share_activity = sh then
    return jsonb_build_object('status', st, 'until', un, 'share_activity', sh, 'changed', false);
  end if;
  insert into member_availability (user_id, status, until, share_activity, updated_at) values (uid, st, un, sh, now())
  on conflict (user_id) do update set status = excluded.status, until = excluded.until, share_activity = excluded.share_activity, updated_at = now();
  if not sh then update member_presence set last_active_at = null where user_id = uid and last_active_at is not null; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), 'presence.availability_set', 'member_availability', uid::text,
          case when o.user_id is not null then jsonb_build_object('status', o.status, 'until', o.until, 'share_activity', o.share_activity) end,
          jsonb_build_object('status', st, 'until', un, 'share_activity', sh));
  for w in select a.workspace_id from workspace_access a where a.user_id = uid and a.status = 'active' loop
    perform public._presence_nudge(w);
  end loop;
  return jsonb_build_object('status', st, 'until', un, 'share_activity', sh, 'changed', true);
end $$;

-- Cartões por membro DESTE cliente: online, ativo (com consentimento), estado escolhido, a trabalhar (tarefa em curso
-- iniciada pela própria pessoa), bloqueios, prazos e última atualização. Tudo filtrado por p_ws: nada de outros clientes.
create or replace function public.team_presence(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  perform public._content_require('ops.presence', p_ws, null, 'presence.read', null);
  if not public._flag_on('ops.team_presence', p_ws, null) then
    raise exception 'funcionalidade_desligada' using errcode = '0A000', detail = 'Quem trabalha em quê ainda não está ligado neste cliente.';
  end if;
  with m as (
    select a.user_id, a.affiliation_type, a.workspace_role, a.job_title,
           coalesce(nullif(p.display_name, ''), u.email) as label, u.email,
           coalesce(mp.last_seen_at > now() - interval '120 seconds', false) as online,
           coalesce(mp.last_seen_at > now() - interval '120 seconds' and av.share_activity and mp.last_active_at > now() - interval '5 minutes', false) as active,
           case when av.status is not null and (av.until is null or av.until > now()) then av.status end as availability,
           case when av.status is not null and av.until > now() then av.until end as availability_until
      from workspace_access a join auth.users u on u.id = a.user_id
      left join profiles p on p.user_id = a.user_id
      left join member_presence mp on mp.user_id = a.user_id and mp.workspace_id = p_ws
      left join member_availability av on av.user_id = a.user_id
     where a.workspace_id = p_ws and a.status = 'active' and (a.expires_at is null or a.expires_at > now())
       and public._authorize('tasks.read', p_ws, a.user_id)
  ), c as (
    select m.*,
      (select jsonb_build_object('id', t.id, 'title', t.title, 'due_at', t.due_at, 'since', t.updated_at,
               'content', (select jsonb_build_object('id', g.id, 'n', g.n, 'tema', g.tema, 'date', g.date,
                                   'project', (select pr.name from projects pr where pr.id = g.project_id and pr.workspace_id = p_ws))
                            from guioes g where g.id = t.content_id and g.client_id = p_ws))
         from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status = 'doing'
        order by t.updated_at desc limit 1) as current,
      (select count(*) from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status in ('todo','doing','blocked')) as open,
      (select count(*) from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status = 'doing') as doing,
      (select count(*) from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status = 'blocked') as blocked,
      (select count(*) from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status in ('todo','doing','blocked') and t.due_at < now()) as overdue,
      (select min(t.due_at) from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status in ('todo','doing','blocked') and t.due_at >= now()) as next_due,
      (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'reason', b.blocked_reason) order by b.updated_at desc), '[]')
         from (select * from tasks t where t.workspace_id = p_ws and t.assignee_id = m.user_id and t.status = 'blocked' order by t.updated_at desc limit 3) b) as blocked_tasks,
      (select max(e.created_at) from task_events e where e.workspace_id = p_ws and e.actor_id = m.user_id) as last_update
    from m
  )
  select jsonb_build_object(
    'online_window_s', 120, 'active_window_s', 300,
    'members', coalesce((select jsonb_agg(jsonb_build_object(
        'user_id', c.user_id, 'label', c.label, 'email', c.email, 'affiliation', c.affiliation_type, 'role', c.workspace_role, 'job_title', c.job_title,
        'is_me', c.user_id = uid, 'online', c.online, 'active', c.active, 'availability', c.availability, 'availability_until', c.availability_until,
        'working', c.doing > 0, 'current', c.current, 'open', c.open, 'blocked', c.blocked, 'overdue', c.overdue, 'next_due', c.next_due,
        'blocked_tasks', c.blocked_tasks, 'last_update', c.last_update)
        order by c.online desc, (c.doing > 0) desc, c.blocked desc, lower(c.label)) from c), '[]'),
    'counts', (select jsonb_build_object('members', count(*), 'online', count(*) filter (where online), 'active', count(*) filter (where active),
                 'available', count(*) filter (where availability = 'available'), 'busy', count(*) filter (where availability in ('busy','dnd')),
                 'away', count(*) filter (where availability = 'away'), 'working', count(*) filter (where doing > 0),
                 'blocked', count(*) filter (where blocked > 0)) from c),
    'me', (select jsonb_build_object('member', exists (select 1 from m where m.user_id = uid),
                    'status', case when av.status is not null and (av.until is null or av.until > now()) then av.status end,
                    'until', case when av.until > now() then av.until end, 'share_activity', coalesce(av.share_activity, false))
             from (select 1) x left join member_availability av on av.user_id = uid))
  into res;
  return res;
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public._ops_category(text), public._presence_nudge(text), public.tasks_presence_nudge(), public._ops_queue(text)
  from public, anon, authenticated;
revoke all on function public.my_queue(text), public.inbox_item_act(text, text, timestamptz), public.task_delegate(uuid, uuid, text, integer),
  public.presence_ping(text, boolean), public.availability_set(jsonb), public.team_presence(text) from public, anon;
grant execute on function public.my_queue(text), public.inbox_item_act(text, text, timestamptz), public.task_delegate(uuid, uuid, text, integer),
  public.presence_ping(text, boolean), public.availability_set(jsonb), public.team_presence(text) to authenticated;

/* Rollback (compatível, por esta ordem):
drop trigger if exists tasks_presence_nudge on public.tasks;
drop policy if exists presence_topic_read on realtime.messages;
drop function public.team_presence(text), public.availability_set(jsonb), public.presence_ping(text, boolean),
  public.task_delegate(uuid, uuid, text, integer), public.inbox_item_act(text, text, timestamptz), public.my_queue(text),
  public._ops_queue(text), public.tasks_presence_nudge(), public._presence_nudge(text), public._ops_category(text);
delete from feature_flags where key in ('ops.workspace', 'ops.team_presence');
delete from feature_flag_defs where key in ('ops.workspace', 'ops.team_presence');
delete from role_capabilities where capability in ('tasks.delegate', 'ops.presence');
delete from permission_grants where capability in ('tasks.delegate', 'ops.presence');
delete from capabilities where key in ('tasks.delegate', 'ops.presence');
-- notificações: apagar as do tipo novo e repor notifications_kind_check de 20261029185412 (sem 'task_delegated')
delete from notifications where kind = 'task_delegated';
-- contract posterior: drop table public.inbox_item_states, public.member_presence, public.member_availability; */
