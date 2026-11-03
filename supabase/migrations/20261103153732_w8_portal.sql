-- W8 · Portal do cliente (PRD SCALE-08; R-13, R-14; §2, §3; TEAM-10; PUB-06; FR-17-01; AGENTS §9; ADR-0041).
-- Espaço: cliente (`/c/<cliente>/portal`). Uma entrada simples para a equipa do cliente com quatro coisas: o que espera a
-- sua aprovação (guiões e publicações planeadas), o estado das entregas do mês contra o volume contratado (só volumes e
-- prazos, nunca dinheiro), um resumo de desempenho e os pedidos de conteúdo.
--
-- Não duplica regras. As ações usam as RPCs que já existem e que continuam a decidir sozinhas:
--   aprovar / pedir alterações / rejeitar guião  → content_transition (e content_transition_reasoned com learn.rework)
--   aprovar publicação                          → pub_approve (política TEAM-10, autoaprovação, revisão vista, versão)
--   criar pedido de conteúdo                    → talent_request_create (requests.create)
-- Este ficheiro só acrescenta leituras: portal_home (agrega) e portal_block (um bloco, para "tentar de novo").
-- Cada bloco verifica a sua capacidade e a sua flag no servidor e, se não puder, devolve {available:false, code, reason}
-- em vez de fazer falhar o portal inteiro. O portal em si pede acesso ao cliente (scripts.read, como my_flags) e a flag
-- client.portal. Sem capacidade nova: todas as capacidades usadas já existem (decisão na ADR-0041).
--
-- Nunca sai daqui: valores do contrato (amount, currency, billing_period), pagamento, renovação, notas do contrato, custos,
-- margens, outros clientes, flags, permissões, notas internas de saúde das contas nem quem as escreveu.
-- Expand (só aditivo): 1 flag e funções novas. Nenhuma função existente muda. Rollback no fim.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('client.portal', 'Portal do cliente', 'Cliente', 'ws', 'owner',
   'Entrada simples para a equipa do cliente: aprovações (guiões e publicações), entregas do mês contra o contratado (sem valores), resumo de desempenho e pedidos de conteúdo (SCALE-08). Cada bloco continua a pedir a sua capacidade.')
on conflict (key) do nothing;

-- ───────────── ajudantes puros ─────────────
create or replace function public._portal_off(p_code text, p_reason text) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('available', false, 'code', p_code, 'reason', p_reason)
$$;

-- Acesso ao portal: capacidade primeiro (42501, igual para cliente sem acesso e cliente inexistente), depois a flag (55000).
create or replace function public._portal_require(p_ws text, p_token text, p_action text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.read', p_ws, p_token, p_action, p_ws);
  if not public._flag_on('client.portal', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O portal do cliente ainda não está ligado neste cliente.';
  end if;
end $$;

-- ───────────── bloco 1a: guiões à espera de aprovação ─────────────
create or replace function public._portal_scripts(p_ws text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
begin
  if not public.ws_can('scripts.approve', p_ws, p_token) then
    return public._portal_off('sem_capacidade', 'Não tens permissão para aprovar guiões neste cliente.');
  end if;
  return (with q as (
      select g.*, cv.version_no,
             coalesce((select max(ct.at) from content_transitions ct where ct.content_id = g.id and ct.kind = 'editorial' and ct.to_status = 'in_review'),
                      g.created_at) since
        from guioes g left join content_versions cv on cv.id = g.current_version_id
       where g.client_id = p_ws and g.editorial_status = 'in_review')
    select jsonb_build_object('available', true,
      'can_reject', public.ws_can('scripts.reject', p_ws, p_token),
      'reasons_by_category', public._flag_on('learn.rework', p_ws, p_token),
      'total', (select count(*) from q),
      'over_48h', (select count(*) from q where since < now() - interval '48 hours'),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
          'id', x.id, 'n', x.n, 'date', x.date, 'tema', x.tema, 'formato', x.formato,
          'hooks', coalesce((select jsonb_agg(h->>'text') from jsonb_array_elements(case when jsonb_typeof(x.hooks) = 'array' then x.hooks else '[]' end) h
                             where nullif(btrim(h->>'text'), '') is not null), '[]'),
          'corpo', x.corpo, 'cta', x.cta, 'lock_version', x.lock_version, 'version_id', x.current_version_id, 'version_no', x.version_no,
          'waiting_since', x.since, 'waiting_local', to_char(x.since at time zone tz, 'DD/MM HH24:MI'),
          'over_48h', x.since < now() - interval '48 hours') order by x.date, x.n)
        from (select * from q order by date, n limit 50) x), '[]')));
