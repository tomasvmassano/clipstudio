-- supabase/tests/w7_learn.sql : aprendizagem e qualidade (FR-17-10, FR-17-11, FR-17-12, SCALE-06), cargos no convite (BIZ-08),
-- exportação dos próprios dados (FR-14-05) e custo por guião/publicação (FR-10-05). Rollback no fim (raise).
-- Números conhecidos (índice às 72 h, mesma conta): a1 400/300 = 1,333; a2 500/350 = 1,429; a3 600/400 = 1,5; b1 200/400 = 0,5;
-- b2 300/400 = 0,75; b3 250/350 = 0,714; w 5000/300 = 16,667; x 10/350 = 0,029. Custos: j1 1,00 € em 2 guiões (0,50 cada), j2 0,80 € por posição 0,30/0,10 (0,60 e 0,20).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_v uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_new uuid := gen_random_uuid(); u_new2 uuid := gen_random_uuid();
  u_adm2 uuid := gen_random_uuid();
  tok text := 'la-a-team-code-0123456789abcdef';
  j jsonb; k jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int; gid text; g2 text; cv uuid;
  e1 uuid; e2 uuid; inv uuid; ref uuid := gen_random_uuid(); j1 uuid; j2 uuid; j3 uuid; j4 uuid; rid uuid; ga guioes;
