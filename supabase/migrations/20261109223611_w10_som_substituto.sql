-- W10-32 · Som substituto de uma gravação (EDL-08, FR-08-01; pedido do Tomás a 10/11; ADR-0080). Expand (aditivo).
-- O Tomás tratou o som da lapela do C7870 fora da app (WAV com a mesma duração) e quer que os vídeos usem esse som, no mesmo tempo.
-- O original (29 GB, SHA-256 conferido) não muda: a versão do vídeo passa a apontar para uma versão de áudio da Biblioteca
-- (media_versions.audio_version_id). A exportação usa esse áudio no lugar do som do vídeo (input cams.<cam>.audio_key) e o palco
-- do editor toca-o (edit_preview_sources devolve audio_version_id). Exportar outra vez depois de trocar o som cria um job novo
-- (a chave do export leva o som). Rollback no fim.

alter table public.media_versions add column if not exists audio_version_id uuid references public.media_versions(id) on delete set null;

-- Ligar (ou tirar, com p_audio null) o som substituto a uma gravação. Mesmo cliente, os dois prontos no R2, durações a menos de 1 s.
create or replace function public.media_audio_replace(p_ws text, p_video uuid, p_audio uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_versions; dv numeric; da numeric;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.audio_replace', coalesce(p_video::text, ''));
  select * into v from media_versions where id = p_video and workspace_id = p_ws for update;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  if v.state <> 'pronta' or v.storage_provider is distinct from 'r2' or coalesce(v.mime, '') not like 'video/%' then
    raise exception 'sem_som_substituto' using errcode = '22023', detail = 'Só uma gravação de vídeo pronta, guardada na app, leva som substituto.'; end if;
  if p_audio is not null then
    select * into a from media_versions where id = p_audio and workspace_id = p_ws;
    if a.id is null then raise exception 'audio_nao_encontrado' using errcode = 'P0002'; end if;
    if a.state <> 'pronta' or a.storage_provider is distinct from 'r2' or coalesce(a.mime, '') not like 'audio/%' then
      raise exception 'audio_invalido' using errcode = '22023', detail = 'O som tem de ser um ficheiro de áudio pronto na Biblioteca.'; end if;
    dv := nullif(v.media_info->>'duration', '')::numeric;
    da := nullif(a.media_info->>'duration', '')::numeric;
    if dv is not null and da is not null and abs(dv - da) > 1 then
      raise exception 'duracao_diferente' using errcode = '22023',
        detail = format('O som dura %s s e a gravação %s s: têm de ter a mesma duração para ficarem no mesmo sítio.', round(da, 1), round(dv, 1)); end if;
  end if;
  update media_versions set audio_version_id = p_audio where id = v.id;
  perform public._media_audit(p_ws, 'media.audio_replaced', 'media_asset', v.asset_id::text,
    jsonb_build_object('audio_version_id', v.audio_version_id), jsonb_build_object('version_id', v.id, 'audio_version_id', p_audio));
  return jsonb_build_object('version_id', v.id, 'audio_version_id', p_audio);
end $$;

-- As câmaras do documento: mais o som substituto de cada gravação (chave no R2 e versão), quando está pronto.
create or replace function public._edit_resolve_cams(p_ws text, p_doc jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(c.key, (
    select jsonb_build_object('name', c.value #>> '{}', 'version_id', v.id, 'asset_id', v.asset_id, 'key', v.storage_path,
             'proxy_key', case when v.proxy_state = 'pronta' then v.proxy_path end, 'proxy_state', v.proxy_state,
             'size_bytes', v.size_bytes, 'media_info', v.media_info)
           || coalesce((select jsonb_build_object('audio_key', s.storage_path, 'audio_version_id', s.id)
                          from media_versions s
                         where s.id = v.audio_version_id and s.workspace_id = p_ws and s.state = 'pronta' and s.storage_provider = 'r2'), '{}')
      from media_versions v join media_assets a on a.id = v.asset_id
     where v.workspace_id = p_ws and v.storage_provider = 'r2' and v.state = 'pronta' and a.lifecycle = 'ativo'
       and v.original_name = regexp_replace(c.value #>> '{}', '^.*/', '')
     order by v.completed_at desc nulls last limit 1)), '{}')
  from jsonb_each(coalesce(p_doc->'source'->'cams', '{}')) c
$$;

create or replace function public.edit_preview_sources(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d edit_documents; v edit_versions; cams jsonb;
begin
  perform public._edit_require(p_ws, p_token, 'edit.preview', p_asset::text, false);
  select * into d from edit_documents where asset_id = p_asset and workspace_id = p_ws;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  cams := public._edit_resolve_cams(p_ws, v.doc);
  return jsonb_build_object('windows', v.doc->'source'->'windows', 'audio', v.doc->'source'->>'audio',
    'cams', (select coalesce(jsonb_object_agg(key, case when value = 'null'::jsonb then jsonb_build_object('state', 'em_falta')
               else jsonb_build_object('state', coalesce(value->>'proxy_state', 'nao_aplica'), 'version_id', value->>'version_id',
                                       'name', value->>'name', 'media_info', value->'media_info',
                                       'audio_version_id', value->>'audio_version_id') end), '{}')
             from jsonb_each(cams)),
    'names', v.doc->'source'->'cams');
end $$;

-- Exportar: como em 20261106055840_w10_qc_irmas.sql; a chave do job leva o som substituto, para trocar o som dar um export novo.
create or replace function public.edit_export_request(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; d edit_documents; v edit_versions; cams jsonb; missing text; j media_jobs; k text; music jsonb; mv media_versions; vis jsonb; sib jsonb;
        snd text;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.export', p_asset::text, true);
  if not public.ws_can('edit.export', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.export');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Exportar precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  select * into d from edit_documents where asset_id = p_asset and workspace_id = p_ws;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  cams := public._edit_resolve_cams(p_ws, v.doc);
  select string_agg(coalesce(v.doc->'source'->'cams'->>key, key), ', ') into missing from jsonb_each(cams) where value = 'null'::jsonb;
  if missing is not null or cams = '{}'::jsonb then
    raise exception 'camaras_em_falta' using errcode = '22023',
      detail = format('Carrega primeiro na Biblioteca as gravações: %s.', coalesce(missing, 'nenhuma câmara no documento')); end if;
  if v.doc->'audio'->'music'->>'asset' is not null then
    select x.* into mv from media_versions x join media_assets a on a.id = x.asset_id
     where a.id::text = v.doc->'audio'->'music'->>'asset' and a.workspace_id = p_ws and x.id = a.current_version_id and x.state = 'pronta' and x.source = 'upload';
    if mv.id is null then raise exception 'musica_em_falta' using errcode = '22023', detail = 'A música escolhida já não está na biblioteca.'; end if;
    music := jsonb_build_object('key', mv.storage_path, 'bucket', mv.storage_bucket, 'db', coalesce((v.doc->'audio'->'music'->>'db')::numeric, -18));
  end if;
  vis := public._edit_resolve_visuals(p_ws, v.doc);
  sib := public._edit_resolve_siblings(p_ws, p_asset);
  select string_agg(key || '=' || (value->>'audio_version_id'), ',' order by key) into snd
    from jsonb_each(cams) where jsonb_typeof(value) = 'object' and value ? 'audio_version_id';
  k := 'export:' || v.id || coalesce(':som:' || md5(snd), '');
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, asset_id, edit_version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'export', k, p_asset, v.id,
            jsonb_build_object('doc', v.doc, 'cams', cams, 'music', music, 'visuals', vis, 'siblings', sib, 'edit_version_no', v.version_no,
                               'out_key', p_ws || '/' || p_asset || '/exports/' || v.id || coalesce('-' || left(md5(snd), 8), '') || '.mp4'),
            uid, public._media_label(uid), 3)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.export_requested', 'media_asset', p_asset::text, null,
      jsonb_build_object('job_id', j.id, 'edit_version_id', v.id, 'edit_version_no', v.version_no, 'som', snd));
  end if;
  return public._media_job_json(j);
end $$;

-- Que gravações têm som substituto neste cliente (para a Biblioteca mostrar a escolha atual).
create or replace function public.media_audio_links(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.audio_links', p_ws);
  return coalesce((select jsonb_object_agg(v.id, v.audio_version_id) from media_versions v
                    where v.workspace_id = p_ws and v.audio_version_id is not null and v.state = 'pronta'), '{}');
end $$;

revoke all on function public.media_audio_links(text, text) from public, anon;
grant execute on function public.media_audio_links(text, text) to authenticated;
revoke all on function public.media_audio_replace(text, uuid, uuid, text) from public, anon;
grant execute on function public.media_audio_replace(text, uuid, uuid, text) to authenticated;

/* Rollback (o código anterior ignora os campos novos):
   repor _edit_resolve_cams e edit_preview_sources de 20261105175803_w5_media_r2_jobs.sql e edit_export_request de 20261106055840_w10_qc_irmas.sql;
   drop function if exists public.media_audio_replace(text, uuid, uuid, text); drop function if exists public.media_audio_links(text, text);
   alter table public.media_versions drop column if exists audio_version_id;   -- contract, depois de a app deixar de a ler */
