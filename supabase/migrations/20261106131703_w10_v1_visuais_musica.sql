-- W10-18 · EDL-07 + EDL-01 + EDL-04 + R-17: a versão 1 do pacote vem com visuais e música escolhidos pela IA (ADR-0068).
-- Expand (aditivo e compatível com o main): flag nova, função nova _edit_package_fill e o corpo de edit_package_request
-- (mesma assinatura). Não mexe em tabelas nem em _edit_doc_problem.
--  1. Flag edit.ai_visuals (por cliente, default 'owner'). Desligada: o input do job e a chave de idempotência ficam iguais aos
--     de hoje (o worker faz o que faz hoje).
--  2. Ligada: edit_package_request junta 'fill' ao input do job, montado no servidor por _edit_package_fill:
--       recipes  receita por hook, do preset de edição do cliente (edit_presets: 1.º hook master, os seguintes pelas saídas
--                split_image_persona / split_attention); sem preset, o ponto de partida do EDL-01;
--       library  só ativos DESTE cliente, ativos, com a versão atual pronta, carregada (upload) no R2 e com a etiqueta que os
--                autoriza para a IA: ia-imagem (imagens), ia-atencao (vídeos de atenção, EDL-04), ia-musica (áudio);
--                no máximo 60 de cada, os mais recentes; links externos e Supabase Storage ficam de fora;
--       persona  a lista de frases-persona em vigor (R-17), só o texto e o nome de quem a frase envolve (como worker_claim).
--     O motor (numeiro-engine, package_visuals) só escolhe dentro disto e escreve o porquê em doc.ai.visuals. A chave de
--     idempotência ganha ':ia1' (pedir de novo com a flag ligada cria um job novo, com visuais).

insert into public.feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('edit.ai_visuals', 'Visuais e música da IA no pacote', 'Editor', 'ws', 'owner',
   'A versão 1 do pacote automático vem com imagem, frase-persona, vídeo de atenção e música da Biblioteca do cliente (etiquetas ia-imagem, ia-atencao, ia-musica) e a lista de frases aprovada; o editor mostra o que a IA escolheu e porquê (EDL-07, ADR-0068).')
on conflict (key) do nothing;

create or replace function public._edit_package_fill(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  with lib as (
    select a.id, a.title, a.tags, a.kind, v.mime, v.media_info, a.updated_at
      from media_assets a join media_versions v on v.id = a.current_version_id
     where a.workspace_id = p_ws and v.workspace_id = p_ws and a.lifecycle = 'ativo'
       and v.state = 'pronta' and v.source = 'upload' and v.storage_provider = 'r2'
       and a.tags && array['ia-imagem', 'ia-atencao', 'ia-musica']
  ), pick as (
    select l.*, s.slot, row_number() over (partition by s.slot order by l.updated_at desc, l.id) rn
      from lib l
      join (values ('images', 'ia-imagem', 'image/'), ('attention', 'ia-atencao', 'video/'), ('music', 'ia-musica', 'audio/')) s(slot, tag, mime)
        on s.tag = any (l.tags) and l.mime like s.mime || '%'
       and ((s.slot = 'images' and l.kind in ('imagem', 'thumbnail')) or (s.slot = 'attention' and l.kind = 'video')
            or (s.slot = 'music' and l.kind = 'audio'))
  ), pl as (select * from public._persona_current(p_ws)
  ), pr as (select version, outputs from edit_presets where workspace_id = p_ws order by version desc limit 1)
  select jsonb_build_object(
    -- receita por hook a partir do preset do cliente (edit_presets): o 1.º hook é o master; os seguintes seguem as saídas
    -- split_image_persona / split_attention do preset, pela ordem. Sem preset: o ponto de partida do EDL-01 (_edit_seed).
    'recipes', case when not exists (select 1 from pr) then jsonb_build_array('master', 'imagem_frase', 'atencao_frase')
                    else jsonb_build_array('master') || coalesce((select jsonb_agg(case o->>'kind' when 'split_image_persona' then 'imagem_frase' else 'atencao_frase' end order by n)
                                                                   from pr, jsonb_array_elements(pr.outputs) with ordinality x(o, n)
                                                                  where o->>'kind' in ('split_image_persona', 'split_attention')), '[]') end,
    'preset_version', (select version from pr),
    'library', jsonb_build_object(
      'images', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'tags', to_jsonb(tags), 'mime', mime) order by rn)
                          from pick where slot = 'images' and rn <= 60), '[]'),
      'attention', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'tags', to_jsonb(tags), 'mime', mime,
                                                                 'duration', media_info->'duration') order by rn)
                             from pick where slot = 'attention' and rn <= 60), '[]'),
      'music', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'tags', to_jsonb(tags), 'mime', mime) order by rn)
                         from pick where slot = 'music' and rn <= 60), '[]')),
    'persona', jsonb_build_object(
      'version', coalesce((select version from pl), 0),
      'phrases', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('text', x->>'text', 'involves', x->'involves'->>'name')))
                           from pl, jsonb_array_elements(coalesce(pl.phrases, '[]')) x), '[]')))
