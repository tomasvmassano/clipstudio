-- W3-01 Tarefas, handoffs e caixa de entrada (PRD TEAM-06, TEAM-12, TEAM-15 parcial, FR-11-02 parcial, FR-17-01, FR-17-05; AGENTS §6).
-- Tarefas por workspace com responsável, prioridade, estado, prazo, dependências, comentários e histórico append-only.
-- Regras de handoff por workspace: um evento de domínio (ex.: guião submetido) cria uma tarefa idempotente e outro evento a fecha.
-- Notificações pessoais (atribuição, reatribuição, menção, tarefa automática), filtradas pelo acesso atual na leitura.
-- Só aditivo. Rollback: bloco no fim.

insert into public.capabilities (key, module, risk, scopes, status)
values ('tasks.work', 'Tarefas', 'B', '{ws,own}', 'ativo') on conflict (key) do nothing;
insert into public.role_capabilities (scope, role, capability)
select 'ws', r, 'tasks.work' from unnest(array['workspace_owner','workspace_admin','manager','contributor','reviewer']) r
on conflict do nothing;
update public.capabilities set status = 'ativo', module = 'Tarefas' where key in ('tasks.read','tasks.manage');

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  title text not null check (length(btrim(title)) between 2 and 200),
  description text check (description is null or length(description) <= 5000),
  kind text not null default 'task' check (kind in ('task','review','recording','edit','publish','request')),
  status text not null default 'todo' check (status in ('todo','doing','blocked','done','cancelled')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  assignee_id uuid references auth.users(id) on delete set null,
  due_at timestamptz,
  blocked_reason text check (blocked_reason is null or length(blocked_reason) <= 500),
  content_id text references public.guioes(id) on delete restrict,
  source_id bigint references public.ideas(id) on delete restrict,
  rule_id uuid,
  dedup_key text,
  client_ref uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user','legacy_code','system')),
  created_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  lock_version integer not null default 1,
  check (status <> 'blocked' or blocked_reason is not null)
);
create unique index tasks_dedup on public.tasks (workspace_id, dedup_key) where dedup_key is not null;
create unique index tasks_client_ref on public.tasks (workspace_id, client_ref) where client_ref is not null;
create index tasks_ws_status on public.tasks (workspace_id, status, due_at);
create index tasks_assignee on public.tasks (assignee_id, status) where status in ('todo','doing','blocked');
create index tasks_content on public.tasks (content_id) where content_id is not null;

create table public.task_dependencies (
  task_id uuid not null references public.tasks(id) on delete restrict,
  depends_on uuid not null references public.tasks(id) on delete restrict,
  workspace_id text not null references public.clients(id),
  created_at timestamptz not null default now(),
  primary key (task_id, depends_on),
  check (task_id <> depends_on)
);

create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete restrict,
  workspace_id text not null references public.clients(id),
  author_id uuid references auth.users(id) on delete set null,
  author_label text,
  body text not null check (length(btrim(body)) between 1 and 4000),
  mentions uuid[] not null default '{}',
  created_at timestamptz not null default now()
);
create index task_comments_task on public.task_comments (task_id, created_at);

-- Histórico de cada tarefa (append-only): criação, mudanças de campo, dependências, fecho automático.
create table public.task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.tasks(id) on delete restrict,
  workspace_id text not null references public.clients(id),
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('user','legacy_code','system')),
  actor_label text,
  action text not null,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index task_events_task on public.task_events (task_id, created_at);

