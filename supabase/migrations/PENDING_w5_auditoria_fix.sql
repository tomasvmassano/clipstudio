-- W5-16 · auditoria das RPCs de 05/11 (isolamento, código de equipa, pré-visualização, soft delete). PENDENTE: não aplicada em produção.
-- Ao aplicar, renomear para <timestamp>_w5_auditoria_fix.sql. Expand (aditivo e compatível com o main): só substitui corpos de funções
-- (mesma assinatura, mesmas chaves de resposta), junta um trigger que recusa ligar ativos a guiões eliminados e retira EXECUTE a anon.
-- Achados (testes em supabase/tests/w5_auditoria_isolamento.sql):
--  1. Guiões eliminados (W9, deleted_at) voltavam pelo editor/pacote: edit_package_request aceitava o id de um eliminado (copiava hooks
--     e corpo para o job), media_worker_package_save criava ativos e documentos ligados a ele (quebrando a regra "sem media ativa" do
--     content_delete), e edit_doc_get, edit_doc_list, edit_package_list e media_review_detail (_review_item_json) mostravam tema/hooks
--     a quem não tem scripts.purge. media_assets_guard deixava ligar ativos novos a um eliminado. content_bulk devolvia a "fotografia
--     antes" (responsável, campanha, etiquetas, data) de um eliminado.
--  2. _content_deleted(text) é executável por authenticated (precisa, por causa das políticas RLS) e respondia para guiões de qualquer
--     cliente: com ids previsíveis (<cliente>-<data>-<n>) dizia a um membro de A que B tinha eliminado um guião naquele dia.
--  3. Defesa em profundidade: funções que exigem sessão individual tinham EXECUTE para anon (privilégios por omissão do Supabase;
--     as migrações só faziam "revoke ... from public"). Hoje paravam em 42501/28000 dentro da função; agora param antes.
--  4. media_worker_package_save só grava guiões que fazem parte do pedido do pacote (o worker não escolhe guiões fora dele).

-- 3 ─ anon fora das RPCs que só servem a sessões individuais
revoke execute on function public.edit_doc_get(text, uuid, uuid, text), public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text),
  public.edit_saved_styles(text, text), public.edit_style_from_doc(text, uuid, uuid, text, text, int, text),
  public.edit_style_apply(text, uuid, uuid, text, text), public.media_review_list(text, jsonb, text),
  public.media_review_detail(text, uuid, uuid, text), public.media_proxy_access(text, uuid, text),
  public.edit_preview_sources(text, uuid, uuid, text), public.edit_export_request(text, uuid, uuid, text),
  public.edit_export_list(text, uuid, text), public.edit_export_cancel(text, uuid, text),
  public.edit_package_request(text, uuid, uuid, text[], text, text), public.edit_package_list(text, text), public.edit_doc_list(text, text),
  public.edit_package_export(text, uuid, text) from anon;
-- (persona_list_* do W5-14 já nascem com "revoke ... from public, anon")

-- 2 ─ só responde por guiões que quem pergunta pode ler (as políticas já exigem authorize('scripts.read', ...) antes)
create or replace function public._content_deleted(p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from guioes where id = p_id and deleted_at is not null and public._authorize('scripts.read', client_id, auth.uid()))
$$;

-- 1 ─ ativos não se ligam (de novo) a guiões eliminados; ativos já ligados continuam a poder mudar (recuperar do lixo, etc.)
create or replace function public.media_assets_content_live() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.content_id is not null and (tg_op = 'INSERT' or new.content_id is distinct from old.content_id)
     and exists (select 1 from guioes g where g.id = new.content_id and g.deleted_at is not null) then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'Este guião foi eliminado.';
  end if;
  return new;
end $$;
drop trigger if exists media_assets_content_live on public.media_assets;
create trigger media_assets_content_live before insert or update of content_id on public.media_assets
  for each row execute function public.media_assets_content_live();
