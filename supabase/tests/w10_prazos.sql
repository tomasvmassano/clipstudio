-- supabase/tests/w10_prazos.sql : notificações de prazos e alterações (FR-11-04, TEAM-12; ADR-0061). Rollback no fim (raise).
-- Prova: limiares 24 h e atraso (uma vez por limiar e por valor de due_at), tick repetido sem duplicados, mudar o prazo volta
-- a avisar, mudança de prazo avisa o responsável (não quem muda), preferências desligadas não criam (exceto obrigatório no
-- cliente) e não contam duas vezes, membro removido nada, flag por quem recebe, isolamento entre clientes, guiões por aprovar
-- com gravação amanhã no fuso do cliente (fronteira de fuso), revisões de vídeo atrasadas pela regra do calendário.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  pa_mgr uuid := gen_random_uuid(); pa_con uuid := gen_random_uuid(); pa_view uuid := gen_random_uuid(); pa_rm uuid := gen_random_uuid();
  pa_off uuid := gen_random_uuid(); pb_adm uuid := gen_random_uuid(); ag uuid := gen_random_uuid(); pc_con uuid := gen_random_uuid();
  t1 uuid; t2 uuid; t3 uuid; t4 uuid; t5 uuid; t6 uuid; t7 uuid; t8 uuid; t9 uuid; tb uuid; tc uuid; tr uuid;
  j jsonb; n1 int; n2 int; ok int := 0; bad int := 0; res text := ''; r record;
  p_tz timestamptz := (date_trunc('day', now() at time zone 'UTC') + interval '21 hours') at time zone 'UTC';   -- 21:00 UTC = 01:00 do dia seguinte no Dubai
  d_utc date := (date_trunc('day', now() at time zone 'UTC'))::date;
  dub_today date := (now() at time zone 'Asia/Dubai')::date;
  a1 jsonb; a2 jsonb; a3 jsonb;
