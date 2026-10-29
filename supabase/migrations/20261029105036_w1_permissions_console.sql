-- W1-08: consola de permissões por cliente: matrizes, exceções por pessoa e "porque tem acesso?" (PRD CAP-02, CAP-03, CAP-05, CAP-07 parcial; ADR-0014).
-- Só aditivo. Rollback: bloco no fim.

alter table public.capabilities add column if not exists label text;
alter table public.permission_grants add column if not exists revoked_at timestamptz, add column if not exists revoked_by uuid references auth.users(id);

update public.capabilities c set label = v.label from (values
  ('workspaces.read','Ver a lista de clientes'), ('workspaces.create','Criar clientes'), ('workspaces.archive','Arquivar e recuperar clientes'),
  ('team.read','Ver a equipa'), ('team.invite','Convidar pessoas'), ('team.manage','Gerir membros (papel, suspender, remover)'),
  ('permissions.manage','Gerir permissões e exceções'), ('audit.read','Ver o histórico de ações'), ('settings.manage','Mudar as definições do cliente'),
  ('integrations.manage','Gerir integrações'),
  ('scripts.read','Ver guiões'), ('scripts.create','Criar guiões'), ('scripts.edit','Editar guiões'), ('scripts.submit','Enviar guiões para revisão'),
  ('scripts.approve','Aprovar guiões'), ('scripts.reject','Rejeitar guiões'), ('scripts.delete','Arquivar guiões'), ('scripts.export','Exportar guiões'),
  ('sources.read','Ver fontes'), ('sources.create','Adicionar fontes'), ('sources.triage','Triar fontes'), ('requests.create','Fazer pedidos de tema'),
  ('references.read','Ver referências'), ('references.manage','Gerir referências'),
  ('recording.use','Usar o teleprompter'), ('recording.confirm','Confirmar gravações'),
  ('tasks.read','Ver tarefas'), ('tasks.work','Trabalhar nas suas tarefas'), ('tasks.manage','Gerir tarefas, templates e automações'),
  ('calendar.read','Ver o calendário'), ('calendar.schedule','Reagendar e agendar'), ('production.update','Mudar o estado de produção'),
  ('agents.read','Ver os agentes'), ('agents.rehearse','Ensaiar a sala dos agentes'), ('agents.run','Correr os agentes'), ('agents.configure','Configurar os agentes'),
  ('analytics.read','Ver o desempenho'), ('costs.read','Ver custos do cliente'), ('costs.read_agency','Ver custos da agência'),
  ('media.upload','Carregar media'), ('media.download','Descarregar media'), ('media.share','Partilhar media'),
  ('clipping.create','Criar clips'), ('clipping.export','Exportar clips'), ('review.comment','Comentar na revisão'), ('review.approve','Aprovar na revisão'),
  ('publishing.schedule','Agendar publicações'), ('publishing.publish','Publicar'), ('social_accounts.manage','Gerir contas sociais')
) v(key, label) where c.key = v.key;

-- team.read, team.invite e permissions.manage já funcionam; o registo passa a dizê-lo
update public.capabilities set status = 'ativo' where key in ('team.read','team.invite','permissions.manage');

-- porque é que esta pessoa pode (ou não) fazer isto neste cliente? Segue a mesma ordem de _authorize (CAP-05)
create or replace function public._access_explain(p_ws text, p_user uuid, p_cap text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clients; a workspace_access; g record; m agency_memberships; cap capabilities; reasons jsonb := '[]';
begin
  select * into cap from capabilities where key = p_cap;
  if cap.key is null then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Capacidade desconhecida: negado por defeito.')); end if;
  select * into c from clients where id = p_ws;
  if c.id is null or c.status <> 'active' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O cliente está arquivado ou não existe.')); end if;
  select * into g from permission_grants where user_id = p_user and workspace_id = p_ws and capability = p_cap and effect = 'deny'
     and revoked_at is null and (expires_at is null or expires_at > now()) order by created_at desc limit 1;
  if g.id is not null then
    return jsonb_build_object('allowed', false, 'source', 'deny', 'grant_id', g.id, 'reasons', jsonb_build_array(
      'Negação explícita' || coalesce(' até ' || to_char(g.expires_at at time zone c.timezone, 'DD/MM/YYYY HH24:MI'), '') || coalesce(': ' || g.reason, '') || '. Prevalece sobre o papel.'));
  end if;
  select * into m from agency_memberships where user_id = p_user and organization_id = c.organization_id;
  if m.user_id is not null and m.agency_role = 'agency_owner' and m.status = 'active' then
    return jsonb_build_object('allowed', true, 'source', 'agency_owner', 'reasons', jsonb_build_array('Dono da agência: acesso a todos os clientes da agência (auditado).'));
  end if;
  select * into a from workspace_access where workspace_id = p_ws and user_id = p_user;
  if a.user_id is null or a.status = 'removed' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Não tem acesso a este cliente.')); end if;
  if a.status = 'suspended' then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O acesso está suspenso.')); end if;
  if a.expires_at is not null and a.expires_at <= now() then return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('O acesso expirou.')); end if;
  if a.affiliation_type = 'agency_staff' and m.status is distinct from 'active' then
    return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('Está suspenso na agência, por isso perde os clientes.'));
  end if;
  if exists (select 1 from role_capabilities where scope = 'ws' and role = a.workspace_role and capability = p_cap) then
    reasons := reasons || jsonb_build_array(format('O papel %s inclui esta capacidade.', a.workspace_role));
  end if;
  select * into g from permission_grants where user_id = p_user and workspace_id = p_ws and capability = p_cap and effect = 'allow'
     and revoked_at is null and (expires_at is null or expires_at > now()) order by created_at desc limit 1;
  if g.id is not null then
    reasons := reasons || jsonb_build_array('Exceção dada à pessoa' || coalesce(' até ' || to_char(g.expires_at at time zone c.timezone, 'DD/MM/YYYY HH24:MI'), '') || coalesce(': ' || g.reason, '') || '.');
  end if;
  if jsonb_array_length(reasons) = 0 then
    return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array(format('O papel %s não inclui esta capacidade e não há exceção.', a.workspace_role)));
  end if;
  return jsonb_build_object('allowed', true, 'source', case when g.id is not null and not exists (select 1 from role_capabilities where scope = 'ws' and role = a.workspace_role and capability = p_cap) then 'grant' else 'role' end,
                            'grant_id', g.id, 'reasons', reasons);
