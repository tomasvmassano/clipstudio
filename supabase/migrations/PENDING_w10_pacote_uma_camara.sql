-- W10-47 · Pacote com uma câmara só (EDL-01, STU-02; pedido do Tomás a 17/11: a EVOLVE gravou o C8128 com uma câmara). Expand (aditivo).
-- p_side passa a poder vir vazio: a gravação da frente faz de tudo (som, imagem, tempo), input.single = true e o motor
-- (numeiro-engine pacote-uma-camara) não sincroniza e alterna o enquadramento no corpo. Com duas câmaras nada muda
-- (mesma assinatura, mesma chave de idempotência, mesmas validações). Rollback: voltar a aplicar a função de
-- 20261109171200_w10_som_da_lapela.sql (os jobs single já criados ficam como estão; o motor continua a lê-los).

create or replace function public.edit_package_request(p_ws text, p_front uuid, p_side uuid, p_guioes text[], p_style text default 'S15',
                                                       p_token text default null, p_audio text default 'side') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; f media_versions; s media_versions; gs jsonb; n int; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
        lk jsonb; lv int; fill jsonb; au text := coalesce(nullif(p_audio, ''), 'side');
begin
  uid := public._edit_require(p_ws, p_token, 'edit.package', coalesce(p_front::text, ''), true);
  if not public.ws_can('edit.timeline', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pacote automático precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  -- uma câmara só (W10-47): sem p_side, a mesma gravação dá o som, a imagem e o tempo
  if p_side is null then au := 'front'; end if;
  if au not in ('front', 'side') then
    raise exception 'camara_do_som_invalida' using errcode = '22023', detail = 'Escolhe a câmara com o som da lapela: a da frente ou a do lado.'; end if;
  if p_front is null or p_front = p_side then
    raise exception 'camaras_invalidas' using errcode = '22023', detail = 'Escolhe a gravação da câmara da frente e, se houve segunda câmara, outra gravação diferente para a câmara do lado.'; end if;
  select v.* into f from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_front and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
  select v.* into s from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_side and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
  if p_side is null then s := f; end if;
  if f.id is null or s.id is null then
    raise exception 'gravacao_nao_encontrada' using errcode = 'P0002', detail = 'As gravações têm de estar prontas na Biblioteca (no R2) deste cliente.'; end if;
  if coalesce(cardinality(p_guioes), 0) = 0 or cardinality(p_guioes) > 40 then
    raise exception 'guioes_invalidos' using errcode = '22023', detail = 'Escolhe entre 1 e 40 guiões gravados nesta sessão.'; end if;
  select count(*), jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'hooks', g.hooks, 'corpo', g.corpo)
                             order by array_position(p_guioes, g.id))
    into n, gs from guioes g where g.client_id = p_ws and g.id = any (p_guioes) and g.deleted_at is null;
  if n <> cardinality(p_guioes) then raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'Um dos guiões não é deste cliente ou foi eliminado.'; end if;
  -- aspeto guardado do estilo pedido (versão atual, deste cliente, não arquivado)
  select v.look, v.version into lk, lv from edit_styles x
    join edit_style_versions v on v.workspace_id = x.workspace_id and v.key = x.key and v.version = x.current_version
   where x.workspace_id = p_ws and x.key = st and x.status <> 'arquivado' and v.look is not null;
  if lk is not null and nullif(lk->'music', 'null'::jsonb) is not null
     and not exists (select 1 from media_assets m where m.id::text = lk->'music'->>'asset' and m.workspace_id = p_ws and m.kind = 'audio' and m.lifecycle = 'ativo') then
    lk := jsonb_set(lk, '{music}', 'null'::jsonb);
  end if;
  -- W10-18: visuais e música da IA (só com a flag; a biblioteca e as frases vêm do servidor, nunca do browser)
  if public._flag_on('edit.ai_visuals', p_ws, p_token) then fill := public._edit_package_fill(p_ws); end if;
  -- a versão do estilo entra na chave: gravar o estilo de novo e pedir o mesmo pacote cria um job novo com o aspeto novo
  k := 'package:' || f.id || ':' || s.id || ':' || md5(array_to_string(p_guioes, ',')) || ':' || st || coalesce(':v' || lv, '')
       || case when fill is null then '' else ':ia1' end || case when au = 'front' then ':af' else '' end;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'package', k, s.id,
            jsonb_build_object('front', jsonb_build_object('version_id', f.id, 'key', f.storage_path, 'name', f.original_name, 'info', f.media_info),
                               'side', jsonb_build_object('version_id', s.id, 'key', s.storage_path, 'name', s.original_name, 'info', s.media_info),
                               'guioes', gs, 'style', st, 'audio', au)
            || case when p_side is null then jsonb_build_object('single', true) else '{}'::jsonb end
            -- sem jsonb_strip_nulls: highlight/background null no aspeto querem dizer "sem destaque/sem caixa"
            || case when lk is null then '{}'::jsonb else jsonb_build_object('look', lk, 'style_version', lv) end
            || case when fill is null then '{}'::jsonb else jsonb_build_object('fill', fill) end,
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.package_requested', 'media_job', j.id::text, null,
      jsonb_build_object('front', f.id, 'side', s.id, 'audio', au, 'single', p_side is null, 'guioes', to_jsonb(p_guioes), 'style', st, 'style_version', lv)
      || case when fill is null then '{}'::jsonb else jsonb_build_object('fill', jsonb_build_object(
           'images', jsonb_array_length(fill->'library'->'images'), 'attention', jsonb_array_length(fill->'library'->'attention'),
           'music', jsonb_array_length(fill->'library'->'music'), 'persona_version', fill->'persona'->'version',
           'preset_version', fill->'preset_version', 'recipes', fill->'recipes')) end);
  end if;
  return public._media_job_json(j);
end $$;

revoke all on function public.edit_package_request(text, uuid, uuid, text[], text, text, text) from public, anon;
grant execute on function public.edit_package_request(text, uuid, uuid, text[], text, text, text) to authenticated;
