-- 20261028185034 w1_identity_core
-- W1-01 núcleo de identidade e autorização (ADR-0001). Aditiva: não altera acessos existentes.
-- Rollback: drop das tabelas/funções criadas aqui (nenhum dado existente é alterado exceto colunas novas em clients).

create extension if not exists citext;

-- organização da agência
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name text not null,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now()
);
insert into public.organizations (slug, name) values ('clipstudio', 'ClipStudio');

-- clients = workspaces (ADR-0001 §2)
alter table public.clients
  add column if not exists organization_id uuid references public.organizations(id),
  add column if not exists timezone text not null default 'Asia/Dubai',
  add column if not exists currency text not null default 'EUR',
  add column if not exists status text not null default 'active';
alter table public.clients add constraint clients_status_chk check (status in ('active','archived'));
update public.clients set organization_id = (select id from public.organizations where slug = 'clipstudio') where organization_id is null;
alter table public.clients alter column organization_id set not null;

-- catálogo de capacidades (docs/feature-registry.md)
create table public.capabilities (
  key text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  module text not null,
  risk text not null check (risk in ('B','M','A')),
  scopes text[] not null,
  status text not null
);
insert into public.capabilities (key, module, risk, scopes, status) values
 ('workspaces.read','Agência','B','{org}','W1'),('workspaces.create','Agência','A','{org}','W1'),('workspaces.archive','Agência','A','{org}','W1'),
 ('team.read','Equipa','B','{org,ws}','W1'),('team.invite','Equipa','A','{org,ws}','W1'),('team.manage','Equipa','A','{org,ws}','W1'),
 ('permissions.manage','CAP','A','{org,ws}','W1'),('audit.read','CAP','M','{org,ws}','W1'),
 ('scripts.read','Guiões','B','{ws,proj,own}','legado'),('scripts.create','Guiões','M','{ws,proj}','W2'),('scripts.edit','Guiões','M','{ws,proj,own}','legado'),
 ('scripts.submit','Guiões','M','{ws,proj,own}','W2'),('scripts.approve','Guiões','A','{ws,proj}','legado'),('scripts.reject','Guiões','M','{ws,proj}','legado'),
 ('scripts.delete','Guiões','A','{ws}','W2'),('scripts.export','Guiões','M','{ws}','legado'),
 ('recording.use','Teleprompter','B','{ws,own}','legado'),('recording.confirm','Teleprompter','M','{ws,own}','legado'),
 ('sources.read','Fontes','B','{ws}','legado'),('sources.create','Fontes','M','{ws}','W2'),('sources.triage','Fontes','M','{ws}','W2'),
 ('references.read','Referências','B','{org,ws}','W2'),('references.manage','Referências','M','{org,ws}','W2'),
 ('review.comment','Revisão','M','{ws,proj}','W5'),('review.approve','Revisão','A','{ws,proj}','W5'),
 ('media.upload','Biblioteca','M','{ws,proj}','W5'),('media.download','Biblioteca','M','{ws,proj}','W5'),('media.share','Biblioteca','A','{ws,proj}','W5'),
 ('clipping.create','Clipping','M','{ws,proj}','W5'),('clipping.export','Clipping','M','{ws,proj}','W5'),
 ('tasks.read','Calendário','B','{ws,proj,own}','W3'),('tasks.manage','Calendário','M','{ws,proj}','W3'),
 ('publishing.schedule','Publicação','A','{ws}','W6'),('publishing.publish','Publicação','A','{ws}','W6'),('social_accounts.manage','Publicação','A','{ws}','W6'),
 ('analytics.read','Desempenho','B','{ws}','legado'),('costs.read','Custos','M','{ws}','W4'),('costs.read_agency','Custos','A','{org}','W4'),
 ('agents.read','Agentes','B','{ws}','legado'),('agents.rehearse','Agentes','M','{ws}','legado'),('agents.run','Agentes','A','{ws}','W4'),('agents.configure','Agentes','A','{ws}','W4'),
 ('integrations.manage','Settings','A','{ws}','W6'),('settings.manage','Settings','A','{ws}','W1');

