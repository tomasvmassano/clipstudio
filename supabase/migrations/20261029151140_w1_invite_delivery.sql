-- W1-14 · Convites por email (FR-13-01): link com token, reenviar, recusar, estado na lista.
-- Expand: só acrescenta colunas e funções; accept_invitations e as listas passam a ignorar convites recusados
-- (antes não existiam). Compatível com o código no main.

alter table public.invitations
  add column if not exists declined_at timestamptz,
  add column if not exists token_hash text,
  add column if not exists sent_count integer not null default 0,
  add column if not exists last_sent_at timestamptz;
create unique index if not exists invitations_token_hash on public.invitations(token_hash) where token_hash is not null;

-- estado de um convite, igual em todo o lado
create or replace function public._invite_status(i public.invitations) returns text
language sql stable set search_path = public as $$
  select case when i.accepted_at is not null then 'accepted' when i.revoked_at is not null then 'revoked'
              when i.declined_at is not null then 'declined' when i.expires_at <= now() then 'expired' else 'pending' end
$$;

-- quem pode enviar/reenviar: o mesmo que pode convidar para esse espaço
create or replace function public._invite_can_manage(i public.invitations, p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid is not null and case when i.workspace_id is null then public._org_can('team.invite', i.organization_id, p_uid)
                                    else public._authorize('team.invite', i.workspace_id, p_uid) end
$$;

-- Gera o link do convite (token novo; o anterior deixa de valer) e renova a validade por 14 dias.
-- Devolve o token só a quem pode convidar: é o que vai no email ou, sem email configurado, no "copiar link".
create or replace function public.invitation_issue_link(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); i invitations; tok text; st text; target text; inviter text;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select * into i from invitations where id = p_id for update;
  if i.id is null or not public._invite_can_manage(i, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  st := public._invite_status(i);
  if st not in ('pending', 'expired') then raise exception 'convite_fechado' using errcode = '22023'; end if;
  if i.last_sent_at > now() - interval '60 seconds' then raise exception 'aguarda_para_reenviar' using errcode = 'PT429'; end if;
  if i.sent_count >= 5 then raise exception 'limite_envios' using errcode = 'PT429'; end if;
  tok := encode(gen_random_bytes(24), 'hex');
  update invitations set token_hash = encode(digest(tok, 'sha256'), 'hex'), sent_count = sent_count + 1, last_sent_at = now(),
         expires_at = greatest(expires_at, now() + interval '14 days')
   where id = p_id returning * into i;
  select coalesce(c.name, o.name) into target from organizations o left join clients c on c.id = i.workspace_id where o.id = i.organization_id;
  select email into inviter from auth.users where id = uid;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', inviter, i.organization_id, i.workspace_id, 'invitation.sent', 'invitation', i.id::text,
          jsonb_build_object('email', i.email, 'sent_count', i.sent_count, 'expires_at', i.expires_at));
  return jsonb_build_object('token', tok, 'email', i.email, 'kind', case when i.workspace_id is null then 'agency' else 'workspace' end,
                            'target', target, 'role', coalesce(i.workspace_role, i.agency_role), 'inviter', inviter,
                            'expires_at', i.expires_at, 'sent_count', i.sent_count);
end $$;

-- O que o link mostra a quem o abre (sem sessão): só o necessário para decidir. Token errado = 'invalid'.
create or replace function public.invitation_preview(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare i invitations; target text;
begin
  if coalesce(length(p_token), 0) < 32 then return jsonb_build_object('status', 'invalid'); end if;
  select * into i from invitations where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  if i.id is null then return jsonb_build_object('status', 'invalid'); end if;
  select coalesce(c.name, o.name) into target from organizations o left join clients c on c.id = i.workspace_id where o.id = i.organization_id;
  return jsonb_build_object('status', public._invite_status(i), 'email', i.email, 'target', target, 'workspace_id', i.workspace_id,
                            'kind', case when i.workspace_id is null then 'agency' else 'workspace' end,
                            'role', coalesce(i.workspace_role, i.agency_role), 'expires_at', i.expires_at,
                            'inviter', (select email from auth.users where id = i.created_by));
end $$;

-- Recusar pelo link. Quem tem o link é quem recebeu o email; não precisa de conta.
create or replace function public.invitation_decline(p_token text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare i invitations;
begin
  if coalesce(length(p_token), 0) < 32 then raise exception 'link_invalido' using errcode = '22023'; end if;
  select * into i from invitations where token_hash = encode(digest(p_token, 'sha256'), 'hex') for update;
  if i.id is null then raise exception 'link_invalido' using errcode = '22023'; end if;
  if public._invite_status(i) <> 'pending' then return public._invite_status(i); end if;
  update invitations set declined_at = now() where id = i.id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (auth.uid(), 'system', 'convidado (link)', i.organization_id, i.workspace_id, 'invitation.declined', 'invitation', i.id::text,
          jsonb_build_object('email', i.email));
  return 'declined';
end $$;

-- accept_invitations: igual ao de 20261029121252, mais "não aceita convites recusados".
create or replace function public.accept_invitations() returns integer
language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid := auth.uid(); v_email text; v_conf timestamptz; inv record; n int := 0;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select email, email_confirmed_at into v_email, v_conf from auth.users where id = uid;
  if v_conf is null then return 0; end if;  -- só emails confirmados
  for inv in select * from invitations where lower(email) = lower(v_email) and accepted_at is null and revoked_at is null
                and declined_at is null and expires_at > now() for update loop
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

-- Listas de convites: passam a mostrar também os expirados e recusados (para reenviar ou convidar de novo),
-- com estado e último envio. Campos novos; os antigos ficam iguais.
create or replace function public._invite_json(i public.invitations) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', i.id, 'email', i.email, 'affiliation', i.invited_as, 'role', i.workspace_role, 'agency_role', i.agency_role,
                            'expires_at', i.expires_at, 'created_at', i.created_at, 'status', public._invite_status(i),
                            'sent_count', i.sent_count, 'last_sent_at', i.last_sent_at, 'declined_at', i.declined_at)
$$;

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
    'invitations', (select coalesce(jsonb_agg(public._invite_json(i) order by i.created_at desc), '[]')
                from invitations i where i.workspace_id = p_ws and i.accepted_at is null and i.revoked_at is null
                  and (i.declined_at is not null or i.expires_at > now() - interval '30 days')),
    'can_invite', public._authorize('team.invite', p_ws, uid),
    'can_invite_agency', owner,
    'can_manage', public._authorize('team.manage', p_ws, uid),
    'my_rank', case when owner then 99 else public.ws_role_rank(mine) end,
    'agency_staff', case when owner then (select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', u.email, 'role', m.agency_role) order by u.email), '[]')
                    from agency_memberships m join auth.users u on u.id = m.user_id
                   where m.organization_id = v_org and m.status = 'active' and m.user_id <> uid
                     and not exists (select 1 from workspace_access a where a.workspace_id = p_ws and a.user_id = m.user_id and a.status = 'active')) end);
end $$;

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
                (select coalesce(jsonb_agg(public._invite_json(i) order by i.created_at desc), '[]')
                 from invitations i where i.organization_id = v_org and i.workspace_id is null
                   and i.accepted_at is null and i.revoked_at is null
                   and (i.declined_at is not null or i.expires_at > now() - interval '30 days')) else '[]'::jsonb end);
end $$;

revoke all on function public._invite_status(public.invitations), public._invite_can_manage(public.invitations, uuid),
  public._invite_json(public.invitations), public.invitation_issue_link(uuid) from public, anon;
grant execute on function public.invitation_issue_link(uuid) to authenticated;
revoke all on function public.invitation_preview(text), public.invitation_decline(text) from public;
grant execute on function public.invitation_preview(text), public.invitation_decline(text) to anon, authenticated;
revoke execute on function public.accept_invitations(), public.workspace_team(text), public.agency_team() from public, anon;
grant execute on function public.accept_invitations(), public.workspace_team(text), public.agency_team() to authenticated;

/* Rollback (compatível): repor accept_invitations, workspace_team e agency_team de 20261029121252 / 20261029100534 / 20261029130512;
drop function public.invitation_decline(text), public.invitation_preview(text), public.invitation_issue_link(uuid),
  public._invite_json(public.invitations), public._invite_can_manage(public.invitations, uuid), public._invite_status(public.invitations);
-- contract posterior, se for preciso: alter table public.invitations drop column declined_at, drop column token_hash, drop column sent_count, drop column last_sent_at; */
