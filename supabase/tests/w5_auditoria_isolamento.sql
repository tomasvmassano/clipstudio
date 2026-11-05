-- supabase/tests/w5_auditoria_isolamento.sql : auditoria adversarial das RPCs de 05/11 (W5-07..W5-14, W9; rollback no fim).
-- Negativos exigem o SQLSTATE certo; outro erro conta como falha. Dois clientes (numeiro = A, ws_au_b = B), staff de cada um,
-- código de equipa, pré-visualização só de leitura, worker, guiões eliminados (soft delete).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  ua_own uuid := gen_random_uuid(); ua_mgr uuid := gen_random_uuid(); ua_view uuid := gen_random_uuid();
  ub uuid := gen_random_uuid(); ub_own uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id = 'numeiro' limit 1);
  gd text := 'numeiro-2026-10-28-21'; gk text := 'numeiro-2026-10-28-22';
  gb text := 'ws_au_b-2026-10-28-01'; gbd text := 'ws_au_b-2026-10-28-02';
  sha text := repeat('c', 64); day date;
  fa uuid; sa uuid; fb uuid; sb uuid; a_fa uuid; a_fb uuid; a_d uuid; a_x uuid; ev_a uuid; ev_b uuid;
  job_exp_b uuid; pkg_b uuid; pkg_a uuid; j jsonb; k jsonb; st text; r record;
  doc_a jsonb; doc_b jsonb; pl jsonb := '[{"id":"p1","text":"O maior do bairro"}]';
  ok int := 0; bad int := 0; res text := '';
  base_doc jsonb := '{"schema":1,"fps":30,"style":"S15","size":[1080,1920],
                 "segments":[{"id":"s1","in":5,"out":10,"section":"hook"},{"id":"s2","in":20,"out":30,"section":"body"}],
                 "captions":{"words":[]},"cameras":[],"hook":{"text":"Hook"},"overlays":[],
                 "audio":{"music":null,"sfx":[],"gains":[]},"notes":[]}';
  internal text[] := array['_media_r2(text)', '_media_ceiling_ws(text)', '_media_job_json(media_jobs)', '_edit_resolve_cams(text,jsonb)',
    '_media_package_done()', '_edit_look_problem(jsonb)', '_edit_guided_problem(text,uuid,jsonb,jsonb,text)', '_edit_saved_look_problem(jsonb)',
    '_content_delete_blockers(guioes)', '_content_delete_why(jsonb)', '_content_recorded_version(text)', '_content_same_as_version(guioes,uuid)',
    '_content_check_recorded(guioes)', '_prereq_on(text,text,text)', '_prereq_missing(guioes,text,text)', '_prereq_check(guioes,text,text)',
    '_review_eligible(media_versions)', '_review_qc(jsonb)', '_persona_current(text)', '_persona_problem(jsonb)', '_media_policy(text)',
    '_media_usage(text)', '_content_require(text,text,text,text,text)', 'guioes_deleted_guard()', '_persona_lists_immutable()'];
  worker_fns text[] := array['media_worker_claim(text,text[],integer)', 'media_worker_heartbeat(text,uuid,jsonb,integer)',
    'media_worker_finish(text,uuid,boolean,jsonb,text,boolean)', 'media_worker_package_save(text,uuid,text,integer,jsonb)',
    'worker_claim(text,text[],integer)'];
  session_only text[] := array['edit_doc_get(text,uuid,uuid,text)', 'edit_doc_save(text,uuid,uuid,jsonb,text,text,text)',
    'edit_saved_styles(text,text)', 'edit_style_from_doc(text,uuid,uuid,text,text,integer,text)', 'edit_style_apply(text,uuid,uuid,text,text)',
    'media_review_list(text,jsonb,text)', 'media_review_detail(text,uuid,uuid,text)', 'media_proxy_access(text,uuid,text)',
    'edit_preview_sources(text,uuid,uuid,text)', 'edit_export_request(text,uuid,uuid,text)', 'edit_export_list(text,uuid,text)',
    'edit_export_cancel(text,uuid,text)', 'edit_package_request(text,uuid,uuid,text[],text,text)', 'edit_package_list(text,text)',
    'edit_doc_list(text,text)', 'edit_package_export(text,uuid,text)', 'persona_list_get(text,text)', 'persona_list_version(text,integer,text)',
    'persona_list_save(text,jsonb,integer,text,text)'];
  persona boolean := to_regprocedure('public.persona_list_save(text,jsonb,integer,text,text)') is not null;   -- W5-14 pode ainda não estar no main
