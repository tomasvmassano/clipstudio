-- supabase/tests/w1_review_fixes.sql : correções da revisão de segurança W1 (rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_ed uuid := gen_random_uuid(); u_appr uuid := gen_random_uuid(); u_agadm uuid := gen_random_uuid();
  g guioes; ok int := 0; bad int := 0; res text := ''; r record; st text;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
   (u_ed,'t-ed@test.invalid',now(),'authenticated','authenticated'),(u_appr,'t-appr@test.invalid',now(),'authenticated','authenticated'),
   (u_agadm,'t-agadm@test.invalid',now(),'authenticated','authenticated');
  insert into agency_memberships (organization_id, user_id, agency_role, status) values (org,u_agadm,'agency_member','active');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role, status) values
   ('numeiro',u_ed,'client_staff','contributor','active'),('numeiro',u_appr,'client_staff','manager','active'),
   ('numeiro',u_agadm,'agency_staff','workspace_admin','active');
  update guioes set validado = true, validado_em = now(), status='aprovado' where id = 'numeiro-2026-10-28-30';
  update guioes set status = 'rejeitado', motivo_rejeicao='x' where id = 'numeiro-2026-10-28-29';

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated;
  insert into t values ('sync: validado direto => approved', true, (select editorial_status from guioes where id='numeiro-2026-10-28-30') = 'approved');
  insert into t values ('sync: rejeitado direto => rejected', true, (select editorial_status from guioes where id='numeiro-2026-10-28-29') = 'rejected');
  execute 'set local role authenticated';

  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  g := guiao_update('numeiro-2026-10-28-30', '{"corpo":"texto novo"}'::jsonb);
  insert into t values ('editar guião validado anula a validação', false, g.validado);
  insert into t values ('validado_em limpo', true, g.validado_em is null);
  insert into t values ('versão anterior guardada como validada', true, (g.history->0->>'validado')::boolean);
  begin perform guiao_update('numeiro-2026-10-28-29', '{"status":"x","tema":"t"}'::jsonb); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('status inventado recusado (22023)', true, st = '22023');
  begin perform guiao_update('numeiro-2026-10-28-29', '{"status":"aprovado"}'::jsonb); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('contributor não desfaz rejeição (42501)', true, st = '42501');

  perform set_config('request.jwt.claims', json_build_object('sub', u_appr, 'role','authenticated')::text, true);
  g := guiao_update('numeiro-2026-10-28-30', '{"validado":true}'::jsonb);
  insert into t values ('manager volta a validar', true, g.validado);
  g := guiao_update('numeiro-2026-10-28-30', '{"corpo":"outra","validado":true}'::jsonb);
  insert into t values ('editar e validar no mesmo pedido mantém validado', true, g.validado);

  perform set_config('request.jwt.claims', json_build_object('sub', u_agadm, 'role','authenticated')::text, true);
  begin perform invite_member('numeiro','z1@test.invalid','viewer','agency_staff'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('admin da agência (não dono) não convida staff da agência (42501)', true, st = '42501');
  begin perform invite_member('numeiro','z2@test.invalid','viewer','client_staff'); st := 'ok';
  exception when others then st := sqlstate; end;
  insert into t values ('admin da agência convida staff do cliente', true, st = 'ok');

  execute 'reset role';
  insert into t values ('anulação registada (script.reopened, W2)', true, exists(select 1 from content_transitions where actor_user_id=u_ed and from_status='approved' and to_status='draft'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
