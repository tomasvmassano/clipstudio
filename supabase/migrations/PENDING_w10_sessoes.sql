-- W10-08 · Sessões e dispositivos (FR-14-03) e revogação imediata (R-11, CAP-06, FL-07, QA-03, QA-13). ADR-0061.
-- Expand (aditivo, compatível com o código do main):
--   * _session_alive: a sessão do JWT (claim session_id) tem de existir em auth.sessions. _mfa_ok passa a exigi-lo, por isso
--     _authorize/_authorize_base/_org_can/my_context/profile_update recusam já um JWT de uma sessão terminada, sem esperar
--     que o token expire. JWT sem session_id (testes, service role) não muda nada. Só vale para o pedido da própria pessoa.
--   * my_sessions / session_terminate / sessions_terminate_others: a própria pessoa vê e termina as suas sessões.
--   * Trigger: quem perde o último acesso ativo (removido ou suspenso no último cliente, ou suspenso na agência)
--     fica sem sessões. Staff que continua noutros clientes não é desligado: perde só o cliente (verificado a cada pedido).
-- Requer que o dono das funções (postgres no Supabase) leia e apague em auth.sessions; se não puder, a migração falha
-- inteira em vez de deixar as RPCs a falhar em produção.

do $$ begin
  if to_regclass('auth.sessions') is null then raise exception 'auth.sessions não existe nesta base'; end if;
  if not (has_table_privilege(current_user, 'auth.sessions', 'select') and has_table_privilege(current_user, 'auth.sessions', 'delete')) then
    raise exception 'o papel % não pode ler e apagar auth.sessions: a revogação de sessões não é possível por SQL', current_user;
  end if;
end $$;

-- id da sessão do pedido (claim session_id do JWT do Supabase Auth); null se não houver ou não for um uuid
create or replace function public._session_id() returns uuid
language sql stable set search_path = public as $$
  select case when (auth.jwt() ->> 'session_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then (auth.jwt() ->> 'session_id')::uuid end
$$;

-- a sessão do pedido continua viva (não foi terminada nem passou do not_after)
create or replace function public._session_alive() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select public._session_id() is null
      or exists (select 1 from auth.sessions s where s.id = public._session_id() and s.user_id = auth.uid()
                  and (s.not_after is null or s.not_after > now()))
$$;

-- MFA (W1-15) + sessão viva. Mesmo nome para cobrir todos os sítios que já o chamam.
create or replace function public._mfa_ok(p_uid uuid) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select p_uid is distinct from auth.uid()
      or (public._session_alive()
          and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
               or not exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified')))
$$;

-- my_context: igual a 20261029153629, exceto que uma sessão terminada é recusada (a app sai em vez de pedir o código MFA).
create or replace function public.my_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then return null; end if;
  if not public._session_alive() then raise exception 'sessao_terminada' using errcode = '42501'; end if;
  if not public._mfa_ok(uid) then
    return jsonb_build_object('mfa_required', true,
      'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'confirmed', u.email_confirmed_at is not null) from auth.users u where u.id = uid),
      'agency', '[]'::jsonb, 'workspaces', '[]'::jsonb);
  end if;
  select jsonb_build_object(
    'mfa_required', false,
    'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'confirmed', u.email_confirmed_at is not null,
                    'display_name', p.display_name, 'avatar_path', p.avatar_path, 'timezone', p.timezone, 'theme', coalesce(p.theme, 'dark'),
                    'preferred_workspace', p.preferred_workspace)
             from auth.users u left join profiles p on p.user_id = u.id where u.id = uid),
    'agency', (select jsonb_agg(jsonb_build_object('organization', o.slug, 'name', o.name, 'role', m.agency_role, 'status', m.status,
                 'capabilities', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from capabilities k
                                   where 'org' = any(k.scopes) and public._org_can(k.key, o.id, uid))))
               from agency_memberships m join organizations o on o.id = m.organization_id where m.user_id = uid),
    'workspaces', (select coalesce(jsonb_agg(w order by w->>'name'), '[]') from (
       select jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
              'logo_path', c.logo_path, 'brand_color', c.brand_color,
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

-- As minhas sessões (FR-14-03). Só as da própria pessoa; a atual primeiro.
create or replace function public.my_sessions() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); cur uuid := public._session_id();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._mfa_ok(uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'user_agent', x.user_agent, 'ip', x.ip, 'created_at', x.created_at,
             'last_active_at', x.last_active_at, 'aal', x.aal, 'not_after', x.not_after, 'current', x.id = cur)
           order by (x.id = cur) desc, x.last_active_at desc)
      from (select s.id, left(s.user_agent, 400) user_agent, host(s.ip) ip, s.created_at, s.aal::text aal, s.not_after,
                   greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') last_active_at
              from auth.sessions s
             where s.user_id = uid and (s.not_after is null or s.not_after > now())
             order by greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') desc limit 100) x), '[]'::jsonb);
end $$;

-- Terminar uma sessão da própria pessoa. A de outra pessoa dá o mesmo erro que uma que não existe (não revela nada).
-- Apagar a sessão apaga os refresh tokens (FK on delete cascade no Supabase Auth): o dispositivo não renova o token
-- e, até lá, _mfa_ok recusa o JWT dessa sessão em todas as RPCs.
create or replace function public.session_terminate(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); cur uuid := public._session_id(); s auth.sessions;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._mfa_ok(uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  delete from auth.sessions where id = p_session and user_id = uid returning * into s;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), 'security.session_terminated', 'session', s.id::text,
          jsonb_build_object('current', s.id = cur, 'user_agent', left(s.user_agent, 200), 'created_at', s.created_at));
  return jsonb_build_object('id', s.id, 'current', s.id = cur);
