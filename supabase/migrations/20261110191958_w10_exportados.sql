-- W10-44: página "Exportados" (EDL-11): os vídeos exportados do cliente num só sítio, para a equipa descarregar e publicar.
-- Leitura só: media.read com a biblioteca ligada (a mesma regra da Biblioteca e da revisão), sessão individual. Descarregar
-- continua pelo /api/media/versions/:id/url?purpose=download (media_access: media.download, auditado, link de 60 s).
-- Expand (só aditivo): uma função nova. Rollback: drop function public.edit_exports_feed(text, int, text);

create or replace function public.edit_exports_feed(p_ws text, p_days int default 14, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d int := least(greatest(coalesce(p_days, 14), 1), 90);
begin
  perform public._media_uid();
  perform public._media_require('media.read', p_ws, p_token, 'edit.exports_feed', p_ws);
  return jsonb_build_object(
    'can_download', public.ws_can('media.download', p_ws, p_token),
    'timezone', (select timezone from clients where id = p_ws),
    'days', d,
    'items', coalesce((select jsonb_agg(x order by x->>'sort_at' desc) from (
      select jsonb_build_object(
        'job_id', j.id, 'status', j.status, 'progress', j.progress, 'last_error', j.last_error,
        'asset_id', a.id, 'title', a.title, 'tags', a.tags,
        'content', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema) from guioes g
                     where g.id = a.content_id and g.client_id = p_ws and g.deleted_at is null),
        'style', (select ev.doc->>'style' from edit_versions ev where ev.id = j.edit_version_id),
        'edit_version_no', (select ev.version_no from edit_versions ev where ev.id = j.edit_version_id),
        'version_id', v.id, 'version_no', v.version_no, 'version_state', v.state,
        'size_bytes', v.size_bytes, 'duration', (v.media_info->>'duration')::numeric,
        'created_label', j.created_label, 'created_at', j.created_at, 'finished_at', j.finished_at,
        'sort_at', coalesce(j.finished_at, j.created_at),
        -- a exportação mais recente pronta deste vídeo (as anteriores ficam para quem precisar)
        'latest', j.status = 'done' and not exists (select 1 from media_jobs n where n.workspace_id = p_ws and n.asset_id = j.asset_id
                    and n.kind = 'export' and n.status = 'done' and n.finished_at > j.finished_at)) x
        from media_jobs j
        join media_assets a on a.id = j.asset_id and a.workspace_id = p_ws and a.lifecycle = 'ativo'
        left join media_versions v on j.status = 'done' and v.id = nullif(j.result->>'version_id', '')::uuid and v.workspace_id = p_ws
       where j.workspace_id = p_ws and j.kind = 'export' and j.status <> 'cancelled'
         and coalesce(j.finished_at, j.created_at) > now() - make_interval(days => d)
         and (j.status <> 'done' or (v.id is not null and v.state = 'pronta' and v.deleted_at is null))
       order by coalesce(j.finished_at, j.created_at) desc
       limit 300) s), '[]'));
end $$;
revoke all on function public.edit_exports_feed(text, int, text) from public, anon;
grant execute on function public.edit_exports_feed(text, int, text) to authenticated;
