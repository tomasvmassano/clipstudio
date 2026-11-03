-- W8 · Notificações por evento, parte 2: regras no servidor, RPCs e a nova _notify. ADR-0040.
-- _notify mantém a assinatura, o security definer, a regra "só quem tem acesso recebe, quem age não se notifica" e a
-- deduplicação (user_id, dedup_key). A única diferença: com a flag notifications.prefs ligada PARA QUEM RECEBE, um tipo
-- não obrigatório pode não ser criado por preferência do cliente, da pessoa ou por silêncio; conta em
-- notification_suppressions. Sem flag, ou sem preferências gravadas, cria-se exatamente o mesmo que antes.

-- A flag está ligada para uma pessoa concreta (quem recebe, não quem age)? Mesma regra de _flag_on.
create or replace function public._flag_on_for(p_key text, p_ws text, p_uid uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare org uuid; st text; role text;
begin
  select organization_id into org from clients where id = p_ws;
  if org is null then return false; end if;
  st := public._flag_stage(p_key, org, p_ws);
  if st = 'off' then return false; end if;
  if st = 'all' then return true; end if;
  if p_uid is null then return false; end if;
  select agency_role into role from agency_memberships where user_id = p_uid and organization_id = org and status = 'active';
  if role is null then return false; end if;
  return st = 'agency' or role = 'agency_owner';
end $$;

-- Porque é que esta notificação "na app" não se cria? null = cria-se. Ordem: obrigatório (catálogo ou cliente) ganha a tudo;
-- depois o cliente desligou; depois a pessoa silenciou o cliente; depois a pessoa desligou o tipo.
create or replace function public._notif_suppress_reason(p_user uuid, p_ws text, p_kind text) returns text
language plpgsql stable security definer set search_path = public as $$
declare d notification_event_defs; w notification_ws_prefs; mine boolean;
begin
  if not public._flag_on_for('notifications.prefs', p_ws, p_user) then return null; end if;
  select * into d from notification_event_defs where kind = p_kind;
  if d.kind is null or d.mandatory then return null; end if;            -- tipo fora do catálogo: comportamento de sempre
  select * into w from notification_ws_prefs where workspace_id = p_ws and kind = p_kind and channel = 'in_app';
  if w.required then return null; end if;
  if w.kind is not null and not w.enabled then return 'org_off'; end if;
  if exists (select 1 from notification_mutes m where m.user_id = p_user and m.workspace_id = p_ws
              and (m.muted_until is null or m.muted_until > now())) then return 'muted'; end if;
  select enabled into mine from notification_user_prefs where user_id = p_user and workspace_id = p_ws and kind = p_kind and channel = 'in_app';
  if mine is false then return 'user_off'; end if;
  return null;
end $$;

create or replace function public._notify(p_user uuid, p_ws text, p_kind text, p_entity_type text, p_entity_id text,
                                          p_title text, p_body text, p_dedup text) returns void
language plpgsql security definer set search_path = public as $$
declare why text;
begin
  -- só quem tem acesso atual recebe (TEAM-12); quem age não se notifica a si próprio
  if p_user is null or p_user is not distinct from auth.uid() or not public._authorize('tasks.read', p_ws, p_user) then return; end if;
  -- já existe (repetição do mesmo evento): nada a fazer, como antes
  if exists (select 1 from notifications where user_id = p_user and dedup_key = p_dedup) then return; end if;
  why := public._notif_suppress_reason(p_user, p_ws, p_kind);
  if why is not null then
    insert into notification_suppressions as s (workspace_id, user_id, kind, reason, day, last_dedup)
    values (p_ws, p_user, p_kind, why, (now() at time zone 'utc')::date, p_dedup)
    on conflict (workspace_id, user_id, kind, reason, day) do update
      set n = s.n + 1, last_at = now(), last_dedup = excluded.last_dedup
      where s.last_dedup is distinct from excluded.last_dedup;            -- a mesma repetição não conta duas vezes
    return;
  end if;
  insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key)
  values (p_user, p_ws, p_kind, p_entity_type, p_entity_id, left(p_title, 200), left(p_body, 500), p_dedup)
  on conflict (user_id, dedup_key) do nothing;
end $$;

-- ───────────── auxiliares de leitura ─────────────
create or replace function public._notif_channels_json() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label, 'available', c.available,
           'unavailable_reason', c.unavailable_reason) order by c.sort), '[]')
  from notification_channel_defs c
$$;

