-- supabase/tests/w10_referencias_link.sql : referências por link (REF-01..04, FR-07-01, FR-07-04). Identidade do vídeo e
-- repetidos, flag, capacidades, fila idempotente, worker com lease, dissecção versionada e imutável, métricas com índice
-- calculado no servidor, guiões da via rápida (3 hooks, semelhança, em revisão), isolamento entre clientes. Rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cc uuid := gen_random_uuid();
  u_cb uuid := gen_random_uuid(); u_ag_b uuid := gen_random_uuid();
  cfg jsonb := '{"language":"pt-PT","voice":"Voz","guardrails":["Regra"],"formats":{"a":{"share":1,"min":0.5,"max":1,"palavras":[50,100]}},"pipeline":{"scripts_per_day":5,"hooks_per_slot":3,"critic_threshold":7,"concurrency":2}}';
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  j jsonb; j2 jsonb; c jsonb; s jsonb; st text; msg text; ok int := 0; bad int := 0; res text := ''; r record;
  r1 bigint; r2 bigint; r3 bigint; rb bigint; ja uuid; ja2 uuid; js uuid; an jsonb; n int;
  dis jsonb := '{"hook":{"texto":"Ninguém te diz isto sobre dinheiro","mecanismo":"segredo revelado","segundos":2.5},"maquina":"isco e revelação",
                 "tese":"Poupar não te torna rico","inimigo":"o conselho de poupar","estrutura":[{"inicio_s":0,"fim_s":3,"parte":"hook","resumo":"promessa"},
                 {"inicio_s":3,"fim_s":20,"parte":"mecanismo","resumo":"explica"},{"inicio_s":"x","parte":"cta"}],
                 "duracao_s":31,"palavras_por_segundo":3.2,"ritmo":"rápido","idioma":"pt",
                 "afirmacoes_terceiros":[{"texto":"O banqueiro X roubou milhões","pessoa":"X","tipo":"acusação de crime"},{"pessoa":"sem texto"}],
                 "campo_estranho":"ignorado"}';
  script jsonb := '{"hooks":[{"hook":"Hook um","mecanismo":"contra"},{"hook":"Hook dois"},{"text":"Hook três"}],"corpo":"Linha um.\nLinha dois.",
                    "formato":"a","tema":"Tema adaptado","similarity":0.04,"notas":"Afirmações por verificar: nenhuma"}';
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_ra', 'Refs A', 'ra', org, 'Europe/Lisbon'), ('ws_rb', 'Refs B', 'rb', org, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'rl-own@test.invalid'),(u_ag,'rl-ag@test.invalid'),(u_ca,'rl-ca@test.invalid'),(u_cc,'rl-cc@test.invalid'),
    (u_cb,'rl-cb@test.invalid'),(u_ag_b,'rl-agb@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_ag_b, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_ra', u_ag, 'agency_staff', 'manager'), ('ws_ra', u_ca, 'client_staff', 'workspace_admin'), ('ws_ra', u_cc, 'client_staff', 'contributor'),
    ('ws_rb', u_cb, 'client_staff', 'workspace_admin'), ('ws_rb', u_ag_b, 'agency_staff', 'manager');
  insert into agent_config_versions (workspace_id, version_no, status, config, validation, activated_at)
    values ('ws_ra', 1, 'active', cfg, '{"ok":true,"errors":[],"warnings":[]}', now()), ('ws_rb', 1, 'active', cfg, '{"ok":true,"errors":[],"warnings":[]}', now());
  insert into accounts (id, client_id, role, platform, handle) values ('ws_ra-autor', 'ws_ra', 'reference', 'instagram', 'autor_x');
  insert into reels (id, client_id, platform, owner, role, url, views, duration, account_id, transcript)
  select 'AUTX' || i, 'ws_ra', 'instagram', 'autor_x', 'reference', 'https://www.instagram.com/reel/AUTX' || i || '/', i * 1000, 30, 'ws_ra-autor', '' from generate_series(1, 5) i;
  insert into reels (id, client_id, platform, owner, role, url, views, duration, account_id, transcript)
  values ('CxYz_9-Ab', 'ws_ra', 'instagram', 'autor_x', 'reference', 'https://www.instagram.com/reel/CxYz_9-Ab/', 50000, 31, 'ws_ra-autor', 'Transcrição recolhida pelo scraper.');
  -- só as execuções deste teste na fila
  update agent_jobs set next_attempt_at = now() + interval '1 day' where status = 'queued';
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, engine_worker;

  -- ── identidade do vídeo ──
  insert into t values ('ref_key: reel', true, reel_ref_key('https://www.instagram.com/reel/CxYz_9-Ab/?igsh=abc') = 'instagram:CxYz_9-Ab');
  insert into t values ('ref_key: /p/ e /reels/ e com utilizador = mesmo vídeo', true,
    reel_ref_key('instagram.com/p/CxYz_9-Ab') = 'instagram:CxYz_9-Ab' and reel_ref_key('https://instagram.com/reels/CxYz_9-Ab/') = 'instagram:CxYz_9-Ab'
    and reel_ref_key('https://www.instagram.com/autor_x/reel/CxYz_9-Ab/') = 'instagram:CxYz_9-Ab');
  insert into t values ('ref_key: shortcode distingue maiúsculas', true, reel_ref_key('https://www.instagram.com/reel/cxyz_9-ab/') <> 'instagram:CxYz_9-Ab');
  insert into t values ('ref_key: tiktok vídeo, /v/ e embed', true,
    reel_ref_key('https://www.tiktok.com/@alguem.pt/video/7301234567890123456?lang=pt') = 'tiktok:7301234567890123456'
    and reel_ref_key('https://m.tiktok.com/v/7301234567890123456.html') = 'tiktok:7301234567890123456'
    and reel_ref_key('https://www.tiktok.com/embed/v2/7301234567890123456') = 'tiktok:7301234567890123456');
  insert into t values ('ref_key: outros links ficam nulos', true, reel_ref_key('https://youtube.com/watch?v=1') is null and reel_ref_key('https://vm.tiktok.com/ZMabc/') is null);

  execute 'set local role authenticated';
  -- ── flag (agência por defeito) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform reference_paste('ws_ra', 'https://www.instagram.com/reel/CxYz_9-Ab/'); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('flag na fase agência: admin do cliente recusado (55000)', true, st = '55000' and msg = 'funcionalidade_desligada');

  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := reference_paste('ws_ra', 'https://www.instagram.com/reel/CxYz_9-Ab/?igsh=xyz', true);
  r1 := (j->'reference'->>'id')::bigint; ja := (j->'job'->>'id')::uuid;
  insert into t values ('colar reel: cria, liga o reel recolhido, deteta autor e plataforma', true,
    (j->>'created')::boolean and j->'reference'->>'ref_key' = 'instagram:CxYz_9-Ab' and j->'reference'->>'reel_id' = 'CxYz_9-Ab'
    and j->'reference'->>'platform' = 'instagram' and j->'reference'->>'creator' = 'autor_x' and j->'reference'->'metrics'->>'source' = 'scraper');
  insert into t values ('colar com dissecar: execução em fila do tipo reference_analysis', true, j->'job'->>'status' = 'queued' and j->'job'->>'kind' = 'reference_analysis');
  j2 := reference_paste('ws_ra', 'instagram.com/p/CxYz_9-Ab');
  insert into t values ('mesmo vídeo noutro formato de link = repetido, devolve a existente', true,
    not (j2->>'created')::boolean and (j2->>'duplicate')::boolean and (j2->'reference'->>'id')::bigint = r1);
  begin perform reference_create('ws_ra', '{"url":"https://www.instagram.com/autor_x/reel/CxYz_9-Ab/"}'); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('adicionar por link também deteta pelo ref_key (PT409)', true, st = 'PT409' and msg = 'duplicado:' || r1);
  j := reference_paste('ws_ra', 'https://www.tiktok.com/@alguem.pt/video/7301234567890123456?lang=pt');
  r2 := (j->'reference'->>'id')::bigint;
  insert into t values ('colar TikTok: autor do link, sem execução se não pedida', true, j->'reference'->>'creator' = 'alguem.pt' and j->'job' = 'null'::jsonb
    and j->'reference'->>'titulo' = 'TikTok de @alguem.pt · 7301234567890123456');
  insert into t values ('TikTok /v/ = repetido', true, (reference_paste('ws_ra', 'https://m.tiktok.com/v/7301234567890123456.html')->>'duplicate')::boolean);
  j := reference_paste('ws_ra', 'https://vm.tiktok.com/ZMabc123/');
  r3 := (j->'reference'->>'id')::bigint;
  insert into t values ('link curto do TikTok entra sem ref_key e repete pelo link', true, j->'reference'->>'ref_key' is null
    and (reference_paste('ws_ra', 'vm.tiktok.com/ZMabc123')->>'duplicate')::boolean);
  begin perform reference_paste('ws_ra', 'https://youtube.com/watch?v=1'); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('link que não é Reel nem TikTok (22023)', true, st = '22023' and msg = 'link_nao_suportado');
  begin perform reference_paste('ws_ra', '   '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link vazio (22023)', true, st = '22023');

  -- ── fila idempotente ──
  j := reference_analyze(r1);
  insert into t values ('pedir de novo com execução ativa devolve a mesma', true, (j->'job'->>'id')::uuid = ja);
  begin perform reference_analyze(r2, 'curta'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('transcrição manual curta demais (22023)', true, st = '22023');
  j := reference_analyze(r2, 'Esta é a transcrição colada à mão pela equipa, com mais de vinte caracteres.');
  insert into t values ('transcrição manual vai para a execução', true, j->'job'->>'status' = 'queued');
  begin perform reference_adapt(r1); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('3 guiões sem dissecção (22023)', true, st = '22023' and msg = 'sem_disseccao');
  j := reference_analysis_get(r1);
  insert into t values ('detalhe: sem dissecção, execução em fila, pode dissecar, worker por atualizar', true,
    j->'analysis' = 'null'::jsonb and j->'analysis_job'->>'status' = 'queued' and (j->'can'->>'analyze')::boolean and not (j->>'worker_ready')::boolean);
  insert into t values ('linha da lista mostra a execução', true,
    (select z->'job'->>'status' from jsonb_array_elements(references_list('ws_ra')) z where (z->>'id')::bigint = r1) = 'queued');

  -- ── permissões ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform reference_analyze(r1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não pede dissecção (42501)', true, st = '42501');
  begin perform reference_paste('ws_ra', 'https://www.instagram.com/reel/NOVOcode1/'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contributor não cola links (42501)', true, st = '42501');
  insert into t values ('contributor lê o detalhe sem poder dissecar', true, not (reference_analysis_get(r1)->'can'->>'analyze')::boolean);

  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform reference_analysis_get(r1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê a dissecção de A (42501)', true, st = '42501');
  begin perform reference_analyze(r1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não pede dissecção em A (42501)', true, st = '42501');
  begin perform reference_paste('ws_ra', 'https://www.instagram.com/reel/NOVOcode2/'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não cola em A (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag_b, 'role','authenticated')::text, true);
  begin perform reference_adapt(r1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência só em B não pede guiões em A (42501)', true, st = '42501');
  j := reference_paste('ws_rb', 'https://www.instagram.com/reel/CxYz_9-Ab/');
  rb := (j->'reference'->>'id')::bigint;
  insert into t values ('o mesmo vídeo noutro cliente não é repetido, nem liga reel de A', true, (j->>'created')::boolean and j->'reference'->>'reel_id' is null);
  insert into t values ('B só vê as suas referências (RLS)', true, (select count(*) from reference_items) = 1);
  insert into t values ('tabelas novas fechadas à API', true, not has_table_privilege('authenticated', 'reference_analyses', 'select')
    and not has_table_privilege('authenticated', 'reference_script_outputs', 'select'));
  execute 'reset role';

  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin perform reference_paste('numeiro', 'https://www.instagram.com/reel/NOVOcode3/', false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não cola links (42501)', true, st = '42501');
  begin perform worker_reference_save(ja, 'w', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anon não chama funções do worker (42501)', true, st = '42501');
  execute 'reset role';

  -- ── worker ──
  -- a agenda diária corre dentro do worker_claim: depois da hora do cliente (18:00 no Numeiro) enfileiraria a corrida do dia
  -- e o "worker antigo" apanhava-a. Corre-se já (idempotente por dia) e empurra-se para amanhã, para o teste não depender da hora.
  perform agent_schedule_tick();
  update agent_jobs set next_attempt_at = now() + interval '1 day' where status = 'queued' and id <> ja;
  execute 'grant engine_worker to current_user';
  execute 'set local role engine_worker';
  c := worker_claim('w-ref-1', array['daily_pipeline','scouts','analysis']);
  insert into t values ('worker antigo (sem os tipos novos) não apanha a dissecção', true, c is null);
  c := worker_claim('w-ref-1', array['reference_analysis']);
  insert into t values ('worker novo apanha a dissecção com persona e configuração', true, (c->'job'->>'id')::uuid = ja and c->'config'->>'voice' = 'Voz' and c ? 'persona');
  begin perform worker_reference_context(ja, 'outro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('contexto sem a lease (PT409)', true, st = 'PT409');
  j := worker_reference_context(ja, 'w-ref-1');
  insert into t values ('contexto: link, transcrição do reel recolhido e mediana do autor', true,
    j->'reference'->>'url' like '%CxYz_9-Ab%' and j->'reel'->>'transcript' = 'Transcrição recolhida pelo scraper.'
    and (j->'author'->>'median_views')::numeric = 3500 and (j->'author'->>'sample')::int = 6 and j->>'manual_transcript' is null);
  begin perform worker_reference_save(ja, 'w-ref-1', jsonb_build_object('transcript', 'x', 'transcript_source', 'manual', 'dissection', dis,
     'model', 'm', 'prompt_version', 'p', 'agent_version', 'a')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('origem manual sem transcrição colada é recusada (22023)', true, st = '22023');
  begin perform worker_reference_save(ja, 'w-ref-1', jsonb_build_object('transcript', 'x', 'transcript_source', 'scraper',
     'dissection', jsonb_set(dis, '{maquina}', '"inventada"'), 'model', 'm', 'prompt_version', 'p', 'agent_version', 'a')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('máquina fora da lista é recusada (22023)', true, st = '22023');
  begin perform worker_reference_save(ja, 'w-ref-1', jsonb_build_object('transcript', 'x', 'transcript_source', 'scraper', 'dissection', dis)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem modelo e versões de prompt/agente é recusada (22023)', true, st = '22023');
  s := worker_reference_save(ja, 'w-ref-1', jsonb_build_object('transcript', 'Transcrição recolhida pelo scraper.', 'transcript_source', 'scraper',
     'dissection', dis, 'metrics', '{"views":50000,"likes":100,"comments":20,"duration_s":31,"owner":"autor_x","index":999}'::jsonb,
     'model', 'claude-sonnet-5-5', 'prompt_version', 'ref-2026-11-06.1', 'agent_version', 'ref_dissector@1', 'tokens_in', 1200, 'tokens_out', 300));
  insert into t values ('grava a versão 1', true, (s->>'created')::boolean and (s->>'version')::int = 1);
  insert into t values ('repetir a gravação da mesma execução não duplica', true, not (worker_reference_save(ja, 'w-ref-1', '{}')->>'created')::boolean);
  perform worker_finish(ja, 'w-ref-1', true, '{"versao":1}', null, false, 0.01, 1200, 300, 'run-t');
  execute 'reset role';
  begin update reference_analyses set model = 'x'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dissecção guardada é imutável (42501)', true, st = '42501');
  insert into t values ('auditado como motor, com modelo e versão do prompt', true, exists (select 1 from audit_events where action = 'reference.analyzed'
    and entity_id = r1::text and actor_kind = 'system' and after->>'prompt_version' = 'ref-2026-11-06.1'));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := reference_analysis_get(r1); an := j->'analysis';
  insert into t values ('detalhe mostra a dissecção com proveniência', true, (an->>'version')::int = 1 and an->>'model' = 'claude-sonnet-5-5'
    and an->>'agent_version' = 'ref_dissector@1' and an->>'transcript_source' = 'scraper' and an->'dissection'->>'maquina' = 'isco e revelação');
  insert into t values ('campos desconhecidos descartados; estrutura limpa; afirmação sem texto descartada', true,
    not (an->'dissection' ? 'campo_estranho') and jsonb_array_length(an->'dissection'->'estrutura') = 3
    and not (an->'dissection'->'estrutura'->2 ? 'inicio_s') and (an->>'third_party_flags')::int = 1);
  insert into t values ('índice calculado no servidor face à mediana (não o do motor)' || (an->'metrics')::text, true, (an->'metrics'->>'index')::numeric = 14.29
    and (an->'metrics'->>'author_median_views')::numeric = 3500 and an->'metrics'->>'source' = 'scraper');
  insert into t values ('classificação vazia completada (hook, idioma), não sobrescreve', true,
    j->'reference'->>'hook' = 'Ninguém te diz isto sobre dinheiro' and j->'reference'->>'idioma' = 'pt' and (j->'reference'->>'duracao_s')::int = 31);
  insert into t values ('linha da lista mostra a dissecção', true,
    (select (z->'dissection'->>'version')::int from jsonb_array_elements(references_list('ws_ra')) z where (z->>'id')::bigint = r1) = 1);
  j := reference_analyze(r1);
  ja2 := (j->'job'->>'id')::uuid;
  insert into t values ('nova dissecção depois de concluída = nova execução', true, ja2 <> ja);
  j := reference_adapt(r1); js := (j->'job'->>'id')::uuid;
  insert into t values ('3 guiões: execução reference_scripts em fila', true, j->'job'->>'kind' = 'reference_scripts' and j->'job'->>'status' = 'queued');
  execute 'reset role';

  update agent_jobs set next_attempt_at = now() + interval '1 day' where id = ja2;
  execute 'set local role engine_worker';
  c := worker_claim('w-ref-1', array['reference_scripts']);
  insert into t values ('worker apanha a adaptação', true, (c->'job'->>'id')::uuid = js);
  j := worker_reference_context(js, 'w-ref-1');
  insert into t values ('contexto da adaptação traz a dissecção usada', true, (j->'analysis'->>'version')::int = 1 and j->'analysis'->'dissection'->>'tese' = 'Poupar não te torna rico'
    and jsonb_typeof(j->'approved_scripts') = 'array');
  begin perform worker_reference_save_script(js, 'w-ref-1', 1, jsonb_set(script, '{hooks}', '[{"hook":"só um"}]')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião sem 3 hooks é recusado (22023)', true, st = '22023');
  begin perform worker_reference_save_script(js, 'w-ref-1', 1, jsonb_set(script, '{similarity}', '0.6')); st := 'none'; msg := ''; exception when others then st := sqlstate; msg := sqlerrm; end;
  insert into t values ('guião demasiado parecido com o original é recusado (22023)', true, st = '22023' and msg = 'demasiado_parecido');
  begin perform worker_reference_save_script(js, 'w-ref-1', 1, script - 'similarity'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião sem medida de semelhança é recusado (22023)', true, st = '22023');
  begin perform worker_reference_save_script(js, 'w-ref-1', 4, script); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('só 3 guiões por pedido (slot 4 recusado)', true, st = '22023');
  begin perform worker_reference_save(js, 'w-ref-1', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gravar dissecção numa execução de guiões (22023)', true, st = '22023');
  s := worker_reference_save_script(js, 'w-ref-1', 1, script);
  insert into t values ('guião 1 gravado', true, (s->>'created')::boolean);
  insert into t values ('repetir o slot não duplica', true, worker_reference_save_script(js, 'w-ref-1', 1, script)->>'id' = s->>'id');
  perform worker_reference_save_script(js, 'w-ref-1', 2, script);
  perform worker_reference_save_script(js, 'w-ref-1', 3, script);
  perform worker_finish(js, 'w-ref-1', true, '{"guioes":3}', null, false, 0.02, 10, 10, 'run-s');
  execute 'reset role';
  select count(*) into n from guioes where client_id = 'ws_ra' and origem = 'via_rapida';
  insert into t values ('3 guiões em revisão, via rápida, 3 hooks, ligados à referência', true, n = 3
    and not exists (select 1 from guioes where client_id = 'ws_ra' and origem = 'via_rapida' and (editorial_status <> 'in_review' or validado or jsonb_array_length(hooks) <> 3
                    or not ('via rápida' = any (tags)) or notas not like 'Via rápida: adaptado da referência #' || r1 || '%'))
    and (select count(*) from reference_links where reference_id = r1 and added_kind = 'engine') = 3);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := reference_analysis_get(r1);
  insert into t values ('detalhe lista os 3 guiões com semelhança; flag desligada tira os botões ao cliente', true,
    jsonb_array_length(j->'scripts') = 3 and (j->'scripts'->0->>'similarity')::numeric = 0.04 and not (j->'can'->>'adapt')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  insert into t values ('cliente B não vê nada da via rápida de A', true, jsonb_array_length(reference_analysis_get(rb)->'scripts') = 0
    and (select count(*) from guioes where client_id = 'ws_ra') = 0);
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('references.link', org, 'ws_ra', 'all');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := reference_paste('ws_ra', 'https://www.instagram.com/reel/NOVOcode9/');
  insert into t values ('flag ligada para o cliente A: o admin do cliente cola', true, (j->>'created')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform reference_paste('ws_rb', 'https://www.instagram.com/reel/NOVOcode9/'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag de A não liga B (55000)', true, st = '55000');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