begin
  internal := array(select f from unnest(internal) f where to_regprocedure('public.' || f) is not null);
  session_only := array(select f from unnest(session_only) f where to_regprocedure('public.' || f) is not null);
  -- ───────────── dados: cliente B, pessoas, flags ─────────────
  insert into clients (id, name, handle, organization_id) values ('ws_au_b', 'Auditoria B', 'aub', org);
  insert into guioes (id, client_id, date, n, tema, corpo, hooks) values
    (gb, 'ws_au_b', '2026-10-28', 1, 'Tema secreto B', 'corpo secreto B', '[{"text":"hook secreto B"}]'),
    (gbd, 'ws_au_b', '2026-10-28', 2, 'Tema B eliminado', 'corpo B eliminado', '[]');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (ua_own,'au-own@test.invalid'),(ua_mgr,'au-mgr@test.invalid'),(ua_view,'au-view@test.invalid'),(ub,'au-b@test.invalid'),(ub_own,'au-bown@test.invalid')) v(x, e);
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', ua_own, 'client_staff', 'workspace_owner'), ('numeiro', ua_mgr, 'client_staff', 'manager'),
    ('numeiro', ua_view, 'client_staff', 'viewer'), ('ws_au_b', ub, 'client_staff', 'workspace_admin'), ('ws_au_b', ub_own, 'client_staff', 'workspace_owner');
  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('media.library', org, 'numeiro', 'all'), ('edit.studio', org, 'numeiro', 'all'), ('media.r2', org, 'numeiro', 'all'),
    ('media.library', org, 'ws_au_b', 'all'), ('edit.studio', org, 'ws_au_b', 'all'), ('media.r2', org, 'ws_au_b', 'all'),
    ('guioes.bulk', org, 'numeiro', 'all')
  on conflict do nothing;
  day := (select date from guioes where id = gk);
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon, engine_worker;

  -- ───────────── privilégios (catálogo) ─────────────
  insert into t values ('helpers internos fechados a anon e authenticated', true,
    not exists (select 1 from unnest(internal) f where has_function_privilege('anon', ('public.' || f)::regprocedure, 'execute')
                                                    or has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'execute')));
  insert into t values ('RPCs do worker só para engine_worker', true,
    not exists (select 1 from unnest(worker_fns) f where has_function_privilege('anon', ('public.' || f)::regprocedure, 'execute')
                                                      or has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'execute')
                                                      or not has_function_privilege('engine_worker', ('public.' || f)::regprocedure, 'execute')));
  insert into t values ('RPCs que exigem sessão individual fechadas a anon (defesa em profundidade)', true,
    not exists (select 1 from unnest(session_only) f where has_function_privilege('anon', ('public.' || f)::regprocedure, 'execute')));
  insert into t values ('SECURITY DEFINER das migrações auditadas com search_path fixo', true,
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.prosecdef
                   and (p.oid::regprocedure::text = any (internal || worker_fns || session_only) or p.proname in
                        ('content_delete', 'content_undelete', 'content_deleted_list', 'content_pending_approval', 'workflow_prereqs',
                         'workflow_prereq_set', 'calendar_range', 'content_bulk', '_content_deleted'))
                   and not coalesce(p.proconfig::text[] && array['search_path=public', 'search_path="public"'], false)));
  insert into t values ('tabelas novas fechadas à API (RLS + sem grants)', true,
    not exists (select 1 from unnest(array['media_jobs', 'media_job_outputs', 'persona_lists', 'workflow_prerequisites']) x
                 where to_regclass('public.' || x) is not null and (
                       has_table_privilege('authenticated', ('public.' || x)::regclass, 'select')
                    or has_table_privilege('anon', ('public.' || x)::regclass, 'select')
                    or not (select relrowsecurity from pg_class where oid = ('public.' || x)::regclass))));

  execute 'set local role authenticated';
  -- ───────────── gravações R2 em A e B ─────────────
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  fa := (media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Au_A_front.mp4', 'size', 1000, 'mime', 'video/mp4', 'sha256', sha))->>'version_id')::uuid;
  perform media_upload_complete('numeiro', fa, null);
  sa := (media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'Au_A_side.mp4', 'size', 1100, 'mime', 'video/mp4', 'sha256', sha))->>'version_id')::uuid;
  perform media_upload_complete('numeiro', sa, null);
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role','authenticated')::text, true);
  fb := (media_upload_begin('ws_au_b', null, '{}', jsonb_build_object('name', 'Au_B_front.mp4', 'size', 1200, 'mime', 'video/mp4', 'sha256', sha))->>'version_id')::uuid;
  perform media_upload_complete('ws_au_b', fb, null);
  sb := (media_upload_begin('ws_au_b', null, '{}', jsonb_build_object('name', 'Au_B_side.mp4', 'size', 1300, 'mime', 'video/mp4', 'sha256', sha))->>'version_id')::uuid;
  perform media_upload_complete('ws_au_b', sb, null);

  -- upload pendente de B: A não o vê nem o conclui
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  begin perform media_upload_target('numeiro', fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('upload de B pedido com p_ws=A: não encontrado (P0002)', true, st = 'P0002');
  begin perform media_upload_target('ws_au_b', fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('upload de B pedido com p_ws=B por A: sem permissão (42501)', true, st = '42501');
  begin perform media_upload_complete('numeiro', fb, null); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('concluir upload de B com p_ws=A (P0002)', true, st = 'P0002');
  -- o mesmo cliente, mas outra pessoa: só quem começou o upload o conclui
  perform set_config('request.jwt.claims', json_build_object('sub', ua_mgr, 'role','authenticated')::text, true);
  begin perform media_upload_complete('numeiro', fa, null); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('upload de outra pessoa do mesmo cliente (P0002)', true, st = 'P0002');

  -- worker verifica as quatro
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  for r in select 1 from generate_series(1, 4) loop
    j := media_worker_claim('w-au', array['ingest']);
    perform media_worker_finish('w-au', (j->'job'->>'id')::uuid, true,
      jsonb_build_object('size_bytes', (j->'job'->'input'->>'size_bytes')::bigint, 'sha256', sha, 'proxy_key', 'p/' || (j->'job'->>'id') || '.mp4'));
  end loop;
  execute 'reset role';
  select asset_id into a_fa from media_versions where id = fa;
  select asset_id into a_fb from media_versions where id = fb;
  insert into t values ('fixture: as quatro gravações prontas', true,
    (select count(*) from media_versions where id in (fa, sa, fb, sb) and state = 'pronta' and proxy_state = 'pronta') = 4);

  doc_a := jsonb_set(base_doc, '{source}', '{"cams":{"front":"Au_A_front.mp4","side":"Au_A_side.mp4"},"audio":"side"}');
  doc_b := jsonb_set(base_doc, '{source}', '{"cams":{"front":"Au_B_front.mp4","side":"Au_B_side.mp4"},"audio":"side"}');

  execute 'set local role authenticated';
  -- ───────────── B: documento, estilo, exportação, pacote, frases-persona ─────────────
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role','authenticated')::text, true);
  ev_b := (edit_doc_save('ws_au_b', a_fb, null, doc_b, null, 'import')->'version'->>'id')::uuid;
  perform edit_style_from_doc('ws_au_b', a_fb, null, null, 'Estilo de B', null);
  job_exp_b := (edit_export_request('ws_au_b', a_fb)->>'id')::uuid;
  pkg_b := (edit_package_request('ws_au_b', fb, sb, array[gb])->>'id')::uuid;
  if persona then
    execute 'select persona_list_save($1, $2, 0, ''v1'')' using 'ws_au_b', pl;
    execute 'select persona_list_save($1, $2, 1, ''v2'')' using 'ws_au_b', '[{"id":"p1","text":"O maior do bairro"},{"id":"p2","text":"Rei da noite"}]'::jsonb;
  end if;

  -- ───────────── A: documento ─────────────
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  ev_a := (edit_doc_save('numeiro', a_fa, null, doc_a, null, 'import')->'version'->>'id')::uuid;
  insert into t values ('fixture: documentos e jobs de B criados', true, ev_a is not null and ev_b is not null and job_exp_b is not null and pkg_b is not null);

  -- ───────────── IDs de B com p_ws = A (owner de A) ─────────────
  begin perform media_proxy_access('numeiro', fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('proxy de versão de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform media_proxy_access('ws_au_b', fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('proxy de B com p_ws=B por A (42501)', true, st = '42501');
  begin perform edit_preview_sources('numeiro', a_fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização de ativo de B (P0002)', true, st = 'P0002');
  begin perform edit_preview_sources('numeiro', a_fa, ev_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ativo de A com versão de edição de B (P0002)', true, st = 'P0002');
  begin perform edit_export_request('numeiro', a_fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('exportar ativo de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform edit_export_request('numeiro', a_fa, ev_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('exportar ativo de A com versão de edição de B (P0002)', true, st = 'P0002');
  insert into t values ('lista de exportações de ativo de B vem vazia', true, edit_export_list('numeiro', a_fb) = '[]'::jsonb);
  begin perform edit_export_cancel('numeiro', job_exp_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('cancelar exportação de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform edit_package_request('numeiro', fa, sb, array[gk]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pacote com gravação de B (P0002)', true, st = 'P0002');
  begin perform edit_package_request('numeiro', fa, sa, array[gk, gb]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pacote com guião de B (P0002)', true, st = 'P0002');
  begin perform edit_package_export('numeiro', pkg_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('exportar pacote de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform edit_package_export('ws_au_b', pkg_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('exportar pacote de B com p_ws=B por A (42501)', true, st = '42501');
  insert into t values ('lista de pacotes de A sem os de B', true,
    not exists (select 1 from jsonb_array_elements(edit_package_list('numeiro')) x where (x->>'id')::uuid = pkg_b));
  insert into t values ('lista de documentos de A sem os de B', true,
    not exists (select 1 from jsonb_array_elements(edit_doc_list('numeiro')) x where (x->>'asset_id')::uuid = a_fb));
  begin perform edit_doc_get('numeiro', a_fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('abrir documento de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform edit_doc_save('numeiro', a_fb, ev_b, doc_a); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('gravar documento de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform edit_style_from_doc('numeiro', a_fb, null, null, 'roubado', null); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('estilo a partir de documento de B (P0002)', true, st = 'P0002');
  begin perform edit_style_apply('numeiro', a_fa, ev_a, 'E01'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('aplicar estilo que só existe em B (P0002)', true, st = 'P0002'
    and not exists (select 1 from jsonb_array_elements(edit_saved_styles('numeiro')->'styles') x where x->>'key' = 'E01'));
  begin perform media_review_detail('numeiro', a_fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisão de ativo de B (P0002)', true, st = 'P0002');
  begin perform media_review_detail('numeiro', a_fa, fb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('revisão de ativo de A com versão de B (P0002)', true, st = 'P0002');
  if persona then
  begin perform persona_list_version('numeiro', 2); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('versão de frases-persona que só existe em B (P0002)', true, st = 'P0002');
  insert into t values ('frases-persona de A vazias (nada de B)', true, (persona_list_get('numeiro')->>'version')::int = 0);
  begin perform persona_list_save('ws_au_b', pl, 2); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não grava frases-persona de B (42501)', true, st = '42501');
  begin perform persona_list_get('ws_au_b'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não lê frases-persona de B (42501)', true, st = '42501');
  end if;
  begin perform content_pending_approval('ws_au_b'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não lista aprovações de B (42501)', true, st = '42501');
  begin perform calendar_range('ws_au_b', day, day); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não abre o calendário de B (42501)', true, st = '42501');
  begin perform workflow_prereqs('numeiro', gb); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-requisitos de guião de B com p_ws=A (P0002)', true, st = 'P0002');
  begin perform workflow_prereq_set('ws_au_b', 'production.ready', 'video_approved', true); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não muda pré-requisitos de B (42501)', true, st = '42501');
  begin perform content_deleted_list('ws_au_b'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não lista eliminados de B (42501)', true, st = '42501');
  begin perform media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AuDitBbBbBbBbBbBbBbBbBbBb1/view', 'title', 'x', 'content_id', gb));
    st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ligar ativo de A a guião de B (22023)', true, st = '22023');

  -- ───────────── B elimina um guião; A não descobre que existiu ─────────────
  perform set_config('request.jwt.claims', json_build_object('sub', ub_own, 'role','authenticated')::text, true);
  perform content_transition(gbd, 'archived');
  perform content_delete(gbd, gbd, 'teste');
  insert into t values ('dono de B vê o próprio eliminado', true, _content_deleted(gbd));
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  insert into t values ('_content_deleted não revela a A guião eliminado de B', true, not _content_deleted(gbd));
  begin perform content_undelete(gbd); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('A não recupera eliminado de B (P0002)', true, st = 'P0002');

  -- ───────────── código de equipa (anon) ─────────────
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin perform content_delete(gk, gk, null, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não elimina guiões (42501)', true, st = '42501');
  begin perform content_deleted_list('numeiro', tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não lista eliminados (42501)', true, st = '42501');
  begin perform content_undelete(gbd, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não recupera (42501)', true, st = '42501');
  begin perform workflow_prereq_set('numeiro', 'production.ready', 'video_approved', true, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não muda pré-requisitos (42501)', true, st = '42501');
  if persona then
  begin perform persona_list_get('numeiro', tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não lê frases-persona (42501)', true, st = '42501');
  end if;
  begin perform edit_doc_get('numeiro', a_fa, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não abre o editor (42501)', true, st = '42501');
  begin perform media_review_list('numeiro', '{}', tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não lê a revisão de vídeos (42501)', true, st = '42501');
  begin perform calendar_range('ws_au_b', day, day, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não abre o calendário de B (42501)', true, st = '42501');
  begin perform content_pending_approval('ws_au_b', tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('código de A não lista aprovações de B (42501)', true, st = '42501');
  j := calendar_range('numeiro', day, day, tok);
  insert into t values ('código de equipa: calendário sem camada de revisões', true,
    (j->'layers'->>'reviews')::boolean is false and j->'reviews' = '[]'::jsonb);
  begin perform media_worker_claim('anon-au'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('anon não chama o worker de media (42501)', true, st = '42501');
  execute 'reset role';

  -- conta de B com o código de A não ganha capacidades de sessão individual em A
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role','authenticated')::text, true);
  if persona then
  begin perform persona_list_save('numeiro', pl, 0, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B com o código de A não grava frases-persona (42501)', true, st = '42501');
  end if;
  begin perform content_delete(gk, gk, null, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B com o código de A não elimina (42501)', true, st = '42501');
  begin perform edit_export_request('numeiro', a_fa, null, tok); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('B com o código de A não exporta (42501)', true, st = '42501');

  -- ───────────── RPCs do worker e tabelas fechadas ao browser ─────────────
  begin perform media_worker_claim('x-au'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não reclama jobs de media (42501)', true, st = '42501');
  begin perform media_worker_heartbeat('x-au', pkg_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não faz heartbeat (42501)', true, st = '42501');
  begin perform media_worker_finish('x-au', pkg_b, true, '{}'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não fecha jobs (42501)', true, st = '42501');
  begin perform media_worker_package_save('x-au', pkg_b, gb, 1, doc_b); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não grava documentos do pacote (42501)', true, st = '42501');
  begin perform worker_claim('x-au'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não reclama jobs de agentes (frases-persona) (42501)', true, st = '42501');
  begin perform count(*) from public.media_jobs; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não lê media_jobs (42501)', true, st = '42501');
  if persona then
  begin perform count(*) from public.persona_lists; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não lê persona_lists (42501)', true, st = '42501');
  end if;
  begin perform count(*) from public.workflow_prerequisites; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não lê workflow_prerequisites (42501)', true, st = '42501');
  begin perform count(*) from public.media_job_outputs; st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('browser não lê media_job_outputs (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('exportação de B continua na fila depois das tentativas de A', true,
    (select status from media_jobs where id = job_exp_b) = 'queued' and not (select cancel_requested from media_jobs where id = job_exp_b));

  -- ───────────── pré-visualização só de leitura (dono de A a ver como viewer) ─────────────
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  perform access_preview_start('numeiro', null, 'viewer');
  begin perform edit_doc_save('numeiro', a_fa, ev_a, jsonb_set(doc_a, '{hook,text}', '"outro"')); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não grava documento (42501)', true, st = '42501');
  begin perform edit_export_request('numeiro', a_fa); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não exporta (42501)', true, st = '42501');
  begin perform edit_package_request('numeiro', fa, sa, array[gk]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não pede pacote (42501)', true, st = '42501');
  begin perform edit_style_apply('numeiro', a_fa, ev_a, 'S15'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não aplica estilo (42501)', true, st = '42501');
  if persona then
  begin perform persona_list_save('numeiro', pl, 0); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não aprova frases-persona (42501)', true, st = '42501');
  end if;
  begin perform workflow_prereq_set('numeiro', 'production.ready', 'video_approved', true); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não muda pré-requisitos (42501)', true, st = '42501');
  begin perform content_delete(gk, gk); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não elimina guiões (42501)', true, st = '42501');
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name', 'pv.mp4', 'size', 10, 'mime', 'video/mp4', 'sha256', sha));
    st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: não carrega ficheiros (42501)', true, st = '42501');
  begin perform calendar_range('numeiro', day, day); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pré-visualização: o calendário (leitura) abre', true, st = 'ok');
  perform access_preview_stop('numeiro');
  execute 'reset role';
  insert into t values ('nada gravado durante a pré-visualização', true,
    (select current_version_id from edit_documents where asset_id = a_fa) = ev_a);

  -- ───────────── calendário: sem media.read não há camada de revisões ─────────────
  insert into permission_grants (workspace_id, user_id, capability, effect, reason) values ('numeiro', ua_view, 'media.read', 'deny', 'auditoria');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua_view, 'role','authenticated')::text, true);
  j := calendar_range('numeiro', day, day);
  insert into t values ('viewer sem media.read: calendário sem revisões', true, (j->'layers'->>'reviews')::boolean is false and j->'reviews' = '[]'::jsonb);

  -- ───────────── guião eliminado em A (soft delete) não volta por caminhos novos ─────────────
  perform set_config('request.jwt.claims', json_build_object('sub', ua_mgr, 'role','authenticated')::text, true);
  pkg_a := (edit_package_request('numeiro', fa, sa, array[gd])->>'id')::uuid;   -- pedido antes de eliminar
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  a_d := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AuDitDdDdDdDdDdDdDdDdDdDd1/view', 'title', 'g21_hook1.mp4',
           'tags', jsonb_build_array('hook_1'), 'content_id', gd))->>'id')::uuid;
  perform media_trash('numeiro', a_d, 'para eliminar o guião');
  perform content_transition(gd, 'archived');
  perform content_delete(gd, gd, 'auditoria');
  perform media_restore('numeiro', a_d);   -- ativo recuperado continua ligado ao guião eliminado
  ev_a := (edit_doc_save('numeiro', a_d, null, doc_a, null, 'import')->'version'->>'id')::uuid;
  insert into t values ('fixture: guião eliminado e ativo recuperado ligado a ele', true,
    not exists (select 1 from public.guioes where id = gd) and ev_a is not null);   -- RLS: o eliminado já não se vê

  -- manager (sem scripts.purge) não lê nem reaproveita o guião eliminado
  perform set_config('request.jwt.claims', json_build_object('sub', ua_mgr, 'role','authenticated')::text, true);
  begin perform edit_package_request('numeiro', fa, sa, array[gd], 'S13'); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('pacote com guião eliminado (P0002)', true, st = 'P0002');
  begin perform edit_package_request('numeiro', fa, sa, array[gd]); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('repetir o pedido antigo com guião eliminado (P0002)', true, st = 'P0002');
  j := edit_doc_get('numeiro', a_d);
  insert into t values ('editor não mostra hooks de guião eliminado', true, j->'guiao' = 'null'::jsonb or j->'guiao' is null);
  j := media_review_detail('numeiro', a_d);
  insert into t values ('revisão não mostra tema/hook de guião eliminado', true, j->'item'->'guiao' = 'null'::jsonb or j->'item'->'guiao' is null);
  insert into t values ('lista de documentos não mostra guião eliminado', true,
    exists (select 1 from jsonb_array_elements(edit_doc_list('numeiro')) x where (x->>'asset_id')::uuid = a_d
            and (x->'guiao' is null or x->'guiao' = 'null'::jsonb)));
  insert into t values ('lista de pacotes não mostra o tema do guião eliminado', true,
    not exists (select 1 from jsonb_array_elements(edit_package_list('numeiro')) x, jsonb_array_elements(coalesce(x->'guioes', '[]')) g
                 where g->>'id' = gd and g->>'tema' is not null));
  begin perform media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AuDitEeEeEeEeEeEeEeEeEeEe1/view', 'title', 'x', 'content_id', gd));
    st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('ligar ativo novo a guião eliminado (P0002)', true, st = 'P0002');
  a_x := (media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/1AuDitFfFfFfFfFfFfFfFfFfFf1/view', 'title', 'solto'))->>'id')::uuid;
  begin perform media_asset_save('numeiro', a_x, jsonb_build_object('content_id', gd)); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('religar ativo existente a guião eliminado (P0002)', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', ua_own, 'role','authenticated')::text, true);
  j := content_bulk('numeiro', array[gd, gk], 'tags', '{"mode":"add","tags":["x"]}'::jsonb, null, true);
  insert into t values ('lote: guião eliminado falha como não encontrado e sem fotografia "antes"', true,
    exists (select 1 from jsonb_array_elements(j->'results') x where x->>'id' = gd and not (x->>'ok')::boolean
            and x->>'code' = 'P0002' and (x->'before' is null or x->'before' = 'null'::jsonb))
    and exists (select 1 from jsonb_array_elements(j->'results') x where x->>'id' = gk and (x->>'ok')::boolean));

  -- worker: o pacote pedido antes de eliminar não recria documentos do guião eliminado; nem de guiões fora do pedido
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role engine_worker';
  j := media_worker_claim('w-au', array['package']);
  while (j->'job'->>'id')::uuid is distinct from pkg_a and j is not null loop
    perform media_worker_finish('w-au', (j->'job'->>'id')::uuid, false, null, 'outro', false);
    j := media_worker_claim('w-au', array['package']);
  end loop;
  insert into t values ('fixture: worker apanha o pacote de A', true, (j->'job'->>'id')::uuid = pkg_a);
  begin perform media_worker_package_save('w-au', pkg_a, gd, 1, doc_a); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('worker: guião eliminado depois do pedido (P0002)', true, st = 'P0002');
  begin perform media_worker_package_save('w-au', pkg_a, gk, 1, doc_a); st := 'ok'; exception when others then st := sqlstate; end;
  insert into t values ('worker: guião que não está no pedido (P0002)', true, st = 'P0002');
  perform media_worker_finish('w-au', pkg_a, true, '{}');
  execute 'reset role';
  insert into t values ('nenhum ativo ativo novo ligado ao guião eliminado', true,
    (select count(*) from media_assets where content_id = gd and lifecycle = 'ativo') = 1);   -- só o recuperado

  -- ───────────── auditoria das escritas sensíveis ─────────────
  insert into t values ('auditoria: exportar, pacote, frases-persona, eliminar', true,
    exists (select 1 from audit_events where workspace_id = 'ws_au_b' and action = 'edit.export_requested')
    and exists (select 1 from audit_events where workspace_id = 'ws_au_b' and action = 'edit.package_requested')
    and (not persona or exists (select 1 from audit_events where workspace_id = 'ws_au_b' and action = 'persona.list_saved' and entity_id = 'ws_au_b:2'))
    and exists (select 1 from audit_events where workspace_id = 'numeiro' and action = 'script.deleted' and entity_id = gd));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
