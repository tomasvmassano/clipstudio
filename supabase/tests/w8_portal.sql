-- supabase/tests/w8_portal.sql : portal do cliente (SCALE-08; R-13, R-14; TEAM-10; PUB-06; ADR-0041).
-- Acesso e flag, isolamento entre clientes, staff da agência sem atribuição, staff atribuído "como o cliente vê", cliente só
-- A, código de equipa, acesso removido, blocos indisponíveis com motivo, nada de dinheiro, ações pelas RPCs existentes e
-- um bloco com erro não derruba o portal. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_un uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid();
  u_cc uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date + 3; j jsonb; b jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record;
  g1 text := 'numeiro-2026-10-28-01'; g2 text := 'numeiro-2026-10-28-02'; p1 uuid; rq bigint; n int; lock int;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_portal_b', 'Portal B', 'portalb', org, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'portal-own@test.invalid'),(u_ag,'portal-ag@test.invalid'),(u_un,'portal-un@test.invalid'),(u_ca,'portal-ca@test.invalid'),
    (u_cc,'portal-cc@test.invalid'),(u_vw,'portal-vw@test.invalid'),(u_cb,'portal-cb@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_un, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_cc, 'client_staff', 'contributor'),
    ('numeiro', u_vw, 'client_staff', 'viewer'), ('ws_portal_b', u_cb, 'client_staff', 'workspace_admin');
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, origem, status, editorial_status)
  values ('ws_portal_b-x-01', 'ws_portal_b', current_date, 1, 'Segredo B', '[{"text":"Hook B"}]', 'Corpo B', 'fixture', 'aprovado', 'in_review');
  -- contrato com dinheiro: os volumes saem, os valores nunca
  insert into client_contracts (workspace_id, version, amount, currency, billing_period, scripts_per_month, videos_per_month, platforms, deadline_days,
                                effective_from, payment_status, notes, renewal_on, starts_on)
  values ('numeiro', 1, 98765.43, 'AED', 'mensal', 40, 30, array['instagram','tiktok'], 5, current_date - 40, 'vencido', 'Nota comercial secreta',
          current_date + 100, current_date - 40);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── flag desligada (fase owner): só o dono da agência ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform portal_home('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag na fase owner: admin do cliente recebe 55000', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform portal_home('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag na fase owner: staff da agência recebe 55000', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('dono da agência vê o portal como o cliente vê', true, j->'viewer'->>'side' = 'agencia' and (j->'viewer'->>'as_client')::boolean);
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'client.portal', org, w, 'all' from unnest(array['numeiro','ws_portal_b']) w;
  execute 'set local role authenticated';

  -- ── isolamento ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform portal_home('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não abre o portal do A (42501)', true, st = '42501');
  begin perform portal_block('numeiro', 'deliveries'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê um bloco do A (42501)', true, st = '42501');
  begin perform portal_home('nao-existe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente inexistente dá o mesmo erro que sem acesso', true, st = '42501');
  j := portal_home('ws_portal_b');
  insert into t values ('cliente B vê só o seu (1 guião, nada do A)', true,
    (j->'blocks'->'scripts'->>'total')::int = 1 and j::text not like '%numeiro%' and j->'viewer'->>'side' = 'cliente');
  insert into t values ('B sem contrato: entregas sem volumes, com motivo', true,
    j->'blocks'->'deliveries'->'contract' = 'null'::jsonb and j->'blocks'->'deliveries'->>'contract_reason' like 'Ainda não há volumes%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_un, 'role','authenticated')::text, true);
  begin perform portal_home('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem atribuição não entra (42501)', true, st = '42501');

  -- ── staff atribuído: "como o cliente vê" ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('staff atribuído vê com as_client', true, j->'viewer'->>'side' = 'agencia' and (j->'viewer'->>'as_client')::boolean);

  -- ── admin do cliente: os cinco blocos ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('admin do cliente: lado cliente, sem as_client', true, j->'viewer'->>'side' = 'cliente' and not (j->'viewer'->>'as_client')::boolean);
  insert into t values ('guiões em revisão listados para quem aprova', true,
    (j->'blocks'->'scripts'->>'available')::boolean
    and (j->'blocks'->'scripts'->>'total')::int = (select count(*) from guioes where client_id = 'numeiro' and editorial_status = 'in_review')
    and exists (select 1 from jsonb_array_elements(j->'blocks'->'scripts'->'items') x where x->>'id' = g2 and jsonb_array_length(x->'hooks') > 0));
  insert into t values ('publicações: indisponível com motivo enquanto pub.planning está desligado', true,
    j->'blocks'->'publications'->>'code' = 'desligado' and j->'blocks'->'publications'->>'reason' like 'O calendário de publicações%');
  insert into t values ('relatórios: indisponível com motivo enquanto perf.center está desligado', true,
    j->'blocks'->'reports'->>'code' = 'desligado' and j->'blocks'->'reports'->>'reason' like 'O centro de desempenho%');
  b := j->'blocks'->'deliveries';
  insert into t values ('entregas: volumes e prazo do contrato', true,
    (b->'contract'->>'videos_per_month')::int = 30 and (b->'contract'->>'scripts_per_month')::int = 40 and (b->'contract'->>'deadline_days')::int = 5
    and (b->'videos'->>'contracted')::int = 30 and b->'contract'->'platforms' = '["instagram", "tiktok"]'::jsonb);
  insert into t values ('entregas: nunca valores, moeda, pagamento, renovação nem notas', true,
    b::text not like '%98765%' and b::text not like '%AED%' and b::text not like '%amount%' and b::text not like '%currency%'
    and b::text not like '%payment%' and b::text not like '%vencido%' and b::text not like '%renewal%' and b::text not like '%secreta%'
    and b::text not like '%billing%' and j::text not like '%margin%' and j::text not like '%cost%');
  insert into t values ('entregas: guiões aprovados e por aprovar do mês', true,
    (b->'scripts'->>'waiting_approval')::int = (select count(*) from guioes where client_id = 'numeiro' and editorial_status = 'in_review'));
  insert into t values ('pedidos: disponível e pode criar', true, (j->'blocks'->'requests'->>'available')::boolean and (j->'blocks'->'requests'->>'can_create')::boolean);
  insert into t values ('nada da administração da agência na resposta', true,
    j::text not like '%flags%' and j::text not like '%ws_portal_b%' and j::text not like '%permission%' and j::text not like '%Portal B%');

  -- ── papéis sem a capacidade: bloco indisponível, portal de pé ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('colaborador: guiões indisponível (sem scripts.approve), entregas disponíveis', true,
    j->'blocks'->'scripts'->>'code' = 'sem_capacidade' and not (j->'blocks'->'scripts' ? 'items') and (j->'blocks'->'deliveries'->>'available')::boolean);
  begin perform content_transition(g2, 'approved', null, null, null); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não aprova pela RPC existente (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('leitor: acompanha pedidos mas não cria', true,
    (j->'blocks'->'requests'->>'available')::boolean and not (j->'blocks'->'requests'->>'can_create')::boolean);
  begin perform talent_request_create('numeiro', 'Pedido do leitor'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não cria pedidos (42501)', true, st = '42501');

  -- ── ações pelas RPCs existentes ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  lock := (select lock_version from guioes where id = g2);
  perform content_transition(g2, 'approved', null, lock, null);
  j := portal_block('numeiro', 'scripts');
  insert into t values ('guião aprovado sai da lista', true, not exists (select 1 from jsonb_array_elements(j->'items') x where x->>'id' = g2));
  rq := (talent_request_create('numeiro', 'Quero um vídeo sobre rendas em Dubai')->>'id')::bigint;
  j := portal_block('numeiro', 'requests');
  insert into t values ('pedido criado aparece como meu e recebido', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where (x->>'id')::bigint = rq and (x->>'mine')::boolean and x->>'status' = 'nova'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  perform source_update(rq, jsonb_build_object('notas', 'Nota interna da agência', 'status', 'descartada', 'status_reason', 'Tema já feito este mês'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := portal_block('numeiro', 'requests');
  insert into t values ('pedido descartado mostra o motivo, nunca as notas internas', true,
    exists (select 1 from jsonb_array_elements(j->'items') x where (x->>'id')::bigint = rq and x->>'status' = 'descartada' and x->>'status_reason' = 'Tema já feito este mês')
    and j::text not like '%Nota interna%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  insert into t values ('cliente B não vê pedidos do A', true, portal_block('ws_portal_b', 'requests')::text not like '%rendas%');

  -- ── publicações à espera do cliente (pub_* existentes) ──
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) values ('pub.planning', org, 'numeiro', 'all'), ('perf.center', org, 'numeiro', 'all');
  insert into pub_approval_policies (workspace_id, required, forbid_self) values ('numeiro', 'cliente', false);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  p1 := (pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + time '12:00') at time zone 'Asia/Dubai'),
          'caption', 'Legenda portal'))->>'id')::uuid;
  b := portal_block('numeiro', 'publications');
  insert into t values ('staff vê a publicação à espera do cliente, mas não a pode aprovar (parte errada)', true,
    exists (select 1 from jsonb_array_elements(b->'items') x where (x->>'id')::uuid = p1 and not (x->>'can_approve')::boolean and x->>'approve_blocked' = 'parte_errada'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  b := portal_block('numeiro', 'publications');
  insert into t values ('cliente vê a publicação com versão, destino e pode aprovar', true,
    (b->>'available')::boolean and not (b->>'publish_available')::boolean and b->'policy'->>'required' = 'cliente'
    and exists (select 1 from jsonb_array_elements(b->'items') x where (x->>'id')::uuid = p1 and (x->>'can_approve')::boolean
                and x->>'account_handle' is not null and x->>'caption' = 'Legenda portal' and (x->>'version_approved')::boolean));
  perform pub_approve('numeiro', p1, 1);
  b := portal_block('numeiro', 'publications');
  insert into t values ('aprovada pela RPC existente sai da lista', true,
    not exists (select 1 from jsonb_array_elements(b->'items') x where (x->>'id')::uuid = p1));
  execute 'reset role';
  insert into t values ('e ficou aprovada na base', true, (select status from pub_publications where id = p1) = 'aprovada');
  update pub_approval_policies set required = 'agencia' where workspace_id = 'numeiro';
  update pub_publications set caption = 'Legenda portal 2' where id = p1;     -- nova revisão, volta a planeada
  insert into t values ('mudar a legenda volta a planeada', true, (select status from pub_publications where id = p1) = 'planeada');
  execute 'set local role authenticated';
  b := portal_block('numeiro', 'publications');
  insert into t values ('política só da agência: nada à espera do cliente', true,
    not exists (select 1 from jsonb_array_elements(b->'items') x where (x->>'id')::uuid = p1));

  -- ── relatórios ──
  j := portal_block('numeiro', 'reports');
  insert into t values ('relatórios com analytics.read e perf.center: contas e semana', true,
    (j->>'available')::boolean and jsonb_typeof(j->'accounts') = 'array' and j->'week' ? 'top' and j->>'source' = 'scraping');
  insert into t values ('relatórios sem notas internas de saúde nem quem as escreveu', true,
    j::text not like '%health_note%' and j::text not like '%set_label%' and j::text not like '%can_manage%' and j::text not like '%params%');

  -- ── código de equipa ──
  execute 'reset role';
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  j := portal_home('numeiro', tok);
  insert into t values ('código de equipa abre com a flag "para todos"', true, j->'viewer'->>'side' = 'codigo' and not (j->'viewer'->>'individual')::boolean);
  insert into t values ('código de equipa não aprova publicações', true,
    not (j->'blocks'->'publications'->>'can_approve')::boolean and not (j->'blocks'->'publications'->>'individual')::boolean);
  begin perform portal_home('ws_portal_b', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código do A não abre o portal do B', true, st = '42501');
  execute 'reset role';
  update feature_flags set stage = 'agency' where key = 'client.portal' and workspace_id = 'numeiro';
  execute 'set local role anon';
  begin perform portal_home('numeiro', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag só para a agência: código de equipa recebe 55000', true, st = '55000');
  execute 'reset role';
  update feature_flags set stage = 'all' where key = 'client.portal' and workspace_id = 'numeiro';

  -- ── um bloco com erro não derruba o portal ──
  execute $f$create or replace function public._portal_reports(p_ws text, p_token text) returns jsonb language plpgsql stable
    set search_path = public as $b$ begin raise exception 'avaria_simulada'; end $b$ $f$;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := portal_home('numeiro');
  insert into t values ('bloco avariado volta como erro com código; os outros continuam', true,
    j->'blocks'->'reports'->>'code' = 'erro' and j->'blocks'->'reports'->>'sqlstate' = 'P0001'
    and (j->'blocks'->'deliveries'->>'available')::boolean and (j->'blocks'->'requests'->>'available')::boolean);
  begin perform portal_block('numeiro', 'custos'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('bloco desconhecido recusado (22023)', true, st = '22023');

  -- ── acesso removido ──
  execute 'reset role';
  delete from workspace_access where user_id = u_ca;
  execute 'set local role authenticated';
  begin perform portal_home('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('acesso removido deixa de ler (42501)', true, st = '42501');
  execute 'reset role';

  insert into t values ('ajudantes fechados; só portal_home e portal_block expostos', true,
    not has_function_privilege('authenticated', 'public._portal_deliveries(text, text)', 'execute')
    and not has_function_privilege('anon', 'public._portal_scripts(text, text)', 'execute')
    and has_function_privilege('authenticated', 'public.portal_home(text, text)', 'execute'));
  insert into t values ('flag registada na fase owner; sem capacidade nova', true,
    exists (select 1 from feature_flag_defs where key = 'client.portal' and default_stage = 'owner' and scope = 'ws')
    and not exists (select 1 from capabilities where key like 'portal.%'));
  insert into t values ('ações auditadas pelas RPCs existentes', true,
    exists (select 1 from audit_events where action = 'request.created' and entity_id = rq::text)
    and exists (select 1 from audit_events where action = 'pub.approved' and correlation_id = 'pub:' || p1));
  insert into t values ('auxiliares com search_path fixo', true,
    not exists (select 1 from pg_proc where proname like '\_portal%' and pronamespace = 'public'::regnamespace and proname <> '_portal_reports'
                and not exists (select 1 from unnest(coalesce(proconfig, '{}')) c where c like 'search_path=%')));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
