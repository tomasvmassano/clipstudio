-- W3-03 Templates de produção, checklists por conteúdo e carga por pessoa (PRD FR-11-04, FR-17-08, FR-17-09, TEAM-08 parcial; AGENTS §6).
-- Template = lista de tarefas (com prazo relativo ao dia do guião, dependências e responsável opcional) + checklist.
-- Aplicar a um guião é idempotente (repetir não duplica). Clonar para outro cliente nunca leva responsáveis nem dados do original.
-- Carga = tarefas abertas por pessoa no cliente, com limite de WIP que só avisa (não bloqueia).
-- Só aditivo. Rollback: bloco no fim.

alter table public.clients add column if not exists wip_limit integer check (wip_limit is null or wip_limit between 1 and 100);

create table public.task_templates (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  name text not null check (length(btrim(name)) between 2 and 120),
  description text check (description is null or length(description) <= 1000),
  -- [{title, kind, priority, offset_days, hour, assignee_id, depends_on: [índices]}]
  items jsonb not null default '[]' check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 30),
  checklist jsonb not null default '[]' check (jsonb_typeof(checklist) = 'array' and jsonb_array_length(checklist) <= 50),
  active boolean not null default true,
  cloned_from uuid references public.task_templates(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index task_templates_ws on public.task_templates (workspace_id) where active;

create table public.content_checklist (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  label text not null check (length(btrim(label)) between 1 and 200),
  position integer not null default 0,
  done boolean not null default false,
  done_by uuid references auth.users(id) on delete set null,
  done_label text,
  done_at timestamptz,
  template_id uuid references public.task_templates(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index content_checklist_label on public.content_checklist (content_id, lower(label));
create index content_checklist_content on public.content_checklist (content_id, position);

create or replace function public.content_checklist_same_ws() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select client_id from guioes where id = new.content_id)
     or (new.template_id is not null and new.workspace_id is distinct from (select workspace_id from task_templates where id = new.template_id)) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.workspace_id, new.content_id) is distinct from (old.workspace_id, old.content_id) then
    raise exception 'imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger content_checklist_ws before insert or update on public.content_checklist for each row execute function public.content_checklist_same_ws();
create trigger content_checklist_no_delete before delete on public.content_checklist for each row execute function public.content_append_only();

create or replace function public.task_templates_before_write() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'imutavel' using errcode = '42501'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger task_templates_before_write before insert or update on public.task_templates for each row execute function public.task_templates_before_write();

alter table public.task_templates enable row level security;
alter table public.content_checklist enable row level security;
revoke all on public.task_templates, public.content_checklist from anon, authenticated;
grant select on public.task_templates, public.content_checklist to authenticated;
create policy task_templates_select on public.task_templates for select to authenticated using (public.authorize('tasks.read', workspace_id));
create policy content_checklist_select on public.content_checklist for select to authenticated using (public.authorize('scripts.read', workspace_id));

-- ───────────── templates ─────────────
-- Valida e normaliza os itens; responsáveis têm de ter tasks.work no cliente (ou ficam vazios se p_drop_assignees).
create or replace function public._template_clean(p_ws text, p_items jsonb, p_checklist jsonb, p_drop_assignees boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare it jsonb; out jsonb := '[]'; i integer := 0; d jsonb; a uuid; k text; cl jsonb := '[]'; lbl text;
begin
  if jsonb_typeof(coalesce(p_items, '[]')) <> 'array' or jsonb_array_length(coalesce(p_items, '[]')) > 30 then raise exception 'template_invalido' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_checklist, '[]')) <> 'array' or jsonb_array_length(coalesce(p_checklist, '[]')) > 50 then raise exception 'template_invalido' using errcode = '22023'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    for k in select jsonb_object_keys(it) loop
      if k not in ('title','kind','priority','offset_days','hour','assignee_id','depends_on') then raise exception 'campo_invalido: %', k using errcode = '22023'; end if;
    end loop;
    if length(btrim(coalesce(it->>'title',''))) < 2 then raise exception 'titulo_obrigatorio' using errcode = '22023'; end if;
    if coalesce(it->>'kind','task') not in ('task','review','recording','edit','publish','request') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
    if coalesce(it->>'priority','normal') not in ('low','normal','high','urgent') then raise exception 'prioridade_invalida' using errcode = '22023'; end if;
    if coalesce((it->>'offset_days')::integer, 0) not between -60 and 60 then raise exception 'prazo_invalido' using errcode = '22023'; end if;
    if coalesce((it->>'hour')::integer, 10) not between 0 and 23 then raise exception 'prazo_invalido' using errcode = '22023'; end if;
    a := nullif(it->>'assignee_id','')::uuid;
    if p_drop_assignees then a := null; elsif a is not null then perform public._task_valid_assignee(p_ws, a); end if;
    d := '[]';
    if it ? 'depends_on' then
      if jsonb_typeof(it->'depends_on') <> 'array' then raise exception 'dependencia_invalida' using errcode = '22023'; end if;
      -- só pode depender de itens anteriores: garante que não há ciclos
      if exists (select 1 from jsonb_array_elements_text(it->'depends_on') x where x !~ '^\d+$' or x::integer >= i) then
        raise exception 'dependencia_invalida' using errcode = '22023';
      end if;
      d := it->'depends_on';
    end if;
    out := out || jsonb_build_array(jsonb_build_object('title', btrim(it->>'title'), 'kind', coalesce(it->>'kind','task'),
             'priority', coalesce(it->>'priority','normal'), 'offset_days', coalesce((it->>'offset_days')::integer, 0),
             'hour', coalesce((it->>'hour')::integer, 10), 'assignee_id', a, 'depends_on', d));
    i := i + 1;
  end loop;
  for lbl in select btrim(x) from jsonb_array_elements_text(coalesce(p_checklist, '[]')) x loop
    if length(lbl) between 1 and 200 and not cl @> jsonb_build_array(lbl) then cl := cl || jsonb_build_array(lbl); end if;
  end loop;
  return jsonb_build_object('items', out, 'checklist', cl);
