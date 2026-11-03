-- supabase/tests/w5_media_review.sql : revisão de vídeo por link da Drive sobre a biblioteca (W5-04, CHG-006; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_ag uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-07'; gb text := 'ws_mr_b-1';
  fid1 text := '1AbCdEfGhIjKlMnOpQrStUvWx'; fid2 text := '1ZyXwVuTsRqPoNmLkJiHgFeDc';
  a1 jsonb; a2 jsonb; ab jsonb; v1 uuid; v2 uuid; c1 jsonb; c2 jsonb; j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_mr_b', 'Media B', 'mrb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_mr_b', current_date, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'mr-con@test.invalid'),(u_rev,'mr-rev@test.invalid'),(u_view,'mr-view@test.invalid'),(u_b,'mr-b@test.invalid'),(u_ag,'mr-ag@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_mr_b', u_b, 'client_staff', 'workspace_admin'),
    ('ws_mr_b', u_ag, 'agency_staff', 'manager');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- biblioteca desligada: a revisão também não abre
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('biblioteca desligada: 55000', true, st = '55000');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'media.library', org, w, 'all' from unnest(array['numeiro','ws_mr_b']) w;
  execute 'set local role authenticated';

  -- colaborador regista o vídeo do hook 1 como link da Drive ligado ao guião
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  a1 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid1 || '/view', 'title', 'g07_hook1_S15.mp4',
          'tags', jsonb_build_array('hook_1', 'S15'), 'content_id', gid, 'format', '9:16'));
  v1 := (a1->'current'->>'id')::uuid;
  j := media_review_list('numeiro');
  insert into t values ('aparece na revisão: hook 1, S15, por rever, ID da Drive', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where x->>'asset_id' = a1->>'id' and x->>'variant' = 'hook_1'
            and x->>'style' = 'S15' and x->>'status' = 'in_review' and x->>'drive_file_id' = fid1 and x->'guiao'->>'hook' is not null));
  perform media_link_add('numeiro', null, jsonb_build_object('url', 'https://example.com/v.mp4', 'title', 'fora da Drive', 'content_id', gid));
  perform media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid2 || '/view', 'title', 'sem guião'));
  j := media_review_list('numeiro');
  insert into t values ('só vídeos da Drive ligados a um guião', true, jsonb_array_length(j->'items') = 1);
  c1 := media_review_comment('numeiro', v1, 'Aos 0:23 o corte salta.', 23000);
  insert into t values ('comenta num momento', true, (c1->>'t_ms')::int = 23000);
  begin perform media_review_comment('numeiro', v1, '  '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentário vazio (22023)', true, st = '22023');
  begin perform media_review_decide('numeiro', v1, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não decide (42501)', true, st = '42501');

  -- revisor responde e pede alterações com motivo
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  c2 := media_review_comment('numeiro', v1, 'Concordo.', null, (c1->>'id')::uuid);
  insert into t values ('resposta herda o momento', true, (c2->>'t_ms')::int = 23000 and c2->>'parent_id' = c1->>'id');
  begin perform media_review_decide('numeiro', v1, 'changes_requested'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pedir alterações sem motivo (22023)', true, st = '22023');
  j := media_review_decide('numeiro', v1, 'changes_requested', 'Corte aos 0:23.');
  insert into t values ('pede alterações com motivo', true, j->>'status' = 'changes_requested');
  j := media_review_comment_resolve('numeiro', (c1->>'id')::uuid);
  insert into t values ('revisor resolve comentário', true, j->>'resolved_at' is not null);

  -- versão nova no mesmo ativo: volta a por rever, a anterior não se decide
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  a2 := media_link_add('numeiro', (a1->>'id')::uuid, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid2 || '/view'));
  v2 := (a2->'current'->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  j := media_review_detail('numeiro', (a1->>'id')::uuid);
  insert into t values ('versão 2 por rever, com histórico de 2 versões', true,
    j->'version'->>'status' = 'in_review' and (j->'version'->>'version')::int = 2 and jsonb_array_length(j->'versions') = 2);
  begin perform media_review_decide('numeiro', v1, 'approved'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão antiga não se decide (22023)', true, st = '22023');
  j := media_review_detail('numeiro', (a1->>'id')::uuid, v1);
  insert into t values ('versão antiga guarda decisão e comentários', true,
    j->'version'->>'status' = 'changes_requested' and jsonb_array_length(j->'decisions') = 1 and jsonb_array_length(j->'comments') = 2);
  j := media_review_decide('numeiro', v2, 'approved');
  insert into t values ('aprova a v2', true, j->>'status' = 'approved');
  begin perform media_review_decide('numeiro', v2, 'rejected', 'mudei de ideia'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aprovado é final (22023)', true, st = '22023');
  j := media_review_list('numeiro', '{"status":["approved"]}');
  insert into t values ('filtro por estado', true, jsonb_array_length(j->'items') = 1 and (j->'counts'->>'approved')::int = 1);

  -- leitor vê mas não comenta nem decide
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  j := media_review_detail('numeiro', (a1->>'id')::uuid);
  insert into t values ('leitor vê sem poder decidir', true, not (j->'can'->>'decide')::boolean and not (j->'can'->>'comment')::boolean);
  begin perform media_review_comment('numeiro', v2, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não comenta (42501)', true, st = '42501');

  -- outro cliente não vê nada de A, nem trocando o cliente nem o ID
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não lista vídeos de A (42501)', true, st = '42501');
  begin perform media_review_detail('ws_mr_b', (a1->>'id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não abre vídeo de A pelo seu cliente (P0002)', true, st = 'P0002');
  begin perform media_review_comment('ws_mr_b', v2, 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não comenta versão de A pelo seu cliente (P0002)', true, st = 'P0002');
  begin perform media_review_decide('ws_mr_b', v2, 'rejected', 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não decide versão de A (P0002)', true, st = 'P0002');
  ab := media_link_add('ws_mr_b', null, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid1 || '/view', 'title', 'B', 'content_id', gb,
          'tags', jsonb_build_array('hook_1')));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := media_review_list('ws_mr_b');
  insert into t values ('agência com acesso a B vê B', true, jsonb_array_length(j->'items') = 1);
  begin perform media_review_list('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('agência sem acesso a A não vê A (42501)', true, st = '42501');

  -- imutabilidade e tabelas fechadas
  execute 'reset role';
  begin delete from media_comments where id = (c1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários não se apagam (42501)', true, st = '42501');
  begin update media_comments set body = 'x' where id = (c1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários não se reescrevem (42501)', true, st = '42501');
  begin update media_decisions set reason = 'x' where version_id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('decisões não se alteram (42501)', true, st = '42501');
  begin update media_reviews set status = 'rejected' where version_id = v2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aprovação não se desfaz por baixo (22023)', true, st = '22023');
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.media_reviews', 'select') and not has_table_privilege('anon', 'public.media_comments', 'select'));
  insert into t values ('decisão auditada', true, exists (select 1 from audit_events where action = 'media.review.decided' and entity_id = a1->>'id'));

  -- código de equipa não chega à revisão de vídeo (sessão individual)
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform media_review_list('numeiro', '{}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa recusado', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
