-- W0 · MIG-09 / CAP-09: interruptores de funcionalidades por cliente. Um módulo novo entra desligado ou só para o dono
-- da agência e é ligado cliente a cliente. Disponibilidade não é autorização: uma flag ligada não dá acesso a nada, as
-- capacidades continuam a decidir (CAP-09). Expand: capacidade, duas tabelas e funções novas. Rollback no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('flags.manage', 'Agência', 'A', array['org'], 'ativo', 'Ligar e desligar funcionalidades em teste')
on conflict (key) do update set status = 'ativo', label = excluded.label;
insert into role_capabilities (scope, role, capability) values ('org', 'agency_owner', 'flags.manage') on conflict do nothing;

-- Registo das flags (uma por módulo novo). stage: off (ninguém), owner (só donos da agência), agency (equipa da agência
-- com acesso ao cliente), all (todos os que têm acesso).
create table if not exists public.feature_flag_defs (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  label text not null,
  module text not null,
  scope text not null default 'ws' check (scope in ('ws', 'org')),
  default_stage text not null default 'owner' check (default_stage in ('off', 'owner', 'agency', 'all')),
  description text,
  created_at timestamptz not null default now()
);
-- Exceções: por cliente (workspace_id) ou para a agência inteira (workspace_id nulo).
create table if not exists public.feature_flags (
  id bigint generated always as identity primary key,
  key text not null references public.feature_flag_defs(key),
  organization_id uuid not null references public.organizations(id),
  workspace_id text references public.clients(id),
  stage text not null check (stage in ('off', 'owner', 'agency', 'all')),
  updated_at timestamptz not null default now(),
  updated_by uuid
);
create unique index if not exists feature_flags_scope on public.feature_flags (key, organization_id, coalesce(workspace_id, ''));
alter table public.feature_flag_defs enable row level security;
alter table public.feature_flags enable row level security;
revoke all on public.feature_flag_defs, public.feature_flags from anon, authenticated;

create or replace function public._flag_stage(p_key text, p_org uuid, p_ws text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select stage from feature_flags where key = p_key and organization_id = p_org and workspace_id = p_ws),
    (select stage from feature_flags where key = p_key and organization_id = p_org and workspace_id is null),
    (select default_stage from feature_flag_defs where key = p_key),
    'off')
$$;

-- A flag está ligada para esta pessoa neste cliente (ou no espaço da agência, com p_ws nulo)?
create or replace function public._flag_on(p_key text, p_ws text, p_token text default null) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid; st text; role text;
begin
  if p_ws is not null then
    select organization_id into org from clients where id = p_ws;
  elsif uid is not null then
    select organization_id into org from agency_memberships where user_id = uid and status = 'active' order by created_at limit 1;
  end if;
  if org is null then return false; end if;
  st := public._flag_stage(p_key, org, p_ws);
  if st = 'off' then return false; end if;
  if st = 'all' then return true; end if;
  if uid is null then return false; end if;                 -- código de equipa: só o que está para todos
  select agency_role into role from agency_memberships where user_id = uid and organization_id = org and status = 'active';
  if role is null then return false; end if;
  return st = 'agency' or role = 'agency_owner';
end $$;

create or replace function public.my_flags(p_ws text default null, p_token text default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
begin
  -- não revela flags de um cliente a quem não tem acesso a ele
  if p_ws is not null and not (public.ws_can('scripts.read', p_ws, p_token) or public.ws_can('team.read', p_ws, p_token)) then return '{}'; end if;
  return coalesce((select array_agg(key order by key) from feature_flag_defs d
                    where (p_ws is null) = (d.scope = 'org') and public._flag_on(d.key, p_ws, p_token)), '{}');
end $$;

create or replace function public.flags_admin() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := (select organization_id from agency_memberships where user_id = auth.uid() and status = 'active' order by created_at limit 1);
begin
  if org is null or not public._org_can('flags.manage', org) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'flags', coalesce((select jsonb_agg(jsonb_build_object('key', d.key, 'label', d.label, 'module', d.module, 'scope', d.scope,
               'default_stage', d.default_stage, 'description', d.description,
               'agency_stage', (select stage from feature_flags f where f.key = d.key and f.organization_id = org and f.workspace_id is null),
               'clients', coalesce((select jsonb_object_agg(f.workspace_id, f.stage) from feature_flags f
                                     where f.key = d.key and f.organization_id = org and f.workspace_id is not null), '{}'))
               order by d.module, d.key) from feature_flag_defs d), '[]'),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
                          from clients c where c.organization_id = org and coalesce(c.status, 'active') <> 'archived'), '[]'));
end $$;

-- Mudar a fase de uma flag para a agência (p_ws nulo) ou para um cliente; p_stage nulo apaga a exceção.
create or replace function public.flag_set(p_key text, p_ws text, p_stage text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := (select organization_id from agency_memberships where user_id = auth.uid() and status = 'active' order by created_at limit 1);
        d feature_flag_defs; before text;
begin
  if org is null or not public._org_can('flags.manage', org) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into d from feature_flag_defs where key = p_key;
  if d.key is null then raise exception 'flag_desconhecida' using errcode = 'P0002'; end if;
  if p_stage is not null and p_stage not in ('off', 'owner', 'agency', 'all') then raise exception 'fase_invalida' using errcode = '22023'; end if;
  if p_ws is not null and not exists (select 1 from clients where id = p_ws and organization_id = org) then
    raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  if p_ws is not null and d.scope = 'org' then raise exception 'flag_da_agencia' using errcode = '22023', detail = 'Esta funcionalidade é do espaço da agência.'; end if;
  select stage into before from feature_flags where key = p_key and organization_id = org and workspace_id is not distinct from p_ws;
  delete from feature_flags where key = p_key and organization_id = org and workspace_id is not distinct from p_ws;
  if p_stage is not null then
    insert into feature_flags (key, organization_id, workspace_id, stage, updated_by) values (p_key, org, p_ws, p_stage, auth.uid());
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (auth.uid(), 'user', (select email from auth.users where id = auth.uid()), org, p_ws, 'flag.set', 'feature_flag', p_key,
          jsonb_build_object('stage', before), jsonb_build_object('stage', p_stage));
  return public.flags_admin();
end $$;

revoke all on function public._flag_stage(text, uuid, text), public._flag_on(text, text, text) from public, anon, authenticated;
revoke all on function public.my_flags(text, text), public.flags_admin(), public.flag_set(text, text, text) from public;
grant execute on function public.my_flags(text, text) to anon, authenticated;
grant execute on function public.flags_admin(), public.flag_set(text, text, text) to authenticated;

/* Rollback (compatível): drop function public.flag_set(text, text, text), public.flags_admin(), public.my_flags(text, text),
   public._flag_on(text, text, text), public._flag_stage(text, uuid, text);
   delete from role_capabilities where capability = 'flags.manage';
-- contract posterior: drop table public.feature_flags, public.feature_flag_defs; */
