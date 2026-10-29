-- W1-06: criar e gerir clientes, e gerir a equipa de cada cliente (PRD §2, §3, CAP-03, CAP-06, CAP-08, SCALE-07, FL-01, TEAM-15; ADR-0012).
-- Só aditivo (o check de workspace_access só fica mais largo). Rollback: bloco no fim.

-- membros removidos ficam no histórico (autoria e auditoria), sem acesso
alter table public.workspace_access drop constraint if exists workspace_access_status_check;
alter table public.workspace_access add constraint workspace_access_status_check check (status in ('active','suspended','removed'));
alter table public.workspace_access add column if not exists updated_at timestamptz;

update public.capabilities set status = 'ativo'
 where key in ('workspaces.read','workspaces.create','workspaces.archive','team.manage','settings.manage');

-- pode na organização? (capacidades de âmbito org)
create or replace function public._org_can(p_cap text, p_org uuid, p_uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid is not null and exists (
    select 1 from agency_memberships m join organizations o on o.id = m.organization_id and o.status = 'active'
      join role_capabilities rc on rc.scope = 'org' and rc.role = m.agency_role and rc.capability = p_cap
     where m.user_id = p_uid and m.organization_id = p_org and m.status = 'active')
$$;

create or replace function public._slug(p text) returns text language sql immutable set search_path = public as $$
  select left(btrim(regexp_replace(lower(translate(coalesce(p, ''),
    'áàâãäåçéèêëíìîïñóòôõöúùûüýÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝ', 'aaaaaaceeeeiiiinooooouuuuyAAAAAACEEEEIIIINOOOOOUUUUY')), '[^a-z0-9]+', '-', 'g'), '-'), 40)
$$;

create or replace function public._ws_validate(p_name text, p_handle text, p_tz text, p_currency text) returns void
language plpgsql stable set search_path = public as $$
begin
  if p_name is null or length(btrim(p_name)) not between 2 and 80 then raise exception 'nome_invalido' using errcode = '22023'; end if;
  if p_handle is not null and p_handle !~ '^[a-z0-9._]{1,30}$' then raise exception 'handle_invalido' using errcode = '22023'; end if;
  if p_tz is null or not exists (select 1 from pg_timezone_names where name = p_tz) then raise exception 'fuso_invalido' using errcode = '22023'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'moeda_invalida' using errcode = '22023'; end if;
end $$;

-- criar cliente; opcionalmente arranca com a estrutura de outro cliente (sem dados privados, pessoas nem segredos: SCALE-07)
create or replace function public.workspace_create(p_name text, p_handle text default null, p_timezone text default 'Asia/Dubai',
                                                   p_currency text default 'EUR', p_copy_from text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; n_org int; v_id text; base text; i int := 1; src clients; cfg jsonb; v jsonb; t record;
        copied jsonb := '{}'; n int;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select count(distinct m.organization_id), min(m.organization_id::text)::uuid into n_org, v_org
    from agency_memberships m where m.user_id = uid and public._org_can('workspaces.create', m.organization_id, uid);
  if n_org = 0 then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', 'workspace.create');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if n_org > 1 then raise exception 'organizacao_ambigua' using errcode = '22023'; end if;
  p_handle := nullif(lower(btrim(coalesce(p_handle, ''))), '');
  p_handle := ltrim(p_handle, '@');
  perform public._ws_validate(p_name, p_handle, p_timezone, upper(p_currency));
  base := public._slug(p_name);
  if length(base) < 2 then raise exception 'nome_invalido' using errcode = '22023'; end if;
  v_id := base;
  while exists (select 1 from clients where id = v_id) loop i := i + 1; v_id := left(base, 36) || '-' || i; end loop;
  insert into clients (id, name, handle, organization_id, timezone, currency, status)
  values (v_id, btrim(p_name), p_handle, v_org, p_timezone, upper(p_currency), 'active');

  if p_copy_from is not null then
    select * into src from clients where id = p_copy_from and organization_id = v_org;
    if src.id is null then raise exception 'cliente_origem_invalido' using errcode = '22023'; end if;
    -- configuração dos agentes: estrutura sim; voz, léxico, notícias e leituras são do cliente de origem e não passam
    if public._authorize('agents.configure', src.id, uid) then
      select config into cfg from agent_config_versions where workspace_id = src.id and status = 'active';
      if cfg is not null then
        cfg := (cfg - 'voice' - 'lexicon' - 'news_beats' - 'reading_list' - 'budget_eur_day')
               || jsonb_build_object('voice', '', 'schedule', jsonb_build_object('enabled', false, 'time', coalesce(cfg->'schedule'->>'time', '18:00')));
        insert into agent_config_versions (workspace_id, version_no, status, config, notes, validation, created_by, created_label)
        values (v_id, 1, 'draft', cfg, 'Estrutura copiada de ' || src.name || '. Falta a voz do cliente.', public.agent_config_validate(cfg), uid,
                (select email from auth.users where id = uid));
        copied := copied || '{"agentes": true}';
      end if;
    end if;
    if public._authorize('tasks.manage', src.id, uid) then
      n := 0;
      for t in select id from task_templates where workspace_id = src.id and active loop
        perform public.template_clone(t.id, v_id); n := n + 1;
      end loop;
      copied := copied || jsonb_build_object('templates', n);
      insert into task_rules (workspace_id, on_event, complete_on, kind, title, assignee_id, priority, due_hours, active, created_by)
      select v_id, r.on_event, r.complete_on, r.kind, r.title, null, r.priority, r.due_hours, r.active, uid
        from task_rules r where r.workspace_id = src.id;
      get diagnostics n = row_count;
      copied := copied || jsonb_build_object('automacoes', n);
    end if;
  end if;

  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', v_org, v_id, 'workspace.created', 'workspace', v_id,
          jsonb_build_object('name', btrim(p_name), 'handle', p_handle, 'timezone', p_timezone, 'currency', upper(p_currency),
                             'copied_from', p_copy_from, 'copied', copied));
  return jsonb_build_object('id', v_id, 'name', btrim(p_name), 'copied', copied);
end $$;

-- editar dados gerais do cliente (M15 geral)
create or replace function public.workspace_update(p_ws text, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients; k text; b jsonb;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('settings.manage', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'workspace.update');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  for k in select jsonb_object_keys(coalesce(p_patch, '{}')) loop
    if k not in ('name','handle','timezone','currency','require_approval_to_record') then raise exception 'campo_desconhecido:%', k using errcode = '22023'; end if;
  end loop;
  if coalesce(p_patch, '{}') = '{}' then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  select * into c from clients where id = p_ws for update;
  b := jsonb_build_object('name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency, 'require_approval_to_record', c.require_approval_to_record);
  c.name := coalesce(btrim(p_patch->>'name'), c.name);
  if p_patch ? 'handle' then c.handle := nullif(ltrim(lower(btrim(coalesce(p_patch->>'handle', ''))), '@'), ''); end if;
  c.timezone := coalesce(p_patch->>'timezone', c.timezone);
  c.currency := upper(coalesce(p_patch->>'currency', c.currency));
  c.require_approval_to_record := coalesce((p_patch->>'require_approval_to_record')::boolean, c.require_approval_to_record);
  perform public._ws_validate(c.name, c.handle, c.timezone, c.currency);
  update clients set name = c.name, handle = c.handle, timezone = c.timezone, currency = c.currency,
                     require_approval_to_record = c.require_approval_to_record where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', c.organization_id, p_ws, 'workspace.updated', 'workspace', p_ws, b,
          jsonb_build_object('name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency, 'require_approval_to_record', c.require_approval_to_record));
  return jsonb_build_object('id', p_ws, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
                            'require_approval_to_record', c.require_approval_to_record);
end $$;

-- arquivar: ninguém entra (authorize exige cliente ativo), a agenda pára e as execuções em fila são canceladas
create or replace function public.workspace_archive(p_ws text, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients; nj int;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select * into c from clients where id = p_ws for update;
  if c.id is null or not public._org_can('workspaces.archive', c.organization_id, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'workspace.archive');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if c.status = 'archived' then return jsonb_build_object('id', p_ws, 'status', 'archived'); end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  update agent_jobs set status = 'cancelled', finished_at = now(), last_error = 'Cliente arquivado' where workspace_id = p_ws and status = 'queued';
  get diagnostics nj = row_count;
  update agent_jobs set cancel_requested = true where workspace_id = p_ws and status = 'running';
  update clients set status = 'archived' where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', c.organization_id, p_ws, 'workspace.archived', 'workspace', p_ws, jsonb_build_object('status', 'active'),
          jsonb_build_object('status', 'archived', 'reason', left(btrim(p_reason), 500), 'jobs_cancelled', nj));
  return jsonb_build_object('id', p_ws, 'status', 'archived', 'jobs_cancelled', nj);
end $$;

create or replace function public.workspace_restore(p_ws text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select * into c from clients where id = p_ws for update;
  if c.id is null or not public._org_can('workspaces.archive', c.organization_id, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if c.status = 'active' then return jsonb_build_object('id', p_ws, 'status', 'active'); end if;
  update clients set status = 'active' where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', c.organization_id, p_ws, 'workspace.restored', 'workspace', p_ws, jsonb_build_object('status', 'archived'), jsonb_build_object('status', 'active'));
  return jsonb_build_object('id', p_ws, 'status', 'active');
end $$;

-- lista de clientes da agência: o dono vê todos (e os arquivados se pode arquivar); o resto da agência só os atribuídos (R-04, CAP-08)
create or replace function public.workspaces_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select m.organization_id into v_org from agency_memberships m where m.user_id = uid and public._org_can('workspaces.read', m.organization_id, uid) limit 1;
  if v_org is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can', jsonb_build_object('create', public._org_can('workspaces.create', v_org, uid), 'archive', public._org_can('workspaces.archive', v_org, uid),
                              'assign_agency', public.is_agency_owner(uid)),
    'clients', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
                  'status', c.status, 'created_at', c.created_at,
                  'members', (select count(*) from workspace_access a where a.workspace_id = c.id and a.status = 'active'),
                  'invites', (select count(*) from invitations i where i.workspace_id = c.id and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()),
                  'can_edit', public._authorize('settings.manage', c.id, uid),
                  'agent_config', (select status from agent_config_versions v where v.workspace_id = c.id order by (v.status = 'active') desc, v.version_no desc limit 1))
                  order by c.status, lower(c.name)), '[]')
                from clients c
               where c.organization_id = v_org
                 and ((c.status = 'active' and (public.is_agency_owner(uid) or exists (select 1 from workspace_access a where a.workspace_id = c.id and a.user_id = uid and a.status = 'active')))
                      or (c.status = 'archived' and public._org_can('workspaces.archive', v_org, uid)))),
    'agency_staff', case when public.is_agency_owner(uid) then (select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', u.email, 'role', m.agency_role)
                  order by u.email), '[]') from agency_memberships m join auth.users u on u.id = m.user_id where m.organization_id = v_org and m.status = 'active') end);
