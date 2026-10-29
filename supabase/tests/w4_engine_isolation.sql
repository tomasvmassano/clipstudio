-- supabase/tests/w4_engine_isolation.sql : dados de pesquisa do motor por cliente (W4-03 expand; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  reelA text := (select r.id from reels r join accounts a on a.id = r.account_id where a.client_id='numeiro' and a.role='reference' order by r.outlier desc nulls last limit 1);
  j jsonb; st text; n int; c text; acc text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_eng_b', 'Motor B (teste)', 'motorb', org);
  insert into accounts (id, client_id, role, platform, handle) values ('ws_eng_b-ref', 'ws_eng_b', 'reference', 'instagram', 'criador_b');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_a,'eng-a@test.invalid',now(),'authenticated','authenticated'), (u_b,'eng-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
   ('numeiro', u_a, 'client_staff', 'manager'), ('ws_eng_b', u_b, 'client_staff', 'workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, engine_worker;
  execute 'grant engine_worker to current_user';

  -- o motor escreve como engine_worker
  execute 'set local role engine_worker';
  insert into reels (id, platform, owner, role, url, views, outlier) values ('ENGLEG1', 'instagram', 'itsnumeiro', 'client', 'https://www.instagram.com/reel/ENGLEG1/', 5, 1);
  select client_id, account_id into c, acc from reels where id = 'ENGLEG1';
  insert into t values ('código antigo sem cliente: reel fica no Numeiro e na conta certa', true, c = 'numeiro' and acc = 'numeiro-ig');
  insert into reels (id, platform, owner, role, url, views, outlier, client_id) values ('ENGB1', 'instagram', 'criador_b', 'reference', 'https://www.instagram.com/reel/ENGB1/', 50, 3, 'ws_eng_b')
    on conflict (client_id, id) do update set views = greatest(excluded.views, reels.views);
  select client_id, account_id into c, acc from reels where id = 'ENGB1';
  insert into t values ('motor novo: reel de B fica em B, na conta de B', true, c = 'ws_eng_b' and acc = 'ws_eng_b-ref');
  insert into reels (id, platform, owner, role, url, views, client_id) values ('ENGB1', 'instagram', 'criador_b', 'reference', 'x', 90, 'ws_eng_b')
    on conflict (client_id, id) do update set views = greatest(excluded.views, reels.views);
  insert into t values ('upsert por (cliente, id) atualiza o reel do próprio cliente', true, (select views from reels where id = 'ENGB1') = 90);
  begin insert into reels (id, platform, owner, role, url, client_id) values ('ENGB1', 'instagram', 'outro', 'reference', 'x', 'numeiro')
      on conflict (client_id, id) do nothing; st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('mesmo reel noutro cliente dá erro em vez de misturar (23505, até ao contract)', true, st = '23505');
  insert into t values ('e o reel de B não mudou de dono', true, (select client_id from reels where id = 'ENGB1') = 'ws_eng_b');
  insert into script_analysis (reel_id, tese) values ('ENGB1', 'tese de B');
  insert into t values ('análise herda o cliente do reel', true, (select client_id from script_analysis where reel_id = 'ENGB1') = 'ws_eng_b');
  insert into themes (tema, client_id, active) values ('tema só de B', 'ws_eng_b', true) on conflict (client_id, tema) do update set active = true;
  insert into themes (tema, client_id, active) values ('tema só de B', 'ws_eng_b', false) on conflict (client_id, tema) do update set active = excluded.active;
  insert into t values ('temas com upsert por (cliente, tema)', true, (select count(*) from themes where tema = 'tema só de B') = 1
    and not (select active from themes where tema = 'tema só de B'));
  insert into themes (tema, active) values ('tema antigo', true);
  insert into t values ('tema sem cliente (código antigo) fica no Numeiro', true, (select client_id from themes where tema = 'tema antigo') = 'numeiro');
  insert into meta (k, v, client_id) values ('teste_b', '1', 'ws_eng_b') on conflict (client_id, k) do update set v = excluded.v;
  insert into meta (k, v, client_id) values ('teste_b', '2', 'ws_eng_b') on conflict (client_id, k) do update set v = excluded.v;
  insert into t values ('meta com upsert por (cliente, chave)', true, (select v from meta where k = 'teste_b' and client_id = 'ws_eng_b') = '2'::jsonb);
  insert into generated (hook, guiao) values ('h', 'g');
  insert into daily_reports (data, report, client_id) values (current_date, '{}', 'ws_eng_b');
  insert into t values ('guião e relatório: cliente por omissão e explícito', true,
    (select client_id from generated where hook = 'h' and guiao = 'g' order by id desc limit 1) = 'numeiro'
    and exists (select 1 from daily_reports where client_id = 'ws_eng_b'));
  -- reel com conta de A mas marcado como de B (dados adulterados): não aparece a ninguém
  insert into reels (id, platform, owner, role, url, views, outlier, account_id, client_id) values ('ENGMIX', 'instagram', 'x', 'reference', 'https://x.test/m', 1, 99, 'cobraalive-ig', 'ws_eng_b');
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);
  j := references_discover('numeiro', null, 200);
  insert into t values ('A não descobre o reel marcado como de B, mesmo com conta de A', true, not exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' in ('ENGMIX','ENGB1')));
  insert into t values ('A continua a descobrir os seus', true, jsonb_array_length(j->'reels') > 0);
  begin perform reference_create('numeiro', '{"reel_id":"ENGMIX"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não guarda o reel de B (42501)', true, st = '42501');
  begin perform reference_create('numeiro', '{"reel_id":"ENGB1"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não guarda reel de B por id (42501)', true, st = '42501');
  j := reference_create('numeiro', jsonb_build_object('reel_id', reelA));
  insert into t values ('A guarda o seu reel com métricas e análise do próprio cliente', true, j->'metrics'->>'source' = 'scraper');
  select count(*) into n from reels;
  insert into t values ('tabelas do motor fechadas à API (0 linhas)', true, n = 0 and (select count(*) from script_analysis) = 0 and (select count(*) from themes) = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := references_discover('ws_eng_b', null, 200);
  insert into t values ('B descobre o seu reel e a sua análise', true, exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = 'ENGB1' and z->'analysis'->>'tese' = 'tese de B'));
  insert into t values ('B não vê o reel adulterado (conta de A)', true, not exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = 'ENGMIX'));
  insert into t values ('B não vê reels do Numeiro', true, not exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = reelA));
  execute 'reset role';

  execute 'set local role anon';
  select count(*) into n from reels;
  insert into t values ('anónimo não lê reels (0 linhas)', true, n = 0);
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