-- Regras de handoff por workspace (FR-17-05). Nunca globais: o preset de um cliente não muda outro.
create table public.task_rules (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  on_event text not null check (on_event in ('script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
                                             'recording.confirmed','request.created','source.approved')),
  complete_on text[] not null default '{}',
  kind text not null default 'task' check (kind in ('task','review','recording','edit','publish','request')),
  title text not null check (length(btrim(title)) between 2 and 200),
  assignee_id uuid references auth.users(id) on delete set null,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  due_hours integer check (due_hours is null or due_hours between 1 and 2160),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index task_rules_ws_event on public.task_rules (workspace_id, on_event) where active;
alter table public.tasks add constraint tasks_rule_fk foreign key (rule_id) references public.task_rules(id) on delete set null;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  kind text not null check (kind in ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done')),
  entity_type text not null,
  entity_id text not null,
  title text not null,
  body text,
  dedup_key text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index notifications_dedup on public.notifications (user_id, dedup_key);
create index notifications_user on public.notifications (user_id, created_at desc);

-- ───────────── integridade ─────────────
create or replace function public.tasks_before_write() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.workspace_id is distinct from old.workspace_id or new.created_at is distinct from old.created_at
       or new.dedup_key is distinct from old.dedup_key or new.client_ref is distinct from old.client_ref then
      raise exception 'imutavel' using errcode = '42501';
    end if;
    new.updated_at := now();
    new.lock_version := old.lock_version + 1;
    new.completed_at := case when new.status in ('done','cancelled') then coalesce(old.completed_at, now()) else null end;
  else
    new.completed_at := case when new.status in ('done','cancelled') then now() end;
  end if;
  if new.content_id is not null and new.workspace_id is distinct from (select client_id from guioes where id = new.content_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  if new.source_id is not null and new.workspace_id is distinct from (select client_id from ideas where id = new.source_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  if new.rule_id is not null and new.workspace_id is distinct from (select workspace_id from task_rules where id = new.rule_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger tasks_before_write before insert or update on public.tasks for each row execute function public.tasks_before_write();
create trigger tasks_no_delete before delete on public.tasks for each row execute function public.content_append_only();

create or replace function public.task_children_same_ws() returns trigger language plpgsql set search_path = public as $$
declare dep uuid := (to_jsonb(new)->>'depends_on')::uuid;
begin
  if new.workspace_id is distinct from (select workspace_id from tasks where id = new.task_id)
     or (dep is not null and new.workspace_id is distinct from (select workspace_id from tasks where id = dep)) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger task_deps_ws before insert on public.task_dependencies for each row execute function public.task_children_same_ws();
create trigger task_comments_ws before insert on public.task_comments for each row execute function public.task_children_same_ws();
create trigger task_events_ws before insert on public.task_events for each row execute function public.task_children_same_ws();
create trigger task_comments_append_only before update or delete on public.task_comments for each row execute function public.content_append_only();
create trigger task_events_append_only before update or delete on public.task_events for each row execute function public.content_append_only();

create or replace function public.task_rules_before_write() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'imutavel' using errcode = '42501'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger task_rules_before_write before insert or update on public.task_rules for each row execute function public.task_rules_before_write();

alter table public.tasks enable row level security;
alter table public.task_dependencies enable row level security;
alter table public.task_comments enable row level security;
alter table public.task_events enable row level security;
alter table public.task_rules enable row level security;
alter table public.notifications enable row level security;
revoke all on public.tasks, public.task_dependencies, public.task_comments, public.task_events, public.task_rules, public.notifications from anon, authenticated;
grant select on public.tasks, public.task_dependencies, public.task_comments, public.task_events, public.task_rules, public.notifications to authenticated;
create policy tasks_select on public.tasks for select to authenticated using (public.authorize('tasks.read', workspace_id));
create policy task_deps_select on public.task_dependencies for select to authenticated using (public.authorize('tasks.read', workspace_id));
create policy task_comments_select on public.task_comments for select to authenticated using (public.authorize('tasks.read', workspace_id));
create policy task_events_select on public.task_events for select to authenticated using (public.authorize('tasks.read', workspace_id));
create policy task_rules_select on public.task_rules for select to authenticated using (public.authorize('tasks.manage', workspace_id));
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid() and public.authorize('tasks.read', workspace_id));

-- O código de equipa do Numeiro passa a ler tarefas (sem as gerir: não tem identidade para ser responsável).
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','references.read','tasks.read',
                            'analytics.read','agents.read','agents.rehearse']);
$$;

-- ───────────── auxiliares ─────────────
create or replace function public._notify(p_user uuid, p_ws text, p_kind text, p_entity_type text, p_entity_id text,
                                          p_title text, p_body text, p_dedup text) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- só quem tem acesso atual recebe (TEAM-12); quem age não se notifica a si próprio
  if p_user is null or p_user is not distinct from auth.uid() or not public._authorize('tasks.read', p_ws, p_user) then return; end if;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key)
  values (p_user, p_ws, p_kind, p_entity_type, p_entity_id, left(p_title, 200), left(p_body, 500), p_dedup)
  on conflict (user_id, dedup_key) do nothing;
end $$;

create or replace function public._task_log(p_t tasks, p_actor jsonb, p_action text, p_before jsonb, p_after jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into task_events (task_id, workspace_id, actor_id, actor_kind, actor_label, action, before, after)
  values (p_t.id, p_t.workspace_id, (p_actor->>'uid')::uuid, p_actor->>'kind', p_actor->>'label', p_action, p_before, p_after);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((p_actor->>'uid')::uuid, case when p_actor->>'kind' = 'system' then 'system' else p_actor->>'kind' end, p_actor->>'label',
          p_t.workspace_id, p_action, 'task', p_t.id::text, p_before, p_after);
end $$;

create or replace function public._task_row(t tasks) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(t) || jsonb_build_object(
    'assignee_email', (select email from auth.users where id = t.assignee_id),
    'assignee_has_access', case when t.assignee_id is null then null else public._authorize('tasks.work', t.workspace_id, t.assignee_id) end,
    'content', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'editorial_status', g.editorial_status)
                from guioes g where g.id = t.content_id),
    'source', (select jsonb_build_object('id', s.id, 'titulo', s.titulo, 'kind', s.kind) from ideas s where s.id = t.source_id),
    'deps', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'status', x.status) order by x.created_at), '[]')
             from task_dependencies d join tasks x on x.id = d.depends_on where d.task_id = t.id),
    'open_deps', (select count(*) from task_dependencies d join tasks x on x.id = d.depends_on
                  where d.task_id = t.id and x.status not in ('done','cancelled')),
    'comments', (select count(*) from task_comments c where c.task_id = t.id),
    'overdue', t.due_at is not null and t.due_at < now() and t.status in ('todo','doing','blocked'));
