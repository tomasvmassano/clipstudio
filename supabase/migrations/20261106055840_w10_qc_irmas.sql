-- W10-09 · QC: variantes irmãs no export (PRD EDL-03; ADR-0052). Expand (aditivo).
-- edit_export_request passa ao worker os exports atuais (R2, pronta) das outras variantes do mesmo guião, no mesmo cliente,
-- até 8; o worker (numeiro-engine #17) compara por pHash e junta `distinct_sibling:<versão>` às notas do QC. Workers antigos ignoram.

create or replace function public._edit_resolve_siblings(p_ws text, p_asset uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', v.storage_path, 'version_id', v.id, 'asset_id', a.id) order by a.id), '[]'::jsonb)
  from (select a.* from media_assets me
          join media_assets a on a.content_id = me.content_id and a.workspace_id = p_ws and a.id <> me.id
         where me.id = p_asset and me.workspace_id = p_ws and me.content_id is not null
           and a.lifecycle = 'ativo' and a.kind = 'video'
           and exists (select 1 from edit_documents e where e.asset_id = a.id and e.workspace_id = p_ws)
         order by a.id limit 8) a
  join media_versions v on v.id = a.current_version_id
  where v.workspace_id = p_ws and v.asset_id = a.id and v.state = 'pronta' and v.storage_provider = 'r2'
    and v.mime like 'video/%' and v.storage_path like p_ws || '/%/exports/%'
$$;
revoke all on function public._edit_resolve_siblings(text, uuid) from public, anon, authenticated;

create or replace function public.edit_export_request(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; d edit_documents; v edit_versions; cams jsonb; missing text; j media_jobs; k text; music jsonb; mv media_versions; vis jsonb; sib jsonb;
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
  vis := public._edit_resolve_visuals(p_ws, v.doc);   -- W5-17: visuais (b-roll, gráficos) no R2; null = fica de fora no render
  sib := public._edit_resolve_siblings(p_ws, p_asset);   -- W10-09: exports atuais das variantes irmãs, para o pHash do QC
  k := 'export:' || v.id;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, asset_id, edit_version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'export', k, p_asset, v.id,
            jsonb_build_object('doc', v.doc, 'cams', cams, 'music', music, 'visuals', vis, 'siblings', sib, 'edit_version_no', v.version_no,
                               'out_key', p_ws || '/' || p_asset || '/exports/' || v.id || '.mp4'),
            uid, public._media_label(uid), 3)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.export_requested', 'media_asset', p_asset::text, null,
      jsonb_build_object('job_id', j.id, 'edit_version_id', v.id, 'edit_version_no', v.version_no));
  end if;
  return public._media_job_json(j);
end $$;

/* Rollback (compatível): repor edit_export_request de 20261105215504_w5_export_visuais.sql; drop function public._edit_resolve_siblings(text, uuid). */
