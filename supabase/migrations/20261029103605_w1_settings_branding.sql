-- W1-07: definições do cliente: geral com logótipo e cor, regras (PRD M15 FR-15-01, FR-15-02 parcial, FR-15-08 parcial; ADR-0013).
-- Só aditivo. Rollback: bloco no fim.

alter table public.clients add column if not exists logo_path text,
  add column if not exists brand_color text check (brand_color is null or brand_color ~ '^#[0-9a-f]{6}$');

-- logótipos: bucket privado; lê quem trabalha no cliente, escreve quem gere as definições (R-02: storage com a mesma fronteira)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('branding', 'branding', false, 512000, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public._branding_ws(p_name text) returns text language sql immutable set search_path = public as $$
  select case when p_name ~ '^[a-z0-9_-]{1,60}/logo-[a-z0-9]{8,40}\.(png|jpg|webp)$' then split_part(p_name, '/', 1) end
$$;

drop policy if exists branding_read on storage.objects;
create policy branding_read on storage.objects for select to authenticated
  using (bucket_id = 'branding' and (public.authorize('scripts.read', public._branding_ws(name)) or public.authorize('team.read', public._branding_ws(name))));
drop policy if exists branding_insert on storage.objects;
create policy branding_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'branding' and public.authorize('settings.manage', public._branding_ws(name)));
drop policy if exists branding_update on storage.objects;
create policy branding_update on storage.objects for update to authenticated
  using (bucket_id = 'branding' and public.authorize('settings.manage', public._branding_ws(name)))
  with check (bucket_id = 'branding' and public.authorize('settings.manage', public._branding_ws(name)));
drop policy if exists branding_delete on storage.objects;
create policy branding_delete on storage.objects for delete to authenticated
  using (bucket_id = 'branding' and public.authorize('settings.manage', public._branding_ws(name)));

-- ler as definições do cliente (quem trabalha nele) e o que cada um pode mudar
create or replace function public.workspace_settings(p_ws text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not (public._authorize('team.read', p_ws, uid) or public._authorize('settings.manage', p_ws, uid)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into c from clients where id = p_ws;
  return jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
    'logo_path', c.logo_path, 'brand_color', c.brand_color, 'require_approval_to_record', c.require_approval_to_record,
    'wip_limit', c.wip_limit, 'created_at', c.created_at,
    'agent_config', (select status from agent_config_versions v where v.workspace_id = c.id order by (v.status = 'active') desc, v.version_no desc limit 1),
    'counts', jsonb_build_object('templates', (select count(*) from task_templates where workspace_id = c.id and active),
                                 'automacoes', (select count(*) from task_rules where workspace_id = c.id and active)),
    'can', jsonb_build_object('manage', public._authorize('settings.manage', p_ws, uid), 'tasks', public._authorize('tasks.manage', p_ws, uid),
                              'agents', public._authorize('agents.configure', p_ws, uid),
                              'archive', public._org_can('workspaces.archive', c.organization_id, uid)));
end $$;

-- editar: passa a aceitar logótipo (só um ficheiro que já existe no bucket deste cliente) e cor
create or replace function public.workspace_update(p_ws text, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c clients; k text; b jsonb; lp text;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('settings.manage', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'workspace.update');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  for k in select jsonb_object_keys(coalesce(p_patch, '{}')) loop
    if k not in ('name','handle','timezone','currency','require_approval_to_record','logo_path','brand_color') then
      raise exception 'campo_desconhecido:%', k using errcode = '22023';
    end if;
  end loop;
  if coalesce(p_patch, '{}') = '{}' then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  select * into c from clients where id = p_ws for update;
  b := jsonb_build_object('name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
                          'require_approval_to_record', c.require_approval_to_record, 'logo_path', c.logo_path, 'brand_color', c.brand_color);
  c.name := coalesce(btrim(p_patch->>'name'), c.name);
  if p_patch ? 'handle' then c.handle := nullif(ltrim(lower(btrim(coalesce(p_patch->>'handle', ''))), '@'), ''); end if;
  c.timezone := coalesce(p_patch->>'timezone', c.timezone);
  c.currency := upper(coalesce(p_patch->>'currency', c.currency));
  c.require_approval_to_record := coalesce((p_patch->>'require_approval_to_record')::boolean, c.require_approval_to_record);
  if p_patch ? 'logo_path' then
    lp := nullif(p_patch->>'logo_path', '');
    if lp is not null and (public._branding_ws(lp) is distinct from p_ws
                           or not exists (select 1 from storage.objects o where o.bucket_id = 'branding' and o.name = lp)) then
      raise exception 'logotipo_invalido' using errcode = '22023';
    end if;
    c.logo_path := lp;
  end if;
  if p_patch ? 'brand_color' then
    c.brand_color := nullif(lower(btrim(coalesce(p_patch->>'brand_color', ''))), '');
    if c.brand_color is not null and c.brand_color !~ '^#[0-9a-f]{6}$' then raise exception 'cor_invalida' using errcode = '22023'; end if;
  end if;
  perform public._ws_validate(c.name, c.handle, c.timezone, c.currency);
  update clients set name = c.name, handle = c.handle, timezone = c.timezone, currency = c.currency,
                     require_approval_to_record = c.require_approval_to_record, logo_path = c.logo_path, brand_color = c.brand_color
   where id = p_ws;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', c.organization_id, p_ws, 'workspace.updated', 'workspace', p_ws, b,
          jsonb_build_object('name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
                             'require_approval_to_record', c.require_approval_to_record, 'logo_path', c.logo_path, 'brand_color', c.brand_color));
  return jsonb_build_object('id', p_ws, 'name', c.name, 'handle', c.handle, 'timezone', c.timezone, 'currency', c.currency,
                            'require_approval_to_record', c.require_approval_to_record, 'logo_path', c.logo_path, 'brand_color', c.brand_color);
end $$;

-- o contexto leva o logótipo e a cor para o seletor de cliente
create or replace function public.my_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then return null; end if;
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'confirmed', u.email_confirmed_at is not null) from auth.users u where u.id = uid),
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

revoke all on function public.workspace_settings(text) from public, anon;
grant execute on function public.workspace_settings(text) to authenticated;
grant execute on function public._branding_ws(text) to authenticated;   -- usada nas políticas do storage

/* Rollback:
drop policy branding_read on storage.objects; drop policy branding_insert on storage.objects;
drop policy branding_update on storage.objects; drop policy branding_delete on storage.objects;
-- esvaziar o bucket no painel e depois: delete from storage.buckets where id = 'branding';
drop function workspace_settings(text);
-- workspace_update e my_context: recriar as versões de 20261029100534
drop function _branding_ws(text);
alter table clients drop column logo_path, drop column brand_color;
*/
