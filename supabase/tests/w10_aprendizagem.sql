-- supabase/tests/w10_aprendizagem.sql : aprendizagem contínua parte 1 (LRN-01, LRN-02, LRN-03; dois níveis LRN-04).
-- Dois clientes (lr_a, lr_b), equipa de cada cliente, staff da agência só em A, dono e admin da agência, código de equipa de A.
-- Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_v uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_aa uuid := gen_random_uuid();
  tok text := 'lr-a-team-code-0123456789abcdef';
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int; g guioes; gm text; job uuid; l1 uuid; l2 uuid; la uuid; v1 uuid;
  sig_b uuid; tz text; pnow timestamptz;
  long_corpo text := 'Esta frase do motor tem muitas palavras que vão desaparecer quase todas porque a pessoa reescreveu o texto inteiro do princípio ao fim.';
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('lr_a', 'Lições A', 'lra', org, 'Europe/Lisbon'), ('lr_b', 'Lições B', 'lrb', org, 'Europe/Lisbon');
  insert into agent_config_versions (workspace_id, version_no, status, config, created_label)
  select w, 1, 'active', config, 'fixture' from (select config from agent_config_versions where workspace_id = 'numeiro' and status = 'active' limit 1) c, unnest(array['lr_a','lr_b']) w;
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'lr-adm@test.invalid'),(u_rev,'lr-rev@test.invalid'),(u_v,'lr-v@test.invalid'),(u_b,'lr-b@test.invalid'),
    (u_own,'lr-own@test.invalid'),(u_ag,'lr-ag@test.invalid'),(u_aa,'lr-aa@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_aa, 'agency_admin');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('lr_a', u_adm, 'client_staff', 'workspace_admin'), ('lr_a', u_rev, 'client_staff', 'reviewer'), ('lr_a', u_v, 'client_staff', 'viewer'),
    ('lr_b', u_b, 'client_staff', 'workspace_admin'), ('lr_a', u_ag, 'agency_staff', 'manager'), ('lr_a', u_aa, 'agency_staff', 'manager');
  insert into studio_tokens (token, client_id, label) values (tok, 'lr_a', 'Equipa LR');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['learn.edits','learn.lessons','learn.rework']) k, unnest(array['lr_a','lr_b']) w;

  -- guiões do motor (inseridos sem RPC: a versão 1 fica como 'engine')
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, cta, editorial_status) values
    ('lr_a-1', 'lr_a', current_date, 1, 'lista', 'T1', '[{"text":"Sabias que isto muda tudo?","mecanismo":"pergunta"}]', 'Primeira frase. Segunda frase curta.', 'Segue para mais', 'in_review'),
    ('lr_a-2', 'lr_a', current_date, 2, 'lista', 'T2', '[{"text":"Ninguém te conta isto","mecanismo":"segredo"}]', 'Um corpo com várias palavras que vai mudar um pouco no fim do texto todo aqui.', 'Comenta', 'in_review'),
    ('lr_a-3', 'lr_a', current_date, 3, 'mito', 'T3', '[{"text":"O mito que todos repetem","mecanismo":"contra"}]', long_corpo, null, 'in_review'),
    ('lr_a-4', 'lr_a', current_date, 4, 'mito', 'T4', '[{"text":"Hook fraco do motor","mecanismo":"pergunta"}]', 'Corpo para rejeitar.', null, 'in_review'),
    ('lr_b-1', 'lr_b', current_date, 1, 'lista', 'B1', '[{"text":"Hook de B","mecanismo":"pergunta"}]', 'Corpo de B com texto.', null, 'in_review');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  -- leitura direta só para as verificações deste teste (tudo volta atrás no fim; as RPCs não dependem disto)
  grant select on lrn_edit_signals, lrn_lessons, lrn_lesson_versions, content_transition_reasons, agent_jobs, audit_events to authenticated;
  create policy t_lrn_s on lrn_edit_signals for select to authenticated using (true);
  create policy t_lrn_l on lrn_lessons for select to authenticated using (true);
  create policy t_lrn_v on lrn_lesson_versions for select to authenticated using (true);
  create policy t_lrn_r on content_transition_reasons for select to authenticated using (true);
  create policy t_lrn_j on agent_jobs for select to authenticated using (true);
  create policy t_lrn_a on audit_events for select to authenticated using (true);
  execute 'set local role authenticated';

  -- ═════ LRN-01 ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := lrn_edit_options('lr_a');
  insert into t values ('opções: flag ligada e as 8 categorias do PRD', true, (j->>'enabled')::boolean
    and (select count(*) from jsonb_array_elements(j->'codes') c where c->>'source' = 'lrn') = 8 and (j->>'threshold')::numeric = 0.30);
  perform rework_reasons_seed('lr_a');
  j := lrn_edit_options('lr_a');
  insert into t values ('opções juntam a taxonomia FR-17-10 sem repetir hook_fraco', true,
    exists (select 1 from jsonb_array_elements(j->'codes') c where c->>'code' = 'factos' and c->>'group' = 'facto')
    and (select count(*) from jsonb_array_elements(j->'codes') c where c->>'code' = 'hook_fraco') = 1);
  j := content_edit_ratio('lr_a-1');
  insert into t values ('guião do motor sem edição: distância 0', true, (j->>'engine')::boolean and (j->>'ratio')::numeric = 0 and not (j->>'required')::boolean);

  g := content_decide_learned('lr_a-1', 'approved');
  insert into t values ('aprovar sem editar: aprovado e sinal positivo', true, g.editorial_status = 'approved'
    and exists (select 1 from lrn_edit_signals where content_id = 'lr_a-1' and kind = 'approved_unedited' and edit_ratio = 0 and version_id = g.approved_version_id));

  -- edição pequena com motivo ao concluir
  g := content_save('lr_a-2', '{"corpo":"Um corpo com várias palavras que vai mudar um pouco no fim do texto todo ali."}');
  j := content_edit_reason('lr_a-2', array['frase_longa'], 'mais natural');
  insert into t values ('motivo da edição guardado com o par motor → versão', true, (j->>'recorded')::boolean and (j->>'ratio')::numeric between 0.01 and 0.3
    and exists (select 1 from lrn_edit_signals s join content_versions ev on ev.id = s.engine_version_id
                where s.id = (j->>'signal_id')::uuid and s.kind = 'edit' and ev.created_kind = 'engine' and s.codes = array['frase_longa']));
  insert into t values ('repetir o motivo na mesma versão não duplica', true, (content_edit_reason('lr_a-2', array['ritmo'])->>'signal_id') = j->>'signal_id');
  begin perform content_edit_reason('lr_a-2', array['inventado']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('motivo desconhecido recusado (22023)', true, st = '22023');
  begin perform content_edit_reason('lr_a-2', '{}', '  '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('motivo vazio recusado ao concluir', true, st = '22023');
  insert into t values ('ratio mostra o motivo da edição antes de aprovar', true, jsonb_array_length(content_edit_ratio('lr_a-2')->'edits') = 1);
  g := content_decide_learned('lr_a-2', 'approved');
  insert into t values ('aprovar edição pequena sem motivo: passa e fica "sem motivo"', true, g.editorial_status = 'approved'
    and exists (select 1 from lrn_edit_signals where content_id = 'lr_a-2' and kind = 'approved' and codes = '{}' and note is null));

  -- edição grande: motivo obrigatório ao aprovar (decisão do PRD), guardar nunca é bloqueado
  g := content_save('lr_a-3', '{"corpo":"Texto novo escrito à mão pela equipa.","hooks":[{"text":"Outro hook","mecanismo":"contra"}]}');
  insert into t values ('guardar uma edição grande não é bloqueado', true, g.corpo = 'Texto novo escrito à mão pela equipa.');
  insert into t values ('ratio acima de 30% pede motivo', true, (content_edit_ratio('lr_a-3')->>'required')::boolean);
  begin perform content_decide_learned('lr_a-3', 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aprovar edição > 30% sem motivo recusado (22023)', true, st = '22023');
  insert into t values ('recusa não deixou o guião aprovado', true, (select editorial_status from guioes where id = 'lr_a-3') = 'in_review');
  g := content_decide_learned('lr_a-3', 'approved', array['nao_soa_cliente','hook_fraco']);
  insert into t values ('aprovar com chips: sinal com distância > 0,3', true, g.editorial_status = 'approved'
    and exists (select 1 from lrn_edit_signals where content_id = 'lr_a-3' and kind = 'approved' and edit_ratio > 0.3 and 'hook_fraco' = any (codes)));

  -- rejeitar com categoria FR-17-10 e chips
  g := content_decide_learned('lr_a-4', 'rejected', array['hook_fraco'], null, 'O hook não prende', 'hook_fraco');
  insert into t values ('rejeitar: estado, categoria FR-17-10 e sinal com o texto', true, g.editorial_status = 'rejected'
    and exists (select 1 from content_transition_reasons where content_id = 'lr_a-4' and code = 'hook_fraco')
    and exists (select 1 from lrn_edit_signals where content_id = 'lr_a-4' and kind = 'rejected' and note = 'O hook não prende'));
  begin perform content_decide_learned('lr_a-4', 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('transição inválida continua recusada pela função de sempre', true, st = '22023');

  -- guião escrito à mão: decide como sempre, sem sinal
  gm := (content_create('lr_a', '{"corpo":"Escrito à mão."}')).id;
  g := content_decide_learned(gm, 'approved');
  insert into t values ('guião manual aprovado sem sinal de aprendizagem', true, g.editorial_status = 'approved' and not exists (select 1 from lrn_edit_signals where content_id = gm));
  begin perform content_edit_reason(gm, array['ritmo']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('motivo de edição em guião manual recusado', true, st = '22023');

  -- leitor não decide
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform content_decide_learned('lr_a-1', 'rejected', '{}', null, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não decide (42501)', true, st = '42501');
  begin perform content_edit_reason('lr_a-2', array['ritmo']); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não regista motivo de edição (42501)', true, st = '42501');

  -- cliente B contra A
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_decide_learned('lr_a-3', 'rejected', '{}', null, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não decide guião de A', true, st = '42501');
  begin perform content_edit_ratio('lr_a-3'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê a distância de A', true, st = '42501');
  begin perform lrn_edit_options('lr_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê as opções de A', true, st = '42501');
  g := content_decide_learned('lr_b-1', 'changes_requested', array['ritmo'], null, 'mais ritmo');
  insert into t values ('B decide o seu guião', true, g.editorial_status = 'changes_requested');
  sig_b := (select id from lrn_edit_signals where content_id = 'lr_b-1');

  -- flag desligada: 55000
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'learn.edits' and workspace_id = 'lr_b';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_decide_learned('lr_b-1', 'rejected', '{}', null, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag learn.edits desligada: 55000', true, st = '55000');
  insert into t values ('opções dizem desligado', true, not (lrn_edit_options('lr_b')->>'enabled')::boolean);

  -- código de equipa: decide guiões (como hoje), nunca lições
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform content_decide_learned('lr_a-4', 'approved', '{}', null, null, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa: flag no estágio "all" passa à função de sempre (rejeitado→aprovado inválido)', true, st = '22023');
  begin perform lrn_lessons_list('lr_a', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não lê lições', true, st = '42501');
  execute 'reset role'; execute 'set local role authenticated';

  -- ═════ LRN-02: fila e worker ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform lrn_lessons_run('lr_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não põe o Editor de lições na fila', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := lrn_lessons_run('lr_a');
  job := (j->>'id')::uuid;
  insert into t values ('Editor de lições na fila', true, j->>'kind' = 'lesson_editor' and j->>'status' = 'queued');
  insert into t values ('pedir outra vez devolve a mesma execução', true, (lrn_lessons_run('lr_a')->>'id')::uuid = job);

  execute 'reset role';
  update agent_jobs set status = 'running', locked_by = 'lr-worker', locked_until = now() + interval '10 minutes',
         params = params || jsonb_build_object('until', now() + interval '1 minute') where id = job;
  begin perform worker_lesson_pairs(job, 'outro-worker'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker sem lease recusado', true, st = 'PT409');
  j := worker_lesson_pairs(job, 'lr-worker');
  insert into t values ('pares só deste cliente, com antes/depois e motivos', true,
    jsonb_array_length(j->'pairs') = (select count(*) from lrn_edit_signals where workspace_id = 'lr_a')
    and not exists (select 1 from jsonb_array_elements(j->'pairs') p where p->>'content_id' like 'lr_b%')
    and exists (select 1 from jsonb_array_elements(j->'pairs') p where p->>'kind' = 'approved' and (p->>'no_reason')::boolean)
    and exists (select 1 from jsonb_array_elements(j->'pairs') p where p->>'content_id' = 'lr_a-3' and p->'before'->>'corpo' = long_corpo));
  begin perform worker_lesson_save(job, 'lr-worker', 1, jsonb_build_object('category', 'tom', 'text', 'Usa frases curtas.', 'signal_ids', jsonb_build_array(sig_b)));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('evidência de outro cliente não conta (sem_evidencia)', true, st = '22023');
  begin perform worker_lesson_save(job, 'lr-worker', 1, jsonb_build_object('category', 'xpto', 'text', 'Usa frases curtas.')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('categoria inválida recusada', true, st = '22023');
  j := worker_lesson_save(job, 'lr-worker', 1, jsonb_build_object('category', 'tom', 'text', 'Escreve como o cliente fala: frases curtas, sem jargão.',
         'rationale', 'Duas edições cortaram frases longas.', 'model', 'claude-sonnet-5-5', 'prompt_version', 'lessons-v1', 'agent_version', '1.0',
         'signal_ids', (select jsonb_agg(id) from lrn_edit_signals where workspace_id = 'lr_a' and kind in ('edit','approved')) || jsonb_build_array(sig_b)));
  l1 := (j->>'lesson_id')::uuid;
  insert into t values ('lição proposta com evidência calculada na base', true, (j->>'created')::boolean
    and (select (evidence->>'edits')::int from lrn_lessons where id = l1) = (select count(*) from lrn_edit_signals where workspace_id = 'lr_a' and kind in ('edit','approved'))
    and (select jsonb_array_length(evidence->'examples') between 1 and 3 from lrn_lessons where id = l1)
    and not (select evidence::text like '%lr_b%' from lrn_lessons where id = l1));
  insert into t values ('gravar outra vez a mesma posição não duplica', true,
    not (worker_lesson_save(job, 'lr-worker', 1, jsonb_build_object('category', 'tom', 'text', 'Outra coisa qualquer.', 'signal_ids', jsonb_build_array(sig_b)))->>'created')::boolean);
  l2 := (worker_lesson_save(job, 'lr-worker', 2, jsonb_build_object('category', 'hook', 'text', 'Evita hooks em pergunta genérica.',
         'signal_ids', (select jsonb_agg(id) from lrn_edit_signals where content_id = 'lr_a-4')))->>'lesson_id')::uuid;

  -- ═════ LRN-03: aprovar, editar, rejeitar, versões ═════
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := lrn_lessons_list('lr_a');
  insert into t values ('lista: 2 propostas, sem versão em vigor, admin pode aprovar, sem secção da agência', true,
    jsonb_array_length(j->'proposed') = 2 and j->'active' = 'null'::jsonb and (j->'can'->>'approve')::boolean and j->'agency' = 'null'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform lrn_lessons_list('lr_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê as lições de A', true, st = '42501');
  insert into t values ('lista de B não tem as propostas de A', true, jsonb_array_length(lrn_lessons_list('lr_b')->'proposed') = 0);
  begin perform lrn_lesson_decide(l1, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não aprova lição de A', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  insert into t values ('revisor lê as lições', true, jsonb_array_length(lrn_lessons_list('lr_a')->'proposed') = 2);
  begin perform lrn_lesson_decide(l1, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisor sem a capacidade não aprova (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := lrn_lesson_decide(l1, 'approve', 'Escreve como o cliente fala: frases curtas.', 'encurtei');
  insert into t values ('aprovar com texto editado', true, j->>'status' = 'approved' and (j->>'edited')::boolean);
  j := lrn_lessons_list('lr_a');
  v1 := (j->'active'->>'id')::uuid;
  insert into t values ('aprovar cria a versão 1 com a lição editada', true, (j->'active'->>'version_no')::int = 1
    and j->'active'->'lessons'->0->>'text' = 'Escreve como o cliente fala: frases curtas.');
  begin perform lrn_lesson_decide(l1, 'reject'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lição decidida não se decide outra vez', true, st = '22023');
  j := lrn_lesson_decide(l2, 'reject', null, 'genérico demais');
  insert into t values ('rejeitar não cria versão', true, j->>'status' = 'rejected'
    and (select count(*) from lrn_lesson_versions where workspace_id = 'lr_a') = 1);
  j := lrn_lesson_retire(l1, 'já não se aplica');
  insert into t values ('retirar cria a versão 2 sem a lição', true, (j->>'version_no')::int = 2 and jsonb_array_length(j->'lessons') = 0);
  j := lrn_version_restore(v1);
  insert into t values ('voltar atrás cria a versão 3 igual à 1', true, (j->>'version_no')::int = 3 and jsonb_array_length(j->'lessons') = 1
    and (select count(*) from lrn_lesson_versions where workspace_id = 'lr_a' and active) = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform lrn_version_restore(v1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não volta atrás nas versões de A', true, st = '42501');
  begin perform lrn_lesson_retire(l1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não retira lições de A', true, st = '42501');

  -- ═════ LRN-04: nível da agência ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform lrn_lesson_promote(l1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não promove à agência', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform lrn_lesson_promote(l1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem a capacidade não promove', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_aa, 'role','authenticated')::text, true);
  j := lrn_lesson_promote(l1, 'Frases curtas e faladas rendem mais em todos os clientes.');
  la := (j->>'id')::uuid;
  insert into t values ('promover: proposta da agência só com a regra (sem cliente nem evidência)', true,
    (select level = 'agency' and workspace_id is null and evidence = '{}'::jsonb and status = 'proposed' from lrn_lessons where id = la));
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform lrn_lesson_decide(la, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não aprova lição da agência', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform lrn_lesson_decide(la, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente B não aprova lição da agência', true, st = '42501');
  insert into t values ('cliente B não vê a secção da agência', true, lrn_lessons_list('lr_b')->'agency' = 'null'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform lrn_lesson_decide(la, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro da agência sem capacidade não aprova', true, st = '42501');
  j := lrn_lessons_list('lr_a');
  insert into t values ('staff da agência vê a secção da agência, sem propostas (sem capacidade)', true,
    j->'agency' is not null and j->'agency' <> 'null'::jsonb and jsonb_array_length(j->'agency'->'proposed') = 0 and not (j->'can'->>'agency')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência vê a proposta da agência', true, jsonb_array_length(lrn_lessons_list('lr_a')->'agency'->'proposed') = 1);
  j := lrn_lesson_decide(la, 'approve');
  insert into t values ('dono da agência aprova: versão 1 da agência', true, j->>'status' = 'approved'
    and (select version_no from lrn_lesson_versions where level = 'agency' and organization_id = org and active) = 1);
  insert into t values ('lição da agência sem evidência no JSON', true, lrn_lessons_list('lr_b')->'agency'->'active'->'lessons'->0->>'text' like 'Frases curtas%'
    and (lrn_lessons_list('lr_b')->'agency'->'active')::text not like '%lr_a%');

  -- motor lê as lições em vigor dos dois níveis
  execute 'reset role';
  j := worker_lessons(job, 'lr-worker');
  insert into t values ('worker_lessons: cliente e agência, prevalece o cliente', true, j->>'precedence' = 'client'
    and jsonb_array_length(j->'client'->'lessons') = 1 and jsonb_array_length(j->'agency'->'lessons') = 1);

  -- imutabilidade
  begin update lrn_lesson_versions set lessons = '[]' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se alteram', true, st = '42501');
  begin update lrn_lessons set text = 'mudado à mão' where id = l1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lição decidida não se altera', true, st = '42501');
  begin delete from lrn_edit_signals where content_id = 'lr_a-1'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sinais são só de acrescentar', true, st = '42501');

  -- agenda: amanhã às 07:00 de Lisboa põe na fila os sinais de hoje; a segunda passagem não duplica
  update agent_jobs set status = 'succeeded', finished_at = now() where id = job;
  tz := 'Europe/Lisbon';
  pnow := ((date_trunc('day', now() at time zone tz) + interval '1 day 7 hours') at time zone tz);
  update feature_flags set stage = 'off' where key = 'learn.lessons' and workspace_id = 'lr_b';
  n := lrn_lessons_tick(pnow);
  insert into t values ('agenda enfileira o dia anterior de A', true, n >= 1
    and exists (select 1 from agent_jobs where workspace_id = 'lr_a' and kind = 'lesson_editor' and idempotency_key = 'lesson_editor:' || to_char((pnow at time zone tz)::date - 1, 'YYYY-MM-DD')));
  insert into t values ('agenda não duplica', true, lrn_lessons_tick(pnow) = 0);
  insert into t values ('agenda ignora cliente com a flag desligada', true,
    not exists (select 1 from agent_jobs where workspace_id = 'lr_b' and kind = 'lesson_editor'));

  revoke select on lrn_edit_signals, lrn_lessons, lrn_lesson_versions, content_transition_reasons, agent_jobs, audit_events from authenticated;
  insert into t values ('tabelas novas fechadas à leitura direta', true,
    not has_table_privilege('authenticated', 'public.lrn_edit_signals', 'select') and not has_table_privilege('authenticated', 'public.lrn_lessons', 'select')
    and not has_table_privilege('authenticated', 'public.lrn_lesson_versions', 'select') and not has_table_privilege('anon', 'public.lrn_lessons', 'select'));
  insert into t values ('funções do worker fechadas a anon e authenticated', true,
    not has_function_privilege('authenticated', 'public.worker_lesson_save(uuid, text, integer, jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.worker_lesson_pairs(uuid, text)', 'execute')
    and has_function_privilege('engine_worker', 'public.worker_lesson_save(uuid, text, integer, jsonb)', 'execute'));
  insert into t values ('capacidades e flags registadas', true,
    (select count(*) from capabilities where key in ('learn.lessons.approve','learn.lessons.agency') and status = 'ativo') = 2
    and (select count(*) from feature_flag_defs where key in ('learn.edits','learn.lessons') and default_stage = 'owner') = 2
    and not exists (select 1 from role_capabilities where capability = 'learn.lessons.agency' and scope = 'ws'));
  insert into t values ('auditoria das decisões', true,
    (select count(*) from audit_events where action in ('lrn.lesson_approved','lrn.lesson_rejected','lrn.version_created','lrn.lesson_promoted','lrn.decision_signal')) >= 8);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
