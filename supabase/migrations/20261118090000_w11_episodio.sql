-- W11-01 · Edição do episódio completo de podcasts e vídeos longos (CHG-013, PRD §48.2, POD-01..06; ADR-0087).
-- Expand (só aditivo e compatível com o main): capacidade edit.episode (ativa) e edit.style_learn / edit.style_approve
-- (planeadas, STY-02/03), flag edit.episode, kind 'episode' em media_jobs, RPCs episode_request / episode_list /
-- episode_file_access, e media_worker_finish substituído com a mesma assinatura e as mesmas chaves (ramo 'episode' novo;
-- os outros ramos iguais aos de 20261106065110_w10_clip_miner.sql).
-- O worker (numeiro-engine, job episode) lê as câmaras no R2 e envia para input.out_prefix: master.mp4, audio.mp3,
-- legendas.srt, capitulos.txt, notas.md, episode_doc.json, cortes.json. Aqui o master entra na Biblioteca como vídeo novo;
-- os outros ficheiros descarregam-se por link assinado curto (episode_file_access, auditado). Nada é publicado.
-- Rollback: desligar a flag edit.episode; reverter a função para a da migração do Clip Miner; os jobs 'episode' ficam
-- como histórico (o check de kind só se aperta numa migração de contração posterior, ADR-0004).

insert into capabilities (key, module, risk, scopes, status, label) values
  ('edit.episode', 'Edição', 'M', array['ws'], 'ativo', 'Editar o episódio completo de um podcast ou vídeo longo'),
  ('edit.style_learn', 'Edição', 'M', array['ws'], 'planeado', 'Aprender o perfil de edição de vídeos editados'),
  ('edit.style_approve', 'Edição', 'M', array['ws'], 'planeado', 'Aprovar uma versão do perfil de edição')
on conflict (key) do update set label = excluded.label, module = excluded.module, scopes = excluded.scopes, risk = excluded.risk,
  status = case when capabilities.key = 'edit.episode' then 'ativo' else capabilities.status end;
-- mesmo grupo que clips.mine (cada pedido gasta transcrição, IA e render); outros por grant individual no Centro de Acessos
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'edit.episode'), ('ws', 'workspace_admin', 'edit.episode'), ('ws', 'manager', 'edit.episode')
on conflict do nothing;
insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('edit.episode', 'Edição do episódio completo', 'Edição', 'ws', 'owner',
   'POD-01..06 (CHG-013): de um episódio no R2 (uma ou várias câmaras) a um master limpo (pausas, hesitações, repetições, falsos arranques, câmara do orador), com áudio, legendas .srt, capítulos e notas. Precisa também de edit.studio e media.r2.')
on conflict do nothing;

alter table public.media_jobs drop constraint if exists media_jobs_kind_check;
alter table public.media_jobs add constraint media_jobs_kind_check check (kind in ('ingest', 'export', 'package', 'clips', 'episode'));