-- Estado do cliente por tipo e canal: ligado (predefinição ou linha gravada), obrigatório, travado pelo catálogo.
create or replace function public._notif_ws_json(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', d.kind, 'group', d.group_key, 'label', d.label, 'description', d.description, 'recipients', d.recipients,
           'mandatory', d.mandatory, 'mandatory_reason', d.mandatory_reason,
           'channels', (select jsonb_agg(jsonb_build_object(
                          'channel', c.key,
                          'enabled', d.mandatory and c.key = 'in_app' or coalesce(w.enabled, c.key = any (d.default_channels)),
                          'default', c.key = any (d.default_channels),
                          'required', d.mandatory and c.key = 'in_app' or coalesce(w.required, false),
                          'customized', w.kind is not null) order by c.sort)
                        from notification_channel_defs c
                        left join notification_ws_prefs w on w.workspace_id = p_ws and w.kind = d.kind and w.channel = c.key
                        where c.key = any (d.channels)))
         order by d.sort), '[]')
  from notification_event_defs d
$$;

-- ───────────── definições do cliente ─────────────
-- Ver: quem vê Definições (team.read). Mudar: settings.manage. Contagens de supressão só para quem gere (são de toda a equipa).
create or replace function public.notif_settings(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare can_manage boolean;
begin
  if auth.uid() is null then raise exception 'sem_permissao' using errcode = '42501', detail = 'As definições de notificações só abrem com conta própria.'; end if;
  perform public._content_require('team.read', p_ws, null, 'notif.settings', p_ws);
  can_manage := public._authorize('settings.manage', p_ws);
  if not public._flag_on('notifications.prefs', p_ws, null) then
    return jsonb_build_object('enabled', false, 'can_manage', can_manage);
  end if;
  return jsonb_build_object('enabled', true, 'can_manage', can_manage,
    'channels', public._notif_channels_json(),
    'events', public._notif_ws_json(p_ws),
    'suppressed_30d', case when can_manage then
       (select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'reason', x.reason, 'n', x.n) order by x.kind, x.reason), '[]')
          from (select kind, reason, sum(n)::int n from notification_suppressions
                 where workspace_id = p_ws and day >= (now() at time zone 'utc')::date - 30 group by kind, reason) x)
       else null end);
end $$;

-- Ligar/desligar um tipo num canal para o cliente inteiro, e marcar "na app" como obrigatório (p_required).
-- Voltar à predefinição apaga a linha. Fica no histórico com antes/depois.
create or replace function public.notif_settings_set(p_ws text, p_kind text, p_channel text, p_enabled boolean,
                                                     p_required boolean default false, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d notification_event_defs; old notification_ws_prefs; req boolean := coalesce(p_required, false); is_default boolean;
begin
  if uid is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  perform public._content_require('settings.manage', p_ws, null, 'notif.ws_pref_set', p_ws);
  if not public._flag_on('notifications.prefs', p_ws, null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
  select * into d from notification_event_defs where kind = p_kind;
  if d.kind is null then raise exception 'evento_desconhecido' using errcode = '22023', detail = 'Tipo de notificação desconhecido.'; end if;
  if p_channel is null or not (p_channel = any (d.channels)) then
    raise exception 'canal_invalido' using errcode = '22023', detail = 'Este canal não existe para este tipo de notificação.'; end if;
  if p_enabled is null then raise exception 'valor_invalido' using errcode = '22023'; end if;
  if d.mandatory and p_channel = 'in_app' then
    raise exception 'evento_obrigatorio' using errcode = '22023', detail = d.mandatory_reason; end if;
  if req and (p_channel <> 'in_app' or not p_enabled) then
    raise exception 'obrigatorio_so_na_app' using errcode = '22023', detail = 'Só "na app" pode ser obrigatório, e tem de estar ligado.'; end if;
  select * into old from notification_ws_prefs where workspace_id = p_ws and kind = p_kind and channel = p_channel;
  is_default := not req and p_enabled = (p_channel = any (d.default_channels));
  if is_default then
    delete from notification_ws_prefs where workspace_id = p_ws and kind = p_kind and channel = p_channel;
  else
    insert into notification_ws_prefs (workspace_id, kind, channel, enabled, required, updated_by)
    values (p_ws, p_kind, p_channel, p_enabled, req, uid)
    on conflict (workspace_id, kind, channel) do update set enabled = excluded.enabled, required = excluded.required,
      updated_at = now(), updated_by = excluded.updated_by;
  end if;
  if old.kind is null and is_default or old.enabled is not distinct from p_enabled and old.required is not distinct from req then
    return public.notif_settings(p_ws);                                  -- nada mudou: sem histórico
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'notif.ws_pref_set', 'notification_pref', p_kind || ':' || p_channel,
          case when old.kind is null then null else jsonb_build_object('enabled', old.enabled, 'required', old.required) end,
          jsonb_build_object('enabled', p_enabled, 'required', req));
  return public.notif_settings(p_ws);
end $$;

-- ───────────── preferências pessoais ─────────────
create or replace function public._notif_require_me(p_ws text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'sem_permissao' using errcode = '42501', detail = 'As preferências são de quem entra com conta própria.'; end if;
  if p_ws is null or not public._authorize('tasks.read', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'notif.my_prefs');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return uid;
end $$;

-- Clientes onde a pessoa pode receber notificações e onde a funcionalidade está ligada para ela.
create or replace function public.my_notif_workspaces() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name,
            'muted', m.user_id is not null and (m.muted_until is null or m.muted_until > now()),
            'muted_until', case when m.muted_until > now() then m.muted_until end) order by c.name), '[]')
          from clients c
          left join notification_mutes m on m.user_id = uid and m.workspace_id = c.id
          where coalesce(c.status, 'active') <> 'archived'
            and public._authorize('tasks.read', c.id, uid)
            and public._flag_on('notifications.prefs', c.id, null));
