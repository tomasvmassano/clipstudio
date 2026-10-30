-- Parte 2 de 4 de 20261030110100_w7_pub.sql (aplicada em produção como w7_pub_p2).

-- ───────────── conflitos (PUB-04) e limites (PUB-02) ─────────────
-- Devolve [{code, severity: bloqueia|aviso, message}]. p_agency: quem vê é da agência (pode ver contagens do projeto).
create or replace function public._pub_conflicts(p pub_publications, p_agency boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'; tz text; org uuid; lim pub_platform_limits; n int; v pub_variants; ve jsonb := '{}'; other record;
        par pub_publications; pv jsonb := '{}'; g guioes; tot int; rep int; day_start timestamptz;
begin
  select coalesce(timezone, 'Asia/Dubai'), organization_id into tz, org from clients where id = p.workspace_id;
  if p.variant_id is not null then select * into v from pub_variants where id = p.variant_id; ve := coalesce(v.elements, '{}'); end if;

  -- variantes do mesmo corpo nunca na mesma conta no mesmo dia
  if exists (select 1 from pub_publications x where x.workspace_id = p.workspace_id and x.id <> p.id and x.status <> 'cancelada'
             and x.content_id = p.content_id and x.account_id = p.account_id
             and (x.scheduled_at at time zone tz)::date = (p.scheduled_at at time zone tz)::date) then
    out := out || jsonb_build_object('code', 'mesmo_dia_conta', 'severity', 'bloqueia',
      'message', 'Já há uma publicação deste guião nesta conta neste dia. Variantes do mesmo corpo nunca saem na mesma conta no mesmo dia.');
  end if;

  -- limite da API
  select * into lim from pub_platform_limits where organization_id = org and platform = p.platform;
  if lim.platform is not null then
    if lim.window_kind = 'rolling_24h' then
      select max(c) into n from (
        select (select count(*) from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
                  and y.scheduled_at >= w.s and y.scheduled_at < w.s + interval '24 hours'
                  and (case when lim.scope = 'conta' then y.account_id = p.account_id
                            else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end)) + 1 c
        from (select p.scheduled_at s union
              select y.scheduled_at from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
                and y.scheduled_at > p.scheduled_at - interval '24 hours' and y.scheduled_at <= p.scheduled_at
                and (case when lim.scope = 'conta' then y.account_id = p.account_id
                          else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end)) w) q;
    else
      day_start := ((p.scheduled_at at time zone lim.window_tz)::date)::timestamp at time zone lim.window_tz;
      select count(*) + 1 into n from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
        and y.scheduled_at >= day_start and y.scheduled_at < day_start + interval '1 day'
        and (case when lim.scope = 'conta' then y.account_id = p.account_id
                  else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end);
    end if;
    if n > lim.max_posts then
      out := out || jsonb_build_object('code', 'limite_api', 'severity', 'bloqueia', 'message',
        case when lim.scope = 'projeto' and not p_agency
             then format('O limite da API do %s para esse dia já está esgotado. Escolhe outro dia.', initcap(p.platform))
             else format('Passa o limite da API: %s de %s %s (verificado a %s).', n, lim.max_posts,
                         case when lim.scope = 'conta' then case when lim.window_kind = 'rolling_24h' then 'por conta em 24 h móveis' else 'por conta por dia' end
                              else 'por dia no projeto da agência' end, to_char(lim.verified_on, 'DD/MM/YYYY')) end);
    end if;
    if lim.public_requires_audit then
      out := out || jsonb_build_object('code', 'so_privado', 'severity', 'aviso',
        'message', 'Até à auditoria do Content Posting API, o que for publicado por API nesta plataforma fica privado.');
    end if;
  end if;

  -- VAR-01: variantes irmãs para a mesma plataforma diferem em pelo menos 2 elementos
  if p.kind = 'original' then
    for other in select x.id, coalesce(xv.elements, '{}') el, xv.label, x.variant_id from pub_publications x left join pub_variants xv on xv.id = x.variant_id
                 where x.workspace_id = p.workspace_id and x.id <> p.id and x.status <> 'cancelada' and x.kind = 'original'
                   and x.content_id = p.content_id and x.platform = p.platform loop
      if public._pub_variant_diff(ve, other.el) < 2 then
        out := out || jsonb_build_object('code', 'variante_repetida', 'severity', 'bloqueia', 'message',
          format('Nesta plataforma já está planeada %s deste guião que difere em menos de 2 dos 5 elementos (segmento, tese do título, ativo de contexto, narração, estrutura).',
                 coalesce('a variante "' || other.label || '"', 'a versão original')));
        exit;
      end if;
    end loop;
  end if;
  if p.variant_id is not null and public._pub_variant_diff(ve, '{}') < 2 then
    out := out || jsonb_build_object('code', 'variante_nao_nova', 'severity', 'aviso',
      'message', 'Esta variante muda menos de 2 dos 5 elementos em relação ao original: não conta como variante nova (layout, cor e letra contam zero).');
  end if;

  -- a versão escolhida é a aprovada editorialmente?
  select * into g from guioes where id = p.content_id;
  if g.approved_version_id is distinct from p.content_version_id then
    out := out || jsonb_build_object('code', 'versao_por_aprovar', 'severity', 'aviso',
      'message', 'Esta versão do guião não é a versão aprovada. A publicação só se aprova com a versão aprovada do guião.');
  end if;

  -- republicação (VAR-05, avisos [pressuposto])
  if p.kind = 'republicacao' and lim.platform is not null then
    select * into par from pub_publications where id = p.parent_publication_id;
    if lim.republish_min_days is not null and par.id is not null and p.scheduled_at < par.scheduled_at + make_interval(days => lim.republish_min_days) then
      out := out || jsonb_build_object('code', 'republicacao_cedo', 'severity', 'aviso',
        'message', format('Republicação a menos de %s dias da original nesta plataforma [pressuposto VAR-05].', lim.republish_min_days));
    end if;
    if not lim.republish_identical and par.id is not null then
      if par.variant_id is not null then select coalesce(elements, '{}') into pv from pub_variants where id = par.variant_id; end if;
      if public._pub_variant_diff(ve, pv) < 2 then
        out := out || jsonb_build_object('code', 'republicacao_identica', 'severity', 'aviso',
          'message', 'Esta plataforma não aceita republicações idênticas: precisa de mudar pelo menos 2 elementos [pressuposto VAR-05].');
      end if;
    end if;
    if lim.republish_max_share is not null then
      select count(*) + 1, count(*) filter (where y.kind = 'republicacao') + 1 into tot, rep from pub_publications y
       where y.account_id = p.account_id and y.status <> 'cancelada' and y.id <> p.id
         and y.scheduled_at > p.scheduled_at - interval '30 days' and y.scheduled_at <= p.scheduled_at;
      if rep::numeric / tot > lim.republish_max_share then
        out := out || jsonb_build_object('code', 'republicacao_quota', 'severity', 'aviso',
          'message', format('Republicações nesta conta nos últimos 30 dias: %s de %s, acima de %s%% [pressuposto VAR-05].', rep, tot, round(lim.republish_max_share * 100)));
      end if;
    end if;
  end if;
  return out;
end $$;

create or replace function public._pub_blocking(c jsonb) returns text
language sql immutable as $$
  select string_agg(x->>'message', ' ') from jsonb_array_elements(c) x where x->>'severity' = 'bloqueia'
$$;

-- ───────────── leitura ─────────────
create or replace function public._pub_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, p_entity);
  -- disponibilidade não é autorização, mas uma flag desligada bloqueia com erro explícito (CAP-09)
  if not public._flag_on('pub.planning', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O calendário de publicações ainda não está ligado neste cliente.';
  end if;
end $$;

create or replace function public._pub_json(p pub_publications, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); me jsonb := case when uid is not null then public._pub_actor_side(p.workspace_id, uid) end;
        agency boolean := coalesce(me->>'side', '') = 'agencia'; tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p.workspace_id);
        pol pub_approval_policies := public._pub_policy(p.workspace_id); missing text[] := public._pub_missing(p);
        cap text := case when p.kind = 'republicacao' then 'publishing.republish.approve' else 'publishing.approve' end; g guioes; cv content_versions;
        v pub_variants; acc accounts; conflicts jsonb; why text;