end $$;

create or replace function public._template_row(t task_templates) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(t) || jsonb_build_object(
    'items', (select coalesce(jsonb_agg(i || jsonb_build_object(
                 'assignee_email', (select email from auth.users where id = (i->>'assignee_id')::uuid),
                 'assignee_has_access', case when i->>'assignee_id' is null then null else public._authorize('tasks.work', t.workspace_id, (i->>'assignee_id')::uuid) end)
               order by o), '[]') from jsonb_array_elements(t.items) with ordinality as x(i, o)),
    'applied', (select count(distinct content_id) from tasks k where k.workspace_id = t.workspace_id and k.dedup_key like 'tpl:' || t.id || ':%'));
$$;

create or replace function public.templates_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('tasks.read', p_ws, p_token, 'template.list', null);
  return (select coalesce(jsonb_agg(public._template_row(t) order by t.active desc, t.name), '[]') from task_templates t where t.workspace_id = p_ws);
end $$;

create or replace function public.template_save(p_ws text, p_tpl jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); t task_templates; tid uuid := nullif(p_tpl->>'id','')::uuid; c jsonb; k text;
begin
  perform public._content_require('tasks.manage', p_ws, null, 'template.save', tid::text);
  for k in select jsonb_object_keys(p_tpl) loop
    if k not in ('id','name','description','items','checklist','active') then raise exception 'campo_invalido: %', k using errcode = '22023'; end if;
  end loop;
  if tid is not null then
    select * into t from task_templates where id = tid for update;
    if t.id is null or t.workspace_id <> p_ws then raise exception 'template_nao_encontrado' using errcode = 'P0002'; end if;
  end if;
  c := public._template_clean(p_ws, coalesce(p_tpl->'items', to_jsonb(t)->'items'), coalesce(p_tpl->'checklist', to_jsonb(t)->'checklist'), false);
  if tid is null then
    if length(btrim(coalesce(p_tpl->>'name',''))) < 2 then raise exception 'nome_obrigatorio' using errcode = '22023'; end if;
    insert into task_templates (workspace_id, name, description, items, checklist, active, created_by)
    values (p_ws, btrim(p_tpl->>'name'), nullif(btrim(p_tpl->>'description'),''), c->'items', c->'checklist', coalesce((p_tpl->>'active')::boolean, true), (a->>'uid')::uuid)
    returning * into t;
  else
    update task_templates set name = coalesce(nullif(btrim(p_tpl->>'name'),''), name),
           description = case when p_tpl ? 'description' then nullif(btrim(p_tpl->>'description'),'') else description end,
           items = c->'items', checklist = c->'checklist', active = coalesce((p_tpl->>'active')::boolean, active)
     where id = tid returning * into t;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when tid is null then 'template.created' else 'template.updated' end, 'task_template', t.id::text, to_jsonb(t));
  return public._template_row(t);
end $$;

-- Clonar para outro cliente: precisa de gerir os dois; nunca leva responsáveis (podem não ter acesso ao destino).
create or replace function public.template_clone(p_tpl uuid, p_target_ws text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); s task_templates; t task_templates; c jsonb;
begin
  select * into s from task_templates where id = p_tpl;
  if s.id is null then raise exception 'template_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('tasks.manage', s.workspace_id, null, 'template.clone', s.id::text);
  perform public._content_require('tasks.manage', p_target_ws, null, 'template.clone', s.id::text);
  c := public._template_clean(p_target_ws, s.items, s.checklist, true);
  insert into task_templates (workspace_id, name, description, items, checklist, cloned_from, created_by)
  values (p_target_ws, s.name, s.description, c->'items', c->'checklist', case when s.workspace_id = p_target_ws then s.id end, (a->>'uid')::uuid)
  returning * into t;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_target_ws, 'template.cloned', 'task_template', t.id::text, jsonb_build_object('from_workspace', s.workspace_id));
  return public._template_row(t);
