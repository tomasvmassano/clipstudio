-- W6 · Minha área de trabalho e quem trabalha em quê (PRD FR-01-03, FR-17-01, OPS-02, OPS-03, OPS-04, OPS-10; ADR-0034).
-- Expand (só aditivo): 2 capacidades, 2 flags, 3 tabelas fechadas à API, funções novas, 1 tipo de notificação novo,
-- 1 gatilho que só avisa o canal privado de presença, 1 política de leitura em realtime.messages.
-- Não muda inbox(), notifications_read(), task_update() nem _notify(): as páginas atuais continuam iguais com as flags
-- desligadas. Rollback no fim.

-- ───────────── capacidades e flags ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('tasks.delegate', 'Tarefas', 'B', array['ws'], 'ativo', 'Passar as minhas tarefas a outra pessoa'),
  ('ops.presence', 'Operações', 'B', array['ws'], 'ativo', 'Ver quem trabalha em quê')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
insert into role_capabilities (scope, role, capability)
select 'ws', r, c from unnest(array['workspace_owner','workspace_admin','manager','contributor','reviewer']) r,
                       unnest(array['tasks.delegate','ops.presence']) c
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('ops.workspace', 'Minha área de trabalho', 'Operações', 'ws', 'owner',
   'A minha fila no Início e caixa de entrada única com ver, adiar, passar a outra pessoa e concluir.'),
  ('ops.team_presence', 'Quem trabalha em quê', 'Operações', 'ws', 'owner',
   'Cartões por pessoa deste cliente com estado, tarefa em curso, bloqueios e prazos. Presença só deste cliente.')
on conflict do nothing;

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done','automation_error','script_mention','script_comment',
   'script_assigned','task_delegated'));

-- ───────────── tabelas ─────────────
-- Estado pessoal de cada item da caixa (visto, adiado). `rev` prende o estado à versão do item: um guião com versão nova
-- ou uma tarefa que volta para mim aparece outra vez como novo.
create table if not exists public.inbox_item_states (
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  item_key text not null check (char_length(item_key) between 3 and 200 and item_key ~ '^[a-z_]+:[A-Za-z0-9:_.-]+$'),
  rev text not null default '-',
  acknowledged_at timestamptz,
  snoozed_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_key)
);

-- Presença por cliente (OPS-02, OPS-10): só a última ligação e, com consentimento, a última atividade. Sem histórico,
-- sem horas: não serve de controlo de horário. Uma linha por pessoa e cliente, por isso dois separadores contam uma vez.
create table if not exists public.member_presence (
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  last_seen_at timestamptz not null default now(),
  last_active_at timestamptz,
  primary key (user_id, workspace_id)
);

