-- supabase/tests/w10_pacote_por_guiao.sql : pacote por guião (W10-20, STU-03; ADR-0070). Rollback no fim.
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  u_own uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid();
  sha text := repeat('a', 64); j jsonb; k jsonb; st text; job uuid; job2 uuid; g1 text; g2 text; g3 text; g4 text; gb text; doc jsonb;
  v jsonb; a_f1 uuid; a_s1 uuid; a_f2 uuid; a_s2 uuid; a_f3 uuid; a_s3 uuid; a_x uuid; a_f4 uuid; a_s4 uuid; a_b uuid;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_pg_b', 'Por guião B', 'pgb', org);
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, origem, status)
  values ('ws_pg_b-g1', 'ws_pg_b', current_date, 1, 'lista', 'Guião B', '[{"text":"Hook B"}]', 'Corpo B.', 'fixture', 'aprovado');
  gb := 'ws_pg_b-g1';
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'pg-own@test.invalid'),(u_rev,'pg-rev@test.invalid'),(u_b,'pg-b@test.invalid'),(u_ag,'pg-ag@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_own, 'client_staff', 'workspace_admin'), ('numeiro', u_rev, 'client_staff', 'reviewer'),
    ('ws_pg_b', u_b, 'client_staff', 'workspace_admin'), ('ws_pg_b', u_ag, 'agency_staff', 'manager');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_pg_b', 'all'), ('edit.studio', org, 'ws_pg_b', 'all'), ('media.r2', org, 'ws_pg_b', 'all');
  select id into g1 from guioes where client_id = 'numeiro' order by date, n limit 1;
  select id into g2 from guioes where client_id = 'numeiro' order by date, n offset 1 limit 1;
  select id into g3 from guioes where client_id = 'numeiro' order by date, n offset 2 limit 1;
  select id into g4 from guioes where client_id = 'numeiro' order by date, n offset 3 limit 1;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g01_frente.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); a_f1 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g01_lado.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); a_s1 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null);

  -- flag desligada: nada responde
  begin perform media_clip_link('numeiro', a_f1, g1, 'front'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: ligar gravação 55000', true, st = '55000');
  begin perform edit_package_script_list('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: lista 55000', true, st = '55000');
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('edit.package_script', org, 'numeiro', 'all'), ('edit.package_script', org, 'ws_pg_b', 'all');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := media_clip_link('numeiro', a_f1, g1, 'front', null, 'upload');
  insert into t values ('ligar frente ao guião', true, k->>'camera' = 'front' and k->>'content_id' = g1 and not (k->>'repeated')::boolean);
  k := media_clip_link('numeiro', a_f1, g1, 'front', null, 'upload');
  insert into t values ('ligar outra vez é idempotente', true, (k->>'repeated')::boolean);
  perform media_clip_link('numeiro', a_s1, g1, 'side', null, 'upload');
  execute 'reset role';
  insert into t values ('ativo fica ligado ao guião', true, (select content_id from media_assets where id = a_s1) = g1);
  execute 'set local role authenticated';
  begin perform media_clip_link('numeiro', a_f1, g1, 'top'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('câmara inválida 22023', true, st = '22023');
  begin perform media_clip_link('numeiro', a_f1, g1, 'front', null, 'agente'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('a app não se faz passar pelo agente (22023)', true, st = '22023');
  begin perform media_clip_link('numeiro', a_f1, gb, 'front'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('guião de outro cliente P0002', true, st = 'P0002');
  begin perform media_clip_link('numeiro', a_f1, g2, 'front'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ficheiro ligado a outro guião 22023', true, st = '22023');
  begin perform edit_package_script_request('numeiro', g1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravações por verificar: em falta P0002', true, st = 'P0002');

  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform media_clip_link('numeiro', a_f1, g1, 'side'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não liga gravações (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_clip_link('numeiro', a_f1, g1, 'side'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não liga no A (42501)', true, st = '42501');
  begin perform media_clip_link('ws_pg_b', a_f1, gb, 'side'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B com ativo do A no seu espaço: P0002', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform edit_package_script_list('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência só em B não lista A (42501)', true, st = '42501');
  begin perform edit_package_script_request('numeiro', g1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência só em B não pede em A (42501)', true, st = '42501');
  k := edit_package_script_list('ws_pg_b');
  insert into t values ('staff da agência em B vê a lista de B (vazia)', true, jsonb_array_length(k->'scripts') = 0 and (k->'can'->>'request')::boolean);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  execute 'set local role anon';
  begin perform edit_package_script_request('numeiro', g1, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não pede (42501/55000)', true, st in ('42501', '55000', '28000'));
  execute 'reset role';

  -- o worker verifica as duas gravações
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 60) loop
    j := media_worker_claim('w-pg', array['ingest']);
    exit when j->'job' is null or j->'job' = 'null'::jsonb;
    perform media_worker_finish('w-pg', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/p.mp4', 'info', jsonb_build_object('duration', 90)));
  end loop;
  execute 'reset role';
  insert into t values ('automático desligado: nenhum pacote sozinho', true,
    not exists (select 1 from media_jobs where kind = 'package' and input->>'guiao_id' = g1));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform edit_package_script_request('numeiro', g1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não pede pacote (42501)', true, st = '42501');
  begin perform package_script_settings_set('numeiro', true, false, 'S15'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não muda as definições (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform edit_package_script_request('numeiro', g1); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não pede no A (42501)', true, st = '42501');
  begin perform package_script_settings_set('numeiro', true, true, 'S15'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não muda definições do A (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_package_script_request('numeiro', g1);
  j := edit_package_script_request('numeiro', g1);
  insert into t values ('pedido por guião idempotente', true, k->>'id' = j->>'id' and k->>'status' = 'queued' and k->>'guiao_id' = g1);
  job := (k->>'id')::uuid;
  k := edit_package_list('numeiro');
  insert into t values ('lista da sessão não mostra o pacote por guião', true, not exists (select 1 from jsonb_array_elements(k) x where x->>'id' = job::text));
  k := edit_package_script_list('numeiro');
  insert into t values ('lista por guião: gravações prontas e pacote', true,
    exists (select 1 from jsonb_array_elements(k->'scripts') x where x->'guiao'->>'id' = g1 and x->'front'->>'state' = 'pronta'
            and x->'side'->>'name' = 'g01_lado.mp4' and x->'job'->>'id' = job::text and x->'job'->>'origin' = 'manual'));
  execute 'reset role';
  insert into t values ('job por guião: mode, um guião, marcas vazias, corte do lado', true,
    (select kind = 'package' and input->>'mode' = 'script' and input->>'guiao_id' = g1 and jsonb_array_length(input->'guioes') = 1
            and input->'guioes'->0 ? 'corpo' and input->'marks'->>'reason' = 'pedido_sem_marcas' and input->'front'->>'name' = 'g01_frente.mp4'
            and input->'side'->>'name' = 'g01_lado.mp4' and idempotency_key like 'package_script:%' and created_by = u_own
       from media_jobs where id = job));
  insert into t values ('pedido auditado', true, exists (select 1 from audit_events where action = 'edit.package_script_requested' and entity_id = job::text and actor_user_id = u_own));

  -- definições: automático + exportar todos
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform package_script_settings_set('numeiro', true, true, 'X Y'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('estilo inválido 22023', true, st = '22023');
  k := package_script_settings_set('numeiro', true, true, 'S15');
  insert into t values ('definições gravadas', true, (k->>'auto_package')::boolean and (k->>'auto_export')::boolean);
  -- g2: liga primeiro, as gravações chegam depois (o automático corre quando a segunda fica pronta)
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g02_frente.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); a_f2 := (j->>'asset_id')::uuid;
  perform media_clip_link('numeiro', a_f2, g2, 'front', null, 'upload');
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g02_lado.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); a_s2 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null);
  perform media_clip_link('numeiro', a_s2, g2, 'side', null, 'upload');
  -- g3: nome repetido noutro ativo
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g03_frente.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); a_f3 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null); perform media_clip_link('numeiro', a_f3, g3, 'front');
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g03_lado.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); a_s3 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null); perform media_clip_link('numeiro', a_s3, g3, 'side');
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g03_lado.mp4', 'size', 7000, 'mime', 'video/mp4', 'sha256', sha)); a_x := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null);
  execute 'reset role';
  insert into t values ('ligar antes de chegar não dispara', true, not exists (select 1 from media_jobs where kind = 'package' and input->>'guiao_id' = g2));

  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 60) loop
    j := media_worker_claim('w-pg', array['ingest']);
    exit when j->'job' is null or j->'job' = 'null'::jsonb;
    perform media_worker_finish('w-pg', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/p.mp4', 'info', jsonb_build_object('duration', 80)));
  end loop;
  execute 'reset role';
  select id into job2 from media_jobs where kind = 'package' and input->>'guiao_id' = g2;
  insert into t values ('automático: pacote do guião quando chega a segunda gravação', true,
    (select count(*) = 1 and bool_and(input->>'origin' = 'auto' and created_by = u_own and created_label like '%(automático)')
       from media_jobs where kind = 'package' and input->>'guiao_id' = g2));
  insert into t values ('automático registado no estado do guião', true,
    exists (select 1 from package_script_status where content_id = g2 and job_id = job2 and reason is null));
  insert into t values ('nome repetido: não corre e diz porquê', true,
    not exists (select 1 from media_jobs where kind = 'package' and input->>'guiao_id' = g3)
    and exists (select 1 from package_script_status where content_id = g3 and reason like 'nome_repetido%'));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform edit_package_script_request('numeiro', g3); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('nome repetido à mão: 22023', true, st = '22023');
  -- trocar a gravação do lado do g2 por outra: a anterior sai da ligação
  k := media_clip_link('numeiro', a_x, g2, 'side');
  execute 'reset role';
  insert into t values ('substituir a câmara: uma gravação por guião e câmara', true,
    (select count(*) from recording_clips where content_id = g2 and camera = 'side') = 1
    and exists (select 1 from recording_clips where asset_id = a_x and content_id = g2) and not exists (select 1 from recording_clips where asset_id = a_s2));
  execute 'set local role authenticated';
  perform media_clip_link('numeiro', a_s2, g2, 'side');
  execute 'reset role';

  -- worker faz os pacotes; o do g2 acaba e exporta sozinho
  doc := jsonb_build_object('schema', 1, 'style', 'S15', 'segments', jsonb_build_array(jsonb_build_object('id', 's01', 'in', 1, 'out', 4, 'section', 'hook'),
           jsonb_build_object('id', 's02', 'in', 5, 'out', 20, 'section', 'body')),
           'captions', jsonb_build_object('words', '[]'::jsonb), 'cameras', '[]'::jsonb, 'hook', jsonb_build_object('text', 'Tema'),
           'source', jsonb_build_object('cams', jsonb_build_object('front', 'g02_frente.mp4', 'side', 'g02_lado.mp4'), 'audio', 'side'),
           'ai', jsonb_build_object('confidence', jsonb_build_object('hook', 0.8, 'body', 0.7)));
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 60) loop
    j := media_worker_claim('w-pg', array['package']);
    exit when j->'job' is null or j->'job' = 'null'::jsonb;
    if (j->'job'->>'id')::uuid = job2 then
      perform media_worker_package_save('w-pg', job2, g2, 1, doc);
      perform media_worker_package_save('w-pg', job2, g2, 2, doc);
      perform media_worker_finish('w-pg', job2, true, jsonb_build_object('documents', 2, 'mode', 'script'));
    elsif j->'job' is not null and j->'job' <> 'null'::jsonb then
      perform media_worker_finish('w-pg', (j->'job'->>'id')::uuid, false, null, 'teste', false);
    end if;
  end loop;
  execute 'reset role';
  insert into t values ('exportar todos automático: um export por vídeo', true,
    (select count(*) from media_jobs e join media_job_outputs o on o.asset_id = e.asset_id where o.job_id = job2 and e.kind = 'export'
      and e.created_by = u_own and e.input->'cams'->'front'->>'name' = 'g02_frente.mp4') = 2);
  insert into t values ('exportar automático auditado', true,
    exists (select 1 from audit_events where action = 'edit.package_script_auto_export' and entity_id = job2::text and (after->>'queued')::int = 2));
  insert into t values ('pacote por guião que falha não exporta', true,
    not exists (select 1 from audit_events where action = 'edit.package_script_auto_export' and entity_id = job::text));
  -- o export automático é o mesmo job que edit_export_request daria (mesma chave)
  select o.asset_id into a_b from media_job_outputs o where o.job_id = job2 order by hook limit 1;
  select e.id::text into st from media_jobs e where e.asset_id = a_b and e.kind = 'export' order by created_at limit 1;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  k := edit_export_request('numeiro', a_b);
  insert into t values ('export automático igual ao pedido à mão', true,
    k->>'id' = st);
  -- falhou: pedir de novo cria job novo
  k := edit_package_script_request('numeiro', g1);
  insert into t values ('pacote falhado: pedir de novo cria outro job', true, k->>'id' <> job::text and k->>'status' = 'queued');

  -- quem ligou o automático perde o acesso: o automático deixa de correr
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g04_frente.mp4', 'size', 5000, 'mime', 'video/mp4', 'sha256', sha)); a_f4 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null); perform media_clip_link('numeiro', a_f4, g4, 'front');
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'g04_lado.mp4', 'size', 6000, 'mime', 'video/mp4', 'sha256', sha)); a_s4 := (j->>'asset_id')::uuid;
  perform media_upload_complete('numeiro', (j->>'version_id')::uuid, null); perform media_clip_link('numeiro', a_s4, g4, 'side');
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  update workspace_access set status = 'suspended' where user_id = u_own and workspace_id = 'numeiro';
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 60) loop
    j := media_worker_claim('w-pg', array['ingest']);
    exit when j->'job' is null or j->'job' = 'null'::jsonb;
    perform media_worker_finish('w-pg', (j->'job'->>'id')::uuid, true, jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'x/p.mp4'));
  end loop;
  execute 'reset role';
  insert into t values ('responsável suspenso: automático não corre (sem_permissao)', true,
    not exists (select 1 from media_jobs where kind = 'package' and input->>'guiao_id' = g4)
    and exists (select 1 from package_script_status where content_id = g4 and reason = 'sem_permissao'));
  insert into t values ('verificação do upload não falha por causa do automático', true,
    (select count(*) from media_versions v join media_assets a on a.id = v.asset_id where a.id in (a_f4, a_s4) and v.state = 'pronta') = 2);
  insert into t values ('tabelas fechadas ao browser', true,
    not has_table_privilege('authenticated', 'public.recording_clips', 'select') and not has_table_privilege('authenticated', 'public.package_script_settings', 'select')
    and not has_table_privilege('anon', 'public.package_script_status', 'select'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