end $$;

-- ───────────── bloco 1b: publicações planeadas à espera da parte do cliente ─────────────
-- As que ainda precisam do cliente (política cliente/ambos) ou de qualquer parte (política "qualquer"). A decisão final
-- (pode aprovar? porque não?) vem de _pub_json, a mesma que o calendário de publicações usa.
create or replace function public._portal_publications(p_ws text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pol pub_approval_policies;
begin
  if not public.ws_can('calendar.read', p_ws, p_token) then
    return public._portal_off('sem_capacidade', 'Não tens acesso ao calendário de publicações deste cliente.');
  end if;
  if not public._flag_on('pub.planning', p_ws, p_token) then
    return public._portal_off('desligado', 'O calendário de publicações ainda não está ligado neste cliente.');
  end if;
  pol := public._pub_policy(p_ws);
  return (with q as (
      select p from pub_publications p
       where p.workspace_id = p_ws and p.status = 'planeada' and p.scheduled_at > now()
         and public._pub_missing(p) && array['cliente', 'qualquer'])
    select jsonb_build_object('available', true,
      'can_approve', public.ws_can('publishing.approve', p_ws, p_token) or public.ws_can('publishing.republish.approve', p_ws, p_token),
      'individual', auth.uid() is not null,
      'policy', jsonb_build_object('required', pol.required, 'forbid_self', pol.forbid_self),
      'total', (select count(*) from q),
      'items', coalesce((select jsonb_agg(public._pub_json(x.p, p_token) order by (x.p).scheduled_at, (x.p).id)
                           from (select p from q order by (p).scheduled_at, (p).id limit 50) x), '[]'),
      'publish_available', false,
      'publish_unavailable_reason', 'Publicação automática chega quando as plataformas aprovarem a app.'));
end $$;

-- ───────────── bloco 2: entregas do mês contra o contratado (sem dinheiro) ─────────────
-- Os números vêm de _biz_ops (BIZ-01, a mesma conta da vista de negócio); do contrato só saem volumes e prazos.
create or replace function public._portal_deliveries(p_ws text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws); today date; m0 date; m1 date;
        c client_contracts; ops jsonb; att jsonb; active boolean;
begin
  -- quem chega aqui já passou _portal_require (scripts.read); volta a verificar para o bloco não depender de quem o chama
  if not public.ws_can('scripts.read', p_ws, p_token) then
    return public._portal_off('sem_capacidade', 'Não tens acesso às entregas deste cliente.');
  end if;
  today := (now() at time zone tz)::date;
  m0 := date_trunc('month', today)::date;
  m1 := (m0 + interval '1 month')::date;
  c := public._biz_contract_at(p_ws, today);
  active := c.id is not null and c.status = 'ativo';
  ops := public._biz_ops(p_ws, m0, array['scripts.read']);
  att := ops->'ops.attainment';
  return jsonb_build_object('available', true,
    'month', m0, 'today', today, 'timezone', tz,
    'contract', case when active then jsonb_build_object(
        'videos_per_month', c.videos_per_month, 'scripts_per_month', c.scripts_per_month,
        'platforms', to_jsonb(c.platforms), 'deadline_days', c.deadline_days) end,
    'contract_reason', case when c.id is null then 'Ainda não há volumes contratados registados para este cliente.'
                            when not active then 'O contrato deste cliente está terminado.' end,
    'videos', jsonb_build_object(
      'contracted', case when active then c.videos_per_month end,
      'published', coalesce((att->>'on_time')::int, 0) + coalesce((att->>'late_published')::int, 0),
      'on_time', (att->>'on_time')::int, 'late', (att->>'late_published')::int,
      'overdue', (att->>'overdue')::int, 'due_today', (att->>'due_today')::int,
      'expected_to_date', att->'expected_to_date', 'pct', att->'pct', 'pace', att->'pace', 'target', att->'target',
      'deadline_days', att->'deadline_days'),
    'scripts', jsonb_build_object(
      'contracted', case when active then c.scripts_per_month end,
      'approved', coalesce((ops->'ops.first_pass'->>'approved')::int, 0),
      'planned', (select count(*) from guioes g where g.client_id = p_ws and g.date >= m0 and g.date < m1
                     and g.editorial_status not in ('rejected', 'archived')),
      'waiting_approval', coalesce((ops->'ops.approvals'->>'pending')::int, 0)),
    'assumption', 'Prazo de cada vídeo: dia do guião no calendário mais os dias de prazo do contrato. Um guião publicado em várias plataformas conta como um vídeo.');
end $$;

-- ───────────── bloco 3: relatório de desempenho ─────────────
-- Resumo de perf_center e perf_levers (mesmas regras e mesmas amostras mínimas). Sem notas internas de saúde.
create or replace function public._portal_reports(p_ws text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pc jsonb; lv jsonb;
begin
  if not public.ws_can('analytics.read', p_ws, p_token) then
    return public._portal_off('sem_capacidade', 'Não tens acesso ao desempenho deste cliente.');
  end if;
  if not public._flag_on('perf.center', p_ws, p_token) then
    return public._portal_off('desligado', 'O centro de desempenho ainda não está ligado neste cliente.');
  end if;
  pc := public.perf_center(p_ws, p_token);
  lv := public.perf_levers(p_ws, true, p_token);
  return jsonb_build_object('available', true,
    'source', pc->'source', 'first_reading_at', pc->'first_reading_at',
    'totals', jsonb_build_object('publications', pc->'totals'->'publications', 'linked', pc->'totals'->'linked'),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a->'id', 'platform', a->'platform', 'handle', a->'handle', 'label', a->'label', 'active', a->'active',
        'n_30d', a->'n_30d', 'last_read_at', a->'last_read_at',
        'idx72_median_30d', a->'idx72_median_30d', 'idx72_n_30d', a->'idx72_n_30d',
        'median_ratio', a->'health'->'median_ratio', 'median_drop', a->'health'->'median_drop'))
      from jsonb_array_elements(pc->'accounts') a), '[]'),
    'week', jsonb_build_object('from', lv->'week'->'from', 'to', lv->'week'->'to', 'n', lv->'week'->'n',
      'top', coalesce((select jsonb_agg(jsonb_build_object('reel_id', t->'reel_id', 'platform', t->'platform', 'handle', t->'handle',
                 'hook_text', t->'hook_text', 'idx72', t->'idx72', 'published_at', t->'published_at'))
               from (select t from jsonb_array_elements(lv->'week'->'top') t limit 3) z), '[]')),
    'min_sample', lv->'params'->'min_sample');
