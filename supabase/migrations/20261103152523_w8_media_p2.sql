-- W8 · Biblioteca de media, parte 2 de 3: leitura, metadados, links externos, upload (registar, alvo, concluir, desistir),
-- acesso por URL assinada curta, lixo e recuperação (FR-08-01..05; ADR-0038).
-- Todas as RPCs: security definer, capacidade + cliente verificados no servidor, flag media.library, auditoria.
-- Expand (só aditivo): funções novas. Rollback no fim.

create or replace function public._media_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, p_entity);
  if not public._flag_on('media.library', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A biblioteca de media ainda não está ligada neste cliente.';
  end if;
end $$;

create or replace function public._media_uid() returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'nao_autenticado' using errcode = '28000', detail = 'A biblioteca precisa de uma sessão individual.'; end if;
  return auth.uid();
end $$;

create or replace function public._media_label(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(display_name, '') from profiles where user_id = p_uid), (select email from auth.users where id = p_uid))
$$;

create or replace function public._media_audit(p_ws text, p_action text, p_type text, p_id text, p_before jsonb, p_after jsonb) returns void
language sql security definer set search_path = public as $$
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  select auth.uid(), case when auth.uid() is null then 'system' else 'user' end, coalesce(public._media_label(auth.uid()), 'link de partilha'),
         c.organization_id, p_ws, p_action, p_type, p_id, p_before, p_after, 'media:' || p_id
    from clients c where c.id = p_ws
$$;

create or replace function public._media_version_json(v media_versions) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when v.id is null then null else jsonb_build_object(
    'id', v.id, 'version_no', v.version_no, 'source', v.source, 'state', v.state, 'original_name', v.original_name,
    'size_bytes', v.size_bytes, 'mime', v.mime, 'sha256', v.sha256, 'checksum_verified', v.checksum_verified,
    'external_url', v.external_url, 'upload_expires_at', v.upload_expires_at, 'completed_at', v.completed_at,
    'failed_reason', v.failed_reason, 'deleted_at', v.deleted_at, 'created_at', v.created_at, 'uploaded_label', v.uploaded_label,
    'mine', v.uploaded_by = auth.uid(),
    'expired', v.state = 'pendente' and v.upload_expires_at <= now()) end
$$;

create or replace function public._media_asset_json(a media_assets) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', a.id, 'kind', a.kind, 'title', a.title, 'tags', to_jsonb(a.tags), 'format', a.format, 'status', a.status, 'notes', a.notes,
    'project', (select jsonb_build_object('id', p.id, 'name', p.name) from projects p where p.id = a.project_id),
    'content', (select jsonb_build_object('id', g.id, 'label', g.date || ' · ' || g.n || ' · ' || coalesce(g.tema, 'sem tema')) from guioes g where g.id = a.content_id),
    'take_id', a.take_id, 'publication_id', a.publication_id,
    'lifecycle', a.lifecycle, 'trashed_at', a.trashed_at, 'trashed_label', a.trashed_label, 'trash_reason', a.trash_reason, 'purge_after', a.purge_after,
    'created_at', a.created_at, 'created_label', a.created_label, 'updated_at', a.updated_at, 'lock_version', a.lock_version,
    'current', (select public._media_version_json(v) from media_versions v where v.id = a.current_version_id),
    'pending', (select public._media_version_json(v) from media_versions v where v.asset_id = a.id and v.state = 'pendente'
                 order by v.version_no desc limit 1),
    'versions', (select count(*) from media_versions v where v.asset_id = a.id))
$$;

