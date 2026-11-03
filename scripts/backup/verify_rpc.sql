-- scripts/backup/verify_rpc.sql: a app continua a funcionar e isolada depois do restauro (QA-15).
-- Corre numa base restaurada, como as pessoas do ensaio (scripts/backup/activity.sql), e termina com RAISE para
-- fazer ROLLBACK: nada fica escrito. Variável psql partial=1 quando a base é o restauro de um só cliente (bk_a).
\if :{?partial}
\else
  \set partial 0
\endif
select set_config('drill.partial', :'partial', false) \gset
do $$
declare
  partial boolean := current_setting('drill.partial') = '1';
  u_own uuid := '00000000-0000-4000-8000-00000000b001'; u_sa uuid := '00000000-0000-4000-8000-00000000b002';
  u_ca uuid := '00000000-0000-4000-8000-00000000b003'; u_cb uuid := '00000000-0000-4000-8000-00000000b004';
  j jsonb; st text; ok int; bad int; res text; max_src bigint; g guioes;
  hits_a int; hits_b int;
begin
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  max_src := (select max(id) from ideas);

  -- dados de base presentes
  insert into t values ('cliente A restaurado', true, exists (select 1 from clients where id = 'bk_a'));
  insert into t values ('guiões de A restaurados', true, (select count(*) from guioes where client_id = 'bk_a') > 0);
  if partial then
    insert into t values ('restauro parcial: cliente B ausente', true, not exists (select 1 from clients where id <> 'bk_a'));
    insert into t values ('restauro parcial: pessoa de B ausente', true, not exists (select 1 from auth.users where id = u_cb));
    insert into t values ('restauro parcial: nenhuma linha de outro cliente', true,
      not exists (select 1 from guioes where client_id <> 'bk_a') and not exists (select 1 from audit_events where workspace_id <> 'bk_a')
      and not exists (select 1 from tasks where workspace_id <> 'bk_a') and not exists (select 1 from ideas where client_id <> 'bk_a'));
  else
    insert into t values ('cliente B restaurado', true, exists (select 1 from clients where id = 'bk_b'));
  end if;

  -- autorização central
  insert into t values ('staff A lê A', true, _authorize('scripts.read', 'bk_a', u_sa));
  insert into t values ('staff A não lê B', false, _authorize('scripts.read', 'bk_b', u_sa));
  insert into t values ('cliente A não lê B', false, _authorize('scripts.read', 'bk_b', u_ca));
  insert into t values ('capacidade desconhecida recusada', false, _authorize('scripts.fly', 'bk_a', u_own));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role', 'authenticated')::text, true);
  j := public.my_context();
  insert into t values ('my_context de A só lista A', true,
    jsonb_array_length(j->'workspaces') = 1 and j->'workspaces'->0->>'id' = 'bk_a');
  j := public.search_global('alfarrobeira');
  hits_a := (select count(*) from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i);
  insert into t values ('A encontra o termo de A', true, hits_a > 0);
  j := public.search_global('zebraquantica');
  insert into t values ('QA-12: A não encontra o termo exclusivo de B', true, jsonb_array_length(j->'groups') = 0);
  begin perform public.search_global('zebraquantica', 'bk_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A a forçar o cliente B na pesquisa: 42501', true, st = '42501');
  begin perform public.task_create('bk_b', '{"title":"intrusão"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('A não cria tarefas em B: 42501', true, st = '42501');
  begin perform 1 from public.workspace_access limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tabela de acessos fechada à API depois do restauro (42501)', true, st = '42501');
  -- escrita depois do restauro: sequências e defaults no sítio (sem colisão de chave)
  begin
    j := public.source_create('bk_a', '{"titulo":"Fonte depois do restauro","fonte_url":"https://exemplo.test/restauro"}');
    insert into t values ('escrever depois do restauro: id novo acima do máximo restaurado', true, (j->>'id')::bigint > coalesce(max_src, 0));
  exception when others then insert into t values ('escrever depois do restauro (' || sqlerrm || ')', true, false); end;
  begin
    g := public.content_create('bk_a', '{"corpo":"Guião depois do restauro"}');
    g := public.content_transition(g.id, 'in_review', null, null, null);
    insert into t values ('fluxo editorial depois do restauro', true, g.editorial_status = 'in_review');
  exception when others then insert into t values ('fluxo editorial depois do restauro (' || sqlerrm || ')', true, false); end;

  if not partial then
    perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role', 'authenticated')::text, true);
    j := public.search_global('zebraquantica');
    hits_b := (select count(*) from jsonb_array_elements(j->'groups') x, jsonb_array_elements(x->'items') i);
    insert into t values ('B encontra o termo de B', true, hits_b > 0);
    j := public.search_global('alfarrobeira');
    insert into t values ('B não encontra o termo exclusivo de A', true, jsonb_array_length(j->'groups') = 0);
  end if;
  execute 'reset role';
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{}', true);
  begin perform 1 from public.clients limit 1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo sem acesso às tabelas', true, st = '42501');
  execute 'reset role';

  select count(*) filter (where expected is not distinct from got), count(*) filter (where expected is distinct from got) into ok, bad from t;
  select string_agg(case when expected is not distinct from got then 'PASS ' else 'FAIL ' end || name, E'\n' order by name) into res from t;
  raise exception E'RESULT ok=% fail=%\n%', ok, bad, res;
end $$;