create or replace function public._episode_require(p_ws text, p_token text, p_action text, p_entity text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid;
begin
  uid := public._edit_require(p_ws, p_token, p_action, p_entity, false);
  if not public._flag_on('edit.episode', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A edição de episódios ainda não está ligada neste cliente.'; end if;
  return uid;
end $$;

-- Perfil de edição enviado ao motor: só as chaves que o motor lê (STY-01), números em intervalos seguros.
create or replace function public._episode_profile_problem(p jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare k text; v jsonb;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) <> 'object' then return 'o perfil não é um objeto'; end if;
  if octet_length(p::text) > 20000 then return 'perfil demasiado grande'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('format', 'pacing', 'audio', 'cameras', 'structure', 'rhythm', 'captions', 'extract_version', 'built_from') then
      return 'chave desconhecida no perfil: ' || k; end if;
  end loop;
  v := p->'pacing'->'max_pause_s';
  if v is not null and (jsonb_typeof(v) <> 'number' or v::text::numeric not between 0.2 and 3) then return 'pausa máxima entre 0,2 e 3 s'; end if;
  v := p->'pacing'->'keep_pause_s';
  if v is not null and (jsonb_typeof(v) <> 'number' or v::text::numeric not between 0.05 and 2) then return 'pausa nas junções entre 0,05 e 2 s'; end if;
  v := p->'audio'->'lufs';
  if v is not null and (jsonb_typeof(v) <> 'number' or v::text::numeric not between -24 and -9) then return 'loudness entre -24 e -9 LUFS'; end if;
  v := p->'cameras'->'min_shot_s';
  if v is not null and (jsonb_typeof(v) <> 'number' or v::text::numeric not between 0.5 and 30) then return 'plano mínimo entre 0,5 e 30 s'; end if;
  return null;
end $$;

-- p_cams: {"front": "<media_version uuid>", "side": "...", "wide": "..."} (1 a 4 câmaras do mesmo cliente, prontas no R2).
create or replace function public.episode_request(p_ws text, p_cams jsonb, p_audio text default null, p_wide text default null,
                                                  p_profile jsonb default null, p_language text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; c record; v media_versions; a media_assets; cams jsonb := '{}'; ids text[] := '{}'; k text; j media_jobs; why text;
        aud text; dur numeric; jid uuid := gen_random_uuid(); first_asset uuid; first_version uuid; title text;
begin
  uid := public._episode_require(p_ws, p_token, 'episode.request', '');
  if not public.ws_can('edit.episode', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.episode');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A edição de episódios precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  if jsonb_typeof(p_cams) <> 'object' or (select count(*) from jsonb_object_keys(p_cams)) not between 1 and 4 then
    raise exception 'cameras_invalidas' using errcode = '22023', detail = 'Escolhe entre 1 e 4 câmaras.'; end if;
  for c in select key, value from jsonb_each_text(p_cams) order by key loop
    if c.key !~ '^[a-z][a-z0-9_]{0,15}$' then
      raise exception 'cameras_invalidas' using errcode = '22023', detail = 'Nome de câmara inválido.'; end if;
    if c.value !~ '^[0-9a-f-]{36}$' then raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'Vídeo inválido.'; end if;
    select x.* into v from media_versions x join media_assets y on y.id = x.asset_id
     where x.id = c.value::uuid and x.workspace_id = p_ws and x.state = 'pronta' and x.storage_provider = 'r2' and x.mime like 'video/%' and y.lifecycle = 'ativo';
    if v.id is null then
      raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'Cada câmara tem de ser um vídeo pronto na Biblioteca (no R2) deste cliente.'; end if;
    if c.value = any(ids) then raise exception 'cameras_invalidas' using errcode = '22023', detail = 'A mesma gravação em duas câmaras.'; end if;
    ids := ids || c.value;
    cams := cams || jsonb_build_object(c.key, jsonb_build_object('version_id', v.id, 'asset_id', v.asset_id, 'key', v.storage_path,
                                                                 'name', v.original_name, 'info', v.media_info));
  end loop;
  aud := coalesce(nullif(p_audio, ''), (select min(x) from jsonb_object_keys(p_cams) x));
  if not cams ? aud then raise exception 'cameras_invalidas' using errcode = '22023', detail = 'A câmara do som tem de ser uma das escolhidas.'; end if;
  if nullif(p_wide, '') is not null and not cams ? p_wide then
    raise exception 'cameras_invalidas' using errcode = '22023', detail = 'A câmara do plano largo tem de ser uma das escolhidas.'; end if;
  why := public._episode_profile_problem(p_profile);
  if why is not null then raise exception 'perfil_invalido' using errcode = '22023', detail = why; end if;
  if p_language is not null and p_language not in ('pt', 'en') then
    raise exception 'idioma_invalido' using errcode = '22023', detail = 'Idioma: pt ou en (vazio deteta).'; end if;
  dur := case when jsonb_typeof(cams->aud->'info'->'duration') = 'number' then (cams->aud->'info'->>'duration')::numeric end;
  if dur is not null and dur < 60 then
    raise exception 'video_curto' using errcode = '22023', detail = 'O episódio tem menos de 1 minuto.'; end if;
  if dur is not null and dur > 4 * 3600 then
    raise exception 'video_longo' using errcode = '22023', detail = 'O episódio tem mais de 4 horas: corta-o em partes.'; end if;
  first_version := (cams->aud->>'version_id')::uuid; first_asset := (cams->aud->>'asset_id')::uuid;
  k := 'episode:' || array_to_string(ids, ',') || ':' || aud || ':' || coalesce(nullif(p_wide, ''), '-') || ':' ||
       md5(coalesce(p_profile::text, '')) || ':' || coalesce(p_language, '-');
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    select y.title into title from media_assets y where y.id = first_asset;
    insert into media_jobs (id, workspace_id, kind, idempotency_key, version_id, asset_id, input, created_by, created_label, max_attempts)
    values (jid, p_ws, 'episode', k, first_version, first_asset,
            jsonb_build_object('cams', cams, 'audio', aud, 'wide', nullif(p_wide, ''), 'profile', p_profile, 'language', p_language,
                               'title', title, 'out_prefix', p_ws || '/episodes/' || jid),
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'episode.requested', 'media_job', j.id::text, null,
      jsonb_build_object('cams', (select jsonb_object_agg(x.key, x.value->'version_id') from jsonb_each(cams) x), 'audio', aud,
                         'wide', nullif(p_wide, ''), 'profile', p_profile is not null));
  end if;
  return public._media_job_json(j);
end $$;

create or replace function public.episode_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._episode_require(p_ws, p_token, 'episode.list', '');
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'status', j.status, 'progress', j.progress, 'last_error', j.last_error, 'created_label', j.created_label,
      'created_at', j.created_at, 'finished_at', j.finished_at, 'title', j.input->>'title',
      'cams', (select jsonb_object_agg(x.key, x.value->>'name') from jsonb_each(j.input->'cams') x),
      'audio', j.input->>'audio', 'wide', j.input->>'wide', 'profile', (j.input->'profile') is not null and j.input->'profile' <> 'null'::jsonb,
      'summary', j.result->'summary', 'titles', j.result->'titles', 'flags', j.result->'flags', 'language', j.result->>'language',
      'files', (select coalesce(jsonb_agg(f order by f), '[]') from jsonb_object_keys(coalesce(j.result->'files', '{}')) f),
      'master_asset_id', j.result->>'asset_id') order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'episode' order by created_at desc limit 50) j), '[]');