-- ───────────── leitura ─────────────
-- p_filters: view (ativos | lixo | orfaos), q, kind, status, format, project_id, tag, limit, offset.
create or replace function public.media_library(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := coalesce(p_filters, '{}'); view text := coalesce(nullif(f->>'view', ''), 'ativos'); q text := nullif(btrim(f->>'q'), '');
        lim int := least(greatest(coalesce((f->>'limit')::int, 100), 1), 200); off int := greatest(coalesce((f->>'offset')::int, 0), 0);
        uid uuid := auth.uid(); can jsonb; total int; items jsonb; orphans jsonb := '[]';
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.library', p_ws);
  if view not in ('ativos', 'lixo', 'orfaos') then raise exception 'vista_invalida' using errcode = '22023'; end if;
  can := jsonb_build_object('read', true, 'upload', public.ws_can('media.upload', p_ws, p_token), 'download', public.ws_can('media.download', p_ws, p_token),
    'share', public.ws_can('media.share', p_ws, p_token), 'manage', public.ws_can('media.manage', p_ws, p_token),
    'policy', coalesce(public._org_can('media.policy.manage', (select organization_id from clients where id = p_ws), uid), false));
  if view = 'orfaos' then
    if not (can->>'manage')::boolean then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]') into orphans from (
      select public._media_version_json(v) || jsonb_build_object('asset_id', a.id, 'asset_title', a.title, 'asset_kind', a.kind,
               'object_exists', exists (select 1 from storage.objects o where o.bucket_id = 'media' and o.name = v.storage_path)) as x
        from media_versions v join media_assets a on a.id = v.asset_id
       where v.workspace_id = p_ws and v.source = 'upload' and (v.state = 'falhou' or (v.state = 'pendente' and v.upload_expires_at <= now()))
       limit 500) s;
  end if;
  with base as (
    select a.* from media_assets a
     where a.workspace_id = p_ws
       and a.lifecycle = case view when 'lixo' then 'no_lixo' else 'ativo' end
       and (q is null or a.title ilike '%' || q || '%' or exists (select 1 from unnest(a.tags) t where t ilike '%' || q || '%'))
       and (f->>'kind' is null or a.kind = f->>'kind')
       and (f->>'status' is null or a.status = f->>'status')
       and (f->>'format' is null or a.format = f->>'format')
       and (f->>'project_id' is null or a.project_id::text = f->>'project_id')
       and (f->>'tag' is null or lower(f->>'tag') = any(a.tags))
       and (f->>'content_id' is null or a.content_id = f->>'content_id'))
  select (select count(*) from base),
         coalesce((select jsonb_agg(public._media_asset_json(b) order by b.updated_at desc)
                     from (select * from base order by updated_at desc limit lim offset off) b), '[]')
    into total, items;
  return jsonb_build_object(
    'workspace', p_ws, 'timezone', (select timezone from clients where id = p_ws), 'view', view, 'can', can,
    'policy', public._media_policy(p_ws), 'usage', public._media_usage(p_ws),
    'antivirus', jsonb_build_object('available', false, 'reason', 'Sem antivírus: não há serviço de análise ligado. Os ficheiros não são analisados.'),
    'cost', jsonb_build_object('available', false, 'reason', 'Custo em euros indisponível: não há preço por GB configurado.'),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name) from projects p
                           where p.workspace_id = p_ws and p.status = 'ativa'), '[]'),
    'tags', coalesce((select jsonb_agg(t order by n desc, t) from (select t, count(*) n from media_assets a, unnest(a.tags) t
                       where a.workspace_id = p_ws and a.lifecycle = 'ativo' group by t order by n desc, t limit 30) s), '[]'),
    'counts', jsonb_build_object(
      'ativos', (select count(*) from media_assets where workspace_id = p_ws and lifecycle = 'ativo'),
      'lixo', (select count(*) from media_assets where workspace_id = p_ws and lifecycle = 'no_lixo'),
      'orfaos', case when (can->>'manage')::boolean then (select count(*) from media_versions v where v.workspace_id = p_ws and v.source = 'upload'
                   and (v.state = 'falhou' or (v.state = 'pendente' and v.upload_expires_at <= now()))) end),
    'total', total, 'limit', lim, 'offset', off, 'assets', items, 'orphans', orphans);
end $$;

create or replace function public.media_asset(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a media_assets;
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.asset', p_id::text);
  select * into a from media_assets where id = p_id and workspace_id = p_ws;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002', detail = 'Este ativo não existe neste cliente ou não tens acesso.'; end if;
  return public._media_asset_json(a) || jsonb_build_object(
    'history', coalesce((select jsonb_agg(public._media_version_json(v) order by v.version_no desc) from media_versions v where v.asset_id = a.id), '[]'),
    'shares', case when public.ws_can('media.share', p_ws, p_token) then coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'version_id', s.version_id, 'version_no', (select version_no from media_versions where id = s.version_id),
        'expires_at', s.expires_at, 'note', s.note, 'open_count', s.open_count, 'last_opened_at', s.last_opened_at,
        'created_label', s.created_label, 'created_at', s.created_at, 'revoked_at', s.revoked_at,
        'active', s.revoked_at is null and s.expires_at > now()) order by s.created_at desc) from media_shares s where s.asset_id = a.id), '[]') end,
    'options', jsonb_build_object(
      'contents', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'label', g.date || ' · ' || g.n || ' · ' || coalesce(g.tema, 'sem tema')) order by g.date desc, g.n)
                   from (select * from guioes where client_id = p_ws order by date desc, n limit 120) g), '[]'),
      'takes', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'label', t.block_key || ' · take ' || t.take_number) order by t.block_key, t.take_number)
                   from takes t where t.workspace_id = p_ws and t.content_id = a.content_id), '[]'),
      'publications', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'label', p.platform || ' · ' || to_char(p.scheduled_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC · ' || p.status) order by p.scheduled_at)
                   from pub_publications p where p.workspace_id = p_ws and p.content_id = a.content_id), '[]')));
