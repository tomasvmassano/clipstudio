-- Parte 3 de 4 de 20261030110100_w7_pub.sql (aplicada em produção como w7_pub_p3).

-- ───────────── escrita: planear / mudar / cancelar ─────────────
-- p_id nulo cria. Ao mudar, p_lock é o lock_version que a pessoa via (conflito PT409 se mudou). Campos ausentes mantêm-se.
create or replace function public.pub_save(p_ws text, p_id uuid, p_input jsonb, p_lock int default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); cur pub_publications; n pub_publications; g guioes; cv content_versions; acc accounts;
        v pub_variants; par pub_publications; tags text[]; t text; blk text; tz text; me jsonb; created boolean := p_id is null;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, case when created then 'pub.plan' else 'pub.update' end, p_id::text);
  if (a->>'uid') is null then raise exception 'identidade_individual' using errcode = '42501', detail = 'Planear publicações exige sessão individual.'; end if;
  if jsonb_typeof(coalesce(p_input, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if not created then
    select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
    if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
    if cur.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
    if p_lock is not null and p_lock <> cur.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
    n := cur;
  else
    n.id := gen_random_uuid(); n.workspace_id := p_ws; n.kind := 'original'; n.caption := ''; n.hashtags := '{}';
  end if;

  if p_input ? 'content_id' or created then
    select * into g from guioes where id = coalesce(p_input->>'content_id', n.content_id) and client_id = p_ws;
    if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
    if g.editorial_status in ('archived', 'rejected') then raise exception 'nao_elegivel' using errcode = '22023', detail = 'Guiões rejeitados ou arquivados não se publicam.'; end if;
    if not created and g.id <> cur.content_id then raise exception 'conteudo_fixo' using errcode = '22023', detail = 'Para outro guião, planeia uma publicação nova.'; end if;
    n.content_id := g.id;
  else select * into g from guioes where id = n.content_id; end if;
  if p_input ? 'content_version_id' or created then
    select * into cv from content_versions where id = coalesce(nullif(p_input->>'content_version_id', '')::uuid, g.approved_version_id, g.current_version_id)
      and content_id = g.id and workspace_id = p_ws;
    if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Escolhe uma versão deste guião.'; end if;
    n.content_version_id := cv.id;
  end if;
  if p_input ? 'variant_id' then n.variant_id := nullif(p_input->>'variant_id', '')::uuid; end if;
  if n.variant_id is not null then
    select * into v from pub_variants where id = n.variant_id and workspace_id = p_ws and content_id = n.content_id;
    if v.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
    if v.archived_at is not null and (created or n.variant_id is distinct from cur.variant_id) then
      raise exception 'variante_arquivada' using errcode = '22023', detail = 'Esta variante foi arquivada.'; end if;
    if v.content_version_id <> n.content_version_id then
      raise exception 'variante_de_outra_versao' using errcode = '22023', detail = 'A variante foi feita a partir de outra versão do guião.'; end if;
  end if;
  if p_input ? 'account_id' or created then
    select * into acc from accounts where id = coalesce(p_input->>'account_id', n.account_id) and client_id = p_ws and role = 'client';
    if acc.id is null then raise exception 'conta_nao_encontrada' using errcode = 'P0002', detail = 'A conta não é deste cliente.'; end if;
    if not acc.active then raise exception 'conta_inativa' using errcode = '22023', detail = 'Esta conta está inativa.'; end if;
    if acc.platform not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
    n.account_id := acc.id; n.platform := acc.platform;
  end if;
  if p_input ? 'scheduled_at' or created then
    n.scheduled_at := nullif(p_input->>'scheduled_at', '')::timestamptz;
    if n.scheduled_at is null then raise exception 'hora_obrigatoria' using errcode = '22023', detail = 'Indica o dia e a hora.'; end if;
    if n.scheduled_at <= now() then raise exception 'hora_passada' using errcode = '22023', detail = 'A hora tem de ser no futuro.'; end if;
    if n.scheduled_at > now() + interval '400 days' then raise exception 'data_longe' using errcode = '22023', detail = 'No máximo 400 dias à frente.'; end if;
  end if;
  if p_input ? 'caption' then
    if char_length(coalesce(p_input->>'caption', '')) > 2200 then raise exception 'legenda_longa' using errcode = '22023', detail = 'Legenda até 2200 caracteres.'; end if;
    n.caption := btrim(coalesce(p_input->>'caption', ''));
  end if;
  if p_input ? 'hashtags' then
    if jsonb_typeof(p_input->'hashtags') <> 'array' then raise exception 'hashtags_invalidas' using errcode = '22023'; end if;
    tags := '{}';
    for t in select btrim(x) from jsonb_array_elements_text(p_input->'hashtags') x loop
      if t = '' then continue; end if;
      if left(t, 1) <> '#' then t := '#' || t; end if;
      if t !~ '^#[^\s#]{1,100}$' then raise exception 'hashtags_invalidas' using errcode = '22023', detail = format('Hashtag inválida: %s', t); end if;
      if not t = any(tags) then tags := tags || t; end if;
    end loop;
    if cardinality(tags) > 30 then raise exception 'hashtags_invalidas' using errcode = '22023', detail = 'No máximo 30 hashtags.'; end if;
    n.hashtags := tags;
  end if;
  if created and p_input ? 'kind' then
    if p_input->>'kind' not in ('original', 'republicacao') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
    n.kind := p_input->>'kind';
  end if;
  if created and n.kind = 'republicacao' then
    select * into par from pub_publications where id = nullif(p_input->>'parent_publication_id', '')::uuid and workspace_id = p_ws and content_id = n.content_id;
    if par.id is null or par.status = 'cancelada' then
      raise exception 'origem_republicacao_invalida' using errcode = '22023', detail = 'Indica a publicação original (do mesmo guião, não cancelada).'; end if;
    if par.scheduled_at >= n.scheduled_at then
      raise exception 'origem_republicacao_invalida' using errcode = '22023', detail = 'A republicação tem de ser depois da original.'; end if;
    n.parent_publication_id := par.id;
  end if;

  if not created and public._pub_snapshot(n) is not distinct from public._pub_snapshot(cur) then
    return public._pub_json(cur, p_token);
  end if;
  me := public._pub_actor_side(p_ws, (a->>'uid')::uuid);
  blk := public._pub_blocking(public._pub_conflicts(n, coalesce(me->>'side', '') = 'agencia'));
  if blk is not null then raise exception 'conflito_publicacao' using errcode = '22023', detail = blk; end if;

  if created then
    insert into pub_publications (id, workspace_id, content_id, content_version_id, variant_id, account_id, platform, scheduled_at, caption, hashtags, kind,
      parent_publication_id, created_by, created_label, revision_by, revision_label)
    values (n.id, p_ws, n.content_id, n.content_version_id, n.variant_id, n.account_id, n.platform, n.scheduled_at, n.caption, n.hashtags, n.kind,
      n.parent_publication_id, (a->>'uid')::uuid, a->>'label', (a->>'uid')::uuid, a->>'label')
    returning * into n;
  else
    update pub_publications set content_version_id = n.content_version_id, variant_id = n.variant_id, account_id = n.account_id, platform = n.platform,
      scheduled_at = n.scheduled_at, caption = n.caption, hashtags = n.hashtags, revision_by = (a->>'uid')::uuid, revision_label = a->>'label'
     where id = cur.id returning * into n;
  end if;
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when created then 'pub.planned' else 'pub.changed' end, 'pub_publication', n.id::text,
          case when created then null else public._pub_snapshot(cur) || jsonb_build_object('status', cur.status, 'revision', cur.revision) end,
          public._pub_snapshot(n) || jsonb_build_object('status', n.status, 'revision', n.revision), n.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, case when created then 'publication.planned' when cur.status = 'aprovada' then 'publication.approval_invalidated' else 'publication.changed' end,
          'publication', n.id::text, jsonb_build_object('revision', n.revision, 'from_status', cur.status, 'status', n.status,
          'scheduled_at', n.scheduled_at, 'local_day', (n.scheduled_at at time zone tz)::date, 'account_id', n.account_id));
  return public._pub_json(n, p_token);
end $$;

create or replace function public.pub_cancel(p_ws text, p_id uuid, p_reason text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); cur pub_publications; n pub_publications;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.cancel', p_id::text);
  select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
  if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if cur.status = 'cancelada' then return public._pub_json(cur, p_token); end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 500 then
    raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Explica porque cancelas (3 a 500 caracteres).'; end if;
  update pub_publications set status = 'cancelada', approved_revision = null, approved_at = null, cancelled_reason = btrim(p_reason) where id = cur.id returning * into n;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.cancelled', 'pub_publication', n.id::text,
          jsonb_build_object('status', cur.status), jsonb_build_object('status', 'cancelada', 'reason', btrim(p_reason)), n.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'publication.cancelled', 'publication', n.id::text, jsonb_build_object('from_status', cur.status, 'revision', n.revision));
  return public._pub_json(n, p_token);
