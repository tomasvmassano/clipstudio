-- W10-28 · Refazer a versão leve de um vídeo já verificado (FR-08-01, EDL-08; ADR-0076). Expand (aditivo).
-- A 09/11 a versão leve do C7870 (29 GB, câmara da frente com o som da lapela) falhou no worker de 512 MB: o original ficou pronto,
-- mas o editor ficou sem imagem nem som e não havia forma de a refazer (uma versão pronta não volta a pendente: media_versions_guard).
-- Agora quem pode carregar ficheiros pede "Refazer versão leve" (media_proxy_redo): um job ingest em modo só versão leve
-- (input.proxy_only, sem reconferir o SHA-256 do original). O worker grava a versão leve por media_worker_proxy_save (só os campos
-- proxy_*, e media_info se faltar; o estado e o original não mudam) e fecha o job com media_worker_finish, que para uma versão já
-- pronta só o marca como feito. Nada reescreve funções existentes. Rollback no fim.

create or replace function public.media_proxy_redo(p_ws text, p_version uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; uid uuid; j media_jobs; k text; n int;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.proxy_redo', coalesce(p_version::text, ''));
  uid := public._media_uid();
  select * into v from media_versions where id = p_version and workspace_id = p_ws for update;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  if v.state <> 'pronta' or v.storage_provider is distinct from 'r2' or coalesce(v.mime, '') not like 'video/%' or v.storage_path is null then
    raise exception 'sem_versao_leve' using errcode = '22023', detail = 'Só um vídeo pronto, guardado na app, tem versão leve.'; end if;
  if v.proxy_state = 'pronta' then
    raise exception 'versao_leve_pronta' using errcode = '22023', detail = 'A versão leve deste vídeo já está pronta.'; end if;
  select * into j from media_jobs where version_id = v.id and kind = 'ingest' and status in ('queued', 'running')
   order by created_at desc limit 1;
  if j.id is not null then return public._media_job_json(j) || jsonb_build_object('repeated', true); end if;
  select count(*) into n from media_jobs where version_id = v.id and kind = 'ingest' and input->>'proxy_only' = 'true';
  k := 'proxy:' || v.id || ':' || (n + 1);
  insert into media_jobs (workspace_id, kind, idempotency_key, version_id, asset_id, input, created_by, created_label)
  values (p_ws, 'ingest', k, v.id, v.asset_id,
          jsonb_build_object('key', v.storage_path, 'size_bytes', v.size_bytes, 'mime', v.mime, 'sha256', v.sha256, 'proxy', true, 'proxy_only', true),
          uid, public._media_label(uid))
  returning * into j;
  update media_versions set proxy_state = 'pendente', proxy_error = null where id = v.id;
  perform public._media_audit(p_ws, 'media.proxy_redo_requested', 'media_asset', v.asset_id::text,
    jsonb_build_object('proxy_state', v.proxy_state, 'proxy_error', v.proxy_error), jsonb_build_object('version_id', v.id, 'job_id', j.id));
  return public._media_job_json(j) || jsonb_build_object('repeated', false);
end $$;

create or replace function public.media_worker_proxy_save(p_worker text, p_job uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; v media_versions; pk text := nullif(p_result->>'proxy_key', '');
begin
  select * into j from media_jobs where id = p_job for update;
  if j.id is null or j.locked_by is distinct from p_worker or j.status <> 'running' then return jsonb_build_object('lost', true); end if;
  if j.kind <> 'ingest' or j.input->>'proxy_only' is distinct from 'true' then
    raise exception 'job_sem_modo_versao_leve' using errcode = '22023'; end if;
  select * into v from media_versions where id = j.version_id and workspace_id = j.workspace_id for update;
  if v.id is null or v.state <> 'pronta' then return jsonb_build_object('lost', false, 'saved', false, 'state', v.state); end if;
  -- a chave tem de ser a da versão leve deste ficheiro (o worker grava ao lado do original)
  if pk is not null and pk <> regexp_replace(v.storage_path, '/[^/]+$', '') || '/proxy.mp4' then
    raise exception 'chave_invalida' using errcode = '22023'; end if;
  update media_versions set proxy_path = pk,
         proxy_state = case when pk is not null then 'pronta' else 'falhou' end,
         proxy_error = case when pk is null then left(coalesce(p_result->>'proxy_error', 'falhou sem motivo'), 500) end,
         media_info = coalesce(media_info, p_result->'info')
   where id = v.id returning * into v;
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'media.proxy_redone', 'media_asset', v.asset_id::text,
          jsonb_build_object('version_id', v.id, 'job_id', j.id, 'proxy', v.proxy_state, 'error', v.proxy_error), 'media:' || v.asset_id);
  return jsonb_build_object('lost', false, 'saved', true, 'proxy', v.proxy_state);
end $$;

revoke all on function public.media_proxy_redo(text, uuid, text) from public, anon;
grant execute on function public.media_proxy_redo(text, uuid, text) to authenticated;
revoke all on function public.media_worker_proxy_save(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.media_worker_proxy_save(text, uuid, jsonb) to engine_worker, service_role;

/* Rollback (o código anterior não usa nenhuma destas funções):
   drop function if exists public.media_proxy_redo(text, uuid, text);
   drop function if exists public.media_worker_proxy_save(text, uuid, jsonb);
   -- jobs ingest com input.proxy_only que fiquem na fila: update media_jobs set status = 'cancelled' where input->>'proxy_only' = 'true' and status = 'queued'; */
