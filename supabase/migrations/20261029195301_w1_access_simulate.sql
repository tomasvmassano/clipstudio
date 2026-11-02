-- W1-16 · CAP-05 simulador "Ver como" e BIZ-07 pré-visualizar como papel: só leitura, avaliado no servidor com a mesma
-- regra de _access_explain, auditado com quem pergunta como ator. Não há impersonação. Expand: uma função nova.

create or replace function public.access_simulate(p_ws text, p_user uuid default null, p_role text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a workspace_access; label text; res jsonb;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('permissions.manage', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if (p_user is null) = (p_role is null) then raise exception 'alvo_invalido' using errcode = '22023', detail = 'Escolhe uma pessoa ou um papel.'; end if;
  if p_role is not null then
    if not exists (select 1 from role_capabilities where scope = 'ws' and role = p_role) then
      raise exception 'papel_desconhecido' using errcode = '22023', detail = 'Esse papel não existe.'; end if;
    label := p_role;
    res := coalesce((select jsonb_agg(jsonb_build_object('key', c.key, 'label', coalesce(c.label, c.key), 'module', c.module, 'status', c.status,
              'allowed', exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = p_role and rc.capability = c.key),
              'reasons', jsonb_build_array(case when exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = p_role and rc.capability = c.key)
                                                then format('O papel %s inclui esta capacidade.', p_role)
                                                else format('O papel %s não inclui esta capacidade.', p_role) end))
              order by c.module, c.key) from capabilities c where 'ws' = any(c.scopes)), '[]');
  else
    -- a pessoa tem de estar ligada a este cliente (ou ser da agência que o gere): não serve para sondar contas alheias
    select * into a from workspace_access where workspace_id = p_ws and user_id = p_user;
    if a.user_id is null and not exists (select 1 from agency_memberships m join clients c on c.organization_id = m.organization_id
                                         where m.user_id = p_user and c.id = p_ws and m.agency_role = 'agency_owner') then
      raise exception 'pessoa_sem_acesso' using errcode = '22023', detail = 'Essa pessoa não tem acesso a este cliente.'; end if;
    label := (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = p_user);
    res := coalesce((select jsonb_agg(jsonb_build_object('key', c.key, 'label', coalesce(c.label, c.key), 'module', c.module, 'status', c.status)
              || (public._access_explain(p_ws, p_user, c.key) - 'grant_id') order by c.module, c.key)
            from capabilities c where 'ws' = any(c.scopes)), '[]');
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'access.simulated', case when p_role is null then 'user' else 'role' end,
          coalesce(p_user::text, p_role), jsonb_build_object('read_only', true));
  return jsonb_build_object('target', jsonb_build_object('kind', case when p_role is null then 'user' else 'role' end, 'label', label,
                                                         'role', coalesce(p_role, a.workspace_role), 'status', a.status),
                            'capabilities', res);
end $$;

revoke all on function public.access_simulate(text, uuid, text) from public, anon;
grant execute on function public.access_simulate(text, uuid, text) to authenticated;

/* Rollback (compatível): drop function public.access_simulate(text, uuid, text); */
