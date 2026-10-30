-- Parte 2 de 2 de 20261030120200_w7_learn_experiments.sql (aplicada em produção como w7_learn_experiments_p2).

-- Estados: start (rascunho → a_decorrer), conclude (a_decorrer → concluida, com fotografia), cancel.
create or replace function public.learn_experiment_act(p_ws text, p_id uuid, p_action text, p_fields jsonb default '{}', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); old learn_experiments; e learn_experiments; snap jsonb; oc text; f jsonb := coalesce(p_fields, '{}');
begin
  perform public._learn_require('learn.experiments', 'learn.manage', p_ws, p_token, 'learn.experiment_act');
  select * into old from learn_experiments where id = p_id and workspace_id = p_ws for update;
  if old.id is null then raise exception 'experiencia_nao_encontrada' using errcode = 'P0002'; end if;
  if p_action = 'start' then
    if old.status <> 'rascunho' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    update learn_experiments set status = 'a_decorrer', updated_at = now() where id = p_id returning * into e;
  elsif p_action = 'conclude' then
    if old.status <> 'a_decorrer' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    oc := f->>'outcome';
    if oc is null or oc not in ('confirmada', 'refutada', 'inconclusiva') then
      raise exception 'resultado_invalido' using errcode = '22023', detail = 'Resultado: confirmada, refutada ou inconclusiva.'; end if;
    if char_length(btrim(coalesce(f->>'conclusion', ''))) < 10 then
      raise exception 'conclusao_obrigatoria' using errcode = '22023', detail = 'Escreve a conclusão (pelo menos 10 caracteres).'; end if;
    snap := public._learn_exp_results(old);
    -- sem amostra suficiente ou sem critério cumprido não se declara "confirmada"
    if oc = 'confirmada' and not coalesce((snap->>'criterion_met')::boolean, false) then
      raise exception 'criterio_nao_cumprido' using errcode = '22023',
        detail = 'Só se confirma com amostra suficiente em todas as variantes e o critério de decisão cumprido. Conclui como inconclusiva.'; end if;
    update learn_experiments set status = 'concluida', outcome = oc, conclusion = left(btrim(f->>'conclusion'), 2000),
      lever = nullif(left(btrim(coalesce(f->>'lever', '')), 200), ''), result_snapshot = snap,
      concluded_at = now(), concluded_by = (a->>'uid')::uuid, concluded_label = a->>'label', updated_at = now()
    where id = p_id returning * into e;
  elsif p_action = 'cancel' then
    if old.status not in ('rascunho', 'a_decorrer') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    update learn_experiments set status = 'cancelada', updated_at = now() where id = p_id returning * into e;
  else
    raise exception 'acao_invalida' using errcode = '22023';
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'learn.experiment_' || p_action, 'learn_experiment', e.id::text,
          jsonb_build_object('status', old.status), jsonb_build_object('status', e.status, 'outcome', e.outcome, 'lever', e.lever));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'learn.experiment_' || p_action, 'learn_experiment', e.id::text, jsonb_build_object('status', e.status, 'outcome', e.outcome));
  return public._learn_exp_json(e, true);
end $$;

