-- supabase/tests/w5_media_review_notif.sql : notificações da revisão de vídeo (W5-05, FR-05-04; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_own uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  gid text := 'numeiro-2026-10-28-07'; fid text := '1AbCdEfGhIjKlMnOpQrStUvWx';
  a1 jsonb; v1 uuid; c1 jsonb; c2 jsonb; j jsonb; q jsonb; st text; n int; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_mn_b', 'Notif B', 'mnb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_con,'mn-con@test.invalid'),(u_rev,'mn-rev@test.invalid'),(u_own,'mn-own@test.invalid'),(u_b,'mn-b@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_con, 'client_staff', 'contributor'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('numeiro', u_own, 'client_staff', 'manager'), ('ws_mn_b', u_b, 'client_staff', 'workspace_admin');
  update guioes set owner_id = u_own where id = gid;
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('notifications.prefs', org, 'numeiro', 'all'), ('ops.workspace', org, 'numeiro', 'all');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- colaborador regista o vídeo; o revisor comenta num momento
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  a1 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/' || fid || '/view', 'title', 'g07_hook1_S15.mp4',
          'tags', jsonb_build_array('hook_1', 'S15'), 'content_id', gid));
  v1 := (a1->'current'->>'id')::uuid;
  c1 := media_review_comment('numeiro', v1, 'Vou rever o corte.', null);
  execute 'reset role';
  insert into t values ('o próprio comentário não notifica quem comenta', true,
    not exists (select 1 from notifications where user_id = u_con and kind = 'video_comment'));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  c2 := media_review_comment('numeiro', v1, 'Aos 0:23 o corte salta.', 83000);
  perform media_review_comment('numeiro', v1, 'Concordo.', null, (c1->>'id')::uuid);
  execute 'reset role';
  insert into t values ('comentário avisa quem registou, com o momento', true,
    exists (select 1 from notifications where user_id = u_con and kind = 'video_comment' and entity_type = 'media_asset'
            and entity_id = a1->>'id' and title like 'Comentário em g07_hook1_S15.mp4 aos 1:23' and body like '%: Aos 0:23 o corte salta.'));
  insert into t values ('resposta avisa o autor do comentário como resposta', true,
    exists (select 1 from notifications where user_id = u_con and kind = 'video_comment' and title like 'Resposta ao teu comentário em %'));
  insert into t values ('uma notificação por comentário e pessoa', true,
    (select count(*) from notifications where user_id = u_con and kind = 'video_comment') = 2);
  insert into t values ('quem comenta não se avisa', true, not exists (select 1 from notifications where user_id = u_rev));
  insert into t values ('responsável do guião não recebe comentários', true,
    not exists (select 1 from notifications where user_id = u_own and kind = 'video_comment'));

  -- pedir alterações: colaborador e responsável do guião recebem, com o motivo
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  perform media_review_decide('numeiro', v1, 'changes_requested', 'Corte aos 0:23.');
  perform media_review_decide('numeiro', v1, 'changes_requested', 'Corte aos 0:23.');   -- repetir não decide outra vez
  execute 'reset role';
  insert into t values ('decisão avisa quem registou e o responsável, com motivo', true,
    (select count(distinct user_id) from notifications where kind = 'video_decision' and entity_id = a1->>'id'
      and title like 'Pedem alterações no vídeo: g07_hook1_S15.mp4 (v1)' and body like '% · Corte aos 0:23.' and user_id in (u_con, u_own)) = 2);
  insert into t values ('repetir a decisão não duplica', true,
    (select count(*) from notifications where kind = 'video_decision' and user_id = u_con) = 1);
  insert into t values ('quem decide não se avisa', true, not exists (select 1 from notifications where user_id = u_rev));

  -- preferência pessoal desligada: não cria, regista a supressão; outro cliente não recebe nada
  insert into notification_user_prefs (user_id, workspace_id, kind, channel, enabled) values (u_own, 'numeiro', 'video_decision', 'in_app', false);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  perform media_review_decide('numeiro', v1, 'approved');
  execute 'reset role';
  insert into t values ('aprovação avisa o colaborador', true,
    exists (select 1 from notifications where user_id = u_con and kind = 'video_decision' and title like 'Vídeo aprovado: %'));
  insert into t values ('preferência desligada suprime e regista', true,
    (select count(*) from notifications where user_id = u_own and kind = 'video_decision') = 1
    and exists (select 1 from notification_suppressions where user_id = u_own and kind = 'video_decision' and reason = 'user_off'));
  insert into t values ('outro cliente não recebe', true, not exists (select 1 from notifications where user_id = u_b));
  insert into t values ('tipos no catálogo de preferências', true,
    (select count(*) from notification_event_defs where kind in ('video_decision', 'video_comment') and not mandatory) = 2);

  -- caixa: um item por vídeo que abre a revisão do vídeo; comentários contam como menção
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  q := my_queue('numeiro');
  execute 'reset role';
  select x into j from jsonb_array_elements(q->'items') x where x->>'key' = 'media_asset:' || (a1->>'id');
  insert into t values ('caixa abre o vídeo na revisão', true, j->>'href' = '/revisao?ver=videos&asset=' || (a1->>'id'));
  insert into t values ('comentário de vídeo é menção', true, j->'categories' ? 'mention');

  -- o aviso nunca desfaz a decisão: com _notify a falhar a decisão fica
  execute 'reset role';
  alter table notifications add constraint tmp_block check (kind <> 'video_comment') not valid;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform media_review_comment('numeiro', v1, 'Mais um.'); st := 'ok'; exception when others then st := sqlstate; end;
  execute 'reset role';
  alter table notifications drop constraint tmp_block;
  insert into t values ('falha do aviso não falha o comentário', true,
    st = 'ok' and exists (select 1 from media_comments where version_id = v1 and body = 'Mais um.'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
