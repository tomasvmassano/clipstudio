-- supabase/tests/w7_busca.sql : pesquisa global com controlo de acesso (FR-16-01, FR-16-02, FR-16-05, QA-12), ações rápidas
-- (FR-01-05) e operações em lote nos guiões (FR-17-07). Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  u_vw uuid := gen_random_uuid(); u_co uuid := gen_random_uuid(); u_zb uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date; j jsonb; st text; det text; ok int := 0; bad int := 0; res text := ''; r record;
  gb text; gc text; g1 text; g2 text; g3 text; garch text; tb uuid; ta uuid; pa uuid; pb uuid; k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid();
  cnt int; ver text;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_bs_b', 'Busca B', 'bsb', org), ('ws_bs_c', 'Busca C', 'bsc', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'bs-own@test.invalid'),(u_ag,'bs-ag@test.invalid'),(u_ca,'bs-ca@test.invalid'),(u_cb,'bs-cb@test.invalid'),
    (u_vw,'bs-vw@test.invalid'),(u_co,'bs-co@test.invalid'),(u_zb,'zeferino@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'), ('ws_bs_b', u_ag, 'agency_staff', 'contributor'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_vw, 'client_staff', 'viewer'), ('numeiro', u_co, 'client_staff', 'contributor'),
    ('ws_bs_b', u_cb, 'client_staff', 'workspace_admin'), ('ws_bs_b', u_zb, 'client_staff', 'contributor');
  insert into profiles (user_id, display_name) values (u_zb, 'Zeferino Zebraquantica'), (u_co, 'Rita Relação');
  update guioes set date = d where client_id = 'numeiro';
  -- termo exclusivo de B: "zebraquantica" (em todas as entidades); exclusivo de C: "ornitorrinco"
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, editorial_status, tags)
  values ('ws_bs_b-g1', 'ws_bs_b', d, 1, 'A Zebraquântica explica impostos', '[{"text":"Hook B","mecanismo":""}]', 'Corpo B.', 'in_review', '{zebratag}'),
         ('ws_bs_c-g1', 'ws_bs_c', d, 1, 'Ornitorrinco fiscal', '[]', 'Corpo C.', 'in_review', '{}');
  gb := 'ws_bs_b-g1'; gc := 'ws_bs_c-g1';
  insert into ideas (client_id, kind, titulo, status, tags) values ('ws_bs_b', 'source', 'Estudo zebraquantica', 'nova', '{zebratag}');
  insert into reference_items (workspace_id, url, url_normalized, titulo, created_kind) values ('ws_bs_b', 'https://x.test/zq', 'x.test/zq', 'Referência zebraquantica', 'engine');
  insert into tasks (workspace_id, title, created_kind) values ('ws_bs_b', 'Montar zebraquantica', 'system') returning id into tb;
  insert into projects (workspace_id, name) values ('ws_bs_b', 'Campanha Zebraquantica') returning id into pb;
  perform public._edit_seed('ws_bs_b', 'system', 'test');
  ver := (select key from edit_styles where workspace_id = 'ws_bs_b' order by key limit 1);
  insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, notes, actor_kind, actor_label)
  select workspace_id, key, version + 1, 'Estilo Zebraquantica', spec, transformation, platforms, notes, 'system', 'test'
    from edit_style_versions v where v.workspace_id = 'ws_bs_b' and v.key = ver and v.version = (select current_version from edit_styles where workspace_id = 'ws_bs_b' and key = ver);
  update edit_styles set current_version = current_version + 1 where workspace_id = 'ws_bs_b' and key = ver;
  -- dados de A
  g1 := (select id from guioes where client_id = 'numeiro' and editorial_status = 'in_review' order by n limit 1);
  g2 := (select id from guioes where client_id = 'numeiro' and editorial_status = 'in_review' order by n offset 1 limit 1);
  g3 := (select id from guioes where client_id = 'numeiro' and editorial_status = 'in_review' order by n offset 2 limit 1);
  garch := (select id from guioes where client_id = 'numeiro' and editorial_status = 'in_review' order by n offset 3 limit 1);
  update guioes set tema = 'Relação ímpar com o dinheiro', tags = '{dinheiro}' where id = g1;
  update guioes set editorial_status = 'archived', archived_from = 'in_review' where id = garch;
  insert into tasks (workspace_id, title, assignee_id, created_kind) values ('numeiro', 'Rever legendas do lote', u_ca, 'system') returning id into ta;
  insert into projects (workspace_id, name) values ('numeiro', 'Black Friday') returning id into pa;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── flag desligada (fase owner por defeito): o dono pesquisa, a equipa do cliente não ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform search_global('dinheiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: pesquisa recusada com 55000', true, st = '55000');
  insert into t values ('flag desligada: paleta não aparece (enabled vazio)', true, jsonb_array_length(search_scope('numeiro')->'enabled') = 0
    and search_scope('numeiro')->'actions' = 'null'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := search_global('ornitorrinco');
  insert into t values ('dono da agência: flag em fase owner, encontra o termo de C', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = gc));

  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['busca.global','guioes.bulk']) k, unnest(array['numeiro','ws_bs_b','ws_bs_c']) w;
  execute 'set local role authenticated';

  -- ── QA-12: cliente A com termo exclusivo de B ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := search_global('zebraquantica');
  insert into t values ('QA-12: A pesquisa termo exclusivo de B e não vê nada', true, jsonb_array_length(j->'groups') = 0);
  j := search_global('#zeb');
  insert into t values ('QA-12: etiqueta exclusiva de B também não aparece a A', true, jsonb_array_length(j->'groups') = 0);
  j := search_global(gb);
  insert into t values ('ID de um guião de B não se encontra a partir de A', true, jsonb_array_length(j->'groups') = 0);
  j := search_global(tb::text);
  insert into t values ('ID de uma tarefa de B não se encontra a partir de A', true, jsonb_array_length(j->'groups') = 0);
  begin perform search_global('zebraquantica', 'ws_bs_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A a forçar p_ws de B: 42501', true, st = '42501');
  insert into t values ('scope de A só lista o cliente A', true, (select array_agg(x->>'id') from jsonb_array_elements(search_scope(null)->'enabled') x) = array['numeiro']);
  insert into t values ('ações rápidas pedidas para B não aparecem a A', true, search_scope('ws_bs_b')->'actions' = 'null'::jsonb);
  j := search_scope('numeiro')->'actions';
  insert into t values ('admin de A: as 4 ações rápidas', true, (j->>'source')::boolean and (j->>'script')::boolean and (j->>'project')::boolean and (j->>'task')::boolean);

  -- pesquisa de A funciona: acentos, várias palavras, ID, etiqueta, campanhas, tarefas, pessoas
  j := search_global('relacao impar');
  insert into t values ('sem acentos e com 2 palavras encontra o guião', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'script' and i->>'id' = g1));
  j := search_global('relacao inexistente');
  insert into t values ('todas as palavras têm de aparecer', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = g1));
  j := search_global(g2);
  insert into t values ('pesquisa pelo ID do guião', true, (j->'groups'->0->'items'->0->>'id') = g2);
  j := search_global(ta::text);
  insert into t values ('pesquisa pelo ID da tarefa', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'task' and i->>'id' = ta::text));
  j := search_global('#dinh');
  insert into t values ('etiqueta por prefixo: sugestão e guião', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'tag' and i->>'id' = 'dinheiro')
    and exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'script' and i->>'id' = g1));
  j := search_global('black');
  insert into t values ('campanhas', true, exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'project' and i->>'id' = pa::text));
  j := search_global('rita');
  insert into t values ('pessoas da equipa pelo nome do perfil', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'person' and i->>'id' = u_co::text));
  j := search_global('de teste', null, 3);
  insert into t values ('limite por grupo e indicação de que há mais', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x where x->>'kind' = 'source' and jsonb_array_length(x->'items') = 3 and (x->>'more')::boolean));
  j := search_global('50%_x');
  insert into t values ('% e _ são texto, não curingas', true, jsonb_array_length(j->'groups') = 0);
  j := search_global('');
  insert into t values ('sem texto: sugestões só de A (recentes e as minhas tarefas)', true, j->>'mode' = 'suggestions'
    and exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where x->>'kind' = 'my_tasks' and i->>'id' = ta::text)
    and not exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'ws' <> 'numeiro'));

  -- negação explícita: A perde as fontes e a pesquisa deixa de as mostrar
  execute 'reset role';
  insert into permission_grants (user_id, workspace_id, capability, effect) values (u_ca, 'numeiro', 'sources.read', 'deny');
  execute 'set local role authenticated';
  j := search_global('de teste');
  insert into t values ('negação explícita de sources.read tira o grupo Fontes', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') x where x->>'kind' = 'source'));

  -- leitor: sem team.read não vê pessoas; sem ações rápidas
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  j := search_global('rita');
  insert into t values ('leitor (sem team.read) não vê pessoas', true, not exists (select 1 from jsonb_array_elements(j->'groups') x where x->>'kind' = 'person'));
  j := search_scope('numeiro')->'actions';
  insert into t values ('leitor: nenhuma ação rápida', true, not ((j->>'source')::boolean or (j->>'script')::boolean or (j->>'project')::boolean or (j->>'task')::boolean));
  insert into t values ('leitor não lê referências: grupo vazio', true,
    not exists (select 1 from jsonb_array_elements(search_global('referência')->'groups') x where x->>'kind' = 'reference'));

  -- ── cliente B encontra as suas coisas em todos os grupos, e nada de A ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  j := search_global('zebraquantica');
  insert into t values ('B encontra guião, fonte, referência, tarefa, campanha, pessoa e estilo', true,
    (select count(distinct x->>'kind') from jsonb_array_elements(j->'groups') x where x->>'kind' in ('script','source','reference','task','project','person','style')) = 7);
  insert into t values ('acento no tema ("Zebraquântica") não impede a correspondência', true,
    exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = gb));
  j := search_global('relacao impar');
  insert into t values ('B com termo de A: nada', true, jsonb_array_length(j->'groups') = 0);

  -- ── staff da agência: só clientes atribuídos ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := search_global('zebraquantica');
  insert into t values ('staff com A e B encontra o de B', true, exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = gb));
  j := search_global('ornitorrinco');
  insert into t values ('staff não atribuído a C não vê C', true, jsonb_array_length(j->'groups') = 0);
  j := search_global('zebraquantica', 'numeiro');
  insert into t values ('âmbito "este cliente" (A) não traz B', true, jsonb_array_length(j->'groups') = 0);
  execute 'reset role';
  update workspace_access set status = 'removed' where user_id = u_ag and workspace_id = 'ws_bs_b';
  execute 'set local role authenticated';
  j := search_global('zebraquantica');
  insert into t values ('acesso removido a B: pesquisa seguinte já não traz B', true, jsonb_array_length(j->'groups') = 0);

  -- ── código de equipa: só o cliente do código, sem pessoas ──
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := search_global('rita', null, 5, tok);
  insert into t values ('código: não vê pessoas', true, not exists (select 1 from jsonb_array_elements(j->'groups') x where x->>'kind' = 'person'));
  j := search_global('zebraquantica', null, 5, tok);
  insert into t values ('código de A: nada de B', true, jsonb_array_length(j->'groups') = 0);
  j := search_global('relacao', null, 5, tok);
  insert into t values ('código de A: encontra guião de A', true, exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = g1));
  begin perform search_global('relacao', null, 5, 'codigo-falso'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem sessão nem código válido: 28000', true, st = '28000');
  execute 'set local role authenticated';

  -- ── operações em lote ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := content_bulk('numeiro', array[g1, g2], 'owner', jsonb_build_object('owner_id', u_co), null, true);
  insert into t values ('pré-visualização: 2 itens mudariam', true, (j->'summary'->>'changed')::int = 2 and (j->>'preview')::boolean
    and (j->'results'->0->'after'->>'owner_id')::uuid = u_co);
  execute 'reset role';
  insert into t values ('pré-visualização não grava nada (nem auditoria)', true,
    (select count(*) from guioes where id in (g1, g2) and owner_id = u_co) = 0
    and not exists (select 1 from audit_events where action in ('script.bulk', 'script.meta_changed') and entity_id in (g1, g2)));
  execute 'set local role authenticated';
  j := content_bulk('numeiro', array[g1, g2, gb, 'nao-existe'], 'owner', jsonb_build_object('owner_id', u_co), k1);
  insert into t values ('lote: 2 ok, guião de B e inexistente falham com o mesmo erro (sem revelar B)', true,
    (j->'summary'->>'ok')::int = 2 and (j->'summary'->>'failed')::int = 2
    and (select count(*) from jsonb_array_elements(j->'results') x where x->>'code' = 'P0002') = 2
    and (select owner_id from guioes where id = gb) is null);
  execute 'reset role';
  insert into t values ('lote grava responsável e audita cada guião + o lote', true,
    (select count(*) from guioes where id in (g1, g2) and owner_id = u_co) = 2
    and (select count(*) from audit_events where action = 'script.bulk' and entity_id = k1::text) = 1
    and (select count(*) from audit_events where action = 'script.meta_changed' and entity_id in (g1, g2)) = 2);
  select count(*) into cnt from notifications where user_id = u_co and kind = 'script_assigned';
  execute 'set local role authenticated';
  j := content_bulk('numeiro', array[g1, g2, gb, 'nao-existe'], 'owner', jsonb_build_object('owner_id', u_co), k1);
  execute 'reset role';
  insert into t values ('repetir a mesma chave devolve o resultado guardado sem reaplicar', true, (j->>'replayed')::boolean
    and (select count(*) from audit_events where action = 'script.bulk' and entity_id = k1::text) = 1
    and (select count(*) from notifications where user_id = u_co and kind = 'script_assigned') = cnt);
  execute 'set local role authenticated';
  begin perform content_bulk('numeiro', array[g3], 'owner', jsonb_build_object('owner_id', u_co), k1); st := 'none'; exception when others then st := sqlstate; det := sqlerrm; end;
  insert into t values ('mesma chave para outro pedido: 22023', true, st = '22023' and det = 'chave_reutilizada');
  j := content_bulk('numeiro', array[g1], 'owner', jsonb_build_object('owner_id', u_cb), gen_random_uuid());
  insert into t values ('responsável de B recusado item a item', true, (j->'summary'->>'failed')::int = 1 and j->'results'->0->>'code' = '22023');

  j := content_bulk('numeiro', array[g1, g2], 'project', jsonb_build_object('project_id', pa), gen_random_uuid());
  insert into t values ('campanha em lote', true, (select count(*) from guioes where id in (g1, g2) and project_id = pa) = 2);
  j := content_bulk('numeiro', array[g1], 'project', jsonb_build_object('project_id', pb), gen_random_uuid());
  insert into t values ('campanha de B recusada', true, (j->'summary'->>'failed')::int = 1 and (select project_id from guioes where id = g1) = pa);
  j := content_bulk('numeiro', array[g1, g2], 'tags', '{"mode":"add","tags":["Lote"]}', gen_random_uuid());
  insert into t values ('etiquetas: acrescentar mantém as que havia', true, (select tags from guioes where id = g1) = array['dinheiro', 'lote']
    and (select tags from guioes where id = g2) = array['lote']);
  j := content_bulk('numeiro', array[g1, g2], 'tags', '{"mode":"remove","tags":["lote"]}', gen_random_uuid());
  insert into t values ('etiquetas: retirar', true, (select tags from guioes where id = g1) = array['dinheiro'] and (select tags from guioes where id = g2) = '{}');

  j := content_bulk('numeiro', array[g1, g2, garch], 'reschedule', jsonb_build_object('date', d - 3), null, true);
  insert into t values ('reagendar para o passado: falha em todos na pré-visualização', true, (j->'summary'->>'failed')::int = 3);
  j := content_bulk('numeiro', array[g1, garch], 'reschedule', jsonb_build_object('date', d + 2), gen_random_uuid());
  insert into t values ('reagendar: ok no ativo, arquivado falha', true, (select date from guioes where id = g1) = d + 2
    and (select date from guioes where id = garch) = d and (j->'summary'->>'failed')::int = 1);

  j := content_bulk('numeiro', array[g2, g3, garch], 'approve', '{}', null, true);
  insert into t values ('aprovar (pré-visualização): 2 aprovariam, arquivado falha', true, (j->'summary'->>'changed')::int = 2 and (j->'summary'->>'failed')::int = 1
    and (select count(*) from guioes where id in (g2, g3) and editorial_status = 'approved') = 0);
  j := content_bulk('numeiro', array[g2, g3, garch], 'approve', '{}', k2);
  insert into t values ('aprovar em lote presa à versão (approved_version_id)', true,
    (select count(*) from guioes where id in (g2, g3) and editorial_status = 'approved' and approved_version_id is not null) = 2);
  j := content_bulk('numeiro', array[g2], 'approve', '{}', gen_random_uuid());
  insert into t values ('aprovar o já aprovado não muda nada', true, (j->'summary'->>'ok')::int = 1 and (j->'summary'->>'changed')::int = 0);
  begin perform content_bulk('numeiro', array[g1], 'apagar', '{}', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ação desconhecida: 22023', true, st = '22023');
  begin perform content_bulk('numeiro', array[g1], 'owner', jsonb_build_object('owner_id', u_co), null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lote confirmado sem chave: 22023', true, st = '22023');
  begin perform content_bulk('numeiro', (select array_agg('x' || g) from generate_series(1, 201) g), 'owner', jsonb_build_object('owner_id', u_co), gen_random_uuid());
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('mais de 200 guiões: 22023', true, st = '22023');

  j := content_bulk_export('numeiro', array[g1, g2, gb]);
  insert into t values ('exportar: só os de A, o de B conta como em falta', true, jsonb_array_length(j->'rows') = 2 and (j->>'missing')::int = 1
    and exists (select 1 from jsonb_array_elements(j->'rows') x where x->>'campanha' = 'Black Friday'));
  execute 'reset role';
  insert into t values ('exportação auditada', true, exists (select 1 from audit_events where action = 'script.exported' and workspace_id = 'numeiro' and (after->>'count')::int = 2));
  execute 'set local role authenticated';

  -- quem não pode
  perform set_config('request.jwt.claims', json_build_object('sub', u_co, 'role','authenticated')::text, true);
  begin perform content_bulk('numeiro', array[g1], 'approve', '{}', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não aprova em lote (42501)', true, st = '42501');
  begin perform content_bulk('numeiro', array[g1], 'reschedule', jsonb_build_object('date', d + 1), gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador sem calendar.schedule não reagenda (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform content_bulk_export('numeiro', array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor sem scripts.export não exporta (42501)', true, st = '42501');
  begin perform content_bulk('numeiro', array[g1], 'tags', '{"mode":"add","tags":["x"]}', gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não muda etiquetas em lote (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform content_bulk('numeiro', array[g1], 'owner', jsonb_build_object('owner_id', u_cb), gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B sobre guiões de A: 42501', true, st = '42501');
  begin perform content_bulk_export('numeiro', array[g1]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não exporta A: 42501', true, st = '42501');
  j := content_bulk('ws_bs_b', array[g1, gb], 'tags', '{"mode":"add","tags":["b"]}', gen_random_uuid());
  execute 'reset role';
  insert into t values ('B a passar um guião de A no seu lote: falha sem mexer em A', true, (j->'summary'->>'failed')::int = 1
    and not (select 'b' = any (tags) from guioes where id = g1));
  execute 'set local role authenticated';

  -- flag de lote desligada para A
  execute 'reset role';
  delete from feature_flags where key = 'guioes.bulk' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform content_bulk('numeiro', array[g1], 'owner', jsonb_build_object('owner_id', u_co), gen_random_uuid()); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag de lote desligada: 55000', true, st = '55000');

  -- código de equipa: exporta (tem scripts.export), não reagenda
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('guioes.bulk', org, 'numeiro', 'all');
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := content_bulk_export('numeiro', array[g1], tok);
  insert into t values ('código de equipa exporta os do seu cliente', true, jsonb_array_length(j->'rows') = 1);
  begin perform content_bulk('numeiro', array[g1], 'reschedule', jsonb_build_object('date', d + 1), gen_random_uuid(), false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não reagenda (42501)', true, st = '42501');
  begin perform content_bulk('ws_bs_b', array[gb], 'tags', '{"mode":"add","tags":["x"]}', gen_random_uuid(), false, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A sobre B: 42501', true, st = '42501');

  execute 'reset role';
  insert into t values ('tabela de lotes fechada à API', true,
    not has_table_privilege('authenticated', 'public.content_bulk_ops', 'select') and not has_table_privilege('anon', 'public.content_bulk_ops', 'select'));
  insert into t values ('flags registadas', true, (select count(*) from feature_flag_defs where key in ('busca.global','guioes.bulk')) = 2);
  insert into t values ('funções internas sem execute para authenticated', true, not has_function_privilege('authenticated', 'public._search_ws(text, text)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