revoke all on function public.media_assets_content_live() from public, anon, authenticated;

-- 1 ─ corpos iguais aos das migrações de origem, com o filtro deleted_at (e o guião tem de ser do pedido, no worker)
create or replace function public.edit_package_request(p_ws text, p_front uuid, p_side uuid, p_guioes text[], p_style text default 'S15',
                                                       p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; f media_versions; s media_versions; gs jsonb; n int; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
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
  k := 'package:' || f.id || ':' || s.id || ':' || md5(array_to_string(p_guioes, ',')) || ':' || st;
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
                               'guioes', gs, 'style', st),
            uid, public._media_label(uid), 2)
    returning * into j;
    perform public._media_audit(p_ws, 'edit.package_requested', 'media_job', j.id::text, null,
      jsonb_build_object('front', f.id, 'side', s.id, 'guioes', to_jsonb(p_guioes), 'style', st));
  end if;
  return public._media_job_json(j);
end $$;

create or replace function public.edit_package_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  return coalesce((select jsonb_agg(public._media_job_json(j) || jsonb_build_object(
      'front_name', j.input->'front'->>'name', 'side_name', j.input->'side'->>'name',
      'guioes', (select jsonb_agg(jsonb_build_object('id', g->>'id', 'n', (g->>'n')::int, 'tema', case when x.live then g->>'tema' end, 'deleted', not x.live))
                   from jsonb_array_elements(j.input->'guioes') g,
                        lateral (select exists (select 1 from guioes z where z.id = g->>'id' and z.client_id = p_ws and z.deleted_at is null) as live) x),
      'outputs', (select coalesce(jsonb_agg(jsonb_build_object('guiao_id', o.guiao_id, 'hook', o.hook, 'asset_id', o.asset_id, 'title', a.title)
                                           order by o.guiao_id, o.hook), '[]')
                    from media_job_outputs o join media_assets a on a.id = o.asset_id where o.job_id = j.id))
      order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'package' order by created_at desc limit 20) j), '[]');
end $$;

create or replace function public.edit_doc_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  return coalesce((select jsonb_agg(x order by x->>'updated_at' desc) from (
    select jsonb_build_object('asset_id', a.id, 'title', a.title, 'content_id', a.content_id, 'tags', to_jsonb(a.tags),
             'version_no', v.version_no, 'source', v.source, 'updated_at', d.updated_at, 'created_label', v.created_label,
             'has_video', a.current_version_id is not null,
             'confidence', v.doc->'ai'->'confidence', 'flags', v.doc->'ai'->'flags',
             'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema) from guioes g where g.id = a.content_id and g.client_id = p_ws and g.deleted_at is null),
             'export', (select jsonb_build_object('status', j.status, 'progress', j.progress) from media_jobs j
                         where j.asset_id = a.id and j.kind = 'export' order by j.created_at desc limit 1)) x
      from edit_documents d join media_assets a on a.id = d.asset_id join edit_versions v on v.id = d.current_version_id
     where d.workspace_id = p_ws and a.lifecycle = 'ativo'
     order by d.updated_at desc limit 300) t), '[]');
end $$;