end $$;

create or replace function public.my_notif_prefs(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := public._notif_require_me(p_ws); m notification_mutes;
begin
  if not public._flag_on('notifications.prefs', p_ws, null) then return jsonb_build_object('enabled', false); end if;
  select * into m from notification_mutes where user_id = uid and workspace_id = p_ws;
  return jsonb_build_object('enabled', true,
    'workspace', (select jsonb_build_object('id', id, 'name', name, 'timezone', timezone) from clients where id = p_ws),
    'channels', public._notif_channels_json(),
    'muted', m.user_id is not null and (m.muted_until is null or m.muted_until > now()),
    'muted_until', case when m.muted_until > now() then m.muted_until end,
    'events', (select coalesce(jsonb_agg(e || jsonb_build_object('channels',
                 (select jsonb_agg(ch || jsonb_build_object(
                     'allowed', (ch->>'enabled')::boolean,
                     'locked', (ch->>'required')::boolean,
                     'mine', coalesce(p.enabled, (ch->>'default')::boolean),
                     'effective', (ch->>'enabled')::boolean and ((ch->>'required')::boolean or coalesce(p.enabled, (ch->>'default')::boolean)))
                   - 'customized')
                  from jsonb_array_elements(e->'channels') ch
                  left join notification_user_prefs p on p.user_id = uid and p.workspace_id = p_ws and p.kind = e->>'kind' and p.channel = ch->>'channel'))
               ), '[]')
               from jsonb_array_elements(public._notif_ws_json(p_ws)) e),
    'suppressed_30d', (select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'reason', x.reason, 'n', x.n) order by x.kind, x.reason), '[]')
          from (select kind, reason, sum(n)::int n from notification_suppressions
                 where workspace_id = p_ws and user_id = uid and day >= (now() at time zone 'utc')::date - 30 group by kind, reason) x));
end $$;