end $$;

-- ───────────── bloco 4: pedidos de conteúdo ─────────────
-- Pedidos (ideas.kind = 'talent_request') deste cliente nos últimos 180 dias e o que aconteceu a cada um. As notas de
-- triagem da agência (ideas.notas) não saem; o motivo só sai quando o pedido não avança.
create or replace function public._portal_requests(p_ws text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); can_create boolean := public.ws_can('requests.create', p_ws, p_token);
        tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
begin
  if not (can_create or public.ws_can('sources.read', p_ws, p_token)) then
    return public._portal_off('sem_capacidade', 'Não tens acesso aos pedidos de conteúdo deste cliente.');
  end if;
  return (with q as (
      select i.* from ideas i where i.client_id = p_ws and i.kind = 'talent_request' and i.created_at >= now() - interval '180 days')
    select jsonb_build_object('available', true, 'can_create', can_create, 'window_days', 180,
      'total', (select count(*) from q),
      'open', (select count(*) from q where status in ('nova', 'triagem', 'selecionada')),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
          'id', x.id, 'titulo', x.titulo, 'texto', x.resumo, 'status', x.status,
          'status_reason', case when x.status = 'descartada' then x.status_reason end,
          'created_at', x.created_at, 'created_local', to_char(x.created_at at time zone tz, 'DD/MM/YYYY'),
          'mine', uid is not null and x.created_by = uid,
          'scripts', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'editorial_status', g.editorial_status) order by g.date, g.n)
                                 from content_sources cs join guioes g on g.id = cs.content_id
                                where cs.source_id = x.id and cs.workspace_id = p_ws and g.client_id = p_ws), '[]'))
          order by x.created_at desc)
        from (select * from q order by created_at desc limit 50) x), '[]')));
