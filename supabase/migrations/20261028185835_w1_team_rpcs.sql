-- W1: RPCs da página Equipa. Reconstruído a partir das definições em produção (pg_get_functiondef)
-- porque o corpo original aplicado não ficou no registo da sessão. Equivalente funcional.
-- Rollback: drop function public.workspace_team(text); drop function public.revoke_invitation(uuid);

create or replace function public.workspace_team(p_ws text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid();
begin
  if not _authorize('team.read', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', a.user_id, 'email', u.email, 'affiliation', a.affiliation_type,
                  'role', a.workspace_role, 'job_title', a.job_title, 'status', a.status, 'expires_at', a.expires_at, 'since', a.created_at)
                  order by a.affiliation_type, u.email), '[]')
                from workspace_access a join auth.users u on u.id = a.user_id where a.workspace_id = p_ws),
    'invitations', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'affiliation', i.invited_as,
                  'role', i.workspace_role, 'expires_at', i.expires_at, 'created_at', i.created_at) order by i.created_at desc), '[]')
                from invitations i where i.workspace_id = p_ws and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()),
    'can_invite', _authorize('team.invite', p_ws, uid),
    'can_invite_agency', is_agency_owner(uid));
end $function$;

create or replace function public.revoke_invitation(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); inv invitations;
begin
  select * into inv from invitations where id = p_id;
  if inv.id is null or inv.workspace_id is null or not _authorize('team.invite', inv.workspace_id, uid) then
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  update invitations set revoked_at = now() where id = p_id and accepted_at is null;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id)
  values (uid, 'user', inv.organization_id, inv.workspace_id, 'invitation.revoked', 'invitation', p_id::text);
end $function$;

revoke all on function public.workspace_team(text) from public, anon;
revoke all on function public.revoke_invitation(uuid) from public, anon;
grant execute on function public.workspace_team(text) to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;