end $$;

-- equipa: quem gere não mexe em si próprio nem acima do seu nível; staff da agência só pelo dono da agência (R-12, CAP-03)
create or replace function public._member_guard(p_ws text, p_user uuid, p_new_role text default null)
returns workspace_access language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); a workspace_access; mine text; owner boolean := public.is_agency_owner(uid);
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('team.manage', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'member.manage');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into a from workspace_access where workspace_id = p_ws and user_id = p_user;
  if a.user_id is null or a.status = 'removed' then raise exception 'membro_nao_encontrado' using errcode = 'P0002'; end if;
  if p_user = uid then raise exception 'nao_a_si_proprio' using errcode = '42501'; end if;
  if p_new_role is not null and public.ws_role_rank(p_new_role) = 0 then raise exception 'papel_invalido' using errcode = '22023'; end if;
  if not owner then
    if a.affiliation_type = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select workspace_role into mine from workspace_access where workspace_id = p_ws and user_id = uid and status = 'active';
    if public.ws_role_rank(a.workspace_role) > public.ws_role_rank(mine)
       or (p_new_role is not null and public.ws_role_rank(p_new_role) > public.ws_role_rank(mine)) then
      raise exception 'acima_do_teto' using errcode = '42501';
    end if;
  end if;
  return a;
