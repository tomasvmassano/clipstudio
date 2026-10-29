-- W1-13: Equipa da agência (espaço da agência; PRD §2, §3, M13, R-13, R-14; ADR-0020).
-- Ler: team.read de agência (dono e admin). Convidar e gerir: team.invite e team.manage de agência (dono).
-- Cada pessoa mostra só os clientes que quem vê também pode ver (nunca revela clientes fora do seu acesso).
-- Só aditiva. Rollback: bloco no fim.

create or replace function public._agency_org(p_cap text) returns uuid
language sql stable security definer set search_path = public as $$
  select m.organization_id from agency_memberships m
   where m.user_id = auth.uid() and m.status = 'active' and public._org_can(p_cap, m.organization_id, auth.uid()) limit 1
$$;
revoke execute on function public._agency_org(text) from public, anon, authenticated;

create or replace function public._viewer_sees(p_ws text, p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_agency_owner(p_uid) or exists (select 1 from workspace_access a where a.workspace_id = p_ws and a.user_id = p_uid
           and a.status = 'active' and (a.expires_at is null or a.expires_at > now()))
$$;
revoke execute on function public._viewer_sees(text, uuid) from public, anon, authenticated;

create or replace function public.agency_team() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  v_org := _agency_org('team.read');
  if v_org is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'me', uid,
    'can', jsonb_build_object('invite', _org_can('team.invite', v_org, uid), 'manage', _org_can('team.manage', v_org, uid)),
    'staff', (select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'email', u.email, 'agency_role', m.agency_role, 'status', m.status, 'since', m.created_at,
        'last_sign_in', u.last_sign_in_at,
        'clients', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'role', a.workspace_role, 'status', a.status,
                       'open_tasks', (select count(*) from tasks t where t.workspace_id = c.id and t.assignee_id = m.user_id and t.status in ('todo','doing','blocked')))
                       order by lower(c.name)), '[]')
                    from workspace_access a join clients c on c.id = a.workspace_id
                    where a.user_id = m.user_id and a.status = 'active' and a.affiliation_type = 'agency_staff' and c.status = 'active'
                      and c.organization_id = v_org and _viewer_sees(c.id, uid)),
        'open_tasks', (select count(*) from tasks t join clients c on c.id = t.workspace_id
                        where t.assignee_id = m.user_id and t.status in ('todo','doing','blocked') and c.status = 'active'
                          and c.organization_id = v_org and _viewer_sees(c.id, uid)))
        order by (m.status = 'active') desc, m.agency_role = 'agency_owner' desc, lower(u.email)), '[]')
      from agency_memberships m join auth.users u on u.id = m.user_id where m.organization_id = v_org),
    'clients', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by lower(c.name)), '[]')
                from clients c where c.organization_id = v_org and c.status = 'active' and _viewer_sees(c.id, uid)),
    'invites', case when _org_can('team.invite', v_org, uid) then
                (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'agency_role', i.agency_role, 'expires_at', i.expires_at,
                          'created_at', i.created_at) order by i.created_at desc), '[]')
                 from invitations i where i.organization_id = v_org and i.workspace_id is null
                   and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()) else '[]'::jsonb end);
end $$;
revoke execute on function public.agency_team() from public, anon;
grant execute on function public.agency_team() to authenticated;

