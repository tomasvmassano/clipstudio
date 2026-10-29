-- supabase/tests/w2_content_meta.sql : campanha, responsável, plataformas e etiquetas (FR-02-03) e fila filtrável (FR-03-01). Rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date; j jsonb; g guioes; pid uuid; pid2 uuid; pb uuid; st text; det text; ok int := 0; bad int := 0; res text := ''; r record;
  gid text; s jsonb;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_cm_b', 'Meta B', 'cmb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'cm-adm@test.invalid'),(u_con,'cm-con@test.invalid'),(u_view,'cm-view@test.invalid'),(u_b,'cm-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_cm_b', u_b, 'client_staff', 'workspace_admin');
  insert into profiles (user_id, display_name) values (u_con, 'Rita Contribui');
  update guioes set date = d where client_id = 'numeiro';
  gid := (select id from guioes where client_id = 'numeiro' and editorial_status not in ('rejected','archived') order by n limit 1);
  insert into projects (workspace_id, name) values ('ws_cm_b', 'Campanha B') returning id into pb;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := project_save('numeiro', null, '{"name":"Black Friday","kind":"campanha"}');
  pid := (select (x->>'id')::uuid from jsonb_array_elements(j->'projects') x where x->>'name' = 'Black Friday');
  insert into t values ('admin cria campanha', true, pid is not null and (j->>'can_manage')::boolean);
  j := project_save('numeiro', null, '{"name":"Série Leis","kind":"serie"}');
  pid2 := (select (x->>'id')::uuid from jsonb_array_elements(j->'projects') x where x->>'name' = 'Série Leis');
  begin perform project_save('numeiro', null, '{"name":"black friday "}'); st := 'none'; exception when others then get stacked diagnostics st = returned_sqlstate, det = pg_exception_detail; end;
  insert into t values ('nome repetido (sem maiúsculas nem espaços) é recusado', true, st = '22023' and det like '%Já há%');
  begin perform project_save('numeiro', null, '{"name":"x","starts_on":"2026-11-10","ends_on":"2026-11-01"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('fim antes do início é recusado (22023)', true, st = '22023');

  g := content_meta_set(gid, jsonb_build_object('project_id', pid, 'owner_id', u_con, 'tags', '["Relações", " relações ", "dinheiro"]'::jsonb, 'platforms', '["instagram","tiktok"]'::jsonb));
  insert into t values ('guião fica com campanha, responsável, etiquetas e plataformas', true,
    g.project_id = pid and g.owner_id = u_con and g.tags = array['dinheiro', 'relações'] and g.platforms = array['instagram', 'tiktok']);
  insert into t values ('não cria versão nova nem mexe no estado editorial', true,
    g.current_version_id = (select current_version_id from guioes where id = gid) and g.editorial_status = (select editorial_status from guioes where id = gid));
  begin perform content_meta_set(gid, jsonb_build_object('project_id', pb)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campanha de outro cliente é recusada (22023)', true, st = '22023');
  begin perform content_meta_set(gid, jsonb_build_object('owner_id', u_b)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('responsável de outro cliente é recusado (22023)', true, st = '22023');
  begin perform content_meta_set(gid, jsonb_build_object('owner_id', u_view)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não pode ser responsável (22023)', true, st = '22023');
  begin perform content_meta_set(gid, '{"platforms":["facebook"]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('plataforma desconhecida recusada (22023)', true, st = '22023');
  begin perform content_meta_set(gid, jsonb_build_object('tags', (select jsonb_agg('t' || x) from generate_series(1, 11) x))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('mais de 10 etiquetas recusado (22023)', true, st = '22023');
  begin perform content_meta_set(gid, '{"corpo":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não muda o texto por aqui (22023)', true, st = '22023');

  -- arquivar a campanha: guiões ficam, mas não se escolhe para outros
  j := project_save('numeiro', pid2, '{"status":"arquivada"}');
  insert into t values ('arquivar a série', true, exists (select 1 from jsonb_array_elements(j->'projects') x where (x->>'id')::uuid = pid2 and x->>'status' = 'arquivada'));
  begin perform content_meta_set(gid, jsonb_build_object('project_id', pid2)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campanha arquivada não se escolhe (22023)', true, st = '22023');
  insert into t values ('lista conta os guiões da campanha', true,
    exists (select 1 from jsonb_array_elements(j->'projects') x where (x->>'id')::uuid = pid and (x->>'scripts')::int = 1));
  j := content_owners('numeiro');
  insert into t values ('responsáveis possíveis: quem edita, com o nome do perfil', true,
    exists (select 1 from jsonb_array_elements(j) x where (x->>'user_id')::uuid = u_con and x->>'label' = 'Rita Contribui')
    and not exists (select 1 from jsonb_array_elements(j) x where (x->>'user_id')::uuid in (u_view, u_b)));

  -- teleprompter traz os campos para filtrar
  s := recording_session_open('numeiro', d);
  insert into t values ('fila do teleprompter traz campanha e responsável', true,
    exists (select 1 from jsonb_array_elements(s->'items') x where x->>'content_id' = gid and (x->'content'->>'project_id')::uuid = pid
            and (x->'content'->>'owner_id')::uuid = u_con and x->'content'->'tags' = '["dinheiro","relações"]'::jsonb));

  -- colaborador edita metadados mas não gere campanhas; leitor nem isso
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  g := content_meta_set(gid, '{"owner_id": null}');
  insert into t values ('colaborador muda o responsável', true, g.owner_id is null);
  begin perform project_save('numeiro', null, '{"name":"Nova"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não cria campanhas (42501)', true, st = '42501');
  insert into t values ('colaborador vê a lista sem poder gerir', true, not (projects_list('numeiro')->>'can_manage')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform content_meta_set(gid, '{"tags":[]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não muda metadados (42501)', true, st = '42501');

  -- outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform projects_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê campanhas do numeiro (42501)', true, st = '42501');
  begin perform content_meta_set(gid, '{"tags":["x"]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não mexe em guiões do numeiro (42501)', true, st = '42501');
  begin perform project_save('numeiro', pid, '{"name":"roubada"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não renomeia campanha do numeiro (42501)', true, st = '42501');
  begin perform project_save('ws_cm_b', pid, '{"name":"roubada"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('trocar o id para outro cliente não encontra (P0002)', true, st = 'P0002');
  begin perform content_owners('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lista pessoas do numeiro (42501)', true, st = '42501');

  -- código de equipa
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  insert into t values ('código de equipa lê as campanhas', true, jsonb_array_length(projects_list('numeiro', tok)->'projects') = 2);
  g := content_meta_set(gid, '{"platforms":["youtube"]}', tok);
  insert into t values ('código de equipa muda plataformas', true, g.platforms = array['youtube']);
  execute 'reset role';
  insert into t values ('responsável recebe notificação', true, exists (select 1 from notifications where user_id = u_con and kind = 'script_assigned' and entity_id = gid));
  insert into t values ('fica no histórico de ações', true, exists (select 1 from audit_events where entity_id = gid and action = 'script.meta_changed'));
  insert into t values ('tabela de campanhas fechada a leitura direta', true, not has_table_privilege('authenticated', 'public.projects', 'select'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