begin
  select * into g from guioes where id = p.content_id;
  select * into cv from content_versions where id = p.content_version_id;
  select * into acc from accounts where id = p.account_id;
  if p.variant_id is not null then select * into v from pub_variants where id = p.variant_id; end if;
  conflicts := case when p.status = 'cancelada' then '[]'::jsonb else public._pub_conflicts(p, agency) end;
  why := case
    when p.status <> 'planeada' then null
    when uid is null or not public.ws_can(cap, p.workspace_id, p_token) then 'sem_capacidade'
    when pol.forbid_self and uid in (p.created_by, p.revision_by) then 'autoaprovacao'
    when exists (select 1 from pub_approvals a where a.publication_id = p.id and a.revision = p.revision and a.actor_user_id = uid and a.invalidated_at is null) then 'ja_aprovaste'
    when cardinality(missing) > 0 and not ('qualquer' = any(missing) or (me->>'side') = any(missing)) then 'parte_errada'
    when g.approved_version_id is distinct from p.content_version_id then 'versao_por_aprovar'
    when public._pub_blocking(conflicts) is not null then 'conflito'
    when p.scheduled_at <= now() then 'hora_passada'
  end;
  return jsonb_build_object(
    'id', p.id, 'status', p.status, 'kind', p.kind, 'revision', p.revision, 'approved_revision', p.approved_revision, 'approved_at', p.approved_at,
    'lock_version', p.lock_version, 'correlation_id', p.correlation_id, 'lineage_id', p.lineage_id, 'parent_publication_id', p.parent_publication_id,
    'content_id', p.content_id, 'content_n', g.n, 'content_date', g.date, 'content_tema', g.tema, 'content_hook', g.hooks->0->>'text',
    'content_version_id', p.content_version_id, 'version_no', cv.version_no, 'version_approved', g.approved_version_id = p.content_version_id,
    'variant', case when v.id is not null then jsonb_build_object('id', v.id, 'label', v.label, 'elements', v.elements,
                 'changes', public._pub_variant_diff(v.elements, '{}'), 'counts_as_new', public._pub_variant_diff(v.elements, '{}') >= 2,
                 'edit_style_key', v.edit_style_key, 'edit_style_version', v.edit_style_version) end,
    'account_id', p.account_id, 'account_handle', acc.handle, 'account_label', acc.label, 'platform', p.platform,
    'scheduled_at', p.scheduled_at, 'local_day', (p.scheduled_at at time zone tz)::date, 'local_time', to_char(p.scheduled_at at time zone tz, 'HH24:MI'),
    'caption', p.caption, 'hashtags', to_jsonb(p.hashtags), 'cancelled_reason', p.cancelled_reason,
    'created_label', p.created_label, 'revision_label', p.revision_label, 'updated_at', p.updated_at,
    'missing', to_jsonb(case when p.status = 'planeada' then missing else '{}'::text[] end),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('side', a.side, 'actor_label', a.actor_label, 'actor_role', a.actor_role,
        'revision', a.revision, 'decided_at', a.decided_at, 'invalidated_at', a.invalidated_at, 'invalidated_reason', a.invalidated_reason) order by a.decided_at)
      from pub_approvals a where a.publication_id = p.id), '[]'),
    'conflicts', conflicts,
    'can_approve', why is null and p.status = 'planeada', 'approve_blocked', why);