end $$;

-- Terminar todas as outras sessões da própria pessoa (fica só esta).
create or replace function public.sessions_terminate_others() returns int
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); cur uuid := public._session_id(); n int;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if cur is null then raise exception 'sessao_desconhecida' using errcode = '22023'; end if;
  if not public._mfa_ok(uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  with d as (delete from auth.sessions where user_id = uid and id <> cur returning 1) select count(*) into n from d;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), 'security.sessions_terminated_others', 'user', uid::text,
          jsonb_build_object('sessions', n));
  return n;
end $$;

-- histórico de segurança: igual a 20261029153629, mais as sessões terminadas
create or replace function public.my_security_log(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action) order by e.at desc), '[]')
    from (select at, action from audit_events
           where actor_user_id = auth.uid() and action in ('profile.updated', 'security.password_changed', 'security.mfa_enabled',
                 'security.mfa_disabled', 'security.signed_out_everywhere', 'invitation.accepted',
                 'security.session_terminated', 'security.sessions_terminated_others', 'security.signed_out_here')
           order by at desc limit least(greatest(coalesce(p_limit, 30), 1), 100)) e
$$;

-- eventos que a app regista depois de o Auth confirmar: igual a 20261029153629, mais "saiu desta sessão"
-- (a própria sessão termina-se com o signOut do Supabase Auth, que a apaga no servidor; ver ADR-0061)
create or replace function public.security_event(p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_action not in ('security.password_changed', 'security.mfa_enabled', 'security.mfa_disabled', 'security.signed_out_everywhere',
                      'security.signed_out_here') then
    raise exception 'evento_invalido' using errcode = '22023'; end if;
  -- no máximo 20 por hora, para o histórico não ser inundado
  if (select count(*) from audit_events where actor_user_id = uid and action like 'security.%' and at > now() - interval '1 hour') >= 20 then
    raise exception 'demasiados_eventos' using errcode = 'PT429'; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), p_action, 'user', uid::text,
          jsonb_build_object('aal', coalesce(auth.jwt() ->> 'aal', 'aal1'), 'session_id', public._session_id()));
end $$;

-- Ainda tem algum acesso ativo? Membro ativo da agência, ou equipa de um cliente ativo com acesso ativo e por expirar.
-- (Staff da agência suspenso perde os clientes no _authorize, por isso só conta a pertença à agência.)
create or replace function public._has_any_access(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from agency_memberships m where m.user_id = p_uid and m.status = 'active')
      or exists (select 1 from workspace_access a join clients c on c.id = a.workspace_id and c.status = 'active'
                  where a.user_id = p_uid and a.affiliation_type = 'client_staff' and a.status = 'active'
                    and (a.expires_at is null or a.expires_at > now()))
$$;

-- Quem perde um acesso ativo e fica sem nenhum: as sessões são terminadas (FL-07). Auditado com quem fez a mudança.
create or replace function public._revoke_sessions_on_access_loss() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid; v_reason text; o jsonb := to_jsonb(old); n int;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'active' then return null; end if;
    v_user := old.user_id; v_reason := 'deleted';
  else
    if old.status <> 'active' or new.status = 'active' then return null; end if;
    v_user := new.user_id; v_reason := new.status;
  end if;
  if public._has_any_access(v_user) then return null; end if;
  with d as (delete from auth.sessions where user_id = v_user returning 1) select count(*) into n from d;
  if n > 0 then
    insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
    values (auth.uid(), case when auth.uid() is null then 'system' else 'user' end, (select email from auth.users where id = auth.uid()),
            (o ->> 'organization_id')::uuid, o ->> 'workspace_id', 'security.sessions_revoked', 'user', v_user::text,
            jsonb_build_object('sessions', n, 'reason', tg_table_name || '.' || v_reason));
  end if;
  return null;
end $$;

drop trigger if exists workspace_access_revoke_sessions on public.workspace_access;
create trigger workspace_access_revoke_sessions after update of status or delete on public.workspace_access
  for each row execute function public._revoke_sessions_on_access_loss();
drop trigger if exists agency_memberships_revoke_sessions on public.agency_memberships;
create trigger agency_memberships_revoke_sessions after update of status or delete on public.agency_memberships
  for each row execute function public._revoke_sessions_on_access_loss();

revoke all on function public._session_id(), public._session_alive(), public._mfa_ok(uuid), public._has_any_access(uuid),
  public._revoke_sessions_on_access_loss() from public, anon, authenticated;
revoke all on function public.my_sessions(), public.session_terminate(uuid), public.sessions_terminate_others(),
  public.my_security_log(int), public.my_context(), public.security_event(text) from public, anon;
grant execute on function public.my_sessions(), public.session_terminate(uuid), public.sessions_terminate_others(),
  public.my_security_log(int), public.my_context(), public.security_event(text) to authenticated;

/* Rollback (compatível, nenhuma tabela nova; as sessões terminadas não voltam):
drop trigger if exists workspace_access_revoke_sessions on public.workspace_access;
drop trigger if exists agency_memberships_revoke_sessions on public.agency_memberships;
drop function if exists public._revoke_sessions_on_access_loss(), public._has_any_access(uuid),
  public.sessions_terminate_others(), public.session_terminate(uuid), public.my_sessions();
-- repor _mfa_ok, my_context, my_security_log e security_event de 20261029153629_w1_profile_mfa.sql (sem a verificação da sessão);
drop function if exists public._session_alive(), public._session_id();
*/