end $$;

create or replace function public._last_client_owner(p_ws text, p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_access where workspace_id = p_ws and user_id = p_user and workspace_role = 'workspace_owner'
                 and affiliation_type = 'client_staff' and status = 'active')
     and not exists (select 1 from workspace_access where workspace_id = p_ws and user_id <> p_user and workspace_role = 'workspace_owner'
                     and affiliation_type = 'client_staff' and status = 'active')
$$;

create or replace function public.member_update(p_ws text, p_user uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a workspace_access; k text; r text := p_patch->>'role'; st text := p_patch->>'status'; jt text;
begin
  for k in select jsonb_object_keys(coalesce(p_patch, '{}')) loop
    if k not in ('role','status','job_title','expires_at') then raise exception 'campo_desconhecido:%', k using errcode = '22023'; end if;
  end loop;
  if coalesce(p_patch, '{}') = '{}' then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  a := public._member_guard(p_ws, p_user, r);
  if st is not null and st not in ('active','suspended') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if ((r is not null and r <> 'workspace_owner') or st = 'suspended') and public._last_client_owner(p_ws, p_user) and not public.is_agency_owner(uid) then
    raise exception 'ultimo_dono' using errcode = '22023';
  end if;
  jt := case when p_patch ? 'job_title' then nullif(left(btrim(coalesce(p_patch->>'job_title', '')), 60), '') else a.job_title end;
  update workspace_access set workspace_role = coalesce(r, workspace_role), status = coalesce(st, status), job_title = jt,
         expires_at = case when p_patch ? 'expires_at' then nullif(p_patch->>'expires_at', '')::timestamptz else expires_at end,
         updated_at = now()
   where workspace_id = p_ws and user_id = p_user;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select organization_id from clients where id = p_ws), p_ws, 'member.updated', 'member', p_user::text,
          jsonb_build_object('role', a.workspace_role, 'status', a.status, 'job_title', a.job_title, 'expires_at', a.expires_at),
          jsonb_build_object('role', coalesce(r, a.workspace_role), 'status', coalesce(st, a.status), 'job_title', jt,
                             'expires_at', case when p_patch ? 'expires_at' then p_patch->'expires_at' else to_jsonb(a.expires_at) end));
  return jsonb_build_object('user_id', p_user, 'role', coalesce(r, a.workspace_role), 'status', coalesce(st, a.status), 'job_title', jt);
