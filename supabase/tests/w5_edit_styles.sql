-- supabase/tests/w5_edit_styles.sql : catálogo de estilos e preset de edição (W5-02, VAR-02, EDL-01; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_mgr uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  j jsonb; st text; det text; ok int := 0; bad int := 0; res text := ''; r record; s13 jsonb; good jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_es_b', 'Estilos B', 'esb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'es-adm@test.invalid'),(u_con,'es-con@test.invalid'),(u_b,'es-b@test.invalid'),(u_mgr,'es-mgr@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('ws_es_b', u_b, 'client_staff', 'workspace_admin'), ('ws_es_b', u_mgr, 'client_staff', 'manager');
  -- a fixture de testes cria o numeiro depois das migrações: semear como a migração faria
  perform _edit_seed('numeiro', 'system', 'teste');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  j := edit_catalog('numeiro');
  insert into t values ('ponto de partida: 13 estilos, S13 ativo, resto em rascunho', true,
    jsonb_array_length(j->'styles') = 13
    and (select count(*) from jsonb_array_elements(j->'styles') x where x->>'status' = 'ativo') = 1
    and exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'S13' and x->>'status' = 'ativo' and x->'problems' = '[]'));
  insert into t values ('preset por defeito: masters por hook, 2 splits e S13 fixado na versão 1', true,
    jsonb_array_length(j->'preset'->'outputs') = 4 and j->'preset'->'outputs'->0->>'kind' = 'master' and (j->'preset'->'outputs'->0->>'per_hook')::boolean
    and j->'preset'->'outputs'->3->>'style' = 'S13' and (j->'preset'->'outputs'->3->>'style_version')::int = 1 and not (j->'preset'->>'stale')::boolean);
  insert into t values ('colaborador lê mas não gere', true, not (j->>'can_manage')::boolean);
  begin perform edit_style_save('numeiro', 'S01', '{"name":"x"}', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não grava estilos (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  s13 := (select x->'spec' from jsonb_array_elements(edit_catalog('numeiro')->'styles') x where x->>'key' = 'S13');
  j := edit_style_save('numeiro', 'S13', jsonb_build_object('name', 'Faixa de estatuto v2', 'spec', s13), 1);
  insert into t values ('gravar cria a versão 2', true, exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'S13' and (x->>'version')::int = 2));
  insert into t values ('preset fica marcado como desatualizado (fixou a v1)', true, (j->'preset'->>'stale')::boolean
    and (j->'preset'->'outputs'->3->>'style_version')::int = 1);
  insert into t values ('histórico guarda as duas versões', true, jsonb_array_length(edit_style_history('numeiro', 'S13')) = 2);
  begin perform edit_style_save('numeiro', 'S13', '{"name":"outra"}', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gravar sobre versão antiga é recusado (40001)', true, st = '40001');

  -- texto fora do retângulo seguro
  begin
    perform edit_style_save('numeiro', 'S13', jsonb_build_object('spec', jsonb_set(s13, '{layers,3,box}', '[20, 830, 860, 180]')), 2);
    st := 'none'; exception when others then get stacked diagnostics st = returned_sqlstate, det = pg_exception_detail; end;
  insert into t values ('título fora do retângulo seguro é recusado (22023)', true, st = '22023' and det like '%retângulo seguro%');
  begin perform edit_style_save('numeiro', 'S13', jsonb_build_object('spec', jsonb_set(s13, '{canvas}', '{"w":1920,"h":1080}')), 2); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('formato tem de ser 1080×1920 (22023)', true, st = '22023');
  begin perform edit_style_save('numeiro', 'S13', jsonb_build_object('spec', jsonb_set(s13, '{layers,2,color}', '"vermelho"')), 2); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('cor inválida recusada (22023)', true, st = '22023');

  -- rascunho sem layout não ativa; com layout ativa
  begin perform edit_style_set_status('numeiro', 'S06', 'ativo'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('rascunho sem camadas não fica ativo (22023)', true, st = '22023');
  good := '{"canvas":{"w":1080,"h":1920},"layers":[{"kind":"video","box":[0,0,1080,1920]},{"kind":"title","box":[100,300,800,200],"max_words":5}]}';
  perform edit_style_save('numeiro', 'S06', jsonb_build_object('spec', good, 'platforms', '["instagram"]'::jsonb, 'transformation', 'alta'), 1);
  j := edit_style_set_status('numeiro', 'S06', 'ativo');
  insert into t values ('com layout válido fica ativo', true, exists (select 1 from jsonb_array_elements(j->'styles') x where x->>'key' = 'S06' and x->>'status' = 'ativo'));

  -- preset
  begin perform edit_preset_save('numeiro', '[{"kind":"style","style":"S01"}]', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('preset recusa estilo em rascunho (22023)', true, st = '22023');
  begin perform edit_preset_save('numeiro', '[{"kind":"style","style":"S99"}]', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('preset recusa estilo inexistente (22023)', true, st = '22023');
  begin perform edit_preset_save('numeiro', '[{"kind":"gif"}]', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('preset recusa tipo desconhecido (22023)', true, st = '22023');
  j := edit_preset_save('numeiro', '[{"kind":"master","per_hook":true},{"kind":"style","style":"S13"},{"kind":"style","style":"S06","captions":"none"}]', 1);
  insert into t values ('preset novo fixa as versões atuais', true, (j->'preset'->>'version')::int = 2 and not (j->'preset'->>'stale')::boolean
    and (j->'preset'->'outputs'->1->>'style_version')::int = 2 and j->'preset'->'outputs'->2->>'captions' = 'none');
  begin perform edit_preset_save('numeiro', '[{"kind":"master"}]', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('preset sobre versão antiga é recusado (40001)', true, st = '40001');
  begin perform edit_style_set_status('numeiro', 'S06', 'arquivado'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não arquiva estilo usado no preset (22023)', true, st = '22023');

  -- isolamento: B não vê nem mexe no numeiro; o catálogo de B é só dele
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_catalog('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê o catálogo do numeiro (42501)', true, st = '42501');
  begin perform edit_style_save('numeiro', 'S13', '{"name":"x"}', 2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não grava no numeiro (42501)', true, st = '42501');
  begin perform edit_style_history('numeiro', 'S13'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não lê o histórico do numeiro (42501)', true, st = '42501');
  j := edit_catalog('ws_es_b');
  insert into t values ('B começa sem estilos nem preset', true, jsonb_array_length(j->'styles') = 0 and j->'preset' = 'null'::jsonb and (j->>'can_manage')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_mgr, 'role','authenticated')::text, true);
  j := edit_catalog_init('ws_es_b');
  insert into t values ('gestor de B parte do ponto de partida', true, jsonb_array_length(j->'styles') = 13 and j->'preset' is not null);
  begin perform edit_catalog_init('ws_es_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não semeia duas vezes (22023)', true, st = '22023');
  insert into t values ('estilos de B são independentes do numeiro', true,
    exists (select 1 from jsonb_array_elements(edit_catalog('ws_es_b')->'styles') x where x->>'key' = 'S13' and (x->>'version')::int = 1));

  -- código de equipa: lê, não gere
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := edit_catalog('numeiro', tok);
  insert into t values ('código de equipa lê o catálogo sem gerir', true, jsonb_array_length(j->'styles') = 13 and not (j->>'can_manage')::boolean);
  begin perform edit_preset_save('numeiro', '[{"kind":"master"}]', 2, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não muda o preset (42501)', true, st = '42501');
  begin perform edit_catalog('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código não lê (42501/28000)', true, st in ('42501', '28000'));
  execute 'reset role';

  begin update edit_style_versions set name = 'x' where workspace_id = 'numeiro'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se alteram (42501)', true, st = '42501');
  begin delete from edit_presets where workspace_id = 'numeiro'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('presets não se apagam (42501)', true, st = '42501');
  insert into t values ('tabelas fechadas a leitura direta', true, not has_table_privilege('authenticated', 'public.edit_style_versions', 'select')
    and not has_table_privilege('anon', 'public.edit_presets', 'select'));
  insert into t values ('gravações ficam no histórico de ações', true,
    (select count(*) from audit_events where workspace_id = 'numeiro' and action in ('edit.style_saved', 'edit.preset_saved', 'edit.style_status')) >= 4);
  insert into t values ('styles.manage só para owner, admin e gestor', true,
    (select array_agg(role order by role) from role_capabilities where capability = 'styles.manage') = array['manager', 'workspace_admin', 'workspace_owner']);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