end $$;

-- ───────────── metadados ─────────────
create or replace function public._media_apply_fields(a media_assets, p jsonb, p_allowed text[]) returns media_assets
language plpgsql stable security definer set search_path = public as $$
declare k text;
begin
  for k in select jsonb_object_keys(coalesce(p, '{}')) loop
    if not k = any(p_allowed) then raise exception 'campo_desconhecido:%', k using errcode = '22023'; end if;
  end loop;
  if p ? 'title' then a.title := btrim(coalesce(p->>'title', ''));
    if char_length(a.title) not between 1 and 160 then raise exception 'titulo_invalido' using errcode = '22023', detail = 'Título entre 1 e 160 caracteres.'; end if; end if;
  if p ? 'tags' then a.tags := public._media_tags(p->'tags'); end if;
  if p ? 'project_id' then a.project_id := nullif(p->>'project_id', '')::uuid; end if;
  if p ? 'format' then a.format := nullif(p->>'format', '');
    if a.format is not null and a.format not in ('9:16', '16:9', '1:1', '4:5', 'outro') then raise exception 'formato_invalido' using errcode = '22023'; end if; end if;
  if p ? 'status' then a.status := coalesce(nullif(p->>'status', ''), 'em_trabalho');
    if a.status not in ('em_trabalho', 'final', 'arquivado') then raise exception 'estado_invalido' using errcode = '22023'; end if; end if;
  if p ? 'content_id' then a.content_id := nullif(p->>'content_id', '');
    if a.content_id is null then a.take_id := null; a.publication_id := null; end if; end if;
  if p ? 'take_id' then a.take_id := nullif(p->>'take_id', '')::uuid; end if;
  if p ? 'publication_id' then a.publication_id := nullif(p->>'publication_id', '')::uuid; end if;
  if p ? 'notes' then a.notes := nullif(btrim(coalesce(p->>'notes', '')), ''); end if;
  -- take e publicação têm de ser do guião ligado (identidade canónica, AGENTS §2.5)
  if a.take_id is not null and not exists (select 1 from takes t where t.id = a.take_id and t.content_id is not distinct from a.content_id) then
    raise exception 'take_de_outro_guiao' using errcode = '22023', detail = 'O take tem de ser do guião ligado.'; end if;
  if a.publication_id is not null and not exists (select 1 from pub_publications x where x.id = a.publication_id and x.content_id is not distinct from a.content_id) then
    raise exception 'publicacao_de_outro_guiao' using errcode = '22023', detail = 'A publicação tem de ser do guião ligado.'; end if;
  return a;
exception when invalid_text_representation then
  raise exception 'identificador_invalido' using errcode = '22023';
end $$;

