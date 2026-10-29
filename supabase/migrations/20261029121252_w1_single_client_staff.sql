-- W1-11: PRD R-03, uma pessoa da equipa de um cliente pertence a um só cliente (ADR-0018).
-- Ao aceitar convites, um convite de equipa de cliente para quem já está ativo na equipa de outro cliente é cancelado
-- (sem erro para quem convidou, para não revelar que o email pertence a outro cliente) e fica no histórico (invitation.blocked).
-- O resto de accept_invitations fica igual. Rollback: recriar accept_invitations de 20261029100534_w1_clients_team.

create or replace function public.accept_invitations() returns integer
language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid := auth.uid(); v_email text; v_conf timestamptz; inv record; n int := 0;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select email, email_confirmed_at into v_email, v_conf from auth.users where id = uid;
  if v_conf is null then return 0; end if;  -- só emails confirmados
  for inv in select * from invitations where lower(email) = lower(v_email) and accepted_at is null and revoked_at is null and expires_at > now() for update loop
    -- PRD R-03: uma pessoa da equipa de um cliente pertence a um só cliente. O convite para outro cliente é cancelado
    -- sem erro para quem convidou (não revela que o email pertence a outro cliente) e fica no histórico.
    if inv.workspace_id is not null and inv.invited_as = 'client_staff' and exists (
         select 1 from workspace_access a join clients c on c.id = a.workspace_id
          where a.user_id = uid and a.status = 'active' and a.affiliation_type = 'client_staff'
            and a.workspace_id <> inv.workspace_id and c.status = 'active') then
      update invitations set revoked_at = now() where id = inv.id;
      insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
      values (null, 'system', 'cliente único', inv.organization_id, inv.workspace_id, 'invitation.blocked', 'invitation', inv.id::text,
              jsonb_build_object('motivo', 'pessoa já pertence à equipa de outro cliente'));
      continue;
    end if;
    if inv.workspace_id is null then
      insert into agency_memberships (organization_id, user_id, agency_role, created_by)
      values (inv.organization_id, uid, inv.agency_role, inv.created_by) on conflict (organization_id, user_id) do nothing;
    else
      if inv.invited_as = 'agency_staff' then
        insert into agency_memberships (organization_id, user_id, agency_role, created_by)
        values (inv.organization_id, uid, 'agency_member', inv.created_by) on conflict do nothing;
      end if;
      insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, created_by)
      values (inv.workspace_id, uid, inv.invited_as, inv.workspace_role, inv.created_by)
      on conflict (workspace_id, user_id) do update set status = 'active', workspace_role = excluded.workspace_role,
        affiliation_type = excluded.affiliation_type, updated_at = now() where workspace_access.status = 'removed';
    end if;
    update invitations set accepted_at = now(), accepted_by = uid where id = inv.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
    values (uid, 'user', v_email, inv.organization_id, inv.workspace_id, 'invitation.accepted', 'invitation', inv.id::text,
            jsonb_build_object('invited_as', inv.invited_as, 'agency_role', inv.agency_role, 'workspace_role', inv.workspace_role));
    n := n + 1;
  end loop;
  return n;
end $function$;
