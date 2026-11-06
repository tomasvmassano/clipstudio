-- supabase/tests/w10_anotacoes.sql : anotações desenhadas nos comentários de vídeo (W10-15, FR-05-03; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_rev uuid := gen_random_uuid(); u_view uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  gid text := (select id from guioes where client_id = 'numeiro' and deleted_at is null order by date, n limit 1);
  gb text := 'ws_an_b-1'; sha text := repeat('b', 64);
  a_up uuid := gen_random_uuid(); v_up uuid := gen_random_uuid(); a_old uuid := gen_random_uuid(); v_old uuid := gen_random_uuid();
  a_b uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); a_dr uuid := gen_random_uuid(); v_dr uuid := gen_random_uuid();
  ann jsonb; big jsonb; c1 jsonb; c2 jsonb; j jsonb; st text; dt text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_an_b', 'Anotações B', 'anb', org);
  insert into guioes (id, client_id, date, n, hooks, corpo) values (gb, 'ws_an_b', current_date, 1, '[{"text":"hook B","mecanismo":""}]', 'corpo B');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_rev,'an-rev@test.invalid'),(u_view,'an-view@test.invalid'),(u_b,'an-b@test.invalid'),(u_ag,'an-ag@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_rev, 'client_staff', 'reviewer'), ('numeiro', u_view, 'client_staff', 'viewer'),
    ('ws_an_b', u_b, 'client_staff', 'workspace_admin'), ('ws_an_b', u_ag, 'agency_staff', 'manager');
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'media.library', org, w, 'all' from unnest(array['numeiro','ws_an_b']) w;

  -- vídeos guardados (como se o worker já os tivesse verificado) e um link da Drive
  insert into media_assets (id, workspace_id, kind, title, tags, content_id) values
    (a_up, 'numeiro', 'video', 'g_hook1_S15.mp4', '{hook_1,S15}', gid), (a_old, 'numeiro', 'video', 'antigo.mp4', '{hook_2}', gid),
    (a_b, 'ws_an_b', 'video', 'b.mp4', '{hook_1}', gb), (a_dr, 'numeiro', 'video', 'drive.mp4', '{hook_3}', gid);
  insert into media_versions (id, workspace_id, asset_id, version_no, source, storage_path, size_bytes, mime, sha256, original_name) values
    (v_up, 'numeiro', a_up, 1, 'upload', 'numeiro/an/1.mp4', 1000, 'video/mp4', sha, '1.mp4'),
    (v_old, 'numeiro', a_old, 1, 'upload', 'numeiro/an/2.mp4', 1000, 'video/mp4', sha, '2.mp4'),
    (v_b, 'ws_an_b', a_b, 1, 'upload', 'ws_an_b/an/1.mp4', 1000, 'video/mp4', sha, 'b.mp4');
  insert into media_versions (id, workspace_id, asset_id, version_no, source, state, external_url) values
    (v_dr, 'numeiro', a_dr, 1, 'link', 'pronta', 'https://drive.google.com/file/d/1AnOtAcOeSdRiVeXyZ0123/view');
  update media_versions set state = 'pronta' where id in (v_up, v_old, v_b);
  update media_assets set current_version_id = id_v from (values (a_up, v_up), (a_old, v_old), (a_b, v_b), (a_dr, v_dr)) z(id_a, id_v) where id = id_a;

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  ann := '{"v": 1, "shapes": [
      {"type": "pen", "color": "#FF3B30", "width": 0.006, "points": [[0.1, 0.1], [0.123456, 0.2], [0.3, 0.35]]},
      {"type": "arrow", "color": "#ffd60a", "width": 0.008, "points": [[0.5, 0.5], [0.8, 0.2]]},
      {"type": "rect", "color": "#34c759", "width": 0.004, "points": [[0, 0], [1, 1]]},
      {"type": "ellipse", "color": "#0a84ff", "width": 0.004, "points": [[0.4, 0.6], [0.6, 0.7]], "extra": "ignorado"}],
    "lixo": true}';
  big := jsonb_build_object('v', 1, 'shapes', (select jsonb_agg(jsonb_build_object('type', 'rect', 'color', '#ffffff', 'width', 0.004,
           'points', '[[0.1,0.1],[0.2,0.2]]'::jsonb)) from generate_series(1, 51)));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);

  -- válido: guardado na forma canónica
  c1 := media_review_comment('numeiro', v_up, 'Corta aqui, o braço sai do enquadramento.', 23400, null, null, ann);
  insert into t values ('comentário com desenho no momento', true, (c1->>'t_ms')::int = 23400 and jsonb_array_length(c1->'annotation'->'shapes') = 4);
  insert into t values ('forma canónica: chaves desconhecidas fora, cor em minúsculas, 4 casas', true,
    not (c1->'annotation' ? 'lixo') and not (c1->'annotation'->'shapes'->3 ? 'extra') and c1->'annotation'->'shapes'->0->>'color' = '#ff3b30'
    and (c1->'annotation'->'shapes'->0->'points'->1->>0)::numeric = 0.1235);
  j := media_review_detail('numeiro', a_up);
  insert into t values ('detalhe devolve o desenho com o comentário', true,
    exists (select 1 from jsonb_array_elements(j->'comments') x where x->>'id' = c1->>'id' and x->'annotation' = c1->'annotation'));

  -- assinatura antiga continua a funcionar (por posição e por nome), sem desenho
  c2 := media_review_comment('numeiro', v_up, 'Sem desenho, por posição.', 1000);
  insert into t values ('assinatura antiga por posição (4 args)', true, (c2->>'t_ms')::int = 1000 and c2->'annotation' = 'null'::jsonb);
  j := media_review_comment(p_ws => 'numeiro', p_version => v_up, p_body => 'Resposta por nome.', p_t_ms => null, p_parent => (c1->>'id')::uuid, p_token => null);
  insert into t values ('assinatura antiga por nome (6 args): resposta herda o momento', true, (j->>'t_ms')::int = 23400 and j->'annotation' = 'null'::jsonb);
  j := media_review_comment('numeiro', v_up, 'Só texto.');
  insert into t values ('assinatura antiga (3 args)', true, j->>'t_ms' is null);
  j := media_review_comment('numeiro', v_up, 'JSON null é sem desenho.', 2000, null, null, 'null'::jsonb);
  insert into t values ('annotation JSON null = sem desenho', true, j->'annotation' = 'null'::jsonb);

  -- inválidos
  for r in select * from (values
      ('tipo não permitido', '{"v":1,"shapes":[{"type":"text","color":"#ffffff","width":0.004,"points":[[0.1,0.1],[0.2,0.2]]}]}'),
      ('coordenada > 1', '{"v":1,"shapes":[{"type":"rect","color":"#ffffff","width":0.004,"points":[[0.1,0.1],[1.2,0.2]]}]}'),
      ('coordenada negativa', '{"v":1,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[[-0.01,0.1]]}]}'),
      ('coordenada em texto', '{"v":1,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[["0.1",0.1]]}]}'),
      ('ponto com 3 valores', '{"v":1,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[[0.1,0.1,0.1]]}]}'),
      ('ponto que não é lista', '{"v":1,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[0.1]}]}'),
      ('cor fora do formato', '{"v":1,"shapes":[{"type":"rect","color":"red","width":0.004,"points":[[0.1,0.1],[0.2,0.2]]}]}'),
      ('cor com CSS injetado', '{"v":1,"shapes":[{"type":"rect","color":"#fff;x","width":0.004,"points":[[0.1,0.1],[0.2,0.2]]}]}'),
      ('sem espessura', '{"v":1,"shapes":[{"type":"rect","color":"#ffffff","points":[[0.1,0.1],[0.2,0.2]]}]}'),
      ('espessura grande', '{"v":1,"shapes":[{"type":"rect","color":"#ffffff","width":0.5,"points":[[0.1,0.1],[0.2,0.2]]}]}'),
      ('seta com 3 pontos', '{"v":1,"shapes":[{"type":"arrow","color":"#ffffff","width":0.004,"points":[[0.1,0.1],[0.2,0.2],[0.3,0.3]]}]}'),
      ('traço sem pontos', '{"v":1,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[]}]}'),
      ('sem formas', '{"v":1,"shapes":[]}'),
      ('versão desconhecida', '{"v":2,"shapes":[{"type":"pen","color":"#ffffff","width":0.004,"points":[[0.1,0.1]]}]}'),
      ('não é objeto', '[1,2]'),
      ('shapes não é lista', '{"v":1,"shapes":{}}')) z(name, js) loop
    begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, r.js::jsonb); st := 'ok'; exception when others then st := sqlstate; end;
    insert into t values ('inválido: ' || r.name || ' (22023)', true, st = '22023');
  end loop;
  -- limites de tamanho
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, big); st := 'ok'; exception when others then st := sqlstate; get stacked diagnostics dt = pg_exception_detail; end;
  insert into t values ('51 formas recusadas (22023)', true, st = '22023' and dt like '%50 formas%');
  j := jsonb_build_object('v', 1, 'shapes', jsonb_build_array(jsonb_build_object('type', 'pen', 'color', '#ffffff', 'width', 0.004,
         'points', (select jsonb_agg(jsonb_build_array(0.5, 0.5)) from generate_series(1, 501)))));
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, j); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('traço com 501 pontos recusado (22023)', true, st = '22023');
  j := jsonb_build_object('v', 1, 'shapes', (select jsonb_agg(jsonb_build_object('type', 'pen', 'color', '#ffffff', 'width', 0.004,
         'points', (select jsonb_agg(jsonb_build_array(0.5, 0.5)) from generate_series(1, 450)))) from generate_series(1, 5)));
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, j); st := 'ok'; exception when others then st := sqlstate; get stacked diagnostics dt = pg_exception_detail; end;
  insert into t values ('mais de 2000 pontos ao todo recusado (22023)', true, st = '22023' and dt like '%2000 pontos%');
  j := jsonb_build_object('v', 1, 'shapes', (select jsonb_agg(jsonb_build_object('type', 'pen', 'color', '#ffffff', 'width', 0.004,
         'points', (select jsonb_agg(jsonb_build_array(0.5, 0.5)) from generate_series(1, 400)))) from generate_series(1, 5)));
  c2 := media_review_comment('numeiro', v_up, 'No limite.', 5000, null, null, j);
  insert into t values ('2000 pontos no limite aceites', true, jsonb_array_length(c2->'annotation'->'shapes') = 5);
  j := jsonb_build_object('v', 1, 'shapes', (select jsonb_agg(jsonb_build_object('type', 'pen', 'color', '#ffffff', 'width', 0.004,
         'points', (select jsonb_agg(jsonb_build_array(0.123456789012345, 0.987654321098765)) from generate_series(1, 500)))) from generate_series(1, 50)));
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, j); st := 'ok'; exception when others then st := sqlstate; get stacked diagnostics dt = pg_exception_detail; end;
  insert into t values ('pedido acima de 256 KB recusado antes de validar (22023)', true, st = '22023' and dt like '%grande demais%');
  -- regras do comentário
  begin perform media_review_comment('numeiro', v_up, 'x', null, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('desenho sem momento (22023)', true, st = '22023');
  begin perform media_review_comment('numeiro', v_up, 'x', null, (c1->>'id')::uuid, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('resposta com desenho (22023)', true, st = '22023');
  begin perform media_review_comment('numeiro', v_dr, 'x', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('vídeo da Drive não leva desenho (22023)', true, st = '22023');
  j := media_review_comment('numeiro', v_dr, 'Drive continua com texto e momento.', 5000);
  insert into t values ('vídeo da Drive comenta como antes', true, (j->>'t_ms')::int = 5000);
  begin perform media_review_comment('numeiro', v_up, '  ', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('desenho exige texto (22023)', true, st = '22023');

  -- quem não pode
  perform set_config('request.jwt.claims', json_build_object('sub', u_view, 'role','authenticated')::text, true);
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não comenta com desenho (42501)', true, st = '42501');
  j := media_review_detail('numeiro', a_up);
  insert into t values ('leitor vê o desenho', true, exists (select 1 from jsonb_array_elements(j->'comments') x where x->'annotation' = c1->'annotation'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não comenta no vídeo de A (42501)', true, st = '42501');
  begin perform media_review_comment('ws_an_b', v_up, 'x', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B com a versão de A no seu espaço: não existe (P0002)', true, st = 'P0002');
  begin perform media_review_detail('numeiro', a_up); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê os desenhos de A (42501)', true, st = '42501');
  j := media_review_comment('ws_an_b', v_b, 'No meu vídeo.', 1000, null, null, ann);
  insert into t values ('cliente B desenha no seu vídeo', true, jsonb_array_length(j->'annotation'->'shapes') = 4);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, null, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência só em B não comenta em A (42501)', true, st = '42501');
  j := media_review_detail('ws_an_b', a_b);
  insert into t values ('staff da agência em B vê o desenho de B', true, exists (select 1 from jsonb_array_elements(j->'comments') x where x->'annotation' is not null and x->'annotation' <> 'null'::jsonb));
  execute 'reset role';
  -- código de equipa recusado (sessão individual)
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  begin perform media_review_comment('numeiro', v_up, 'x', 5000, null, tok, ann); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não comenta (recusado)', true, st in ('42501', '28000'));
  execute 'reset role';
  insert into t values ('evento sabe que o comentário tem desenho', true,
    exists (select 1 from domain_events where type = 'media.commented' and payload->>'comment_id' = c1->>'id' and (payload->>'annotated')::boolean
            and (payload->>'shapes')::int = 4));
  insert into t values ('nada gravado nas tentativas inválidas', true,
    (select count(*) from media_comments where version_id = v_up and annotation is not null) = 2);
  -- o desenho não se reescreve
  begin update media_comments set annotation = null where id = (c1->>'id')::uuid; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('desenho não se reescreve (42501)', true, st = '42501');
  begin update media_comments set resolved_at = now() where id = (c1->>'id')::uuid; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('resolver continua possível', true, st = 'ok');
  begin insert into media_comments (workspace_id, asset_id, version_id, body, annotation) values ('numeiro', a_up, v_up, 'x', '[1]'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('coluna recusa anotação que não é objeto (23514)', true, st = '23514');
  insert into t values ('browser não chama o validador interno', true,
    not has_function_privilege('authenticated', 'public._review_annotation(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.media_review_comment(text, uuid, text, int, uuid, text, jsonb)', 'execute'));
  insert into t values ('só existe uma media_review_comment', true, (select count(*) from pg_proc where proname = 'media_review_comment') = 1);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
