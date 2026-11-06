-- W10-07 · EDL-13 + EDL-10: o pacote automático recebe o aspeto do estilo guardado e o modo guiado usa as alternativas da IA.
-- Expand (aditivo e compatível com o main): substitui os corpos de edit_package_request e edit_doc_get (mesma assinatura;
-- edit_doc_get só ganha a chave ai_alternatives) e junta edit_alternative_apply. Não mexe em tabelas.
--  1. edit_package_request lê o aspeto (look) da versão atual do estilo pedido (edit_styles deste cliente, não arquivado) e junta
--     'look' e 'style_version' ao input do job; sem aspeto o input fica igual ao de hoje (o worker faz o que faz hoje). A música
--     do estilo só entra se continuar a ser um áudio ativo da biblioteca deste cliente (a regra de edit_style_apply); senão vai a
--     null. A versão do estilo entra na chave de idempotência. Sem jsonb_strip_nulls: highlight/background null querem dizer
--     "sem destaque/sem caixa". (numeiro-engine #16: package_style.)
--  2. edit_doc_get devolve ai_alternatives = doc.ai.alternatives da última versão ai/import do documento (a do worker).
--  3. edit_alternative_apply monta no servidor uma versão nova a partir de uma alternativa da IA guardada nesse documento:
--     nunca usa cortes vindos do browser. Permitido a edit.guided e edit.timeline (_edit_require), protegido por p_base_version
--     como edit_doc_save, validado por _edit_doc_problem, auditado e idempotente.

create or replace function public.edit_package_request(p_ws text, p_front uuid, p_side uuid, p_guioes text[], p_style text default 'S15',
                                                       p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; f media_versions; s media_versions; gs jsonb; n int; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
        lk jsonb; lv int;
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
  -- a versão do estilo entra na chave: gravar o estilo de novo e pedir o mesmo pacote cria um job novo com o aspeto novo
  k := 'package:' || f.id || ':' || s.id || ':' || md5(array_to_string(p_guioes, ',')) || ':' || st || coalesce(':v' || lv, '');
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
            || case when lk is null then '{}'::jsonb else jsonb_build_object('look', lk, 'style_version', lv) end,
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.package_requested', 'media_job', j.id::text, null,
      jsonb_build_object('front', f.id, 'side', s.id, 'guioes', to_jsonb(p_guioes), 'style', st, 'style_version', lv));
  end if;
  return public._media_job_json(j);
end $$;

-- 2 ─ edit_doc_get: igual a 20261105215624_w5_auditoria_fix.sql e mais ai_alternatives (alternativas da IA guardadas pelo pacote).
create or replace function public.edit_doc_get(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets; d edit_documents; v edit_versions; mv media_versions; ai edit_versions;
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_asset::text, false);
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo';
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into mv from media_versions where id = a.current_version_id;
  select * into d from edit_documents where asset_id = a.id;
  if d.id is not null then
    select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
    if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
    select * into ai from edit_versions where document_id = d.id and source in ('import', 'ai') order by version_no desc limit 1;
  end if;
  return jsonb_build_object(
    'asset', jsonb_build_object('id', a.id, 'title', a.title, 'content_id', a.content_id, 'tags', to_jsonb(a.tags),
               'variant', public._review_variant(a.tags), 'style', public._review_style(a.tags),
               'drive_file_id', public._drive_file_id(mv.external_url), 'media_version_no', mv.version_no),
    'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
                'hooks', coalesce((select jsonb_agg(h->>'text' order by i) from jsonb_array_elements(case when jsonb_typeof(g.hooks) = 'array' then g.hooks else '[]' end)
                                     with ordinality t(h, i) where nullif(btrim(h->>'text'), '') is not null), '[]'))
                from guioes g where g.id = a.content_id and g.client_id = p_ws and g.deleted_at is null),
    'document', case when d.id is null then null else jsonb_build_object('id', d.id, 'current_version_id', d.current_version_id, 'updated_at', d.updated_at) end,
    'version', case when v.id is null then null else public._edit_version_json(v, true) end,
    'versions', coalesce((select jsonb_agg(public._edit_version_json(x, false) order by x.version_no desc) from edit_versions x where x.document_id = d.id), '[]'),
    'ai_choice', case when ai.id is null then null else jsonb_build_object('version_no', ai.version_no, 'hook', ai.doc->'hook'->>'text',
                   'music', ai.doc->'audio'->'music', 'segments', ai.doc->'segments') end,
    'ai_alternatives', case when ai.id is null or jsonb_typeof(ai.doc->'ai'->'alternatives') is distinct from 'object' then null
                            else ai.doc->'ai'->'alternatives' end,
    'cut_pool', case when v.id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('seg', z.s, 'after', z.prev, 'version_no', z.version_no) order by z.version_no desc, z.ord)
        from (select distinct on (x.s->>'id') x.s, x.prev, x.ord, ev.version_no
                from edit_versions ev,
                     lateral (select e.s, lag(e.s->>'id') over (order by e.ord) as prev, e.ord
                                from jsonb_array_elements(ev.doc->'segments') with ordinality e(s, ord)) x
               where ev.document_id = d.id
                 and not exists (select 1 from jsonb_array_elements(v.doc->'segments') c where c->>'id' = x.s->>'id')
               order by x.s->>'id', ev.version_no desc) z), '[]') end,
    'can', jsonb_build_object('timeline', public.ws_can('edit.timeline', p_ws, p_token), 'guided', public.ws_can('edit.guided', p_ws, p_token),
               'export', public.ws_can('edit.export', p_ws, p_token), 'styles', public.ws_can('styles.manage', p_ws, p_token)));