end $$;

-- ───────────── PUB-06 / TEAM-10 / FR-21-02: aprovar ─────────────
-- p_revision é a revisão que a pessoa estava a ver: se entretanto mudou, recusa (40001) em vez de aprovar outra coisa.
create or replace function public.pub_approve(p_ws text, p_id uuid, p_revision int, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a jsonb; cur pub_publications; n pub_publications; cap text; pol pub_approval_policies; me jsonb; missing text[];
        g guioes; blk text; snap jsonb;
begin
  select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
  cap := case when cur.kind = 'republicacao' then 'publishing.republish.approve' else 'publishing.approve' end;
  perform public._pub_require(cap, p_ws, p_token, 'pub.approve', p_id::text);
  if uid is null then raise exception 'identidade_individual' using errcode = '42501', detail = 'Aprovar exige sessão individual.'; end if;
  a := public._content_actor(p_token);
  if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if cur.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
  if p_revision is null or p_revision <> cur.revision then
    raise exception 'revisao_mudou' using errcode = '40001', detail = 'A publicação mudou desde que a abriste. Revê a versão nova antes de aprovar.'; end if;
  if cur.status = 'aprovada' then return public._pub_json(cur, p_token); end if;
  pol := public._pub_policy(p_ws);
  if pol.forbid_self and uid in (cur.created_by, cur.revision_by) then
    raise exception 'autoaprovacao_proibida' using errcode = '42501', detail = 'Neste cliente quem planeou ou mudou a publicação não a pode aprovar.'; end if;
  if exists (select 1 from pub_approvals x where x.publication_id = cur.id and x.revision = cur.revision and x.actor_user_id = uid and x.invalidated_at is null) then
    return public._pub_json(cur, p_token); end if;
  me := public._pub_actor_side(p_ws, uid);
  if me is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  missing := public._pub_missing(cur);
  -- (sem partes em falta, p.ex. depois de a política ficar mais leve, qualquer pessoa com a capacidade confirma)
  if cardinality(missing) > 0 and not ('qualquer' = any(missing) or (me->>'side') = any(missing)) then
    raise exception 'parte_errada' using errcode = '42501', detail = case pol.required
      when 'agencia' then 'Neste cliente a aprovação é da agência (direção criativa).'
      when 'cliente' then 'Neste cliente a aprovação é do cliente.'
      else format('A parte %s já aprovou; falta a outra parte.', case when me->>'side' = 'agencia' then 'da agência' else 'do cliente' end) end;
  end if;
  select * into g from guioes where id = cur.content_id;
  if g.approved_version_id is distinct from cur.content_version_id then
    raise exception 'versao_por_aprovar' using errcode = '22023', detail = 'A versão do guião desta publicação não é a versão aprovada. Aprova o guião ou muda a versão.'; end if;
  if cur.scheduled_at <= now() then raise exception 'hora_passada' using errcode = '22023', detail = 'A hora já passou. Muda a hora antes de aprovar.'; end if;
  blk := public._pub_blocking(public._pub_conflicts(cur, me->>'side' = 'agencia'));
  if blk is not null then raise exception 'conflito_publicacao' using errcode = '22023', detail = blk; end if;

  perform set_config('pub.approving', cur.id::text, true);
  snap := public._pub_snapshot(cur);
  insert into pub_approvals (workspace_id, publication_id, revision, side, capability, actor_user_id, actor_label, actor_role, snapshot, snapshot_hash)
  values (p_ws, cur.id, cur.revision, me->>'side', cap, uid, a->>'label', me->>'role', snap, public._pub_hash(cur));
  if cardinality(public._pub_missing(cur)) = 0 then
    update pub_publications set status = 'aprovada', approved_revision = revision, approved_at = now() where id = cur.id returning * into n;
  else n := cur; end if;
  perform set_config('pub.approving', '', true);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values (uid, 'user', a->>'label', p_ws, case when n.status = 'aprovada' then 'pub.approved' else 'pub.approval_partial' end, 'pub_publication', cur.id::text,
          jsonb_build_object('status', cur.status, 'revision', cur.revision),
          jsonb_build_object('status', n.status, 'revision', n.revision, 'side', me->>'side', 'role', me->>'role', 'capability', cap, 'snapshot', snap), cur.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, case when n.status = 'aprovada' then 'publication.approved' else 'publication.approval_partial' end, 'publication', cur.id::text,
          jsonb_build_object('revision', cur.revision, 'side', me->>'side'));
  return public._pub_json(n, p_token);
end $$;

-- Aprovar em lote (PUB-01: aprovar em lote = autorizar a publicação agendada). Cada item é independente.
create or replace function public.pub_approve_batch(p_ws text, p_items jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it jsonb; out jsonb := '[]'; r jsonb; m text; d text;
begin
  if jsonb_typeof(coalesce(p_items, 'null')) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'pedido_invalido' using errcode = '22023', detail = 'Entre 1 e 100 publicações.'; end if;
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.approve_batch', null);
  for it in select * from jsonb_array_elements(p_items) loop
    begin
      r := public.pub_approve(p_ws, (it->>'id')::uuid, (it->>'revision')::int, p_token);
      out := out || jsonb_build_object('id', it->>'id', 'ok', true, 'status', r->>'status');
    exception when others then
      get stacked diagnostics m = message_text, d = pg_exception_detail;
      out := out || jsonb_build_object('id', it->>'id', 'ok', false, 'code', sqlstate, 'error', m, 'detail', nullif(d, ''));
    end;
  end loop;
  return out;
end $$;

-- ───────────── TEAM-10: política (dono/admin do cliente) ─────────────
create or replace function public.pub_policy_save(p_ws text, p_policy jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); before pub_approval_policies := public._pub_policy(p_ws); req text; fs boolean; p pub_publications; n int := 0;
begin
  perform public._pub_require('publishing.policy.manage', p_ws, p_token, 'pub.policy_save', p_ws);
  if (a->>'uid') is null then raise exception 'identidade_individual' using errcode = '42501'; end if;
  req := coalesce(p_policy->>'required', before.required);
  fs := coalesce((p_policy->>'forbid_self')::boolean, before.forbid_self);
  if req not in ('qualquer', 'agencia', 'cliente', 'ambos') then
    raise exception 'politica_invalida' using errcode = '22023', detail = 'Quem aprova: qualquer, agencia, cliente ou ambos.'; end if;
  insert into pub_approval_policies (workspace_id, required, forbid_self, updated_at, updated_by, updated_label)
  values (p_ws, req, fs, now(), (a->>'uid')::uuid, a->>'label')
  on conflict (workspace_id) do update set required = excluded.required, forbid_self = excluded.forbid_self, updated_at = now(),
    updated_by = excluded.updated_by, updated_label = excluded.updated_label;
  -- aprovadas que deixam de cumprir a política nova voltam a planeadas (as aprovações ficam; falta a parte nova)
  for p in select * from pub_publications where workspace_id = p_ws and status = 'aprovada' for update loop
    if cardinality(public._pub_missing(p)) > 0 then
      update pub_publications set status = 'planeada', approved_revision = null, approved_at = null where id = p.id;
      n := n + 1;
    end if;
  end loop;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.policy_saved', 'pub_policy', p_ws,
          jsonb_build_object('required', before.required, 'forbid_self', before.forbid_self),
          jsonb_build_object('required', req, 'forbid_self', fs, 'reopened', n));
  return jsonb_build_object('required', req, 'forbid_self', fs, 'reopened', n);
end $$;

-- ───────────── PUB-02: limites (só dono da agência) ─────────────
create or replace function public.pub_limit_save(p_ws text, p_platform text, p_patch jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid := (select organization_id from clients where id = p_ws); cur pub_platform_limits; nw pub_platform_limits;
begin
  if uid is null or org is null or not public._org_can('publishing.limits.manage', org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'pub.limit_save', 'capability', 'publishing.limits.manage');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._flag_on('pub.planning', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O calendário de publicações ainda não está ligado neste cliente.'; end if;
  if jsonb_typeof(coalesce(p_patch, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  perform public._pub_seed_limits(org);
  select * into cur from pub_platform_limits where organization_id = org and platform = p_platform for update;
  if cur.platform is null then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
  if p_patch ? 'max_posts' and (jsonb_typeof(p_patch->'max_posts') <> 'number' or (p_patch->>'max_posts')::numeric not between 1 and 10000) then
    raise exception 'limite_invalido' using errcode = '22023', detail = 'O máximo tem de estar entre 1 e 10000.'; end if;
  if p_patch ? 'window_kind' and p_patch->>'window_kind' not in ('rolling_24h', 'calendar_day') then raise exception 'limite_invalido' using errcode = '22023'; end if;
  if p_patch ? 'scope' and p_patch->>'scope' not in ('conta', 'projeto') then raise exception 'limite_invalido' using errcode = '22023'; end if;
  if p_patch ? 'window_tz' and not exists (select 1 from pg_timezone_names where name = p_patch->>'window_tz') then
    raise exception 'limite_invalido' using errcode = '22023', detail = 'Fuso horário desconhecido.'; end if;
  if nullif(p_patch->>'verified_on', '') is null then
    raise exception 'data_verificacao_obrigatoria' using errcode = '22023', detail = 'Indica a data em que verificaste o limite na documentação da plataforma.'; end if;
  if (p_patch->>'verified_on')::date > (now() at time zone 'UTC')::date + 1 then
    raise exception 'data_verificacao_invalida' using errcode = '22023', detail = 'A data de verificação não pode ser no futuro.'; end if;
  update pub_platform_limits set
    max_posts = coalesce((p_patch->>'max_posts')::int, max_posts),
    window_kind = coalesce(p_patch->>'window_kind', window_kind),
    window_tz = coalesce(p_patch->>'window_tz', window_tz),
    scope = coalesce(p_patch->>'scope', scope),
    public_requires_audit = coalesce((p_patch->>'public_requires_audit')::boolean, public_requires_audit),
    note = case when p_patch ? 'note' then left(nullif(btrim(p_patch->>'note'), ''), 500) else note end,
    verified_on = (p_patch->>'verified_on')::date,
    republish_min_days = case when p_patch ? 'republish_min_days' then nullif(p_patch->>'republish_min_days', '')::int else republish_min_days end,
    republish_max_share = case when p_patch ? 'republish_max_share' then nullif(p_patch->>'republish_max_share', '')::numeric else republish_max_share end,
    republish_identical = coalesce((p_patch->>'republish_identical')::boolean, republish_identical),
    updated_at = now(), updated_label = (select email from auth.users where id = uid)
  where organization_id = org and platform = p_platform returning * into nw;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), org, p_ws, 'pub.limit_saved', 'pub_platform_limit', p_platform,
          to_jsonb(cur) - 'organization_id', to_jsonb(nw) - 'organization_id');
  return public._pub_limits_json(p_ws);
end $$;
