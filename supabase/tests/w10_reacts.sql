-- supabase/tests/w10_reacts.sql : Radar de reacts (W10-25, REACT-01..07; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_con uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_den uuid := gen_random_uuid();
  j jsonb; st text; cid bigint; cid2 bigint; sid uuid; sid_b uuid; g1 text; g2 text; n int;
  ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_rx_b', 'Reacts B', 'rxb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'rx-adm@test.invalid'),(u_con,'rx-con@test.invalid'),(u_rev,'rx-rev@test.invalid'),(u_b,'rx-b@test.invalid'),(u_den,'rx-den@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_adm, 'client_staff', 'workspace_admin'), ('numeiro', u_con, 'client_staff', 'contributor'),
    ('numeiro', u_rev, 'client_staff', 'reviewer'), ('numeiro', u_den, 'client_staff', 'manager'), ('ws_rx_b', u_b, 'client_staff', 'workspace_admin');
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('numeiro', u_den, 'reacts.read', 'deny', 'teste: negação explícita');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, engine_worker;

  insert into t values ('capacidades registadas e ativas', true,
    (select count(*) from capabilities where key in ('reacts.read', 'reacts.decide', 'reacts.sources.manage') and status = 'ativo') = 3
    and not exists (select 1 from role_capabilities where capability like 'reacts.%' and role in ('reviewer', 'viewer'))
    and not exists (select 1 from role_capabilities where capability = 'reacts.sources.manage' and role = 'contributor'));

  -- flag desligada (código de cliente sem agência): 55000 mesmo com a capacidade
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  begin perform reacts_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: 55000', true, st = '55000');
  begin perform worker_react_context('numeiro'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sessão não chama RPC do agente (42501)', true, st = '42501');
  begin perform count(*) from react_candidates; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('tabela fechada à API (42501)', true, st = '42501');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('reacts.radar', org, 'numeiro', 'all'), ('reacts.radar', org, 'ws_rx_b', 'all');

  -- o agente propõe contas e cria candidatos
  execute 'set local role engine_worker';
  j := worker_react_source_upsert('numeiro', jsonb_build_object('platform', 'instagram', 'handle', '@KikoIshot', 'status', 'active', 'origin', 'seed', 'score', 80));
  sid := (j->>'id')::uuid;
  j := worker_react_source_upsert('numeiro', jsonb_build_object('platform', 'instagram', 'handle', 'outra.conta', 'origin', 'coauthor', 'origin_detail', 'coautora de @kikoishot', 'score', 61));
  j := worker_react_candidate_upsert('numeiro', jsonb_build_object('url', 'https://www.instagram.com/reel/DfW7duUNv5g/', 'author', 'kikoishot', 'source_handle', 'kikoishot',
        'video_url', 'https://scontent.cdninstagram.com/v/x.mp4', 'video_url_expires_at', now() + interval '2 days', 'posted_at', now() - interval '3 hours',
        'metrics', jsonb_build_object('views', 596078, 'comments', 1800, 'ck', 3.02, 'polemic_index', 4.4), 'video_type', 'talking_head',
        'ai', jsonb_build_object('score', 86, 'risk_level', 'baixo', 'angulo', 'Hipocrisia', 'resumo', 'Goza com o Ronaldo',
               'hooks', jsonb_build_array(jsonb_build_object('text', 'Mais uma na saga dos hipócritas.', 'mecanismo', 'hipocrisia')), 'resposta', 'Resposta de teste.')));
  cid := (j->>'id')::bigint;
  j := worker_react_candidate_upsert('numeiro', jsonb_build_object('url', 'https://www.instagram.com/reel/DfXMwD9OLxp/', 'author', 'kikoishot', 'source_handle', 'kikoishot',
        'metrics', jsonb_build_object('views', 527831), 'ai', jsonb_build_object('score', 70)));
  cid2 := (j->>'id')::bigint;
  j := worker_react_candidate_upsert('numeiro', jsonb_build_object('url', 'https://www.instagram.com/reel/DfW7duUNv5g/', 'metrics', jsonb_build_object('views', 600000)));
  execute 'reset role';
  insert into t values ('repetido pela identidade do vídeo não duplica', true, (j->>'id')::bigint = cid and (select count(*) from react_candidates where workspace_id = 'numeiro') = 2);
  insert into react_sources (workspace_id, platform, handle, status) values ('ws_rx_b', 'instagram', 'conta_b', 'active') returning id into sid_b;
  begin update react_candidates set source_id = sid_b where id = cid; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('fonte de outro cliente rejeitada (23514)', true, st = '23514');

  -- leitura
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := reacts_list('numeiro', 'open');
  insert into t values ('fila ordenada pela nota, sem link do vídeo na linha', true,
    (j->'items'->0->>'id')::bigint = cid and not (j->'items'->0 ? 'video_url') and (j->'items'->0->>'has_video')::boolean
    and (j->'counts'->>'open')::int = 2 and (j->'can'->>'decide')::boolean and (j->'can'->>'sources')::boolean);
  j := react_video_access('numeiro', cid);
  insert into t values ('acesso ao vídeo devolve o link', true, j->>'url' = 'https://scontent.cdninstagram.com/v/x.mp4');
  begin perform react_video_access('numeiro', cid2); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('sem link de vídeo: 55000', true, st = '55000');
  begin perform reacts_list('numeiro', 'xpto'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('separador inválido: 22023', true, st = '22023');

  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform reacts_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisor não vê reacts (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_den, 'role','authenticated')::text, true);
  begin perform reacts_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gestor com negação explícita não vê (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform reacts_list('numeiro', 'open'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não vê a fila (42501)', true, st = '42501');
  begin perform react_video_access('numeiro', cid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não descarrega o vídeo (42501)', true, st = '42501');
  begin perform react_video_access('ws_rx_b', cid); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('trocar o cliente no pedido não dá o vídeo de A (P0002)', true, st = 'P0002');
  begin perform react_decide(cid, 'save'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('outro cliente não decide (42501)', true, st = '42501');
  j := reacts_list('ws_rx_b', 'open');
  insert into t values ('fila de B vazia (sem fuga de A)', true, jsonb_array_length(j->'items') = 0);

  -- decisões (colaborador)
  perform set_config('request.jwt.claims', json_build_object('sub', u_con, 'role','authenticated')::text, true);
  begin perform react_decide(cid2, 'reject'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('rejeitar sem motivo: 22023', true, st = '22023');
  j := react_decide(cid2, 'reject', 'velho', 2, 'já passou');
  insert into t values ('rejeitar com motivo e nota', true, j->>'status' = 'rejected' and j->>'reject_reason' = 'velho' and (j->>'rating')::int = 2);
  j := react_decide(cid2, 'reopen');
  insert into t values ('reabrir volta à fila', true, j->>'status' = 'open' and j->>'reject_reason' is null);
  j := react_decide(cid2, 'save', null, 4);
  insert into t values ('guardar', true, j->>'status' = 'saved' and (j->>'rating')::int = 4);
  begin perform react_source_decide(sid, 'pause'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não gere fontes (42501)', true, st = '42501');
  -- gravar cria guião (colaborador tem scripts.create?)
  begin j := react_record(cid); g1 := j->>'content_id'; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravar cria guião em rascunho, formato react, com os ganchos', true,
    st = 'ok' and exists (select 1 from guioes where id = g1 and client_id = 'numeiro' and formato = 'react' and editorial_status = 'draft'
                          and hooks->0->>'text' = 'Mais uma na saga dos hipócritas.' and corpo = 'Resposta de teste.'));
  j := react_record(cid); g2 := j->>'content_id';
  insert into t values ('gravar outra vez é idempotente', true, g2 = g1 and not (j->>'created')::boolean);
  begin perform react_decide(cid, 'reject', 'risco'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('react gravado não se rejeita (55000)', true, st = '55000');

  -- fontes (admin)
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := react_sources_list('numeiro');
  insert into t values ('propostas primeiro, com a origem', true, j->'items'->0->>'status' = 'proposed' and j->'items'->0->>'origin' = 'coauthor');
  j := react_source_decide((j->'items'->0->>'id')::uuid, 'reject', 'não é do nosso nicho');
  insert into t values ('rejeitar uma proposta', true, j->>'status' = 'rejected');
  j := react_source_add('numeiro', 'tiktok', '@Nova.Conta');
  insert into t values ('adicionar conta manualmente fica ativa', true, j->>'status' = 'active' and j->>'handle' = 'nova.conta');
  begin perform react_source_add('numeiro', 'instagram', 'conta com espaços'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('conta inválida: 22023', true, st = '22023');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  -- o agente nunca desfaz decisões humanas
  execute 'set local role engine_worker';
  j := worker_react_source_upsert('numeiro', jsonb_build_object('handle', 'outra.conta', 'status', 'active', 'score', 90));
  insert into t values ('agente não reativa conta rejeitada', true, j->>'status' = 'rejected');
  j := worker_react_candidate_upsert('numeiro', jsonb_build_object('url', 'https://www.instagram.com/reel/DfXMwD9OLxp/', 'ai', jsonb_build_object('score', 99)));
  st := j->>'status';
  j := worker_react_context('numeiro');
  insert into t values ('contexto traz decisões e links a renovar', true,
    jsonb_array_length(j->'decisions') >= 2 and exists (select 1 from jsonb_array_elements(j->'refresh') x where (x->>'id')::bigint = cid2));
  execute 'reset role';
  insert into t values ('agente atualiza a nota mas não o estado', true, st = 'saved' and (select score from react_candidates where id = cid2) = 99);
  insert into t values ('decisões auditadas', true,
    (select count(*) from audit_events where entity_type = 'react_candidate' and action in ('react.reject', 'react.save', 'react.reopen', 'react.record')) >= 4);

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