-- Estado escolhido pela pessoa (disponível, ocupado, ausente, não incomodar) e consentimento para mostrar atividade.
create table if not exists public.member_availability (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text check (status is null or status in ('available','busy','away','dnd')),
  until timestamptz,
  share_activity boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.inbox_item_states enable row level security;
alter table public.member_presence enable row level security;
alter table public.member_availability enable row level security;
revoke all on public.inbox_item_states, public.member_presence, public.member_availability from anon, authenticated;   -- só pelas RPCs

-- ───────────── auxiliares ─────────────
create or replace function public._ops_category(p_reason text) returns text language sql immutable set search_path = public as $$
  select case
    when p_reason in ('assigned','blocked','changes_requested') then 'task'
    when p_reason = 'approval' then 'approval'
    when p_reason = 'recording' then 'recording'
    when p_reason in ('unassigned','blocked_other','talent_request') then 'decision'
    when p_reason in ('task_mention','script_mention','script_comment') then 'mention'
    when p_reason in ('automation_error','task_blocked','overdue') then 'alert'
    else 'info' end
$$;

-- Avisa quem está a ver a equipa deste cliente que algo mudou. Sem dados pessoais no aviso: a página volta a pedir
-- team_presence(), que verifica o acesso. Falhar o aviso nunca falha a operação.
create or replace function public._presence_nudge(p_ws text) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_ws is null or public._flag_stage('ops.team_presence', (select organization_id from clients where id = p_ws), p_ws) = 'off' then return; end if;
  begin
    perform realtime.send(jsonb_build_object('at', now()), 'presence_changed', 'presence:' || p_ws, true);
  exception when others then null;
  end;
end $$;

create or replace function public.tasks_presence_nudge() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status or new.assignee_id is distinct from old.assignee_id then
    perform public._presence_nudge(new.workspace_id);
  end if;
  return null;
end $$;
drop trigger if exists tasks_presence_nudge on public.tasks;
create trigger tasks_presence_nudge after insert or update on public.tasks for each row execute function public.tasks_presence_nudge();

-- Canal privado presence:<cliente>: só lê quem pode ver a equipa desse cliente. Não há política de escrita: ninguém
-- publica nem faz "track" neste tópico a partir do browser (o estado vem só do servidor).
drop policy if exists presence_topic_read on realtime.messages;
create policy presence_topic_read on realtime.messages for select to authenticated
  using (realtime.topic() like 'presence:%' and public.authorize('ops.presence', split_part(realtime.topic(), ':', 2)));

-- ───────────── a minha fila (FR-17-01, FR-01-03, OPS-03) ─────────────
-- Todos os itens que precisam de mim, de todos os clientes a que tenho acesso agora (ou só de p_ws), um por objeto:
-- tarefa, guião, pedido ou execução. Notificações sobre o mesmo objeto juntam-se ao item (deduplicação por evento).
create or replace function public._ops_queue(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
  w_read text[]; w_work text[]; w_manage text[]; w_appr text[]; w_rec text[]; w_edit text[]; w_triage text[]; w_deleg text[]; w_ops text[];
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select coalesce(array_agg(c.id) filter (where public._authorize('tasks.read', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('tasks.work', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('tasks.manage', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('scripts.approve', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('recording.use', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('scripts.edit', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('sources.triage', c.id, uid)), '{}'),
         coalesce(array_agg(c.id) filter (where public._authorize('tasks.delegate', c.id, uid)), '{}')
    into w_read, w_work, w_manage, w_appr, w_rec, w_edit, w_triage, w_deleg
    from clients c where c.status = 'active' and (p_ws is null or c.id = p_ws);
  select coalesce(array_agg(x), '{}') into w_ops from unnest(w_read) x where public._flag_on('ops.workspace', x, null);

  return (
    with mine as (
      select t.* from tasks t where t.assignee_id = uid and t.status in ('todo','doing','blocked') and t.workspace_id = any (w_work)
    ), r as (
      -- 1 · as minhas tarefas (uma tarefa de revisão ou de gravação absorve a aprovação/gravação do mesmo guião)
      select 'task:' || t.id as ekey, t.workspace_id as ws, 1 as src, t.title,
             coalesce(case when t.status = 'blocked' then 'Bloqueada: ' || t.blocked_reason end,
                      (select 'Guião ' || g.n || coalesce(' · ' || g.tema, '') from guioes g where g.id = t.content_id),
                      (select s.titulo from ideas s where s.id = t.source_id)) as detail,
             '/tarefas?task=' || t.id as href, t.due_at, null::date as day, t.priority, t.created_at,
             array_remove(array[case when t.status = 'blocked' then 'blocked' else 'assigned' end,
                   case when t.kind = 'review' and t.workspace_id = any (w_appr)
                         and exists (select 1 from guioes g where g.id = t.content_id and g.editorial_status = 'in_review') then 'approval' end,
                   case when t.kind = 'recording' then 'recording' end], null) as reasons,
             t.id as task_id, t.status as task_status, t.lock_version as task_lock, t.assignee_id as task_assignee,
             (select count(*) from task_dependencies d join tasks x on x.id = d.depends_on
               where d.task_id = t.id and x.status not in ('done','cancelled'))::int as open_deps,
             coalesce(t.assignee_id::text, '-') as rev, null::uuid as notif_id
        from mine t
      union all
      -- 5 · decisões de quem gere: tarefas sem responsável válido ou bloqueadas de outra pessoa
      select 'task:' || t.id, t.workspace_id, 5, t.title,
             case when t.status = 'blocked' then 'Bloqueada: ' || t.blocked_reason else 'Sem responsável' end,
             '/tarefas?task=' || t.id, t.due_at, null, t.priority, t.created_at,
             array_remove(array[
               case when t.assignee_id is null or not public._authorize('tasks.work', t.workspace_id, t.assignee_id) then 'unassigned' end,
               case when t.status = 'blocked' then 'blocked_other' end], null),
             t.id, t.status, t.lock_version, t.assignee_id, 0, coalesce(t.assignee_id::text, '-'), null
        from tasks t
       where t.status in ('todo','doing','blocked') and t.workspace_id = any (w_manage) and t.assignee_id is distinct from uid
         and (t.status = 'blocked' or t.assignee_id is null or not public._authorize('tasks.work', t.workspace_id, t.assignee_id))
      union all
      -- 2 · guiões à espera da minha aprovação
      select 'content:' || g.id, g.client_id, 2, 'Guião ' || g.n || ' à espera de aprovação', coalesce(g.tema, g.hooks->0->>'text'),
             '/guioes?date=' || g.date || '&open=' || g.id,
             (select min(t.due_at) from tasks t where t.content_id = g.id and t.kind = 'review' and t.status in ('todo','doing','blocked')),
             g.date,
             coalesce((select t.priority from tasks t where t.content_id = g.id and t.kind = 'review' and t.status in ('todo','doing','blocked')
                        order by t.created_at desc limit 1), 'normal'),
             g.updated_at, array['approval'], null, null, null, null, 0,
             coalesce(g.current_version_id::text, '-') || ':' || g.editorial_status, null
        from guioes g
       where g.editorial_status = 'in_review' and g.client_id = any (w_appr)
         and not exists (select 1 from mine t where t.content_id = g.id and t.kind = 'review')
      union all
      -- 3 · alterações pedidas nos guiões de que sou responsável
      select 'content:' || g.id, g.client_id, 3, 'Alterações pedidas no guião ' || g.n, g.tema,
             '/guioes?date=' || g.date || '&open=' || g.id, null, g.date, 'normal', g.updated_at, array['changes_requested'],
             null, null, null, null, 0, coalesce(g.current_version_id::text, '-') || ':' || g.editorial_status, null
        from guioes g
       where g.owner_id = uid and g.editorial_status = 'changes_requested' and g.client_id = any (w_edit)
      union all
      -- 4 · as minhas gravações de hoje (sou responsável pelo guião; com tarefa de gravação fica na tarefa)
      select 'content:' || g.id, g.client_id, 4, 'Gravar guião ' || g.n || ' hoje', g.tema, '/teleprompter?date=' || g.date,
             null, g.date, 'normal', g.updated_at, array['recording'], null, null, null, null, 0,
             coalesce(g.current_version_id::text, '-') || ':' || g.editorial_status, null
        from guioes g join clients c on c.id = g.client_id
       where g.client_id = any (w_rec) and g.owner_id = uid and g.date = (now() at time zone coalesce(c.timezone, 'UTC'))::date
         and g.production_status in ('not_started','scheduled','recording') and g.editorial_status not in ('rejected','archived')
         and (not c.require_approval_to_record or g.editorial_status = 'approved')
         and not exists (select 1 from mine t where t.content_id = g.id and t.kind = 'recording')
      union all
      -- 6 · pedidos do talento por decidir
      select 'request:' || i.id, i.client_id, 6, 'Pedido do talento: ' || coalesce(nullif(btrim(i.titulo), ''), 'sem título'), null, '/fontes',
             null, null, 'normal', i.created_at, array['talent_request'], null, null, null, null, 0, '-', null
        from ideas i
       where i.kind = 'talent_request' and i.status in ('nova','triagem') and i.client_id = any (w_triage)
      union all
      -- 9 · notificações por ler (juntam-se ao objeto a que se referem)
      select case when n.entity_type = 'task' then 'task:' when n.entity_type = 'content' then 'content:' else n.entity_type || ':' end || n.entity_id,
             n.workspace_id, 9, n.title, n.body,
             case n.entity_type
               when 'task' then '/tarefas?task=' || n.entity_id
               when 'content' then coalesce((select '/guioes?date=' || g.date || '&open=' || g.id from guioes g where g.id = n.entity_id), '/guioes')
               when 'agent_job' then '/agentes/configuracao'
               else '/' end,
             null, null, 'normal', n.created_at, array[n.kind], null, null, null, null, 0, '-', n.id
        from (select * from notifications x where x.user_id = uid and x.read_at is null and x.workspace_id = any (w_read)
               order by x.created_at desc limit 200) n
    ), agg as (
      select r.ekey,
             (array_agg(r.ws order by r.src, r.created_at desc))[1] as ws,
             min(r.src) as src,
             (array_agg(r.title order by r.src, r.created_at desc))[1] as title,
             (array_agg(r.detail order by r.src, r.created_at desc))[1] as detail,
             (array_agg(r.href order by r.src, r.created_at desc))[1] as href,
             min(r.due_at) as due_at, min(r.day) as day,
             (array_agg(r.priority order by case r.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end))[1] as priority,
             max(r.created_at) as last_at,
             (array_agg(r.task_id order by r.src) filter (where r.task_id is not null))[1] as task_id,
             (array_agg(r.task_status order by r.src) filter (where r.task_id is not null))[1] as task_status,
             (array_agg(r.task_lock order by r.src) filter (where r.task_id is not null))[1] as task_lock,
             (array_agg(r.task_assignee order by r.src) filter (where r.task_id is not null))[1] as task_assignee,
             max(r.open_deps) as open_deps,
             (array_agg(r.rev order by r.src))[1] as rev,
             coalesce(array_agg(r.notif_id order by r.created_at desc) filter (where r.notif_id is not null), '{}') as notif_ids,
             max(r.created_at) filter (where r.notif_id is not null) as last_notif,
             count(*) filter (where r.notif_id is null) as live
        from r group by r.ekey
    ), rs as (
      select r.ekey, array_agg(distinct x order by x) as reasons from r, unnest(r.reasons) x group by r.ekey
    ), items as (
      select a.*, c.name as ws_name, s.acknowledged_at, s.updated_at as state_at,
             case when s.snoozed_until > now() and not coalesce(a.last_notif > s.updated_at, false) then s.snoozed_until end as snoozed_until,
             a.due_at is not null and a.due_at < now() as overdue,
             rs.reasons || case when a.due_at is not null and a.due_at < now() then array['overdue'] else '{}'::text[] end as reasons_all,
             a.ws = any (w_ops) as en
        from agg a join rs on rs.ekey = a.ekey join clients c on c.id = a.ws
        left join inbox_item_states s on s.user_id = uid and s.item_key = a.ekey and s.rev = a.rev
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'key', i.ekey, 'workspace_id', i.ws, 'workspace', i.ws_name,
             'kind', (select k from unnest(array['task','approval','recording','decision','mention','alert','info']) with ordinality o(k, n)
                       where k = any (array(select public._ops_category(x) from unnest(i.reasons_all) x)) order by n limit 1),
             'categories', to_jsonb(array(select distinct public._ops_category(x) from unnest(i.reasons_all) x order by 1)),
             'reasons', to_jsonb(i.reasons_all), 'title', i.title, 'detail', i.detail, 'href', i.href,
             'due_at', i.due_at, 'day', i.day, 'priority', i.priority, 'overdue', i.overdue, 'last_at', i.last_at,
             'unread', cardinality(i.notif_ids), 'notification_ids', to_jsonb(i.notif_ids), 'only_notifications', i.live = 0,
             'seen', i.acknowledged_at is not null and cardinality(i.notif_ids) = 0,
             'acknowledged_at', i.acknowledged_at, 'snoozed_until', i.snoozed_until, 'rev', i.rev,
             'task', case when i.task_id is not null then jsonb_build_object('id', i.task_id, 'status', i.task_status,
                         'lock_version', i.task_lock, 'open_deps', i.open_deps, 'mine', i.task_assignee is not distinct from uid) end,
             'enabled', i.en,
             'can', jsonb_build_object(
               'ack', i.en, 'snooze', i.en,
               'delegate', i.en and i.task_id is not null
                           and (i.ws = any (w_manage) or (i.task_assignee is not distinct from uid and i.ws = any (w_deleg))),
               'complete', i.en and i.task_assignee is not distinct from uid and i.task_status in ('todo','doing') and coalesce(i.open_deps, 0) = 0,
               'start', i.en and i.task_assignee is not distinct from uid and i.task_status = 'todo'))
           order by i.overdue desc, case i.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
                    coalesce(i.due_at, i.day::timestamptz) nulls last, i.last_at desc), '[]'::jsonb)
      from items i);
end $$;

create or replace function public.my_queue(p_ws text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q jsonb; vis jsonb; sn jsonb;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  -- cliente sem acesso e cliente inexistente dão a mesma resposta
  if p_ws is not null and not (public._authorize('tasks.read', p_ws, uid) or public._authorize('scripts.read', p_ws, uid)) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'inbox.queue');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  q := public._ops_queue(p_ws);
  select coalesce(jsonb_agg(x), '[]') into vis from jsonb_array_elements(q) x where x->>'snoozed_until' is null;
  select coalesce(jsonb_agg(x), '[]') into sn from jsonb_array_elements(q) x where x->>'snoozed_until' is not null;
  return jsonb_build_object(
    'items', vis, 'snoozed', sn,
    'counts', jsonb_build_object(
      'all', jsonb_array_length(vis),
      'new', (select count(*) from jsonb_array_elements(vis) x where not (x->>'seen')::boolean),
      'task', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'task'),
      'approval', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'approval'),
      'recording', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'recording'),
      'decision', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'decision'),
      'mention', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'mention'),
      'alert', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'alert'),
      'info', (select count(*) from jsonb_array_elements(vis) x where x->'categories' ? 'info'),
      'snoozed', jsonb_array_length(sn)),
    'enabled', coalesce((select jsonb_agg(c.id order by c.id) from clients c
                          where c.status = 'active' and (p_ws is null or c.id = p_ws)
                            and public._authorize('tasks.read', c.id, uid) and public._flag_on('ops.workspace', c.id, null)), '[]'));
end $$;

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
