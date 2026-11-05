-- supabase/tests/w10_publicacao_manual.sql : registo da publicação manual (FR-12-02; FR-21-02, FR-21-04; R-16, R-18, PERF-02;
-- ADR-0054). Vídeo aprovado vs por aprovar vs versão antiga, publicação por aprovar, idempotência, correção com motivo,
-- validação do URL por plataforma, linhagem gravada e ligada ao publication_id, isolamento (cliente B, revisor sem a
-- capacidade, código de equipa, membro removido), auditoria, eventos e notificação. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid(); u_rev uuid := gen_random_uuid();
  u_cb uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  d date := (now() at time zone 'Asia/Dubai')::date + 3; j jsonb; st text; det text; ok int := 0; bad int := 0; res text := ''; r record;
  g1 text := 'numeiro-2026-10-28-01'; g2 text := 'numeiro-2026-10-28-02'; gb text := 'ws_pm_b-x-01';
  a1 jsonb; a2 jsonb; a3 jsonb; ab jsonb; v1 uuid; v1b uuid; v2 uuid; v3 uuid; vb uuid; p1 uuid; p2 uuid; p3 uuid; pb uuid;
  tt text; lin bigint; n int; rev int;
  u_ok text := 'https://www.instagram.com/reel/FXitsnumeiro1/?igsh=abc';
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_pm_b', 'PM B', 'pmb', org, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'pm-own@test.invalid'),(u_ag,'pm-ag@test.invalid'),(u_ca,'pm-ca@test.invalid'),(u_rev,'pm-rev@test.invalid'),
    (u_cb,'pm-cb@test.invalid'),(u_vw,'pm-vw@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'), ('numeiro', u_ca, 'client_staff', 'workspace_admin'),
    ('numeiro', u_rev, 'client_staff', 'reviewer'), ('numeiro', u_vw, 'client_staff', 'viewer'),
    ('ws_pm_b', u_cb, 'client_staff', 'workspace_admin');
  update guioes set editorial_status = 'approved', approved_version_id = current_version_id where id = g2;
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, origem, status, editorial_status)
  values (gb, 'ws_pm_b', current_date, 1, 'B', '[{"text":"Hook B"}]', 'Corpo B', 'fixture', 'aprovado', 'approved');
  update guioes set approved_version_id = current_version_id where id = gb;
  insert into feature_flags (key, organization_id, workspace_id, stage)
    select k, org, w, 'all' from unnest(array['numeiro','ws_pm_b']) w, unnest(array['pub.planning','media.library']) k;
  perform perf_sync_lineage('numeiro');      -- o reel FXitsnumeiro1 já existe como linhagem inferida (motor)
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- ── regra pura do URL (igual a src/lib/pub-url.ts) ──
  insert into t values ('IG reel com query: shortcode e URL canónico', true,
    _pub_post_url('instagram', u_ok) = '{"external_id":"FXitsnumeiro1","handle":null,"url":"https://www.instagram.com/reel/FXitsnumeiro1/"}'::jsonb);
  insert into t values ('IG reels/ e p/ aceites; com utilizador guarda o handle', true,
    _pub_post_url('instagram', 'https://instagram.com/reels/AbC_12-x')->>'external_id' = 'AbC_12-x'
    and _pub_post_url('instagram', 'https://www.instagram.com/p/AbCdE1/')->>'url' = 'https://www.instagram.com/p/AbCdE1/'
    and _pub_post_url('instagram', 'https://www.instagram.com/ItsNumeiro/reel/AbCdE1/')->>'handle' = 'itsnumeiro');
  insert into t values ('IG perfil, stories e outro domínio recusados', true,
    _pub_post_url('instagram', 'https://www.instagram.com/itsnumeiro/') is null and _pub_post_url('instagram', 'https://www.instagram.com/stories/x/123/') is null
    and _pub_post_url('instagram', 'https://evil.com/reel/AbCdE1/') is null and _pub_post_url('instagram', 'https://www.instagram.com.evil.com/reel/AbCdE1/') is null);
  insert into t values ('TikTok: ID numérico e conta', true,
    _pub_post_url('tiktok', 'https://www.tiktok.com/@ItsNumeiro/video/7301234567890123456?lang=pt') =
      '{"external_id":"7301234567890123456","handle":"itsnumeiro","url":"https://www.tiktok.com/@itsnumeiro/video/7301234567890123456"}'::jsonb
    and _pub_post_url('tiktok', 'https://vm.tiktok.com/ZMabc123/') is null);
  insert into t values ('YouTube: shorts, watch e youtu.be dão o mesmo ID', true,
    _pub_post_url('youtube', 'https://youtube.com/shorts/dQw4w9WgXcQ?feature=share')->>'external_id' = 'dQw4w9WgXcQ'
    and _pub_post_url('youtube', 'https://www.youtube.com/watch?t=3&v=dQw4w9WgXcQ')->>'url' = 'https://www.youtube.com/shorts/dQw4w9WgXcQ'
    and _pub_post_url('youtube', 'https://youtu.be/dQw4w9WgXcQ')->>'external_id' = 'dQw4w9WgXcQ'
    and _pub_post_url('youtube', 'https://youtu.be/curto') is null);
  insert into t values ('URL de outra plataforma recusado', true, _pub_post_url('youtube', u_ok) is null and _pub_post_url('tiktok', u_ok) is null);

  execute 'set local role authenticated';
  -- vídeos: g1 com v1 (aprovado e atual) e um segundo ativo por aprovar; g2 com um vídeo aprovado
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  a1 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWx/view', 'title', 'g01_hook1_S15.mp4',
          'tags', jsonb_build_array('hook_1', 'S15'), 'content_id', g1));
  v1 := (a1->'current'->>'id')::uuid;
  a2 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1ZyXwVuTsRqPoNmLkJiHgFeDc/view', 'title', 'g01_hook2.mp4',
          'tags', jsonb_build_array('hook_2'), 'content_id', g1));
  v2 := (a2->'current'->>'id')::uuid;
  a3 := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1QwErTyUiOpAsDfGhJkLzXcV/view', 'title', 'g02_hook1.mp4',
          'tags', jsonb_build_array('hook_1'), 'content_id', g2));
  v3 := (a3->'current'->>'id')::uuid;
  perform media_review_decide('numeiro', v1, 'approved');
  perform media_review_decide('numeiro', v3, 'approved');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  ab := media_link_add('ws_pm_b', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1BbBbBbBbBbBbBbBbBbBbBbB/view', 'title', 'b.mp4', 'content_id', gb));
  vb := (ab->'current'->>'id')::uuid;
  perform media_review_decide('ws_pm_b', vb, 'approved');
  perform pub_account_add('ws_pm_b', 'instagram', 'pmb_ig');
  pb := (pub_save('ws_pm_b', null, jsonb_build_object('content_id', gb, 'account_id', 'ws_pm_b-ig-pmb_ig',
          'scheduled_at', ((d + time '12:00') at time zone 'Asia/Dubai')))->>'id')::uuid;
  perform pub_approve('ws_pm_b', pb, 1);

  -- publicações: p1 (g1, IG), p2 (g2, IG, outro dia), p3 (g1, TikTok) fica por aprovar
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  p1 := (pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + time '18:00') at time zone 'Asia/Dubai')))->>'id')::uuid;
  p2 := (pub_save('numeiro', null, jsonb_build_object('content_id', g2, 'account_id', 'numeiro-ig', 'scheduled_at', ((d + 1 + time '18:00') at time zone 'Asia/Dubai')))->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  tt := pub_account_add('numeiro', 'tiktok', 'itsnumeiro')->>'id';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  p3 := (pub_save('numeiro', null, jsonb_build_object('content_id', g1, 'account_id', tt, 'scheduled_at', ((d + time '19:00') at time zone 'Asia/Dubai')))->>'id')::uuid;

  -- ── por aprovar: recusa ──
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('publicação por aprovar não se regista (22023 publicacao_por_aprovar)', true, st = '22023' and det = 'publicacao_por_aprovar');
  j := pub_calendar('numeiro', d, d + 6);
  insert into t values ('calendário: can.record e motivo por_aprovar', true,
    (j->'can'->>'record')::boolean and exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p1
      and not (x->>'can_record')::boolean and x->>'record_blocked' = 'por_aprovar'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  perform pub_approve('numeiro', p1, 1);
  perform pub_approve('numeiro', p2, 1);
  rev := 1;

  -- ── negativos de autorização ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('revisor sem publishing.publish: 42501', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('leitor: 42501', true, st = '42501');
  j := pub_record_options('numeiro', p1);
  insert into t values ('leitor vê as opções mas can_record = false', true, not (j->>'can_record')::boolean and jsonb_array_length(j->'publications') = 1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('cliente B na publicação de A: 42501', true, st = '42501');
  begin perform pub_record_published('ws_pm_b', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('cliente B com o ID da publicação de A no seu cliente: P0002', true, st = 'P0002');
  begin perform pub_record_published('ws_pm_b', pb, jsonb_build_object('url', 'https://www.instagram.com/reel/BbBbB1/', 'published_at', now(), 'media_version_id', v1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('cliente B com um vídeo de A: P0002 (não revela)', true, st = 'P0002');
  begin perform pub_record_options('ws_pm_b', null, v1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê opções de um vídeo de A: P0002', true, st = 'P0002');
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '{}', true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1), null, tok); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('código de equipa: 42501', true, st = '42501');
  execute 'set local role authenticated';

  -- ── validações ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', 'https://www.tiktok.com/@itsnumeiro/video/7301234567890123456', 'published_at', now(), 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('URL de TikTok numa conta do Instagram: url_invalido', true, st = '22023' and det = 'url_invalido');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', 'https://www.instagram.com/outra_conta/reel/FXitsnumeiro1/', 'published_at', now(), 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('URL com outra conta no caminho: url_de_outra_conta', true, st = '22023' and det = 'url_de_outra_conta');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now() + interval '1 hour', 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('hora no futuro recusada', true, det = 'hora_futura');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now() - interval '2 days', 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('publicado antes da aprovação recusado (AGENTS §2.7)', true, det = 'publicado_antes_da_aprovacao');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v2));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('vídeo por aprovar na revisão: video_por_aprovar', true, det = 'video_por_aprovar');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v3));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('vídeo de outro guião: video_de_outro_guiao', true, det = 'video_de_outro_guiao');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1, 'revision', 7));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('revisão vista diferente: 40001', true, st = '40001');
  -- versão nova do vídeo aprovado: a v1 deixa de ser a atual
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  v1b := (media_link_add('numeiro', (a1->>'id')::uuid, jsonb_build_object('url', 'https://drive.google.com/file/d/1NnNnNnNnNnNnNnNnNnNnNnN/view'))->'current'->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('versão antiga (já não é a atual): versao_antiga', true, det = 'versao_antiga');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v1b));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('versão atual mas ainda por aprovar: video_por_aprovar', true, det = 'video_por_aprovar');
  j := pub_record_options('numeiro', p1);
  insert into t values ('opções: vídeos do guião com aprovado/por aprovar, can_record', true, (j->>'can_record')::boolean
    and exists (select 1 from jsonb_array_elements(j->'videos') x where (x->>'version_id')::uuid = v1b and not (x->>'eligible')::boolean)
    and not exists (select 1 from jsonb_array_elements(j->'videos') x where (x->>'version_id')::uuid = v1));
  perform set_config('request.jwt.claims', json_build_object('sub', u_rev, 'role','authenticated')::text, true);
  perform media_review_decide('numeiro', v1b, 'approved');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  execute 'reset role';
  insert into t values ('nada ficou publicado depois das recusas', true,
    (select count(*) from pub_publications where status = 'publicada') = 0
    and not exists (select 1 from publication_lineage where lineage_mode = 'gravada' and workspace_id = 'numeiro'));
  execute 'set local role authenticated';

  -- ── registo ──
  j := pub_record_published('numeiro', p1, jsonb_build_object('url', u_ok, 'published_at', now() - interval '1 minute', 'media_version_id', v1b, 'revision', rev));
  lin := (j->>'lineage_id')::bigint;
  insert into t values ('regista: publicada, URL canónico, ID do post, vídeo e modo manual', true,
    j->>'status' = 'publicada' and j->'published'->>'url' = 'https://www.instagram.com/reel/FXitsnumeiro1/' and j->'published'->>'external_id' = 'FXitsnumeiro1'
    and (j->'published'->>'media_version_id')::uuid = v1b and j->'published'->>'mode' = 'manual' and not (j->>'replayed')::boolean);
  execute 'reset role';
  select count(*) into n from publication_lineage where workspace_id = 'numeiro' and account_id = 'numeiro-ig' and external_id = 'FXitsnumeiro1';
  insert into t values ('R-18: linhagem gravada (a inferida deu lugar), uma só linha', true, n = 1 and exists (select 1 from publication_lineage l
    where l.id = lin and l.lineage_mode = 'gravada' and l.origin = 'sistema' and l.correlation_id = 'pub:' || p1 and l.content_id = g1
      and l.content_version_id = (select approved_version_id from guioes where id = g1) and l.recorded_kind = 'user'));
  insert into t values ('PERF-02: hook pela etiqueta, estilo, ativo e conta', true, exists (select 1 from publication_lineage l where l.id = lin
    and l.hook_index = 0 and l.asset_ref = 'media_version:' || v1b and l.account_id = 'numeiro-ig' and l.local_tz = 'Asia/Dubai'));
  insert into t values ('FR-21-04: publicação ligada à linhagem (publication_id)', true,
    (select lineage_id from pub_publications where id = p1) = lin);
  insert into t values ('métricas do reel ficam na linhagem gravada', true,
    exists (select 1 from _perf_pubs('numeiro') x where x.reel_id = 'FXitsnumeiro1' and x.lineage_id = lin and x.lineage_mode = 'gravada' and x.origin = 'sistema'));
  insert into t values ('auditoria e evento de domínio', true,
    exists (select 1 from audit_events where action = 'pub.published_recorded' and entity_id = p1::text and correlation_id = 'pub:' || p1 and actor_user_id = u_ag)
    and exists (select 1 from audit_events where action = 'perf.lineage_recorded' and correlation_id = 'pub:' || p1)
    and (select count(*) from domain_events where type = 'publication.published' and entity_id = p1::text) = 1);
  insert into t values ('notificação a quem aprovou (não a quem registou)', true,
    exists (select 1 from notifications where kind = 'publication_published' and entity_id = p1::text and user_id = u_ca)
    and not exists (select 1 from notifications where kind = 'publication_published' and user_id = u_ag));
  execute 'set local role authenticated';

  -- ── idempotência ──
  j := pub_record_published('numeiro', p1, jsonb_build_object('url', 'https://instagram.com/reel/FXitsnumeiro1', 'published_at', now() - interval '1 minute', 'media_version_id', v1b));
  insert into t values ('mesmo URL outra vez: replayed, nada novo', true, (j->>'replayed')::boolean);
  execute 'reset role';
  insert into t values ('sem auditoria nem evento duplicados', true,
    (select count(*) from audit_events where action = 'pub.published_recorded' and entity_id = p1::text) = 1
    and (select count(*) from domain_events where type = 'publication.published' and entity_id = p1::text) = 1
    and (select count(*) from publication_lineage where correlation_id = 'pub:' || p1) = 1);
  execute 'set local role authenticated';
  begin perform pub_record_published('numeiro', p2, jsonb_build_object('url', u_ok, 'published_at', now(), 'media_version_id', v3));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('o mesmo post noutra publicação: url_ja_registada', true, det = 'url_ja_registada');
  begin perform pub_record_published('numeiro', p1, jsonb_build_object('url', 'https://www.instagram.com/reel/FXitsnumeiro2/', 'published_at', now(), 'media_version_id', v1b));
    st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('mudar o registo sem motivo: ja_publicada', true, det = 'ja_publicada');

  -- ── correção com motivo ──
  j := pub_record_published('numeiro', p1, jsonb_build_object('url', 'https://www.instagram.com/reel/FXitsnumeiro2/', 'published_at', now() - interval '2 minutes', 'media_version_id', v1b),
         'Colei o link do post errado.');
  insert into t values ('correção: URL novo, mesma linhagem, contador e histórico', true, (j->>'corrected')::boolean and j->'published'->>'external_id' = 'FXitsnumeiro2'
    and (j->>'lineage_id')::bigint = lin and (j->'published'->>'corrections')::int = 1 and jsonb_array_length(j->'published'->'history') = 2);
  execute 'reset role';
  insert into t values ('linhagem corrigida no sítio, a inferida do post novo saiu', true,
    (select external_id from publication_lineage where id = lin) = 'FXitsnumeiro2'
    and (select count(*) from publication_lineage where workspace_id = 'numeiro' and account_id = 'numeiro-ig' and external_id = 'FXitsnumeiro2') = 1);
  insert into t values ('correção auditada com antes/depois e motivo', true, exists (select 1 from audit_events where action = 'pub.published_corrected'
    and entity_id = p1::text and before->>'external_id' = 'FXitsnumeiro1' and after->>'external_id' = 'FXitsnumeiro2' and after->>'reason' = 'Colei o link do post errado.'));
  begin update publication_lineage set published_at = now() where id = lin; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('linhagem gravada continua imutável fora da correção', true, st = '42501');
  begin update pub_publications set published_url = 'https://x.y/z' where id = p1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('registo só pela RPC (UPDATE direto recusado)', true, st = '42501');
  begin update pub_publications set status = 'publicada' where id = p2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('passar a publicada à mão recusado', true, st in ('42501', '23514'));
  execute 'set local role authenticated';

  -- ── depois de publicada: não muda nem cancela; o publicador não liga outra vez ──
  begin perform pub_cancel('numeiro', p1, 'já não quero'); st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('publicada não se cancela', true, det = 'publicacao_publicada');
  begin perform pub_save('numeiro', p1, jsonb_build_object('caption', 'outra legenda')); st := 'none'; exception when others then st := sqlstate; get stacked diagnostics det = message_text; end;
  insert into t values ('publicada não se muda', true, det = 'publicacao_publicada');
  execute 'reset role';
  begin perform _pub_link_lineage(p1, lin); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('_pub_link_lineage recusa uma publicada (sem dupla ligação)', true, st = '42501');
  execute 'set local role authenticated';

  -- ── a partir do vídeo (folha da revisão) ──
  j := pub_record_options('numeiro', null, v3);
  insert into t values ('opções pelo vídeo: publicações aprovadas do guião', true,
    (j->'video'->>'approved')::boolean and exists (select 1 from jsonb_array_elements(j->'publications') x where (x->>'id')::uuid = p2 and (x->>'can_record')::boolean));
  j := pub_record_published('numeiro', p2, jsonb_build_object('url', 'https://www.instagram.com/p/NovoPost9/', 'published_at', now(), 'media_version_id', v3));
  insert into t values ('regista p2 por outro post', true, j->>'status' = 'publicada');
  j := pub_calendar('numeiro', d, d + 6);
  insert into t values ('calendário mostra publicada sem conflitos', true, exists (select 1 from jsonb_array_elements(j->'publications') x
    where (x->>'id')::uuid = p1 and x->>'status' = 'publicada' and jsonb_array_length(x->'conflicts') = 0 and x->'published'->>'by_label' = 'pm-ag@test.invalid'));

  -- ── membro removido ──
  execute 'reset role';
  delete from workspace_access where user_id = u_ca;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform pub_record_published('numeiro', p3, jsonb_build_object('url', 'https://www.tiktok.com/@itsnumeiro/video/7301234567890123456', 'published_at', now(), 'media_version_id', v1b));
    st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido deixa de registar (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('capacidade ativa, manager com publishing.publish, revisor sem', true,
    (select status from capabilities where key = 'publishing.publish') = 'ativo'
    and exists (select 1 from role_capabilities where scope = 'ws' and role = 'manager' and capability = 'publishing.publish')
    and not exists (select 1 from role_capabilities where scope = 'ws' and role in ('reviewer', 'viewer', 'contributor') and capability = 'publishing.publish'));
  insert into t values ('funções internas fechadas', true, not has_function_privilege('authenticated', 'public._pub_post_url(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public._pub_record_video(text, text, uuid, uuid)', 'execute'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