begin
  insert into clients (id, name, handle, organization_id, timezone) values
    ('pz_a', 'Prazos A', 'pza', org, 'Asia/Dubai'), ('pz_b', 'Prazos B', 'pzb', org, 'Europe/Lisbon'), ('pz_c', 'Prazos C', 'pzc', org, 'UTC');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (pa_mgr,'pz-mgr@test.invalid'),(pa_con,'pz-con@test.invalid'),(pa_view,'pz-view@test.invalid'),(pa_rm,'pz-rm@test.invalid'),
    (pa_off,'pz-off@test.invalid'),(pb_adm,'pz-b@test.invalid'),(ag,'pz-ag@test.invalid'),(pc_con,'pz-c@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('pz_a', pa_mgr, 'client_staff', 'manager'), ('pz_a', pa_con, 'client_staff', 'contributor'), ('pz_a', pa_view, 'client_staff', 'viewer'),
    ('pz_a', pa_rm, 'client_staff', 'manager'), ('pz_a', pa_off, 'client_staff', 'contributor'), ('pz_b', pb_adm, 'client_staff', 'workspace_admin'),
    ('pz_a', ag, 'agency_staff', 'manager'), ('pz_c', pc_con, 'client_staff', 'contributor');
  -- flag ligada para todos em A e B; C fica na predefinição (só o dono da agência)
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['notifications.deadlines', 'notifications.prefs', 'media.library']) k, unnest(array['pz_a', 'pz_b']) w;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- ═════ catálogo ═════
  insert into t values ('5 tipos novos no catálogo e no check, grupo prazos, nenhum obrigatório', true,
    (select count(*) from notification_event_defs where group_key = 'prazos' and not mandatory
       and kind in ('task_due_soon','task_overdue','task_due_changed','script_unapproved_recording','video_review_overdue')) = 5
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'notifications_kind_check') like '%video_review_overdue%'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'notifications_kind_check') like '%video_comment%');
  insert into t values ('flag registada só para o dono da agência', true,
    (select default_stage from feature_flag_defs where key = 'notifications.deadlines') = 'owner');
  insert into t values ('tick agendado de 15 em 15 minutos', true,
    exists (select 1 from cron.job where jobname = 'deadline-notify-tick' and schedule = '*/15 * * * *'));
  insert into t values ('caixa: avisos de prazo são alertas, mudança de prazo é tarefa', true,
    _ops_category('task_overdue') = 'alert' and _ops_category('task_due_soon') = 'alert' and _ops_category('video_review_overdue') = 'alert'
    and _ops_category('script_unapproved_recording') = 'alert' and _ops_category('task_due_changed') = 'task'
    and _ops_category('overdue') = 'alert' and _ops_category('video_comment') = 'mention');

  -- ═════ (a) tarefas ═════
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T1 em 3 horas', pa_con, now() + interval '3 hours', 'todo', 'system') returning id into t1;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T2 atrasada', pa_con, now() - interval '2 hours', 'doing', 'system') returning id into t2;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T3 em 30 horas', pa_con, now() + interval '30 hours', 'todo', 'system') returning id into t3;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T4 atrasada há 10 dias', pa_con, now() - interval '10 days', 'todo', 'system') returning id into t4;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T5 feita', pa_con, now() + interval '1 hour', 'done', 'system') returning id into t5;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T6 de quem saiu', pa_rm, now() + interval '2 hours', 'todo', 'system') returning id into t6;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T7 pref desligada', pa_off, now() + interval '2 hours', 'todo', 'system') returning id into t7;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T8 obrigatória no cliente', pa_off, now() - interval '1 hour', 'todo', 'system') returning id into t8;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T9 do manager', pa_mgr, now() + interval '40 hours', 'todo', 'system') returning id into t9;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'TR sem prazo', pa_con, null, 'todo', 'system') returning id into tr;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_b', 'TB de B', pb_adm, now() + interval '2 hours', 'todo', 'system') returning id into tb;
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_c', 'TC sem flag', pc_con, now() + interval '2 hours', 'todo', 'system') returning id into tc;
  update workspace_access set status = 'removed' where workspace_id = 'pz_a' and user_id = pa_rm;
  insert into notification_user_prefs (user_id, workspace_id, kind, channel, enabled) values
    (pa_off, 'pz_a', 'task_due_soon', 'in_app', false), (pa_off, 'pz_a', 'task_overdue', 'in_app', false);
  insert into notification_ws_prefs (workspace_id, kind, channel, enabled, required) values ('pz_a', 'task_overdue', 'in_app', true, true);

  perform set_config('request.jwt.claims', '', true);
  j := deadline_notify_tick();
  insert into t values ('tick devolve contagens', true, (j->>'task_due_soon')::int >= 2 and (j->>'task_overdue')::int >= 2);
  insert into t values ('24 h: o responsável recebe um aviso', true,
    (select count(*) from notifications where user_id = pa_con and kind = 'task_due_soon' and entity_id = t1::text) = 1);
  insert into t values ('atrasada: o responsável recebe um aviso, com o prazo no fuso do cliente', true,
    (select count(*) from notifications where user_id = pa_con and kind = 'task_overdue' and entity_id = t2::text
       and body like '%(Asia/Dubai)%' and title like 'Tarefa atrasada:%') = 1);
  insert into t values ('fora das 24 h, atrasada há mais de 7 dias, feita: nada', true,
    not exists (select 1 from notifications where entity_id in (t3::text, t4::text, t5::text, t9::text, tr::text)));
  insert into t values ('membro removido não recebe nem fica registado', true,
    not exists (select 1 from notifications where user_id = pa_rm) and not exists (select 1 from notification_deadline_sent where user_id = pa_rm));
  insert into t values ('preferência desligada: não cria, regista como não entregue e conta 1 supressão', true,
    not exists (select 1 from notifications where entity_id = t7::text)
    and exists (select 1 from notification_deadline_sent where user_id = pa_off and kind = 'task_due_soon' and not delivered)
    and (select sum(n) from notification_suppressions where user_id = pa_off and kind = 'task_due_soon') = 1);
  insert into t values ('obrigatória no cliente vence a preferência pessoal', true,
    (select count(*) from notifications where user_id = pa_off and kind = 'task_overdue' and entity_id = t8::text) = 1);
  insert into t values ('flag desligada para quem recebe (cliente C): nada', true,
    not exists (select 1 from notifications where workspace_id = 'pz_c') and not exists (select 1 from notification_deadline_sent where workspace_id = 'pz_c'));
  insert into t values ('cliente B: avisa o seu responsável', true,
    (select count(*) from notifications where user_id = pb_adm and entity_id = tb::text and workspace_id = 'pz_b') = 1);

  select count(*) into n1 from notifications where workspace_id in ('pz_a','pz_b','pz_c');
  perform deadline_notify_tick();
  perform deadline_notify_tick();
  select count(*) into n2 from notifications where workspace_id in ('pz_a','pz_b','pz_c');
  insert into t values ('tick repetido: sem duplicados', true, n1 = n2 and n1 > 0);
  insert into t values ('tick repetido: supressões não contam duas vezes', true,
    (select sum(n) from notification_suppressions where user_id = pa_off and kind = 'task_due_soon') = 1);
  -- simula a mesma pessoa com dois avisos suprimidos alternados: o registo impede contar de novo
  insert into tasks (workspace_id, title, assignee_id, due_at, status, created_kind) values ('pz_a', 'T7b', pa_off, now() + interval '4 hours', 'todo', 'system');
  perform deadline_notify_tick(); perform deadline_notify_tick();
  insert into t values ('duas tarefas suprimidas: 2 supressões, não mais', true,
    (select sum(n) from notification_suppressions where user_id = pa_off and kind = 'task_due_soon') = 2);

  -- ═════ (d) mudança de prazo e de responsável ═════
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pa_mgr, 'role','authenticated')::text, true);
  perform task_update(t1, jsonb_build_object('due_at', now() + interval '5 hours'));
  perform task_update(t9, jsonb_build_object('due_at', now() + interval '50 hours'));
  perform task_update(tr, jsonb_build_object('title', 'TR sem prazo, título novo'));
  perform task_update(t3, jsonb_build_object('due_at', null));
  perform task_update(t2, jsonb_build_object('assignee_id', ag, 'due_at', now() + interval '6 hours'));
  execute 'reset role';
  insert into t values ('mudar o prazo avisa o responsável, com o novo e o antigo', true,
    (select count(*) from notifications where user_id = pa_con and kind = 'task_due_changed' and entity_id = t1::text
       and body like 'Novo prazo:%(era%') = 1);
  insert into t values ('quem muda o prazo da própria tarefa não se avisa', true,
    not exists (select 1 from notifications where kind = 'task_due_changed' and entity_id = t9::text));
  insert into t values ('mudar outro campo não avisa prazo', true,
    not exists (select 1 from notifications where kind = 'task_due_changed' and entity_id = tr::text));
  insert into t values ('tirar o prazo avisa "sem prazo"', true,
    exists (select 1 from notifications where user_id = pa_con and kind = 'task_due_changed' and entity_id = t3::text and body = 'A tarefa ficou sem prazo.'));
  insert into t values ('mudar responsável e prazo juntos: atribuição ao novo e aviso ao antigo, sem aviso de prazo repetido', true,
    exists (select 1 from notifications where user_id = ag and kind = 'task_assigned' and entity_id = t2::text)
    and exists (select 1 from notifications where user_id = pa_con and kind = 'task_unassigned' and entity_id = t2::text)
    and not exists (select 1 from notifications where kind = 'task_due_changed' and entity_id = t2::text));
  perform set_config('request.jwt.claims', '', true);
  perform deadline_notify_tick();
  insert into t values ('novo prazo volta a armar o aviso de 24 h (uma vez)', true,
    (select count(*) from notifications where user_id = pa_con and kind = 'task_due_soon' and entity_id = t1::text) = 2);
  insert into t values ('tarefa passada a outra pessoa: o novo responsável recebe o limiar do novo prazo', true,
    (select count(*) from notifications where user_id = ag and kind = 'task_due_soon' and entity_id = t2::text) = 1);
  perform deadline_notify_tick();
  insert into t values ('e não repete', true,
    (select count(*) from notifications where user_id = pa_con and kind = 'task_due_soon' and entity_id = t1::text) = 2);

  -- ═════ (b) guiões por aprovar com gravação amanhã (fronteira de fuso) ═════
  -- p_tz = hoje 21:00 UTC: no Dubai já é amanhã 01:00 (o "amanhã" do Dubai é d_utc + 2); em Lisboa o "amanhã" é d_utc + 1
  insert into guioes (id, client_id, date, n, hooks, corpo, owner_id) values
    ('pz_a-g1', 'pz_a', d_utc + 2, 1, '[]', 'corpo', pa_con),
    ('pz_a-g2', 'pz_a', d_utc + 1, 2, '[]', 'corpo', pa_con),
    ('pz_a-g3', 'pz_a', d_utc + 2, 3, '[]', 'corpo', pa_con),
    ('pz_a-g4', 'pz_a', d_utc + 2, 4, '[]', 'corpo', pa_con),
    ('pz_b-g1', 'pz_b', d_utc + 1, 1, '[]', 'corpo', null),
    ('pz_b-g2', 'pz_b', d_utc + 2, 2, '[]', 'corpo', null);
  update guioes set editorial_status = 'approved' where id = 'pz_a-g3';
  update guioes set production_status = 'recorded' where id = 'pz_a-g4';
  perform deadline_notify_tick(p_tz);
  insert into t values ('Dubai: guião de amanhã (local) avisa responsável, manager e staff da agência', true,
    (select array_agg(user_id order by user_id) from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_a-g1')
      = (select array_agg(x order by x) from unnest(array[pa_con, pa_mgr, ag]) x));
  insert into t values ('Dubai: guião de hoje local (amanhã em UTC) não avisa', true,
    not exists (select 1 from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_a-g2'));
  insert into t values ('aprovado ou já gravado: nada', true,
    not exists (select 1 from notifications where kind = 'script_unapproved_recording' and entity_id in ('pz_a-g3','pz_a-g4')));
  insert into t values ('viewer não aprova: não recebe', true,
    not exists (select 1 from notifications where kind = 'script_unapproved_recording' and user_id = pa_view));
  insert into t values ('Lisboa: amanhã local = amanhã UTC; só a equipa de B', true,
    (select array_agg(user_id) from notifications where kind = 'script_unapproved_recording' and workspace_id = 'pz_b') = array[pb_adm]
    and exists (select 1 from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_b-g1')
    and not exists (select 1 from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_b-g2'));
  select count(*) into n1 from notifications where kind = 'script_unapproved_recording';
  perform deadline_notify_tick(p_tz);
  insert into t values ('guiões: tick repetido sem duplicados', true, n1 = (select count(*) from notifications where kind = 'script_unapproved_recording'));
  update clients set require_approval_to_record = true where id = 'pz_a';
  update guioes set date = d_utc + 3 where id = 'pz_a-g1';
  perform deadline_notify_tick(p_tz + interval '1 day');
  insert into t values ('mudar a data volta a avisar (e diz que só grava aprovados)', true,
    (select count(*) from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_a-g1' and user_id = pa_con) = 2
    and exists (select 1 from notifications where kind = 'script_unapproved_recording' and entity_id = 'pz_a-g1' and body like 'Este cliente só grava%'));

  -- ═════ (c) revisões de vídeo atrasadas (regra do calendário) ═════
  insert into guioes (id, client_id, date, n, hooks, corpo, owner_id) values
    ('pz_a-r1', 'pz_a', dub_today - 2, 11, '[]', 'corpo', pa_con),
    ('pz_a-r2', 'pz_a', dub_today + 3, 12, '[]', 'corpo', pa_con),
    ('pz_a-r3', 'pz_a', dub_today - 20, 13, '[]', 'corpo', pa_con);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pa_con, 'role','authenticated')::text, true);
  a1 := media_link_add('pz_a', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1PzPzPzPzPzPzPzPzPzPzPzAa/view', 'title', 'r1.mp4', 'content_id', 'pz_a-r1'));
  a2 := media_link_add('pz_a', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1PzPzPzPzPzPzPzPzPzPzPzBb/view', 'title', 'r2.mp4', 'content_id', 'pz_a-r2'));
  a3 := media_link_add('pz_a', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1PzPzPzPzPzPzPzPzPzPzPzCc/view', 'title', 'r3.mp4', 'content_id', 'pz_a-r3'));
  execute 'reset role';
  insert into tasks (workspace_id, title, kind, assignee_id, due_at, status, content_id, created_kind)
  values ('pz_a', 'Rever r2', 'review', pa_con, now() - interval '2 days', 'todo', 'pz_a-r2', 'system');
  perform set_config('request.jwt.claims', '', true);
  perform deadline_notify_tick();
  insert into t values ('vídeo sem tarefa, dia do guião passado: avisa quem decide (não quem registou)', true,
    (select array_agg(user_id order by user_id) from notifications where kind = 'video_review_overdue' and entity_id = a1->>'id')
      = (select array_agg(x order by x) from unnest(array[pa_mgr, ag]) x));
  insert into t values ('vídeo com tarefa atrasada: avisa o responsável da tarefa e quem decide', true,
    (select array_agg(user_id order by user_id) from notifications where kind = 'video_review_overdue' and entity_id = a2->>'id')
      = (select array_agg(x order by x) from unnest(array[pa_con, pa_mgr, ag]) x));
  insert into t values ('atrasado há mais de 7 dias: nada', true,
    not exists (select 1 from notifications where kind = 'video_review_overdue' and entity_id = a3->>'id'));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pa_mgr, 'role','authenticated')::text, true);
  perform media_review_decide('pz_a', (a1->'current'->>'id')::uuid, 'changes_requested', 'Cortar o início');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform deadline_notify_tick(); perform deadline_notify_tick();
  insert into t values ('alterações pedidas: avisa quem registou, uma vez, sem repetir quem decide', true,
    (select count(*) from notifications where kind = 'video_review_overdue' and entity_id = a1->>'id' and user_id = pa_con) = 1
    and (select count(*) from notifications where kind = 'video_review_overdue' and entity_id = a1->>'id' and user_id = pa_mgr) = 1);

  -- ═════ isolamento ═════
  insert into t values ('nenhuma notificação de A para quem não está ativo em A', true,
    not exists (select 1 from notifications n where n.workspace_id = 'pz_a'
                 and not exists (select 1 from workspace_access a where a.workspace_id = 'pz_a' and a.user_id = n.user_id and a.status = 'active')));
  insert into t values ('B só recebe de B; a agência não recebe de B sem atribuição', true,
    not exists (select 1 from notifications where user_id = pb_adm and workspace_id <> 'pz_b')
    and not exists (select 1 from notifications where user_id = ag and workspace_id <> 'pz_a'));
  insert into t values ('tick, envio e registo fechados à API', true,
    not has_function_privilege('authenticated', 'public.deadline_notify_tick(timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.deadline_notify_tick(timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public._deadline_send(uuid,text,text,text,text,text,text,text,text)', 'execute')
    and not has_table_privilege('authenticated', 'public.notification_deadline_sent', 'select')
    and (select relrowsecurity from pg_class where oid = 'public.notification_deadline_sent'::regclass));
  insert into t values ('funções novas com search_path fixo', true,
    not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('_deadline_send','_deadline_fmt','deadline_notify_tick','tasks_due_changed_notify')
                 and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
