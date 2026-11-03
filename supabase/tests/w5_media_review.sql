-- supabase/tests/w5_media_review.sql : revisão de vídeo por link da Drive (W5-04, CHG-006; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_ag uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-07'; gb text := 'ws_mr_b-1';
  m1 jsonb; m2 jsonb; mb jsonb; c1 jsonb; c2 jsonb; j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
  fid1 text := '1AbCdEfGhIjKlMnOpQrStUvWx'; fid2 text := '1ZyXwVuTsRqPoNmLkJiHgFeDc';
begin
  insert into clients (id, name, handle, organization_id) values ('ws_mr_b', 'Media B', 'mrb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_mr_b', current_date, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'mr-con@test.invalid'),(u_rev,'mr-rev@test.invalid'),(u_view,'mr-view@test.invalid'),(u_b,'mr-b@test.invalid'),(u_ag,'mr-ag@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_mr_b', u_b, 'client_staff', 'workspace_admin'),
    ('ws_mr_b', u_ag, 'agency_staff', 'manager');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- colaborador regista o vídeo do hook 1 por link da Drive
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  m1 := media_link_add(gid, 'hook_1', 'https://drive.google.com/file/d/' || fid1 || '/view?usp=sharing', 'S15', 'g07_hook1_S15.mp4', 58.4);
  insert into t values ('regista link da Drive (ID extraído, v1, por rever)', true,
    m1->>'drive_file_id' = fid1 and (m1->>'version')::int = 1 and m1->>'review_status' = 'in_review');
  j := media_link_add(gid, 'hook_1', fid1, 'S15');
  insert into t values ('repetir o mesmo ficheiro não duplica', true, j->>'id' = m1->>'id');
  begin perform media_link_add(gid, 'hook_1', 'https://example.com/video.mp4'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link que não é da Drive (22023)', true, st = '22023');
  begin perform media_link_add(gid, 'hook_9', fid2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('hook que o guião não tem (22023)', true, st = '22023');
  begin perform media_link_add(gb, 'hook_1', fid2); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não regista em guião de outro cliente (42501)', true, st = '42501');

  -- comentários com momento
  c1 := media_comment_add((m1->>'id')::uuid, 'Aos 0:23 o corte salta.', 23000);
  insert into t values ('comenta num momento', true, (c1->>'t_ms')::int = 23000);
  begin perform media_comment_add((m1->>'id')::uuid, 'depois do fim', 9999000); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('momento depois do fim do vídeo (22023)', true, st = '22023');
  begin perform media_comment_add((m1->>'id')::uuid, '  '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentário vazio (22023)', true, st = '22023');
  begin perform media_decide((m1->>'id')::uuid, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não decide (42501)', true, st = '42501');

  -- revisor responde, pede alterações com motivo
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  c2 := media_comment_add((m1->>'id')::uuid, 'Concordo, tira esse take.', null, (c1->>'id')::uuid);
  insert into t values ('resposta herda o momento', true, (c2->>'t_ms')::int = 23000 and c2->>'parent_id' = c1->>'id');
  begin perform media_decide((m1->>'id')::uuid, 'changes_requested'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pedir alterações sem motivo (22023)', true, st = '22023');
  j := media_decide((m1->>'id')::uuid, 'changes_requested', 'Corte aos 0:23.');
  insert into t values ('pede alterações com motivo', true, j->>'review_status' = 'changes_requested');
  j := media_comment_resolve((c1->>'id')::uuid);
  insert into t values ('revisor resolve comentário', true, j->>'resolved_at' is not null);

  -- nova versão: a anterior deixa de se poder decidir
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  m2 := media_link_add(gid, 'hook_1', fid2, 'S15');
  insert into t values ('novo ficheiro = versão 2 por rever', true, (m2->>'version')::int = 2 and m2->>'review_status' = 'in_review');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform media_decide((m1->>'id')::uuid, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão antiga não se decide (22023)', true, st = '22023');
  j := media_decide((m2->>'id')::uuid, 'approved');
  insert into t values ('aprova a v2', true, j->>'review_status' = 'approved');
  begin perform media_decide((m2->>'id')::uuid, 'rejected', 'mudei de ideia'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aprovado é final (22023)', true, st = '22023');
  j := media_detail((m2->>'id')::uuid);
  insert into t values ('detalhe: 2 versões e 1 decisão', true,
    jsonb_array_length(j->'versions') = 2 and jsonb_array_length(j->'decisions') = 1 and (j->'can'->>'decide')::boolean);
  j := media_review_list('numeiro', '{}');
  insert into t values ('lista só a versão mais recente', true,
    (select count(*) from jsonb_array_elements(j->'items') x where x->'guiao'->>'id' = gid) = 1
    and exists (select 1 from jsonb_array_elements(j->'items') x where x->'media'->>'id' = m2->>'id'));
  insert into t values ('lista traz o texto do hook', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->'media'->>'id' = m2->>'id' and x->'guiao'->>'hook' is not null));

  -- leitor vê mas não comenta nem decide
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  j := media_detail((m2->>'id')::uuid);
  insert into t values ('leitor vê sem poder decidir', true, not (j->'can'->>'decide')::boolean);
  begin perform media_comment_add((m2->>'id')::uuid, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não comenta (42501)', true, st = '42501');

  -- outro cliente não vê nada de A (nem por ID)
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_detail((m2->>'id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não abre vídeo de A por ID (42501)', true, st = '42501');
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista vídeos de A (42501)', true, st = '42501');
  begin perform media_comment_add((m2->>'id')::uuid, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não comenta vídeo de A (42501)', true, st = '42501');
  mb := media_link_add(gb, 'hook_1', fid1);
  insert into t values ('B regista no seu espaço', true, mb->>'id' is not null);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := media_review_list('ws_mr_b');
  insert into t values ('agência com acesso a B vê B', true, jsonb_array_length(j->'items') = 1);
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('agência sem acesso a A não vê A (42501)', true, st = '42501');

  -- imutabilidade e tabelas fechadas
  execute 'reset role';
  begin update content_media set drive_file_id = fid1 where id = (m2->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ficheiro de uma versão não se troca (42501)', true, st = '42501');
  begin delete from media_comments where id = (c1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários não se apagam (42501)', true, st = '42501');
  begin update media_decisions set reason = 'x' where media_id = (m1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('decisões não se alteram (42501)', true, st = '42501');
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.content_media', 'select') and not has_table_privilege('anon', 'public.media_comments', 'select'));

  -- código de equipa do Numeiro: comenta e decide em A, nunca em B
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := media_comment_add((m2->>'id')::uuid, 'Pelo código de equipa', 1000, null, tok);
  insert into t values ('código de equipa comenta', true, j->>'author_kind' = 'legacy_code');
  begin perform media_detail((mb->>'id')::uuid, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não abre vídeo de B (42501)', true, st = '42501');
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código recusado', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