end $$;

-- Aplicar a um guião: cria as tarefas (prazo = dia do guião + offset, à hora do cliente) e a checklist. Idempotente.
create or replace function public.template_apply(p_tpl uuid, p_content text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); tp task_templates; g guioes; it jsonb; o bigint; ids uuid[] := '{}'; tk tasks; d text; tz text;
        made integer := 0; lbl text; pos integer;
begin
  select * into tp from task_templates where id = p_tpl;
  if tp.id is null or not tp.active then raise exception 'template_nao_encontrado' using errcode = 'P0002'; end if;
  select * into g from guioes where id = p_content;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('tasks.manage', g.client_id, p_token, 'template.apply', g.id);
  if tp.workspace_id <> g.client_id then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = g.client_id;
  for it, o in select x, n from jsonb_array_elements(tp.items) with ordinality as y(x, n) loop
    insert into tasks (workspace_id, title, kind, priority, assignee_id, due_at, content_id, dedup_key, created_by, created_kind, created_label)
    values (g.client_id, left(replace(replace(it->>'title', '{n}', g.n::text), '{tema}', coalesce(g.tema, '')), 200), it->>'kind', it->>'priority',
            case when it->>'assignee_id' is not null and public._authorize('tasks.work', g.client_id, (it->>'assignee_id')::uuid) then (it->>'assignee_id')::uuid end,
            ((g.date + (it->>'offset_days')::integer)::timestamp + make_interval(hours => (it->>'hour')::integer)) at time zone tz,
            g.id, 'tpl:' || tp.id || ':' || g.id || ':' || (o - 1), (a->>'uid')::uuid, a->>'kind', a->>'label')
    on conflict (workspace_id, dedup_key) where dedup_key is not null do nothing
    returning * into tk;
    if tk.id is null then
      select * into tk from tasks where workspace_id = g.client_id and dedup_key = 'tpl:' || tp.id || ':' || g.id || ':' || (o - 1);
    else
      made := made + 1;
      perform public._task_log(tk, a, 'task.created', null, jsonb_build_object('template_id', tp.id, 'title', tk.title));
      perform public._notify(tk.assignee_id, tk.workspace_id, 'task_assigned', 'task', tk.id::text, 'Nova tarefa: ' || tk.title, a->>'label', 'assigned:' || tk.id || ':' || tk.lock_version);
      for d in select jsonb_array_elements_text(it->'depends_on') loop
        insert into task_dependencies (task_id, depends_on, workspace_id) values (tk.id, ids[d::integer + 1], g.client_id) on conflict do nothing;
      end loop;
    end if;
    ids := ids || tk.id;
    tk := null;
  end loop;
  select coalesce(max(position), 0) into pos from content_checklist where content_id = g.id;
  for lbl in select jsonb_array_elements_text(tp.checklist) loop
    pos := pos + 1;
    insert into content_checklist (workspace_id, content_id, label, position, template_id) values (g.client_id, g.id, lbl, pos, tp.id)
    on conflict (content_id, lower(label)) do nothing;
  end loop;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'template.applied', 'guiao', g.id, jsonb_build_object('template_id', tp.id, 'tasks_created', made));
  return jsonb_build_object('tasks_created', made, 'tasks', jsonb_array_length(tp.items), 'checklist', public.checklist_list(g.id, p_token));
end $$;

-- ───────────── checklist por guião ─────────────
create or replace function public.checklist_list(p_content text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ws text := (select client_id from guioes where id = p_content);
begin
  if ws is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', ws, p_token, 'checklist.list', p_content);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'label', c.label, 'done', c.done, 'done_label', c.done_label, 'done_at', c.done_at,
                   'from_template', c.template_id is not null) order by c.position, c.created_at), '[]')
          from content_checklist c where c.content_id = p_content);
end $$;

create or replace function public.checklist_add(p_content text, p_label text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes;
begin
  select * into g from guioes where id = p_content;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('production.update', g.client_id, p_token, 'checklist.add', g.id);
  if length(btrim(coalesce(p_label, ''))) not between 1 and 200 then raise exception 'texto_invalido' using errcode = '22023'; end if;
  insert into content_checklist (workspace_id, content_id, label, position)
  values (g.client_id, g.id, btrim(p_label), coalesce((select max(position) from content_checklist where content_id = g.id), 0) + 1)
  on conflict (content_id, lower(label)) do nothing;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'checklist.added', 'guiao', g.id, jsonb_build_object('label', btrim(p_label)));
  return public.checklist_list(g.id, p_token);