end $$;

create or replace function public._pub_limits_json(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('platform', l.platform, 'max_posts', l.max_posts, 'window_kind', l.window_kind, 'window_tz', l.window_tz,
    'scope', l.scope, 'public_requires_audit', l.public_requires_audit, 'note', l.note, 'verified_on', l.verified_on,
    'republish_min_days', l.republish_min_days, 'republish_max_share', l.republish_max_share, 'republish_identical', l.republish_identical,
    'updated_at', l.updated_at, 'updated_label', l.updated_label) order by l.platform), '[]')
  from pub_platform_limits l join clients c on c.organization_id = l.organization_id where c.id = p_ws
$$;

create or replace function public.pub_calendar(p_ws text, p_from date, p_to date, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; org uuid; pol pub_approval_policies;
begin
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.calendar', null);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then raise exception 'intervalo_invalido' using errcode = '22023'; end if;
  select coalesce(timezone, 'Asia/Dubai'), organization_id into tz, org from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  pol := public._pub_policy(p_ws);
  return jsonb_build_object(
    'today', today, 'timezone', tz,
    'publications', coalesce((select jsonb_agg(public._pub_json(p, p_token) order by p.scheduled_at, p.id) from pub_publications p
       where p.workspace_id = p_ws and (p.scheduled_at at time zone tz)::date between p_from and p_to), '[]'),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'platform', a.platform, 'handle', a.handle, 'label', a.label, 'active', a.active,
         'connection_state', coalesce(s.connection_state, 'por_ligar'), 'token_expires_at', s.token_expires_at) order by a.platform, a.handle)
       from accounts a left join social_accounts s on s.account_id = a.id where a.client_id = p_ws and a.role = 'client'), '[]'),
    'limits', public._pub_limits_json(p_ws),
    'policy', jsonb_build_object('required', pol.required, 'forbid_self', pol.forbid_self, 'updated_at', pol.updated_at, 'updated_label', pol.updated_label),
    'me', case when auth.uid() is not null then public._pub_actor_side(p_ws, auth.uid()) end,
    'can', jsonb_build_object('schedule', public.ws_can('publishing.schedule', p_ws, p_token), 'approve', public.ws_can('publishing.approve', p_ws, p_token),
      'republish_approve', public.ws_can('publishing.republish.approve', p_ws, p_token), 'policy', public.ws_can('publishing.policy.manage', p_ws, p_token),
      'accounts', public.ws_can('social_accounts.manage', p_ws, p_token), 'limits', org is not null and public._org_can('publishing.limits.manage', org)),
    'publish_available', false,
    'publish_unavailable_reason', 'Publicação automática chega quando as plataformas aprovarem a app.');