create or replace function public.media_worker_package_save(p_worker text, p_job uuid, p_guiao text, p_hook int, p_doc jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j media_jobs; o media_job_outputs; g guioes; a media_assets; d edit_documents; v edit_versions; why text; st text; ttl text;
begin
  select * into j from media_jobs where id = p_job;
  if j.id is null or j.kind <> 'package' or j.status <> 'running' or j.locked_by is distinct from p_worker then
    raise exception 'job_perdido' using errcode = 'PT409'; end if;
  select * into o from media_job_outputs where job_id = j.id and guiao_id = p_guiao and hook = p_hook;
  if o.job_id is not null then return jsonb_build_object('asset_id', o.asset_id, 'repeated', true); end if;
  -- só guiões do pedido e ainda não eliminados (o pacote pode ter sido pedido antes de o guião ser eliminado)
  if not exists (select 1 from jsonb_array_elements(coalesce(j.input->'guioes', '[]')) x where x->>'id' = p_guiao) then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'Este guião não faz parte do pacote.'; end if;
  select * into g from guioes where id = p_guiao and client_id = j.workspace_id and deleted_at is null;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  why := public._edit_doc_problem(p_doc);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  st := coalesce(nullif(p_doc->>'style', ''), j.input->>'style', 'S15');
  ttl := format('g%s_hook%s_%s', lpad(g.n::text, 2, '0'), p_hook, st) || ' · ' || to_char(g.date, 'DD/MM');
  insert into media_assets (workspace_id, kind, title, tags, status, content_id, notes, created_by, created_label)
  values (j.workspace_id, 'video', left(ttl, 160), array['hook_' || p_hook, lower(st), 'pacote'], 'em_trabalho', g.id,
          'Criado pelo pacote de edição automático da sessão (' || coalesce(j.input->'front'->>'name', '?') || ' + ' || coalesce(j.input->'side'->>'name', '?') || ').',
          j.created_by, 'pacote automático')
  returning * into a;
  insert into edit_documents (workspace_id, asset_id, content_id) values (j.workspace_id, a.id, g.id) returning * into d;
  insert into edit_versions (workspace_id, document_id, version_no, doc, source, note, created_by, created_label)
  values (j.workspace_id, d.id, 1, p_doc, 'ai', 'Versão 1 do pacote automático (proposta da IA)', null, 'pacote automático')
  returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  insert into media_job_outputs (job_id, workspace_id, guiao_id, hook, asset_id, edit_version_id) values (j.id, j.workspace_id, g.id, p_hook, a.id, v.id);
  insert into audit_events (actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ('system', 'worker ' || p_worker, j.workspace_id, 'edit.package_doc', 'media_asset', a.id::text,
          jsonb_build_object('job_id', j.id, 'guiao_id', g.id, 'hook', p_hook, 'edit_version_id', v.id), 'media:' || a.id);
  return jsonb_build_object('asset_id', a.id, 'edit_version_id', v.id, 'repeated', false);
end $$;

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

create or replace function public._review_item_json(a public.media_assets) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'asset_id', a.id, 'title', a.title, 'variant', public._review_variant(a.tags), 'style', public._review_style(a.tags),
    'version_id', v.id, 'version', v.version_no, 'drive_file_id', public._drive_file_id(v.external_url), 'url', v.external_url,
    'player', case when v.source = 'link' then 'drive' else 'ficheiro' end,
    'proxy', v.proxy_state = 'pronta' and v.proxy_path is not null,
    'duration', (v.media_info->>'duration')::numeric,
    'qc', public._review_qc(v.media_info),
    'status', public._review_status(v.id),
    'decided_at', (select r.decided_at from media_reviews r where r.version_id = v.id),
    'decided_by', (select r.decided_label from media_reviews r where r.version_id = v.id),
    'open_comments', (select count(*) from media_comments c where c.version_id = v.id and c.parent_id is null and c.resolved_at is null),
    'all_comments', (select count(*) from media_comments c where c.version_id = v.id),
    'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema,
                'hook', case when public._review_variant(a.tags) like 'hook_%'
                             then g.hooks -> (substr(public._review_variant(a.tags), 6)::int - 1) ->> 'text' end)
              from guioes g where g.id = a.content_id and g.client_id = a.workspace_id and g.deleted_at is null))
  from media_versions v where v.id = a.current_version_id
$$;

