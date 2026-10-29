-- supabase/tests/w6_perf.sql : centro de desempenho (PERF-01..07, R-16, R-18; rollback no fim).
-- Números conhecidos: 5 publicações de base com views às 72 h de 100..500 (mediana 300) e uma publicação com 600 às 70 h
-- (e 900 às 80 h) dá índice 2,0. Uma segunda conta com views enormes nunca entra na base da primeira.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_v uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  t0 timestamptz := now() - interval '5 days';
  j jsonb; p jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int; vid uuid; lid bigint;
begin
  insert into clients (id, name, handle, organization_id) values ('pa_a', 'Perf A', 'pfa', org), ('pa_b', 'Perf B', 'pfb', org);
  insert into accounts (id, client_id, role, platform, handle) values
    ('pa-a-ig', 'pa_a', 'client', 'instagram', 'perf_a'), ('pa-a-tt', 'pa_a', 'client', 'tiktok', 'perf_a'),
    ('pa-a-ref', 'pa_a', 'reference', 'instagram', 'outro'), ('pa-b-ig', 'pa_b', 'client', 'instagram', 'perf_b');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_v,'pf-v@test.invalid'),(u_adm,'pf-adm@test.invalid'),(u_b,'pf-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('pa_a', u_v, 'client_staff', 'viewer'), ('pa_a', u_adm, 'client_staff', 'workspace_admin'), ('pa_b', u_b, 'client_staff', 'workspace_admin');

  -- conta A Instagram: base q1..q5, publicação p, publicação s sem leitura perto das 72 h
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views)
  select 'pa_a', 'q' || g, 'instagram', 'perf_a', 'client', 'pa-a-ig', now() - make_interval(days => 21 - g), 1 from generate_series(1, 5) g;
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views, hook) values
    ('pa_a', 'p', 'instagram', 'perf_a', 'client', 'pa-a-ig', t0, 1, 'Ninguém te diz isto sobre dinheiro e casas'),
    ('pa_a', 's', 'instagram', 'perf_a', 'client', 'pa-a-ig', now() - interval '10 days', 1, ''),
    ('pa_a', 'ref1', 'instagram', 'outro', 'reference', 'pa-a-ref', t0, 99999, '');
  insert into perf_readings (workspace_id, reel_id, captured_at, views)
  select 'pa_a', 'q' || g, now() - make_interval(days => 21 - g) + interval '72 hours', 100 * g from generate_series(1, 5) g;
  insert into perf_readings (workspace_id, reel_id, captured_at, views) values
    ('pa_a', 'q1', now() - interval '20 days' + interval '24 hours', 10), ('pa_a', 'q2', now() - interval '19 days' + interval '24 hours', 20),
    ('pa_a', 'p', t0 + interval '24 hours', 50), ('pa_a', 'p', t0 + interval '70 hours', 600), ('pa_a', 'p', t0 + interval '80 hours', 900),
    ('pa_a', 's', now() - interval '10 days' + interval '100 hours', 777);
  -- conta A TikTok: 20 publicações com views enormes, formato "lista" (para as alavancas)
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views)
  select 'pa_a', 't' || g, 'tiktok', 'perf_a', 'client', 'pa-a-tt', now() - make_interval(days => 40 - g), 1 from generate_series(1, 20) g;
  insert into perf_readings (workspace_id, reel_id, captured_at, views)
  select 'pa_a', 't' || g, now() - make_interval(days => 40 - g) + interval '72 hours', 1000000 + g * 1000 from generate_series(1, 20) g;
  insert into script_analysis (client_id, reel_id, formato_norm) select 'pa_a', 't' || g, 'lista' from generate_series(1, 20) g;
  insert into script_analysis (client_id, reel_id, formato_norm) values ('pa_a', 'p', 'mito');
  -- cliente B: uma publicação
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views) values ('pa_b', 'b1', 'instagram', 'perf_b', 'client', 'pa-b-ig', t0, 5);
  -- guião de A para a linhagem gravada (a versão 1 nasce com o guião)
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo)
  values ('pa_a-g1', 'pa_a', current_date, 1, 'lista', 'Casas', '[{"text":"Hook um","mecanismo":"número"},{"text":"Hook dois","mecanismo":"segredo"}]', 'Corpo.');
  vid := (select current_version_id from guioes where id = 'pa_a-g1');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- recolha idempotente (como o cron)
  n := perf_capture('pa_a');
  insert into t values ('recolha guarda a leitura atual de cada publicação do cliente (sem referências)', true, n = 27);
  insert into t values ('recolha repetida não duplica', true, perf_capture('pa_a') = 0);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  j := perf_publications('pa_a', '{"limit":200}');
  p := (select x from jsonb_array_elements(j->'items') x where x->>'reel_id' = 'p');
  insert into t values ('referências não são publicações do cliente', true, (j->>'total')::int = 27
    and not exists (select 1 from jsonb_array_elements(j->'items') x where x->>'reel_id' = 'ref1'));
  insert into t values ('fotografia às 72 h escolhe a leitura mais próxima (70 h, não 80 h)', true, (p->'snapshots'->'72h'->>'views')::int = 600);
  insert into t values ('índice às 72 h = 600 ÷ mediana 300 = 2,0', true, (p->'snapshots'->'72h'->>'idx')::numeric = 2.0
    and (p->'snapshots'->'72h'->>'base_n')::int = 5 and (p->'snapshots'->'72h'->>'base_median')::numeric = 300);
  insert into t values ('base só da própria conta: TikTok com milhões não entra', true, (p->>'idx72')::numeric = 2.0);
  insert into t values ('às 24 h base de 2: amostra insuficiente, sem índice', true, (p->'snapshots'->'24h'->>'base_n')::int = 2
    and p->'snapshots'->'24h'->>'idx' is null and (p->'snapshots'->'24h'->>'views')::int = 50);
  insert into t values ('sem leitura entre 54 h e 90 h não há fotografia às 72 h', true,
    not ((select x from jsonb_array_elements(j->'items') x where x->>'reel_id' = 's')->'snapshots' ? '72h'));
  insert into t values ('sem leituras à 1 h: fotografia ausente, nunca interpolada', true, not (p->'snapshots' ? '1h'));
  insert into t values ('R-16: importada entra como externo e linhagem inferida', true, p->>'origin' = 'externo' and p->>'lineage_mode' = 'inferida'
    and p->>'origin_source' = 'importacao' and p->>'inference_source' = 'analise' and p->>'formato' = 'mito');
  insert into t values ('filtro por conta', true, (perf_publications('pa_a', '{"account":"pa-a-tt"}')->>'total')::int = 20);
  insert into t values ('ordenar por índice põe p (2,0) à frente na conta Instagram', true,
    perf_publications('pa_a', '{"account":"pa-a-ig","sort":"indice"}')->'items'->0->>'reel_id' = 'p');

  j := perf_center('pa_a');
  insert into t values ('visão geral: 2 contas do cliente, sem referências', true, jsonb_array_length(j->'accounts') = 2);
  insert into t values ('famílias sem dados do scraping ficam indisponíveis', true,
    exists (select 1 from jsonb_array_elements(j->'families') f, jsonb_array_elements(f->'metrics') m where m->>'key' = 'reach' and m->>'available' = 'false')
    and exists (select 1 from jsonb_array_elements(j->'families') f, jsonb_array_elements(f->'metrics') m where m->>'key' = 'skip_rate' and m->>'available' = 'false'));
  insert into t values ('totais: tudo externo e inferido', true, (j->'totals'->>'externo')::int = 27 and (j->'totals'->>'sistema')::int = 0);
  insert into t values ('leitor não gere', true, not (j->>'can_manage')::boolean);

  j := perf_breakdown('pa_a', 'account', '72h', '{}');
  insert into t values ('vista por conta: views medianas só dentro da conta', true,
    (select (x->>'views_median')::numeric from jsonb_array_elements(j->'groups') x where x->>'key' = 'pa-a-ig') is not null);
  j := perf_breakdown('pa_a', 'platform', '72h', '{}');
  j := perf_breakdown('pa_a', 'creator', '72h', '{}');
  insert into t values ('vista por criador junta 2 contas e não mostra views absolutas', true,
    (j->'groups'->0->>'accounts')::int = 2 and j->'groups'->0->'views_median' = 'null'::jsonb);
  begin perform perf_breakdown('pa_a', 'senha', '72h', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dimensão desconhecida recusada (22023)', true, st = '22023');
  begin perform perf_breakdown('pa_a', 'format', '48h', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('idade desconhecida recusada (22023)', true, st = '22023');

  -- PERF-07
  j := perf_levers('pa_a', true);
  insert into t values ('alavancas por defeito só com origem sistema: nada ainda', true, (j->>'eligible')::int = 0 and jsonb_array_length(j->'levers') = 0);
  j := perf_levers('pa_a', false);
  insert into t values ('alavanca com 15 publicações com índice é mostrada', true,
    exists (select 1 from jsonb_array_elements(j->'levers') x where x->>'dimension' = 'format' and x->>'key' = 'lista'
            and (x->>'n')::int = 15 and (x->>'shown')::boolean and x->>'idx_median' is not null));
  insert into t values ('alavanca com 1 publicação: amostra insuficiente, sem mediana', true,
    exists (select 1 from jsonb_array_elements(j->'levers') x where x->>'dimension' = 'format' and x->>'key' = 'mito'
            and not (x->>'shown')::boolean and x->'idx_median' = 'null'::jsonb));
  insert into t values ('relatório semanal inclui p (publicada há 5 dias, índice às 72 h)', true,
    j->'week'->'top'->0->>'reel_id' = 'p');

  -- escrita: leitor não corrige
  begin perform perf_account_set('pa_a', 'pa-a-ig', '{"tier":"A"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não muda camada (42501)', true, st = '42501');
  begin perform perf_origin_set('pa_a', 'pa-a-ig', 'p', 'sistema', 'render nosso'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não corrige origem (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := perf_account_set('pa_a', 'pa-a-ig', '{"tier":"A","creator":"Perf","health_state":"alcance_reduzido","health_note":"Aviso na app"}');
  insert into t values ('admin define camada, criador e estado (PERF-01)', true,
    exists (select 1 from jsonb_array_elements(j->'accounts') x where x->>'id' = 'pa-a-ig' and x->>'tier' = 'A' and x->>'creator' = 'Perf'
            and x->'health'->>'state' = 'alcance_reduzido') and (j->>'can_manage')::boolean);
  begin perform perf_account_set('pa_a', 'pa-a-ig', '{"tier":"Z"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('camada inválida recusada (22023)', true, st = '22023');
  begin perform perf_account_set('pa_a', 'pa-b-ig', '{"tier":"A"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conta de outro cliente não se muda por A (P0002)', true, st = 'P0002');
  begin perform perf_origin_set('pa_a', 'pa-a-ig', 'p', 'sistema', ''); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('origem sem motivo recusada (22023)', true, st = '22023');
  j := perf_origin_set('pa_a', 'pa-a-ig', 'p', 'sistema', 'Render nosso publicado à mão');
  insert into t values ('origem corrigida à mão fica sistema/manual', true, j->>'origin' = 'sistema' and j->>'origin_source' = 'manual');
  execute 'reset role';
  perform perf_sync_lineage('pa_a');
  insert into t values ('sincronização não desfaz a correção manual', true,
    (select origin from publication_lineage where workspace_id = 'pa_a' and external_id = 'p') = 'sistema');
  insert into t values ('sincronização materializa todas as publicações como inferidas', true,
    (select count(*) from publication_lineage where workspace_id = 'pa_a' and lineage_mode = 'inferida') = 27);
  insert into t values ('sincronização repetida não reescreve nada', true, perf_sync_lineage('pa_a') = 0);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  insert into t values ('alavancas só sistema passam a ver p', true, (perf_levers('pa_a', true)->>'eligible')::int = 1);

  -- R-18: linhagem gravada pelo publicador
  j := perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'novo1', 'content_id', 'pa_a-g1',
         'content_version_id', vid, 'hook_index', 0, 'edit_style_key', null, 'persona_phrase', 'o homem mais rico', 'duration_s', 31,
         'source_type', 'guiao', 'correlation_id', 'pub-1'));
  lid := (j->>'id')::bigint;
  insert into t values ('linhagem gravada: sistema, versão, hook e mecanismo do guião', true, (j->>'created')::boolean and j->>'origin' = 'sistema'
    and j->>'lineage_mode' = 'gravada' and (j->>'version_no')::int = 1 and j->>'hook_text' = 'Hook um' and j->>'hook_mechanism' = 'numero'
    and j->>'formato' = 'lista' and (j->>'generation')::int = 0);
  j := perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'novo1', 'content_id', 'pa_a-g1', 'content_version_id', vid));
  insert into t values ('gravar outra vez é idempotente (não duplica)', true, not (j->>'created')::boolean and (j->>'id')::bigint = lid);
  j := perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-tt', 'external_id', 'novo2', 'content_id', 'pa_a-g1',
         'content_version_id', vid, 'hook_index', 1, 'parent_lineage_id', lid));
  insert into t values ('republicação ligada à original é geração 1', true, (j->>'generation')::int = 1 and j->>'hook_mechanism' = 'segredo');
  begin perform perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-b-ig', 'external_id', 'x', 'content_id', 'pa_a-g1', 'content_version_id', vid));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conta de outro cliente recusada (22023)', true, st = '22023');
  begin perform perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'x', 'content_id', 'numeiro-2026-10-28-01', 'content_version_id', vid));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conteúdo de outro cliente recusado (22023)', true, st = '22023');
  begin perform perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'x', 'content_id', 'pa_a-g1'));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem versão exata recusado (22023)', true, st = '22023');
  begin perform perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'x', 'content_id', 'pa_a-g1',
      'content_version_id', vid, 'hook_mechanism', 'magia')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('mecanismo fora da lista recusado (22023)', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform perf_record_lineage('pa_a', jsonb_build_object('account_id', 'pa-a-ig', 'external_id', 'y', 'content_id', 'pa_a-g1', 'content_version_id', vid));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem publishing.publish não grava linhagem (42501)', true, st = '42501');
  execute 'reset role';
  begin update publication_lineage set hook_text = 'outro' where id = lid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('linhagem gravada não se altera (42501)', true, st = '42501');
  begin delete from publication_lineage where id = lid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('linhagem gravada não se apaga (42501)', true, st = '42501');
  -- a gravada ganha à inferida quando o scraper encontra o post
  insert into reels (client_id, id, platform, owner, role, account_id, taken_at, views) values ('pa_a', 'novo1', 'instagram', 'perf_a', 'client', 'pa-a-ig', now() - interval '1 day', 10);
  perform perf_sync_lineage('pa_a');
  insert into t values ('sincronização não toca na gravada', true, (select lineage_mode from publication_lineage where id = lid) = 'gravada');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  p := (select x from jsonb_array_elements(perf_publications('pa_a', '{"limit":200}')->'items') x where x->>'reel_id' = 'novo1');
  insert into t values ('publicação gravada mostra as etiquetas gravadas', true, p->>'lineage_mode' = 'gravada' and p->>'origin' = 'sistema'
    and p->>'persona_phrase' = 'o homem mais rico' and p->>'content_id' = 'pa_a-g1' and (p->>'duration_s')::numeric = 31);

  -- isolamento: B nunca vê A
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform perf_center('pa_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê a visão geral de A (42501)', true, st = '42501');
  begin perform perf_publications('pa_a', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê as publicações de A (42501)', true, st = '42501');
  begin perform perf_levers('pa_a', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê as alavancas de A (42501)', true, st = '42501');
  begin perform perf_origin_set('pa_a', 'pa-a-ig', 'q1', 'sistema', 'tentativa'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não corrige a origem em A (42501)', true, st = '42501');
  j := perf_publications('pa_b', '{}');
  insert into t values ('B vê só a sua publicação', true, (j->>'total')::int = 1 and j->'items'->0->>'reel_id' = 'b1');
  begin perform 1 from perf_readings limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabelas fechadas a leitura direta (42501)', true, st = '42501');
  insert into t values ('sem privilégios diretos nas tabelas novas', true, not has_table_privilege('authenticated', 'public.publication_lineage', 'select')
    and not has_table_privilege('anon', 'public.perf_accounts', 'select'));
  begin perform perf_capture('pa_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('recolha não é chamável pelo browser (42501)', true, st = '42501');

  -- código de equipa: lê o seu cliente, não muda nada, não lê outros
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := perf_center('numeiro', tok);
  insert into t values ('código de equipa lê o centro do numeiro', true, jsonb_array_length(j->'accounts') >= 1 and not (j->>'can_manage')::boolean);
  begin perform perf_center('pa_a', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código do numeiro não lê A (42501)', true, st = '42501');
  begin perform perf_account_set('numeiro', 'numeiro-ig', '{"tier":"B"}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não muda camadas (42501)', true, st = '42501');
  begin perform perf_center('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código não lê (42501)', true, st = '42501');
  execute 'reset role';

  insert into t values ('correções ficam no histórico de ações', true,
    (select count(*) from audit_events where workspace_id = 'pa_a' and action in ('perf.account_set', 'perf.origin_set', 'perf.lineage_recorded')) = 4);
  insert into t values ('analytics.manage só para owner, admin e gestor', true,
    (select array_agg(role order by role) from role_capabilities where capability = 'analytics.manage') = array['manager', 'workspace_admin', 'workspace_owner']);
  insert into t values ('flag perf.center registada, por defeito só o dono', true,
    (select default_stage from feature_flag_defs where key = 'perf.center') = 'owner');
  insert into t values ('perf-tick agendado de hora a hora', true, exists (select 1 from cron.job where jobname = 'perf-tick'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