end $$;

-- Guiões e versões para escolher ao planear, com as variantes de cada um e a comparação VAR-01.
create or replace function public.pub_content_options(p_ws text, p_content_id text default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.content_options', p_content_id);
  if not public.ws_can('scripts.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_content_id is null then
    return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'hook', g.hooks->0->>'text',
        'editorial_status', g.editorial_status, 'approved', g.approved_version_id is not null) order by g.date desc, g.n)
      from (select * from guioes where client_id = p_ws and editorial_status not in ('archived', 'rejected') order by date desc, n limit 200) g), '[]');
  end if;
  if not exists (select 1 from guioes where id = p_content_id and client_id = p_ws) then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'created_at', v.created_at,
        'approved', v.id = g.approved_version_id, 'current', v.id = g.current_version_id) order by v.version_no desc)
      from content_versions v join guioes g on g.id = v.content_id where v.content_id = p_content_id and v.workspace_id = p_ws), '[]'),
    'approved_version_id', (select approved_version_id from guioes where id = p_content_id),
    'variants', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'label', v.label, 'platform', v.platform, 'content_version_id', v.content_version_id,
        'edit_style_key', v.edit_style_key, 'edit_style_version', v.edit_style_version, 'elements', v.elements, 'archived', v.archived_at is not null,
        'changes', public._pub_variant_diff(v.elements, '{}'), 'counts_as_new', public._pub_variant_diff(v.elements, '{}') >= 2,
        'created_at', v.created_at, 'created_label', v.created_label,
        'siblings', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label, 'diff', public._pub_variant_diff(v.elements, o.elements)) order by o.created_at)
                              from pub_variants o where o.content_id = v.content_id and o.id <> v.id and o.archived_at is null
                                and (v.platform is null or o.platform is null or o.platform = v.platform)), '[]')) order by v.created_at)
      from pub_variants v where v.workspace_id = p_ws and v.content_id = p_content_id), '[]'),
    'styles', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'version', s.current_version, 'name', sv.name) order by s.key)
      from edit_styles s join edit_style_versions sv on sv.workspace_id = s.workspace_id and sv.key = s.key and sv.version = s.current_version
      where s.workspace_id = p_ws and s.status = 'ativo'), '[]'));