CREATE OR REPLACE FUNCTION public.content_bulk(p_ws text, p_ids text[], p_action text, p_args jsonb, p_key uuid, p_preview boolean DEFAULT false, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a jsonb := public._content_actor(p_token); cap text; v_ids text[]; cid text; g guioes; n guioes; prev content_bulk_ops;
  args jsonb := coalesce(p_args, '{}'); res jsonb := '[]'; item jsonb; bef jsonb; aft jsonb; tg text[]; mode text; dt date;
  st text; msg text; det text; n_ok int := 0; n_fail int := 0; n_changed int := 0; inserted boolean;
begin
  cap := case p_action when 'owner' then 'scripts.edit' when 'project' then 'scripts.edit' when 'tags' then 'scripts.edit'
                       when 'approve' then 'scripts.approve' when 'reschedule' then 'calendar.schedule' end;
  if cap is null then raise exception 'acao_invalida' using errcode = '22023', detail = 'Ação em lote desconhecida.'; end if;
  perform public._content_require(cap, p_ws, p_token, 'script.bulk.' || p_action, null);
  if not public._flag_on('guioes.bulk', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'As operações em lote ainda não estão ligadas para ti.'; end if;
  v_ids := array(select x from unnest(p_ids) with ordinality u(x, o) where x is not null group by x order by min(o));
  if coalesce(cardinality(v_ids), 0) = 0 or cardinality(v_ids) > 200 then
    raise exception 'selecao_invalida' using errcode = '22023', detail = 'Escolhe entre 1 e 200 guiões.'; end if;

  -- argumentos
  if p_action = 'owner' and not (args ? 'owner_id') then raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Falta o responsável.'; end if;
  if p_action = 'project' and not (args ? 'project_id') then raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Falta a campanha.'; end if;
  if p_action = 'tags' then
    mode := coalesce(args->>'mode', 'add');
    if mode not in ('add', 'remove', 'replace') or jsonb_typeof(args->'tags') is distinct from 'array' then
      raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Etiquetas: modo add, remove ou replace e uma lista.'; end if;
    tg := array(select distinct lower(btrim(x)) from jsonb_array_elements_text(args->'tags') x where btrim(x) <> '');
    if mode <> 'replace' and coalesce(cardinality(tg), 0) = 0 then
      raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'Escreve pelo menos uma etiqueta.'; end if;
  end if;
  if p_action = 'approve' and args ? 'recorded_only' and jsonb_typeof(args->'recorded_only') <> 'boolean' then
    raise exception 'argumentos_invalidos' using errcode = '22023', detail = 'recorded_only tem de ser verdadeiro ou falso.'; end if;
  if p_action = 'reschedule' then
    begin dt := (args->>'date')::date; exception when others then dt := null; end;
    if dt is null then raise exception 'data_obrigatoria' using errcode = '22023', detail = 'Escolhe a nova data.'; end if;
  end if;

  -- idempotência (só para o lote confirmado)
  if not p_preview then
    if p_key is null then raise exception 'chave_obrigatoria' using errcode = '22023', detail = 'Pedido sem chave de idempotência.'; end if;
    insert into content_bulk_ops (id, workspace_id, action, args, ids, actor_user_id, actor_kind, actor_label)
    values (p_key, p_ws, p_action, args, v_ids, (a->>'uid')::uuid, a->>'kind', a->>'label')
    on conflict (id) do nothing;
    get diagnostics inserted = row_count;
    if not inserted then
      select * into prev from content_bulk_ops where id = p_key;
      if prev.workspace_id <> p_ws or prev.action <> p_action or prev.ids <> v_ids or prev.args <> args
         or prev.actor_user_id is distinct from (a->>'uid')::uuid or prev.actor_kind <> a->>'kind' then
        raise exception 'chave_reutilizada' using errcode = '22023', detail = 'Esta confirmação já foi usada para outro pedido. Abre a pré-visualização outra vez.'; end if;
      return jsonb_build_object('replayed', true, 'preview', false, 'key', p_key, 'results', prev.results, 'summary', prev.summary);
    end if;
  end if;

  foreach cid in array v_ids loop
    bef := null; aft := null; item := null;
    begin
      select * into g from guioes where id = cid and client_id = p_ws and deleted_at is null for update;
      if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;   -- mesmo erro se for de outro cliente
      bef := public._bulk_snapshot(g);
      if p_action = 'owner' then
        n := case when g.owner_id is not distinct from nullif(args->>'owner_id', '')::uuid then g
                  else public.content_meta_set(g.id, jsonb_build_object('owner_id', args->'owner_id'), p_token) end;
      elsif p_action = 'project' then
        n := case when g.project_id is not distinct from nullif(args->>'project_id', '')::uuid then g
                  else public.content_meta_set(g.id, jsonb_build_object('project_id', args->'project_id'), p_token) end;
      elsif p_action = 'tags' then
        n := public.content_meta_set(g.id, jsonb_build_object('tags', to_jsonb(case mode
               when 'add' then array(select distinct x from unnest(g.tags || tg) x)
               when 'remove' then array(select x from unnest(g.tags) x where not x = any (tg))
               else tg end)), p_token);
      elsif p_action = 'approve' then
        -- recorded_only (W9-02): só guiões gravados e cujo texto é exatamente a versão gravada (AGENTS §2.6)
        if g.editorial_status <> 'approved' and coalesce((args->>'recorded_only')::boolean, false) then
          perform public._content_check_recorded(g);
        end if;
        n := case when g.editorial_status = 'approved' then g else public.content_transition(g.id, 'approved', null, null, p_token) end;
      else
        n := jsonb_populate_record(null::guioes, public.content_reschedule(g.id, dt, null, p_token));
      end if;
      aft := public._bulk_snapshot(n);
      item := jsonb_build_object('id', cid, 'ok', true, 'changed', bef is distinct from aft, 'before', bef, 'after', aft);
      if p_preview then raise exception 'previa' using errcode = 'PT200'; end if;   -- desfaz este item
    exception
      when sqlstate 'PT200' then null;
      when others then
        get stacked diagnostics st = returned_sqlstate, msg = message_text, det = pg_exception_detail;
        item := jsonb_build_object('id', cid, 'ok', false, 'changed', false, 'before', bef, 'code', st, 'error', msg, 'detail', nullif(det, ''));
    end;
    res := res || jsonb_build_array(item);
    if (item->>'ok')::boolean then n_ok := n_ok + 1; if (item->>'changed')::boolean then n_changed := n_changed + 1; end if;
    else n_fail := n_fail + 1; end if;
  end loop;

  if not p_preview then
    update content_bulk_ops set results = res, summary = jsonb_build_object('total', cardinality(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail)
     where id = p_key;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.bulk', 'content_bulk', p_key::text,
            jsonb_build_object('action', p_action, 'args', args, 'ids', to_jsonb(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail,
                               'failed_ids', (select coalesce(jsonb_agg(x->'id'), '[]') from jsonb_array_elements(res) x where not (x->>'ok')::boolean)));
  end if;
  return jsonb_build_object('replayed', false, 'preview', p_preview, 'key', p_key, 'results', res,
                            'summary', jsonb_build_object('total', cardinality(v_ids), 'ok', n_ok, 'changed', n_changed, 'failed', n_fail));
end $function$;

/* Rollback (compatível, por esta ordem):
   1. drop trigger if exists media_assets_content_live on public.media_assets; drop function if exists public.media_assets_content_live();
   2. Repor _content_deleted de 20261105202033_w9_guioes_eliminar.sql, content_bulk de 20261105202110_w9_aprovar_gravados.sql,
      edit_package_request, edit_package_list, edit_doc_list e media_worker_package_save de 20261105192728_w5_edit_package.sql,
      edit_doc_get de 20261105195826_w5_editor_guided.sql e _review_item_json de 20261105211447_w5_review_stored.sql.
   3. (opcional) voltar a dar EXECUTE a anon nas funções do passo 3 não é preciso: anon não tem nenhuma capacidade que as abra. */
