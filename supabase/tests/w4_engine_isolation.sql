-- supabase/tests/w4_engine_isolation.sql : dados de pesquisa do motor por cliente (W4-03 contract; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  reelA text := (select r.id from reels r join accounts a on a.id = r.account_id where a.client_id='numeiro' and a.role='reference' order by r.outlier desc nulls last limit 1);
  temaA text := (select tema from themes where client_id = 'numeiro' limit 1);
  n_a int := (select count(distinct x.id) from reels x join accounts y on y.id = x.account_id where y.client_id = 'numeiro' and x.client_id = 'numeiro' and y.role = 'client');
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

  -- o motor escreve como engine_worker, com o cliente na sessão (o PgDB grava engine.client_id ao ligar)
  execute 'set local role engine_worker';
  perform set_config('engine.client_id', 'ws_eng_b', true);
  select count(*) into n from reels;
  insert into t values ('worker em B não vê reels do Numeiro', true, n = 0);
  insert into reels (client_id, id, platform, owner, role, url, views, outlier) values ('ws_eng_b', 'ENGB1', 'instagram', 'criador_b', 'reference', 'https://www.instagram.com/reel/ENGB1/', 50, 3)
    on conflict (client_id, id) do update set views = greatest(excluded.views, reels.views);
  select client_id, account_id into c, acc from reels where id = 'ENGB1';
  insert into t values ('reel de B fica em B, na conta de B', true, c = 'ws_eng_b' and acc = 'ws_eng_b-ref');
  insert into reels (client_id, id, platform, owner, role, url, views) values ('ws_eng_b', 'ENGB1', 'instagram', 'criador_b', 'reference', 'x', 90)
    on conflict (client_id, id) do update set views = greatest(excluded.views, reels.views);
  insert into t values ('upsert por (cliente, id) atualiza o reel do próprio cliente', true, (select views from reels where id = 'ENGB1') = 90);
  insert into reels (client_id, id, platform, owner, role, url, views) values ('ws_eng_b', reelA, 'instagram', 'criador_b', 'reference', 'x', 1);
  insert into t values ('o mesmo reel do Numeiro entra em B como cópia própria', true, (select count(*) from reels where id = reelA) = 1);
  insert into script_analysis (client_id, reel_id, tese) values ('ws_eng_b', 'ENGB1', 'tese de B');
  insert into themes (client_id, tema, active) values ('ws_eng_b', temaA, true) on conflict (client_id, tema) do update set active = true;
  insert into themes (client_id, tema, active) values ('ws_eng_b', temaA, false) on conflict (client_id, tema) do update set active = excluded.active;
  insert into t values ('tema com o mesmo nome do Numeiro, upsert por (cliente, tema)', true, (select count(*) from themes) = 1 and not (select active from themes));
  insert into meta (client_id, k, v) values ('ws_eng_b', 'padroes_hook', '1') on conflict (client_id, k) do update set v = excluded.v;
  insert into meta (client_id, k, v) values ('ws_eng_b', 'padroes_hook', '2') on conflict (client_id, k) do update set v = excluded.v;
  insert into t values ('meta com a mesma chave do Numeiro', true, (select v from meta where k = 'padroes_hook') = '2'::jsonb);
  insert into daily_reports (client_id, data, report) values ('ws_eng_b', current_date, '{}');
  begin insert into reels (client_id, id, url) values ('numeiro', 'ENGX', 'u'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('worker em B não escreve no Numeiro (42501)', true, st = '42501');
  begin insert into themes (tema) values ('sem cliente'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem cliente é recusado', true, st in ('23502', '42501'));
  perform set_config('engine.client_id', '', true);
  select count(*) into n from reels;
  insert into t values ('worker sem cliente na sessão não vê nada', true, n = 0);
  execute 'reset role';

  insert into t values ('Numeiro intacto (reel, tema e meta próprios)', true,
    (select count(*) from reels where id = reelA and client_id = 'numeiro') = 1 and (select active from themes where client_id = 'numeiro' and tema = temaA) is not null);
  begin insert into generated (client_id, hook, theme_id) values ('ws_eng_b', 'h', (select id from themes where client_id = 'numeiro' limit 1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('guião de B não aponta para tema do Numeiro (23503)', true, st = '23503');
  begin insert into script_analysis (client_id, reel_id) values ('ws_eng_b', 'NAOEXISTE'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('análise de B só para reel de B (23503)', true, st = '23503');
  begin insert into reels (id, url) values ('ENGNULL', 'u'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('reel sem cliente nem conta recusado (23502)', true, st = '23502');
  -- reel de B com a conta de A (dados adulterados): não aparece a ninguém
  insert into reels (client_id, id, platform, owner, role, url, views, outlier, account_id) values ('ws_eng_b', 'ENGMIX', 'instagram', 'x', 'reference', 'https://x.test/m', 1, 99, 'cobraalive-ig');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);
  j := references_discover('numeiro', null, 200);
  insert into t values ('A não descobre reels de B, mesmo com conta de A', true, not exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' in ('ENGMIX','ENGB1')));
  insert into t values ('A descobre o seu reel com a análise de A', true, exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = reelA and z->>'url' <> 'x'));
  begin perform reference_create('numeiro', '{"reel_id":"ENGMIX"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não guarda o reel de B (42501)', true, st = '42501');
  j := reference_create('numeiro', jsonb_build_object('reel_id', reelA));
  insert into t values ('A guarda o seu reel com as suas métricas', true, j->'metrics'->>'source' = 'scraper' and (j->'metrics'->>'views')::bigint <> 1);
  begin perform 1 from reels limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabelas do motor fechadas à API (42501)', true, st = '42501');
  insert into t values ('Desempenho de A não conta reels de B', true, (desempenho('numeiro')->'kpi'->>'reels')::int = n_a);
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  j := references_discover('ws_eng_b', null, 200);
  insert into t values ('B descobre o seu reel e a sua análise', true, exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = 'ENGB1' and z->'analysis'->>'tese' = 'tese de B'));
  insert into t values ('B vê a sua cópia do reel do Numeiro, com os seus números', true, exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = reelA and (z->>'views')::int = 1));
  insert into t values ('B não vê o reel adulterado', true, not exists (select 1 from jsonb_array_elements(j->'reels') z where z->>'id' = 'ENGMIX'));
  execute 'reset role';

  execute 'set local role anon';
  begin perform 1 from reels limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem acesso a reels (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