end $$;

create or replace function public.access_explain(p_ws text, p_user uuid, p_cap text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  -- cada pessoa pode perguntar por si; sobre outros só quem gere permissões neste cliente
  if p_user is distinct from uid and not public._authorize('permissions.manage', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_user = uid and not exists (select 1 from capabilities k where public._authorize(k.key, p_ws, uid)) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return public._access_explain(p_ws, p_user, p_cap) || jsonb_build_object('capability', p_cap);
end $$;

-- matrizes: papéis × capacidades e pessoas × capacidades, com as exceções (CAP-02)
create or replace function public.permissions_matrix(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); owner boolean := public.is_agency_owner(uid); mine text;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('permissions.manage', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select workspace_role into mine from workspace_access where workspace_id = p_ws and user_id = uid and status = 'active';
  return jsonb_build_object(
    'capabilities', (select jsonb_agg(jsonb_build_object('key', k.key, 'label', coalesce(k.label, k.key), 'module', k.module, 'risk', k.risk, 'status', k.status,
                       'mine', public._authorize(k.key, p_ws, uid)) order by k.module, k.key)
                     from capabilities k where 'ws' = any(k.scopes)),
    'roles', (select jsonb_object_agg(r.role, (select coalesce(jsonb_agg(rc.capability order by rc.capability), '[]') from role_capabilities rc where rc.scope = 'ws' and rc.role = r.role))
              from (values ('workspace_owner'),('workspace_admin'),('manager'),('contributor'),('reviewer'),('viewer')) r(role)),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', a.user_id, 'email', u.email, 'role', a.workspace_role, 'affiliation', a.affiliation_type,
                   'status', a.status, 'job_title', a.job_title,
                   'effective', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from capabilities k where 'ws' = any(k.scopes) and public._authorize(k.key, p_ws, a.user_id)),
                   'can_edit', a.user_id <> uid and a.status <> 'removed'
                               and (owner or (a.affiliation_type = 'client_staff' and public.ws_role_rank(a.workspace_role) <= public.ws_role_rank(mine))))
                   order by a.affiliation_type, u.email), '[]')
                from workspace_access a join auth.users u on u.id = a.user_id where a.workspace_id = p_ws and a.status <> 'removed'),
    'grants', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'user_id', g.user_id, 'capability', g.capability, 'effect', g.effect, 'expires_at', g.expires_at,
                   'reason', g.reason, 'created_at', g.created_at, 'by', (select email from auth.users where id = g.created_by)) order by g.created_at desc), '[]')
               from permission_grants g where g.workspace_id = p_ws and g.revoked_at is null and (g.expires_at is null or g.expires_at > now())));
end $$;

