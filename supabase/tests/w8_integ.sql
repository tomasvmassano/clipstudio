-- supabase/tests/w8_integ.sql : centro de integrações (FR-15-03, FR-17-16, FR-21-01). Só estados reais: contas sociais por
-- ligar, revogar real e idempotente, recolha por scraping e motor de agentes lidos da base, testar só onde se testa algo
-- real. Isolamento entre clientes, flag, código de equipa, acesso removido, nunca expor tokens. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_mb uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid();
  u_cc uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  cfg uuid := (select id from agent_config_versions where workspace_id = 'numeiro' order by created_at desc limit 1);
  j jsonb; x jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_integ_b', 'Integ B', 'integb', org, 'Europe/Lisbon');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select v.x, v.e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'integ-own@test.invalid'),(u_ag,'integ-ag@test.invalid'),(u_mb,'integ-mb@test.invalid'),(u_ca,'integ-ca@test.invalid'),
    (u_cc,'integ-cc@test.invalid'),(u_vw,'integ-vw@test.invalid'),(u_cb,'integ-cb@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_mb, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_cc, 'client_staff', 'contributor'),
    ('numeiro', u_vw, 'client_staff', 'viewer'), ('ws_integ_b', u_cb, 'client_staff', 'workspace_admin');
  insert into accounts (id, client_id, role, platform, handle, label) values ('ws_integ_b-ig', 'ws_integ_b', 'client', 'instagram', 'integb', 'integb · Instagram');
  insert into social_accounts (account_id, workspace_id) values ('ws_integ_b-ig', 'ws_integ_b') on conflict do nothing;
  insert into reels (client_id, id, platform, owner, role, url, views, account_id, taken_at, updated_at)
  values ('ws_integ_b', 'INTEGB1', 'instagram', 'integb', 'client', 'https://www.instagram.com/reel/INTEGB1/', 10, 'ws_integ_b-ig', now() - interval '5 days', now() - interval '3 days');
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── flag desligada ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada (staff da agência): 55000', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := integrations_overview('numeiro');
  insert into t values ('fase owner: o dono da agência vê 5 integrações do cliente', true, jsonb_array_length(j->'items') = 5 and (j->>'can_manage')::boolean);
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'integrations.center', org, w, 'all' from unnest(array['numeiro','ws_integ_b']) w;
  execute 'set local role authenticated';

  -- ── leitura e papéis ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := integrations_overview('numeiro');
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'instagram');
  insert into t values ('gestor lê, mas não gere', true, j ? 'items' and not (j->>'can_manage')::boolean);
  insert into t values ('Instagram por ligar, com contas e limites', true,
    x->>'state' = 'por_ligar' and jsonb_array_length(x->'detail'->'accounts') >= 1 and (x->'detail'->'limits'->>'max_posts')::int = 100);
  insert into t values ('ligar e renovar indisponíveis com o motivo', true,
    (select bool_and(not (a->>'available')::boolean and coalesce(a->>'reason', '') <> '') from jsonb_array_elements(x->'actions') a where a->>'key' in ('ligar', 'renovar'))
    and (select count(*) from jsonb_array_elements(x->'actions') a where a->>'key' in ('ligar', 'renovar')) = 2);
  insert into t values ('revogar fica indisponível para quem só lê', true,
    exists (select 1 from jsonb_array_elements(x->'actions') a where a->>'key' = 'revogar' and not (a->>'available')::boolean));
  insert into t values ('âmbitos planeados do PRD (PLAT-02/03)', true, x->'planned_permissions' ? 'instagram_business_manage_insights');
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'scraping');
  insert into t values ('scraping em dia, com última sincronização real', true, x->>'state' = 'em_dia' and x->>'last_sync_at' is not null
    and exists (select 1 from jsonb_array_elements(x->'detail'->'accounts') a where a->>'account_id' = 'numeiro-ig' and (a->>'reels')::int = 100));
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'agents_worker');
  insert into t values ('worker por alojar sem contacto nem execuções', true, x->>'state' = 'por_alojar' and x->'detail'->>'worker_seen_at' is null);
  insert into t values ('integrações da agência não aparecem no cliente', true,
    not exists (select 1 from jsonb_array_elements(j->'items') i where i->>'scope' <> 'cliente'));

  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não vê integrações (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não vê integrações (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_mb, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem atribuição não vê (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê integrações de A (42501)', true, st = '42501');
  j := integrations_overview('ws_integ_b');
  insert into t values ('cliente B vê só as suas contas', true, j::text not like '%numeiro-ig%' and j::text not like '%"numeiro"%'
    and exists (select 1 from jsonb_array_elements(j->'items') i, jsonb_array_elements(i->'detail'->'accounts') a where a->>'account_id' = 'ws_integ_b-ig'));
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'scraping');
  insert into t values ('scraping de B atrasado (3 dias > 48 h)', true, x->>'state' = 'atrasada' and x->>'health' = 'aviso');
  insert into t values ('YouTube sem contas em B', true,
    (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'youtube') = 'sem_contas');
  begin perform integrations_test('numeiro', 'scraping'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não testa em A (42501)', true, st = '42501');
  begin perform integrations_social_revoke('ws_integ_b', 'numeiro-ig', 'motivo de teste'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não revoga conta de A pelo seu cliente (P0002)', true, st = 'P0002');
  begin perform integrations_social_revoke('numeiro', 'numeiro-ig', 'motivo de teste'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não revoga em A (42501)', true, st = '42501');

  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform integrations_overview('numeiro', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não vê integrações (42501)', true, st = '42501');
  begin perform integrations_agency(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('anon não chama a vista da agência', true, st = '42501');

  -- ── revogar (FR-15-03, FR-21-01) ──
  execute 'reset role';
  -- O serviço de OAuth futuro é quem liga contas; aqui imita-se o estado que ele deixará.
  update social_accounts set connection_state = 'ligada', token_ref = 'vault:22222222-2222-2222-2222-222222222222',
    scopes = array['instagram_business_basic'], token_expires_at = now() + interval '50 days', connected_at = now() - interval '1 day', connected_label = 'teste'
   where account_id = 'numeiro-ig';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := integrations_overview('numeiro');
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'instagram');
  insert into t values ('ligada aparece com âmbitos e validade, sem token', true,
    exists (select 1 from jsonb_array_elements(x->'detail'->'accounts') a where a->>'account_id' = 'numeiro-ig' and a->>'connection_state' = 'ligada'
      and (a->>'credential_stored')::boolean and a->'scopes' ? 'instagram_business_basic' and (a->>'can_revoke')::boolean));
  insert into t values ('nunca expõe token_ref nem a referência do Vault', true, j::text not like '%vault:%' and j::text not like '%token_ref%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform integrations_social_revoke('numeiro', 'numeiro-ig', 'motivo de teste'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não revoga (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform integrations_social_revoke('numeiro', 'numeiro-ig', 'motivo de teste'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gestor não revoga (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform integrations_social_revoke('numeiro', 'numeiro-ig', ' '); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revogar sem motivo (22023)', true, st = '22023');
  j := integrations_social_revoke('numeiro', 'numeiro-ig', 'Conta entregue ao cliente');
  insert into t values ('admin do cliente revoga', true, (j->>'changed')::boolean and j->>'connection_state' = 'revogada' and (j->>'secret_purge_pending')::boolean);
  j := integrations_social_revoke('numeiro', 'numeiro-ig', 'outra vez');
  insert into t values ('revogar outra vez é idempotente', true, not (j->>'changed')::boolean);
  begin perform integrations_social_revoke('numeiro', 'numeiro-tt-nao-existe', 'motivo'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conta inexistente (P0002)', true, st = 'P0002');
  execute 'reset role';
  insert into t values ('token_ref limpo e estado revogada', true,
    (select connection_state = 'revogada' and token_ref is null and token_expires_at is null and scopes = '{}' from social_accounts where account_id = 'numeiro-ig'));
  insert into t values ('pedido de purga do segredo registado uma vez', true,
    (select count(*) from integration_secret_purges where account_id = 'numeiro-ig' and purged_at is null) = 1);
  insert into t values ('auditoria com motivo, uma só vez, sem token', true,
    (select count(*) from audit_events where action = 'integrations.social_revoked' and entity_id = 'numeiro-ig') = 1
    and exists (select 1 from audit_events where action = 'integrations.social_revoked' and after->>'reason' = 'Conta entregue ao cliente'
                and before::text not like '%vault:%')
    and (select count(*) from domain_events where type = 'integration.social_revoked') = 1);
  -- por ligar não se revoga; ligada com validade passada conta como expirada
  insert into accounts (id, client_id, role, platform, handle, label) values ('numeiro-yt-integ', 'numeiro', 'client', 'youtube', 'integyt', 'integyt · YouTube');
  insert into social_accounts (account_id, workspace_id, connection_state, token_ref, token_expires_at)
  values ('numeiro-yt-integ', 'numeiro', 'ligada', 'vault:33333333-3333-3333-3333-333333333333', now() - interval '1 hour');
  insert into accounts (id, client_id, role, platform, handle, label) values ('numeiro-tt-integ', 'numeiro', 'client', 'tiktok', 'integtt', 'integtt · TikTok');
  insert into social_accounts (account_id, workspace_id) values ('numeiro-tt-integ', 'numeiro');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform integrations_social_revoke('numeiro', 'numeiro-tt-integ', 'motivo');
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('conta por ligar: nada para revogar (22023)', true, st = '22023');
  j := integrations_overview('numeiro');
  x := (select i from jsonb_array_elements(j->'items') i where i->>'key' = 'youtube');
  insert into t values ('token com validade passada aparece expirado', true, x->>'state' = 'expirada'
    and exists (select 1 from jsonb_array_elements(x->'detail'->'accounts') a where a->>'account_id' = 'numeiro-yt-integ' and a->>'connection_state' = 'expirada' and (a->>'can_revoke')::boolean));
  insert into t values ('Instagram revogada', true,
    (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'instagram') in ('revogada', 'por_ligar'));

  -- ── testar (só scraping e worker) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform integrations_test('numeiro', 'scraping'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gestor não testa (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := integrations_test('numeiro', 'scraping');
  insert into t values ('testar a recolha: ok com a frescura real', true, j->>'outcome' = 'ok' and j->>'state' = 'em_dia' and not (j->>'reused')::boolean);
  j := integrations_test('numeiro', 'scraping');
  insert into t values ('testar outra vez em 30 s reutiliza o teste', true, (j->>'reused')::boolean);
  begin perform integrations_test('numeiro', 'instagram'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('Instagram não se testa (22023)', true, st = '22023');
  begin perform integrations_test('numeiro', 'google_drive'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('integração da agência não se testa no cliente (22023)', true, st = '22023');
  begin perform integrations_test('numeiro', 'nao_existe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('integração desconhecida: falha fechada (22023)', true, st = '22023');
  j := integrations_test('numeiro', 'agents_worker');
  insert into t values ('testar o worker por alojar: falhou', true, j->>'outcome' = 'falhou' and j->>'state' = 'por_alojar');
  j := integrations_overview('numeiro');
  insert into t values ('último teste aparece no item', true,
    (select i->'last_check'->>'outcome' from jsonb_array_elements(j->'items') i where i->>'key' = 'scraping') = 'ok');
  execute 'reset role';
  insert into t values ('um teste por pedido, com auditoria', true,
    (select count(*) from integration_checks where workspace_id = 'numeiro') = 2
    and (select count(*) from audit_events where action = 'integrations.tested' and workspace_id = 'numeiro') = 2);
  begin update integration_checks set outcome = 'ok' where workspace_id = 'numeiro'; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('testes só de acrescentar', true, st = '42501');

  -- worker: execução falhada sem contacto = parado; com contacto recente = ativo
  if cfg is not null then
    insert into agent_jobs (workspace_id, kind, idempotency_key, status, config_version_id, requested_kind, started_at, finished_at, last_error, attempts)
    values ('numeiro', 'daily_pipeline', 'integ-test-1', 'failed', cfg, 'system', now() - interval '1 hour', now() - interval '50 minutes', 'erro de teste', 1);
  end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  x := (select i from jsonb_array_elements(integrations_overview('numeiro')->'items') i where i->>'key' = 'agents_worker');
  insert into t values ('execução recente sem worker: parado, com o erro', true, cfg is null or (x->>'state' = 'parado'
    and x->'detail'->'last_job'->>'status' = 'failed' and x->'detail'->'last_job'->>'last_error' = 'erro de teste'));
  execute 'reset role';
  insert into agent_workers (id, kinds, last_seen, version) values ('worker-integ-1', array['daily_pipeline'], now(), 'teste');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  x := (select i from jsonb_array_elements(integrations_overview('numeiro')->'items') i where i->>'key' = 'agents_worker');
  insert into t values ('worker com contacto recente: ativo, sem o identificar ao cliente', true,
    x->>'state' = 'ativo' and x::text not like '%worker-integ-1%');

  -- ── vista da agência (só o dono) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := integrations_agency();
  insert into t values ('dono vê integrações da agência por ligar', true,
    (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'google_drive') = 'por_ligar'
    and (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'resend') = 'por_ligar'
    and (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'cloudflare_r2') = 'por_ligar'
    and (select i->>'state' from jsonb_array_elements(j->'items') i where i->>'key' = 'platform_limits') = 'em_dia');
  insert into t values ('dono vê o estado de cada cliente e os workers', true,
    exists (select 1 from jsonb_array_elements(j->'clients') c where c->>'id' = 'ws_integ_b' and c->'scraping'->>'state' = 'atrasada')
    and exists (select 1 from jsonb_array_elements(j->'clients') c where c->>'id' = 'numeiro' and (c->'social'->>'revogada')::int = 1 and (c->'social'->>'expirada')::int = 1)
    and exists (select 1 from jsonb_array_elements(j->'workers') w where w->>'id' = 'worker-integ-1' and (w->>'active')::boolean)
    and jsonb_array_length(j->'limits') = 3 and j::text not like '%vault:%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform integrations_agency(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência não vê a vista da agência (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform integrations_agency(); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('equipa do cliente não vê a vista da agência (42501)', true, st = '42501');

  -- ── flag desligada só num cliente; acesso removido ──
  execute 'reset role';
  update feature_flags set stage = 'off' where key = 'integrations.center' and workspace_id = 'ws_integ_b';
  delete from workspace_access where user_id = u_ag;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform integrations_overview('ws_integ_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada em B: 55000', true, st = '55000');
  begin perform integrations_test('ws_integ_b', 'scraping'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada em B: testar recusa', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform integrations_overview('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido deixa de ler (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.integration_types', 'select') and not has_table_privilege('authenticated', 'public.integration_checks', 'select')
    and not has_table_privilege('anon', 'public.integration_secret_purges', 'select'));
  insert into t values ('capacidades e flag registadas', true,
    (select count(*) from capabilities where key in ('integrations.read', 'integrations.manage', 'integrations.agency.read') and status = 'ativo') = 3
    and not exists (select 1 from role_capabilities where capability = 'integrations.read' and role in ('contributor', 'reviewer', 'viewer'))
    and exists (select 1 from feature_flag_defs where key = 'integrations.center' and default_stage = 'owner')
    and not public.legacy_can(tok, 'integrations.read', 'numeiro'));
  insert into t values ('funções auxiliares fechadas', true,
    not has_function_privilege('authenticated', 'public._integ_item(text, integration_types, boolean)', 'execute')
    and not has_function_privilege('anon', 'public.integrations_agency()', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
