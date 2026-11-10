-- supabase/tests/w10_biblioteca_estilos.sql : biblioteca de estilos da agência e importar para cliente (REF-07, REF-08). W10-42; rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_ag uuid := gen_random_uuid(); u_mem uuid := gen_random_uuid(); u_cli uuid := gen_random_uuid(); u_bcli uuid := gen_random_uuid();
  b jsonb; st text; ok int := 0; bad int := 0; res text := ''; rr record; v int;
  spec jsonb := '{"canvas":{"w":1080,"h":1920},"layers":[{"kind":"video","box":[0,0,1080,1920]},{"kind":"captions","box":[90,1225,870,90],"max_words":4}]}';
begin
  insert into clients (id, name, handle, organization_id) values ('ws_be_b', 'Estilos B', 'beb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_ag,'be-ag@test.invalid'),(u_mem,'be-mem@test.invalid'),(u_cli,'be-cli@test.invalid'),(u_bcli,'be-bcli@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_admin'), (org, u_mem, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'workspace_admin'), ('numeiro', u_mem, 'agency_staff', 'workspace_admin'),
    ('numeiro', u_cli, 'client_staff', 'workspace_admin'), ('ws_be_b', u_bcli, 'client_staff', 'workspace_admin');
  -- um estilo do próprio cliente com a chave S90 (não veio da agência)
  insert into edit_styles (workspace_id, key, status) values ('numeiro', 'S90', 'ativo');
  insert into edit_style_versions (workspace_id, key, version, name, spec, actor_kind) values ('numeiro', 'S90', 1, 'Do cliente', spec, 'system');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  -- staff da agência com a capacidade
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  b := agency_style_library();
  insert into t values ('biblioteca abre para admin da agência', true, b ? 'styles' and (b->>'can_import')::boolean);
  insert into t values ('clientes a que posso importar: só os que vejo (numeiro, não B)', true,
    exists (select 1 from jsonb_array_elements(b->'clients') c where c->>'ws' = 'numeiro')
    and not exists (select 1 from jsonb_array_elements(b->'clients') c where c->>'ws' = 'ws_be_b'));
  b := agency_style_save('S90', jsonb_build_object('name', 'Caixa teste', 'spec', spec, 'source_url', 'https://www.instagram.com/reel/x',
                                                   'look', '{"captions":{"color":"#FFFFFF"},"music":{"label":"m","db":-10,"asset":"x"}}'::jsonb), 0);
  insert into t values ('gravar cria v1', true, (select (s->>'version')::int = 1 from jsonb_array_elements(b->'styles') s where s->>'key' = 'S90'));
  execute 'reset role';
  insert into t values ('música tirada do aspeto da agência', true, (select look ? 'music' from agency_style_versions where key = 'S90') = false);
  execute 'set local role authenticated';
  begin perform agency_style_save('S90', '{"name":"x"}', 0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão desatualizada recusada (40001)', true, st = '40001');
  begin perform agency_style_save('S90', '{"source_url":"javascript:alert(1)"}', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link de origem tem de ser http(s) (22023)', true, st = '22023');
  begin perform agency_style_import('S90', 'numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('rascunho não se importa (22023)', true, st = '22023');
  perform agency_style_set_status('S90', 'ativo');
  begin perform agency_style_import('S90', 'numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('chave do cliente que não veio da agência: recusa (PT409)', true, st = 'PT409');
  execute 'reset role';
  insert into t values ('estilo do cliente intacto', true, (select current_version = 1 and origin_key is null from edit_styles where workspace_id = 'numeiro' and key = 'S90'));
  execute 'set local role authenticated';
  b := agency_style_import('S90', 'numeiro', 'S91');
  execute 'reset role';
  insert into t values ('importar com outra chave: ativo, versão fixa e origem', true,
    (select status = 'ativo' and current_version = 1 and origin_key = 'S90' and origin_version = 1 from edit_styles where workspace_id = 'numeiro' and key = 'S91'));
  execute 'set local role authenticated';
  insert into t values ('a biblioteca mostra quem tem o estilo', true,
    (select exists (select 1 from jsonb_array_elements(s->'imports') i where i->>'ws' = 'numeiro' and i->>'key' = 'S91' and (i->>'version')::int = 1)
       from jsonb_array_elements(b->'styles') s where s->>'key' = 'S90'));
  execute 'reset role';
  insert into t values ('importar outra vez sem mudança: não cria versão', true,
    (select current_version from edit_styles where workspace_id = 'numeiro' and key = 'S91') = 1 and agency_style_import('S90', 'numeiro', 'S91') ? 'styles'
    and (select current_version from edit_styles where workspace_id = 'numeiro' and key = 'S91') = 1);
  execute 'set local role authenticated';
  perform agency_style_save('S90', '{"name":"Caixa teste 2"}', 1);
  execute 'reset role';
  insert into t values ('cliente fica na versão importada até atualizar', true,
    (select origin_version from edit_styles where workspace_id = 'numeiro' and key = 'S91') = 1);
  execute 'set local role authenticated';
  perform agency_style_import('S90', 'numeiro', 'S91');
  execute 'reset role';
  insert into t values ('atualizar: versão nova no cliente com a versão 2 da agência', true,
    (select current_version = 2 and origin_version = 2 from edit_styles where workspace_id = 'numeiro' and key = 'S91')
    and (select name from edit_style_versions where workspace_id = 'numeiro' and key = 'S91' and version = 2) = 'Caixa teste 2');
  execute 'set local role authenticated';
  execute 'reset role';
  insert into t values ('aspeto vem da agência, sem música', true,
    (select look->'captions'->>'color' = '#FFFFFF' and not (look ? 'music') from edit_style_versions where workspace_id = 'numeiro' and key = 'S91' and version = 2));
  execute 'set local role authenticated';
  begin perform agency_style_import('S90', 'ws_be_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente que não vejo: recusado (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('auditoria: importado e atualizado', true,
    (select count(*) from audit_events where entity_id = 'S91' and action in ('edit.style_imported', 'edit.style_import_updated')) = 2);
  execute 'set local role authenticated';
  -- o catálogo do cliente diz a origem
  b := edit_catalog('numeiro');
  insert into t values ('catálogo do cliente mostra a origem', true,
    (select s->'origin'->>'key' = 'S90' and (s->'origin'->>'version')::int = 2 from jsonb_array_elements(b->'styles') s where s->>'key' = 'S91'));

  -- membro da agência sem a capacidade
  perform set_config('request.jwt.claims', json_build_object('sub', u_mem, 'role','authenticated')::text, true);
  begin perform agency_style_library(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro da agência sem capacidade: recusado (42501)', true, st = '42501');
  begin perform agency_style_import('S90', 'numeiro', 'S92'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('membro sem styles.import: recusado (42501)', true, st = '42501');
  -- equipa do cliente nunca vê a biblioteca (R-13)
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role','authenticated')::text, true);
  begin perform agency_style_library(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não vê a biblioteca (42501)', true, st = '42501');
  begin perform agency_style_history('S90'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não lê versões (42501)', true, st = '42501');
  begin perform agency_style_save('S93', '{"name":"x"}', 0); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não grava (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_bcli, 'role','authenticated')::text, true);
  begin perform agency_style_import('S90', 'ws_be_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não importa para si (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('versões da agência imutáveis', true, (select count(*) from agency_style_versions where key = 'S90') = 2);
  begin update agency_style_versions set name = 'x' where key = 'S90'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('update numa versão recusado', true, st = '42501');
  insert into t values ('anon sem EXECUTE', true, not has_function_privilege('anon', 'public.agency_style_library()', 'execute'));
  insert into t values ('tabelas fechadas à API', true, not has_table_privilege('authenticated', 'public.agency_styles', 'select'));
  -- a herança de aspeto continua fora das importações
  insert into edit_style_versions (workspace_id, key, version, name, spec, actor_kind) values ('numeiro', 'S91', 3, 'herda', spec, 'system');
  insert into t values ('versão normal herda o aspeto anterior', true,
    (select look is not null from edit_style_versions where workspace_id = 'numeiro' and key = 'S91' and version = 3));

  for rr in select * from t loop
    if rr.expected = rr.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || rr.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