$$;

create or replace function public._task_valid_assignee(p_ws text, p_user uuid) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_user is not null and not public._authorize('tasks.work', p_ws, p_user) then
    raise exception 'responsavel_sem_acesso' using errcode = '22023';
  end if;
end $$;

-- ───────────── leitura ─────────────
create or replace function public.tasks_list(p_ws text, p_scope text default 'open', p_content text default null, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('tasks.read', p_ws, p_token, 'task.list', null);
  if p_scope not in ('open','mine','unassigned','done','all') then raise exception 'filtro_invalido' using errcode = '22023'; end if;
  return (select coalesce(jsonb_agg(public._task_row(t) order by
            case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.due_at nulls last, t.created_at), '[]')
          from tasks t
          where t.workspace_id = p_ws
            and (p_content is null or t.content_id = p_content)
            and case p_scope
                  when 'open' then t.status in ('todo','doing','blocked')
                  when 'mine' then t.status in ('todo','doing','blocked') and t.assignee_id = auth.uid() and auth.uid() is not null
                  when 'unassigned' then t.status in ('todo','doing','blocked')
                       and (t.assignee_id is null or not public._authorize('tasks.work', t.workspace_id, t.assignee_id))
                  when 'done' then t.status in ('done','cancelled') and t.completed_at > now() - interval '60 days'
                  else true end
          limit 500);
end $$;

create or replace function public.task_get(p_id uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t tasks;
begin
  select * into t from tasks where id = p_id;
  if t.id is null then raise exception 'tarefa_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('tasks.read', t.workspace_id, p_token, 'task.get', t.id::text);
  return public._task_row(t) || jsonb_build_object(
    'comments_list', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'author_label', c.author_label, 'body', c.body,
                         'created_at', c.created_at, 'mentions', (select coalesce(jsonb_agg(u.email), '[]') from auth.users u where u.id = any (c.mentions)))
                         order by c.created_at), '[]') from task_comments c where c.task_id = t.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('action', e.action, 'actor_label', coalesce(e.actor_label, 'sistema'), 'actor_kind', e.actor_kind,
                   'before', e.before, 'after', e.after, 'created_at', e.created_at) order by e.created_at), '[]') from task_events e where e.task_id = t.id),
    'can_manage', public.ws_can('tasks.manage', t.workspace_id, p_token),
    'can_work', public.ws_can('tasks.work', t.workspace_id, p_token) and (t.assignee_id = auth.uid() or public.ws_can('tasks.manage', t.workspace_id, p_token)));
end $$;