create or replace function public.agency_invite(p_email text, p_role text) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; v_id uuid; e text := lower(btrim(p_email));
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  v_org := _agency_org('team.invite');
  if v_org is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if e !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'email_invalido' using errcode = '22023'; end if;
  if p_role not in ('agency_admin', 'agency_manager', 'agency_member') then raise exception 'papel_invalido' using errcode = '22023'; end if;
  if exists (select 1 from agency_memberships m join auth.users u on u.id = m.user_id where m.organization_id = v_org and lower(u.email) = e) then
    raise exception 'ja_e_staff' using errcode = 'PT409'; end if;
  -- R-14: quem é da equipa de um cliente não ganha acesso à agência (o dono vê todos os clientes: não revela nada)
  if exists (select 1 from workspace_access a join auth.users u on u.id = a.user_id join clients c on c.id = a.workspace_id
              where lower(u.email) = e and a.status = 'active' and a.affiliation_type = 'client_staff' and c.organization_id = v_org) then
    raise exception 'pessoa_e_equipa_de_cliente' using errcode = '22023'; end if;
  if exists (select 1 from invitations where organization_id = v_org and workspace_id is null and lower(email) = e
              and accepted_at is null and revoked_at is null and expires_at > now()) then
    raise exception 'convite_pendente' using errcode = 'PT409'; end if;
  insert into invitations (organization_id, workspace_id, email, invited_as, agency_role, created_by)
  values (v_org, null, e, 'agency_staff', p_role, uid) returning id into v_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, action, entity_type, entity_id, after)
  values (uid, 'user', v_org, 'agency.invitation.create', 'invitation', v_id::text, jsonb_build_object('email', e, 'agency_role', p_role));
  return v_id;
end $$;
revoke execute on function public.agency_invite(text, text) from public, anon;
grant execute on function public.agency_invite(text, text) to authenticated;

create or replace function public.agency_invite_revoke(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; inv invitations;
begin
  v_org := _agency_org('team.invite');
  select * into inv from invitations where id = p_id;
  if v_org is null or inv.id is null or inv.workspace_id is not null or inv.organization_id <> v_org then
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  update invitations set revoked_at = now() where id = p_id and accepted_at is null and revoked_at is null;
  insert into audit_events (actor_user_id, actor_kind, organization_id, action, entity_type, entity_id, before)
  values (uid, 'user', v_org, 'agency.invitation.revoked', 'invitation', p_id::text, jsonb_build_object('email', inv.email, 'agency_role', inv.agency_role));
end $$;
revoke execute on function public.agency_invite_revoke(uuid) from public, anon;
grant execute on function public.agency_invite_revoke(uuid) to authenticated;

-- mudar papel na agência ou suspender/reativar; suspender corta logo o acesso a todos os clientes (_authorize)
create or replace function public.agency_member_update(p_user uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_org uuid; m agency_memberships; r text := p_patch->>'agency_role'; st text := p_patch->>'status';
begin
  v_org := _agency_org('team.manage');
  if uid is null or v_org is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_user = uid then raise exception 'nao_a_si_proprio' using errcode = '42501'; end if;
  select * into m from agency_memberships where organization_id = v_org and user_id = p_user;
  if m.user_id is null then raise exception 'membro_nao_encontrado' using errcode = 'P0002'; end if;
  if m.agency_role = 'agency_owner' then raise exception 'dono_protegido' using errcode = '42501'; end if;
  if r is not null and r not in ('agency_admin', 'agency_manager', 'agency_member') then raise exception 'papel_invalido' using errcode = '22023'; end if;
  if st is not null and st not in ('active', 'suspended') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if coalesce(r, m.agency_role) = m.agency_role and coalesce(st, m.status) = m.status then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  update agency_memberships set agency_role = coalesce(r, agency_role), status = coalesce(st, status)
   where organization_id = v_org and user_id = p_user;
  insert into audit_events (actor_user_id, actor_kind, organization_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', v_org, 'agency.member.updated', 'member', p_user::text,
          jsonb_build_object('agency_role', m.agency_role, 'status', m.status),
          jsonb_build_object('agency_role', coalesce(r, m.agency_role), 'status', coalesce(st, m.status)));
  return jsonb_build_object('user_id', p_user, 'agency_role', coalesce(r, m.agency_role), 'status', coalesce(st, m.status));
end $$;
revoke execute on function public.agency_member_update(uuid, jsonb) from public, anon;
grant execute on function public.agency_member_update(uuid, jsonb) to authenticated;

/* Rollback:
drop function agency_member_update(uuid, jsonb); drop function agency_invite_revoke(uuid); drop function agency_invite(text, text);
drop function agency_team(); drop function _viewer_sees(text, uuid); drop function _agency_org(text);
*/