-- papéis -> capacidades por defeito (docs/access-matrix.md)
create table public.role_capabilities (
  scope text not null check (scope in ('org','ws')),
  role text not null,
  capability text not null references public.capabilities(key),
  primary key (scope, role, capability)
);
insert into public.role_capabilities (scope, role, capability)
select 'org', r, c from (values
  ('agency_owner'), ('agency_admin')) roles(r),
  (values ('workspaces.read'),('team.read'),('audit.read')) caps(c)
union all select 'org','agency_owner', c from (values ('workspaces.create'),('workspaces.archive'),('team.invite'),('team.manage'),('permissions.manage'),('costs.read_agency')) x(c);

insert into public.role_capabilities (scope, role, capability)
select 'ws', r.role, r.cap from (values
 -- workspace_owner: tudo o que existe no âmbito ws
 ('workspace_owner','scripts.read'),('workspace_owner','scripts.create'),('workspace_owner','scripts.edit'),('workspace_owner','scripts.submit'),('workspace_owner','scripts.approve'),('workspace_owner','scripts.reject'),('workspace_owner','scripts.delete'),('workspace_owner','scripts.export'),
 ('workspace_owner','recording.use'),('workspace_owner','recording.confirm'),('workspace_owner','sources.read'),('workspace_owner','sources.create'),('workspace_owner','sources.triage'),('workspace_owner','references.read'),('workspace_owner','references.manage'),
 ('workspace_owner','review.comment'),('workspace_owner','review.approve'),('workspace_owner','media.upload'),('workspace_owner','media.download'),('workspace_owner','media.share'),('workspace_owner','clipping.create'),('workspace_owner','clipping.export'),
 ('workspace_owner','tasks.read'),('workspace_owner','tasks.manage'),('workspace_owner','publishing.schedule'),('workspace_owner','publishing.publish'),('workspace_owner','social_accounts.manage'),('workspace_owner','analytics.read'),('workspace_owner','costs.read'),
 ('workspace_owner','agents.read'),('workspace_owner','agents.rehearse'),('workspace_owner','agents.run'),('workspace_owner','agents.configure'),('workspace_owner','integrations.manage'),('workspace_owner','settings.manage'),
 ('workspace_owner','team.read'),('workspace_owner','team.invite'),('workspace_owner','team.manage'),('workspace_owner','permissions.manage'),('workspace_owner','audit.read'),
 -- workspace_admin: como owner, sem apagar guiões
 ('workspace_admin','scripts.read'),('workspace_admin','scripts.create'),('workspace_admin','scripts.edit'),('workspace_admin','scripts.submit'),('workspace_admin','scripts.approve'),('workspace_admin','scripts.reject'),('workspace_admin','scripts.delete'),('workspace_admin','scripts.export'),
 ('workspace_admin','recording.use'),('workspace_admin','recording.confirm'),('workspace_admin','sources.read'),('workspace_admin','sources.create'),('workspace_admin','sources.triage'),('workspace_admin','references.read'),('workspace_admin','references.manage'),
 ('workspace_admin','review.comment'),('workspace_admin','review.approve'),('workspace_admin','media.upload'),('workspace_admin','media.download'),('workspace_admin','media.share'),('workspace_admin','clipping.create'),('workspace_admin','clipping.export'),
 ('workspace_admin','tasks.read'),('workspace_admin','tasks.manage'),('workspace_admin','publishing.schedule'),('workspace_admin','publishing.publish'),('workspace_admin','social_accounts.manage'),('workspace_admin','analytics.read'),('workspace_admin','costs.read'),
 ('workspace_admin','agents.read'),('workspace_admin','agents.rehearse'),('workspace_admin','agents.run'),('workspace_admin','agents.configure'),('workspace_admin','integrations.manage'),('workspace_admin','settings.manage'),
 ('workspace_admin','team.read'),('workspace_admin','team.invite'),('workspace_admin','team.manage'),('workspace_admin','permissions.manage'),('workspace_admin','audit.read'),
 -- manager
 ('manager','scripts.read'),('manager','scripts.create'),('manager','scripts.edit'),('manager','scripts.submit'),('manager','scripts.approve'),('manager','scripts.reject'),('manager','scripts.export'),
 ('manager','recording.use'),('manager','recording.confirm'),('manager','sources.read'),('manager','sources.create'),('manager','sources.triage'),('manager','references.read'),('manager','references.manage'),
 ('manager','review.comment'),('manager','review.approve'),('manager','media.upload'),('manager','media.download'),('manager','media.share'),('manager','clipping.create'),('manager','clipping.export'),
 ('manager','tasks.read'),('manager','tasks.manage'),('manager','analytics.read'),('manager','agents.read'),('manager','agents.rehearse'),('manager','agents.run'),('manager','team.read'),
 -- contributor
 ('contributor','scripts.read'),('contributor','scripts.create'),('contributor','scripts.edit'),('contributor','scripts.submit'),('contributor','scripts.export'),
 ('contributor','recording.use'),('contributor','recording.confirm'),('contributor','sources.read'),('contributor','sources.create'),('contributor','sources.triage'),('contributor','references.read'),
 ('contributor','review.comment'),('contributor','media.upload'),('contributor','media.download'),('contributor','clipping.create'),('contributor','clipping.export'),
 ('contributor','tasks.read'),('contributor','analytics.read'),('contributor','agents.read'),('contributor','team.read'),
 -- reviewer
 ('reviewer','scripts.read'),('reviewer','scripts.approve'),('reviewer','scripts.reject'),('reviewer','scripts.export'),('reviewer','sources.read'),('reviewer','references.read'),
 ('reviewer','review.comment'),('reviewer','review.approve'),('reviewer','media.download'),('reviewer','tasks.read'),('reviewer','analytics.read'),('reviewer','agents.read'),('reviewer','team.read'),
 -- viewer
 ('viewer','scripts.read'),('viewer','sources.read'),('viewer','analytics.read'),('viewer','agents.read'),('viewer','tasks.read')
) r(role, cap);