begin
  insert into clients (id, name, handle, organization_id) values ('la_a', 'Learn A', 'lna', org), ('la_b', 'Learn B', 'lnb', org);
  insert into accounts (id, client_id, role, platform, handle) values ('la-a-ig', 'la_a', 'client', 'instagram', 'learn_a'), ('la-b-ig', 'la_b', 'client', 'instagram', 'learn_b');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'ln-adm@test.invalid'),(u_v,'ln-v@test.invalid'),(u_rev,'ln-rev@test.invalid'),(u_b,'ln-b@test.invalid'),
    (u_own,'ln-own@test.invalid'),(u_ag,'ln-ag@test.invalid'),(u_adm2,'ln-adm2@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('la_a', u_adm, 'client_staff', 'workspace_admin'), ('la_a', u_v, 'client_staff', 'viewer'), ('la_a', u_rev, 'client_staff', 'reviewer'),
    ('la_a', u_adm2, 'client_staff', 'workspace_admin'), ('la_b', u_b, 'client_staff', 'workspace_admin'), ('la_a', u_ag, 'agency_staff', 'manager');
  insert into studio_tokens (token, client_id, label) values (tok, 'la_a', 'Equipa LA');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k2, org, w, 'all' from unnest(array['learn.rework','learn.experiments','team.job_titles','profile.data_export','costs.content','perf.center']) k2,
                                unnest(array['la_a','la_b']) w;

  -- desempenho: base q1..q5, formato lista (a1..a3) e mito (b1), vencedor w ligado ao guião g1, x fraco
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views)
  select 'la_a', 'q' || g, 'instagram', 'learn_a', 'client', 'la-a-ig', now() - make_interval(days => 31 - g), 1 from generate_series(1, 5) g;
  insert into perf_readings (workspace_id, reel_id, captured_at, views)
  select 'la_a', 'q' || g, now() - make_interval(days => 31 - g) + interval '72 hours', 100 * g from generate_series(1, 5) g;
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views) values
    ('la_a', 'a1', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '12 days', 1),
    ('la_a', 'a2', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '11 days', 1),
    ('la_a', 'a3', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '10 days', 1),
    ('la_a', 'b1', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '9 days', 1),
    ('la_a', 'b2', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '7 days', 1),
    ('la_a', 'b3', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '6 days', 1),
    ('la_a', 'w', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '5 days', 1),
    ('la_a', 'x', 'instagram', 'learn_a', 'client', 'la-a-ig', now() - interval '4 days', 1),
    ('la_b', 'bw', 'instagram', 'learn_b', 'client', 'la-b-ig', now() - interval '5 days', 1);
  insert into perf_readings (workspace_id, reel_id, captured_at, views) values
    ('la_a', 'a1', now() - interval '12 days' + interval '72 hours', 400), ('la_a', 'a2', now() - interval '11 days' + interval '72 hours', 500),
    ('la_a', 'a3', now() - interval '10 days' + interval '72 hours', 600), ('la_a', 'b1', now() - interval '9 days' + interval '72 hours', 200),
    ('la_a', 'b2', now() - interval '7 days' + interval '72 hours', 300), ('la_a', 'b3', now() - interval '6 days' + interval '72 hours', 250),
    ('la_a', 'w', now() - interval '5 days' + interval '72 hours', 5000), ('la_a', 'x', now() - interval '4 days' + interval '72 hours', 10);
  insert into script_analysis (client_id, reel_id, formato_norm) values ('la_a', 'a1', 'lista'), ('la_a', 'a2', 'lista'), ('la_a', 'a3', 'lista'), ('la_a', 'b1', 'mito'), ('la_a', 'b2', 'mito'), ('la_a', 'b3', 'mito');
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, notas)
  select 'la_a-g' || g, 'la_a', current_date - 20, g, 'lista', 'Tema ' || g, '[{"text":"Hook do vencedor","mecanismo":"numero"}]', 'Corpo ' || g || '.', 'nota original'
  from generate_series(1, 5) g;
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo) values ('la_b-g1', 'la_b', current_date - 20, 1, 'lista', 'B', '[]', 'Corpo B.');
  insert into publicacoes (guiao_id, account_id, reel_id, published_at) values ('la_a-g1', 'la-a-ig', 'w', now() - interval '5 days');

  -- custos (FR-10-05)
  insert into agent_config_versions (workspace_id, version_no, status, config, created_label)
  select w, 1, 'draft', config, 'fixture' from agent_config_versions, unnest(array['la_a','la_b']) w where workspace_id = 'numeiro' limit 2;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, cost_eur, finished_at, run_id)
  values ('la_a', 'daily_pipeline', 'ln-j1', 'succeeded', (select id from agent_config_versions where workspace_id = 'la_a'), 'system', 1.0, now(), 'run1') returning id into j1;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, cost_eur, finished_at, run_id)
  values ('la_a', 'daily_pipeline', 'ln-j2', 'succeeded', (select id from agent_config_versions where workspace_id = 'la_a'), 'system', 0.8, now(), 'run2') returning id into j2;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, cost_eur, finished_at, run_id)
  values ('la_a', 'daily_pipeline', 'ln-j3', 'failed', (select id from agent_config_versions where workspace_id = 'la_a'), 'system', null, now(), 'run3') returning id into j3;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, cost_eur, finished_at)
  values ('la_a', 'scouts', 'ln-j4', 'succeeded', (select id from agent_config_versions where workspace_id = 'la_a'), 'system', 0.25, now()) returning id into j4;
  insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, cost_eur, finished_at)
  values ('la_b', 'daily_pipeline', 'ln-jb', 'succeeded', (select id from agent_config_versions where workspace_id = 'la_b'), 'system', 9.0, now());
  insert into agent_job_outputs (job_id, slot, workspace_id, content_id) values
    (j1, 0, 'la_a', 'la_a-g1'), (j1, 1, 'la_a', 'la_a-g2'), (j2, 0, 'la_a', 'la_a-g3'), (j2, 1, 'la_a', 'la_a-g4'), (j3, 0, 'la_a', 'la_a-g5');
  insert into agent_log (run_id, slot, client_id, agent, cost_eur) values ('run2', 0, 'la_a', 'guionista', 0.3), ('run2', 1, 'la_a', 'guionista', 0.1);

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ═════ FR-17-10 motivos e retrabalho ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := rework_reasons_list('la_a');
  insert into t values ('sem motivos ainda; flag ligada; admin gere', true, jsonb_array_length(j->'reasons') = 0 and (j->>'enabled')::boolean and (j->>'can_manage')::boolean);
  j := rework_reasons_seed('la_a');
  insert into t values ('lista sugerida copiada para o cliente', true, jsonb_array_length(j->'reasons') = 10);
  insert into t values ('semear outra vez não duplica', true, jsonb_array_length(rework_reasons_seed('la_a')->'reasons') = 10);
  j := rework_reason_save('la_a', null, '{"code":"musica","label":"Música sem direitos","applies_to":["video"]}');
  insert into t values ('criar motivo só para vídeo', true, exists (select 1 from jsonb_array_elements(j->'reasons') x where x->>'code' = 'musica'));
  begin perform rework_reason_save('la_a', null, '{"code":"musica","label":"Outra"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código repetido recusado (22023)', true, st = '22023');
  rid := (select (x->>'id')::uuid from jsonb_array_elements(j->'reasons') x where x->>'code' = 'musica');
  begin perform rework_reason_save('la_a', rid, '{"code":"outra_coisa"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código não muda depois de criado', true, st = '22023');

  ga := content_create('la_a', '{"corpo":"Guião para rever.","hooks":[{"text":"Um hook","mecanismo":"ego"}]}');
  gid := ga.id;
  perform content_transition(gid, 'in_review', null, null, null);
  begin perform content_transition_reasoned(gid, 'changes_requested', 'muda o hook', 'musica', null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('motivo só de vídeo não serve para guião', true, st = '22023');
  begin perform content_transition_reasoned(gid, 'changes_requested', '', 'hook_fraco', null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('texto livre continua obrigatório com categoria', true, st = '22023');
  begin perform content_transition_reasoned(gid, 'changes_requested', 'muda', 'nao_existe', null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('categoria fora da lista recusada', true, st = '22023');
  ga := content_transition_reasoned(gid, 'changes_requested', 'O hook não prende', 'hook_fraco', null, null);
  insert into t values ('pedido de alterações com categoria muda o estado como antes', true, ga.editorial_status = 'changes_requested' and ga.motivo_rejeicao = 'O hook não prende');
  execute 'reset role';
  insert into t values ('categoria ligada à transição gravada', true, exists (select 1 from content_transition_reasons x join content_transitions c on c.id = x.transition_id
    where x.content_id = gid and x.code = 'hook_fraco' and c.to_status = 'changes_requested' and c.reason = 'O hook não prende'));
  execute 'set local role authenticated';
  perform content_transition(gid, 'in_review', null, null, null);
  ga := content_transition_reasoned(gid, 'rejected', 'Factos errados', 'factos', null, null);
  ga := content_create('la_a', '{"corpo":"Outro guião."}');
  g2 := ga.id;
  ga := content_transition(g2, 'rejected', 'sem categoria, como antes', null, null);
  insert into t values ('assinatura antiga de content_transition continua a funcionar', true, ga.editorial_status = 'rejected');
  j := rework_dashboard('la_a', 3);
  k := j->'by_month'->0;
  insert into t values ('painel: 3 decisões, 1 pedido de alterações, 2 rejeições', true,
    (k->>'decisions')::int = 3 and (k->>'changes')::int = 1 and (k->>'rejected')::int = 2 and (k->>'rework_rate')::numeric = 1);
  insert into t values ('painel: um ciclo fechado e sem ciclos em aberto', true, (k->>'cycles_closed')::int = 1 and (k->>'cycles_open')::int = 0 and (k->>'hours_lost')::numeric >= 0);
  insert into t values ('por motivo: hook_fraco, factos e sem categoria', true,
    exists (select 1 from jsonb_array_elements(j->'by_reason') x where x->>'code' = 'hook_fraco' and (x->>'changes')::int = 1)
    and exists (select 1 from jsonb_array_elements(j->'by_reason') x where x->>'code' = 'factos' and (x->>'rejected')::int = 1)
    and exists (select 1 from jsonb_array_elements(j->'by_reason') x where x->>'code' = 'sem_categoria' and (x->>'rejected')::int = 1)
    and (j->'totals'->>'uncategorized')::int = 1);
  insert into t values ('etapa vídeo marcada como indisponível com motivo', true,
    exists (select 1 from jsonb_array_elements(j->'stages') s where s->>'key' = 'video' and not (s->>'available')::boolean and s->>'reason' is not null));
  insert into t values ('3 meses pedidos, 3 meses devolvidos', true, jsonb_array_length(j->'by_month') = 3);

  -- isolamento e permissões
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform rework_dashboard('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê o retrabalho de A (42501)', true, st = '42501');
  begin perform rework_reasons_list('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê os motivos de A', true, st = '42501');
  begin perform content_transition_reasoned(g2, 'rejected', 'x', 'hook_fraco', null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não rejeita guiões de A', true, st = '42501');
  insert into t values ('lista de B vazia (nada de A)', true, jsonb_array_length(rework_reasons_list('la_b')->'reasons') = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform rework_dashboard('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor sem learn.read não vê o painel', true, st = '42501');
  begin perform rework_reason_save('la_a', null, '{"code":"novo","label":"Novo"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não gere motivos', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  insert into t values ('revisor vê o painel', true, (rework_dashboard('la_a')->'totals'->>'decisions')::int = 3);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform rework_dashboard('la_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência só nos clientes atribuídos', true, st = '42501');
  -- flag desligada
  execute 'reset role';
  delete from feature_flags where key = 'learn.rework' and workspace_id = 'la_a';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform rework_dashboard('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: painel recusa com 55000', true, st = '55000');
  insert into t values ('flag desligada: lista diz enabled=false', true, not (rework_reasons_list('la_a')->>'enabled')::boolean);
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('learn.rework', org, 'la_a', 'all');
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  insert into t values ('código de equipa lê os motivos para escolher', true, jsonb_array_length(rework_reasons_list('la_a', tok)->'reasons') = 11);
  begin perform rework_dashboard('la_a', 6, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não vê o painel', true, st = '42501');
  begin perform rework_dashboard('la_a', 6, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código recusado', true, st <> 'none');
  execute 'reset role';
  execute 'set local role authenticated';

  -- ═════ FR-17-11 experiências ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform learn_experiment_save('la_a', null, jsonb_build_object('title', 'Lista vs mito', 'hypothesis', 'Listas prendem mais do que mitos.',
      'dimension', 'formato', 'variants', '[{"key":"A","value":"lista"}]'::jsonb, 'accounts', '["la-a-ig"]'::jsonb,
      'window_start', current_date - 15, 'window_end', current_date)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('uma só variante recusada', true, st = '22023');
  begin perform learn_experiment_save('la_a', null, jsonb_build_object('title', 'Lista vs mito', 'hypothesis', 'Listas prendem mais do que mitos.',
      'dimension', 'formato', 'variants', '[{"key":"A","value":"lista"},{"key":"B","value":"mito"}]'::jsonb, 'accounts', '["la-b-ig"]'::jsonb,
      'window_start', current_date - 15, 'window_end', current_date)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conta de outro cliente recusada', true, st = '22023');
  j := learn_experiment_save('la_a', null, jsonb_build_object('title', 'Lista vs mito', 'hypothesis', 'Listas prendem mais do que mitos.',
      'dimension', 'formato', 'variants', '[{"key":"A","value":"lista","label":"Lista"},{"key":"B","value":"mito"}]'::jsonb, 'accounts', '["la-a-ig"]'::jsonb,
      'window_start', current_date - 15, 'window_end', current_date, 'min_per_variant', 4, 'include_external', true));
  e1 := (j->>'id')::uuid;
  j := learn_experiment_get('la_a', e1);
  insert into t values ('rascunho mostra pré-visualização dos resultados', true, j ? 'preview' and jsonb_array_length(j->'preview'->'variants') = 2);
  perform learn_experiment_act('la_a', e1, 'start');
  j := learn_experiment_get('la_a', e1);
  k := (select v from jsonb_array_elements(j->'results'->'variants') v where v->>'key' = 'A');
  insert into t values ('variante A: 4 publicações (a1..a3 e w pelo guião ligado), mediana 1,46 (mesmo índice do centro)', true, (k->>'n')::int = 4 and (k->>'median')::numeric = 1.46 and (k->>'sufficient')::boolean);
  k := (select v from jsonb_array_elements(j->'results'->'variants') v where v->>'key' = 'B');
  insert into t values ('variante B: 3 publicações, mediana 0,71, abaixo do mínimo 4: amostra insuficiente', true, (k->>'n')::int = 3 and (k->>'median')::numeric = 0.71 and not (k->>'sufficient')::boolean);
  insert into t values ('amostra insuficiente: sem líder nem critério, com aviso', true, j->'results'->>'leader' is null and j->'results'->>'criterion_met' is null
    and exists (select 1 from jsonb_array_elements_text(j->'results'->'warnings') w where w like 'Amostra insuficiente na variante B%'));
  insert into t values ('nunca declara causa', true, j->'results'->>'note' like '%não prova%');
  begin perform learn_experiment_save('la_a', e1, '{"min_per_variant": 1}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('regras fechadas depois de começar', true, st = '22023');
  begin perform learn_experiment_act('la_a', e1, 'conclude', '{"outcome":"confirmada","conclusion":"As listas ganham sempre."}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se confirma com amostra insuficiente', true, st = '22023');
  j := learn_experiment_act('la_a', e1, 'conclude', '{"outcome":"inconclusiva","conclusion":"Poucos mitos publicados na janela."}');
  insert into t values ('concluir como inconclusiva guarda a fotografia', true, j->>'status' = 'concluida' and j->'results' ? 'variants');
  j := learn_experiment_save('la_a', null, jsonb_build_object('title', 'Lista vs mito 2', 'hypothesis', 'Listas prendem mais do que mitos.',
      'dimension', 'formato', 'variants', '[{"key":"A","value":"lista"},{"key":"B","value":"mito"}]'::jsonb, 'accounts', '["la-a-ig"]'::jsonb,
      'window_start', current_date - 15, 'window_end', current_date, 'min_per_variant', 3, 'decision_ratio', 1.2, 'include_external', true));
  e2 := (j->>'id')::uuid;
  perform learn_experiment_act('la_a', e2, 'start');
  j := learn_experiment_get('la_a', e2);
  insert into t values ('com amostra: líder A, razão 1,46 ÷ 0,71 = 2,06, critério cumprido', true,
    j->'results'->>'leader' = 'A' and (j->'results'->>'ratio')::numeric = 2.06 and (j->'results'->>'criterion_met')::boolean);
  insert into t values ('comparação por conta', true, jsonb_array_length(j->'results'->'by_account') = 1);
  j := learn_experiment_act('la_a', e2, 'conclude', '{"outcome":"confirmada","conclusion":"Listas acima de mitos nesta conta.","lever":"Mais listas"}');
  insert into t values ('confirmada com critério cumprido', true, j->>'outcome' = 'confirmada');
  -- sem incluir externos não há publicações (todas importadas): nunca se inventa
  j := learn_experiment_save('la_a', null, jsonb_build_object('title', 'Só sistema', 'hypothesis', 'Só o que publicámos pela app.',
      'dimension', 'formato', 'variants', '[{"key":"A","value":"lista"},{"key":"B","value":"mito"}]'::jsonb, 'accounts', '["la-a-ig"]'::jsonb,
      'window_start', current_date - 15, 'window_end', current_date));
  j := learn_experiment_get('la_a', (j->>'id')::uuid);
  insert into t values ('só origem sistema: zero publicações, nada inventado', true, (j->'preview'->>'matched')::int = 0
    and not exists (select 1 from jsonb_array_elements(j->'preview'->'variants') v where v->>'median' is not null));

  -- ═════ SCALE-06 recomendações ═════
  j := learn_recommendations('la_a');
  insert into t values ('recomendação da experiência confirmada com evidência e limitações', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->>'kind' = 'experiencia' and x->>'title' = 'Mais listas'
            and x->'evidence'->>'leader' = 'A' and jsonb_array_length(x->'limitations') >= 1));
  insert into t values ('inconclusiva não vira recomendação', true,
    not exists (select 1 from jsonb_array_elements(j->'items') x where (x->>'experiment_id')::uuid = e1));
  insert into t values ('limitações gerais dizem que nada muda sozinho', true, j->'limitations'->>0 like 'Nenhuma recomendação muda%');

  -- ═════ FR-17-12 repetir vencedor ═════
  j := learn_winners('la_a');
  insert into t values ('vencedores: w (16,667) e a3 (1,5), não x', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->>'reel_id' = 'w' and (x->>'idx')::numeric = 16.667)
    and exists (select 1 from jsonb_array_elements(j->'items') x where x->>'reel_id' = 'a3')
    and not exists (select 1 from jsonb_array_elements(j->'items') x where x->>'reel_id' = 'x'));
  j := learn_repeat_winner('la_a', 'w', 'variacao', 'Testar outro número', ref);
  ga := (select g from guioes g where g.id = j->>'content_id');
  insert into t values ('proposta nasce em rascunho, ligada ao original, sem publicar', true, (j->>'created')::boolean and ga.editorial_status = 'draft'
    and ga.origem = 'repetir:w' and ga.corpo = 'Corpo 1.' and ga.notas like 'Variação da publicação w%' and ga.production_status = 'not_started'
    and ga.client_id = 'la_a');
  insert into t values ('repetir com o mesmo client_ref é idempotente', true, learn_repeat_winner('la_a', 'w', 'variacao', null, ref)->>'content_id' = ga.id
    and not (learn_repeat_winner('la_a', 'w', 'variacao', null, ref)->>'created')::boolean);
  insert into t values ('vencedor mostra a proposta feita', true, exists (select 1 from jsonb_array_elements(learn_winners('la_a')->'items') x, jsonb_array_elements(x->'repeats') rp
    where x->>'reel_id' = 'w' and rp->>'content_id' = ga.id and rp->>'status' = 'draft'));
  begin perform learn_repeat_winner('la_a', 'x', 'variacao'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('publicação fraca não é vencedor', true, st = '22023');
  begin perform learn_repeat_winner('la_a', 'a3', 'continuacao'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('vencedor sem guião ligado: recusa com explicação', true, st = '22023');
  begin perform learn_repeat_winner('la_a', 'bw', 'continuacao'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('publicação de B pelo cliente A: não encontrada', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform learn_repeat_winner('la_a', 'w', 'continuacao'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisor sem scripts.create não cria proposta', true, st = '42501');
  begin perform learn_experiment_save('la_a', null, '{"title":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não gere experiências', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform learn_experiment_get('la_a', e2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não abre experiência de A', true, st = '42501');
  begin perform learn_experiment_get('la_b', e2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('trocar o cliente no pedido não abre a experiência de A (P0002)', true, st = 'P0002');
  begin perform learn_repeat_winner('la_a', 'w', 'continuacao'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não repete vencedor de A', true, st = '42501');
  insert into t values ('B não vê experiências nem vencedores de A', true, jsonb_array_length(learn_experiments_list('la_b')->'experiments') = 0
    and not exists (select 1 from jsonb_array_elements(learn_winners('la_b')->'items') x where x->>'reel_id' in ('w', 'a3')));

  -- ═════ BIZ-08 cargos no convite ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := job_title_templates('la_a');
  insert into t values ('modelos com papel, exceções sugeridas e o que se pode dar', true, (j->>'can_grant')::boolean
    and exists (select 1 from jsonb_array_elements(j->'templates') x, jsonb_array_elements(x->'grant_options') go
                where x->>'key' = 'smm' and go->>'key' = 'publishing.schedule' and (go->>'grantable')::boolean and not (go->>'in_role')::boolean));
  begin perform invite_member_with_title('la_a', 'ln-new@test.invalid', 'contributor', 'client_staff', 'smm', array['permissions.manage']); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('exceção fora do modelo recusada', true, st = '22023');
  begin perform invite_member_with_title('la_a', 'ln-new@test.invalid', 'contributor', 'client_staff', 'astronauta', '{}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('cargo desconhecido recusado', true, st = '22023');
  inv := invite_member_with_title('la_a', 'ln-new@test.invalid', 'contributor', 'client_staff', 'smm', array['calendar.schedule', 'publishing.schedule']);
  execute 'reset role';
  insert into t values ('convite guarda cargo e exceções', true, (select job_title = 'Social Media Manager' and suggested_grants = array['calendar.schedule','publishing.schedule']
    and workspace_role = 'contributor' from invitations where id = inv));
  insert into t values ('o cargo sozinho não dá nada antes de aceitar', true, not exists (select 1 from permission_grants where reason like 'Sugerida pelo cargo%'));
  insert into auth.users (id, email, email_confirmed_at, aud, role) values (u_new, 'ln-new@test.invalid', now(), 'authenticated', 'authenticated');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_new, 'role','authenticated')::text, true);
  n := accept_invitations();
  execute 'reset role';
  insert into t values ('ao aceitar: cargo no membro e 2 exceções explícitas do autor do convite', true, n = 1
    and (select job_title from workspace_access where workspace_id = 'la_a' and user_id = u_new) = 'Social Media Manager'
    and (select count(*) from permission_grants where workspace_id = 'la_a' and user_id = u_new and effect = 'allow' and created_by = u_adm and revoked_at is null) = 2
    and public._authorize('publishing.schedule', 'la_a', u_new) and not public._authorize('publishing.publish', 'la_a', u_new));
  insert into t values ('exceções auditadas com origem no cargo', true,
    (select count(*) from audit_events where action = 'grant.set' and entity_id = u_new::text and after->>'source' = 'job_title') = 2);
  insert into t values ('acesso só ao cliente A', true, not public._authorize('scripts.read', 'la_b', u_new));
  -- quem convidou perdeu o direito antes da aceitação: exceções não entram
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm2, 'role','authenticated')::text, true);
  inv := invite_member_with_title('la_a', 'ln-new2@test.invalid', 'contributor', 'client_staff', 'editor', array['media.share']);
  execute 'reset role';
  update workspace_access set workspace_role = 'contributor' where workspace_id = 'la_a' and user_id = u_adm2;
  insert into auth.users (id, email, email_confirmed_at, aud, role) values (u_new2, 'ln-new2@test.invalid', now(), 'authenticated', 'authenticated');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_new2, 'role','authenticated')::text, true);
  perform accept_invitations();
  execute 'reset role';
  insert into t values ('autor sem direito na aceitação: exceção não entra e fica auditado', true,
    not exists (select 1 from permission_grants where user_id = u_new2)
    and exists (select 1 from audit_events where action = 'grant.skipped' and entity_id = u_new2::text)
    and (select job_title from workspace_access where workspace_id = 'la_a' and user_id = u_new2) = 'Editor');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  inv := invite_member('la_a', 'ln-old@test.invalid', 'viewer', 'client_staff');
  insert into t values ('invite_member antigo continua igual', true, inv is not null);
  begin perform invite_member_with_title('la_b', 'ln-x@test.invalid', 'contributor', 'client_staff', 'clipper', '{}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('admin de A não convida para B', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform job_title_templates('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem não convida não vê os modelos', true, st = '42501');

  -- ═════ FR-14-05 exportar e pedir eliminação ═════
  execute 'reset role';
  insert into content_comments (workspace_id, content_id, block, body, author_id, author_kind) values
    ('la_a', 'la_a-g1', 'geral', 'Comentário meu em A', u_v, 'user'), ('la_b', 'la_b-g1', 'geral', 'Comentário antigo em B', u_v, 'user'),
    ('la_a', 'la_a-g1', 'geral', 'Comentário de outra pessoa', u_adm, 'user');
  insert into tasks (workspace_id, title, assignee_id, created_kind) values ('la_a', 'Tarefa minha', u_v, 'system'), ('la_b', 'Tarefa de B', u_v, 'system');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  insert into t values ('exportação disponível com a flag', true, (my_data_status()->>'available')::boolean);
  j := my_data_export();
  insert into t values ('exporta perfil, clientes, comentários e tarefas próprios', true, j->'profile'->>'email' = 'ln-v@test.invalid'
    and jsonb_array_length(j->'script_comments') = 1 and j->'script_comments'->0->>'body' = 'Comentário meu em A'
    and jsonb_array_length(j->'tasks') = 1 and jsonb_array_length(j->'workspaces') = 1);
  insert into t values ('nada de outros clientes nem de outras pessoas', true, j::text not like '%Comentário antigo em B%' and j::text not like '%Tarefa de B%'
    and j::text not like '%Comentário de outra pessoa%');
  insert into t values ('histórico sem antes/depois', true, not exists (select 1 from jsonb_array_elements(j->'audit_trail') x where x ? 'before' or x ? 'after'));
  j := my_data_deletion_request('Quero sair');
  k := my_data_deletion_request('outra vez');
  insert into t values ('pedido de eliminação idempotente e pendente', true, j->>'id' = k->>'id' and j->>'status' = 'pendente');
  execute 'reset role';
  insert into t values ('nada foi apagado', true, exists (select 1 from auth.users where id = u_v) and exists (select 1 from workspace_access where user_id = u_v));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform privacy_requests_admin(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente não vê pedidos de eliminação', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência vê o pedido', true, exists (select 1 from jsonb_array_elements(privacy_requests_admin()->'items') x where x->>'id' = j->>'id'));
  begin perform privacy_request_resolve((j->>'id')::uuid, 'tratado', ''); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tratar exige explicação', true, st = '22023');
  k := privacy_request_resolve((j->>'id')::uuid, 'tratado', 'Conta anonimizada à mão');
  insert into t values ('pedido tratado e auditado', true, exists (select 1 from jsonb_array_elements(k->'items') x where x->>'id' = j->>'id' and x->>'status' = 'tratado'));
  execute 'reset role';
  delete from feature_flags where key = 'profile.data_export';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform my_data_export(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: exportação recusa (55000) e status diz indisponível', true, st = '55000' and not (my_data_status()->>'available')::boolean);

  -- ═════ FR-10-05 custos ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := content_costs('la_a', 3);
  k := j->'by_month'->0;
  insert into t values ('mês: total 2,05 €, atribuído 1,80 €, por atribuir 0,25 €, 1 execução sem custo', true,
    (k->>'ai_total')::numeric = 2.05 and (k->>'attributed')::numeric = 1.80 and (k->>'unattributed')::numeric = 0.25 and (k->>'jobs_unknown')::int = 1);
  insert into t values ('4 guiões com custo, 0,45 € por guião', true, (k->>'scripts')::int = 4 and (k->>'cost_per_script')::numeric = 0.45);
  insert into t values ('partes iguais: g1 e g2 a 0,50 €', true,
    (select bool_and((x->>'cost_eur')::numeric = 0.5 and x->>'method' = 'partes_iguais') from jsonb_array_elements(j->'scripts') x where x->>'content_id' in ('la_a-g1','la_a-g2')));
  insert into t values ('por posição: g3 0,60 € e g4 0,20 €', true,
    (select (x->>'cost_eur')::numeric from jsonb_array_elements(j->'scripts') x where x->>'content_id' = 'la_a-g3') = 0.6
    and (select (x->>'cost_eur')::numeric from jsonb_array_elements(j->'scripts') x where x->>'content_id' = 'la_a-g4') = 0.2);
  insert into t values ('custo desconhecido nunca é zero', true,
    (select x->'cost_eur' = 'null'::jsonb and not (x->>'cost_known')::boolean from jsonb_array_elements(j->'scripts') x where x->>'content_id' = 'la_a-g5'));
  insert into t values ('publicação: g1 com 1 publicação a 0,50 €', true,
    (select (x->>'publications')::int = 1 and (x->>'cost_per_publication')::numeric = 0.5 from jsonb_array_elements(j->'scripts') x where x->>'content_id' = 'la_a-g1'));
  insert into t values ('vídeo indisponível com motivo', true, not (j->'video'->>'available')::boolean and j->'video'->>'reason' is not null);
  insert into t values ('custos de B não entram em A', true, j::text not like '%la_b%' and (k->>'ai_total')::numeric < 9);
  j := content_costs_export('la_a', 3);
  execute 'reset role';
  insert into t values ('exportação auditada', true, exists (select 1 from audit_events where action = 'costs.exported' and workspace_id = 'la_a' and actor_user_id = u_adm));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform content_costs('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem costs.read não vê custos', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform content_costs('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor do cliente não vê custos', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_costs('la_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê custos de A', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência vê custos', true, (content_costs('la_a', 1)->'by_month'->0->>'ai_total')::numeric = 2.05);
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform content_costs('la_a', 6, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa nunca vê custos', true, st = '42501');
  execute 'reset role';

  insert into t values ('tabelas novas fechadas à leitura direta', true,
    not has_table_privilege('authenticated', 'public.rework_reasons', 'select') and not has_table_privilege('authenticated', 'public.content_transition_reasons', 'select')
    and not has_table_privilege('authenticated', 'public.learn_experiments', 'select') and not has_table_privilege('authenticated', 'public.learn_repeat_links', 'select')
    and not has_table_privilege('authenticated', 'public.privacy_requests', 'select'));
  insert into t values ('capacidades e flags registadas', true,
    (select count(*) from capabilities where key in ('learn.read','learn.manage','privacy.manage','profile.export')) = 4
    and (select count(*) from feature_flag_defs where key in ('learn.rework','learn.experiments','team.job_titles','profile.data_export','costs.content')) = 5);
  insert into t values ('categoria é só de acrescentar', true, (select count(*) from content_transition_reasons where content_id = gid) = 2);
  begin update content_transition_reasons set code = 'x' where content_id = gid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('categoria não se altera', true, st = '42501');

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