end $$;

-- ───────────── leitura pública ─────────────
-- Um bloco. Erros do bloco não fazem cair o portal: 42501/55000 viram "indisponível" com o motivo; outro erro fica no
-- log do servidor e volta como "erro" com o código, para a UI oferecer "tentar de novo" (nunca engolido).
create or replace function public.portal_block(p_ws text, p_block text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text; d text; st text;
begin
  perform public._portal_require(p_ws, p_token, 'portal.' || coalesce(p_block, ''));
  if p_block not in ('scripts', 'publications', 'deliveries', 'reports', 'requests') then
    raise exception 'bloco_desconhecido' using errcode = '22023', detail = 'Blocos: scripts, publications, deliveries, reports, requests.';
  end if;
  begin
    return case p_block
      when 'scripts' then public._portal_scripts(p_ws, p_token)
      when 'publications' then public._portal_publications(p_ws, p_token)
      when 'deliveries' then public._portal_deliveries(p_ws, p_token)
      when 'reports' then public._portal_reports(p_ws, p_token)
      when 'requests' then public._portal_requests(p_ws, p_token) end;
  exception
    when insufficient_privilege then
      return public._portal_off('sem_capacidade', 'Não tens permissão para ver isto neste cliente.');
    when others then
      get stacked diagnostics m = message_text, d = pg_exception_detail, st = returned_sqlstate;
      if st = '55000' then return public._portal_off('desligado', coalesce(nullif(d, ''), 'Esta parte ainda não está ligada neste cliente.')); end if;
      raise log 'portal_block_error %', jsonb_build_object('workspace_id', p_ws, 'block', p_block, 'sqlstate', st, 'message', m, 'actor_user_id', auth.uid());
      return public._portal_off('erro', 'Não consegui carregar esta parte do portal. Tenta de novo.') || jsonb_build_object('sqlstate', st);
  end;
end $$;

-- Tudo de uma vez. viewer diz de que lado está quem vê: a equipa da agência vê "como o cliente vê" (as_client).
create or replace function public.portal_home(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); me jsonb; side text;
begin
  perform public._portal_require(p_ws, p_token, 'portal.home');
  me := case when uid is not null then public._pub_actor_side(p_ws, uid) end;
  side := case when uid is null then 'codigo' else coalesce(me->>'side', 'agencia') end;
  return jsonb_build_object(
    'client', (select jsonb_build_object('id', id, 'name', name, 'timezone', coalesce(timezone, 'Asia/Dubai')) from clients where id = p_ws),
    'viewer', jsonb_build_object('side', side, 'as_client', side = 'agencia', 'individual', uid is not null),
    'generated_at', now(),
    'blocks', jsonb_build_object(
      'scripts', public.portal_block(p_ws, 'scripts', p_token),
      'publications', public.portal_block(p_ws, 'publications', p_token),
      'deliveries', public.portal_block(p_ws, 'deliveries', p_token),
      'reports', public.portal_block(p_ws, 'reports', p_token),
      'requests', public.portal_block(p_ws, 'requests', p_token)));
end $$;

revoke all on function public._portal_off(text, text), public._portal_require(text, text, text), public._portal_scripts(text, text),
  public._portal_publications(text, text), public._portal_deliveries(text, text), public._portal_reports(text, text),
  public._portal_requests(text, text) from public, anon, authenticated;
revoke all on function public.portal_block(text, text, text), public.portal_home(text, text) from public;
grant execute on function public.portal_block(text, text, text), public.portal_home(text, text) to anon, authenticated;
-- anon só passa com código de equipa válido e a flag "para todos" (o código não aprova publicações: exige sessão individual).

/* Rollback (compatível: nada do que existia mudou):
   drop function public.portal_home(text, text), public.portal_block(text, text, text), public._portal_requests(text, text),
     public._portal_reports(text, text), public._portal_deliveries(text, text), public._portal_publications(text, text),
     public._portal_scripts(text, text), public._portal_require(text, text, text), public._portal_off(text, text);
   delete from feature_flags where key = 'client.portal'; delete from feature_flag_defs where key = 'client.portal'; */
