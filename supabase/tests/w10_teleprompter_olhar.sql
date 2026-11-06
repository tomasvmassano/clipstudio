-- supabase/tests/w10_teleprompter_olhar.sql : preferências do olhar no teleprompter (GAZE-01/02; rollback no fim).
do $$
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_a,'t-gaze-a@test.invalid',now(),'authenticated','authenticated'),(u_b,'t-gaze-b@test.invalid',now(),'authenticated','authenticated');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values ('numeiro',u_a,'client_staff','contributor');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role','authenticated')::text, true);

  j := tp_prefs_set('ipad-estudio-01', '{"speed":4,"distance_m":2.5,"screen_in":12.9,"column_fit":true,"focus_pct":18,"phrase_mode":true}');
  insert into t values ('chaves do olhar guardadas', true,
    (j->>'distance_m')::numeric = 2.5 and (j->>'screen_in')::numeric = 12.9 and (j->>'column_fit')::boolean
    and (j->>'focus_pct')::int = 18 and (j->>'phrase_mode')::boolean and tp_prefs_get('ipad-estudio-01') = j);
  j := tp_prefs_set('ipad-estudio-01', '{"distance_m":40,"screen_in":1,"focus_pct":99}');
  insert into t values ('valores limitados ao intervalo', true,
    (j->>'distance_m')::numeric = 6 and (j->>'screen_in')::numeric = 4 and (j->>'focus_pct')::int = 60);
  j := tp_prefs_set('ipad-estudio-01', '{"distance_m":0.01,"focus_pct":0}');
  insert into t values ('mínimos', true, (j->>'distance_m')::numeric = 0.3 and (j->>'focus_pct')::int = 5);
  j := tp_prefs_set('ipad-estudio-01', '{"screen_in":null}');
  insert into t values ('ecrã por definir (null)', true, j ? 'screen_in' and jsonb_typeof(j->'screen_in') = 'null');
  begin perform tp_prefs_set('ipad-estudio-01', '{"distance_m":"longe"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('distância não numérica (22023)', true, st = '22023');
  begin perform tp_prefs_set('ipad-estudio-01', '{"screen_in":"grande"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ecrã não numérico (22023)', true, st = '22023');
  begin perform tp_prefs_set('ipad-estudio-01', '{"focus_pct":"topo"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('linha de foco não numérica (22023)', true, st = '22023');
  begin perform tp_prefs_set('ipad-estudio-01', '{"phrase_mode":"talvez"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('modo frase não booleano (22P02)', true, st = '22P02');
  begin perform tp_prefs_set('ipad-estudio-01', '{"gaze_hack":1}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('chave desconhecida continua recusada (22023)', true, st = '22023');
  j := tp_prefs_set('ipad-estudio-01', '{"speed":3,"mirror_h":true,"keys":{"play":[" "]}}');
  insert into t values ('formato antigo (código em main) continua a funcionar', true,
    (j->>'speed')::int = 3 and (j->>'mirror_h')::boolean and not j ? 'distance_m');
  j := tp_prefs_set('portatil-00001', '{"distance_m":1,"screen_in":15.6}');
  insert into t values ('cada dispositivo tem a sua distância', true,
    (tp_prefs_get('portatil-00001')->>'screen_in')::numeric = 15.6 and not tp_prefs_get('ipad-estudio-01') ? 'screen_in');

  -- outra pessoa (sem acesso ao workspace) não vê nem escreve as do A
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  insert into t values ('B não lê as preferências de A', true, tp_prefs_get('portatil-00001') is null);
  perform tp_prefs_set('portatil-00001', '{"distance_m":3}');
  insert into t values ('B grava as suas sem tocar nas de A (RLS)', true,
    (select count(*) from teleprompter_prefs) = 1 and (select (prefs->>'distance_m')::numeric from teleprompter_prefs) = 3);
  execute 'reset role';
  insert into t values ('as de A ficaram iguais', true,
    (select (prefs->>'screen_in')::numeric from teleprompter_prefs where user_id = u_a and device_id = 'portatil-00001') = 15.6);

  -- anónimo (código de equipa) não guarda no servidor
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin perform tp_prefs_set('ipad-estudio-01', '{"distance_m":2}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não guarda preferências (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
