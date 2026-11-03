-- W1-17 · BIZ-07 / CAP-05: navegar a app como um papel ou uma pessoa, só leitura, avaliado no servidor (ADR-0045).
-- Expand: uma tabela nova, três RPCs novas e _authorize passa a estreitar o acesso de quem tem uma pré-visualização ativa
-- nesse cliente. Sem linhas em access_previews (o código do main nunca as cria) _authorize dá exatamente o mesmo de antes.
-- A pré-visualização só tira acesso, nunca dá: capacidade de leitura que o alvo tem E que a própria pessoa tem.

create table if not exists public.access_previews (
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  target_role text,
  target_user uuid references auth.users(id) on delete cascade,
  target_label text not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (user_id, workspace_id),
  check ((target_role is null) <> (target_user is null)),
  check (expires_at > started_at and expires_at <= started_at + interval '2 hours')
);
alter table public.access_previews enable row level security;
revoke all on public.access_previews from anon, authenticated;   -- só pelas RPCs

-- Capacidades que só leem: as únicas que podem ficar ligadas durante uma pré-visualização.
create or replace function public._cap_is_read(p_cap text) returns boolean
language sql immutable set search_path = public as $$
  select p_cap like '%.read' or p_cap = 'ops.presence'
$$;

-- A regra de sempre (W1-15), sem pré-visualização. Mesmo corpo que _authorize tinha.
create or replace function public._authorize_base(p_cap text, p_ws text default null, p_uid uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_role text; v_org uuid;
begin
  if p_uid is null then return false; end if;
  if not public._mfa_ok(p_uid) then return false; end if;                                  -- MFA ativo exige aal2 (W1-15)
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

-- _authorize: igual a _authorize_base, exceto para a própria sessão com pré-visualização ativa neste cliente.
create or replace function public._authorize(p_cap text, p_ws text default null, p_uid uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare pv access_previews;
begin
  if p_ws is not null and p_uid is not null and p_uid = auth.uid() then
    select * into pv from access_previews where user_id = p_uid and workspace_id = p_ws and expires_at > now();
    if pv.user_id is not null then
      return public._cap_is_read(p_cap)
         and public._authorize_base(p_cap, p_ws, p_uid)
         and case when pv.target_role is not null
                  then exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = pv.target_role and rc.capability = p_cap)
                  else public._authorize_base(p_cap, p_ws, pv.target_user) end;
    end if;
  end if;
  return public._authorize_base(p_cap, p_ws, p_uid);
end $$;

-- Capacidades do alvo (para a app mostrar menus e botões como ele os vê; escrever continua recusado).
create or replace function public._preview_caps(p_ws text, p_role text, p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(c.key order by c.key), '[]') from capabilities c
   where 'ws' = any (c.scopes)
     and case when p_role is not null
              then exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = p_role and rc.capability = c.key)
              else public._authorize_base(c.key, p_ws, p_user) end
$$;

create or replace function public._preview_json(pv access_previews) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('workspace_id', pv.workspace_id, 'kind', case when pv.target_role is null then 'user' else 'role' end,
           'role', coalesce(pv.target_role, (select a.workspace_role from workspace_access a where a.workspace_id = pv.workspace_id and a.user_id = pv.target_user)),
           'label', pv.target_label, 'started_at', pv.started_at, 'expires_at', pv.expires_at,
           'capabilities', public._preview_caps(pv.workspace_id, pv.target_role, pv.target_user))
$$;

-- Começar (ou trocar de alvo): quem gere permissões no cliente; 30 minutos; auditado com quem começa como ator.
create or replace function public.access_preview_start(p_ws text, p_user uuid default null, p_role text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); lbl text; pv access_previews;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize_base('permissions.manage', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if (p_user is null) = (p_role is null) then raise exception 'alvo_invalido' using errcode = '22023', detail = 'Escolhe uma pessoa ou um papel.'; end if;
  if p_role is not null then
    if not exists (select 1 from role_capabilities where scope = 'ws' and role = p_role) then
      raise exception 'papel_desconhecido' using errcode = '22023', detail = 'Esse papel não existe.'; end if;
    lbl := p_role;
  else
    if p_user = uid then raise exception 'alvo_invalido' using errcode = '22023', detail = 'Escolhe outra pessoa.'; end if;
    if not exists (select 1 from workspace_access where workspace_id = p_ws and user_id = p_user) then
      raise exception 'pessoa_sem_acesso' using errcode = '22023', detail = 'Essa pessoa não tem acesso a este cliente.'; end if;
    lbl := (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = p_user);
  end if;
  insert into access_previews (user_id, workspace_id, target_role, target_user, target_label, started_at, expires_at)
  values (uid, p_ws, p_role, p_user, lbl, now(), now() + interval '30 minutes')
  on conflict (user_id, workspace_id) do update set target_role = excluded.target_role, target_user = excluded.target_user,
    target_label = excluded.target_label, started_at = excluded.started_at, expires_at = excluded.expires_at
  returning * into pv;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'access.preview_started',
          case when p_role is null then 'user' else 'role' end, coalesce(p_user::text, p_role),
          jsonb_build_object('read_only', true, 'expires_at', pv.expires_at));
  return public._preview_json(pv);
end $$;

-- Sair: a própria pessoa, sempre (não depende de capacidades, que estão estreitadas durante a pré-visualização).
create or replace function public.access_preview_stop(p_ws text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); pv access_previews;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  delete from access_previews where user_id = uid and workspace_id = p_ws returning * into pv;
  if pv.user_id is not null then
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'access.preview_stopped',
            case when pv.target_role is null then 'user' else 'role' end, coalesce(pv.target_user::text, pv.target_role),
            jsonb_build_object('ended_early', pv.expires_at > now()));
  end if;
end $$;

-- As minhas pré-visualizações ativas (a app mostra a faixa e esconde o que o alvo não vê). Apaga as expiradas.
create or replace function public.access_preview_mine() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return '[]'; end if;
  delete from access_previews where user_id = uid and expires_at <= now();
  return coalesce((select jsonb_agg(public._preview_json(p) order by p.workspace_id) from access_previews p where p.user_id = uid), '[]');
end $$;

revoke all on function public._cap_is_read(text), public._authorize_base(text, text, uuid), public._preview_caps(text, text, uuid),
  public._preview_json(public.access_previews) from public, anon, authenticated;
revoke all on function public.access_preview_start(text, uuid, text), public.access_preview_stop(text), public.access_preview_mine() from public, anon;
grant execute on function public.access_preview_start(text, uuid, text), public.access_preview_stop(text), public.access_preview_mine() to authenticated;

/* Rollback (compatível): repor _authorize com o corpo de _authorize_base (20261029153629_w1_profile_mfa.sql) e
   drop function public.access_preview_mine(), public.access_preview_stop(text), public.access_preview_start(text, uuid, text),
     public._preview_json(public.access_previews), public._preview_caps(text, text, uuid), public._authorize_base(text, text, uuid), public._cap_is_read(text);
   drop table public.access_previews; */