-- dar ou negar uma capacidade a uma pessoa: só quem gere permissões, nunca a si próprio, nunca acima do seu nível,
-- e só se dá o que se tem (R-12); a negação prevalece e pode ter prazo; tudo com motivo e auditado (CAP-03, CAP-07)
create or replace function public.grant_set(p_ws text, p_user uuid, p_cap text, p_effect text, p_expires_at timestamptz default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a workspace_access; mine text; owner boolean := public.is_agency_owner(uid); prev permission_grants; g permission_grants; org uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('permissions.manage', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'grant.set', 'capability', p_cap);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_effect not in ('allow','deny') then raise exception 'efeito_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from capabilities where key = p_cap and 'ws' = any(scopes)) then raise exception 'capacidade_invalida' using errcode = '22023'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  if p_expires_at is not null and (p_expires_at <= now() or p_expires_at > now() + interval '366 days') then raise exception 'prazo_invalido' using errcode = '22023'; end if;
  if p_user = uid then raise exception 'nao_a_si_proprio' using errcode = '42501'; end if;
  select * into a from workspace_access where workspace_id = p_ws and user_id = p_user and status <> 'removed';
  if a.user_id is null then raise exception 'membro_nao_encontrado' using errcode = 'P0002'; end if;
  if not owner then
    if a.affiliation_type = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select workspace_role into mine from workspace_access where workspace_id = p_ws and user_id = uid and status = 'active';
    if public.ws_role_rank(a.workspace_role) > public.ws_role_rank(mine) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
    if p_effect = 'allow' and not public._authorize(p_cap, p_ws, uid) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end if;
  -- só uma exceção ativa por pessoa e capacidade: a nova substitui a anterior
  select * into prev from permission_grants where workspace_id = p_ws and user_id = p_user and capability = p_cap and revoked_at is null
    and (expires_at is null or expires_at > now()) order by created_at desc limit 1;
  update permission_grants set revoked_at = now(), revoked_by = uid
   where workspace_id = p_ws and user_id = p_user and capability = p_cap and revoked_at is null;
  insert into permission_grants (workspace_id, user_id, capability, effect, expires_at, reason, created_by)
  values (p_ws, p_user, p_cap, p_effect, p_expires_at, left(btrim(p_reason), 500), uid) returning * into g;
  select organization_id into org from clients where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', org, p_ws, 'grant.set', 'member', p_user::text,
          case when prev.id is not null then jsonb_build_object('capability', prev.capability, 'effect', prev.effect, 'expires_at', prev.expires_at) end,
          jsonb_build_object('capability', p_cap, 'effect', p_effect, 'expires_at', p_expires_at, 'reason', left(btrim(p_reason), 500), 'grant_id', g.id));
  return jsonb_build_object('id', g.id, 'capability', p_cap, 'effect', p_effect, 'expires_at', p_expires_at,
                            'now', public._access_explain(p_ws, p_user, p_cap));
end $$;

create or replace function public.grant_revoke(p_id bigint, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g permission_grants; a workspace_access; mine text; owner boolean := public.is_agency_owner(uid);
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select * into g from permission_grants where id = p_id;
  if g.id is null or not public._authorize('permissions.manage', g.workspace_id, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if g.user_id = uid then raise exception 'nao_a_si_proprio' using errcode = '42501'; end if;
  select * into a from workspace_access where workspace_id = g.workspace_id and user_id = g.user_id;
  if not owner then
    if a.affiliation_type = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select workspace_role into mine from workspace_access where workspace_id = g.workspace_id and user_id = uid and status = 'active';
    if public.ws_role_rank(a.workspace_role) > public.ws_role_rank(mine) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end if;
  if g.revoked_at is not null then return jsonb_build_object('id', g.id, 'revoked', true); end if;
  update permission_grants set revoked_at = now(), revoked_by = uid where id = p_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select organization_id from clients where id = g.workspace_id), g.workspace_id, 'grant.revoked', 'member', g.user_id::text,
          jsonb_build_object('capability', g.capability, 'effect', g.effect, 'expires_at', g.expires_at, 'grant_id', g.id),
          jsonb_build_object('revoked', true, 'reason', left(btrim(coalesce(p_reason, '')), 500)));
  return jsonb_build_object('id', g.id, 'revoked', true, 'now', public._access_explain(g.workspace_id, g.user_id, g.capability));
end $$;

-- _authorize passa a ignorar exceções revogadas
create or replace function public._authorize(p_cap text, p_ws text default null, p_uid uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
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
             and g.effect = 'deny' and g.revoked_at is null and (g.expires_at is null or g.expires_at > now())) then return false; end if;
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
                 and g.effect = 'allow' and g.revoked_at is null and (g.expires_at is null or g.expires_at > now()));
end $$;

revoke all on function public._access_explain(text,uuid,text), public.access_explain(text,uuid,text), public.permissions_matrix(text),
  public.grant_set(text,uuid,text,text,timestamptz,text), public.grant_revoke(bigint,text) from public, anon;
grant execute on function public.access_explain(text,uuid,text), public.permissions_matrix(text),
  public.grant_set(text,uuid,text,text,timestamptz,text), public.grant_revoke(bigint,text) to authenticated;

/* Rollback:
drop function grant_revoke(bigint,text), grant_set(text,uuid,text,text,timestamptz,text), permissions_matrix(text), access_explain(text,uuid,text), _access_explain(text,uuid,text);
-- _authorize: recriar a versão de 20261028185124 (sem revoked_at)
alter table permission_grants drop column revoked_at, drop column revoked_by;
alter table capabilities drop column label;
update capabilities set status = 'W1' where key in ('team.read','team.invite','permissions.manage');
*/