-- membros da agência
create table public.agency_memberships (
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_role text not null check (agency_role in ('agency_owner','agency_admin','agency_manager','agency_member')),
  status text not null default 'active' check (status in ('active','suspended')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

-- acesso a workspaces (staff da agência atribuído ou equipa do cliente)
create table public.workspace_access (
  workspace_id text not null references public.clients(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  affiliation_type text not null check (affiliation_type in ('agency_staff','client_staff')),
  workspace_role text not null check (workspace_role in ('workspace_owner','workspace_admin','manager','contributor','reviewer','viewer')),
  job_title text,
  status text not null default 'active' check (status in ('active','suspended')),
  expires_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index workspace_access_user on public.workspace_access(user_id);

-- grants e negações explícitas (CAP-03)
create table public.permission_grants (
  id bigserial primary key,
  workspace_id text not null references public.clients(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  capability text not null references public.capabilities(key),
  effect text not null check (effect in ('allow','deny')),
  expires_at timestamptz,
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index permission_grants_lookup on public.permission_grants(user_id, workspace_id, capability);

-- convites
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  workspace_id text references public.clients(id),
  email citext not null,
  invited_as text not null check (invited_as in ('agency_staff','client_staff')),
  agency_role text check (agency_role in ('agency_owner','agency_admin','agency_manager','agency_member')),
  workspace_role text check (workspace_role in ('workspace_owner','workspace_admin','manager','contributor','reviewer','viewer')),
  expires_at timestamptz not null default now() + interval '14 days',
  accepted_at timestamptz, accepted_by uuid references auth.users(id),
  revoked_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check ((workspace_id is null and agency_role is not null) or (workspace_id is not null and workspace_role is not null)),
  check (not (invited_as = 'client_staff' and agency_role is not null))
);
create index invitations_email on public.invitations(email) where accepted_at is null and revoked_at is null;

-- auditoria append-only (R-05)
create table public.audit_events (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor_user_id uuid,
  actor_kind text not null check (actor_kind in ('user','legacy_code','system')),
  actor_label text,
  organization_id uuid,
  workspace_id text,
  action text not null,
  entity_type text,
  entity_id text,
  before jsonb,
  after jsonb,
  result text not null default 'ok' check (result in ('ok','denied','error')),
  correlation_id text
);
create index audit_events_ws_at on public.audit_events(workspace_id, at desc);
create or replace function public.audit_events_immutable() returns trigger language plpgsql as $$
begin raise exception 'audit_events é append-only'; end $$;
create trigger audit_events_no_update before update or delete on public.audit_events
  for each row execute function public.audit_events_immutable();

-- RLS: tudo fechado; leitura só pelas RPCs/políticas abaixo
alter table public.organizations enable row level security;
alter table public.capabilities enable row level security;
alter table public.role_capabilities enable row level security;
alter table public.agency_memberships enable row level security;
alter table public.workspace_access enable row level security;
alter table public.permission_grants enable row level security;
alter table public.invitations enable row level security;
alter table public.audit_events enable row level security;
revoke all on public.organizations, public.capabilities, public.role_capabilities, public.agency_memberships,
  public.workspace_access, public.permission_grants, public.invitations, public.audit_events from anon, authenticated;
revoke all on sequence public.permission_grants_id_seq, public.audit_events_id_seq from anon, authenticated;

-- ===== avaliação central =====
create or replace function public.is_agency_owner(p_uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from agency_memberships m join organizations o on o.id = m.organization_id
                 where m.user_id = p_uid and m.agency_role = 'agency_owner' and m.status = 'active' and o.status = 'active');
$$;

-- authorize(cap, workspace): PRD §3. Workspace null = âmbito da organização.
create or replace function public.authorize(p_cap text, p_ws text default null, p_uid uuid default auth.uid()) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_role text; v_org uuid;
begin
  if p_uid is null then return false; end if;
  if not exists (select 1 from capabilities where key = p_cap) then return false; end if;   -- desconhecida = negado
  if p_ws is null then
    return exists (select 1 from agency_memberships m join role_capabilities rc on rc.scope = 'org' and rc.role = m.agency_role and rc.capability = p_cap
                   where m.user_id = p_uid and m.status = 'active');
  end if;
  select organization_id into v_org from clients where id = p_ws and status = 'active';
  if v_org is null then return false; end if;
  -- negação explícita prevalece (CAP-03)
  if exists (select 1 from permission_grants g where g.user_id = p_uid and g.workspace_id = p_ws and g.capability = p_cap
             and g.effect = 'deny' and (g.expires_at is null or g.expires_at > now())) then return false; end if;
  -- agency owner: acesso global à sua organização (auditado nas escritas)
  if exists (select 1 from agency_memberships m where m.user_id = p_uid and m.organization_id = v_org
             and m.agency_role = 'agency_owner' and m.status = 'active') then return true; end if;
  select a.workspace_role into v_role from workspace_access a
   where a.user_id = p_uid and a.workspace_id = p_ws and a.status = 'active' and (a.expires_at is null or a.expires_at > now());
  if v_role is null then return false; end if;
  -- staff da agência suspenso na organização perde acesso aos clientes
  if exists (select 1 from workspace_access a join agency_memberships m on m.user_id = a.user_id and m.organization_id = v_org
             where a.user_id = p_uid and a.workspace_id = p_ws and a.affiliation_type = 'agency_staff' and m.status <> 'active') then return false; end if;
  return exists (select 1 from role_capabilities where scope = 'ws' and role = v_role and capability = p_cap)
      or exists (select 1 from permission_grants g where g.user_id = p_uid and g.workspace_id = p_ws and g.capability = p_cap
                 and g.effect = 'allow' and (g.expires_at is null or g.expires_at > now()));
end $$;
revoke all on function public.authorize(text, text, uuid) from public, anon;
grant execute on function public.authorize(text, text, uuid) to authenticated;
revoke all on function public.is_agency_owner(uuid) from public, anon;

-- o p_uid só pode ser o próprio quando chamado pela API
create or replace function public.can(p_cap text, p_ws text default null) returns boolean
language sql stable security invoker set search_path = public as $$ select public.authorize(p_cap, p_ws, auth.uid()); $$;
revoke execute on function public.authorize(text, text, uuid) from authenticated;
grant execute on function public.can(text, text) to authenticated;

-- ===== contexto do utilizador =====
create or replace function public.my_context() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then return null; end if;
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'confirmed', u.email_confirmed_at is not null) from auth.users u where u.id = uid),
    'agency', (select jsonb_agg(jsonb_build_object('organization', o.slug, 'name', o.name, 'role', m.agency_role, 'status', m.status))
               from agency_memberships m join organizations o on o.id = m.organization_id where m.user_id = uid),
    'workspaces', (select coalesce(jsonb_agg(w order by w->>'name'), '[]') from (
       select jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
              'role', coalesce(a.workspace_role, case when is_agency_owner(uid) then 'agency_owner' end),
              'affiliation', coalesce(a.affiliation_type, 'agency_staff'),
              'capabilities', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from capabilities k where authorize(k.key, c.id, uid))) w
       from clients c left join workspace_access a on a.workspace_id = c.id and a.user_id = uid and a.status = 'active' and (a.expires_at is null or a.expires_at > now())
       where c.status = 'active' and (a.user_id is not null or exists (select 1 from agency_memberships m where m.user_id = uid and m.organization_id = c.organization_id and m.agency_role = 'agency_owner' and m.status = 'active'))
    ) s)
  ) into res;
  return res;