end $$;

-- Link assinado curto para um ficheiro do episódio (media.download, auditado; a autorização de 60 s é a de media_access).
create or replace function public.episode_file_access(p_ws text, p_job uuid, p_name text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; f jsonb; uid uuid; mime text; base text;
begin
  perform public._episode_require(p_ws, p_token, 'episode.file', coalesce(p_job::text, ''));
  perform public._media_require('media.download', p_ws, p_token, 'episode.file', coalesce(p_job::text, ''));
  uid := public._media_uid();
  if p_name not in ('master.mp4', 'audio.mp3', 'legendas.srt', 'capitulos.txt', 'notas.md', 'cortes.json') then
    raise exception 'ficheiro_invalido' using errcode = '22023', detail = 'Ficheiro desconhecido.'; end if;
  select * into j from media_jobs where id = p_job and workspace_id = p_ws and kind = 'episode';
  if j.id is null then raise exception 'episodio_nao_encontrado' using errcode = 'P0002'; end if;
  if j.status <> 'done' then raise exception 'episodio_por_acabar' using errcode = '22023', detail = 'O episódio ainda não está pronto.'; end if;
  f := j.result->'files'->p_name;
  if f is null or coalesce(f->>'key', '') not like (j.input->>'out_prefix') || '/%' then
    raise exception 'ficheiro_nao_encontrado' using errcode = 'P0002', detail = 'Este ficheiro não foi gerado neste episódio.'; end if;
  mime := case split_part(p_name, '.', 2) when 'mp4' then 'video/mp4' when 'mp3' then 'audio/mpeg' when 'srt' then 'application/x-subrip'
          when 'txt' then 'text/plain' when 'md' then 'text/markdown' else 'application/json' end;
  base := left(regexp_replace(coalesce(j.input->>'title', 'episodio'), '[^A-Za-z0-9 ._-]', '', 'g'), 80);
  delete from media_access_grants where expires_at < now() - interval '1 hour';
  insert into media_access_grants (workspace_id, object_path, user_id, purpose, expires_at) values (p_ws, f->>'key', uid, 'download', now() + interval '60 seconds');
  perform public._media_audit(p_ws, 'episode.file_accessed', 'media_job', j.id::text, null, jsonb_build_object('file', p_name));
  return jsonb_build_object('bucket', 'r2', 'path', f->>'key', 'mime', mime, 'filename', coalesce(nullif(btrim(base), ''), 'episodio') || ' - ' || p_name,
                            'ttl_seconds', 120);
end $$;

grant execute on function public.episode_request(text, jsonb, text, text, jsonb, text, text) to authenticated;
grant execute on function public.episode_list(text, text) to authenticated;
grant execute on function public.episode_file_access(text, uuid, text, text) to authenticated;
revoke execute on function public._episode_require(text, text, text, text) from public, anon, authenticated;

-- Igual a 20261106065110_w10_clip_miner.sql mais o ramo 'episode' (antes do export, que é o ramo por omissão).
create or replace function public.media_worker_finish(p_worker text, p_job uuid, p_ok boolean, p_result jsonb default null,
                                                      p_error text default null, p_retryable boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j media_jobs; v media_versions; a media_assets; why text; n int; out_sha text; out_size bigint;
begin
  select * into j from media_jobs where id = p_job for update;
  if j.id is null or j.locked_by is distinct from p_worker or j.status <> 'running' then return jsonb_build_object('lost', true); end if;
  if not p_ok then
    if j.cancel_requested then
      update media_jobs set status = 'cancelled', finished_at = now(), locked_by = null, locked_until = null, last_error = left(p_error, 2000) where id = j.id;
    elsif p_retryable and j.attempts < j.max_attempts then
      update media_jobs set status = 'queued', locked_by = null, locked_until = null, last_error = left(p_error, 2000),
             next_attempt_at = now() + make_interval(secs => least(3600, 30 * power(2, j.attempts)::int)) where id = j.id;
    else
      update media_jobs set status = case when p_retryable then 'dead' else 'failed' end, finished_at = now(), locked_by = null, locked_until = null,
             last_error = left(p_error, 2000) where id = j.id;
      if j.kind = 'ingest' then
        update media_versions set state = 'falhou', failed_reason = left('verificacao_falhou: ' || coalesce(p_error, ''), 500)
         where id = j.version_id and state = 'pendente';
      end if;
    end if;
    insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
    values ('system', 'worker ' || p_worker, j.workspace_id, 'media.job_error', 'media_job', j.id::text,
            jsonb_build_object('kind', j.kind, 'attempt', j.attempts, 'error', left(p_error, 500), 'retryable', p_retryable), 'media:' || coalesce(j.asset_id::text, ''));
    return jsonb_build_object('lost', false);
  end if;

  if j.kind = 'ingest' then
    select * into v from media_versions where id = j.version_id for update;
    if v.state <> 'pendente' then
      update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
      return jsonb_build_object('lost', false, 'state', v.state);
    end if;
    if (p_result->>'size_bytes')::bigint is distinct from v.size_bytes then
      why := format('tamanho_diferente: declarado %s, guardado %s', v.size_bytes, coalesce(p_result->>'size_bytes', 'desconhecido'));
    elsif lower(coalesce(p_result->>'sha256', '')) <> v.sha256 then
      why := 'checksum_diferente: o SHA-256 do objeto guardado não é o do ficheiro do browser';
    end if;
    if why is not null then
      update media_versions set state = 'falhou', failed_reason = why where id = v.id;
      update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result || jsonb_build_object('rejected', why) where id = j.id;
      insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
      values ('system', 'worker ' || p_worker, j.workspace_id, 'media.upload_failed', 'media_asset', v.asset_id::text,
              jsonb_build_object('version_id', v.id, 'reason', why), 'media:' || v.asset_id);
      return jsonb_build_object('lost', false, 'state', 'falhou');
    end if;
    update media_versions set state = 'pronta', completed_at = now(), checksum_verified = true, checksum_verified_at = now(),
           media_info = p_result->'info',
           proxy_path = nullif(p_result->>'proxy_key', ''),
           proxy_state = case when v.mime like 'video/%' then case when nullif(p_result->>'proxy_key', '') is not null then 'pronta' else 'falhou' end else 'nao_aplica' end,
           proxy_error = p_result->>'proxy_error'
     where id = v.id returning * into v;
    update media_assets x set current_version_id = v.id
     where x.id = v.asset_id and (x.current_version_id is null or (select version_no from media_versions where id = x.current_version_id) < v.version_no)
     returning * into a;
    if a.id is null then select * into a from media_assets where id = v.asset_id; end if;
    insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
    values ('system', 'worker ' || p_worker, j.workspace_id, 'media.version_ready', 'media_asset', v.asset_id::text,
            jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'size_bytes', v.size_bytes, 'sha256', v.sha256, 'checksum_verified', true,
                               'proxy', v.proxy_state), 'media:' || v.asset_id);
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (j.workspace_id, 'asset.uploaded', 'media_asset', v.asset_id::text, jsonb_build_object('version_id', v.id, 'version_no', v.version_no,
            'kind', a.kind, 'content_id', a.content_id, 'size_bytes', v.size_bytes, 'mime', v.mime));
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta');
  end if;

  if j.kind = 'package' then
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta', 'documents', (select count(*) from media_job_outputs where job_id = j.id));
  end if;

  if j.kind = 'clips' then
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'pronta', 'clips', (select count(*) from media_job_clips where job_id = j.id));
  end if;

  if j.kind = 'episode' then
    -- POD-01..06 (CHG-013): o master entra na Biblioteca como vídeo novo; os outros ficheiros ficam no resultado (links por episode_file_access)
    out_sha := lower(coalesce(p_result->'files'->'master.mp4'->>'sha256', '')); out_size := (p_result->'files'->'master.mp4'->>'size_bytes')::bigint;
    if out_sha !~ '^[0-9a-f]{64}$' or out_size is null or out_size <= 0
       or coalesce(p_result->'files'->'master.mp4'->>'key', '') <> (j.input->>'out_prefix') || '/master.mp4'
       or exists (select 1 from jsonb_each(coalesce(p_result->'files', '{}')) f where coalesce(f.value->>'key', '') not like (j.input->>'out_prefix') || '/%') then
      update media_jobs set status = 'failed', finished_at = now(), locked_by = null, locked_until = null, last_error = 'resultado_invalido', result = p_result where id = j.id;
      return jsonb_build_object('lost', false, 'state', 'falhou');
    end if;
    insert into media_assets (workspace_id, kind, title, tags, status, content_id, notes, created_by, created_label)
    values (j.workspace_id, 'video', left('Episódio editado · ' || coalesce(j.input->>'title', 'sem título'), 160), array['episodio', 'edicao_ia'], 'em_trabalho', null,
            left('Edição do episódio completo (proposta da IA para rever): ' || coalesce((p_result->'summary'->>'cuts'), '?') || ' cortes, '
                 || coalesce((p_result->'summary'->>'removed_pct'), '?') || '% removido.', 500), j.created_by, 'Edição de episódio')
    returning * into a;
    insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256,
                                upload_expires_at, uploaded_by, uploaded_label, storage_provider)
    values (j.workspace_id, a.id, 1, 'upload', 'pendente', 'r2', p_result->'files'->'master.mp4'->>'key',
            left(regexp_replace(coalesce(j.input->>'title', 'episodio'), '[^A-Za-z0-9 ._-]', '', 'g'), 100) || ' (editado).mp4',
            out_size, 'video/mp4', out_sha, now() + interval '1 hour', j.created_by, j.created_label, 'r2')
    returning * into v;
    update media_versions set state = 'pronta', completed_at = now(), checksum_verified = true, checksum_verified_at = now(), upload_claimed_at = now(),
           media_info = p_result->'files'->'master.mp4'->'info', proxy_state = 'falhou', proxy_error = 'sem versão leve (episódio em paisagem)'
     where id = v.id returning * into v;
    update media_assets set current_version_id = v.id where id = a.id;
    insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
    values ('system', 'worker ' || p_worker, j.workspace_id, 'episode.edited', 'media_asset', a.id::text,
            jsonb_build_object('job_id', j.id, 'version_id', v.id, 'size_bytes', out_size, 'summary', p_result->'summary'), 'media:' || a.id);
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (j.workspace_id, 'asset.uploaded', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', 1, 'kind', a.kind,
            'content_id', null, 'size_bytes', out_size, 'mime', 'video/mp4', 'from_episode', j.id));
    update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, version_id = v.id,
           result = p_result || jsonb_build_object('asset_id', a.id, 'version_id', v.id) where id = j.id;
    if j.created_by is not null then
      perform public._notify(j.created_by, j.workspace_id, 'video_decision', 'media_asset', a.id::text,
        'Episódio editado: ' || coalesce(j.input->>'title', 'episódio'), 'O master, o áudio, as legendas e os capítulos estão prontos.', 'episode:' || j.id);
    end if;
    return jsonb_build_object('lost', false, 'state', 'pronta', 'asset_id', a.id, 'version_id', v.id);
  end if;

  -- export
  out_sha := lower(coalesce(p_result->>'sha256', '')); out_size := (p_result->>'size_bytes')::bigint;
  if out_sha !~ '^[0-9a-f]{64}$' or out_size is null or out_size <= 0 or coalesce(p_result->>'key', '') <> j.input->>'out_key' then
    update media_jobs set status = 'failed', finished_at = now(), locked_by = null, locked_until = null, last_error = 'resultado_invalido', result = p_result where id = j.id;
    return jsonb_build_object('lost', false, 'state', 'falhou');
  end if;
  select * into a from media_assets where id = j.asset_id for update;
  n := coalesce((select max(version_no) from media_versions where asset_id = a.id), 0) + 1;
  insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_bucket, storage_path, original_name, size_bytes, mime, sha256,
                              upload_expires_at, uploaded_by, uploaded_label, storage_provider)
  values (j.workspace_id, a.id, n, 'upload', 'pendente', 'r2', j.input->>'out_key',
          left(regexp_replace(coalesce(a.title, 'video'), '[^A-Za-z0-9 ._-]', '', 'g'), 120) || ' (edição v' || (j.input->>'edit_version_no') || ').mp4',
          out_size, 'video/mp4', out_sha, now() + interval '1 hour', j.created_by, j.created_label, 'r2')
  returning * into v;
  update media_versions set state = 'pronta', completed_at = now(), checksum_verified = true, checksum_verified_at = now(), upload_claimed_at = now(),
         media_info = p_result->'info', proxy_path = nullif(p_result->>'proxy_key', ''),
         proxy_state = case when nullif(p_result->>'proxy_key', '') is not null then 'pronta' else 'falhou' end
   where id = v.id returning * into v;
  update media_assets set current_version_id = v.id where id = a.id;
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'edit.exported', 'media_asset', a.id::text,
          jsonb_build_object('job_id', j.id, 'version_id', v.id, 'version_no', n, 'edit_version_id', j.edit_version_id, 'size_bytes', out_size), 'media:' || a.id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'asset.uploaded', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', n, 'kind', a.kind,
          'content_id', a.content_id, 'size_bytes', out_size, 'mime', 'video/mp4', 'from_edit', j.edit_version_id));
  update media_jobs set status = 'done', finished_at = now(), locked_by = null, locked_until = null, version_id = v.id,
         result = p_result || jsonb_build_object('version_id', v.id, 'version_no', n) where id = j.id;
  if j.created_by is not null then
    perform public._notify(j.created_by, j.workspace_id, 'video_decision', 'media_asset', a.id::text,
      'Exportação pronta: ' || coalesce(a.title, 'vídeo') || ' (v' || n || ')', 'A versão editada já está na revisão.', 'export:' || j.id);
  end if;
  return jsonb_build_object('lost', false, 'state', 'pronta', 'version_id', v.id, 'version_no', n);
end $$;
