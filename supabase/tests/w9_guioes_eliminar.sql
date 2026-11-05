-- supabase/tests/w9_guioes_eliminar.sql : eliminar guiões arquivados (FR-02-01, R-09; ADR-0051). Rollback no fim.
-- Negativos exigem o SQLSTATE certo; outro erro conta como falha.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-05'; g2 text := 'numeiro-2026-10-28-06'; g3 text := 'numeiro-2026-10-28-07';
  gb text := 'ws_del_b-2026-10-28-01';
  g guioes; j jsonb; st text; det text; tid uuid; lk int;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_del_b', 'Cliente B (teste)', 'clientedelb', org);
  insert into guioes (id, client_id, date, n, corpo, hooks) values (gb, 'ws_del_b', '2026-10-28', 1, 'corpo secreto B', '[]');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_own,'d-own@test.invalid',now(),'authenticated','authenticated'),(u_adm,'d-adm@test.invalid',now(),'authenticated','authenticated'),
   (u_b,'d-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro',u_own,'client_staff','workspace_owner'),('numeiro',u_adm,'client_staff','workspace_admin'),
   ('ws_del_b',u_b,'client_staff','workspace_owner');
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('busca.global', org, 'numeiro', 'all');
  insert into tasks (workspace_id, title, content_id, created_kind) values ('numeiro', 'rever o guião 6', g2, 'system') returning id into tid;

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  insert into t values ('capacidade scripts.purge registada e só no workspace_owner', true,
    exists (select 1 from capabilities where key = 'scripts.purge' and risk = 'A' and status = 'ativo')
    and (select array_agg(role) from role_capabilities where capability = 'scripts.purge') = array['workspace_owner']);

  execute 'set local role authenticated';
  -- admin arquiva (scripts.delete) mas não elimina
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform content_transition(gid, 'archived'); perform content_transition(g2, 'archived');
  begin perform content_delete(gid, gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace_admin não elimina (42501)', true, st = '42501');
  begin perform content_deleted_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('workspace_admin não vê eliminados (42501)', true, st = '42501');

  -- dono do cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform content_delete(g3, g3); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('guião não arquivado não se elimina (22023)', true, st = '22023');
  begin perform content_delete(gid, 'numeiro-2026-10-28-99'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('confirmação errada recusada (22023)', true, st = '22023');
  begin perform content_delete(gid, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem confirmação recusado (22023)', true, st = '22023');
  insert into t values ('depois das recusas o guião continua lá', true, (select deleted_at from guioes where id = gid) is null);
  begin perform content_delete(g2, g2); st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('com tarefa aberta recusado com a causa (22023)', true, st = '22023' and det like '%tarefa%');
  begin perform content_delete(gb, gb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não elimina guião de B (42501)', true, st = '42501');
  lk := (select lock_version from guioes where id = gid);
  begin perform content_delete(gid, gid, null, lk - 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lock antigo = conflito (PT409)', true, st = 'PT409');
  j := content_delete(gid, gid, 'duplicado do 4', lk);
  insert into t values ('elimina com confirmação e devolve prazo de recuperação', true,
    (j->>'recoverable_until')::timestamptz > now() + interval '29 days');
  insert into t values ('eliminado some do RLS', true, not exists (select 1 from guioes where id = gid));
  insert into t values ('versões do eliminado fora do RLS', true, not exists (select 1 from content_versions where content_id = gid));
  insert into t values ('transições do eliminado fora do RLS', true, not exists (select 1 from content_transitions where content_id = gid));
  insert into t values ('outros guiões continuam visíveis', true, exists (select 1 from guioes where id = g3)
    and exists (select 1 from content_versions where content_id = g3));
  begin perform content_history(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('histórico do eliminado: P0002', true, st = 'P0002');
  begin perform content_transition(gid, 'restore'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('recuperar do arquivo um eliminado: P0002', true, st = 'P0002');
  begin perform content_save(gid, '{"corpo":"x"}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('editar eliminado: P0002', true, st = 'P0002');
  begin perform content_duplicate(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('duplicar eliminado: P0002', true, st = 'P0002');
  begin perform content_delete(gid, gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('eliminar duas vezes: P0002', true, st = 'P0002');
  j := search_global(gid);
  insert into t values ('pesquisa pelo ID não encontra o eliminado', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = gid));
  j := search_global('Tema de teste 5');
  insert into t values ('pesquisa por texto não encontra o eliminado', true,
    not exists (select 1 from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i where i->>'id' = gid));
  begin perform review_inbox('numeiro', '{"status":["archived"]}'::jsonb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('caixa de revisão não aceita arquivados (22023)', true, st = '22023');
  j := content_deleted_list('numeiro');
  insert into t values ('lista de eliminados do dono traz o guião, o motivo e quem', true,
    exists (select 1 from jsonb_array_elements(j) x where x->>'id' = gid and x->>'reason' = 'duplicado do 4' and x->>'deleted_by' = 'd-own@test.invalid'));

  -- outro cliente
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform content_deleted_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista eliminados de A (42501)', true, st = '42501');
  begin perform content_undelete(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não recupera guião de A (P0002, igual a inexistente)', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform content_undelete(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin sem scripts.purge não recupera (P0002)', true, st = 'P0002');

  -- código de equipa
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin perform content_delete(g3, g3, null, null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não elimina (42501)', true, st = '42501');
  insert into t values ('código de equipa não vê o eliminado', true,
    not exists (select 1 from legacy_guioes(tok, current_date - 400, current_date + 400) x where x.id = gid)
    and exists (select 1 from legacy_guioes(tok, current_date - 400, current_date + 400) x where x.id = g3));
  execute 'reset role';

  -- base de dados (motor / service role)
  begin update guioes set corpo = 'motor' where id = gid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('escrita direta num eliminado recusada (P0002)', true, st = 'P0002');
  insert into t values ('auditoria e transição de eliminação', true,
    exists (select 1 from audit_events where entity_id = gid and action = 'script.deleted' and actor_user_id = u_own)
    and exists (select 1 from content_transitions where content_id = gid and to_status = 'deleted' and reason = 'duplicado do 4')
    and exists (select 1 from domain_events where entity_id = gid and type = 'script.deleted'));
  insert into t values ('versões continuam guardadas (imutáveis)', true, (select count(*) from content_versions where content_id = gid) >= 1);

  -- recuperar
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  g := content_undelete(gid);
  insert into t values ('dono recupera: volta a arquivado e visível', true, g.deleted_at is null and g.editorial_status = 'archived'
    and exists (select 1 from guioes where id = gid));
  g := content_transition(gid, 'restore');
  insert into t values ('recuperado pode sair do arquivo', true, g.editorial_status <> 'archived');
  perform content_transition(gid, 'archived');
  perform content_delete(gid, gid);
  execute 'reset role';
  perform set_config('clipstudio.content_undelete', 'on', true);
  update guioes set deleted_at = now() - interval '31 days' where id = gid;
  perform set_config('clipstudio.content_undelete', 'off', true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform content_undelete(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('depois de 30 dias não se recupera (22023)', true, st = '22023');
  insert into t values ('depois de 30 dias sai da lista de eliminados', true,
    not exists (select 1 from jsonb_array_elements(content_deleted_list('numeiro')) x where x->>'id' = gid));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