end $$;
revoke all on function public.my_context() from public, anon;
grant execute on function public.my_context() to authenticated;

-- ===== convites =====
create or replace function public.accept_invitations() returns integer
language plpgsql security definer set search_path = public as $$
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
      on conflict (workspace_id, user_id) do nothing;
    end if;
    update invitations set accepted_at = now(), accepted_by = uid where id = inv.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
    values (uid, 'user', v_email, inv.organization_id, inv.workspace_id, 'invitation.accepted', 'invitation', inv.id::text,
            jsonb_build_object('invited_as', inv.invited_as, 'agency_role', inv.agency_role, 'workspace_role', inv.workspace_role));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.accept_invitations() from public, anon;
grant execute on function public.accept_invitations() to authenticated;

-- ordem dos papéis para o teto de autoridade (R-12)
create or replace function public.ws_role_rank(p_role text) returns int language sql immutable as $$
  select case p_role when 'workspace_owner' then 6 when 'workspace_admin' then 5 when 'manager' then 4
                     when 'contributor' then 3 when 'reviewer' then 2 when 'viewer' then 1 else 0 end;
$$;

create or replace function public.invite_member(p_ws text, p_email text, p_role text, p_affiliation text default 'client_staff') returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; my_role text; my_aff text; v_id uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'email_invalido' using errcode = '22023'; end if;
  select organization_id into v_org from clients where id = p_ws and status = 'active';
  if v_org is null or not authorize('team.invite', p_ws, uid) then
    insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, result) values (uid, 'user', p_ws, 'invitation.create', 'invitation', 'denied');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_affiliation not in ('agency_staff','client_staff') or ws_role_rank(p_role) = 0 then raise exception 'papel_invalido' using errcode = '22023'; end if;
  select workspace_role, affiliation_type into my_role, my_aff from workspace_access where user_id = uid and workspace_id = p_ws and status = 'active';
  if not is_agency_owner(uid) then
    -- staff do cliente nunca convida staff da agência (TEAM-02); ninguém convida acima de si (R-12)
    if my_aff = 'client_staff' and p_affiliation = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    if ws_role_rank(p_role) > ws_role_rank(my_role) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end if;
  insert into invitations (organization_id, workspace_id, email, invited_as, workspace_role, created_by)
  values (v_org, p_ws, lower(p_email), p_affiliation, p_role, uid) returning id into v_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', v_org, p_ws, 'invitation.create', 'invitation', v_id::text, jsonb_build_object('email', lower(p_email), 'role', p_role, 'affiliation', p_affiliation));
  return v_id;
end $$;
revoke all on function public.invite_member(text, text, text, text) from public, anon;
grant execute on function public.invite_member(text, text, text, text) to authenticated;

-- bootstrap: o owner da agência é o Tomás (ADR-0001); o convite é aceite quando ele entrar com este email confirmado
insert into public.invitations (organization_id, email, invited_as, agency_role)
select id, 'tomas@informallabs.com', 'agency_staff', 'agency_owner' from public.organizations where slug = 'clipstudio';

-- referências isoladas por cliente (ADR-0001 §5): as contas de referência pertencem ao workspace numeiro
update public.accounts set client_id = 'numeiro' where role = 'reference' and client_id is null;

-- ideias ganham workspace (MIG-06)
alter table public.ideas add column if not exists client_id text references public.clients(id);
update public.ideas set client_id = 'numeiro' where client_id is null;
alter table public.ideas alter column client_id set not null;
alter table public.ideas alter column client_id set default 'numeiro';
