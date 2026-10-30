-- supabase/tests/w8_media.sql : biblioteca de media (FR-08-01..06, ING-01). Isolamento entre clientes, flag, upload com
-- caminho gerado no servidor e políticas do storage, confirmação por tamanho/tipo/checksum, versões imutáveis, filtros,
-- links externos, quota e tipos, acesso por autorização curta, partilha com expiração, lixo, órfãos e eliminação
-- definitiva com confirmação. Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_ag2 uuid := gen_random_uuid(); u_ca uuid := gen_random_uuid();
  u_cc uuid := gen_random_uuid(); u_vw uuid := gen_random_uuid(); u_cb uuid := gen_random_uuid();
  tok text := (select token from studio_tokens where client_id='numeiro' limit 1);
  g1 text := 'numeiro-2026-10-28-01'; gb text := 'ws_med_b-x-01';
  sha1 text := repeat('a', 64); sha2 text := repeat('b', 64); sha3 text := repeat('c', 64); sha4 text := repeat('d', 64);
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; n int;
  a1 uuid; v1 uuid; v2 uuid; v3 uuid; v4 uuid; v5 uuid; p1 text; p2 text; p3 text; p4 text; p5 text;
  la uuid; proj uuid; sh uuid; stok text; vb uuid; pb text;
begin
  insert into clients (id, name, handle, organization_id, timezone) values ('ws_med_b', 'Media B', 'medb', org, 'Asia/Dubai');
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_own,'med-own@test.invalid'),(u_ag,'med-ag@test.invalid'),(u_ag2,'med-ag2@test.invalid'),(u_ca,'med-ca@test.invalid'),
    (u_cc,'med-cc@test.invalid'),(u_vw,'med-vw@test.invalid'),(u_cb,'med-cb@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_ag2, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('numeiro', u_ag, 'agency_staff', 'manager'), ('numeiro', u_ca, 'client_staff', 'workspace_admin'),
    ('numeiro', u_cc, 'client_staff', 'contributor'), ('numeiro', u_vw, 'client_staff', 'viewer'),
    ('ws_med_b', u_cb, 'client_staff', 'workspace_admin');
  insert into guioes (id, client_id, date, n, tema, hooks, corpo, origem, status)
  values (gb, 'ws_med_b', current_date, 1, 'B', '[{"text":"Hook B"}]', 'Corpo B', 'fixture', 'aprovado');
  insert into projects (workspace_id, name) values ('numeiro', 'Campanha Dubai') returning id into proj;
  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;
  execute 'set local role authenticated';

  -- ── flag desligada ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_library('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada (staff da agência): 55000', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  j := media_library('numeiro');
  insert into t values ('fase owner: o dono da agência vê a biblioteca vazia', true, (j->>'total')::int = 0 and j->'can'->>'policy' = 'true');
  insert into t values ('sem antivírus explícito e custo indisponível', true,
    not (j->'antivirus'->>'available')::boolean and j->'antivirus'->>'reason' like 'Sem antivírus%' and not (j->'cost'->>'available')::boolean);
  insert into t values ('política por defeito: 50 MiB por ficheiro (teto do bucket), 5 GiB de quota, 30 dias de lixo', true,
    (j->'policy'->>'max_file_bytes')::bigint = 52428800 and (j->'policy'->>'quota_bytes')::bigint = 5368709120 and (j->'policy'->>'trash_days')::int = 30);
  execute 'reset role';
  insert into feature_flags (key, organization_id, workspace_id, stage) select 'media.library', org, w, 'all' from unnest(array['numeiro','ws_med_b']) w;
  execute 'set local role authenticated';

  -- ── isolamento de leitura ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform media_library('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não lê a biblioteca de A (42501)', true, st = '42501');
  begin perform media_library('nao-existe'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente inexistente = sem acesso (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag2, 'role','authenticated')::text, true);
  begin perform media_library('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem atribuição não lê (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_library('ws_med_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff com acesso a A não lê B (42501)', true, st = '42501');
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  begin perform media_library('numeiro', '{}', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não tem media (42501)', true, st = '42501');
  execute 'reset role'; execute 'set local role authenticated';

  -- ── FR-08-01: registar upload ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','a.mp4','size',1000,'mime','video/mp4','sha256',sha1)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('leitor não carrega (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, jsonb_build_object('title', 'Final hook 1'),
         jsonb_build_object('name', '../../Vídeo Final (1).MP4', 'size', 1000, 'mime', 'video/mp4', 'sha256', sha1));
  a1 := (j->>'asset_id')::uuid; v1 := (j->>'version_id')::uuid; p1 := j->>'path';
  insert into t values ('caminho gerado no servidor: <ws>/<asset>/<versão>/<nome-sanitizado>', true, p1 = 'numeiro/' || a1 || '/1/video-final-1.mp4');
  execute 'reset role';
  insert into t values ('versão nasce pendente com expiração', true,
    (select state = 'pendente' and upload_expires_at > now() + interval '23 hours' from media_versions where id = v1));
  execute 'set local role authenticated';
  execute 'reset role';
  insert into t values ('tipo deduzido do MIME: vídeo', true, (select kind from media_assets where id = a1) = 'video');
  execute 'set local role authenticated';
  j := media_upload_begin('numeiro', null, jsonb_build_object('title', 'Final hook 1'),
         jsonb_build_object('name', '../../Vídeo Final (1).MP4', 'size', 1000, 'mime', 'video/mp4', 'sha256', sha1));
  insert into t values ('repetir o registo é idempotente (mesma versão)', true, (j->>'version_id')::uuid = v1 and (j->>'reused')::boolean);
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','a.zip','size',10,'mime','application/zip','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('tipo não permitido (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', null, '{"kind":"audio"}', jsonb_build_object('name','a.mp4','size',10,'mime','video/mp4','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('MIME que não corresponde ao tipo (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','a.mp4','size',52428801,'mime','video/mp4','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('acima do máximo por ficheiro (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','a.mp4','size',10,'mime','video/mp4','sha256','xyz')); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('sem SHA-256 válido (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', null, jsonb_build_object('content_id', gb), jsonb_build_object('name','a.mp4','size',10,'mime','video/mp4','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('ligar a um guião de B (22023)', true, st = '22023');

  -- ── storage.objects: só o caminho pendente do próprio ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p1, u_ca, '{"size":1000,"mimetype":"video/mp4"}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('outra pessoa não escreve no caminho pendente de quem registou', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin insert into storage.objects (bucket_id, name, owner, metadata) values ('media', 'numeiro/' || gen_random_uuid() || '/1/x.mp4', u_cc, '{}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('caminho escolhido pelo browser é recusado', true, st = '42501');
  begin perform media_upload_complete('numeiro', v1, sha1); st := 'none'; exception when others then st := sqlstate; end;
  execute 'reset role';
  insert into t values ('confirmar sem objeto: P0002 (fica pendente para retentar)', true, st = 'P0002' and (select state from media_versions where id = v1) = 'pendente');
  execute 'set local role authenticated';
  j := media_upload_target('numeiro', v1);
  insert into t values ('retomar devolve o mesmo caminho', true, j->>'path' = p1 and not (j->>'object_exists')::boolean);
  insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p1, u_cc, '{"size":1000,"mimetype":"video/mp4"}');
  insert into t values ('quem registou escreve no seu caminho pendente', true, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform media_upload_complete('ws_med_b', v1, sha1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não confirma uma versão de A trocando o cliente', true, st in ('P0002', '42501'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := media_upload_complete('numeiro', v1, sha1);
  insert into t values ('confirmado com checksum conferido: pronta', true,
    j->>'state' = 'pronta' and (j->'version'->>'checksum_verified')::boolean and (j->'asset'->'current'->>'id')::uuid = v1);
  insert into t values ('confirmar outra vez é idempotente', true, (media_upload_complete('numeiro', v1, sha1)->>'repeated')::boolean);

  -- ── FR-08-04: versões novas (substituir) e falhas de confirmação ──
  j := media_upload_begin('numeiro', a1, '{}', jsonb_build_object('name','v2.mp4','size',2000,'mime','video/mp4','sha256',sha2));
  v2 := (j->>'version_id')::uuid; p2 := j->>'path';
  insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p2, u_cc, '{"size":1999,"mimetype":"video/mp4"}');
  j := media_upload_complete('numeiro', v2, sha2);
  execute 'reset role';
  insert into t values ('tamanho diferente: versão falhou e a atual não muda', true,
    j->>'state' = 'falhou' and j->>'reason' like 'tamanho_diferente%' and (select current_version_id from media_assets where id = a1) = v1);
  execute 'set local role authenticated';
  j := media_upload_begin('numeiro', a1, '{}', jsonb_build_object('name','v3.mp4','size',3000,'mime','video/mp4','sha256',sha3));
  v3 := (j->>'version_id')::uuid; p3 := j->>'path';
  insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p3, u_cc, '{"size":3000,"mimetype":"video/mp4"}');
  j := media_upload_complete('numeiro', v3, sha4);
  insert into t values ('checksum do servidor diferente: falhou', true, j->>'state' = 'falhou' and j->>'reason' like 'checksum_diferente%');
  j := media_upload_begin('numeiro', a1, '{}', jsonb_build_object('name','v4.mp4','size',4000,'mime','video/mp4','sha256',sha4));
  v4 := (j->>'version_id')::uuid; p4 := j->>'path';
  insert into t values ('versão nova numera a seguir (4)', true, (j->>'version_no')::int = 4 and p4 like '%/4/v4.mp4');
  insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p4, u_cc, '{"size":4000,"mimetype":"video/mp4"}');
  j := media_upload_complete('numeiro', v4, null);
  insert into t values ('sem checksum do servidor: pronta mas não conferida', true, j->>'state' = 'pronta' and not (j->'version'->>'checksum_verified')::boolean);
  execute 'reset role';
  insert into t values ('substituir: a versão 4 passa a atual, histórico com 4', true,
    (select current_version_id from media_assets where id = a1) = v4 and jsonb_array_length(media_asset('numeiro', a1)->'history') = 4);
  execute 'set local role authenticated';
  execute 'reset role';
  insert into t values ('evento asset.uploaded emitido por versão pronta', true,
    (select count(*) from domain_events where type = 'asset.uploaded' and entity_id = a1::text) = 2);
  execute 'set local role authenticated';
  execute 'reset role';
  begin update media_versions set size_bytes = 1 where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão pronta é imutável (tamanho)', true, st = '42501');
  begin update media_versions set state = 'pendente' where id = v1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão pronta não volta a pendente', true, st = '42501');
  begin delete from media_versions where id = v2; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versões não se apagam', true, st = '42501');
  begin delete from media_assets where id = a1; st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ativos não se apagam por SQL', true, st = '42501');
  execute 'set local role authenticated';

  -- ── leitura do objeto só com autorização curta ──
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p1;
  insert into t values ('sem autorização a versão pronta não se lê no storage', true, n = 0);
  j := media_access('numeiro', v1, 'preview');
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p1;
  insert into t values ('depois de media_access (pré-visualizar) lê-se', true, n = 1 and j->>'path' = p1 and (j->>'ttl_seconds')::int = 300);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vw, 'role','authenticated')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p1;
  insert into t values ('a autorização é da pessoa, não do caminho', true, n = 0);
  perform media_access('numeiro', v1, 'preview');
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p1;
  insert into t values ('leitor pré-visualiza', true, n = 1);
  begin perform media_access('numeiro', v1, 'download'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não descarrega (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'media' and name like 'numeiro/%';
  insert into t values ('B não vê objetos de A no storage', true, n = 0);
  begin perform media_access('numeiro', v1, 'download'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não pede acesso a A (42501)', true, st = '42501');
  begin perform media_access('ws_med_b', v1, 'download'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('troca de cliente com o id de A: P0002', true, st = 'P0002');
  begin perform media_asset('ws_med_b', a1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ativo de A pelo cliente B: P0002', true, st = 'P0002');
  execute 'reset role';
  update media_access_grants set expires_at = now() - interval '1 second';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p1;
  insert into t values ('autorização expirada deixa de dar leitura', true, n = 0);
  j := media_access('numeiro', v4, 'download');
  insert into t values ('colaborador descarrega (120 s, nome original)', true, (j->>'ttl_seconds')::int = 120 and j->>'filename' = 'v4.mp4');

  -- ── FR-08-02: metadados, filtros e pesquisa ──
  j := media_asset_save('numeiro', a1, jsonb_build_object('title', 'Final hook 1 Dubai', 'tags', jsonb_build_array('#Dubai', 'final', 'dubai'),
         'project_id', proj, 'format', '9:16', 'status', 'final', 'content_id', g1));
  insert into t values ('etiquetas normalizadas e sem repetição', true, j->'tags' = '["dubai","final"]'::jsonb and j->'project'->>'name' = 'Campanha Dubai');
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('notes', 'x'), 1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('edição concorrente: PT409', true, st = 'PT409');
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('owner', 'x')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('campo desconhecido (22023)', true, st = '22023');
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('content_id', gb)); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('não liga a guião de outro cliente (22023)', true, st = '22023');
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('take_id', gen_random_uuid())); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('take de outro guião (22023)', true, st = '22023');
  insert into t values ('pesquisa por título/etiqueta', true, (media_library('numeiro', '{"q":"DUBAI"}')->>'total')::int = 1);
  insert into t values ('filtro por etiqueta, campanha, formato, estado e guião', true,
    (media_library('numeiro', jsonb_build_object('tag', 'final', 'project_id', proj, 'format', '9:16', 'status', 'final', 'content_id', g1))->>'total')::int = 1);
  insert into t values ('filtro por tipo sem resultados', true, (media_library('numeiro', '{"kind":"audio"}')->>'total')::int = 0);
  insert into t values ('ligações aparecem no ativo', true, media_asset('numeiro', a1)->'content'->>'id' = g1);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('title', 'roubado')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não edita ativos de A (42501)', true, st = '42501');
  insert into t values ('B não vê os ativos de A na sua biblioteca', true, (media_library('ws_med_b')->>'total')::int = 0);

  -- ── links externos (ING-01: o Drive fica fora da app) ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := media_link_add('numeiro', null, jsonb_build_object('url', 'https://drive.google.com/file/d/abc/view', 'title', 'Bruto sessão 28/10'));
  la := (j->>'id')::uuid;
  insert into t values ('link externo registado sem descarregar', true, j->>'kind' = 'link_externo' and j->'current'->>'source' = 'link' and j->'current'->>'state' = 'pronta');
  begin perform media_link_add('numeiro', null, jsonb_build_object('url', 'http://drive.google.com/x')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link sem https (22023)', true, st = '22023');
  j := media_link_add('numeiro', la, jsonb_build_object('url', 'https://drive.google.com/file/d/def/view'));
  insert into t values ('link novo = versão 2', true, (j->'current'->>'version_no')::int = 2);
  begin perform media_access('numeiro', (j->'current'->>'id')::uuid, 'download'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link externo não gera URL assinado (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', la, '{}', jsonb_build_object('name','a.mp4','size',10,'mime','video/mp4','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('link externo não recebe ficheiros (22023)', true, st = '22023');

  -- ── FR-08-05: política (só o dono da agência), quota e tipos ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  begin perform media_policy_save('numeiro', '{"quota_bytes": 104857600}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('admin do cliente não muda a quota (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_policy_save('numeiro', '{"quota_bytes": 104857600}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência não muda a quota (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_own, 'role','authenticated')::text, true);
  begin perform media_policy_save('numeiro', '{"max_file_bytes": 104857600}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('máximo acima do teto do bucket (22023)', true, st = '22023');
  begin perform media_policy_save('numeiro', '{"allowed_mime": ["application/zip"]}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tipo fora do bucket (22023)', true, st = '22023');
  j := media_policy_save('numeiro', '{"quota_bytes": 104857600, "allowed_mime": ["video/mp4", "image/png"], "trash_days": 7}');
  insert into t values ('dono da agência define quota, tipos e lixo', true,
    (j->>'quota_bytes')::bigint = 104857600 and (j->>'trash_days')::int = 7 and (j->>'customized')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','a.mp3','size',10,'mime','audio/mpeg','sha256',sha2)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('tipo retirado pela política do cliente (22023)', true, st = '22023');
  begin perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','grande.mp4','size',52428800,'mime','video/mp4','sha256',sha2));
    perform media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','grande2.mp4','size',52428800,'mime','video/mp4','sha256',sha3)); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('quota (com reservas pendentes) excedida (22023)', true, st = '22023');
  j := media_library('numeiro');
  insert into t values ('uso: bytes guardados reais', true, (j->'usage'->>'stored_bytes')::bigint = 1000 + 1999 + 3000 + 4000);
  insert into t values ('uso: órfãos contados à parte', true, (j->'usage'->>'orphan_bytes')::bigint = 1999 + 3000);
  execute 'reset role';
  insert into t values ('cliente B tem a política por defeito', true, (select count(*) from media_policies where workspace_id = 'ws_med_b') = 0);
  execute 'set local role authenticated';

  -- ── FR-08-03: partilha com expiração e auditoria ──
  begin perform media_share_create('numeiro', v4, 24); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não partilha (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_share_create('numeiro', v4, 500); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('validade acima de 7 dias (22023)', true, st = '22023');
  begin perform media_share_create('numeiro', v2, 24); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão falhada não se partilha (22023)', true, st = '22023');
  j := media_share_create('numeiro', v4, 24, 'para o cliente');
  sh := (j->>'id')::uuid; stok := j->>'token';
  insert into t values ('link criado; token só na resposta', true, stok ~ '^[0-9a-f]{48}$'
    and not exists (select 1 from jsonb_array_elements(media_asset('numeiro', a1)->'shares') x where x ? 'token' or x ? 'token_hash'));
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p4;
  insert into t values ('sem abrir o link, anónimo não lê', true, n = 0);
  j := media_share_open(stok);
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p4;
  insert into t values ('abrir o link dá leitura de 60 s ao objeto partilhado (só esse)', true, j->>'path' = p4 and n = 1
    and (select count(*) from storage.objects where bucket_id = 'media' and name = p1) = 0);
  begin perform media_share_open(left(stok, 47) || 'f'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('token adulterado: P0002', true, st = 'P0002' or left(stok, 47) || 'f' = stok);
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  begin perform media_share_revoke('numeiro', sh); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('B não revoga links de A (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  perform media_share_revoke('numeiro', sh);
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'media' and name = p4;
  insert into t values ('revogar corta a leitura já concedida', true, n = 0);
  begin perform media_share_open(stok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link revogado: P0002', true, st = 'P0002');
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  stok := media_share_create('numeiro', v4, 1)->>'token';
  execute 'reset role';
  update media_shares set expires_at = now() - interval '1 second' where token_hash = encode(extensions.digest(stok, 'sha256'), 'hex');
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  begin perform media_share_open(stok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('link expirado: P0002', true, st = 'P0002');
  execute 'reset role';
  insert into t values ('partilha auditada (criar, abrir, revogar)', true,
    exists (select 1 from audit_events where action = 'media.share_created' and entity_id = a1::text)
    and exists (select 1 from audit_events where action = 'media.share_opened' and entity_id = a1::text and actor_kind = 'system')
    and exists (select 1 from audit_events where action = 'media.share_revoked' and entity_id = a1::text));
  execute 'set local role authenticated';

  -- ── FR-08-06: lixo e recuperação ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  stok := media_share_create('numeiro', v4, 24)->>'token';
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := media_trash('numeiro', a1, 'repetido');
  insert into t values ('lixo com prazo da política (7 dias)', true, j->>'lifecycle' = 'no_lixo'
    and (j->>'purge_after')::timestamptz between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour');
  insert into t values ('no lixo sai da vista ativos e entra na vista lixo', true,
    not exists (select 1 from jsonb_array_elements(media_library('numeiro')->'assets') x where (x->>'id')::uuid = a1)
    and exists (select 1 from jsonb_array_elements(media_library('numeiro', '{"view":"lixo"}')->'assets') x where (x->>'id')::uuid = a1));
  execute 'reset role';
  insert into t values ('mandar para o lixo revoga os links', true, not exists (select 1 from media_shares where asset_id = a1 and revoked_at is null));
  execute 'set local role authenticated';
  begin perform media_asset_save('numeiro', a1, jsonb_build_object('title', 'x')); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ativo no lixo não se edita (22023)', true, st = '22023');
  j := media_restore('numeiro', a1);
  insert into t values ('recuperar volta a ativo', true, j->>'lifecycle' = 'ativo' and j->>'purge_after' is null);
  perform media_trash('numeiro', a1, 'agora sim');

  -- ── órfãos: listar, limpar com confirmação, apagar pela API do storage ──
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','abandonado.png','size',500,'mime','image/png','sha256',sha1));
  v5 := (j->>'version_id')::uuid; p5 := j->>'path';
  execute 'reset role';
  update media_versions set upload_expires_at = now() - interval '1 minute' where id = v5;
  execute 'set local role authenticated';
  begin insert into storage.objects (bucket_id, name, owner, metadata) values ('media', p5, u_cc, '{"size":500,"mimetype":"image/png"}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('upload expirado já não escreve no storage', true, st = '42501');
  begin perform media_library('numeiro', '{"view":"orfaos"}'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('colaborador não vê órfãos (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  j := media_library('numeiro', '{"view":"orfaos"}');
  insert into t values ('órfãos: falhados e pendentes expirados', true, jsonb_array_length(j->'orphans') = 3 and (j->'counts'->>'orfaos')::int = 3);
  begin perform media_purge_begin('numeiro', 'orfaos', array[v2, v3, v5], 'sim'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('sem escrever APAGAR não apaga (22023)', true, st = '22023');
  begin perform media_purge_begin('numeiro', 'orfaos', array[v2, v4], 'APAGAR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão pronta não é órfã (22023)', true, st = '22023');
  delete from storage.objects where bucket_id = 'media' and name = p4;
  get diagnostics n = row_count;
  insert into t values ('versão pronta de ativo não pedido não se apaga no storage', true, n = 0);
  j := media_purge_begin('numeiro', 'orfaos', array[v2, v3, v5], 'APAGAR');
  insert into t values ('begin devolve os caminhos', true, jsonb_array_length(j->'objects') = 3);
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  delete from storage.objects where bucket_id = 'media' and name in (p2, p3);
  get diagnostics n = row_count;
  insert into t values ('sem media.manage não apaga objetos', true, n = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ca, 'role','authenticated')::text, true);
  delete from storage.objects where bucket_id = 'media' and name in (p2, p3);
  get diagnostics n = row_count;
  insert into t values ('media.manage apaga os objetos órfãos pela política', true, n = 2);
  j := media_purge_finish('numeiro', 'orfaos', array[v2, v3, v5]);
  execute 'reset role';
  insert into t values ('finish marca apagadas só as que já não existem', true, (j->>'versions_deleted')::int = 3
    and (select count(*) from media_versions where id in (v2, v3, v5) and state = 'apagada') = 3);
  execute 'set local role authenticated';

  -- ── eliminação definitiva do lixo ──
  begin perform media_purge_begin('numeiro', 'lixo', array[la], 'APAGAR'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('ativo fora do lixo não se apaga (22023)', true, st = '22023');
  j := media_purge_begin('numeiro', 'lixo', array[a1], 'APAGAR');
  insert into t values ('lixo: caminhos das versões ainda guardadas', true, jsonb_array_length(j->'objects') = 2);
  j := media_purge_finish('numeiro', 'lixo', array[a1]);
  insert into t values ('enquanto o objeto existe, nada fica eliminado', true, (j->>'assets_purged')::int = 0 and jsonb_array_length(j->'remaining') = 2);
  delete from storage.objects where bucket_id = 'media' and name in (p1, p4);
  get diagnostics n = row_count;
  insert into t values ('pedido de eliminação permite apagar os objetos', true, n = 2);
  j := media_purge_finish('numeiro', 'lixo', array[a1]);
  execute 'reset role';
  insert into t values ('ativo eliminado (lápide), versões apagadas', true, (j->>'assets_purged')::int = 1
    and (select lifecycle from media_assets where id = a1) = 'eliminado'
    and (select count(*) from media_versions where asset_id = a1 and state <> 'apagada') = 0);
  execute 'set local role authenticated';
  begin perform media_restore('numeiro', a1); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('eliminado não se recupera (22023)', true, st = '22023');
  begin perform media_access('numeiro', v4, 'preview'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('versão apagada não dá acesso (22023)', true, st = '22023');

  -- ── abandonar, B no seu cliente, removido ──
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  j := media_upload_begin('numeiro', null, '{}', jsonb_build_object('name','x.png','size',10,'mime','image/png','sha256',sha2));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform media_upload_abandon('numeiro', (j->>'version_id')::uuid); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('outra pessoa sem media.manage não desiste por mim (P0002)', true, st = 'P0002');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  insert into t values ('desistir deixa a versão como órfã', true, media_upload_abandon('numeiro', (j->>'version_id')::uuid, 'mudei de ideias')->>'state' = 'falhou');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cb, 'role','authenticated')::text, true);
  j := media_upload_begin('ws_med_b', null, '{}', jsonb_build_object('name','b.png','size',10,'mime','image/png','sha256',sha1));
  vb := (j->>'version_id')::uuid; pb := j->>'path';
  insert into t values ('B carrega no seu cliente com o prefixo de B', true, pb like 'ws_med_b/%');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cc, 'role','authenticated')::text, true);
  begin insert into storage.objects (bucket_id, name, owner, metadata) values ('media', pb, u_cc, '{"size":10,"mimetype":"image/png"}'); st := 'none';
  exception when others then st := sqlstate; end;
  insert into t values ('A não escreve no caminho pendente de B', true, st = '42501');
  execute 'reset role';
  delete from workspace_access where user_id = u_cc;
  execute 'set local role authenticated';
  begin perform media_library('numeiro'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('removido deixa de ler (42501)', true, st = '42501');
  execute 'reset role';
  insert into t values ('tabelas fechadas a leitura direta', true,
    not has_table_privilege('authenticated', 'public.media_assets', 'select') and not has_table_privilege('authenticated', 'public.media_versions', 'select')
    and not has_table_privilege('anon', 'public.media_shares', 'select') and not has_table_privilege('authenticated', 'public.media_access_grants', 'select')
    and not has_table_privilege('authenticated', 'public.media_policies', 'select'));
  insert into t values ('capacidades e flag registadas', true,
    (select count(*) from capabilities where key in ('media.read','media.upload','media.download','media.share','media.manage','media.policy.manage') and status = 'ativo') = 6
    and exists (select 1 from feature_flag_defs where key = 'media.library' and default_stage = 'owner')
    and exists (select 1 from storage.buckets where id = 'media' and not public and file_size_limit = 52428800));
  insert into t values ('auditoria do ciclo (upload, acesso, lixo, eliminação, política)', true,
    (select count(distinct action) from audit_events where action in ('media.upload_started', 'media.version_ready', 'media.upload_failed', 'media.accessed',
      'media.trashed', 'media.restored', 'media.purge_requested', 'media.purged', 'media.policy_updated', 'media.upload_abandoned')) = 10);
  insert into t values ('nome desconhecido no storage: negado', true, not public._media_object_can('select', 'numeiro/x/1/y.mp4'));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
