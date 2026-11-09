-- supabase/tests/w10_notif_agrupada.sql : notificação agrupada dos pacotes por guião (W10-23, STU-03; ADR-0072). Rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_gone uuid := gen_random_uuid();
  g1 text; g2 text; g3 text; g4 text; n3 int; j1 uuid; j2 uuid; j3 uuid; j3b uuid; j4 uuid; js uuid; jx uuid; jn uuid;
  sess uuid; a4 uuid; nt notifications; ca timestamptz; inb jsonb; ev0 bigint; c int;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_na_b', 'Agrupada B', 'nab', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'na-own@test.invalid'),(u_rev,'na-rev@test.invalid'),(u_b,'na-b@test.invalid'),(u_gone,'na-gone@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('ws_na_b', u_b, 'client_staff', 'workspace_admin'), ('numeiro', u_gone, 'client_staff', 'workspace_admin');
  select id into g1 from guioes where client_id = 'numeiro' order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' order by date, n offset 1 limit 1;
  select id, n into g3, n3 from guioes where client_id = 'numeiro' order by date, n offset 2 limit 1;
  select id into g4 from guioes where client_id = 'numeiro' order by date, n offset 3 limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  perform set_config('request.jwt.claims', '', true);

  -- texto (função pura)
  insert into t values ('texto em curso', true, public._package_script_batch_text(12, 7, 0, null)->>'title' = 'Pacotes por guião prontos: 7 de 12');
  insert into t values ('texto final com falhas', true, public._package_script_batch_text(12, 9, 3, 'guião 1')->>'title' = 'Pacotes por guião terminados: 9 de 12 prontos, 3 falharam'
    and (public._package_script_batch_text(12, 9, 3, 'guião 1')->>'final')::boolean);

  -- 3 pacotes por guião do mesmo dia (sem sessão conhecida), pedidos por u_own
  ev0 := (select coalesce(max(id), 0) from domain_events);
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:' || g1, jsonb_build_object('mode', 'script', 'guiao_id', g1), u_own, 2) returning id into j1;
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:' || g2, jsonb_build_object('mode', 'script', 'guiao_id', g2), u_own, 2) returning id into j2;
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:' || g3, jsonb_build_object('mode', 'script', 'guiao_id', g3), u_own, 2) returning id into j3;
  insert into t values ('um lote por dia com 3 guiões', true,
    (select count(*) from package_script_batches where user_id = u_own) = 1
    and (select batch_key from package_script_batches where user_id = u_own) like 'day:%'
    and (select count(*) from package_script_batch_items i join package_script_batches b on b.id = i.batch_id where b.user_id = u_own) = 3);
  insert into t values ('pedir não cria notificação (nada acabou)', true, not exists (select 1 from notifications where user_id = u_own));

  update media_jobs set status = 'running' where id = j1;
  update media_jobs set status = 'done' where id = j1;
  select * into nt from notifications where user_id = u_own and entity_type = 'package_script_batch';
  insert into t values ('1 de 3', true, nt.title = 'Pacotes por guião prontos: 1 de 3' and nt.read_at is null and nt.kind = 'video_decision');
  insert into t values ('sem notificação "Pacote de edição pronto" por guião', true,
    not exists (select 1 from notifications where user_id = u_own and dedup_key = 'package:' || j1));
  update notifications set read_at = now() where id = nt.id;

  update media_jobs set status = 'done' where id = j2;
  insert into t values ('2 de 3, uma só notificação, de novo por ler', true,
    (select count(*) from notifications where user_id = u_own) = 1
    and (select title from notifications where id = nt.id) = 'Pacotes por guião prontos: 2 de 3'
    and (select read_at from notifications where id = nt.id) is null);
  update notifications set read_at = now() where id = nt.id;
  ca := (select created_at from notifications where id = nt.id);

  -- retry de um job já acabado: não conta duas vezes nem volta a pôr por ler
  update media_jobs set status = 'queued' where id = j2;
  update media_jobs set status = 'running' where id = j2;
  update media_jobs set status = 'done' where id = j2;
  insert into t values ('retry não conta duas vezes', true,
    (select title from notifications where id = nt.id) = 'Pacotes por guião prontos: 2 de 3'
    and (select read_at from notifications where id = nt.id) is not null
    and (select created_at from notifications where id = nt.id) = ca
    and (select notified_done from package_script_batches where user_id = u_own) = 2);

  -- falha conta e fica nomeada; estado final
  update media_jobs set status = 'dead' where id = j3;
  select * into nt from notifications where id = nt.id;
  insert into t values ('final: 2 de 3 prontos, 1 falhou', true,
    nt.title = 'Pacotes por guião terminados: 2 de 3 prontos, 1 falhou' and nt.read_at is null and nt.body like '%guião ' || n3 || '%');
  insert into t values ('audit do estado final', true,
    exists (select 1 from audit_events where action = 'edit.package_script_batch_done' and workspace_id = 'numeiro' and (after->>'failed')::int = 1));
  insert into t values ('domain_event por mudança (3)', true,
    (select count(*) from domain_events where id > ev0 and type = 'package_script.batch_progress' and workspace_id = 'numeiro') = 3);

  -- voltar a pedir o guião que falhou: substitui o item (total continua 3) e fecha 3 de 3
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na2:' || g3, jsonb_build_object('mode', 'script', 'guiao_id', g3), u_own, 2) returning id into j3b;
  update media_jobs set status = 'done' where id = j3b;
  update media_jobs set status = 'failed' where id = j3;   -- o job antigo já não é do lote: ignorado
  insert into t values ('pedir de novo: 3 de 3 prontos', true,
    (select title from notifications where id = nt.id) = 'Pacotes por guião prontos: 3 de 3'
    and (select count(*) from notifications where user_id = u_own) = 1);

  -- sessão conhecida (gravação ligada a uma sessão do teleprompter): lote próprio
  insert into recording_sessions (workspace_id, date, opened_kind) values ('numeiro', current_date + 400, 'user') returning id into sess;
  insert into media_assets (workspace_id, kind, title) values ('numeiro', 'video', 'na_lado.mp4') returning id into a4;
  insert into recording_clips (asset_id, workspace_id, content_id, camera, session_id) values (a4, 'numeiro', g4, 'side', sess);
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:' || g4, jsonb_build_object('mode', 'script', 'guiao_id', g4), u_own, 2) returning id into j4;
  update media_jobs set status = 'done' where id = j4;
  insert into t values ('lote por sessão: notificação própria 1 de 1', true,
    exists (select 1 from package_script_batches where user_id = u_own and batch_key = 'session:' || sess)
    and (select count(*) from notifications where user_id = u_own and entity_type = 'package_script_batch') = 2
    and exists (select 1 from notifications where user_id = u_own and title = 'Pacotes por guião prontos: 1 de 1'));

  -- pacote da sessão: igual a hoje
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:sess', '{}'::jsonb, u_own, 2) returning id into js;
  update media_jobs set status = 'done' where id = js;
  insert into t values ('pacote da sessão: notificação própria como hoje', true,
    exists (select 1 from notifications where user_id = u_own and dedup_key = 'package:' || js and title = 'Pacote de edição pronto: 0 vídeos para rever'
            and entity_type = 'media_job')
    and not exists (select 1 from package_script_batch_items where job_id = js));

  -- destinatários: quem pediu; sem created_by nada; quem perdeu o acesso não recebe
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:null', jsonb_build_object('mode', 'script', 'guiao_id', g1), null, 2) returning id into jn;
  update media_jobs set status = 'done' where id = jn;
  update workspace_access set status = 'suspended' where user_id = u_gone and workspace_id = 'numeiro';
  insert into media_jobs (workspace_id, kind, idempotency_key, input, created_by, max_attempts) values
    ('numeiro', 'package', 'na:gone', jsonb_build_object('mode', 'script', 'guiao_id', g1), u_gone, 2) returning id into jx;
  update media_jobs set status = 'done' where id = jx;
  insert into t values ('sem created_by: sem lote nem notificação', true, not exists (select 1 from package_script_batch_items where job_id = jn));
  insert into t values ('quem perdeu o acesso não recebe', true, not exists (select 1 from notifications where user_id = u_gone));
  insert into t values ('revisor (não pediu) não recebe', true, not exists (select 1 from notifications where user_id = u_rev));

  -- leitura: dono vê na caixa; cliente B nunca vê a notificação do A
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  inb := inbox();
  insert into t values ('caixa do dono mostra o lote', true,
    exists (select 1 from jsonb_array_elements(inb->'notifications') x where x->>'entity_type' = 'package_script_batch' and x->>'title' = 'Pacotes por guião prontos: 3 de 3'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  inb := inbox();
  insert into t values ('cliente B: caixa sem a notificação do A', true,
    not exists (select 1 from jsonb_array_elements(inb->'notifications') x where x->>'workspace_id' = 'numeiro'));
  select count(*) into c from notifications where entity_type = 'package_script_batch';
  insert into t values ('cliente B: select direto vê 0', true, c = 0);
  begin select count(*) into c from package_script_batches; c := -1; exception when insufficient_privilege then c := 0; end;
  insert into t values ('tabelas do lote fechadas ao browser', true, c = 0
    and not has_table_privilege('authenticated', 'public.package_script_batch_items', 'select')
    and not has_table_privilege('anon', 'public.package_script_batches', 'select'));
  begin perform public._package_script_batch_notify(gen_random_uuid()); c := -1; exception when insufficient_privilege then c := 0; end;
  insert into t values ('browser não chama a função interna', true, c = 0);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