create or replace function public.media_asset_save(p_ws text, p_id uuid, p_fields jsonb, p_lock int default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets; b media_assets;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.asset_save', p_id::text);
  perform public._media_uid();
  select * into a from media_assets where id = p_id and workspace_id = p_ws for update;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023', detail = 'Recupera o ativo do lixo antes de o editar.'; end if;
  if p_lock is not null and p_lock <> a.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
  if coalesce(p_fields, '{}') = '{}' then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  b := a;
  a := public._media_apply_fields(a, p_fields, array['title', 'tags', 'project_id', 'format', 'status', 'content_id', 'take_id', 'publication_id', 'notes']);
  update media_assets set title = a.title, tags = a.tags, project_id = a.project_id, format = a.format, status = a.status, content_id = a.content_id,
         take_id = a.take_id, publication_id = a.publication_id, notes = a.notes
   where id = p_id returning * into a;
  perform public._media_audit(p_ws, 'media.asset_updated', 'media_asset', p_id::text,
    to_jsonb(b) - array['updated_at', 'lock_version'], to_jsonb(a) - array['updated_at', 'lock_version']);
  return public._media_asset_json(a);
end $$;

-- ───────────── link externo (ex.: Google Drive): metadados, nada é descarregado ─────────────
create or replace function public.media_link_add(p_ws text, p_asset_id uuid, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; url text := btrim(coalesce(p_fields->>'url', '')); n int; vid uuid; lbl text;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.link_add', coalesce(p_asset_id::text, p_ws));
  uid := public._media_uid(); lbl := public._media_label(uid);
  if url !~ '^https://[^\s/]+\.[^\s/]+(/\S*)?$' or char_length(url) > 2000 then
    raise exception 'link_invalido' using errcode = '22023', detail = 'O link tem de começar por https://.'; end if;
  if p_asset_id is null then
    a.id := gen_random_uuid(); a.workspace_id := p_ws; a.kind := 'link_externo'; a.status := 'em_trabalho'; a.tags := '{}';
    a.title := coalesce(nullif(btrim(p_fields->>'title'), ''), left(regexp_replace(url, '^https://', ''), 160));
    a := public._media_apply_fields(a, p_fields - 'url', array['title', 'tags', 'project_id', 'format', 'status', 'content_id', 'take_id', 'publication_id', 'notes']);
    insert into media_assets (id, workspace_id, kind, title, tags, project_id, format, status, content_id, take_id, publication_id, notes, created_by, created_label)
    values (a.id, p_ws, 'link_externo', a.title, a.tags, a.project_id, a.format, a.status, a.content_id, a.take_id, a.publication_id, a.notes, uid, lbl);
    n := 1;
  else
    select * into a from media_assets where id = p_asset_id and workspace_id = p_ws for update;
    if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
    if a.kind <> 'link_externo' then raise exception 'tipo_invalido' using errcode = '22023', detail = 'Só um link externo recebe um link novo.'; end if;
    if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023'; end if;
    if (p_fields - 'url') <> '{}' then raise exception 'campo_desconhecido' using errcode = '22023'; end if;
    n := coalesce((select max(version_no) from media_versions where asset_id = a.id), 0) + 1;
  end if;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, external_url, completed_at, uploaded_by, uploaded_label)
  values (p_ws, a.id, n, 'link', 'pronta', url, now(), uid, lbl) returning id into vid;
  update media_assets set current_version_id = vid where id = a.id returning * into a;
  perform public._media_audit(p_ws, 'media.link_added', 'media_asset', a.id::text, null, jsonb_build_object('version_no', n, 'url', url));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'asset.linked', 'media_asset', a.id::text, jsonb_build_object('version_id', vid, 'version_no', n));
  return public._media_asset_json(a);
end $$;

