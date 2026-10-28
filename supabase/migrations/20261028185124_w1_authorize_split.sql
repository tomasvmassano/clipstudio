-- 20261028185124 w1_authorize_split
-- authorize(cap, ws) pública usa sempre auth.uid(); a versão com uid é interna (sem EXECUTE para a API).
alter function public.authorize(text, text, uuid) rename to _authorize;
revoke all on function public._authorize(text, text, uuid) from public, anon, authenticated;
drop function if exists public.can(text, text);

create or replace function public.authorize(p_cap text, p_ws text default null) returns boolean
language sql stable security definer set search_path = public as $$ select public._authorize(p_cap, p_ws, auth.uid()); $$;
revoke all on function public.authorize(text, text) from public, anon;
grant execute on function public.authorize(text, text) to authenticated;

-- my_context, accept/invite passam a usar a interna
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

create or replace function public.invite_member(p_ws text, p_email text, p_role text, p_affiliation text default 'client_staff') returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; my_role text; my_aff text; v_id uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'email_invalido' using errcode = '22023'; end if;
  select organization_id into v_org from clients where id = p_ws and status = 'active';
  if v_org is null or not _authorize('team.invite', p_ws, uid) then
    insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, result) values (uid, 'user', p_ws, 'invitation.create', 'invitation', 'denied');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_affiliation not in ('agency_staff','client_staff') or ws_role_rank(p_role) = 0 then raise exception 'papel_invalido' using errcode = '22023'; end if;
  select workspace_role, affiliation_type into my_role, my_aff from workspace_access where user_id = uid and workspace_id = p_ws and status = 'active';
  if not is_agency_owner(uid) then
    if my_aff = 'client_staff' and p_affiliation = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    if ws_role_rank(p_role) > ws_role_rank(my_role) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end if;
  insert into invitations (organization_id, workspace_id, email, invited_as, workspace_role, created_by)
  values (v_org, p_ws, lower(p_email), p_affiliation, p_role, uid) returning id into v_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', v_org, p_ws, 'invitation.create', 'invitation', v_id::text, jsonb_build_object('email', lower(p_email), 'role', p_role, 'affiliation', p_affiliation));
  return v_id;
end $$;
