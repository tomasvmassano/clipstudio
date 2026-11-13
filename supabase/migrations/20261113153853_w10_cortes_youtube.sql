-- W10-45 (CHG-012, CLIP-01/03/05/06): pedir cortes a partir do link do YouTube + ficheiro, com modo leve por defeito e o
-- número pela duração (até 20). A app nunca descarrega do YouTube: o link fica guardado no pedido (metadados, CLIP-08/09);
-- o vídeo é sempre o ficheiro do cliente no R2 (as mesmas regras de clips_request).
-- Expand (só aditivo): função nova clips_request2 (clips_request fica igual para o código em produção) e clips_list passa a
-- devolver também o modo e o link. Rollback: drop function public.clips_request2(text, uuid, int, text, text, text);
-- repor clips_list de 20261106065110_w10_clip_miner.sql.

-- Link do YouTube -> id do vídeo (11 caracteres) ou null. Aceita watch?v=, youtu.be/, shorts/, live/, embed/.
create or replace function public._youtube_id(p_url text) returns text
language sql immutable set search_path = public as $$
  select (regexp_match(btrim(coalesce(p_url, '')),
    '^(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:[^#]*&)?v=|shorts/|live/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})(?:[?&#/].*)?$'))[1]
$$;

create or replace function public.clips_request2(p_ws text, p_version uuid, p_count int default null, p_mode text default 'leve',
                                                 p_youtube text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; v media_versions; a media_assets; k text; j media_jobs; n int; dur numeric; md text := coalesce(nullif(p_mode, ''), 'leve');
        yt text := nullif(btrim(coalesce(p_youtube, '')), ''); yid text;
begin
  uid := public._clips_require(p_ws, p_token, 'clips.request', coalesce(p_version::text, ''));
  if not public.ws_can('clips.mine', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'clips.mine');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os cortes precisam do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  if md not in ('leve', 'completo') then raise exception 'modo_invalido' using errcode = '22023', detail = 'Modo: leve ou completo.'; end if;
  if p_count is not null and p_count not between 3 and 20 then
    raise exception 'numero_invalido' using errcode = '22023', detail = 'Pede entre 3 e 20 cortes, ou deixa automático.'; end if;
  if yt is not null then
    yid := public._youtube_id(yt);
    if yid is null then raise exception 'link_invalido' using errcode = '22023', detail = 'O link tem de ser de um vídeo do YouTube (youtube.com/watch?v=… ou youtu.be/…).'; end if;
  end if;
  select x.* into v from media_versions x join media_assets y on y.id = x.asset_id
   where x.id = p_version and x.workspace_id = p_ws and x.state = 'pronta' and x.storage_provider = 'r2' and x.mime like 'video/%' and y.lifecycle = 'ativo';
  if v.id is null then
    raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'Escolhe ou carrega o ficheiro do vídeo: tem de estar pronto na Biblioteca (no R2) deste cliente.'; end if;
  select * into a from media_assets where id = v.asset_id;
  dur := case when jsonb_typeof(v.media_info->'duration') = 'number' then (v.media_info->>'duration')::numeric end;
  if dur is not null and dur < 120 then
    raise exception 'video_curto' using errcode = '22023', detail = 'O vídeo tem menos de 2 minutos: os cortes são para vídeos longos.'; end if;
  if dur is not null and dur > 4 * 3600 then
    raise exception 'video_longo' using errcode = '22023', detail = 'O vídeo tem mais de 4 horas: corta-o em partes antes de pedir cortes.'; end if;
  -- automático: ~1 corte por cada 4 min, entre 5 e 20 (o motor faz a mesma conta, CHG-012)
  n := coalesce(p_count, case when dur is null then 8 else greatest(5, least(20, round(dur / 240)::int)) end);
  k := 'clips:' || v.id || ':' || n || ':' || md;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, version_id, asset_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'clips', k, v.id, a.id,
            jsonb_build_object('master', jsonb_build_object('version_id', v.id, 'asset_id', a.id, 'key', v.storage_path, 'name', v.original_name,
                                                            'title', a.title, 'info', v.media_info),
                               'count', n, 'count_auto', p_count is null, 'mode', md, 'language', null,
                               'youtube', case when yid is null then null else jsonb_build_object('url', left(yt, 300), 'id', yid) end),
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'clips.requested', 'media_job', j.id::text, null,
      jsonb_build_object('version_id', v.id, 'asset_id', a.id, 'count', n, 'mode', md, 'youtube', yid));
  end if;
  return public._media_job_json(j) || jsonb_build_object('count', n, 'mode', md, 'youtube', j.input->'youtube');
end $$;
revoke all on function public.clips_request2(text, uuid, int, text, text, text) from public, anon;
grant execute on function public.clips_request2(text, uuid, int, text, text, text) to authenticated;

create or replace function public.clips_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._clips_require(p_ws, p_token, 'clips.read', p_ws);
  return coalesce((select jsonb_agg(public._media_job_json(j) || jsonb_build_object(
      'master_name', j.input->'master'->>'name', 'master_title', j.input->'master'->>'title', 'count', (j.input->>'count')::int,
      'mode', coalesce(j.input->>'mode', j.result->>'mode', 'completo'), 'youtube', j.input->'youtube',
      'master_active', exists (select 1 from media_assets m where m.id = j.asset_id and m.lifecycle = 'ativo'),
      'clips', (select coalesce(jsonb_agg(public._clip_json(c) order by c.idx), '[]') from media_job_clips c where c.job_id = j.id))
      order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'clips' order by created_at desc limit 20) j), '[]');
end $$;