-- ───────────── upload (FR-08-01, FR-08-04, FR-08-05) ─────────────
-- Regista uma versão pendente e devolve o caminho gerado no servidor. Validação de tipo, tamanho e quota aqui (e no bucket).
-- Idempotente: a mesma pessoa a repetir o mesmo ficheiro (sha256 + tamanho) recebe a mesma versão pendente.
create or replace function public.media_upload_begin(p_ws text, p_asset_id uuid, p_fields jsonb, p_file jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; lbl text; pol jsonb := public._media_policy(p_ws); use jsonb; a media_assets; v media_versions;
        fname text := btrim(coalesce(p_file->>'name', '')); fsize bigint; fmime text := lower(btrim(coalesce(p_file->>'mime', '')));
        fsha text := lower(btrim(coalesce(p_file->>'sha256', ''))); kind text; n int; path text; avail bigint;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_begin', coalesce(p_asset_id::text, p_ws));
  uid := public._media_uid(); lbl := public._media_label(uid);
  begin fsize := (p_file->>'size')::bigint; exception when others then fsize := null; end;
  if fname = '' or char_length(fname) > 255 then raise exception 'nome_invalido' using errcode = '22023', detail = 'O ficheiro precisa de um nome (até 255 caracteres).'; end if;
  if fsize is null or fsize <= 0 then raise exception 'tamanho_invalido' using errcode = '22023', detail = 'O ficheiro está vazio.'; end if;
  if fsha !~ '^[0-9a-f]{64}$' then raise exception 'checksum_invalido' using errcode = '22023', detail = 'Falta o SHA-256 do ficheiro.'; end if;
  if not fmime = any(array(select jsonb_array_elements_text(pol->'allowed_mime'))) then
    raise exception 'tipo_nao_permitido' using errcode = '22023', detail = format('O tipo %s não é permitido neste cliente.', coalesce(nullif(fmime, ''), 'desconhecido')); end if;
  if fsize > (pol->>'max_file_bytes')::bigint then
    raise exception 'ficheiro_grande_demais' using errcode = '22023',
      detail = format('Máximo por ficheiro neste cliente: %s MB.', round((pol->>'max_file_bytes')::numeric / 1048576, 1)); end if;

  if p_asset_id is null then
    kind := coalesce(nullif(p_fields->>'kind', ''), case when fmime like 'video/%' then 'video' when fmime like 'audio/%' then 'audio'
              when fmime like 'image/%' then 'imagem' when fmime in ('text/vtt', 'application/x-subrip') then 'legenda' else 'documento' end);
    if kind not in ('video', 'audio', 'imagem', 'thumbnail', 'legenda', 'documento') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
    -- repetição depois de uma resposta perdida: a mesma pessoa, o mesmo ficheiro, um ativo ainda sem versão pronta
    select v2.* into v from media_versions v2 join media_assets a2 on a2.id = v2.asset_id
     where v2.workspace_id = p_ws and v2.uploaded_by = uid and v2.state = 'pendente' and v2.upload_expires_at > now()
       and v2.sha256 = fsha and v2.size_bytes = fsize and v2.original_name = fname and a2.current_version_id is null and a2.lifecycle = 'ativo'
     order by v2.created_at desc limit 1;
    if v.id is not null then
      return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'version_no', v.version_no, 'bucket', v.storage_bucket,
        'path', v.storage_path, 'expires_at', v.upload_expires_at, 'reused', true);
    end if;
    a.id := gen_random_uuid(); a.workspace_id := p_ws; a.kind := kind; a.status := 'em_trabalho'; a.tags := '{}';
    a.title := coalesce(nullif(btrim(p_fields->>'title'), ''), left(regexp_replace(fname, '\.[A-Za-z0-9]{1,10}$', ''), 160));
    a := public._media_apply_fields(a, p_fields - 'kind', array['title', 'tags', 'project_id', 'format', 'status', 'content_id', 'take_id', 'publication_id', 'notes']);
  else
    select * into a from media_assets where id = p_asset_id and workspace_id = p_ws for update;
    if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
    if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023', detail = 'Recupera o ativo do lixo antes de carregar uma versão nova.'; end if;
    if a.kind = 'link_externo' then raise exception 'tipo_invalido' using errcode = '22023', detail = 'Um link externo não recebe ficheiros.'; end if;
    if coalesce(p_fields, '{}') <> '{}' then raise exception 'campo_desconhecido' using errcode = '22023', detail = 'Os dados do ativo mudam-se à parte.'; end if;
    select * into v from media_versions where asset_id = a.id and uploaded_by = uid and state = 'pendente' and upload_expires_at > now()
       and sha256 = fsha and size_bytes = fsize order by version_no desc limit 1;
    if v.id is not null then
      return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'version_no', v.version_no, 'bucket', v.storage_bucket,
        'path', v.storage_path, 'expires_at', v.upload_expires_at, 'reused', true);
    end if;
  end if;
  if not public._media_kind_mime_ok(a.kind, fmime) then
    raise exception 'tipo_nao_corresponde' using errcode = '22023', detail = format('Um ficheiro %s não serve para um ativo do tipo %s.', fmime, a.kind); end if;
  if (select count(*) from media_versions where workspace_id = p_ws and uploaded_by = uid and state = 'pendente' and upload_expires_at > now()) >= 20 then
    raise exception 'demasiados_pendentes' using errcode = '22023', detail = 'Tens 20 uploads por concluir neste cliente: conclui ou desiste de algum.'; end if;
  use := public._media_usage(p_ws);
  avail := (pol->>'quota_bytes')::bigint - (use->>'stored_bytes')::bigint - (use->>'reserved_bytes')::bigint;
  if fsize > avail then
    raise exception 'quota_excedida' using errcode = '22023',
      detail = format('A quota deste cliente (%s GB) não chega: livre %s MB, o ficheiro tem %s MB.',
        round((pol->>'quota_bytes')::numeric / 1073741824, 2), round(greatest(avail, 0)::numeric / 1048576, 1), round(fsize::numeric / 1048576, 1)); end if;

  if p_asset_id is null then
    insert into media_assets (id, workspace_id, kind, title, tags, project_id, format, status, content_id, take_id, publication_id, notes, created_by, created_label)
    values (a.id, p_ws, a.kind, a.title, a.tags, a.project_id, a.format, a.status, a.content_id, a.take_id, a.publication_id, a.notes, uid, lbl);
  end if;
  n := coalesce((select max(version_no) from media_versions where asset_id = a.id), 0) + 1;
  path := p_ws || '/' || a.id || '/' || n || '/' || public._media_safe_name(fname);
  insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256,
                              upload_expires_at, uploaded_by, uploaded_label)
  values (p_ws, a.id, n, 'upload', 'pendente', 'media', path, fname, fsize, fmime, fsha, now() + make_interval(hours => (pol->>'pending_hours')::int), uid, lbl)
  returning * into v;
  perform public._media_audit(p_ws, 'media.upload_started', 'media_asset', a.id::text, null,
    jsonb_build_object('version_id', v.id, 'version_no', n, 'size_bytes', fsize, 'mime', fmime, 'sha256', fsha, 'new_asset', p_asset_id is null));
  return jsonb_build_object('asset_id', a.id, 'version_id', v.id, 'version_no', n, 'bucket', 'media', 'path', path, 'expires_at', v.upload_expires_at, 'reused', false);
