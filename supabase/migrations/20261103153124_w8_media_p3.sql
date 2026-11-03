-- W8 · Biblioteca de media, parte 3 de 3: links de partilha com expiração e auditoria (FR-08-03), limpeza de órfãos e
-- eliminação definitiva com confirmação explícita (FR-08-06), política de tipos/tamanho/quota/retenção por cliente (FR-08-05).
-- A eliminação do objeto é feita pela API do storage (o Supabase não deixa apagar storage.objects por SQL): a RPC "begin"
-- autoriza e devolve os caminhos, o servidor apaga pela API e a RPC "finish" só marca o que já não existe. Não há job de
-- eliminação automática ao fim do prazo do lixo: fica para um job futuro (ADR-0038).
-- Expand (só aditivo): funções novas. Rollback no fim.

-- ───────────── partilha ─────────────
create or replace function public.media_share_create(p_ws text, p_version uuid, p_hours int default 24, p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v media_versions; a media_assets; uid uuid; tok text; s media_shares;
begin
  perform public._media_require('media.share', p_ws, p_token, 'media.share_create', p_version::text);
  uid := public._media_uid();
  if p_hours is null or p_hours not between 1 and 168 then
    raise exception 'validade_invalida' using errcode = '22023', detail = 'Um link de partilha vale entre 1 hora e 7 dias.'; end if;
  select * into v from media_versions where id = p_version and workspace_id = p_ws;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  select * into a from media_assets where id = v.asset_id;
  if v.source <> 'upload' or v.state <> 'pronta' or a.lifecycle <> 'ativo' then
    raise exception 'versao_indisponivel' using errcode = '22023', detail = 'Só se partilha uma versão pronta de um ativo ativo.'; end if;
  tok := encode(extensions.gen_random_bytes(24), 'hex');
  insert into media_shares (workspace_id, asset_id, version_id, token_hash, expires_at, note, created_by, created_label)
  values (p_ws, a.id, v.id, encode(extensions.digest(tok, 'sha256'), 'hex'), now() + make_interval(hours => p_hours),
          nullif(left(btrim(coalesce(p_note, '')), 200), ''), uid, public._media_label(uid))
  returning * into s;
  perform public._media_audit(p_ws, 'media.share_created', 'media_asset', a.id::text, null,
    jsonb_build_object('share_id', s.id, 'version_id', v.id, 'expires_at', s.expires_at));
  -- o token só sai aqui, uma vez; na base fica o hash
  return jsonb_build_object('id', s.id, 'token', tok, 'expires_at', s.expires_at, 'version_no', v.version_no);
end $$;

create or replace function public.media_share_revoke(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s media_shares; uid uuid;
begin
  perform public._media_require('media.share', p_ws, p_token, 'media.share_revoke', p_id::text);
  uid := public._media_uid();
  select * into s from media_shares where id = p_id and workspace_id = p_ws for update;
  if s.id is null then raise exception 'link_nao_encontrado' using errcode = 'P0002'; end if;
  if s.revoked_at is null then
    update media_shares set revoked_at = now(), revoked_by = uid, revoked_label = public._media_label(uid) where id = p_id returning * into s;
    delete from media_access_grants where share_id = p_id;
    perform public._media_audit(p_ws, 'media.share_revoked', 'media_asset', s.asset_id::text, null, jsonb_build_object('share_id', s.id));
  end if;
  return jsonb_build_object('id', s.id, 'revoked_at', s.revoked_at);
end $$;

-- Abrir um link de partilha (sem sessão). Qualquer falha devolve o mesmo erro: não revela se o link existiu.
create or replace function public.media_share_open(p_share_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s media_shares; v media_versions; a media_assets; c clients;
begin
  if p_share_token is null or p_share_token !~ '^[0-9a-f]{48}$' then raise exception 'link_invalido' using errcode = 'P0002'; end if;
  select * into s from media_shares where token_hash = encode(extensions.digest(p_share_token, 'sha256'), 'hex') for update;
  if s.id is not null then
    select * into v from media_versions where id = s.version_id;
    select * into a from media_assets where id = s.asset_id;
    select * into c from clients where id = s.workspace_id;
  end if;
  if s.id is null or s.revoked_at is not null or s.expires_at <= now() or v.state <> 'pronta' or a.lifecycle <> 'ativo' or c.status <> 'active'
     or public._flag_stage('media.library', c.organization_id, c.id) = 'off' then
    -- a exceção desfaz qualquer escrita: a recusa fica no log da base (como audit_denied nas outras RPCs)
    raise log 'audit_denied %', jsonb_build_object('action', 'media.share_opened', 'share_id', s.id, 'workspace_id', s.workspace_id);
    raise exception 'link_invalido' using errcode = 'P0002', detail = 'Este link expirou, foi revogado ou não existe.';
  end if;
  update media_shares set open_count = open_count + 1, last_opened_at = now() where id = s.id;
  delete from media_access_grants where expires_at < now() - interval '1 hour';
  insert into media_access_grants (workspace_id, object_path, share_id, purpose, expires_at) values (s.workspace_id, v.storage_path, s.id, 'share', now() + interval '60 seconds');
  insert into audit_events (actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'link de partilha', c.organization_id, s.workspace_id, 'media.share_opened', 'media_asset', s.asset_id::text,
          jsonb_build_object('share_id', s.id, 'version_id', v.id), 'media:' || s.asset_id);
  return jsonb_build_object('bucket', v.storage_bucket, 'path', v.storage_path, 'filename', v.original_name, 'mime', v.mime,
    'ttl_seconds', least(300, greatest(1, extract(epoch from s.expires_at - now())::int)));
end $$;

-- ───────────── limpeza de órfãos e eliminação definitiva ─────────────
-- p_scope 'orfaos': p_ids são versões falhadas ou pendentes expiradas. 'lixo': p_ids são ativos no lixo.
-- p_confirm tem de ser exatamente 'APAGAR' (confirmação explícita verificada no servidor).
create or replace function public.media_purge_begin(p_ws text, p_scope text, p_ids uuid[], p_confirm text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; n int; out jsonb;
begin
  perform public._media_require('media.manage', p_ws, p_token, 'media.purge', p_ws);
  uid := public._media_uid();
  if p_scope not in ('orfaos', 'lixo') then raise exception 'ambito_invalido' using errcode = '22023'; end if;
  if coalesce(p_confirm, '') <> 'APAGAR' then
    raise exception 'confirmacao_em_falta' using errcode = '22023', detail = 'Escreve APAGAR para confirmar a eliminação definitiva.'; end if;
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 100 then raise exception 'selecao_invalida' using errcode = '22023', detail = 'Escolhe entre 1 e 100.'; end if;
  if p_scope = 'orfaos' then
    select count(*) into n from media_versions v where v.id = any(p_ids) and v.workspace_id = p_ws and v.source = 'upload'
       and (v.state = 'falhou' or (v.state = 'pendente' and v.upload_expires_at <= now()));
    if n <> cardinality(p_ids) then raise exception 'selecao_invalida' using errcode = '22023', detail = 'Há itens que não são órfãos deste cliente.'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('version_id', v.id, 'bucket', v.storage_bucket, 'path', v.storage_path)), '[]') into out
      from media_versions v where v.id = any(p_ids);
  else
    select count(*) into n from media_assets a where a.id = any(p_ids) and a.workspace_id = p_ws and a.lifecycle = 'no_lixo';
    if n <> cardinality(p_ids) then raise exception 'selecao_invalida' using errcode = '22023', detail = 'Há itens que não estão no lixo deste cliente.'; end if;
    update media_assets set purge_requested_at = now(), purge_requested_by = uid where id = any(p_ids);
    select coalesce(jsonb_agg(jsonb_build_object('version_id', v.id, 'bucket', v.storage_bucket, 'path', v.storage_path)), '[]') into out
      from media_versions v where v.asset_id = any(p_ids) and v.source = 'upload' and v.state <> 'apagada';
  end if;
  perform public._media_audit(p_ws, 'media.purge_requested', 'workspace', p_ws, null, jsonb_build_object('scope', p_scope, 'ids', to_jsonb(p_ids)));
  return jsonb_build_object('scope', p_scope, 'objects', out);
end $$;

create or replace function public.media_purge_finish(p_ws text, p_scope text, p_ids uuid[], p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; gone int := 0; purged int := 0; remaining jsonb; r record;
begin
  perform public._media_require('media.manage', p_ws, p_token, 'media.purge', p_ws);
  uid := public._media_uid();
  if p_scope not in ('orfaos', 'lixo') then raise exception 'ambito_invalido' using errcode = '22023'; end if;
  for r in
    select v.id from media_versions v
     where v.workspace_id = p_ws and v.state <> 'apagada'
       and ((p_scope = 'orfaos' and v.id = any(p_ids) and (v.state = 'falhou' or (v.state = 'pendente' and v.upload_expires_at <= now())))
         or (p_scope = 'lixo' and v.asset_id = any(p_ids) and exists (select 1 from media_assets a where a.id = v.asset_id and a.lifecycle = 'no_lixo' and a.purge_requested_at is not null)))
       and (v.source = 'link' or not exists (select 1 from storage.objects o where o.bucket_id = 'media' and o.name = v.storage_path))
  loop
    update media_versions set state = 'apagada', deleted_at = now() where id = r.id;
    gone := gone + 1;
  end loop;
  if p_scope = 'lixo' then
    for r in select a.id from media_assets a where a.id = any(p_ids) and a.workspace_id = p_ws and a.lifecycle = 'no_lixo' and a.purge_requested_at is not null
               and not exists (select 1 from media_versions v where v.asset_id = a.id and v.state <> 'apagada') loop
      update media_assets set lifecycle = 'eliminado', purged_at = now(), purged_by = uid, current_version_id = null where id = r.id;
      update media_shares set revoked_at = coalesce(revoked_at, now()), revoked_by = coalesce(revoked_by, uid) where asset_id = r.id;
      insert into domain_events (workspace_id, type, entity_type, entity_id, payload) values (p_ws, 'asset.purged', 'media_asset', r.id::text, '{}');
      purged := purged + 1;
    end loop;
  end if;
  select coalesce(jsonb_agg(v.storage_path), '[]') into remaining from media_versions v
   where v.workspace_id = p_ws and v.state <> 'apagada' and v.source = 'upload'
     and ((p_scope = 'orfaos' and v.id = any(p_ids)) or (p_scope = 'lixo' and v.asset_id = any(p_ids)));
  perform public._media_audit(p_ws, 'media.purged', 'workspace', p_ws, null,
    jsonb_build_object('scope', p_scope, 'ids', to_jsonb(p_ids), 'versions_deleted', gone, 'assets_purged', purged, 'remaining', remaining));
  return jsonb_build_object('versions_deleted', gone, 'assets_purged', purged, 'remaining', remaining);
end $$;

-- ───────────── política do cliente (FR-08-05): só o dono da agência (media.policy.manage) ─────────────
create or replace function public.media_policy_save(p_ws text, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid := (select organization_id from clients where id = p_ws and status = 'active'); k text;
        b jsonb; mimes text[]; mx bigint; qt bigint; td int; f jsonb := coalesce(p_fields, '{}');
begin
  if uid is null or org is null or not public._org_can('media.policy.manage', org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'media.policy_save');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not public._flag_on('media.library', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A biblioteca de media ainda não está ligada neste cliente.'; end if;
  for k in select jsonb_object_keys(f) loop
    if k not in ('allowed_mime', 'max_file_bytes', 'quota_bytes', 'trash_days') then raise exception 'campo_desconhecido:%', k using errcode = '22023'; end if;
  end loop;
  b := public._media_policy(p_ws);
  select allowed_mime, max_file_bytes, quota_bytes, trash_days into mimes, mx, qt, td from media_policies where workspace_id = p_ws;
  if f ? 'allowed_mime' then
    if jsonb_typeof(f->'allowed_mime') = 'null' then mimes := null;
    else
      mimes := array(select distinct lower(x) from jsonb_array_elements_text(f->'allowed_mime') x order by 1);
      if cardinality(mimes) = 0 then raise exception 'tipos_invalidos' using errcode = '22023', detail = 'Escolhe pelo menos um tipo.'; end if;
      if not mimes <@ public._media_default_mime() then
        raise exception 'tipos_invalidos' using errcode = '22023', detail = 'Só tipos que o bucket aceita.'; end if;
    end if;
  end if;
  if f ? 'max_file_bytes' then mx := (f->>'max_file_bytes')::bigint;
    if mx is not null and (mx < 1048576 or mx > public._media_ceiling()) then
      raise exception 'tamanho_invalido' using errcode = '22023',
        detail = format('Entre 1 MB e %s MB (limite do bucket, depende do plano do Supabase).', round(public._media_ceiling()::numeric / 1048576)); end if; end if;
  if f ? 'quota_bytes' then qt := (f->>'quota_bytes')::bigint;
    if qt is not null and (qt < 104857600 or qt > 10995116277760) then
      raise exception 'quota_invalida' using errcode = '22023', detail = 'Quota entre 100 MB e 10 TB.'; end if; end if;
  if f ? 'trash_days' then td := (f->>'trash_days')::int;
    if td is not null and td not between 1 and 365 then raise exception 'prazo_invalido' using errcode = '22023', detail = 'Lixo entre 1 e 365 dias.'; end if; end if;
  insert into media_policies (workspace_id, allowed_mime, max_file_bytes, quota_bytes, trash_days, updated_at, updated_by, updated_label)
  values (p_ws, mimes, mx, qt, td, now(), uid, public._media_label(uid))
  on conflict (workspace_id) do update set allowed_mime = excluded.allowed_mime, max_file_bytes = excluded.max_file_bytes,
    quota_bytes = excluded.quota_bytes, trash_days = excluded.trash_days, updated_at = now(), updated_by = uid, updated_label = excluded.updated_label;
  perform public._media_audit(p_ws, 'media.policy_updated', 'workspace', p_ws, b, public._media_policy(p_ws));
  return public._media_policy(p_ws);
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'valor_invalido' using errcode = '22023';
end $$;

revoke all on function public.media_share_create(text, uuid, int, text, text), public.media_share_revoke(text, uuid, text), public.media_share_open(text),
  public.media_purge_begin(text, text, uuid[], text, text), public.media_purge_finish(text, text, uuid[], text), public.media_policy_save(text, jsonb, text) from public;
grant execute on function public.media_share_create(text, uuid, int, text, text), public.media_share_revoke(text, uuid, text),
  public.media_purge_begin(text, text, uuid[], text, text), public.media_purge_finish(text, text, uuid[], text), public.media_policy_save(text, jsonb, text) to anon, authenticated;
grant execute on function public.media_share_open(text) to anon, authenticated;

/* Rollback (compatível):
   drop function public.media_policy_save(text, jsonb, text), public.media_purge_finish(text, text, uuid[], text),
     public.media_purge_begin(text, text, uuid[], text, text), public.media_share_open(text), public.media_share_revoke(text, uuid, text),
     public.media_share_create(text, uuid, int, text, text); */