end $$;

-- remover: perde o acesso já (CAP-06); tarefas abertas passam para quem escolheres ou ficam sem responsável (TEAM-15)
create or replace function public.member_remove(p_ws text, p_user uuid, p_reassign_to uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a workspace_access; t record; n int := 0; lbl text;
begin
  a := public._member_guard(p_ws, p_user);
  if public._last_client_owner(p_ws, p_user) and not public.is_agency_owner(uid) then raise exception 'ultimo_dono' using errcode = '22023'; end if;
  if p_reassign_to is not null and (p_reassign_to = p_user or not public._authorize('tasks.work', p_ws, p_reassign_to)) then
    raise exception 'responsavel_sem_acesso' using errcode = '22023';
  end if;
  select email into lbl from auth.users where id = uid;
  update workspace_access set status = 'removed', updated_at = now() where workspace_id = p_ws and user_id = p_user;
  for t in select id, assignee_id, title from tasks where workspace_id = p_ws and assignee_id = p_user and status not in ('done','cancelled') loop
    update tasks set assignee_id = p_reassign_to where id = t.id;   -- o trigger trata de updated_at e lock_version
    insert into task_events (task_id, workspace_id, actor_id, actor_kind, actor_label, action, before, after)
    values (t.id, p_ws, uid, 'user', lbl, 'reassigned', jsonb_build_object('assignee_id', p_user), jsonb_build_object('assignee_id', p_reassign_to, 'motivo', 'membro removido'));
    if p_reassign_to is not null then
      perform public._notify(p_reassign_to, p_ws, 'task_assigned', 'task', t.id::text, 'Tarefa passada para ti: ' || t.title, null, 'reassign:' || t.id || ':' || p_reassign_to);
    end if;
    n := n + 1;
  end loop;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select organization_id from clients where id = p_ws), p_ws, 'member.removed', 'member', p_user::text,
          jsonb_build_object('role', a.workspace_role, 'status', a.status, 'affiliation', a.affiliation_type),
          jsonb_build_object('status', 'removed', 'tasks_reassigned', n, 'reassigned_to', p_reassign_to));
  return jsonb_build_object('user_id', p_user, 'status', 'removed', 'tasks_reassigned', n);
end $$;

