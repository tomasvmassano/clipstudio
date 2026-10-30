-- Parte 1 de 2 de 20261030020100_w6_ops.sql (aplicada em produção como w6_ops_p1).
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
