-- supabase/tests/w10_diff_versoes.sql : comparar versões e restaurar (FR-02-06, FR-05-06, FR-05-07; AGENTS §2.6).
-- Rollback no fim. Negativos exigem o SQLSTATE certo.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g7 text := 'numeiro-2026-10-28-07'; g8 text := 'numeiro-2026-10-28-08'; gb text := 'ws_df_b-01';
  g guioes; j jsonb; st text; v_rec uuid; v_app uuid; v_new uuid; v_other uuid; lk int; corpo0 text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_df_b', 'Cliente B (teste)', 'clientedfb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_mgr,'d-mgr@test.invalid',now(),'authenticated','authenticated'),(u_con,'d-con@test.invalid',now(),'authenticated','authenticated'),
   (u_b,'d-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_con,'client_staff','viewer'),('ws_df_b',u_b,'client_staff','workspace_owner');
  insert into guioes (id, client_id, date, n, corpo, hooks, status, validado)
  values (gb, 'ws_df_b', (now() at time zone 'Asia/Dubai')::date, 1, 'guião do cliente B', '[{"text":"hook B","mecanismo":""}]', 'aprovado', false);
  corpo0 := (select corpo from guioes where id = g7);

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  -- gravado (fotografa v1), aprovado (mesma versão), editado depois (reabre), submetido (fotografa v2)
  perform content_production(g7, 'recorded');
  g := content_transition(g7, 'approved', null, null);
  v_app := g.approved_version_id;
  g := content_save(g7, '{"corpo":"Corpo reescrito depois de aprovado.","tema":"Tema novo"}'::jsonb, g.lock_version);
  g := content_transition(g7, 'in_review', 'texto mais curto', null);
  v_new := g.current_version_id;
  execute 'reset role'; v_rec := public._content_recorded_version(g7); execute 'set local role authenticated';
  v_other := (select current_version_id from guioes where id = g8);
  if v_other is null then
    g := content_transition(g8, 'approved', null, null); v_other := g.current_version_id;
  end if;

  j := content_history(g7);
  insert into t values ('histórico traz formato e tema de cada versão', true,
    (select bool_and(x ? 'formato' and x ? 'tema') from jsonb_array_elements(j->'versions') x)
    and (select x->>'tema' from jsonb_array_elements(j->'versions') x where (x->>'id')::uuid = v_new) = 'Tema novo');
  insert into t values ('chaves antigas mantêm-se', true,
    (select bool_and(x ?& array['id','version_no','hooks','corpo','cta','created_at','created_kind','author','is_current','is_approved'])
       from jsonb_array_elements(j->'versions') x) and jsonb_typeof(j->'transitions') = 'array');
  insert into t values ('versão gravada marcada (regra de W9-02)', true,
    (j->>'recorded_version_id')::uuid = v_rec
    and (select count(*) from jsonb_array_elements(j->'versions') x where (x->>'is_recorded')::boolean) = 1
    and (select (x->>'is_recorded')::boolean from jsonb_array_elements(j->'versions') x where (x->>'id')::uuid = v_rec));
  insert into t values ('versão aprovada e em vigor marcadas', true,
    (j->>'approved_version_id')::uuid = v_app and (j->>'current_version_id')::uuid = v_new
    and (select (x->>'is_approved')::boolean from jsonb_array_elements(j->'versions') x where (x->>'id')::uuid = v_app));
  insert into t values ('motivo da submissão fica na transição da versão', true,
    exists (select 1 from jsonb_array_elements(j->'transitions') x where x->>'reason' = 'texto mais curto'
            and (x->>'version_no')::int = (select version_no from content_versions where id = v_new)));

  -- restauro com lock antigo: conflito, nada muda
  lk := (select lock_version from guioes where id = g7);
  begin perform content_restore_version(g7, v_app, lk - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('restaurar com versão antiga da cópia: conflito (PT409)', true, st = 'PT409');
  insert into t values ('conflito não muda o texto', true, (select corpo from guioes where id = g7) = 'Corpo reescrito depois de aprovado.');

  -- restauro certo: copia o texto, a aprovação fica onde estava
  g := content_restore_version(g7, v_app, lk);
  insert into t values ('restaurar copia o texto da versão', true, g.corpo = corpo0 and g.tema = 'Tema de teste 7');
  insert into t values ('restaurar não mexe na versão aprovada', true,
    g.approved_version_id = v_app and (select corpo from content_versions where id = v_new) = 'Corpo reescrito depois de aprovado.');
  execute 'reset role';
  insert into t values ('restauro auditado com a versão de origem', true,
    exists (select 1 from audit_events where action = 'script.version_restored' and entity_id = g7 and actor_user_id = u_mgr
            and (after->>'version_no')::int = (select version_no from content_versions where id = v_app)));
  execute 'set local role authenticated';
  j := content_history(g7);
  insert into t values ('histórico mostra o restauro', true,
    (j->'restores'->0->>'version_no')::int = (select version_no from content_versions where id = v_app) and j->'restores'->0->>'actor' = 'd-mgr@test.invalid');

  -- restaurar sobre um guião aprovado abre revisão nova; a versão aprovada não muda
  g := content_transition(g7, 'approved', null, null);
  v_app := g.approved_version_id;
  g := content_restore_version(g7, v_new, g.lock_version);
  insert into t values ('restaurar sobre aprovado: volta a rascunho', true, g.editorial_status = 'draft' and not g.validado);
  insert into t values ('restaurar sobre aprovado: aprovação presa à versão antiga', true,
    g.approved_version_id = v_app and (select corpo from content_versions where id = v_app) = corpo0);
  execute 'reset role';
  insert into t values ('restauro sobre aprovado auditado com o estado antes', true,
    exists (select 1 from audit_events where action = 'script.version_restored' and entity_id = g7 and before->>'editorial_status' = 'approved'
            and after->>'editorial_status' = 'draft'));
  execute 'set local role authenticated';

  -- negativos
  begin perform content_restore_version(g7, v_other, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão de outro guião: não encontrada (P0002)', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  insert into t values ('viewer lê o histórico', true, jsonb_array_length(content_history(g7)->'versions') >= 2);
  begin perform content_restore_version(g7, v_app, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('viewer não restaura (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_history(g7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lê o histórico de A (42501)', true, st = '42501');
  begin perform content_restore_version(g7, v_app, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não restaura em A (42501)', true, st = '42501');
  begin perform content_restore_version(gb, v_app, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não restaura versão de A no seu guião (P0002)', true, st = 'P0002');
  insert into t values ('B lê o seu histórico sem nada de A', true,
    not exists (select 1 from jsonb_array_elements(content_history(gb)->'versions') x where x->>'corpo' = corpo0)
    and jsonb_array_length(content_history(gb)->'restores') = 0);

  -- código de equipa (scripts.read e scripts.edit no seu cliente)
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  insert into t values ('código de equipa lê o histórico do seu cliente', true, (content_history(g7, tok)->>'recorded_version_id')::uuid = v_rec);
  begin perform content_history(gb, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não lê B (42501)', true, st = '42501');
  begin perform content_history(g7, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código: recusado', true, st in ('42501', '28000'));
  execute 'reset role';
  insert into t values ('nada de A ficou no audit de B', true,
    not exists (select 1 from audit_events where workspace_id = 'ws_df_b' and action = 'script.version_restored'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