end $$;

-- ───────────── escrita: variantes ─────────────
create or replace function public.pub_variant_save(p_ws text, p_input jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes; cv content_versions; el jsonb; v pub_variants; o record; plat text; sup pub_variants;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.variant_save', p_input->>'content_id');
  if jsonb_typeof(coalesce(p_input, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  select * into g from guioes where id = p_input->>'content_id' and client_id = p_ws;
  if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
  select * into cv from content_versions where id = coalesce(nullif(p_input->>'content_version_id', '')::uuid, g.approved_version_id, g.current_version_id)
    and content_id = g.id and workspace_id = p_ws;
  if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Escolhe uma versão deste guião.'; end if;
  if char_length(btrim(coalesce(p_input->>'label', ''))) not between 1 and 80 then
    raise exception 'nome_invalido' using errcode = '22023', detail = 'Dá um nome à variante (1 a 80 caracteres).'; end if;
  plat := nullif(p_input->>'platform', '');
  if plat is not null and plat not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
  el := public._pub_elements_clean(p_input->'elements');
  if nullif(p_input->>'edit_style_key', '') is not null and not exists (select 1 from edit_style_versions where workspace_id = p_ws
       and key = p_input->>'edit_style_key' and version = nullif(p_input->>'edit_style_version', '')::int) then
    raise exception 'estilo_invalido' using errcode = '22023', detail = 'Estilo e versão têm de existir neste cliente.'; end if;
  if nullif(p_input->>'supersedes_id', '') is not null then
    select * into sup from pub_variants where id = (p_input->>'supersedes_id')::uuid and workspace_id = p_ws and content_id = g.id;
    if sup.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
  end if;
  -- VAR-01: variantes irmãs para a mesma plataforma diferem em >= 2 elementos (bloqueia)
  if plat is not null then
    for o in select * from pub_variants x where x.workspace_id = p_ws and x.content_id = g.id and x.archived_at is null and x.platform = plat
               and (sup.id is null or x.id <> sup.id) loop
      if public._pub_variant_diff(el, o.elements) < 2 then
        raise exception 'variante_repetida' using errcode = '22023',
          detail = format('Difere da variante "%s" (mesma plataforma) em menos de 2 dos 5 elementos.', o.label); end if;
    end loop;
  end if;
  insert into pub_variants (workspace_id, content_id, content_version_id, label, platform, edit_style_key, edit_style_version, elements, supersedes_id, created_by, created_label)
  values (p_ws, g.id, cv.id, btrim(p_input->>'label'), plat, nullif(p_input->>'edit_style_key', ''),
          case when nullif(p_input->>'edit_style_key', '') is not null then nullif(p_input->>'edit_style_version', '')::int end, el, sup.id,
          (a->>'uid')::uuid, a->>'label')
  returning * into v;
  if sup.id is not null then update pub_variants set archived_at = now() where id = sup.id and archived_at is null; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.variant_created', 'pub_variant', v.id::text, null, to_jsonb(v) - 'workspace_id');
  return public.pub_content_options(p_ws, g.id, p_token);
end $$;

create or replace function public.pub_variant_archive(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); v pub_variants;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.variant_archive', p_id::text);
  select * into v from pub_variants where id = p_id and workspace_id = p_ws for update;
  if v.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
  if v.archived_at is null then
    update pub_variants set archived_at = now() where id = v.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.variant_archived', 'pub_variant', v.id::text);
  end if;
  return public.pub_content_options(p_ws, v.content_id, p_token);
end $$;