-- o dono da agência atribui staff da agência que já existe a um cliente, sem convite por email
create or replace function public.agency_staff_assign(p_ws text, p_user uuid, p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients; prev workspace_access;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select * into c from clients where id = p_ws and status = 'active';
  if c.id is null or not public.is_agency_owner(uid) or not public._org_can('workspaces.read', c.organization_id, uid) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if public.ws_role_rank(p_role) = 0 then raise exception 'papel_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from agency_memberships where organization_id = c.organization_id and user_id = p_user and status = 'active') then
    raise exception 'nao_e_staff_da_agencia' using errcode = '22023';
  end if;
  select * into prev from workspace_access where workspace_id = p_ws and user_id = p_user;
  if prev.user_id is not null and prev.affiliation_type = 'client_staff' then raise exception 'ja_e_equipa_do_cliente' using errcode = '22023'; end if;
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, created_by)
  values (p_ws, p_user, 'agency_staff', p_role, uid)
  on conflict (workspace_id, user_id) do update set workspace_role = excluded.workspace_role, status = 'active', updated_at = now();
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', c.organization_id, p_ws, 'member.assigned', 'member', p_user::text,
          case when prev.user_id is not null then jsonb_build_object('role', prev.workspace_role, 'status', prev.status) end,
          jsonb_build_object('role', p_role, 'status', 'active', 'affiliation', 'agency_staff'));
  return jsonb_build_object('user_id', p_user, 'role', p_role, 'status', 'active');
end $$;

-- equipa: removidos saem da lista; diz o que quem vê pode fazer
create or replace function public.workspace_team(p_ws text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); mine text; owner boolean := public.is_agency_owner(uid); v_org uuid;
begin
  if not public._authorize('team.read', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select workspace_role into mine from workspace_access where workspace_id = p_ws and user_id = uid and status = 'active';
  select organization_id into v_org from clients where id = p_ws;
  return jsonb_build_object(
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', a.user_id, 'email', u.email, 'affiliation', a.affiliation_type,
                  'role', a.workspace_role, 'job_title', a.job_title, 'status', a.status, 'expires_at', a.expires_at, 'since', a.created_at,
                  'open_tasks', (select count(*) from tasks t where t.workspace_id = p_ws and t.assignee_id = a.user_id and t.status not in ('done','cancelled')),
                  'can_manage', public._authorize('team.manage', p_ws, uid) and a.user_id <> uid
                                and (owner or (a.affiliation_type = 'client_staff' and public.ws_role_rank(a.workspace_role) <= public.ws_role_rank(mine))))
                  order by a.affiliation_type, u.email), '[]')
                from workspace_access a join auth.users u on u.id = a.user_id where a.workspace_id = p_ws and a.status <> 'removed'),
    'invitations', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'affiliation', i.invited_as,
                  'role', i.workspace_role, 'expires_at', i.expires_at, 'created_at', i.created_at) order by i.created_at desc), '[]')
                from invitations i where i.workspace_id = p_ws and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()),
    'can_invite', public._authorize('team.invite', p_ws, uid),
    'can_invite_agency', owner,
    'can_manage', public._authorize('team.manage', p_ws, uid),
    'my_rank', case when owner then 99 else public.ws_role_rank(mine) end,
    'agency_staff', case when owner then (select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', u.email, 'role', m.agency_role) order by u.email), '[]')
                    from agency_memberships m join auth.users u on u.id = m.user_id
                   where m.organization_id = v_org and m.status = 'active' and m.user_id <> uid
                     and not exists (select 1 from workspace_access a where a.workspace_id = p_ws and a.user_id = m.user_id and a.status = 'active')) end);
end $$;

