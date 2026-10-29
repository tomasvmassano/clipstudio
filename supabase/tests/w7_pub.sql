-- supabase/tests/w7_pub.sql : planeamento e aprovação de publicações (PUB-02, PUB-04, PUB-06, TEAM-10, FR-21-01, FR-21-02,
-- FR-21-04, VAR-01). Nada publica. Isolamento entre clientes, flag, limites das APIs, variantes, aprovação presa à versão e
-- ao destino, política de aprovação e autoaprovação. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_cc uuid := gen_random_uuid();
  u_cb uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date + 3; j jsonb; st text; det text; ok int := 0; bad int := 0; res text := ''; r record;
  g1 text; g2 text; g3 text; g4 text; g5 text; gb text; ver1 uuid; ver2 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; prep uuid; pb uuid; py uuid;
  v1 uuid; v2 uuid; v3 uuid; tt text; ytb text; yta text; lin bigint; n int;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_pub_b', 'Pub B', 'pubb', org, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'pub-own@test.invalid'),(u_ag,'pub-ag@test.invalid'),(u_ca,'pub-ca@test.invalid'),(u_cc,'pub-cc@test.invalid'),
    (u_cb,'pub-cb@test.invalid'),(u_vw,'pub-vw@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'),
    ('numeiro', u_ca, 'client_staff', 'workspace_admin'), ('numeiro', u_cc, 'client_staff', 'contributor'),
    ('numeiro', u_vw, 'client_staff', 'viewer'), ('ws_pub_b', u_cb, 'client_staff', 'workspace_admin');
  g1 := 'numeiro-2026-10-28-01';
  g2 := 'numeiro-2026-10-28-02'; g3 := 'numeiro-2026-10-28-03'; g4 := 'numeiro-2026-10-28-04'; g5 := 'numeiro-2026-10-28-05';
  update guioes set editorial_status = 'approved' where id in (g3, g4, g5);    -- g2 fica em revisão
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, origem, status, editorial_status)
  values ('ws_pub_b-x-01', 'ws_pub_b', current_date, 1, 'B', '[{"text":"Hook B"}]', 'Corpo B', 'fixture', 'aprovado', 'approved');
  gb := 'ws_pub_b-x-01';
  ver1 := (select approved_version_id from guioes where id = g1);
  ver2 := (select current_version_id from guioes where id = g2);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── flag desligada: o módulo recusa com 55000 ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_calendar('numeiro', d, d + 6); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada (staff da agência): 55000', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := pub_calendar('numeiro', d, d + 6);
  insert into t values ('fase owner: o dono da agência vê', true, j ? 'publications');
  insert into t values ('publicação automática marcada como indisponível', true,
    not (j->>'publish_available')::boolean and j->>'publish_unavailable_reason' = 'Publicação automática chega quando as plataformas aprovarem a app.');
  insert into t values ('FR-21-01: conta do cliente aparece por ligar', true,
    exists (select 1 from jsonb_array_elements(j->'accounts') x where x->>'id' = 'numeiro-ig' and x->>'connection_state' = 'por_ligar'));
  insert into t values ('PUB-02: limites com data de verificação 2026-10-29', true,
    jsonb_array_length(j->'limits') = 3 and not exists (select 1 from jsonb_array_elements(j->'limits') x where x->>'verified_on' <> '2026-10-29')
    and exists (select 1 from jsonb_array_elements(j->'limits') x where x->>'platform' = 'instagram' and (x->>'max_posts')::int = 100 and x->>'window_kind' = 'rolling_24h'));
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'pub.planning', org, w, 'all' from unnest(array['numeiro','ws_pub_b']) w;
  execute 'set local role authenticated';

  -- ── contas de destino (FR-21-01) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform pub_account_add('numeiro', 'tiktok', 'itsnumeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não acrescenta contas (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := pub_account_add('numeiro', 'tiktok', '@ItsNumeiro'); tt := j->>'id';
  yta := pub_account_add('numeiro', 'youtube', 'numeiroyt')->>'id';
  insert into t values ('admin do cliente acrescenta conta TikTok por ligar', true,
    tt = 'numeiro-tt-itsnumeiro' and j->>'connection_state' = 'por_ligar');
  insert into t values ('acrescentar outra vez é idempotente', true, pub_account_add('numeiro', 'tiktok', 'itsnumeiro')->>'id' = tt);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform pub_account_add('ws_pub_b', 'tiktok', 'itsnumeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não fica com a conta de A (22023)', true, st = '22023');
  ytb := pub_account_add('ws_pub_b', 'youtube', 'pubbyt')->>'id';

  -- ── planear (PUB-04) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig',
    'scheduled_at', ((d + time '12:00') at time zone 'Asia/Dubai'))); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não planeia (42501)', true, st = '42501');
  insert into t values ('leitor lê o calendário de publicações', true, pub_calendar('numeiro', d, d + 6) ? 'publications');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + time '12:00') at time zone 'Asia/Dubai'),
    'caption', 'Legenda 1', 'hashtags', jsonb_build_array('dinheiro', '#dinheiro', 'dubai')));
  p1 := (j->>'id')::uuid;
  insert into t values ('planeada, revisão 1, versão aprovada por defeito', true,
    j->>'status' = 'planeada' and (j->>'revision')::int = 1 and (j->>'content_version_id')::uuid = ver1 and (j->>'version_approved')::boolean);
  insert into t values ('hashtags normalizadas e sem repetidos', true, j->'hashtags' = '["#dinheiro", "#dubai"]'::jsonb);
  insert into t values ('FR-21-04: correlation_id pub:<id> para a linhagem', true, j->>'correlation_id' = 'pub:' || p1);
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + time '20:00') at time zone 'Asia/Dubai')));
    st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('mesmo guião, mesma conta, mesmo dia: bloqueia', true, st = '22023' and det like '%mesma conta no mesmo dia%');
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + 1 + time '12:00') at time zone 'Asia/Dubai')));
    st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('VAR-01: o mesmo original duas vezes na mesma plataforma bloqueia', true, st = '22023' and det like '%menos de 2 dos 5 elementos%');
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', now() - interval '1 hour'));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('hora no passado recusada', true, st = '22023');

  -- ── variantes (VAR-01) ──
  execute 'reset role';
  insert into t values ('troca de ativo de contexto sem tese nova conta zero', true, _pub_variant_diff('{"context_asset":"foto nova"}', '{}') = 0);
  insert into t values ('ativo de contexto com tese nova conta 2', true, _pub_variant_diff('{"context_asset":"foto nova","title_thesis":"40 mil foi barato"}', '{}') = 2);
  insert into t values ('maiúsculas e espaços não contam como mudança', true,
    _pub_variant_diff('{"segment":"Min 1  a 2"}', '{"segment":"min 1 a 2"}') = 0);
  execute 'set local role authenticated';
  j := pub_variant_save('numeiro', jsonb_build_object('content_id', g1, 'label', 'Só título', 'elements', jsonb_build_object('title_thesis', 'Tese nova')));
  v1 := (select (x->>'id')::uuid from jsonb_array_elements(j->'variants') x where x->>'label' = 'Só título');
  insert into t values ('variante com 1 elemento não conta como nova', true,
    exists (select 1 from jsonb_array_elements(j->'variants') x where x->>'label' = 'Só título' and not (x->>'counts_as_new')::boolean and (x->>'changes')::int = 1));
  j := pub_variant_save('numeiro', jsonb_build_object('content_id', g1, 'label', 'Segmento e narração', 'platform', 'instagram',
    'edit_style_key', 'S13', 'edit_style_version', 1, 'elements', jsonb_build_object('segment', '00:10-00:40', 'narration', 'Comentário por cima')));
  v2 := (select (x->>'id')::uuid from jsonb_array_elements(j->'variants') x where x->>'label' = 'Segmento e narração');
  insert into t values ('variante com 2 elementos conta como nova e guarda o estilo', true,
    exists (select 1 from jsonb_array_elements(j->'variants') x where (x->>'id')::uuid = v2 and (x->>'counts_as_new')::boolean and x->>'edit_style_key' = 'S13'));
  begin perform pub_variant_save('numeiro', jsonb_build_object('content_id', g1, 'label', 'Quase igual', 'platform', 'instagram',
    'elements', jsonb_build_object('segment', '00:10-00:40', 'narration', 'Outro comentário'))); st := 'none';
  exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('VAR-01: irmã na mesma plataforma com 1 diferença bloqueia', true, st = '22023' and det like '%menos de 2%');
  begin perform pub_variant_save('numeiro', jsonb_build_object('content_id', g1, 'label', 'X', 'elements', jsonb_build_object('cor', 'vermelho'))); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('elemento fora dos 5 recusado (layout não é elemento)', true, st = '22023');
  begin perform pub_variant_save('numeiro', jsonb_build_object('content_id', g1, 'label', 'X', 'edit_style_key', 'S99', 'edit_style_version', 1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('estilo de outro cliente/inexistente recusado', true, st = '22023');
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'variant_id', v2, 'account_id', 'numeiro-ig',
    'scheduled_at', ((d + 1 + time '12:00') at time zone 'Asia/Dubai')));
  p2 := (j->>'id')::uuid;
  insert into t values ('variante nova na mesma plataforma noutro dia: aceite', true, j->>'status' = 'planeada' and j->'variant'->>'id' = v2::text);
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'variant_id', v1, 'account_id', tt,
    'scheduled_at', ((d + time '13:00') at time zone 'Asia/Dubai')));
  p3 := (j->>'id')::uuid;
  insert into t values ('variante que não conta como nova: aviso, não bloqueia', true,
    exists (select 1 from jsonb_array_elements(j->'conflicts') x where x->>'code' = 'variante_nao_nova' and x->>'severity' = 'aviso'));
  insert into t values ('TikTok: aviso de só privado até à auditoria', true,
    exists (select 1 from jsonb_array_elements(j->'conflicts') x where x->>'code' = 'so_privado'));
  execute 'reset role';
  begin update pub_variants set label = 'mudado' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('variantes são imutáveis', true, st = '42501');
  execute 'set local role authenticated';

  -- ── limites das APIs (PUB-02): só o dono da agência edita ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform pub_limit_save('numeiro', 'tiktok', '{"max_posts":1,"verified_on":"2026-10-30"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente não edita limites (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_limit_save('numeiro', 'tiktok', '{"max_posts":1,"verified_on":"2026-10-30"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência não edita limites (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform pub_limit_save('numeiro', 'tiktok', '{"max_posts":1}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('editar limite exige data de verificação', true, st = '22023');
  j := pub_limit_save('numeiro', 'tiktok', '{"max_posts":1,"verified_on":"2026-10-30"}');
  insert into t values ('dono da agência edita e a data fica registada', true,
    exists (select 1 from jsonb_array_elements(j) x where x->>'platform' = 'tiktok' and (x->>'max_posts')::int = 1 and x->>'verified_on' = '2026-10-30'));
  perform pub_limit_save('numeiro', 'youtube', '{"max_posts":1,"verified_on":"2026-10-30"}');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g3, 'account_id', tt, 'scheduled_at', ((d + time '18:00') at time zone 'Asia/Dubai')));
    st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('acima do limite da conta em 24 h móveis: bloqueia com explicação', true, st = '22023' and det like '%limite da API: 2 de 1%');
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g3, 'account_id', tt, 'scheduled_at', ((d + 1 + time '14:00') at time zone 'Asia/Dubai')));
  insert into t values ('fora da janela de 24 h passa', true, j->>'status' = 'planeada');
  -- YouTube conta o projeto inteiro (todos os clientes): o cliente não vê contagens dos outros
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  py := (pub_save('ws_pub_b', null, jsonb_build_object('content_id', gb, 'account_id', ytb, 'scheduled_at', ((d + time '10:00') at time zone 'America/Los_Angeles')))->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform pub_save('numeiro', null, jsonb_build_object('content_id', g4, 'account_id', yta, 'scheduled_at', ((d + time '11:00') at time zone 'America/Los_Angeles')));
    st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('YouTube: limite do projeto conta outros clientes, sem revelar números ao cliente', true,
    st = '22023' and det like '%limite da API do Youtube%' and det not like '%de 1%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  perform pub_limit_save('numeiro', 'tiktok', '{"max_posts":15,"verified_on":"2026-10-29"}');
  perform pub_limit_save('numeiro', 'youtube', '{"max_posts":100,"verified_on":"2026-10-29"}');

  -- ── aprovar (PUB-06, FR-21-02) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform pub_approve('numeiro', p1, 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem publishing.approve não aprova (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := pub_calendar('numeiro', d, d + 6);
  insert into t values ('calendário diz que posso aprovar a planeada', true,
    exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p1 and (x->>'can_approve')::boolean));
  begin perform pub_approve('numeiro', p1, 7); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisão desatualizada: 40001', true, st = '40001');
  j := pub_approve('numeiro', p1, 1);
  insert into t values ('aprovação humana: aprovada, presa à revisão 1', true, j->>'status' = 'aprovada' and (j->>'approved_revision')::int = 1);
  execute 'reset role';
  insert into t values ('aprovação guarda fotografia (versão, conta, hora, legenda), parte e papel', true,
    exists (select 1 from pub_approvals a where a.publication_id = p1 and a.revision = 1 and a.side = 'agencia' and a.actor_role = 'manager'
            and (a.snapshot->>'content_version_id')::uuid = ver1 and a.snapshot->>'account_id' = 'numeiro-ig' and a.snapshot->>'caption' = 'Legenda 1'));
  begin update pub_publications set status = 'aprovada', approved_revision = revision where id = p2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('FR-21-02: nem a base aprova sem a RPC de aprovação', true, st = '42501');
  begin insert into pub_approvals (workspace_id, publication_id, revision, side, capability, actor_user_id, actor_role, snapshot, snapshot_hash)
    values ('numeiro', p2, 1, 'agencia', 'publishing.approve', u_ag, 'manager', '{}', 'x'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('aprovações não se inserem fora da RPC', true, st = '42501');
  begin insert into pub_publications (workspace_id, content_id, content_version_id, account_id, platform, scheduled_at, status, approved_revision)
    values ('numeiro', g1, ver1, 'numeiro-ig', 'instagram', now() + interval '9 days', 'aprovada', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não nasce aprovada', true, st = '42501');
  begin delete from pub_publications where id = p1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('publicações não se apagam', true, st = '42501');
  insert into t values ('não existe ação de publicar', true, not exists (select 1 from pg_proc where proname in ('pub_publish', 'publication_publish')));
  execute 'set local role authenticated';

  -- editar legenda depois de aprovar retira a aprovação
  j := pub_save('numeiro', p1, '{"caption":"Legenda 1 corrigida"}');
  insert into t values ('mudar a legenda: revisão 2, volta a planeada', true, j->>'status' = 'planeada' and (j->>'revision')::int = 2);
  insert into t values ('a aprovação antiga fica marcada como invalidada', true,
    exists (select 1 from jsonb_array_elements(j->'approvals') x where (x->>'revision')::int = 1 and x->>'invalidated_at' is not null));
  j := pub_approve('numeiro', p1, 2);
  insert into t values ('nova aprovação para a revisão 2', true, j->>'status' = 'aprovada');
  j := pub_save('numeiro', p1, jsonb_build_object('scheduled_at', ((d + time '15:30') at time zone 'Asia/Dubai')));
  insert into t values ('arrastar (mudar hora) também retira a aprovação', true, j->>'status' = 'planeada' and (j->>'revision')::int = 3);
  j := pub_save('numeiro', p1, jsonb_build_object('scheduled_at', ((d + time '15:30') at time zone 'Asia/Dubai')));
  insert into t values ('guardar igual não cria revisão', true, (j->>'revision')::int = 3);
  begin perform pub_save('numeiro', p1, '{"caption":"x"}', 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lock desatualizado: PT409', true, st = 'PT409');
  p4 := (pub_save('numeiro', null, jsonb_build_object('content_id', g2, 'account_id', 'numeiro-ig',
      'scheduled_at', ((d + 2 + time '12:00') at time zone 'Asia/Dubai')))->>'id')::uuid;
  begin perform pub_approve('numeiro', p4, 1); st := 'none';
  exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('versão do guião por aprovar: não aprova', true, st = '22023' and det like '%não é a versão aprovada%');

  -- ── TEAM-10: política ──
  begin perform pub_policy_save('numeiro', '{"required":"ambos"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gestor não muda a política (42501)', true, st = '42501');
  perform pub_approve('numeiro', p1, 3);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform pub_policy_save('numeiro', '{"required":"todos"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('política inválida recusada', true, st = '22023');
  j := pub_policy_save('numeiro', '{"required":"ambos","forbid_self":false}');
  insert into t values ('política ambos reabre as aprovadas que já não cumprem', true, (j->>'reopened')::int >= 1
    and exists (select 1 from jsonb_array_elements(pub_calendar('numeiro', d, d + 6)->'publications') x where (x->>'id')::uuid = p1 and x->>'status' = 'planeada'));
  j := pub_approve('numeiro', p1, 3);
  insert into t values ('cliente aprova a parte do cliente: com a da agência fica aprovada', true, j->>'status' = 'aprovada');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := pub_approve('numeiro', p2, 1);
  insert into t values ('ambos: só a agência aprovou, falta o cliente', true, j->>'status' = 'planeada' and j->'missing' = '["cliente"]'::jsonb);
  insert into t values ('repetir a mesma aprovação é idempotente', true, (pub_approve('numeiro', p2, 1)->>'status') = 'planeada'
    and (select jsonb_array_length(x->'approvals') from jsonb_array_elements(pub_calendar('numeiro', d, d + 6)->'publications') x where (x->>'id')::uuid = p2) = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform pub_approve('numeiro', p2, 1); st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('ambos: segunda pessoa da agência não substitui o cliente', true, st = '42501' and det like '%falta a outra parte%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  perform pub_policy_save('numeiro', '{"forbid_self":true}');
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g5, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + 4 + time '12:00') at time zone 'Asia/Dubai')));
  p5 := (j->>'id')::uuid;
  insert into t values ('autoaprovação: o calendário explica porque não posso', true, j->>'approve_blocked' = 'autoaprovacao' and not (j->>'can_approve')::boolean);
  begin perform pub_approve('numeiro', p5, 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('autoaprovação proibida pela política (42501)', true, st = '42501');
  perform pub_policy_save('numeiro', '{"required":"agencia","forbid_self":false}');
  begin perform pub_approve('numeiro', p5, 1); st := 'none'; exception when others then get stacked diagnostics det = pg_exception_detail; st := sqlstate; end;
  insert into t values ('política agência: o cliente não aprova', true, st = '42501' and det like '%da agência%');
  perform pub_policy_save('numeiro', '{"required":"qualquer","forbid_self":false}');
  execute 'reset role';
  insert into t values ('política auditada com antes/depois', true,
    (select count(*) from audit_events where action = 'pub.policy_saved' and workspace_id = 'numeiro') = 4);
  execute 'set local role authenticated';

  -- ── republicação: capacidade própria ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  j := pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'kind', 'republicacao', 'parent_publication_id', p1, 'account_id', 'numeiro-ig',
    'scheduled_at', ((d + 10 + time '12:00') at time zone 'Asia/Dubai')));
  prep := (j->>'id')::uuid;
  insert into t values ('republicação cedo e idêntica: avisos', true,
    exists (select 1 from jsonb_array_elements(j->'conflicts') x where x->>'code' = 'republicacao_cedo')
    and exists (select 1 from jsonb_array_elements(j->'conflicts') x where x->>'code' = 'republicacao_identica'));
  begin perform pub_approve('numeiro', prep, 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('gestor sem publishing.republish.approve não aprova republicação', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  insert into t values ('dono da agência aprova a republicação', true, pub_approve('numeiro', prep, 1)->>'status' = 'aprovada');

  -- ── aprovar em lote ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := pub_approve_batch('numeiro', jsonb_build_array(jsonb_build_object('id', p2, 'revision', 1), jsonb_build_object('id', p3, 'revision', 9)));
  insert into t values ('lote: cada item independente (um aprova, outro recusa)', true,
    (j->0->>'ok')::boolean and (j->0->>'status') = 'aprovada' and not (j->1->>'ok')::boolean and j->1->>'code' = '40001');

  -- ── cancelar ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_cancel('numeiro', p4, ''); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cancelar exige motivo', true, st = '22023');
  j := pub_cancel('numeiro', p4, 'Guião não vai sair');
  insert into t values ('cancelada', true, j->>'status' = 'cancelada');
  begin perform pub_save('numeiro', p4, '{"caption":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cancelada não se muda', true, st = '22023');

  -- ── isolamento entre clientes ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform pub_calendar('numeiro', d, d + 6); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê publicações de A (42501)', true, st = '42501');
  begin perform pub_approve('ws_pub_b', p1, 3); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não aprova publicação de A pelo seu cliente (P0002)', true, st = 'P0002');
  begin perform pub_save('ws_pub_b', p1, '{"caption":"x"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não muda publicação de A (P0002)', true, st = 'P0002');
  begin perform pub_save('ws_pub_b', null, jsonb_build_object('content_id', gb, 'account_id', 'numeiro-ig', 'scheduled_at', now() + interval '5 days'));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não planeia na conta de A (P0002)', true, st = 'P0002');
  begin perform pub_content_options('ws_pub_b', g1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê variantes de A (P0002)', true, st = 'P0002');
  j := pub_calendar('ws_pub_b', d, d + 6);
  insert into t values ('calendário de B só tem B', true,
    not exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid <> py)
    and not exists (select 1 from jsonb_array_elements(j->'accounts') x where x->>'id' like 'numeiro%'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_calendar('ws_pub_b', d, d + 6); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff só de A não lê B (42501)', true, st = '42501');

  -- ── código de equipa: lê, não planeia nem aprova ──
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  insert into t values ('código de equipa lê o calendário com a flag para todos', true, pub_calendar('numeiro', d, d + 6, tok) ? 'publications');
  begin perform pub_save('numeiro', p5, '{"caption":"x"}', null, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não planeia', true, st = '42501');
  begin perform pub_approve('numeiro', p5, 1, tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não aprova', true, st = '42501');
  execute 'reset role';

  -- ── FR-21-04: linhagem ligada pelo publicador (service_role) ──
  lin := (_perf_record_lineage('numeiro', jsonb_build_object('account_id', 'numeiro-ig', 'external_id', 'TESTPUB1', 'content_id', g1,
          'content_version_id', ver1, 'correlation_id', 'pub:' || prep), '{"kind":"system","label":"teste"}')->>'id')::bigint;
  j := _pub_link_lineage(prep, lin);
  insert into t values ('publicação aprovada liga-se à linhagem gravada pelo correlation_id', true,
    (j->>'linked')::boolean and (select lineage_id from pub_publications where id = prep) = lin);
  begin perform _pub_link_lineage(p2, lin); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('linhagem de outra publicação recusada', true, st = '22023');
  begin update pub_publications set lineage_id = null where id = prep; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('lineage_id não muda fora do publicador', true, st = '42501');

  -- ── credenciais por conta (FR-21-01) ──
  begin update social_accounts set token_ref = 'EAAG-segredo', connection_state = 'ligada' where account_id = 'numeiro-ig'; st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('token em claro recusado (só referência ao Vault)', true, st = '23514');
  update social_accounts set token_ref = 'vault:11111111-1111-1111-1111-111111111111', connection_state = 'ligada' where account_id = 'numeiro-ig';
  begin update social_accounts set token_ref = 'vault:11111111-1111-1111-1111-111111111111', connection_state = 'ligada' where account_id = ytb; st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('o mesmo token nunca serve duas contas', true, st = '23505');
  begin insert into social_accounts (account_id, workspace_id) values ('numeiro-ig', 'ws_pub_b') on conflict (account_id) do update set workspace_id = 'ws_pub_b'; st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('conta social não muda de cliente', true, st = '42501');

  -- ── membro removido ──
  delete from workspace_access where user_id = u_ag;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_calendar('numeiro', d, d + 6); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido deixa de ler (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.pub_publications', 'select') and not has_table_privilege('authenticated', 'public.pub_approvals', 'select')
    and not has_table_privilege('authenticated', 'public.social_accounts', 'select') and not has_table_privilege('anon', 'public.pub_variants', 'select'));
  insert into t values ('capacidades e flag registadas', true,
    (select count(*) from capabilities where key in ('publishing.approve','publishing.republish.approve','publishing.policy.manage','publishing.limits.manage') and status = 'ativo') = 4
    and (select status from capabilities where key = 'publishing.publish') = 'W6'
    and exists (select 1 from feature_flag_defs where key = 'pub.planning' and default_stage = 'owner'));
  insert into t values ('eventos e auditoria das transições', true,
    (select count(*) from domain_events where type = 'publication.approval_invalidated') >= 2
    and exists (select 1 from audit_events where action = 'pub.approved' and correlation_id = 'pub:' || p1));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
