-- Parte 2 de 2 de 20261030100100_w7_busca.sql (aplicada em produção como w7_busca_p2).
revoke all on public.content_bulk_ops from anon, authenticated;   -- só pelas RPCs

create or replace function public._bulk_snapshot(g guioes) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('owner_id', g.owner_id, 'owner', (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = g.owner_id),
    'project_id', g.project_id, 'project', (select name from projects where id = g.project_id), 'tags', to_jsonb(g.tags),
    'editorial_status', g.editorial_status, 'date', g.date, 'n', g.n)
$$;

-- p_preview: corre cada item a sério e desfaz no fim (mesmas validações e permissões, nada fica gravado), para mostrar o
-- impacto antes de confirmar. Cada item é independente: o resultado diz, item a item, o que mudou ou porque falhou.
create or replace function public.content_bulk(p_ws text, p_ids text[], p_action text, p_args jsonb, p_key uuid, p_preview boolean default false,
                                              p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
      select * into g from guioes where id = cid and client_id = p_ws for update;
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
end $$;

-- Exportar os guiões escolhidos (CSV montado no browser). Só os do cliente; os outros contam como em falta. Auditado.
create or replace function public.content_bulk_export(p_ws text, p_ids text[], p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); ids text[]; rows jsonb;
begin
  perform public._content_require('scripts.export', p_ws, p_token, 'script.bulk.export', null);
  perform public._content_require('scripts.read', p_ws, p_token, 'script.bulk.export', null);
  if not public._flag_on('guioes.bulk', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'As operações em lote ainda não estão ligadas para ti.'; end if;
  ids := array(select distinct x from unnest(p_ids) x where x is not null);
  if coalesce(cardinality(ids), 0) = 0 or cardinality(ids) > 500 then
    raise exception 'selecao_invalida' using errcode = '22023', detail = 'Escolhe entre 1 e 500 guiões.'; end if;
  rows := (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'date', g.date, 'n', g.n, 'tema', g.tema, 'formato', g.formato,
              'editorial_status', g.editorial_status, 'production_status', g.production_status,
              'campanha', (select name from projects where id = g.project_id),
              'responsavel', (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = g.owner_id),
              'tags', to_jsonb(g.tags), 'platforms', to_jsonb(g.platforms),
              'hooks', (select coalesce(jsonb_agg(h->>'text'), '[]') from jsonb_array_elements(case when jsonb_typeof(g.hooks) = 'array' then g.hooks else '[]'::jsonb end) h),
              'corpo', g.corpo, 'cta', g.cta) order by g.date, g.n), '[]')
           from guioes g where g.client_id = p_ws and g.id = any (ids));
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.exported', 'content_bulk', null,
          jsonb_build_object('format', 'csv', 'count', jsonb_array_length(rows), 'ids', (select jsonb_agg(x->'id') from jsonb_array_elements(rows) x)));
  return jsonb_build_object('rows', rows, 'missing', cardinality(ids) - jsonb_array_length(rows));
end $$;

revoke all on function public._search_fold(text), public._sdoc_guiao(text, text, text, text, jsonb, text[], text), public._sdoc_source(text, text, text, text, text, text[]),
  public._sdoc_reference(text, text, text, text, text, text, text[]), public._sdoc_task(text, text), public._search_all(text, text[]), public._like_escape(text),
  public._search_ws(text, text), public._bulk_snapshot(guioes) from public, anon, authenticated;
revoke all on function public.search_scope(text, text), public.search_global(text, text, integer, text),
  public.content_bulk(text, text[], text, jsonb, uuid, boolean, text), public.content_bulk_export(text, text[], text) from public;
grant execute on function public.search_scope(text, text), public.search_global(text, text, integer, text),
  public.content_bulk(text, text[], text, jsonb, uuid, boolean, text), public.content_bulk_export(text, text[], text) to anon, authenticated;
-- anon só passa com código de equipa válido (_content_actor / _search_ws recusam sem sessão nem código).

/* Rollback (compatível): drop function public.content_bulk_export(text, text[], text), public.content_bulk(text, text[], text, jsonb, uuid, boolean, text),
   public.search_global(text, text, integer, text), public.search_scope(text, text), public._search_ws(text, text), public._bulk_snapshot(guioes),
   public._like_escape(text), public._search_all(text, text[]);
   drop index if exists guioes_search_trgm, ideas_search_trgm, reference_items_search_trgm, tasks_search_trgm;
   drop function public._sdoc_task(text, text), public._sdoc_reference(text, text, text, text, text, text, text[]),
     public._sdoc_source(text, text, text, text, text, text[]), public._sdoc_guiao(text, text, text, text, jsonb, text[], text), public._search_fold(text);
   delete from feature_flags where key in ('busca.global', 'guioes.bulk'); delete from feature_flag_defs where key in ('busca.global', 'guioes.bulk');
-- contract posterior: drop table public.content_bulk_ops; (a extensão pg_trgm pode ficar) */