end $$;

-- Para retomar: o caminho e o que foi declarado (só o próprio, versão pendente e não expirada).
create or replace function public.media_upload_target(p_ws text, p_version uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v media_versions; uid uuid;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_target', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws and source = 'upload';
  if v.id is null or v.uploaded_by <> uid then raise exception 'upload_nao_encontrado' using errcode = 'P0002'; end if;
  if v.state <> 'pendente' then raise exception 'upload_terminado' using errcode = '22023', detail = format('Este upload já está %s.', v.state); end if;
  if v.upload_expires_at <= now() then raise exception 'upload_expirado' using errcode = '22023', detail = 'Este upload expirou: carrega o ficheiro outra vez.'; end if;
  return jsonb_build_object('asset_id', v.asset_id, 'version_id', v.id, 'bucket', v.storage_bucket, 'path', v.storage_path, 'size_bytes', v.size_bytes,
    'mime', v.mime, 'sha256', v.sha256, 'expires_at', v.upload_expires_at,
    'object_exists', exists (select 1 from storage.objects o where o.bucket_id = 'media' and o.name = v.storage_path));
end $$;

-- Confirma o upload: o objeto tem de existir com o tamanho e o tipo declarados. p_server_sha256 é o SHA-256 que o servidor
-- calculou ao ler o objeto (rota /api/media/uploads/:id/complete); se não vier, o checksum fica "declarado" (não conferido).
-- Diferenças marcam a versão como falhou (fica órfã para limpar) e devolvem o motivo, sem lançar erro (o estado persiste).
create or replace function public.media_upload_complete(p_ws text, p_version uuid, p_server_sha256 text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; o record; uid uuid; why text; sha text := lower(nullif(btrim(coalesce(p_server_sha256, '')), ''));
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_complete', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws and source = 'upload' for update;
  if v.id is null or v.uploaded_by <> uid then raise exception 'upload_nao_encontrado' using errcode = 'P0002'; end if;
  if v.state = 'pronta' then
    select * into a from media_assets where id = v.asset_id;
    return jsonb_build_object('state', 'pronta', 'version', public._media_version_json(v), 'asset', public._media_asset_json(a), 'repeated', true);
  end if;
  if v.state <> 'pendente' then raise exception 'upload_terminado' using errcode = '22023', detail = format('Este upload já está %s.', v.state); end if;
  if sha is not null and sha !~ '^[0-9a-f]{64}$' then raise exception 'checksum_invalido' using errcode = '22023'; end if;
  select * into o from storage.objects where bucket_id = 'media' and name = v.storage_path;
  if o.id is null then
    raise exception 'objeto_em_falta' using errcode = 'P0002', detail = 'O ficheiro ainda não chegou ao armazenamento: tenta enviar outra vez.'; end if;
  if coalesce((o.metadata->>'size')::bigint, -1) <> v.size_bytes then
    why := format('tamanho_diferente: declarado %s, guardado %s', v.size_bytes, coalesce(o.metadata->>'size', 'desconhecido'));
  elsif lower(coalesce(o.metadata->>'mimetype', '')) <> v.mime then
    why := format('tipo_diferente: declarado %s, guardado %s', v.mime, coalesce(o.metadata->>'mimetype', 'desconhecido'));
  elsif sha is not null and sha <> v.sha256 then
    why := 'checksum_diferente: o SHA-256 do objeto guardado não é o do ficheiro do browser';
  end if;
  if why is not null then
    update media_versions set state = 'falhou', failed_reason = why where id = v.id returning * into v;
    perform public._media_audit(p_ws, 'media.upload_failed', 'media_asset', v.asset_id::text, null, jsonb_build_object('version_id', v.id, 'reason', why));
    return jsonb_build_object('state', 'falhou', 'reason', why, 'version', public._media_version_json(v));
  end if;
  update media_versions set state = 'pronta', completed_at = now(), checksum_verified = sha is not null,
         checksum_verified_at = case when sha is not null then now() end
   where id = v.id returning * into v;
  update media_assets x set current_version_id = v.id
   where x.id = v.asset_id and (x.current_version_id is null or (select version_no from media_versions where id = x.current_version_id) < v.version_no)
   returning * into a;
  if a.id is null then select * into a from media_assets where id = v.asset_id; end if;
  perform public._media_audit(p_ws, 'media.version_ready', 'media_asset', v.asset_id::text, null,
    jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'size_bytes', v.size_bytes, 'sha256', v.sha256, 'checksum_verified', v.checksum_verified));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'asset.uploaded', 'media_asset', v.asset_id::text, jsonb_build_object('version_id', v.id, 'version_no', v.version_no,
          'kind', a.kind, 'content_id', a.content_id, 'size_bytes', v.size_bytes, 'mime', v.mime));
  return jsonb_build_object('state', 'pronta', 'version', public._media_version_json(v), 'asset', public._media_asset_json(a), 'repeated', false);
