-- supabase/tests/w9_aprovar_gravados.sql : aprovar em lote guiões já gravados (FR-02-05, FR-17-07; AGENTS §2.6; ADR-0051).
-- Rollback no fim. Negativos exigem o SQLSTATE certo.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_mgr uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g2 text := 'numeiro-2026-10-28-02'; g3 text := 'numeiro-2026-10-28-03'; g4 text := 'numeiro-2026-10-28-04';
  g5 text := 'numeiro-2026-10-28-05'; ge text := 'numeiro-2026-10-28-31';
  g guioes; j jsonb; st text; it jsonb; rv uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ap_b', 'Cliente B (teste)', 'clienteapb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_mgr,'a-mgr@test.invalid',now(),'authenticated','authenticated'),(u_con,'a-con@test.invalid',now(),'authenticated','authenticated'),
   (u_b,'a-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_mgr,'client_staff','manager'),('numeiro',u_con,'client_staff','viewer'),('ws_ap_b',u_b,'client_staff','workspace_owner');
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('guioes.bulk', org, 'numeiro', 'all');
  -- gravado pelo motor/script antigo sem registo da versão gravada
  insert into guioes (id, client_id, date, n, corpo, hooks, status, validado, gravado)
  values (ge, 'numeiro', (now() at time zone 'Asia/Dubai')::date, 31, 'gravado à moda antiga', '[]', 'aprovado', false, true);

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  perform content_production(g2, 'recorded'); perform content_production(g3, 'recorded'); perform content_production(g4, 'recorded');
  g := content_save(g4, '{"corpo":"mudei depois de gravar"}'::jsonb);   -- texto já não é o gravado
  execute 'reset role'; rv := public._content_recorded_version(g2); execute 'set local role authenticated';

  j := content_pending_approval('numeiro');
  insert into t values ('lista traz os gravados por aprovar, de todos os dias', true,
    (select count(*) from jsonb_array_elements(j->'items') x where x->>'id' in (g2, g3, g4, ge)) = 4);
  insert into t values ('lista não traz os por gravar nem os aprovados', true,
    not exists (select 1 from jsonb_array_elements(j->'items') x where x->>'id' in (g5, 'numeiro-2026-10-28-01')));
  insert into t values ('lista marca o que mudou depois de gravado', true,
    (select bool_and(case x->>'id' when g4 then not (x->>'same_as_recorded')::boolean when ge then not (x->>'same_as_recorded')::boolean
                                   else (x->>'same_as_recorded')::boolean end)
       from jsonb_array_elements(j->'items') x where x->>'id' in (g2, g3, g4, ge)));
  insert into t values ('lista traz estado legado e flag do lote', true,
    (select x->>'legacy_status' from jsonb_array_elements(j->'items') x where x->>'id' = ge) = 'aprovado' and (j->'can'->>'bulk')::boolean);

  -- pré-visualização: nada fica gravado
  j := content_bulk('numeiro', array[g2, g3, g4, g5, ge], 'approve', '{"recorded_only":true}'::jsonb, null, true);
  insert into t values ('pré-visualização: 2 aprovam, 3 recusados', true,
    (j->'summary'->>'changed')::int = 2 and (j->'summary'->>'failed')::int = 3);
  insert into t values ('pré-visualização não grava', true, (select editorial_status from guioes where id = g2) = 'in_review');
  insert into t values ('texto mudado: recusado com a causa', true,
    (select x->>'error' from jsonb_array_elements(j->'results') x where x->>'id' = g4) = 'texto_mudou');
  insert into t values ('por gravar: recusado', true,
    (select x->>'error' from jsonb_array_elements(j->'results') x where x->>'id' = g5) = 'nao_gravado');
  insert into t values ('sem registo da versão gravada: recusado', true,
    (select x->>'error' from jsonb_array_elements(j->'results') x where x->>'id' = ge) = 'versao_gravada_desconhecida');

  -- confirmar
  j := content_bulk('numeiro', array[g2, g3, g4, g5, ge], 'approve', '{"recorded_only":true}'::jsonb, '00000000-0000-4000-8000-00000000a901', false);
  g := (select x from guioes x where x.id = g2);
  insert into t values ('aprovados no fluxo novo e sincronizados', true,
    g.editorial_status = 'approved' and g.validado and (select editorial_status from guioes where id = g3) = 'approved');
  insert into t values ('aprovação presa a uma versão com o texto gravado', true,
    (select corpo from content_versions where id = g.approved_version_id) = (select corpo from content_versions where id = rv));
  insert into t values ('recusados ficam como estavam', true,
    (select count(*) from guioes where id in (g4, g5, ge) and editorial_status = 'in_review') = 3);
  j := content_bulk('numeiro', array[g2, g3, g4, g5, ge], 'approve', '{"recorded_only":true}'::jsonb, '00000000-0000-4000-8000-00000000a901', false);
  insert into t values ('repetir a confirmação devolve o resultado guardado', true, (j->>'replayed')::boolean);
  j := content_pending_approval('numeiro');
  insert into t values ('aprovados saem da lista', true, not exists (select 1 from jsonb_array_elements(j->'items') x where x->>'id' in (g2, g3)));
  begin perform content_bulk('numeiro', array[g4], 'approve', '{"recorded_only":"sim"}'::jsonb, null, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('recorded_only inválido (22023)', true, st = '22023');
  -- sem recorded_only o comportamento antigo mantém-se
  j := content_bulk('numeiro', array[g4], 'approve', '{}'::jsonb, null, true);
  insert into t values ('sem recorded_only: aprovar como antes', true, (j->'summary'->>'changed')::int = 1);

  -- negativos
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform content_pending_approval('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem scripts.approve não vê a lista (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_pending_approval('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não vê a lista de A (42501)', true, st = '42501');
  begin perform content_bulk('ws_ap_b', array[g4], 'approve', '{"recorded_only":true}'::jsonb, null, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B com lote no seu cliente e guião de A: flag desligada em B (55000)', true, st = '55000');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('guioes.bulk', org, 'ws_ap_b', 'all');
  execute 'set local role authenticated';
  j := content_bulk('ws_ap_b', array[g4], 'approve', '{"recorded_only":true}'::jsonb, null, true);
  insert into t values ('B não aprova guião de A (P0002 no item)', true,
    (j->'results'->0->>'code') = 'P0002');

  -- código de equipa (tem scripts.approve)
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  j := content_pending_approval('numeiro', tok);
  insert into t values ('código de equipa vê a lista do seu cliente', true, exists (select 1 from jsonb_array_elements(j->'items') x where x->>'id' = g4));
  begin perform content_pending_approval('ws_ap_b', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não vê B (42501)', true, st = '42501');
  execute 'reset role';

  insert into t values ('aprovação auditada por guião e por lote', true,
    exists (select 1 from audit_events where entity_id = g2 and action = 'script.approved' and actor_user_id = u_mgr)
    and exists (select 1 from audit_events where action = 'script.bulk' and entity_id = '00000000-0000-4000-8000-00000000a901'));
  -- flag desligada
  delete from feature_flags where key = 'guioes.bulk' and workspace_id = 'numeiro';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  insert into t values ('flag desligada: lista diz que o lote não está ligado', true, not (content_pending_approval('numeiro')->'can'->>'bulk')::boolean);
  begin perform content_bulk('numeiro', array[g4], 'approve', '{"recorded_only":true}'::jsonb, null, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: lote recusado (55000)', true, st = '55000');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
