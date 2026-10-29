-- supabase/tests/w2_review_comments.sql : comentários contextuais e caixa de revisão (W2-06; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := 'numeiro-2026-10-28-07'; gid2 text := 'numeiro-2026-10-28-08'; gb text := 'ws_rc_b-1';
  c1 jsonb; c2 jsonb; c3 jsonb; j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; tid uuid;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_rc_b', 'Revisão B', 'rcb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_rc_b', current_date, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo secreto B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'rc-con@test.invalid'),(u_rev,'rc-rev@test.invalid'),(u_view,'rc-view@test.invalid'),(u_b,'rc-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_view, 'client_staff', 'viewer'), ('ws_rc_b', u_b, 'client_staff', 'workspace_admin');
  insert into tasks (workspace_id, title, kind, priority, assignee_id, due_at, content_id, created_kind)
  values ('numeiro', 'Rever guião 7', 'review', 'urgent', u_rev, now() - interval '1 day', gid, 'system') returning id into tid;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- colaborador comenta uma frase do corpo e menciona o revisor
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  c1 := content_comment_add(gid, 'corpo', 'Esta frase está fraca, troca por uma cena concreta.', 'A seguinte tem menos roupa.', array[u_rev]);
  insert into t values ('comentário num bloco com a frase citada', true, c1->>'block' = 'corpo' and c1->>'quote' = 'A seguinte tem menos roupa.' and (c1->>'on_current')::boolean);
  c2 := content_comment_add(gid, 'hook_2', 'O hook 2 precisa de sujeito concreto.');
  begin perform content_comment_add(gid, 'hook_9', 'não existe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('hook que não existe (22023)', true, st = '22023');
  begin perform content_comment_add(gid, 'titulo', 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('bloco inválido (22023)', true, st = '22023');
  begin perform content_comment_add(gid, 'corpo', '   '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentário vazio (22023)', true, st = '22023');
  begin perform content_comment_add(gid, 'corpo', 'x', null, array[u_b]); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se menciona quem é de outro cliente (22023)', true, st = '22023');
  begin perform content_comment_add(gb, 'corpo', 'olá B'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não comenta guiões de outro cliente (42501)', true, st = '42501');
  begin perform content_comments(gb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não lê comentários de outro cliente (42501)', true, st = '42501');
  begin perform content_comment_resolve((c2->>'id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('quem escreveu pode resolver o seu', true, st = 'none');

  -- revisor responde, resolve o do colaborador e vê a caixa
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  c3 := content_comment_add(gid, 'geral', 'Concordo, muda isso.', null, '{}', (c1->>'id')::uuid);
  insert into t values ('resposta herda o bloco do comentário', true, c3->>'block' = 'corpo' and c3->>'parent_id' = c1->>'id');
  begin perform content_comment_add(gid, 'geral', 'x', null, '{}', (c3->>'id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não se responde a uma resposta (22023)', true, st = '22023');
  j := review_inbox('numeiro', '{"assignee":"me"}');
  insert into t values ('caixa: "atribuídos a mim" traz o guião com a tarefa', true,
    jsonb_array_length(j->'items') = 1 and j->'items'->0->'guiao'->>'id' = gid and j->'items'->0->'task'->>'priority' = 'urgent'
    and (j->'items'->0->>'open_comments')::int = 1);
  j := review_inbox('numeiro', '{"due":"overdue"}');
  insert into t values ('caixa: atrasados', true, exists (select 1 from jsonb_array_elements(j->'items') x where x->'guiao'->>'id' = gid));
  j := review_inbox('numeiro', '{"priority":"urgent"}');
  insert into t values ('caixa: por prioridade', true, jsonb_array_length(j->'items') = 1);
  j := review_inbox('numeiro', '{"q":"tema de teste 8"}');
  insert into t values ('caixa: pesquisa no tema', true, exists (select 1 from jsonb_array_elements(j->'items') x where x->'guiao'->>'id' = gid2));
  j := review_inbox('numeiro', '{}');
  insert into t values ('caixa: urgente primeiro e contagens por estado', true, j->'items'->0->'guiao'->>'id' = gid and (j->'counts'->>'in_review')::int >= 1
    and not exists (select 1 from jsonb_array_elements(j->'items') x where x->'guiao'->>'client_id' <> 'numeiro'));
  begin perform review_inbox('numeiro', '{"status":["publicado"]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('filtro inválido (22023)', true, st = '22023');
  begin perform review_inbox('ws_rc_b', '{}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('caixa de outro cliente (42501)', true, st = '42501');
  j := content_comment_resolve((c1->>'id')::uuid);
  insert into t values ('revisor resolve', true, j->>'resolved_at' is not null and j->>'resolved_by' = 'rc-rev@test.invalid');
  j := content_comment_resolve((c1->>'id')::uuid, false);
  insert into t values ('e reabre', true, j->>'resolved_at' is null);
  j := content_comments(gid);
  insert into t values ('lista com respostas e permissões', true, jsonb_array_length(j->'comments') = 3 and (j #>> '{can,comment}')::boolean and (j #>> '{can,resolve}')::boolean);

  -- leitor vê mas não comenta nem resolve
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  j := content_comments(gid);
  insert into t values ('leitor lê os comentários', true, jsonb_array_length(j->'comments') = 3 and not (j #>> '{can,comment}')::boolean);
  begin perform content_comment_add(gid, 'corpo', 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não comenta (42501)', true, st = '42501');
  begin perform content_comment_resolve((c1->>'id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não resolve (42501)', true, st = '42501');
  execute 'reset role';

  -- notificações, histórico, imutabilidade
  insert into t values ('menção notifica o revisor', true, exists (select 1 from notifications where user_id = u_rev and kind = 'script_mention'));
  insert into t values ('resposta notifica quem escreveu', true, exists (select 1 from notifications where user_id = u_con and kind = 'script_comment'));
  insert into t values ('eventos na outbox', true, (select count(*) from domain_events where entity_id = gid and type like 'script.comment%') >= 5);
  begin update content_comments set body = 'reescrito' where id = (c1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários não se reescrevem (42501)', true, st = '42501');
  begin delete from content_comments where id = (c1->>'id')::uuid; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('comentários não se apagam (42501)', true, st = '42501');
  insert into t values ('tabela fechada a leitura direta', true, not has_table_privilege('authenticated', 'public.content_comments', 'select'));

  -- nova versão: o comentário fica marcado como de uma versão anterior
  update guioes set corpo = corpo || ' (revisto)' where id = gid;
  perform public._content_snapshot(gid, '{"kind":"engine","uid":null,"label":"teste"}', 'teste');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  insert into t values ('comentário antigo marcado de versão anterior', true,
    exists (select 1 from jsonb_array_elements(content_comments(gid)->'comments') x where x->>'id' = c1->>'id' and not (x->>'on_current')::boolean));

  -- código de equipa do Numeiro comenta
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'reset role'; execute 'set local role anon';
  j := content_comment_add(gid, 'cta', 'Pelo código de equipa', null, '{}', null, tok);
  insert into t values ('código de equipa comenta', true, j->>'author_kind' = 'legacy_code');
  begin perform content_comment_add(gb, 'corpo', 'x', null, '{}', null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não comenta em B (42501)', true, st = '42501');
  begin perform content_comments(gid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem código recusado', true, st in ('42501', '28000'));
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
