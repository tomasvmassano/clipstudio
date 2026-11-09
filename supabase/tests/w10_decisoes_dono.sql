-- supabase/tests/w10_decisoes_dono.sql : decisões do dono de 2026-11-09 (ADR-0071). W10-22; rollback no fim (raise).
--  1. FR-10-01: a equipa do cliente nunca vê custos (nem como admin, nem com exceção); staff da agência com costs.read vê.
--  2. EDL-07/EDL-11: etiquetar ia-* na Biblioteca exige a declaração de direitos e fica no histórico.
--  3. LRN-04: a equipa do cliente vê as lições da agência em vigor, só leitura; propostas só para a agência.
-- Clientes A e B na agência, cliente X noutra agência, staff da agência só em A, código de equipa de A.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio'); org2 uuid := gen_random_uuid();
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cc uuid := gen_random_uuid();
  u_cb uuid := gen_random_uuid(); u_cv uuid := gen_random_uuid(); u_cx uuid := gen_random_uuid();
  tok text := 'dd-a-team-code-0123456789abcdef'; sha text := repeat('a', 64);
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; img uuid; img_b uuid; la uuid; ctx jsonb;
begin
  insert into organizations (id, slug, name) values (org2, 'dd-outra', 'Outra agência');
  insert into clients (id, name, handle, organization_id, timezone) values
    ('dd_a', 'Decisões A', 'dda', org, 'Asia/Dubai'), ('dd_b', 'Decisões B', 'ddb', org, 'Asia/Dubai'), ('dd_x', 'Decisões X', 'ddx', org2, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'dd-own@test.invalid'),(u_ag,'dd-ag@test.invalid'),(u_ca,'dd-ca@test.invalid'),(u_cc,'dd-cc@test.invalid'),
    (u_cb,'dd-cb@test.invalid'),(u_cv,'dd-cv@test.invalid'),(u_cx,'dd-cx@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('dd_a', u_ag, 'agency_staff', 'manager'), ('dd_a', u_ca, 'client_staff', 'workspace_admin'), ('dd_a', u_cc, 'client_staff', 'contributor'),
    ('dd_a', u_cv, 'client_staff', 'workspace_owner'), ('dd_b', u_cb, 'client_staff', 'workspace_admin'), ('dd_x', u_cx, 'client_staff', 'workspace_admin');
  insert into studio_tokens (token, client_id, label) values (tok, 'dd_a', 'Equipa DD');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, o, w, 'all' from unnest(array['costs.content','media.library','learn.lessons']) k,
    (values (org, 'dd_a'), (org, 'dd_b'), (org2, 'dd_x')) v(o, w);
  -- exceções: costs.read à admin do cliente A (não pode abrir custos) e ao staff da agência em A (abre)
  insert into permission_grants (user_id, workspace_id, capability, effect, created_by) values
    (u_ca, 'dd_a', 'costs.read', 'allow', u_own), (u_ag, 'dd_a', 'costs.read', 'allow', u_own);

  -- biblioteca: uma imagem pronta em A e outra em B
  for r in select * from (values ('dd_a'), ('dd_b')) v(ws) loop
    la := gen_random_uuid();
    insert into media_assets (id, workspace_id, kind, title, tags) values (la, r.ws, 'imagem', 'Ferrari ' || r.ws, array['dubai']);
    insert into media_versions (id, workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256, storage_provider)
    values (la, r.ws, la, 1, 'upload', 'pendente', 'r2', r.ws || '/' || la || '/1/f', 'f.jpg', 100, 'image/jpeg', sha, 'r2');
    update media_versions set state = 'pronta', completed_at = now() where id = la;
    update media_assets set current_version_id = la where id = la;
    if r.ws = 'dd_a' then img := la; else img_b := la; end if;
  end loop;

  -- lições da agência: versão em vigor com 1 regra, 1 proposta; outra agência com a sua regra
  perform public._lrn_new_version('agency', org, null, jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'category', 'hook', 'text', 'Hook em menos de 2 segundos.')),
    jsonb_build_object('action', 'approve'), jsonb_build_object('uid', u_own, 'kind', 'user', 'label', 'segredo-dono@agencia.invalid'));
  insert into lrn_lessons (level, organization_id, workspace_id, category, text, proposed_text, source, evidence)
  values ('agency', org, null, 'tom', 'Proposta da agência por decidir', 'Proposta da agência por decidir', 'promoted', '{}') returning id into la;
  perform public._lrn_new_version('agency', org2, null, jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'category', 'cta', 'text', 'Regra da outra agência.')),
    jsonb_build_object('action', 'approve'), jsonb_build_object('uid', null, 'kind', 'system', 'label', 'fixture'));

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ═════ 1. custos ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('dd_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A com exceção costs.read: costs_ai_usage recusa 42501', true, st = '42501');
  begin perform costs_ai_usage_export('runs', 'dd_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A: exportação recusada 42501', true, st = '42501');
  begin perform content_costs('dd_a', 3); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A: custo por guião recusado 42501', true, st = '42501');
  begin perform content_costs_export('dd_a', 3); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente A: exportação por guião recusada 42501', true, st = '42501');
  insert into t values ('admin do cliente A: agents_overview sem custo do dia', true,
    agents_overview('dd_a')->'spend_today' = 'null'::jsonb and not (agents_overview('dd_a')->'can'->>'costs')::boolean);
  ctx := my_context();
  insert into t values ('admin do cliente A: menu sem costs.* (my_context)', true,
    (select bool_and(not (x->'capabilities') @> '["costs.read"]' and not (x->'capabilities') @> '["costs.export"]') from jsonb_array_elements(ctx->'workspaces') x where x->>'id' = 'dd_a')
    and (select (x->'capabilities') @> '["scripts.read"]' from jsonb_array_elements(ctx->'workspaces') x where x->>'id' = 'dd_a'));
  j := access_explain('dd_a', u_ca, 'costs.read');
  insert into t values ('consola explica a recusa (equipa do cliente)', true, not (j->>'allowed')::boolean and j->>'source' = 'policy' and j->'reasons'->>0 like 'A equipa do cliente nunca vê custos%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cv, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('dd_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dono do cliente A (workspace_owner) também recusado', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform costs_ai_usage('dd_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente B não vê os custos de B', true, st = '42501');
  begin perform costs_ai_usage('dd_a', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente B não vê os custos de A (troca de id)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := costs_ai_usage('dd_a', 7);
  insert into t values ('staff da agência com costs.read em A vê A', true, j->>'scope' = 'workspace' and j->'workspaces'->0->>'id' = 'dd_a');
  insert into t values ('staff da agência: my_context com costs.read em A', true,
    (select (x->'capabilities') @> '["costs.read"]' from jsonb_array_elements(my_context()->'workspaces') x where x->>'id' = 'dd_a'));
  begin perform costs_ai_usage('dd_b', 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem acesso a B não vê B', true, st = '42501');
  begin perform costs_ai_usage(null, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem costs.read_agency não vê a vista da agência', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência vê A', true, (costs_ai_usage('dd_a', 7)->>'scope') = 'workspace');
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform costs_ai_usage('dd_a', 7, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa nunca vê custos', true, st = '42501');
  execute 'reset role';
  insert into t values ('staff da agência: explicação continua pela exceção', true, (public._access_explain('dd_a', u_ag, 'costs.read')->>'allowed')::boolean);
  execute 'set local role authenticated';

  -- ═════ 2. declaração de direitos ao etiquetar ia-* ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform media_asset_save('dd_a', img, jsonb_build_object('tags', jsonb_build_array('dubai', 'ia-imagem'))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ia-imagem sem confirmação: recusa 22023', true, st = '22023');
  begin perform media_asset_save('dd_a', img, jsonb_build_object('tags', jsonb_build_array('ia-imagem'), 'ai_rights_confirmed', false)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ia-imagem com confirmação false: recusa 22023', true, st = '22023');
  j := media_asset_save('dd_a', img, jsonb_build_object('title', 'Ferrari livre', 'notes', 'sem ia'));
  insert into t values ('guardar sem mexer nas etiquetas continua a funcionar', true, j->>'title' = 'Ferrari livre');
  j := media_asset_save('dd_a', img, jsonb_build_object('tags', jsonb_build_array('dubai', 'ia-imagem'), 'ai_rights_confirmed', true));
  insert into t values ('ia-imagem com confirmação: guardado', true, j->'tags' @> '["ia-imagem"]');
  j := media_asset_save('dd_a', img, jsonb_build_object('title', 'Ferrari IA', 'tags', jsonb_build_array('dubai', 'ia-imagem', 'final')));
  insert into t values ('etiqueta ia-* que já lá estava não pede nova confirmação', true, j->>'title' = 'Ferrari IA');
  begin perform media_link_add('dd_a', null, jsonb_build_object('url', 'https://example.com/a.jpg', 'tags', jsonb_build_array('ia-musica'))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link com ia-musica (sem confirmação possível): recusa 22023', true, st = '22023');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform media_asset_save('dd_a', img, jsonb_build_object('tags', jsonb_build_array('ia-atencao'), 'ai_rights_confirmed', true)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não etiqueta o ativo de A', true, st = '42501');
  begin perform media_asset_save('dd_b', img, jsonb_build_object('tags', jsonb_build_array('ia-atencao'), 'ai_rights_confirmed', true)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não chega ao ativo de A pelo seu cliente (P0002)', true, st = 'P0002');
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform media_asset_save('dd_a', img, jsonb_build_object('tags', jsonb_build_array('ia-musica')), null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa sem confirmação não acrescenta ia-*', true, st in ('22023', '42501'));
  execute 'reset role';
  insert into t values ('declaração no histórico: quem, etiqueta, ativo e versão', true, (select count(*) = 1 and bool_and(actor_user_id = u_ca and workspace_id = 'dd_a'
      and after->'tags' = '["ia-imagem"]' and (after->>'asset_id')::uuid = img and (after->>'version_id')::uuid = img and (after->>'version_no')::int = 1
      and (after->>'confirmed')::boolean and at is not null)
    from audit_events where action = 'media.ai_rights_declared' and entity_id = img::text));
  insert into t values ('nada declarado em B nem por recusas', true, not exists (select 1 from audit_events where action = 'media.ai_rights_declared' and (workspace_id <> 'dd_a' or entity_id <> img::text) and workspace_id in ('dd_a','dd_b')));
  perform set_config('request.jwt.claims', '', true);
  update media_assets set tags = array['ia-musica'] where id = img_b;   -- sistema (sem sessão): não é travado, fica registado
  insert into t values ('sistema que acrescente ia-* fica registado sem confirmação', true,
    exists (select 1 from audit_events where action = 'media.ai_rights_declared' and entity_id = img_b::text and not (after->>'confirmed')::boolean and actor_kind = 'system'));
  insert into t values ('funções internas fechadas', true, not has_function_privilege('authenticated', 'public.media_assets_ai_rights()', 'execute')
    and not has_function_privilege('anon', 'public._media_ai_tags()', 'execute'));
  execute 'set local role authenticated';

  -- ═════ 3. lições da agência para a equipa do cliente ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := lrn_lessons_list('dd_a');
  insert into t values ('equipa do cliente: secção da agência só leitura com a regra em vigor', true,
    (j->'agency'->>'readonly')::boolean and jsonb_array_length(j->'agency'->'active'->'lessons') = 1
    and j->'agency'->'active'->'lessons'->0->>'text' = 'Hook em menos de 2 segundos.' and j->'agency'->'active'->'lessons'->0->>'category' = 'hook');
  insert into t values ('equipa do cliente: só categoria e texto (sem quem mudou, mudança nem evidência)', true,
    not (j->'agency'->'active' ? 'change') and not (j->'agency'->'active' ? 'created_label') and position('segredo-dono' in j::text) = 0
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(x) k) = array['category','id','text']) from jsonb_array_elements(j->'agency'->'active'->'lessons') x));
  insert into t values ('equipa do cliente: sem propostas da agência e sem poder da agência', true,
    j->'agency'->'proposed' = '[]'::jsonb and not (j->'can'->>'agency')::boolean and position('Proposta da agência' in j::text) = 0);
  begin perform lrn_lesson_decide(la, 'approve'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não aprova a lição da agência', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  insert into t values ('cliente B vê a mesma regra da agência, só leitura', true,
    (lrn_lessons_list('dd_b')->'agency'->>'readonly')::boolean and lrn_lessons_list('dd_b')->'agency'->'active'->'lessons'->0->>'text' = 'Hook em menos de 2 segundos.');
  begin perform lrn_lessons_list('dd_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê as lições de A', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cx, 'role','authenticated')::text, true);
  j := lrn_lessons_list('dd_x');
  insert into t values ('cliente de outra agência só vê as regras da sua agência', true,
    j->'agency'->'active'->'lessons'->0->>'text' = 'Regra da outra agência.' and position('Hook em menos' in j::text) = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := lrn_lessons_list('dd_a');
  insert into t values ('staff da agência: não é só leitura e vê quem mudou', true, not (j->'agency'->>'readonly')::boolean and j->'agency'->'active' ? 'change');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência vê a proposta da agência', true, jsonb_array_length(lrn_lessons_list('dd_a')->'agency'->'proposed') = 1);
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := lrn_lessons_list('dd_a', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa: nada da agência', true, st <> 'none' or j->'agency' = 'null'::jsonb);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
