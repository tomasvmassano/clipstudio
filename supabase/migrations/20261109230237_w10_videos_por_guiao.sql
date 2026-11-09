-- W10-33 · Vídeos por guião e corpo partilhado (EDL-14, EDL-15; CHG-011; ADR-0081). Expand (aditivo, só leitura).
-- edit_board: os vídeos com documento de edição deste cliente agrupados por guião (número, data, tema), cada variante com o texto
-- do hook, a duração, a versão, a assinatura dos cortes do corpo (para mostrar se as variantes têm o mesmo corpo), o primeiro corte
-- e as câmaras (para a imagem do vídeo) e o estado da exportação. p_content limita a um guião (separadores no editor).
-- Gravar o corpo nas outras variantes usa edit_doc_save, variante a variante (mesmas regras, controlo de versões e auditoria).

create or replace function public.edit_board(p_ws text, p_content text default null, p_limit int default 40, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := greatest(1, least(coalesce(p_limit, 40), 100));
begin
  perform public._edit_require(p_ws, p_token, 'edit.board', coalesce(p_content, p_ws), false);
  return coalesce((
    select jsonb_agg(g.j order by g.last desc)
      from (
        select max(d.updated_at) as last,
               jsonb_build_object(
                 'content_id', a.content_id,
                 'guiao', (select jsonb_build_object('id', x.id, 'n', x.n, 'date', x.date, 'tema', x.tema)
                             from guioes x where x.id = a.content_id and x.client_id = p_ws and x.deleted_at is null),
                 'variants', jsonb_agg(jsonb_build_object(
                    'asset_id', a.id, 'title', a.title, 'status', a.status,
                    'variant', public._review_variant(a.tags), 'style', coalesce(v.doc->>'style', public._review_style(a.tags)),
                    'version_id', v.id, 'version_no', v.version_no, 'updated_at', d.updated_at, 'updated_label', v.created_label,
                    'hook_text', v.doc->'hook'->>'text',
                    'duration', (select round(coalesce(sum((s->>'out')::numeric - (s->>'in')::numeric), 0), 2) from jsonb_array_elements(v.doc->'segments') s),
                    'body_sig', md5(coalesce((select string_agg((s->>'in') || '-' || (s->>'out'), ',' order by o)
                                                from jsonb_array_elements(v.doc->'segments') with ordinality t(s, o)
                                               where coalesce(s->>'section', 'body') <> 'hook'), '')),
                    'first_in', (v.doc->'segments'->0->>'in')::numeric,
                    'source', jsonb_build_object('cams', v.doc->'source'->'cams', 'windows', v.doc->'source'->'windows',
                                                 'offsets', v.doc->'source'->'offsets', 'audio', v.doc->'source'->>'audio'),
                    'export', (select jsonb_build_object('status', j.status, 'finished_at', j.finished_at, 'edit_version_id', j.edit_version_id,
                                                         'current', j.edit_version_id = v.id)
                                 from media_jobs j where j.workspace_id = p_ws and j.kind = 'export' and j.asset_id = a.id
                                order by j.created_at desc limit 1))
                    order by public._review_variant(a.tags), a.title)) as j
          from edit_documents d
          join media_assets a on a.id = d.asset_id and a.workspace_id = p_ws and a.lifecycle = 'ativo' and a.kind = 'video'
          join edit_versions v on v.id = d.current_version_id
         where d.workspace_id = p_ws and a.content_id is not null and (p_content is null or a.content_id = p_content)
         group by a.content_id
         order by max(d.updated_at) desc
         limit lim) g), '[]'::jsonb);
end $$;

revoke all on function public.edit_board(text, text, int, text) from public, anon;
grant execute on function public.edit_board(text, text, int, text) to authenticated;

/* Rollback: drop function if exists public.edit_board(text, text, int, text); */