-- Vencedores (FR-17-12): publicações com índice ≥ limiar à idade de vencedor, com as propostas já feitas a partir delas.
create or replace function public.learn_winners(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prm jsonb := public._learn_params();
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.winners');
  return jsonb_build_object('params', prm, 'can_create', public.ws_can('scripts.create', p_ws, p_token),
    'items', coalesce((select jsonb_agg(w order by (w->>'idx')::numeric desc) from (
        select jsonb_build_object('reel_id', x->>'reel_id', 'account_id', x->>'account_id', 'handle', x->>'handle', 'platform', x->>'platform',
          'url', x->>'url', 'title', x->>'title', 'published_at', x->>'published_at', 'origin', x->>'origin', 'lineage_mode', x->>'lineage_mode',
          'idx', (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric, 'content_id', x->>'content_id', 'hook_text', x->>'hook_text', 'formato', x->>'formato',
          'repeats', coalesce((select jsonb_agg(jsonb_build_object('content_id', l.new_content_id, 'kind', l.kind, 'created_at', l.created_at,
                                   'status', (select editorial_status from guioes where id = l.new_content_id)) order by l.created_at desc)
                               from learn_repeat_links l where l.workspace_id = p_ws and l.source_reel_id = x->>'reel_id'), '[]')) w
        from public._perf_rows(p_ws) x
        where (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric >= (prm->>'winner_idx')::numeric
          and (x->>'published_at')::timestamptz >= now() - make_interval(days => (prm->>'winner_days')::int)
        order by (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric desc limit 50) z), '[]'));
end $$;

-- Repetir vencedor: cria um guião em rascunho a partir do guião da publicação vencedora, ligado a ela. Idempotente por client_ref.
create or replace function public.learn_repeat_winner(p_ws text, p_reel_id text, p_kind text, p_note text default null,
                                                      p_client_ref uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); prm jsonb := public._learn_params(); x jsonb; src guioes; g guioes; l learn_repeat_links;
        idx numeric; tz text; lid bigint; nt text;
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.repeat_winner');
  perform public._content_require('scripts.create', p_ws, p_token, 'learn.repeat_winner', p_reel_id);
  if p_kind is null or p_kind not in ('continuacao', 'variacao') then raise exception 'tipo_invalido' using errcode = '22023', detail = 'Continuação ou variação.'; end if;
  if p_client_ref is not null then
    select * into l from learn_repeat_links where workspace_id = p_ws and client_ref = p_client_ref;
    if l.id is not null then return jsonb_build_object('content_id', l.new_content_id, 'created', false); end if;
  end if;
  select r into x from public._perf_rows(p_ws) r where r->>'reel_id' = p_reel_id limit 1;
  if x is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  idx := (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric;
  if idx is null or idx < (prm->>'winner_idx')::numeric then
    raise exception 'nao_e_vencedor' using errcode = '22023',
      detail = format('Só publicações com índice às %s de pelo menos %s.', prm->>'winner_age', replace((prm->>'winner_idx'), '.', ',')); end if;
  select * into src from guioes where id = x->>'content_id' and client_id = p_ws;
  if src.id is null then
    raise exception 'sem_guiao_de_origem' using errcode = '22023', detail = 'Esta publicação não está ligada a um guião deste cliente: liga-a primeiro no centro de desempenho.'; end if;
  select coalesce(timezone, 'Asia/Dubai') into tz from clients where id = p_ws;
  nt := format('%s da publicação %s (@%s, índice %s às %s). Proposta: rever antes de submeter.',
               case when p_kind = 'continuacao' then 'Continuação' else 'Variação' end, p_reel_id, x->>'handle', idx, prm->>'winner_age')
        || coalesce(E'\n' || nullif(left(btrim(p_note), 1000), ''), '') || coalesce(E'\n\nNotas do original: ' || src.notas, '');
  g := public.content_create(p_ws, jsonb_build_object('date', (now() at time zone tz)::date, 'formato', src.formato, 'tema', src.tema, 'hooks', src.hooks,
         'corpo', src.corpo, 'cta', src.cta, 'notas', left(nt, 4000), 'origem', 'repetir:' || p_reel_id), p_token);
  select id into lid from publication_lineage where workspace_id = p_ws and account_id = x->>'account_id' and external_id = p_reel_id;
  insert into learn_repeat_links (workspace_id, new_content_id, source_content_id, source_reel_id, source_account_id, source_lineage_id, source_idx,
                                  source_age, kind, note, client_ref, created_by, created_label)
  values (p_ws, g.id, src.id, p_reel_id, x->>'account_id', lid, idx, prm->>'winner_age', p_kind, nullif(left(btrim(p_note), 1000), ''), p_client_ref,
          (a->>'uid')::uuid, a->>'label');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'learn.repeat_proposed', 'guiao', g.id,
          jsonb_build_object('source_reel_id', p_reel_id, 'source_content_id', src.id, 'idx', idx, 'kind', p_kind));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'learn.repeat_proposed', 'content', g.id, jsonb_build_object('source_reel_id', p_reel_id, 'source_content_id', src.id, 'kind', p_kind));
  return jsonb_build_object('content_id', g.id, 'date', g.date, 'created', true, 'editorial_status', g.editorial_status);
end $$;

-- Learning loop (SCALE-06): recomendações com evidência e limitações. Só leitura: nada se aplica sozinho.
create or replace function public.learn_recommendations(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prm jsonb := public._learn_params(); lv jsonb; recs jsonb := '[]'; e learn_experiments; r jsonb; tot jsonb; inferred numeric;
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.recommendations');
  for e in select * from learn_experiments where workspace_id = p_ws and status = 'concluida' and outcome in ('confirmada', 'refutada')
           order by concluded_at desc limit 20 loop
    r := e.result_snapshot;
    recs := recs || jsonb_build_array(jsonb_build_object(
      'kind', 'experiencia', 'direction', case when e.outcome = 'confirmada' then 'repetir' else 'rever' end,
      'title', coalesce(e.lever, e.title), 'detail', e.conclusion, 'experiment_id', e.id,
      'evidence', jsonb_build_object('hypothesis', e.hypothesis, 'dimension', e.dimension, 'window_start', e.window_start, 'window_end', e.window_end,
        'age', e.age, 'accounts', to_jsonb(e.accounts), 'leader', r->>'leader', 'ratio', r->'ratio', 'decision_ratio', e.decision_ratio,
        'variants', (select coalesce(jsonb_agg(jsonb_build_object('key', v->>'key', 'label', v->>'label', 'n', v->'n', 'median', v->'median')), '[]')
                     from jsonb_array_elements(r->'variants') v),
        'concluded_at', e.concluded_at, 'concluded_label', e.concluded_label),
      'limitations', jsonb_build_array(r->>'note') || coalesce(r->'warnings', '[]')));
  end loop;
  -- alavancas do centro de desempenho (PERF-07), só para quem também vê o desempenho
  if public.ws_can('analytics.read', p_ws, p_token) and public._flag_on('perf.center', p_ws, p_token) then
    lv := public.perf_levers(p_ws, true, p_token);
    recs := recs || coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'alavanca', 'direction', case when (l->>'idx_median')::numeric >= (prm->>'lever_up')::numeric then 'repetir' else 'evitar' end,
        'title', format('%s: %s', l->>'dimension', l->>'key'),
        'detail', format('Índice mediano %s às 72 h em %s publicações de origem sistema (últimos 90 dias).', l->>'idx_median', l->>'n'),
        'evidence', jsonb_build_object('dimension', l->>'dimension', 'key', l->>'key', 'n', l->'n', 'median', l->'idx_median', 'age', '72h', 'days', 90),
        'limitations', jsonb_build_array('Comparação observacional: outras diferenças entre as publicações podem explicar o resultado.',
                                         'Atributos deduzidos das etiquetas; nas publicações sem linhagem gravada podem estar errados.'))
        order by abs((l->>'idx_median')::numeric - 1) desc)
      from jsonb_array_elements(lv->'levers') l
      where (l->>'shown')::boolean and ((l->>'idx_median')::numeric >= (prm->>'lever_up')::numeric or (l->>'idx_median')::numeric < (prm->>'lever_down')::numeric)), '[]');
  end if;
  select jsonb_build_object('n', count(*), 'inferred', count(*) filter (where x->>'lineage_mode' = 'inferida'))
    into tot from public._perf_rows(p_ws) x;
  inferred := case when (tot->>'n')::int > 0 then round((tot->>'inferred')::numeric / (tot->>'n')::numeric, 2) end;
  return jsonb_build_object('params', prm, 'items', recs,
    'limitations', jsonb_build_array(
      'Nenhuma recomendação muda a estratégia, os prompts, as permissões ou a publicação sozinha: quem decide é uma pessoa (AGENTS §7).',
      'Métricas da recolha por scraping: sem alcance, retenção nem seguidores até as contas estarem ligadas pela API oficial.',
      'O índice compara cada publicação com a mediana da própria conta nos 30 dias anteriores; contas com menos de 5 publicações não têm índice.')
      || case when inferred > 0 then jsonb_build_array(format('%s%% das publicações deste cliente têm linhagem inferida.', round(inferred * 100))) else '[]'::jsonb end);
