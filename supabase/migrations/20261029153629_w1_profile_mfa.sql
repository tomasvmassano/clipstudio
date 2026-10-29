-- W1-15 · Perfil (FR-14-01, parte de FR-14-02/03/04): nome, avatar, fuso, tema, cliente preferido; MFA aplicado no servidor.
-- Expand: tabela e bucket novos; _authorize e _org_can passam a recusar quem tem MFA ativo e entrou só com a palavra-passe
-- (aal1). Hoje ninguém tem fatores, por isso nada muda para os utilizadores atuais.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 80),
  avatar_path text,
  timezone text,
  theme text not null default 'dark' check (theme in ('system', 'light', 'dark')),
  preferred_workspace text references public.clients(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
-- leitura e escrita só pelas RPCs abaixo (cada pessoa só a sua linha)

-- avatares: bucket privado, cada pessoa só escreve e lê a sua pasta <uid>/
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;
drop policy if exists avatars_own_read on storage.objects;
create policy avatars_own_read on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_own_write on storage.objects;
create policy avatars_own_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_own_update on storage.objects;
create policy avatars_own_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_own_delete on storage.objects;
create policy avatars_own_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- MFA: quem tem um fator verificado só passa com uma sessão aal2. Só se aplica ao pedido da própria pessoa
-- (p_uid = auth.uid()); verificações feitas pelo servidor para outro utilizador não dependem da sessão de ninguém.
create or replace function public._mfa_ok(p_uid uuid) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select p_uid is distinct from auth.uid()
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified')
$$;

create or replace function public._authorize(p_cap text, p_ws text default null, p_uid uuid default auth.uid())
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

create or replace function public._org_can(p_cap text, p_org uuid, p_uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid is not null and public._mfa_ok(p_uid) and exists (
    select 1 from agency_memberships m join organizations o on o.id = m.organization_id and o.status = 'active'
      join role_capabilities rc on rc.scope = 'org' and rc.role = m.agency_role and rc.capability = p_cap
     where m.user_id = p_uid and m.organization_id = p_org and m.status = 'active')
$$;

-- my_context: igual ao de 20261029103605, mais 'mfa_required' (a app pede o código em vez de dizer "sem acesso")
-- e o perfil da própria pessoa.
create or replace function public.my_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then return null; end if;
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

-- o próprio perfil
create or replace function public.profile_update(p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text; before jsonb; p profiles; n text; tz text; th text; ws text;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._mfa_ok(uid) then raise exception 'mfa_necessario' using errcode = '42501'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('display_name', 'avatar_path', 'timezone', 'theme', 'preferred_workspace') then raise exception 'campo_invalido: %', k using errcode = '22023'; end if;
  end loop;
  insert into profiles (user_id) values (uid) on conflict (user_id) do nothing;
  select to_jsonb(x) - 'user_id' - 'updated_at' into before from profiles x where x.user_id = uid;
  if p_patch ? 'display_name' then
    n := nullif(btrim(p_patch->>'display_name'), '');
    if n is not null and char_length(n) > 80 then raise exception 'nome_longo' using errcode = '22023'; end if;
    update profiles set display_name = n where user_id = uid;
  end if;
  if p_patch ? 'avatar_path' then
    -- só um caminho dentro da pasta da própria pessoa (o upload é feito pelo browser com a RLS do storage)
    if p_patch->>'avatar_path' is not null and (p_patch->>'avatar_path') !~ ('^' || uid::text || '/[A-Za-z0-9._-]{1,80}$') then
      raise exception 'caminho_invalido' using errcode = '22023'; end if;
    update profiles set avatar_path = p_patch->>'avatar_path' where user_id = uid;
  end if;
  if p_patch ? 'timezone' then
    tz := nullif(p_patch->>'timezone', '');
    if tz is not null and not exists (select 1 from pg_timezone_names where name = tz) then raise exception 'fuso_invalido' using errcode = '22023'; end if;
    update profiles set timezone = tz where user_id = uid;
  end if;
  if p_patch ? 'theme' then
    th := p_patch->>'theme';
    if th not in ('system', 'light', 'dark') then raise exception 'tema_invalido' using errcode = '22023'; end if;
    update profiles set theme = th where user_id = uid;
  end if;
  if p_patch ? 'preferred_workspace' then
    ws := nullif(p_patch->>'preferred_workspace', '');
    -- só um cliente a que a pessoa tem acesso; não revela se outro existe
    if ws is not null and not exists (select 1 from capabilities c where public._authorize(c.key, ws, uid)) then
      raise exception 'sem_permissao' using errcode = '42501'; end if;
    update profiles set preferred_workspace = ws where user_id = uid;
  end if;
  update profiles set updated_at = now() where user_id = uid returning * into p;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), 'profile.updated', 'profile', uid::text, before, to_jsonb(p) - 'user_id' - 'updated_at');
  return to_jsonb(p) - 'user_id';
end $$;

-- histórico de segurança da própria pessoa (FR-14-03, parte): entradas, MFA, palavra-passe, perfil
create or replace function public.my_security_log(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action) order by e.at desc), '[]')
    from (select at, action from audit_events
           where actor_user_id = auth.uid() and action in ('profile.updated', 'security.password_changed', 'security.mfa_enabled',
                 'security.mfa_disabled', 'security.signed_out_everywhere', 'invitation.accepted')
           order by at desc limit least(greatest(coalesce(p_limit, 30), 1), 100)) e
$$;

-- eventos de segurança que a app regista depois de o Supabase Auth confirmar a ação (palavra-passe, MFA, sair de todo o lado)
create or replace function public.security_event(p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_action not in ('security.password_changed', 'security.mfa_enabled', 'security.mfa_disabled', 'security.signed_out_everywhere') then
    raise exception 'evento_invalido' using errcode = '22023'; end if;
  -- no máximo 20 por hora, para o histórico não ser inundado
  if (select count(*) from audit_events where actor_user_id = uid and action like 'security.%' and at > now() - interval '1 hour') >= 20 then
    raise exception 'demasiados_eventos' using errcode = 'PT429'; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), p_action, 'user', uid::text,
          jsonb_build_object('aal', coalesce(auth.jwt() ->> 'aal', 'aal1')));
end $$;

revoke all on function public._mfa_ok(uuid) from public, anon, authenticated;
revoke all on function public.profile_update(jsonb), public.my_security_log(int), public.security_event(text) from public, anon;
grant execute on function public.profile_update(jsonb), public.my_security_log(int), public.security_event(text) to authenticated;
revoke all on function public.my_context() from public, anon;
grant execute on function public.my_context() to authenticated;

/* Rollback (compatível): repor _authorize (20261029105036), _org_can (20261029100534) e my_context (20261029103605);
drop function public.security_event(text), public.my_security_log(int), public.profile_update(jsonb), public._mfa_ok(uuid);
drop policy avatars_own_read, avatars_own_write, avatars_own_update, avatars_own_delete on storage.objects;
-- contract posterior, com o bucket vazio: delete from storage.buckets where id = 'avatars'; drop table public.profiles; */