end $$;

-- 3 ─ Usar uma alternativa da IA (EDL-10, passo Corte do modo guiado). O browser só diz qual (secção + id da opção); o documento
-- novo é montado aqui a partir de doc.ai.alternatives da última versão ai/import deste documento:
--   · cortes: saem os de "replaces" e os de qualquer outra opção desta secção já usada; os da opção entram no lugar do primeiro
--     que saiu (no hook, se já não houver nenhum, entram no início); o resto fica como está, pela mesma ordem;
--   · legendas: saem as palavras que só se ouviam nos cortes que saíram; entram as palavras da opção (sem repetir o mesmo
--     instante); ordenadas pelo tempo da fonte;
--   · tudo o resto (hook, aspeto, câmaras, visuais, som, notas) fica igual.
-- Se a opção já está no documento atual devolve-o sem criar versão (repetir por causa da rede não duplica nem dá conflito).
create or replace function public.edit_alternative_apply(p_ws text, p_asset uuid, p_base_version uuid, p_section text, p_option_id text,
                                                         p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; d edit_documents; v edit_versions; ai edit_versions; sec jsonb; opt jsonb; rep text[];
        pos int; segs jsonb; words jsonb; nd jsonb; why text; n int;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.alternative_apply', p_asset::text, true);
  if p_section is null or p_section not in ('hook', 'body', 'cta') then
    raise exception 'seccao_invalida' using errcode = '22023', detail = 'A secção tem de ser hook, corpo ou CTA.'; end if;
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo' for update;
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into d from edit_documents where asset_id = a.id for update;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = d.current_version_id;
  select * into ai from edit_versions where document_id = d.id and source in ('import', 'ai') order by version_no desc limit 1;
  sec := case when jsonb_typeof(ai.doc->'ai'->'alternatives'->'sections'->p_section) = 'object' then ai.doc->'ai'->'alternatives'->'sections'->p_section end;
  select o into opt from jsonb_array_elements(case when jsonb_typeof(sec->'options') = 'array' then sec->'options' else '[]' end) o
   where jsonb_typeof(o) = 'object' and o->>'id' = p_option_id limit 1;
  if opt is null then
    raise exception 'alternativa_nao_encontrada' using errcode = 'P0002', detail = 'Esta alternativa não existe neste vídeo.'; end if;
  if jsonb_typeof(opt->'segments') <> 'array' or jsonb_array_length(opt->'segments') = 0
     or exists (select 1 from jsonb_array_elements(opt->'segments') s
                 where jsonb_typeof(s) <> 'object' or jsonb_typeof(s->'id') <> 'string' or coalesce(s->>'section', '') not in ('hook', 'body'))
     or jsonb_typeof(coalesce(opt->'words', '[]')) <> 'array'
     or exists (select 1 from jsonb_array_elements(coalesce(opt->'words', '[]')) w where jsonb_typeof(w) <> 'object' or jsonb_typeof(w->'id') <> 'string') then
    raise exception 'documento_invalido: alternativa mal formada' using errcode = '22023'; end if;

  -- já usada: todos os cortes da opção estão, iguais, no documento atual
  if not exists (select 1 from jsonb_array_elements(opt->'segments') s
                  where not exists (select 1 from jsonb_array_elements(v.doc->'segments') c where c = s)) then
    return public.edit_doc_get(p_ws, p_asset, v.id, p_token);
  end if;
  if d.current_version_id is distinct from p_base_version then raise exception 'conflito_versao_edicao' using errcode = '40001'; end if;

  -- o que sai: os cortes que a secção substitui e os de qualquer opção desta secção
  rep := array(select jsonb_array_elements_text(case when jsonb_typeof(sec->'replaces') = 'array' then sec->'replaces' else '[]' end)
               union
               select s->>'id' from jsonb_array_elements(sec->'options') o, jsonb_array_elements(case when jsonb_typeof(o->'segments') = 'array' then o->'segments' else '[]' end) s);
  select min(i) into pos from jsonb_array_elements(v.doc->'segments') with ordinality x(s, i) where s->>'id' = any (rep);
  if pos is null then
    if p_section <> 'hook' then
      raise exception 'alternativa_sem_lugar' using errcode = '22023',
        detail = 'Os cortes que esta alternativa substitui já não estão no vídeo. Repõe-nos ou usa a linha do tempo.'; end if;
    pos := 1;
  end if;
  segs := coalesce((select jsonb_agg(s order by i) from jsonb_array_elements(v.doc->'segments') with ordinality x(s, i)
                     where i < pos and not (s->>'id' = any (rep))), '[]')
       || (opt->'segments')
       || coalesce((select jsonb_agg(s order by i) from jsonb_array_elements(v.doc->'segments') with ordinality x(s, i)
                     where i >= pos and not (s->>'id' = any (rep))), '[]');
  if exists (select 1 from jsonb_array_elements(segs) s group by s->>'id' having count(*) > 1) then
    raise exception 'documento_invalido: cortes repetidos' using errcode = '22023'; end if;

  -- legendas: fora as palavras que só se ouviam nos cortes que saíram; dentro as da opção
  with base as (
    select w, ((w->>'s')::numeric + (w->>'e')::numeric) / 2 as mid
      from jsonb_array_elements(coalesce(v.doc->'captions'->'words', '[]')) w
     where jsonb_typeof(w->'s') = 'number' and jsonb_typeof(w->'e') = 'number'),
  gone as (select (s->>'in')::numeric as a, (s->>'out')::numeric as b from jsonb_array_elements(v.doc->'segments') s where s->>'id' = any (rep)),
  kept as (select (s->>'in')::numeric as a, (s->>'out')::numeric as b from jsonb_array_elements(v.doc->'segments') s where not (s->>'id' = any (rep))),
  stay as (
    select w from base
     where not (exists (select 1 from gone where mid >= gone.a and mid < gone.b) and not exists (select 1 from kept where mid >= kept.a and mid < kept.b))),
  added as (
    select o as w from jsonb_array_elements(coalesce(opt->'words', '[]')) o
     where not exists (select 1 from stay where stay.w->>'id' = o->>'id')
       and not exists (select 1 from stay where jsonb_typeof(o->'s') = 'number' and jsonb_typeof(o->'e') = 'number'
                                            and abs((stay.w->>'s')::numeric - (o->>'s')::numeric) < 0.005
                                            and abs((stay.w->>'e')::numeric - (o->>'e')::numeric) < 0.005)),
  allw as (select w from stay union all select w from added)
  select coalesce(jsonb_agg(w order by (w->>'s')::numeric, w->>'id'), '[]') into words from allw;

  nd := v.doc || jsonb_build_object('segments', segs,
                                    'captions', (case when jsonb_typeof(v.doc->'captions') = 'object' then v.doc->'captions' else '{}' end)
                                                || jsonb_build_object('words', words));
  why := public._edit_doc_problem(nd);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  select coalesce(max(version_no), 0) + 1 into n from edit_versions where document_id = d.id;
  insert into edit_versions (workspace_id, document_id, version_no, base_version_id, doc, source, note, created_by, created_label)
  values (p_ws, d.id, n, v.id, nd, 'user',
          format('alternativa da IA no %s (%s)', case p_section when 'hook' then 'hook' when 'body' then 'corpo' else 'CTA' end, p_option_id),
          uid, public._media_label(uid)) returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  perform public._media_audit(p_ws, 'edit.alternative_applied', 'media_asset', a.id::text, jsonb_build_object('version_id', p_base_version),
                              jsonb_build_object('version_id', v.id, 'version_no', n, 'section', p_section, 'option', p_option_id,
                                                 'ai_version_id', ai.id, 'replaced', to_jsonb(rep)));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'edit.version_saved', 'media_asset', a.id::text,
          jsonb_build_object('version_id', v.id, 'version_no', n, 'source', 'user', 'alternative', p_option_id));
  return public.edit_doc_get(p_ws, p_asset, v.id, p_token);
end $$;

revoke all on function public.edit_alternative_apply(text, uuid, uuid, text, text, text) from public, anon;
grant execute on function public.edit_alternative_apply(text, uuid, uuid, text, text, text) to authenticated;

/* Rollback (compatível, por esta ordem; o código do main não chama nada disto):
   1. drop function if exists public.edit_alternative_apply(text, uuid, uuid, text, text, text);
   2. Repor edit_doc_get e edit_package_request de 20261105215624_w5_auditoria_fix.sql (a UI trata ai_alternatives ausente como
      "sem alternativas"). Jobs já criados com look/style_version continuam válidos: o worker sem essas chaves faz o que fazia.
   3. Versões criadas por edit_alternative_apply ficam: são versões normais do documento (source 'user'). */