end $$;

revoke all on function public._learn_params(), public._learn_variants_valid(text, jsonb), public._learn_exp_results(learn_experiments),
  public._learn_exp_json(learn_experiments, boolean) from public, anon, authenticated;
revoke all on function public.learn_experiments_list(text, text), public.learn_experiment_get(text, uuid, text), public.learn_experiment_save(text, uuid, jsonb, text),
  public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_winners(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text),
  public.learn_recommendations(text, text) from public;
grant execute on function public.learn_experiments_list(text, text), public.learn_experiment_get(text, uuid, text), public.learn_experiment_save(text, uuid, jsonb, text),
  public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_winners(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text),
  public.learn_recommendations(text, text) to anon, authenticated;

/* Rollback (compatível: nada do que existia mudou):
   drop function public.learn_recommendations(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text), public.learn_winners(text, text),
     public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_experiment_save(text, uuid, jsonb, text),
     public.learn_experiment_get(text, uuid, text), public.learn_experiments_list(text, text), public._learn_exp_json(learn_experiments, boolean),
     public._learn_exp_results(learn_experiments), public._learn_variants_valid(text, jsonb), public._learn_params();
   delete from feature_flags where key = 'learn.experiments'; delete from feature_flag_defs where key = 'learn.experiments';
-- contract posterior (só depois de exportar): drop table public.learn_repeat_links, public.learn_experiments;
-- os guiões criados por "repetir vencedor" ficam (origem 'repetir:<reel>'), são conteúdo normal. */