$$;
revoke all on function public._edit_package_fill(text) from public, anon, authenticated;

create or replace function public.edit_package_request(p_ws text, p_front uuid, p_side uuid, p_guioes text[], p_style text default 'S15',
                                                       p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; f media_versions; s media_versions; gs jsonb; n int; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
        lk jsonb; lv int; fill jsonb;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.package', coalesce(p_front::text, ''), true);
  if not public.ws_can('edit.timeline', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pacote automático precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  if p_front is null or p_side is null or p_front = p_side then
    raise exception 'camaras_invalidas' using errcode = '22023', detail = 'Escolhe duas gravações diferentes: a câmara da frente e a câmara do lado (com o som).'; end if;
  select v.* into f from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_front and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
  select v.* into s from media_versions v join media_assets a on a.id = v.asset_id
   where v.id = p_side and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%' and a.lifecycle = 'ativo';
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
       || case when fill is null then '' else ':ia1' end;
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
                               'guioes', gs, 'style', st)
            -- sem jsonb_strip_nulls: highlight/background null no aspeto querem dizer "sem destaque/sem caixa"
            || case when lk is null then '{}'::jsonb else jsonb_build_object('look', lk, 'style_version', lv) end
            || case when fill is null then '{}'::jsonb else jsonb_build_object('fill', fill) end,
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.package_requested', 'media_job', j.id::text, null,
      jsonb_build_object('front', f.id, 'side', s.id, 'guioes', to_jsonb(p_guioes), 'style', st, 'style_version', lv)
      || case when fill is null then '{}'::jsonb else jsonb_build_object('fill', jsonb_build_object(
           'images', jsonb_array_length(fill->'library'->'images'), 'attention', jsonb_array_length(fill->'library'->'attention'),
           'music', jsonb_array_length(fill->'library'->'music'), 'persona_version', fill->'persona'->'version',
           'preset_version', fill->'preset_version', 'recipes', fill->'recipes')) end);
  end if;
  return public._media_job_json(j);
end $$;

/* Rollback (compatível, por esta ordem; o código do main não chama nada disto):
   1. Repor edit_package_request de 20261106060134_w10_pacote_estilo_alternativas.sql.
   2. drop function if exists public._edit_package_fill(text);
   3. delete from public.feature_flags where key = 'edit.ai_visuals'; delete from public.feature_flag_defs where key = 'edit.ai_visuals';
   Jobs já criados com 'fill' continuam válidos (um worker sem package_visuals ignora a chave). Versões 1 já gravadas com visuais
   ficam: são documentos normais (overlays com "box" e doc.ai.visuals são aceites por _edit_doc_problem e pelo render). */