-- Pessoas a quem se pode atribuir neste workspace (têm tasks.work agora).
create or replace function public.tasks_assignees(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('tasks.read', p_ws, p_token, 'task.assignees', null);
  return (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'email', u.email) order by u.email), '[]')
          from auth.users u
          where (exists (select 1 from workspace_access a where a.user_id = u.id and a.workspace_id = p_ws)
                 or exists (select 1 from agency_memberships m join clients c on c.organization_id = m.organization_id
                            where m.user_id = u.id and c.id = p_ws and m.agency_role = 'agency_owner'))
            and public._authorize('tasks.work', p_ws, u.id));
end $$;

-- ───────────── escrita ─────────────
create or replace function public.task_create(p_ws text, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t tasks; k text; ref uuid := nullif(p_fields->>'client_ref','')::uuid; d text;
begin
  perform public._content_require('tasks.manage', p_ws, p_token, 'task.create', null);
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('title','description','kind','priority','assignee_id','due_at','content_id','source_id','depends_on','client_ref') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
  end loop;
  if ref is not null then
    select * into t from tasks where workspace_id = p_ws and client_ref = ref;
    if t.id is not null then return public._task_row(t); end if;
  end if;
  perform public._task_valid_assignee(p_ws, nullif(p_fields->>'assignee_id','')::uuid);
  insert into tasks (workspace_id, title, description, kind, priority, assignee_id, due_at, content_id, source_id, client_ref,
                     created_by, created_kind, created_label)
  values (p_ws, btrim(p_fields->>'title'), nullif(btrim(p_fields->>'description'), ''), coalesce(nullif(p_fields->>'kind',''), 'task'),
          coalesce(nullif(p_fields->>'priority',''), 'normal'), nullif(p_fields->>'assignee_id','')::uuid, nullif(p_fields->>'due_at','')::timestamptz,
          nullif(p_fields->>'content_id',''), nullif(p_fields->>'source_id','')::bigint, ref, (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into t;
  for d in select jsonb_array_elements_text(coalesce(p_fields->'depends_on', '[]'::jsonb)) loop
    insert into task_dependencies (task_id, depends_on, workspace_id) values (t.id, d::uuid, p_ws);
  end loop;
  perform public._task_log(t, a, 'task.created', null, jsonb_build_object('title', t.title, 'assignee_id', t.assignee_id, 'due_at', t.due_at, 'status', t.status));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'task.created', 'task', t.id::text, jsonb_build_object('assignee_id', t.assignee_id, 'content_id', t.content_id));
  perform public._notify(t.assignee_id, p_ws, 'task_assigned', 'task', t.id::text, 'Nova tarefa: ' || t.title, a->>'label', 'assigned:' || t.id || ':' || t.lock_version);
  return public._task_row(t);
end $$;

create or replace function public.task_update(p_id uuid, p_patch jsonb, p_lock integer default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t tasks; o tasks; k text; mgr boolean; before jsonb := '{}'; after jsonb := '{}';
        st text := p_patch->>'status'; newa uuid;
begin
  select * into t from tasks where id = p_id for update;
  if t.id is null then raise exception 'tarefa_nao_encontrada' using errcode = 'P0002'; end if;
  mgr := public.ws_can('tasks.manage', t.workspace_id, p_token);
  if not mgr then
    perform public._content_require('tasks.work', t.workspace_id, p_token, 'task.update', t.id::text);
    -- sem gerir: só o responsável, e só estado/bloqueio (TEAM-05 assigned_only)
    if t.assignee_id is distinct from auth.uid() or auth.uid() is null then
      raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', t.workspace_id, 'action', 'task.update', 'entity_id', t.id);
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
  end if;
  if p_lock is not null and p_lock <> t.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('status','blocked_reason','title','description','priority','due_at','assignee_id','kind') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
    if not mgr and k not in ('status','blocked_reason') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  end loop;
  if st is not null and st not in ('todo','doing','blocked','done','cancelled') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if st = 'cancelled' and not mgr then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if st = 'blocked' and coalesce(btrim(p_patch->>'blocked_reason'), '') = '' then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  if st = 'done' and exists (select 1 from task_dependencies d join tasks x on x.id = d.depends_on
                             where d.task_id = t.id and x.status not in ('done','cancelled')) then
    raise exception 'dependencias_abertas' using errcode = '22023';
  end if;
  if p_patch ? 'assignee_id' then
    newa := nullif(p_patch->>'assignee_id','')::uuid;
    perform public._task_valid_assignee(t.workspace_id, newa);
  end if;
  if p_patch ? 'title' and length(btrim(coalesce(p_patch->>'title',''))) < 2 then raise exception 'titulo_obrigatorio' using errcode = '22023'; end if;
  o := t;
  update tasks set
    status = coalesce(st, status),
    blocked_reason = case when coalesce(st, status) = 'blocked' then coalesce(nullif(btrim(p_patch->>'blocked_reason'), ''), blocked_reason) else null end,
    title = coalesce(nullif(btrim(p_patch->>'title'), ''), title),
    description = case when p_patch ? 'description' then nullif(btrim(p_patch->>'description'), '') else description end,
    priority = coalesce(nullif(p_patch->>'priority',''), priority),
    kind = coalesce(nullif(p_patch->>'kind',''), kind),
    due_at = case when p_patch ? 'due_at' then nullif(p_patch->>'due_at','')::timestamptz else due_at end,
    assignee_id = case when p_patch ? 'assignee_id' then newa else assignee_id end
  where id = t.id returning * into t;
  for k in select jsonb_object_keys(p_patch) loop
    if to_jsonb(o)->k is distinct from to_jsonb(t)->k then
      before := before || jsonb_build_object(k, to_jsonb(o)->k); after := after || jsonb_build_object(k, to_jsonb(t)->k);
    end if;
  end loop;
  if after = '{}'::jsonb then return public._task_row(t); end if;
  perform public._task_log(t, a, 'task.updated', before, after);
  if o.status is distinct from t.status then
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (t.workspace_id, 'task.' || t.status, 'task', t.id::text, jsonb_build_object('from', o.status, 'content_id', t.content_id));
  end if;
  -- mudança de responsável notifica ambos (TEAM-06)
  if o.assignee_id is distinct from t.assignee_id then
    perform public._notify(t.assignee_id, t.workspace_id, 'task_assigned', 'task', t.id::text, 'Tarefa atribuída a ti: ' || t.title, a->>'label', 'assigned:' || t.id || ':' || t.lock_version);
    perform public._notify(o.assignee_id, t.workspace_id, 'task_unassigned', 'task', t.id::text, 'Tarefa passou para outra pessoa: ' || t.title, a->>'label', 'unassigned:' || t.id || ':' || t.lock_version);
  end if;
  if t.status = 'blocked' and o.status <> 'blocked' then
    perform public._notify(t.created_by, t.workspace_id, 'task_blocked', 'task', t.id::text, 'Tarefa bloqueada: ' || t.title, t.blocked_reason, 'blocked:' || t.id || ':' || t.lock_version);
  elsif t.status = 'done' and o.status <> 'done' then
    perform public._notify(t.created_by, t.workspace_id, 'task_done', 'task', t.id::text, 'Tarefa concluída: ' || t.title, a->>'label', 'done:' || t.id || ':' || t.lock_version);
  end if;
  return public._task_row(t);
end $$;

-- Dependências: mesma conta, sem ciclos.
create or replace function public.task_depend(p_id uuid, p_on uuid, p_link boolean default true, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t tasks; x tasks;
begin
  select * into t from tasks where id = p_id;
  select * into x from tasks where id = p_on;
  if t.id is null or x.id is null then raise exception 'tarefa_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('tasks.manage', t.workspace_id, p_token, 'task.depend', t.id::text);
  if x.workspace_id <> t.workspace_id then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_link then
    if p_id = p_on or exists (
      with recursive up(id) as (select p_on union select d.depends_on from task_dependencies d join up on d.task_id = up.id)
      select 1 from up where id = p_id) then
      raise exception 'dependencia_circular' using errcode = '22023';
    end if;
    insert into task_dependencies (task_id, depends_on, workspace_id) values (p_id, p_on, t.workspace_id) on conflict do nothing;
  else
    delete from task_dependencies where task_id = p_id and depends_on = p_on;
  end if;
  perform public._task_log(t, a, case when p_link then 'task.dependency_added' else 'task.dependency_removed' end, null, jsonb_build_object('depends_on', p_on, 'title', x.title));
  return public._task_row(t);
end $$;

create or replace function public.task_comment(p_id uuid, p_body text, p_mentions uuid[] default '{}', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t tasks; m uuid; c task_comments;
begin
  select * into t from tasks where id = p_id;
  if t.id is null then raise exception 'tarefa_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('tasks.work', t.workspace_id, p_token, 'task.comment', t.id::text);
  if coalesce(btrim(p_body), '') = '' then raise exception 'comentario_vazio' using errcode = '22023'; end if;
  if length(p_body) > 4000 then raise exception 'comentario_longo' using errcode = '22023'; end if;
  foreach m in array coalesce(p_mentions, '{}') loop
    if not public._authorize('tasks.read', t.workspace_id, m) then raise exception 'mencao_sem_acesso' using errcode = '22023'; end if;
  end loop;
  insert into task_comments (task_id, workspace_id, author_id, author_label, body, mentions)
  values (t.id, t.workspace_id, (a->>'uid')::uuid, a->>'label', btrim(p_body), coalesce(p_mentions, '{}')) returning * into c;
  perform public._task_log(t, a, 'task.commented', null, jsonb_build_object('comment_id', c.id));
  foreach m in array coalesce(p_mentions, '{}') loop
    perform public._notify(m, t.workspace_id, 'task_mention', 'task', t.id::text, (a->>'label') || ' mencionou-te: ' || t.title, left(c.body, 300), 'mention:' || c.id || ':' || m);
  end loop;
  if t.assignee_id is not null and not (t.assignee_id = any (coalesce(p_mentions, '{}'))) then
    perform public._notify(t.assignee_id, t.workspace_id, 'task_mention', 'task', t.id::text, 'Comentário na tua tarefa: ' || t.title, left(c.body, 300), 'comment:' || c.id);
  end if;
  return public.task_get(t.id, p_token);
end $$;

-- ───────────── regras de handoff ─────────────
create or replace function public.task_rules_list(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('tasks.manage', p_ws, null, 'task_rule.list', null);
  return (select coalesce(jsonb_agg(to_jsonb(r) || jsonb_build_object(
            'assignee_email', (select email from auth.users where id = r.assignee_id),
            'assignee_has_access', case when r.assignee_id is null then null else public._authorize('tasks.work', r.workspace_id, r.assignee_id) end,
            'tasks_open', (select count(*) from tasks t where t.rule_id = r.id and t.status in ('todo','doing','blocked')))
          order by r.created_at), '[]') from task_rules r where r.workspace_id = p_ws);
end $$;

create or replace function public.task_rule_save(p_ws text, p_rule jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); r task_rules; rid uuid := nullif(p_rule->>'id','')::uuid; k text; e text;
        evs text[] := array['script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
                            'recording.confirmed','request.created','source.approved'];
begin
  perform public._content_require('tasks.manage', p_ws, null, 'task_rule.save', rid::text);
  for k in select jsonb_object_keys(p_rule) loop
    if k not in ('id','on_event','complete_on','kind','title','assignee_id','priority','due_hours','active') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
  end loop;
  for e in select jsonb_array_elements_text(coalesce(p_rule->'complete_on','[]'::jsonb)) loop
    if not e = any (evs) then raise exception 'evento_invalido: %', e using errcode = '22023'; end if;
  end loop;
  perform public._task_valid_assignee(p_ws, nullif(p_rule->>'assignee_id','')::uuid);
  if rid is null then
    insert into task_rules (workspace_id, on_event, complete_on, kind, title, assignee_id, priority, due_hours, active, created_by)
    values (p_ws, p_rule->>'on_event',
            coalesce((select array_agg(x) from jsonb_array_elements_text(p_rule->'complete_on') x), '{}'),
            coalesce(nullif(p_rule->>'kind',''), 'task'), btrim(p_rule->>'title'), nullif(p_rule->>'assignee_id','')::uuid,
            coalesce(nullif(p_rule->>'priority',''), 'normal'), nullif(p_rule->>'due_hours','')::integer, coalesce((p_rule->>'active')::boolean, true),
            (a->>'uid')::uuid)
    returning * into r;
  else
    select * into r from task_rules where id = rid for update;
    if r.id is null or r.workspace_id <> p_ws then raise exception 'regra_nao_encontrada' using errcode = 'P0002'; end if;
    update task_rules set
      on_event = coalesce(nullif(p_rule->>'on_event',''), on_event),
      complete_on = case when p_rule ? 'complete_on' then coalesce((select array_agg(x) from jsonb_array_elements_text(p_rule->'complete_on') x), '{}') else complete_on end,
      kind = coalesce(nullif(p_rule->>'kind',''), kind),
      title = coalesce(nullif(btrim(p_rule->>'title'),''), title),
      assignee_id = case when p_rule ? 'assignee_id' then nullif(p_rule->>'assignee_id','')::uuid else assignee_id end,
      priority = coalesce(nullif(p_rule->>'priority',''), priority),
      due_hours = case when p_rule ? 'due_hours' then nullif(p_rule->>'due_hours','')::integer else due_hours end,
      active = coalesce((p_rule->>'active')::boolean, active)
    where id = rid returning * into r;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when rid is null then 'task_rule.created' else 'task_rule.updated' end,
          'task_rule', r.id::text, to_jsonb(r));
  return to_jsonb(r);
end $$;

-- Consumidor síncrono do outbox: cria e fecha tarefas pelas regras do workspace. Idempotente por dedup_key
-- (regra + entidade + versão), por isso repetir a transição não duplica tarefas (FR-17-05).
create or replace function public.domain_events_handoff() returns trigger language plpgsql security definer set search_path = public as $$
declare r task_rules; t tasks; g guioes; s ideas; cid text; sid bigint; key text; ttl text; sys jsonb;
begin
  if new.type not in ('script.created','script.submitted','script.approved','script.rejected','review.changes_requested',
                      'recording.confirmed','request.created','source.approved') then
    return null;
  end if;
  if new.entity_type = 'content' then cid := new.entity_id; select * into g from guioes where id = cid;
  elsif new.entity_type = 'source' then sid := new.entity_id::bigint; select * into s from ideas where id = sid;
  else return null; end if;
  sys := jsonb_build_object('kind', 'system', 'uid', null, 'label', 'Automação');
  -- fechar as tarefas automáticas que este evento conclui
  for t in select x.* from tasks x join task_rules rr on rr.id = x.rule_id
            where x.workspace_id = new.workspace_id and new.type = any (rr.complete_on) and x.status in ('todo','doing','blocked')
              and (x.content_id is not distinct from cid) and (x.source_id is not distinct from sid)
            for update of x loop
    update tasks set status = 'done' where id = t.id;
    perform public._task_log(t, sys, 'task.auto_completed', jsonb_build_object('status', t.status), jsonb_build_object('status', 'done', 'event', new.type));
  end loop;
  -- criar as tarefas que este evento abre
  for r in select * from task_rules where workspace_id = new.workspace_id and on_event = new.type and active loop
    key := r.id || ':' || new.entity_id || ':' || coalesce(new.payload->>'version_id', '-');
    ttl := replace(replace(replace(r.title, '{n}', coalesce(g.n::text, '')), '{tema}', coalesce(g.tema, s.titulo, '')),
                   '{data}', coalesce(to_char(g.date, 'DD/MM'), ''));
    insert into tasks (workspace_id, title, kind, priority, assignee_id, due_at, content_id, source_id, rule_id, dedup_key, created_kind, created_label)
    values (new.workspace_id, left(coalesce(nullif(btrim(ttl), ''), r.title), 200), r.kind, r.priority,
            case when r.assignee_id is not null and public._authorize('tasks.work', new.workspace_id, r.assignee_id) then r.assignee_id end,
            case when r.due_hours is not null then now() + make_interval(hours => r.due_hours) end, cid, sid, r.id, key, 'system', 'Automação')
    on conflict (workspace_id, dedup_key) where dedup_key is not null do nothing
    returning * into t;
    if t.id is not null then
      perform public._task_log(t, sys, 'task.created', null, jsonb_build_object('rule_id', r.id, 'event', new.type, 'assignee_id', t.assignee_id));
      perform public._notify(t.assignee_id, t.workspace_id, 'task_auto', 'task', t.id::text, 'Nova tarefa: ' || t.title, 'Criada automaticamente', 'auto:' || t.id);
    end if;
    t := null;
  end loop;
  return null;
end $$;
create trigger domain_events_handoff after insert on public.domain_events for each row execute function public.domain_events_handoff();

-- ───────────── caixa de entrada pessoal (todos os workspaces autorizados) ─────────────
create or replace function public.inbox() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  return jsonb_build_object(
    'notifications', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'workspace_id', n.workspace_id, 'workspace', c.name, 'kind', n.kind,
                        'entity_type', n.entity_type, 'entity_id', n.entity_id, 'title', n.title, 'body', n.body, 'read_at', n.read_at, 'created_at', n.created_at)
                        order by n.created_at desc), '[]')
                      from (select * from notifications where user_id = uid and (read_at is null or created_at > now() - interval '14 days')
                            order by created_at desc limit 200) n
                      join clients c on c.id = n.workspace_id
                      where public._authorize('tasks.read', n.workspace_id, uid)),
    'tasks', (select coalesce(jsonb_agg(public._task_row(t) || jsonb_build_object('workspace', c.name)
                 order by t.due_at nulls last, t.created_at), '[]')
              from tasks t join clients c on c.id = t.workspace_id
              where t.assignee_id = uid and t.status in ('todo','doing','blocked') and public._authorize('tasks.work', t.workspace_id, uid)),
    'approvals', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'workspace_id', g.client_id, 'workspace', c.name, 'n', g.n, 'date', g.date,
                     'tema', g.tema, 'hook', g.hooks->0->>'text', 'since', g.updated_at) order by g.date, g.n), '[]')
                  from guioes g join clients c on c.id = g.client_id
                  where g.editorial_status = 'in_review' and public._authorize('scripts.approve', g.client_id, uid)),
    'unassigned', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'workspace_id', t.workspace_id, 'workspace', c.name, 'title', t.title,
                      'created_at', t.created_at) order by t.created_at), '[]')
                   from tasks t join clients c on c.id = t.workspace_id
                   where t.status in ('todo','doing','blocked') and public._authorize('tasks.manage', t.workspace_id, uid)
                     and (t.assignee_id is null or not public._authorize('tasks.work', t.workspace_id, t.assignee_id))));