-- A pessoa liga/desliga um tipo num canal, dentro do que o cliente permite. Obrigatório não se desliga.
create or replace function public.my_notif_pref_set(p_ws text, p_kind text, p_channel text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._notif_require_me(p_ws); d notification_event_defs; w notification_ws_prefs; old boolean;
        allowed boolean; locked boolean;
begin
  if not public._flag_on('notifications.prefs', p_ws, null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
  select * into d from notification_event_defs where kind = p_kind;
  if d.kind is null then raise exception 'evento_desconhecido' using errcode = '22023', detail = 'Tipo de notificação desconhecido.'; end if;
  if p_channel is null or not (p_channel = any (d.channels)) then
    raise exception 'canal_invalido' using errcode = '22023', detail = 'Este canal não existe para este tipo de notificação.'; end if;
  if p_enabled is null then raise exception 'valor_invalido' using errcode = '22023'; end if;
  select * into w from notification_ws_prefs where workspace_id = p_ws and kind = p_kind and channel = p_channel;
  locked := d.mandatory and p_channel = 'in_app' or coalesce(w.required, false);
  allowed := locked or coalesce(w.enabled, p_channel = any (d.default_channels));
  if locked and not p_enabled then
    raise exception 'evento_obrigatorio' using errcode = '22023', detail = coalesce(d.mandatory_reason, 'Este cliente tornou esta notificação obrigatória.'); end if;
  if not allowed then
    raise exception 'desligado_no_cliente' using errcode = '22023', detail = 'Este cliente desligou esta notificação neste canal. Fala com quem gere as definições.'; end if;
  select enabled into old from notification_user_prefs where user_id = uid and workspace_id = p_ws and kind = p_kind and channel = p_channel;
  if p_enabled = (p_channel = any (d.default_channels)) then
    delete from notification_user_prefs where user_id = uid and workspace_id = p_ws and kind = p_kind and channel = p_channel;
  else
    insert into notification_user_prefs (user_id, workspace_id, kind, channel, enabled) values (uid, p_ws, p_kind, p_channel, p_enabled)
    on conflict (user_id, workspace_id, kind, channel) do update set enabled = excluded.enabled, updated_at = now();
  end if;
  if coalesce(old, p_channel = any (d.default_channels)) is distinct from p_enabled then
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
    values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'notif.my_pref_set', 'notification_pref', p_kind || ':' || p_channel,
            jsonb_build_object('enabled', coalesce(old, p_channel = any (d.default_channels))), jsonb_build_object('enabled', p_enabled));
  end if;
  return public.my_notif_prefs(p_ws);
end $$;

-- Silenciar este cliente para mim: p_muted false desliga; p_until nulo = até desligar (no máximo 90 dias se tiver fim).
-- Obrigatórios continuam a chegar.
create or replace function public.my_notif_mute(p_ws text, p_muted boolean, p_until timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._notif_require_me(p_ws); was boolean;
begin
  if not public._flag_on('notifications.prefs', p_ws, null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
  if p_muted is null then raise exception 'valor_invalido' using errcode = '22023'; end if;
  if p_muted and p_until is not null and (p_until <= now() or p_until > now() + interval '90 days') then
    raise exception 'prazo_invalido' using errcode = '22023', detail = 'Escolhe um fim entre agora e 90 dias.'; end if;
  was := exists (select 1 from notification_mutes where user_id = uid and workspace_id = p_ws and (muted_until is null or muted_until > now()));
  if p_muted then
    insert into notification_mutes (user_id, workspace_id, muted_until) values (uid, p_ws, p_until)
    on conflict (user_id, workspace_id) do update set muted_until = excluded.muted_until, created_at = now();
  else
    delete from notification_mutes where user_id = uid and workspace_id = p_ws;
  end if;
  if was or p_muted then
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
    values (uid, 'user', (select email from auth.users where id = uid), p_ws, 'notif.mute_set', 'notification_mute', p_ws,
            jsonb_build_object('muted', was), jsonb_build_object('muted', p_muted, 'until', p_until));
  end if;
  return public.my_notif_prefs(p_ws);
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public._flag_on_for(text, text, uuid), public._notif_suppress_reason(uuid, text, text),
  public._notif_channels_json(), public._notif_ws_json(text), public._notif_require_me(text) from public, anon, authenticated;
revoke all on function public._notify(uuid,text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.notif_settings(text, text), public.notif_settings_set(text, text, text, boolean, boolean, text),
  public.my_notif_workspaces(), public.my_notif_prefs(text), public.my_notif_pref_set(text, text, text, boolean),
  public.my_notif_mute(text, boolean, timestamptz) from public, anon;
grant execute on function public.notif_settings(text, text), public.notif_settings_set(text, text, text, boolean, boolean, text),
  public.my_notif_workspaces(), public.my_notif_prefs(text), public.my_notif_pref_set(text, text, text, boolean),
  public.my_notif_mute(text, boolean, timestamptz) to authenticated;

/* Rollback (compatível): repor _notify como em 20261029071504_w3_tasks_handoffs_inbox.sql (sem a leitura de preferências):
   create or replace function public._notify(p_user uuid, p_ws text, p_kind text, p_entity_type text, p_entity_id text,
     p_title text, p_body text, p_dedup text) returns void language plpgsql security definer set search_path = public as $f$
   begin
     if p_user is null or p_user is not distinct from auth.uid() or not public._authorize('tasks.read', p_ws, p_user) then return; end if;
     insert into notifications (user_id, workspace_id, kind, entity_type, entity_id, title, body, dedup_key)
     values (p_user, p_ws, p_kind, p_entity_type, p_entity_id, left(p_title, 200), left(p_body, 500), p_dedup)
     on conflict (user_id, dedup_key) do nothing;
   end $f$;
   drop function public.my_notif_mute(text, boolean, timestamptz), public.my_notif_pref_set(text, text, text, boolean),
     public.my_notif_prefs(text), public.my_notif_workspaces(), public._notif_require_me(text),
     public.notif_settings_set(text, text, text, boolean, boolean, text), public.notif_settings(text, text),
     public._notif_ws_json(text), public._notif_channels_json(), public._notif_suppress_reason(uuid, text, text),
     public._flag_on_for(text, text, uuid);
   Depois o rollback de p1. Preferências gravadas perdem-se (não há dados de negócio nelas). */
