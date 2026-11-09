-- supabase/tests/w10_comentarios.sql : Comentários como fonte de ideias (W10-26, REACT-08; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_den uuid := gen_random_uuid();
  j jsonb; st text; c1 bigint; c2 bigint; g1 text; g2 text;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_cm_b', 'Comentários B', 'cmb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'cm-adm@test.invalid'),(u_con,'cm-con@test.invalid'),(u_rev,'cm-rev@test.invalid'),(u_b,'cm-b@test.invalid'),(u_den,'cm-den@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_rev, 'client_staff', 'reviewer'), ('numeiro', u_den, 'client_staff', 'manager'), ('ws_cm_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('numeiro', u_den, 'reacts.read', 'deny', 'teste: negação explícita');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  -- flag desligada: 55000
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform comments_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: 55000', true, st = '55000');
  begin perform worker_comment_context('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sessão não chama RPC do agente (42501)', true, st = '42501');
  begin perform count(*) from comment_ideas; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tabela fechada à API (42501)', true, st = '42501');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('reacts.radar', org, 'numeiro', 'all'), ('reacts.radar', org, 'ws_cm_b', 'all');

  -- o agente cria ideias
  execute 'set local role engine_worker';
  j := worker_comment_upsert('numeiro', jsonb_build_object('comment_key', 'instagram:18000000000000001', 'reel_url', 'https://www.instagram.com/reel/DfXsMW9hFeH/',
        'reel_account', 'itsnumeiro', 'author', 'fulano.x', 'text', 'Isto é tudo mentira, trabalhar por conta de outrem é o mais seguro.', 'likes', 120, 'replies', 14,
        'kind', 'discorda', 'ai', jsonb_build_object('score', 82, 'risk_level', 'baixo', 'ideia', 'O emprego seguro não existe', 'angulo', 'Segurança é ilusão',
           'hooks', jsonb_build_array(jsonb_build_object('text', 'Disseram-me que o emprego é seguro.', 'mecanismo', 'contradição')), 'resposta', 'Resposta de teste.')));
  c1 := (j->>'id')::bigint;
  j := worker_comment_upsert('numeiro', jsonb_build_object('comment_key', 'instagram:18000000000000002', 'text', 'Concordo, e acrescento os impostos.', 'kind', 'concorda',
        'ai', jsonb_build_object('score', 60)));
  c2 := (j->>'id')::bigint;
  j := worker_comment_upsert('numeiro', jsonb_build_object('comment_key', 'instagram:18000000000000001', 'text', 'Isto é tudo mentira.', 'likes', 300));
  execute 'reset role';
  insert into t values ('repetido não duplica e atualiza os gostos', true,
    (j->>'id')::bigint = c1 and (select count(*) from comment_ideas where workspace_id = 'numeiro') = 2 and (select likes from comment_ideas where id = c1) = 300);
  insert into t values ('reel_ref_key derivada do link', true, (select reel_ref_key from comment_ideas where id = c1) = 'instagram:DfXsMW9hFeH');
  begin insert into comment_ideas (workspace_id, comment_key, text, kind) values ('numeiro', 'instagram:x1x', 'a', 'insulto'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tipo inválido rejeitado (23514)', true, st = '23514');

  -- leitura
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := comments_list('numeiro', 'open');
  insert into t values ('fila ordenada pela nota, com contagens e tipos', true,
    (j->'items'->0->>'id')::bigint = c1 and (j->'counts'->>'open')::int = 2 and (j->'kinds'->>'discorda')::int = 1 and (j->'can'->>'decide')::boolean);
  j := comments_list('numeiro', 'open', 'concorda');
  insert into t values ('filtro por tipo', true, jsonb_array_length(j->'items') = 1 and (j->'items'->0->>'id')::bigint = c2);
  begin perform comments_list('numeiro', 'xpto'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('separador inválido: 22023', true, st = '22023');
  begin perform comments_list('numeiro', 'open', 'insulto'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tipo inválido no filtro: 22023', true, st = '22023');

  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform comments_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não vê (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_den, 'role','authenticated')::text, true);
  begin perform comments_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('negação explícita não vê (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform comments_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não vê a fila (42501)', true, st = '42501');
  begin perform comment_decide(c1, 'save'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não decide (42501)', true, st = '42501');
  begin perform comment_record(c1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não grava (42501)', true, st = '42501');
  j := comments_list('ws_cm_b', 'open');
  insert into t values ('fila de B vazia (sem fuga de A)', true, jsonb_array_length(j->'items') = 0 and (j->'counts'->>'open')::int = 0);

  -- decisões (colaborador)
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform comment_decide(c2, 'reject'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('rejeitar sem motivo: 22023', true, st = '22023');
  j := comment_decide(c2, 'reject', 'fraco', 2, 'pouco a dizer');
  insert into t values ('rejeitar com motivo', true, j->>'status' = 'rejected' and j->>'reject_reason' = 'fraco' and (j->>'rating')::int = 2);
  j := comment_decide(c2, 'reopen');
  insert into t values ('reabrir', true, j->>'status' = 'open' and j->>'reject_reason' is null);
  j := comment_decide(c2, 'save', null, 4);
  insert into t values ('guardar', true, j->>'status' = 'saved' and (j->>'rating')::int = 4);
  begin j := comment_record(c1); g1 := j->>'content_id'; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravar cria guião rascunho, sem o nome de quem comentou', true,
    st = 'ok' and exists (select 1 from guioes where id = g1 and client_id = 'numeiro' and formato = 'resposta_comentario' and editorial_status = 'draft'
                          and hooks->0->>'text' = 'Disseram-me que o emprego é seguro.' and corpo = 'Resposta de teste.'
                          and position('fulano.x' in coalesce(notas, '') || coalesce(tema, '')) = 0));
  j := comment_record(c1); g2 := j->>'content_id';
  insert into t values ('gravar outra vez é idempotente', true, g2 = g1 and not (j->>'created')::boolean);
  begin perform comment_decide(c1, 'reject', 'risco'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravado não se rejeita (55000)', true, st = '55000');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  -- o agente nunca desfaz decisões humanas
  execute 'set local role engine_worker';
  j := worker_comment_upsert('numeiro', jsonb_build_object('comment_key', 'instagram:18000000000000002', 'text', 'x', 'ai', jsonb_build_object('score', 95)));
  st := j->>'status';
  j := worker_comment_context('numeiro');
  execute 'reset role';
  insert into t values ('agente atualiza a nota mas não o estado', true, st = 'saved' and (select score from comment_ideas where id = c2) = 95);
  insert into t values ('contexto traz vistos, decisões e conta do cliente', true,
    jsonb_array_length(j->'seen') = 2 and jsonb_array_length(j->'decisions') >= 2 and j->'accounts' ? 'itsnumeiro');
  insert into t values ('decisões auditadas', true,
    (select count(*) from audit_events where entity_type = 'comment_idea' and action in ('comment.reject', 'comment.save', 'comment.reopen', 'comment.record')) >= 4);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