end $$;

-- Marcar lido não aprova nem fecha nada (FR-17-01).
create or replace function public.notifications_read(p_ids uuid[] default null) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if auth.uid() is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  update notifications set read_at = now() where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics n = row_count;
  return n;
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public.tasks_before_write(), public.task_children_same_ws(), public.task_rules_before_write(), public.domain_events_handoff(),
  public._notify(uuid,text,text,text,text,text,text,text), public._task_log(tasks,jsonb,text,jsonb,jsonb), public._task_row(tasks),
  public._task_valid_assignee(text,uuid) from public, anon, authenticated;
revoke all on function public.tasks_list(text,text,text,text), public.task_get(uuid,text), public.tasks_assignees(text,text),
  public.task_create(text,jsonb,text), public.task_update(uuid,jsonb,integer,text), public.task_depend(uuid,uuid,boolean,text),
  public.task_comment(uuid,text,uuid[],text), public.task_rules_list(text), public.task_rule_save(text,jsonb),
  public.inbox(), public.notifications_read(uuid[]) from public, anon;
-- leitura com código de equipa (anon + token); escrita e caixa de entrada só com conta
grant execute on function public.tasks_list(text,text,text,text), public.task_get(uuid,text), public.tasks_assignees(text,text) to anon, authenticated;
grant execute on function public.task_create(text,jsonb,text), public.task_update(uuid,jsonb,integer,text), public.task_depend(uuid,uuid,boolean,text),
  public.task_comment(uuid,text,uuid[],text), public.task_rules_list(text), public.task_rule_save(text,jsonb),
  public.inbox(), public.notifications_read(uuid[]) to authenticated;

/* Rollback:
drop trigger domain_events_handoff on domain_events;
drop function inbox, notifications_read, task_rules_list, task_rule_save, task_comment, task_depend, task_update, task_create,
  tasks_assignees, task_get, tasks_list, _task_valid_assignee, _task_row, _task_log, _notify, domain_events_handoff,
  task_rules_before_write, task_children_same_ws, tasks_before_write;
drop table notifications, task_events, task_comments, task_dependencies, tasks, task_rules;
delete from role_capabilities where capability = 'tasks.work'; delete from capabilities where key = 'tasks.work';
update capabilities set status = 'W3', module = 'Calendário' where key in ('tasks.read','tasks.manage');
-- reaplicar legacy_can de 20261028205017_w2_references.
*/