end $$;

-- Desistir de um upload (o próprio) ou marcar um pendente como falhado (media.manage). Fica órfão para limpar.
create or replace function public.media_upload_abandon(p_ws text, p_version uuid, p_reason text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; uid uuid;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.upload_abandon', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws and source = 'upload' for update;
  if v.id is null or (v.uploaded_by <> uid and not public.ws_can('media.manage', p_ws, p_token)) then
    raise exception 'upload_nao_encontrado' using errcode = 'P0002'; end if;
  if v.state = 'falhou' then return public._media_version_json(v); end if;
  if v.state <> 'pendente' then raise exception 'upload_terminado' using errcode = '22023'; end if;
  update media_versions set state = 'falhou', failed_reason = 'desistiu: ' || left(coalesce(nullif(btrim(p_reason), ''), 'sem motivo'), 300)
   where id = v.id returning * into v;
  perform public._media_audit(p_ws, 'media.upload_abandoned', 'media_asset', v.asset_id::text, null, jsonb_build_object('version_id', v.id, 'reason', v.failed_reason));
  return public._media_version_json(v);
end $$;

-- ───────────── acesso (FR-08-03): autorização de 60 s para o storage assinar um URL curto ─────────────
create or replace function public.media_access(p_ws text, p_version uuid, p_purpose text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid;
begin
  if p_purpose not in ('preview', 'download') then raise exception 'finalidade_invalida' using errcode = '22023'; end if;
  perform public._media_require(case p_purpose when 'download' then 'media.download' else 'media.read' end, p_ws, p_token, 'media.access', p_version::text);
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  select * into a from media_assets where id = v.asset_id;
  if v.source <> 'upload' then raise exception 'link_externo' using errcode = '22023', detail = 'Esta versão é um link externo: abre-o diretamente.'; end if;
  if v.state <> 'pronta' or a.lifecycle = 'eliminado' then raise exception 'versao_indisponivel' using errcode = '22023', detail = format('Esta versão está %s.', v.state); end if;
  if a.lifecycle = 'no_lixo' and not public.ws_can('media.upload', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  delete from media_access_grants where expires_at < now() - interval '1 hour';
  insert into media_access_grants (workspace_id, object_path, user_id, purpose, expires_at) values (p_ws, v.storage_path, uid, p_purpose, now() + interval '60 seconds');
  perform public._media_audit(p_ws, 'media.accessed', 'media_asset', a.id::text, null, jsonb_build_object('version_id', v.id, 'purpose', p_purpose));
  return jsonb_build_object('bucket', v.storage_bucket, 'path', v.storage_path, 'mime', v.mime, 'filename', v.original_name,
    'ttl_seconds', case p_purpose when 'download' then 120 else 300 end);
end $$;

-- ───────────── lixo e recuperação (FR-08-06) ─────────────
create or replace function public.media_trash(p_ws text, p_id uuid, p_reason text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets; uid uuid; days int := (public._media_policy(p_ws)->>'trash_days')::int;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.trash', p_id::text);
  uid := public._media_uid();
  select * into a from media_assets where id = p_id and workspace_id = p_ws for update;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.lifecycle = 'no_lixo' then return public._media_asset_json(a); end if;
  if a.lifecycle <> 'ativo' then raise exception 'ativo_eliminado' using errcode = '22023'; end if;
  update media_assets set lifecycle = 'no_lixo', trashed_at = now(), trashed_by = uid, trashed_label = public._media_label(uid),
         trash_reason = nullif(left(btrim(coalesce(p_reason, '')), 500), ''), purge_after = now() + make_interval(days => days)
   where id = p_id returning * into a;
  update media_shares set revoked_at = now(), revoked_by = uid, revoked_label = 'lixo' where asset_id = p_id and revoked_at is null;
  perform public._media_audit(p_ws, 'media.trashed', 'media_asset', p_id::text, jsonb_build_object('lifecycle', 'ativo'),
    jsonb_build_object('lifecycle', 'no_lixo', 'purge_after', a.purge_after, 'reason', a.trash_reason));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload) values (p_ws, 'asset.trashed', 'media_asset', p_id::text, jsonb_build_object('purge_after', a.purge_after));
  return public._media_asset_json(a);
end $$;

create or replace function public.media_restore(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.restore', p_id::text);
  perform public._media_uid();
  select * into a from media_assets where id = p_id and workspace_id = p_ws for update;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.lifecycle = 'ativo' then return public._media_asset_json(a); end if;
  if a.lifecycle <> 'no_lixo' then raise exception 'ativo_eliminado' using errcode = '22023', detail = 'Este ativo já foi apagado definitivamente.'; end if;
  update media_assets set lifecycle = 'ativo', trashed_at = null, trashed_by = null, trashed_label = null, trash_reason = null, purge_after = null,
         purge_requested_at = null, purge_requested_by = null
   where id = p_id returning * into a;
  perform public._media_audit(p_ws, 'media.restored', 'media_asset', p_id::text, jsonb_build_object('lifecycle', 'no_lixo'), jsonb_build_object('lifecycle', 'ativo'));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload) values (p_ws, 'asset.restored', 'media_asset', p_id::text, '{}');
  return public._media_asset_json(a);
end $$;

-- ───────────── privilégios ─────────────
revoke all on function public._media_require(text, text, text, text, text), public._media_uid(), public._media_label(uuid),
  public._media_audit(text, text, text, text, jsonb, jsonb), public._media_version_json(media_versions), public._media_asset_json(media_assets),
  public._media_apply_fields(media_assets, jsonb, text[]) from public, anon, authenticated;
revoke all on function public.media_library(text, jsonb, text), public.media_asset(text, uuid, text), public.media_asset_save(text, uuid, jsonb, int, text),
  public.media_link_add(text, uuid, jsonb, text), public.media_upload_begin(text, uuid, jsonb, jsonb, text), public.media_upload_target(text, uuid, text),
  public.media_upload_complete(text, uuid, text, text), public.media_upload_abandon(text, uuid, text, text), public.media_access(text, uuid, text, text),
  public.media_trash(text, uuid, text, text), public.media_restore(text, uuid, text) from public;
grant execute on function public.media_library(text, jsonb, text), public.media_asset(text, uuid, text), public.media_asset_save(text, uuid, jsonb, int, text),
  public.media_link_add(text, uuid, jsonb, text), public.media_upload_begin(text, uuid, jsonb, jsonb, text), public.media_upload_target(text, uuid, text),
  public.media_upload_complete(text, uuid, text, text), public.media_upload_abandon(text, uuid, text, text), public.media_access(text, uuid, text, text),
  public.media_trash(text, uuid, text, text), public.media_restore(text, uuid, text) to anon, authenticated;
-- anon (código de equipa) chega às funções mas não tem nenhuma capacidade media.*: recebe 42501.

/* Rollback (compatível):
   drop function public.media_restore(text, uuid, text), public.media_trash(text, uuid, text, text), public.media_access(text, uuid, text, text),
     public.media_upload_abandon(text, uuid, text, text), public.media_upload_complete(text, uuid, text, text), public.media_upload_target(text, uuid, text),
     public.media_upload_begin(text, uuid, jsonb, jsonb, text), public.media_link_add(text, uuid, jsonb, text), public.media_asset_save(text, uuid, jsonb, int, text),
     public.media_asset(text, uuid, text), public.media_library(text, jsonb, text), public._media_apply_fields(media_assets, jsonb, text[]),
     public._media_asset_json(media_assets), public._media_version_json(media_versions), public._media_audit(text, text, text, text, jsonb, jsonb),
     public._media_label(uuid), public._media_uid(), public._media_require(text, text, text, text, text); */
