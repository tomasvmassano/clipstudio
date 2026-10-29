-- supabase/tests/w6_ops.sql : minha área de trabalho, fila deduplicada, ver/adiar/passar, presença e quem trabalha em quê
-- (FR-01-03, FR-17-01, OPS-02, OPS-03, OPS-04, OPS-10). Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cc uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  u_rm uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date; j jsonb; q jsonb; it jsonb; st text; det text; ok int := 0; bad int := 0; res text := ''; r record;
  t1 uuid; t2 uuid; tb uuid; tc uuid; tag uuid; gid text; gapp text; cnt int; ver text;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_ops_b', 'Ops B', 'opsb', org), ('ws_ops_c', 'Ops C', 'opsc', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_ag,'ops-ag@test.invalid'),(u_ca,'ops-ca@test.invalid'),(u_cc,'ops-cc@test.invalid'),(u_cb,'ops-cb@test.invalid'),
    (u_rm,'ops-rm@test.invalid'),(u_vw,'ops-vw@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'), ('ws_ops_b', u_ag, 'agency_staff', 'contributor'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_cc, 'client_staff', 'contributor'),
    ('numeiro', u_rm, 'client_staff', 'contributor'), ('numeiro', u_vw, 'client_staff', 'viewer'),
    ('ws_ops_b', u_cb, 'client_staff', 'workspace_admin');
  insert into profiles (user_id, display_name) values (u_cc, 'Carla Contribui');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select k, org, w, 'all' from unnest(array['ops.workspace','ops.team_presence']) k, unnest(array['numeiro','ws_ops_b','ws_ops_c']) w;
  update guioes set date = d where client_id = 'numeiro';
  gid := (select id from guioes where client_id = 'numeiro' and editorial_status = 'approved' order by n limit 1);
  gapp := (select id from guioes where client_id = 'numeiro' and editorial_status = 'in_review' order by n limit 1);
  update guioes set owner_id = u_cc where id = gid;
  insert into ideas (client_id, kind, titulo, status, ingested_via, created_kind) values ('numeiro', 'talent_request', 'Falar de rendas', 'nova', 'talent', 'user');
  insert into tasks (workspace_id, title, assignee_id, created_kind) values ('ws_ops_b', 'Tarefa do cliente B', u_cb, 'system') returning id into tb;
  insert into tasks (workspace_id, title, created_kind) values ('ws_ops_c', 'Tarefa de C sem dono', 'system') returning id into tc;
  insert into tasks (workspace_id, title, assignee_id, status, created_kind) values ('numeiro', 'Montar o vídeo 3', u_ag, 'doing', 'system') returning id into tag;
  insert into tasks (workspace_id, title, assignee_id, created_kind) values ('ws_ops_b', 'Legendas B', u_ag, 'system');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── admin do cliente A cria tarefa para a colaboradora e menciona-a ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  t1 := (task_create('numeiro', jsonb_build_object('title', 'Rever legendas', 'assignee_id', u_cc, 'priority', 'high'))->>'id')::uuid;
  perform task_comment(t1, 'Vê isto hoje', array[u_cc]);
  t2 := (task_create('numeiro', jsonb_build_object('title', 'Sem dono ainda'))->>'id')::uuid;
  q := my_queue('numeiro');
  insert into t values ('admin vê guiões à espera de aprovação na fila', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'content:' || gapp and x->'categories' ? 'approval'));
  insert into t values ('decisão além de aprovações: tarefa sem responsável', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || t2 and x->>'kind' = 'decision'));
  insert into t values ('decisão além de aprovações: pedido do talento', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'title' like 'Pedido do talento%' and x->'categories' ? 'decision'));
  insert into t values ('fila do cliente A não traz nada de B nem de C', true,
    not exists (select 1 from jsonb_array_elements(q->'items') x where x->>'workspace_id' <> 'numeiro'));

  -- ── colaboradora: deduplicação por evento ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  q := my_queue(null);
  select count(*) into cnt from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || t1;
  insert into t values ('tarefa + notificação de atribuição + menção = um só item', true, cnt = 1);
  it := (select x from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || t1);
  insert into t values ('o item junta as 2 notificações por ler e as razões', true,
    (it->>'unread')::int = 2 and it->'reasons' ? 'assigned' and it->'reasons' ? 'task_mention' and it->'categories' ? 'mention');
  insert into t values ('tarefa nova aparece como não vista, com ações', true,
    not (it->>'seen')::boolean and (it->'can'->>'ack')::boolean and (it->'can'->>'delegate')::boolean and (it->'can'->>'start')::boolean);
  insert into t values ('gravação de hoje do guião de que sou responsável (FR-01-03)', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'content:' || gid and x->'categories' ? 'recording'
            and x->>'href' like '/teleprompter?date=%'));
  insert into t values ('colaboradora não vê a tarefa sem dono (só quem gere)', true,
    not exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || t2));
  insert into t values ('colaboradora não aprova: sem itens de aprovação', true,
    not exists (select 1 from jsonb_array_elements(q->'items') x where x->'categories' ? 'approval'));
  insert into t values ('contadores por tipo', true, (q->'counts'->>'task')::int >= 1 and (q->'counts'->>'recording')::int = 1);
  insert into t values ('flag ligada aparece em enabled', true, q->'enabled' ? 'numeiro');

  -- ── ver (acknowledge): idempotente, auditado, marca lido, não aprova ──
  j := inbox_item_act('task:' || t1, 'ack');
  insert into t values ('ver muda o estado', true, (j->>'changed')::boolean);
  insert into t values ('ver marca as notificações do item como lidas', true,
    not exists (select 1 from notifications where user_id = u_cc and entity_id = t1::text and read_at is null));
  j := inbox_item_act('task:' || t1, 'ack');
  insert into t values ('ver outra vez não muda nada', true, not (j->>'changed')::boolean);
  execute 'reset role';
  insert into t values ('ver fica uma vez no histórico, com antes e depois', true,
    (select count(*) from audit_events where action = 'inbox.ack' and entity_id = 'task:' || t1 and actor_user_id = u_cc
       and before ? 'acknowledged_at' and after->>'acknowledged_at' is not null) = 1);
  insert into t values ('tarefa continua aberta depois de vista', true, (select status from tasks where id = t1) = 'todo');
  execute 'set local role authenticated';
  it := (select x from jsonb_array_elements(my_queue(null)->'items') x where x->>'key' = 'task:' || t1);
  insert into t values ('item visto continua na fila', true, (it->>'seen')::boolean);

  -- ── adiar (snooze) ──
  begin perform inbox_item_act('task:' || t1, 'snooze', now() - interval '1 hour'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('adiar para o passado é recusado (22023)', true, st = '22023');
  begin perform inbox_item_act('task:' || t1, 'snooze', now() + interval '40 days'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('adiar mais de 30 dias é recusado (22023)', true, st = '22023');
  j := inbox_item_act('task:' || t1, 'snooze', date_trunc('minute', now()) + interval '2 hours');
  insert into t values ('adiar muda o estado', true, (j->>'changed')::boolean);
  j := inbox_item_act('task:' || t1, 'snooze', date_trunc('minute', now()) + interval '2 hours');
  insert into t values ('adiar para a mesma hora não muda nada', true, not (j->>'changed')::boolean);
  q := my_queue(null);
  insert into t values ('item adiado sai da fila e vai para adiados', true,
    not exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || t1)
    and exists (select 1 from jsonb_array_elements(q->'snoozed') x where x->>'key' = 'task:' || t1));
  -- notificação nova acorda o item adiado
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  execute 'reset role'; update inbox_item_states set updated_at = now() - interval '1 minute' where user_id = u_cc; execute 'set local role authenticated';
  perform task_comment(t1, 'Ainda falta isto', array[u_cc]);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  it := (select x from jsonb_array_elements(my_queue(null)->'items') x where x->>'key' = 'task:' || t1);
  insert into t values ('menção nova traz o item adiado de volta, como não visto', true, it is not null and not (it->>'seen')::boolean and (it->>'unread')::int = 1);
  j := inbox_item_act('task:' || t1, 'unsnooze');
  insert into t values ('voltar a mostrar limpa o adiamento', true, (j->>'changed')::boolean and j->>'snoozed_until' is null);

  -- ── item de outra pessoa ou de outro cliente ──
  begin perform inbox_item_act('task:' || tb, 'ack'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ver item de tarefa do cliente B não encontra (P0002)', true, st = 'P0002');
  begin perform inbox_item_act('task:' || t2, 'snooze', now() + interval '1 hour'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('adiar item que não é meu não encontra (P0002)', true, st = 'P0002');
  begin perform my_queue('ws_ops_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('fila de outro cliente recusada (42501)', true, st = '42501');
  begin perform my_queue('nao_existe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente inexistente responde igual (42501)', true, st = '42501');

  -- ── delegar ──
  begin perform task_delegate(t1, u_cb); st := 'none'; exception when others then get stacked diagnostics st = returned_sqlstate, det = pg_exception_detail; end;
  insert into t values ('passar a alguém do cliente B é recusado (22023)', true, st = '22023' and det like '%não pode trabalhar%');
  begin perform task_delegate(t1, u_vw); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('passar a um leitor é recusado (22023)', true, st = '22023');
  execute 'reset role'; update tasks set status = 'doing' where id = t1; execute 'set local role authenticated';
  j := task_delegate(t1, u_rm, 'Fico sem tempo hoje');
  insert into t values ('colaboradora passa a sua tarefa', true, (j->>'changed')::boolean and (j->>'assignee_id')::uuid = u_rm);
  insert into t values ('em curso volta a por fazer (quem recebe ainda não começou)', true, j->>'status' = 'todo');
  j := task_delegate(t1, u_rm, 'Fico sem tempo hoje');
  insert into t values ('repetir é idempotente', true, not (j->>'changed')::boolean);
  begin perform task_delegate(t1, u_cc); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('já não é minha: não a posso passar (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('quem recebe é notificado uma só vez', true,
    (select count(*) from notifications where user_id = u_rm and kind = 'task_delegated' and entity_id = t1::text) = 1);
  insert into t values ('passagem no histórico da tarefa e auditoria com antes/depois', true,
    exists (select 1 from task_events where task_id = t1 and action = 'task.delegated' and (before->>'assignee_id')::uuid = u_cc and (after->>'assignee_id')::uuid = u_rm)
    and exists (select 1 from audit_events where entity_id = t1::text and action = 'task.delegated'));
  execute 'set local role authenticated';
  -- gestor (agência) atribui a tarefa sem dono
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := task_delegate(t2, u_cc);
  insert into t values ('gestor atribui tarefa sem dono pela caixa', true, (j->>'assignee_id')::uuid = u_cc);
  -- cliente B não mexe em A
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform task_delegate(t1, u_cb); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não passa tarefas de A (42501)', true, st = '42501');
  insert into t values ('cliente B não vê nada de A na fila', true,
    not exists (select 1 from jsonb_array_elements(my_queue(null)->'items') x where x->>'workspace_id' = 'numeiro'));
  -- flag desligada bloqueia as ações com erro explícito (CAP-09)
  execute 'reset role'; update feature_flags set stage = 'off' where workspace_id = 'ws_ops_b' and key = 'ops.workspace'; execute 'set local role authenticated';
  begin perform task_delegate(tb, u_ag); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: passar recusado (0A000)', true, st = '0A000');
  begin perform inbox_item_act('task:' || tb, 'ack'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: ver recusado (0A000)', true, st = '0A000');
  q := my_queue(null);
  insert into t values ('flag desligada: itens sem ações', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'key' = 'task:' || tb and not (x->'can'->>'ack')::boolean)
    and not (q->'enabled' ? 'ws_ops_b'));

  -- ── staff da agência: só clientes atribuídos ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  q := my_queue(null);
  insert into t values ('agência vê A e B atribuídos, nunca C', true,
    exists (select 1 from jsonb_array_elements(q->'items') x where x->>'workspace_id' = 'ws_ops_b')
    and exists (select 1 from jsonb_array_elements(q->'items') x where x->>'workspace_id' = 'numeiro')
    and not exists (select 1 from jsonb_array_elements(q->'items') x where x->>'workspace_id' = 'ws_ops_c'));
  insert into t values ('em B (colaborador) não decide tarefas sem dono de B', true,
    not exists (select 1 from jsonb_array_elements(q->'items') x where x->>'workspace_id' = 'ws_ops_b' and x->>'kind' = 'decision'));

  -- ── aprovar não acontece por ver ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  it := (select x from jsonb_array_elements(my_queue('numeiro')->'items') x where x->>'key' = 'content:' || gapp);
  ver := it->>'rev';
  perform inbox_item_act('content:' || gapp, 'ack');
  insert into t values ('ver um guião não o aprova', true, (select editorial_status from guioes where id = gapp) = 'in_review');

  -- ── presença (OPS-02, OPS-10) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := presence_ping('numeiro', true);
  perform presence_ping('numeiro', true);   -- segundo separador
  insert into t values ('sinal de vida aceite', true, (j->>'ok')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := team_presence('numeiro');
  it := (select x from jsonb_array_elements(j->'members') x where (x->>'user_id')::uuid = u_cc);
  insert into t values ('online depois do sinal; dois separadores contam uma pessoa', true,
    (it->>'online')::boolean and (select count(*) from jsonb_array_elements(j->'members') x where (x->>'user_id')::uuid = u_cc) = 1
    and (j->'counts'->>'online')::int = 1);
  insert into t values ('ativo só com consentimento (desligado por omissão)', true, not (it->>'active')::boolean);
  insert into t values ('cartão com nome do perfil', true, it->>'label' = 'Carla Contribui');
  insert into t values ('lista só membros deste cliente (sem o admin de B)', true,
    not exists (select 1 from jsonb_array_elements(j->'members') x where (x->>'user_id')::uuid = u_cb));
  it := (select x from jsonb_array_elements(j->'members') x where (x->>'user_id')::uuid = u_ag);
  insert into t values ('a trabalhar = tarefa em curso iniciada, com tarefa atual', true,
    (it->>'working')::boolean and it->'current'->>'title' = 'Montar o vídeo 3');
  insert into t values ('staff da agência em A: contagens só de A', true, (it->>'open')::int = 1);
  insert into t values ('não está online sem sinal (online ≠ a trabalhar)', true, not (it->>'online')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := availability_set('{"status":"busy","share_activity":true}');
  insert into t values ('estado manual e consentimento guardados', true, (j->>'changed')::boolean and j->>'status' = 'busy');
  j := availability_set('{"status":"busy","share_activity":true}');
  insert into t values ('repetir o estado não muda nada', true, not (j->>'changed')::boolean);
  begin perform availability_set('{"status":"a_dormir"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('estado desconhecido recusado (22023)', true, st = '22023');
  begin perform availability_set('{"hours":8}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo desconhecido recusado (22023)', true, st = '22023');
  execute 'reset role'; update member_presence set last_seen_at = now() - interval '1 minute' where user_id = u_cc; execute 'set local role authenticated';
  perform presence_ping('numeiro', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  it := (select x from jsonb_array_elements(team_presence('numeiro')->'members') x where (x->>'user_id')::uuid = u_cc);
  insert into t values ('com consentimento aparece ativo e ocupado', true, (it->>'active')::boolean and it->>'availability' = 'busy');
  -- desconexão: deixa de estar online sem fechar a tarefa nem inventar horas
  execute 'reset role';
  update tasks set status = 'doing' where id = t2;
  update member_presence set last_seen_at = now() - interval '10 minutes' where user_id = u_cc;
  execute 'set local role authenticated';
  it := (select x from jsonb_array_elements(team_presence('numeiro')->'members') x where (x->>'user_id')::uuid = u_cc);
  insert into t values ('desligado: offline, mas continua a trabalhar na tarefa iniciada', true,
    not (it->>'online')::boolean and not (it->>'active')::boolean and (it->>'working')::boolean and (select status from tasks where id = t2) = 'doing');
  insert into t values ('sem horas trabalhadas nem histórico de presença', true, not (it ? 'hours') and not (it ? 'last_seen_at'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  perform availability_set('{"share_activity":false}');
  execute 'reset role';
  insert into t values ('retirar consentimento apaga a última atividade', true, (select last_active_at from member_presence where user_id = u_cc) is null);
  execute 'set local role authenticated';

  -- cliente B e leitor
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform team_presence('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê a equipa de A (42501)', true, st = '42501');
  begin perform presence_ping('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não se faz presente em A (42501)', true, st = '42501');
  j := team_presence('ws_ops_b');
  it := (select x from jsonb_array_elements(j->'members') x where (x->>'user_id')::uuid = u_ag);
  insert into t values ('em B, o staff da agência aparece sem a tarefa em curso de A', true,
    it is not null and it->'current' = 'null'::jsonb and not (it->>'working')::boolean and (it->>'open')::int = 1);
  insert into t values ('em B nenhum título de tarefa de A', true, position('Montar o vídeo 3' in j::text) = 0 and position('Carla' in j::text) = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform team_presence('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor sem ops.presence recusado (42501)', true, st = '42501');

  -- canal privado de presença (OPS-10)
  perform set_config('realtime.topic', 'presence:numeiro', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  insert into t values ('cliente B não lê o canal de presença de A', true, (select count(*) from realtime.messages where topic = 'presence:numeiro') = 0);
  begin insert into realtime.messages (topic, extension, event, payload) values ('presence:numeiro', 'presence', 'track', '{}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('ninguém publica no canal a partir do browser', true, st <> 'none');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  insert into t values ('membro de A lê os avisos do canal de A, sem dados pessoais', true,
    (select count(*) from realtime.messages where topic = 'presence:numeiro') > 0
    and not exists (select 1 from realtime.messages where topic = 'presence:numeiro' and payload::text like '%@%'));
  perform set_config('realtime.topic', 'presence:ws_ops_b', true);
  insert into t values ('membro de A não lê o canal de B', true, (select count(*) from realtime.messages where topic = 'presence:ws_ops_b') = 0);
  perform set_config('realtime.topic', '', true);

  -- membro removido deixa de aparecer e de ver
  execute 'reset role'; delete from workspace_access where user_id = u_rm; execute 'set local role authenticated';
  insert into t values ('removido sai dos cartões', true,
    not exists (select 1 from jsonb_array_elements(team_presence('numeiro')->'members') x where (x->>'user_id')::uuid = u_rm));
  perform set_config('request.jwt.claims', json_build_object('sub', u_rm, 'role','authenticated')::text, true);
  begin perform my_queue('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido não lê a fila do cliente (42501)', true, st = '42501');
  insert into t values ('removido: a fila geral fica vazia', true, jsonb_array_length(my_queue(null)->'items') = 0);

  -- código de equipa não tem caixa pessoal
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform my_queue('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa sem fila pessoal', true, st <> 'none');
  execute 'reset role';
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.inbox_item_states', 'select') and not has_table_privilege('authenticated', 'public.member_presence', 'select')
    and not has_table_privilege('authenticated', 'public.member_availability', 'select'));
  insert into t values ('capacidades e flags registadas', true,
    (select count(*) from capabilities where key in ('tasks.delegate','ops.presence')) = 2
    and (select count(*) from feature_flag_defs where key in ('ops.workspace','ops.team_presence')) = 2);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