-- voltar a convidar quem foi removido reativa o acesso com o papel do convite
create or replace function public.accept_invitations()
returns integer language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_email text; v_conf timestamptz; inv record; n int := 0;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select email, email_confirmed_at into v_email, v_conf from auth.users where id = uid;
  if v_conf is null then return 0; end if;               -- só emails confirmados
  for inv in select * from invitations where lower(email) = lower(v_email) and accepted_at is null and revoked_at is null and expires_at > now() for update loop
    if inv.workspace_id is null then
      insert into agency_memberships (organization_id, user_id, agency_role, created_by)
      values (inv.organization_id, uid, inv.agency_role, inv.created_by)
      on conflict (organization_id, user_id) do nothing;
    else
      if inv.invited_as = 'agency_staff' then
        insert into agency_memberships (organization_id, user_id, agency_role, created_by)
        values (inv.organization_id, uid, 'agency_member', inv.created_by) on conflict do nothing;
      end if;
      insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, created_by)
      values (inv.workspace_id, uid, inv.invited_as, inv.workspace_role, inv.created_by)
      on conflict (workspace_id, user_id) do update set status = 'active', workspace_role = excluded.workspace_role,
        affiliation_type = excluded.affiliation_type, updated_at = now()
        where workspace_access.status = 'removed';
    end if;
    update invitations set accepted_at = now(), accepted_by = uid where id = inv.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
    values (uid, 'user', v_email, inv.organization_id, inv.workspace_id, 'invitation.accepted', 'invitation', inv.id::text,
            jsonb_build_object('invited_as', inv.invited_as, 'agency_role', inv.agency_role, 'workspace_role', inv.workspace_role));
    n := n + 1;
  end loop;
  return n;
end $$;

-- o contexto passa a dizer o que a pessoa pode fazer na agência (para a navegação; o servidor decide sempre)
create or replace function public.my_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then return null; end if;
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'confirmed', u.email_confirmed_at is not null) from auth.users u where u.id = uid),
    'agency', (select jsonb_agg(jsonb_build_object('organization', o.slug, 'name', o.name, 'role', m.agency_role, 'status', m.status,
                 'capabilities', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from capabilities k
                                   where 'org' = any(k.scopes) and public._org_can(k.key, o.id, uid))))
               from agency_memberships m join organizations o on o.id = m.organization_id where m.user_id = uid),
    'workspaces', (select coalesce(jsonb_agg(w order by w->>'name'), '[]') from (
       select jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
              'role', coalesce(a.workspace_role, 'agency_owner'),
              'affiliation', coalesce(a.affiliation_type, 'agency_staff'),
              'capabilities', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from capabilities k where _authorize(k.key, c.id, uid))) w
       from clients c left join workspace_access a on a.workspace_id = c.id and a.user_id = uid and a.status = 'active' and (a.expires_at is null or a.expires_at > now())
       where c.status = 'active'
         and (a.user_id is not null or exists (select 1 from agency_memberships m where m.user_id = uid and m.organization_id = c.organization_id and m.agency_role = 'agency_owner' and m.status = 'active'))
         and exists (select 1 from capabilities k where _authorize(k.key, c.id, uid))
    ) s)
  ) into res;
  return res;
end $$;

revoke all on function public._org_can(text,uuid,uuid), public._slug(text), public._ws_validate(text,text,text,text), public._member_guard(text,uuid,text),
  public._last_client_owner(text,uuid), public.workspace_create(text,text,text,text,text), public.workspace_update(text,jsonb),
  public.workspace_archive(text,text), public.workspace_restore(text), public.workspaces_list(), public.member_update(text,uuid,jsonb),
  public.member_remove(text,uuid,uuid), public.agency_staff_assign(text,uuid,text) from public, anon;
grant execute on function public.workspace_create(text,text,text,text,text), public.workspace_update(text,jsonb), public.workspace_archive(text,text),
  public.workspace_restore(text), public.workspaces_list(), public.member_update(text,uuid,jsonb), public.member_remove(text,uuid,uuid),
  public.agency_staff_assign(text,uuid,text) to authenticated;

/* Rollback:
drop function agency_staff_assign(text,uuid,text), member_remove(text,uuid,uuid), member_update(text,uuid,jsonb), _last_client_owner(text,uuid),
  _member_guard(text,uuid,text), workspaces_list(), workspace_restore(text), workspace_archive(text,text), workspace_update(text,jsonb),
  workspace_create(text,text,text,text,text), _ws_validate(text,text,text,text), _slug(text), _org_can(text,uuid,uuid);
-- workspace_team, accept_invitations e my_context: recriar as versões de 20261028185835 / 20261028185034
update capabilities set status = 'W1' where key in ('workspaces.read','workspaces.create','workspaces.archive','team.manage','settings.manage');
-- só depois de não haver linhas 'removed': alter table workspace_access drop constraint workspace_access_status_check, add check (status in ('active','suspended'));
*/