end $$;

create or replace function public.checklist_toggle(p_item uuid, p_done boolean, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); c content_checklist;
begin
  select * into c from content_checklist where id = p_item for update;
  if c.id is null then raise exception 'item_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('production.update', c.workspace_id, p_token, 'checklist.toggle', c.content_id);
  if c.done is distinct from p_done then
    update content_checklist set done = p_done, done_by = case when p_done then (a->>'uid')::uuid end,
           done_label = case when p_done then a->>'label' end, done_at = case when p_done then now() end
     where id = c.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', c.workspace_id, case when p_done then 'checklist.done' else 'checklist.undone' end,
            'guiao', c.content_id, jsonb_build_object('label', c.label));
  end if;
  return public.checklist_list(c.content_id, p_token);
end $$;

-- ───────────── carga por pessoa ─────────────
create or replace function public.workload(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim integer; tz text;
begin
  perform public._content_require('tasks.manage', p_ws, p_token, 'workload.read', null);
  select wip_limit, coalesce(timezone, 'UTC') into lim, tz from clients where id = p_ws;
  return jsonb_build_object(
    'wip_limit', lim,
    'people', (select coalesce(jsonb_agg(p order by (p->>'open')::int desc, p->>'email'), '[]') from (
       select jsonb_build_object('user_id', u.id, 'email', u.email,
                'has_access', public._authorize('tasks.work', p_ws, u.id),
                'open', count(*) filter (where t.status in ('todo','doing','blocked')),
                'doing', count(*) filter (where t.status = 'doing'),
                'blocked', count(*) filter (where t.status = 'blocked'),
                'overdue', count(*) filter (where t.status in ('todo','doing','blocked') and t.due_at < now()),
                'due_7d', count(*) filter (where t.status in ('todo','doing','blocked') and t.due_at between now() and now() + interval '7 days'),
                'done_7d', count(*) filter (where t.status = 'done' and t.completed_at > now() - interval '7 days'),
                'over_limit', lim is not null and count(*) filter (where t.status in ('todo','doing','blocked')) > lim) p
         from tasks t join auth.users u on u.id = t.assignee_id
        where t.workspace_id = p_ws and t.assignee_id is not null
          and (t.status in ('todo','doing','blocked') or t.completed_at > now() - interval '7 days')
        group by u.id, u.email) q),
    'unassigned', (select count(*) from tasks t where t.workspace_id = p_ws and t.status in ('todo','doing','blocked')
                     and (t.assignee_id is null or not public._authorize('tasks.work', p_ws, t.assignee_id))));
end $$;

create or replace function public.workload_set_limit(p_ws text, p_limit integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(null); before integer;
begin
  perform public._content_require('tasks.manage', p_ws, null, 'workload.limit', null);
  if p_limit is not null and p_limit not between 1 and 100 then raise exception 'limite_invalido' using errcode = '22023'; end if;
  select wip_limit into before from clients where id = p_ws;
  update clients set wip_limit = p_limit where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'workload.limit_set', 'workspace', p_ws, jsonb_build_object('wip_limit', before), jsonb_build_object('wip_limit', p_limit));
  return public.workload(p_ws, null);
end $$;

revoke all on function public.content_checklist_same_ws(), public.task_templates_before_write(), public._template_clean(text,jsonb,jsonb,boolean),
  public._template_row(task_templates) from public, anon, authenticated;
revoke all on function public.templates_list(text,text), public.template_save(text,jsonb), public.template_clone(uuid,text), public.template_apply(uuid,text,text),
  public.checklist_list(text,text), public.checklist_add(text,text,text), public.checklist_toggle(uuid,boolean,text),
  public.workload(text,text), public.workload_set_limit(text,integer) from public, anon;
grant execute on function public.templates_list(text,text), public.checklist_list(text,text), public.checklist_add(text,text,text),
  public.checklist_toggle(uuid,boolean,text), public.template_apply(uuid,text,text), public.workload(text,text) to anon, authenticated;
grant execute on function public.template_save(text,jsonb), public.template_clone(uuid,text), public.workload_set_limit(text,integer) to authenticated;

/* Rollback:
drop function workload_set_limit, workload, checklist_toggle, checklist_add, checklist_list, template_apply, template_clone, template_save,
  templates_list, _template_row, _template_clean, task_templates_before_write, content_checklist_same_ws;
drop table content_checklist, task_templates;
alter table clients drop column wip_limit;
-- tarefas criadas por template ficam (dedup_key 'tpl:...'), são tarefas normais.
*/
