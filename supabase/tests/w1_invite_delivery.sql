-- supabase/tests/w1_invite_delivery.sql : link do convite, reenviar, recusar (W1-14, FR-13-01; rollback no fim).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_adm_a uuid := gen_random_uuid(); u_adm_b uuid := gen_random_uuid(); u_ag_adm uuid := gen_random_uuid();
  u_new uuid := gen_random_uuid();
  inv_a uuid; inv_b uuid; inv_ag uuid; inv_x uuid; j jsonb; tok text; tok2 text; st text; ok int := 0; bad int := 0; res text := ''; r record;
begin
  insert into clients (id, name, handle, organization_id) values ('ws_d_a', 'Entrega A', 'da', org), ('ws_d_b', 'Entrega B', 'db', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'d-own@test.invalid'),(u_adm_a,'d-adm-a@test.invalid'),(u_adm_b,'d-adm-b@test.invalid'),(u_ag_adm,'d-ag-adm@test.invalid'),
    (u_new,'d-novo@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag_adm, 'agency_admin');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('ws_d_a', u_adm_a, 'client_staff', 'workspace_admin'), ('ws_d_b', u_adm_b, 'client_staff', 'workspace_admin');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- admin do cliente A convida e gera o link
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm_a, 'role','authenticated')::text, true);
  inv_a := invite_member('ws_d_a', 'd-novo@test.invalid', 'contributor');
  j := invitation_issue_link(inv_a); tok := j->>'token';
  insert into t values ('link gerado com token, email e destino', true, length(tok) = 48 and j->>'email' = 'd-novo@test.invalid' and j->>'target' = 'Entrega A' and (j->>'sent_count')::int = 1);
  begin perform invitation_issue_link(inv_a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('reenviar logo a seguir é travado (PT429)', true, st = 'PT429');

  -- admin do cliente B não mexe no convite de A
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm_b, 'role','authenticated')::text, true);
  begin perform invitation_issue_link(inv_a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin de B não gera link do convite de A (42501)', true, st = '42501');
  inv_b := invite_member('ws_d_b', 'outra@test.invalid', 'viewer');

  -- quem abre o link, sem sessão
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := invitation_preview(tok);
  insert into t values ('link mostra o convite a quem o abre', true, j->>'status' = 'pending' and j->>'target' = 'Entrega A' and j->>'email' = 'd-novo@test.invalid'
    and j->>'inviter' = 'd-adm-a@test.invalid');
  insert into t values ('token errado não revela nada', true, invitation_preview(repeat('a', 48)) = '{"status":"invalid"}'::jsonb
    and invitation_preview('curto') = '{"status":"invalid"}'::jsonb);
  begin perform invitation_issue_link(inv_a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anónimo não gera links (42501)', true, st = '42501');
  execute 'reset role';

  -- reenviar troca o token: o link antigo deixa de valer
  update invitations set last_sent_at = now() - interval '2 minutes' where id = inv_a;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm_a, 'role','authenticated')::text, true);
  tok2 := invitation_issue_link(inv_a)->>'token';
  insert into t values ('reenviar dá um link novo', true, tok2 <> tok and invitation_preview(tok2)->>'status' = 'pending');
  insert into t values ('o link antigo deixa de valer', true, invitation_preview(tok)->>'status' = 'invalid');

  -- recusar pelo link
  execute 'reset role'; execute 'set local role anon';
  st := invitation_decline(tok2);
  insert into t values ('recusar pelo link', true, st = 'declined' and invitation_preview(tok2)->>'status' = 'declined');
  insert into t values ('recusar outra vez não muda nada', true, invitation_decline(tok2) = 'declined');
  begin perform invitation_decline(repeat('b', 48)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('recusar com link inválido (22023)', true, st = '22023');
  execute 'reset role';
  insert into t values ('recusa fica no histórico', true, exists (select 1 from audit_events where entity_id = inv_a::text and action = 'invitation.declined'));
  insert into t values ('envios ficam no histórico', true, (select count(*) from audit_events where entity_id = inv_a::text and action = 'invitation.sent') = 2);

  -- quem recusou e depois entra não fica com acesso
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_new, 'role','authenticated')::text, true);
  insert into t values ('convite recusado não é aceite ao entrar', true, accept_invitations() = 0);
  execute 'reset role';
  insert into t values ('sem acesso ao cliente depois de recusar', true, not exists (select 1 from workspace_access where user_id = u_new));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm_a, 'role','authenticated')::text, true);
  begin perform invitation_issue_link(inv_a); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('convite recusado não se reenvia (22023)', true, st = '22023');
  insert into t values ('lista da equipa mostra o convite como recusado', true,
    exists (select 1 from jsonb_array_elements(workspace_team('ws_d_a')->'invitations') x where x->>'id' = inv_a::text and x->>'status' = 'declined'));

  -- convite expirado: reenviar renova a validade
  inv_x := invite_member('ws_d_a', 'expirado@test.invalid', 'viewer');
  execute 'reset role';
  update invitations set expires_at = now() - interval '1 day' where id = inv_x;
  execute 'set local role authenticated';
  insert into t values ('lista mostra o expirado', true,
    exists (select 1 from jsonb_array_elements(workspace_team('ws_d_a')->'invitations') x where x->>'id' = inv_x::text and x->>'status' = 'expired'));
  j := invitation_issue_link(inv_x);
  insert into t values ('reenviar um expirado renova 14 dias', true, (j->>'expires_at')::timestamptz > now() + interval '13 days');
  execute 'reset role';
  update invitations set last_sent_at = now() - interval '2 minutes', sent_count = 5 where id = inv_x;
  execute 'set local role authenticated';
  begin perform invitation_issue_link(inv_x); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('no máximo 5 envios por convite (PT429)', true, st = 'PT429');

  -- convites da agência
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  inv_ag := agency_invite('d-staff@test.invalid', 'agency_member');
  j := invitation_issue_link(inv_ag);
  insert into t values ('dono gera link de convite para a agência', true, j->>'kind' = 'agency' and j->>'token' is not null);
  insert into t values ('lista da agência traz estado e envios', true,
    exists (select 1 from jsonb_array_elements(agency_team()->'invites') x where x->>'id' = inv_ag::text and x->>'status' = 'pending' and (x->>'sent_count')::int = 1));
  begin perform invitation_issue_link(inv_b); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('dono da agência pode reenviar convites dos clientes', true, st = 'none');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag_adm, 'role','authenticated')::text, true);
  begin perform invitation_issue_link(inv_ag); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin da agência sem team.invite não reenvia (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm_a, 'role','authenticated')::text, true);
  begin perform invitation_issue_link(inv_ag); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não mexe em convites da agência (42501)', true, st = '42501');
  execute 'reset role';

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
