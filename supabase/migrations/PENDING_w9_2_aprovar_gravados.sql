-- W9-02 · Aprovar guiões já gravados que ficaram por aprovar (PRD FR-02-05, FR-17-07; AGENTS §2.6; ADR-0051).
-- Contexto: guiões antigos foram gravados antes de haver aprovação no fluxo novo (status legado 'aprovado', editorial
-- 'in_review'). A equipa precisa de os ver todos (não só os do dia) e aprovar em lote, sabendo que aprova exatamente o texto
-- que foi gravado. Não mexe em dados: é uma ação que a equipa faz na app.
-- Expand (só aditivo): 3 funções novas; content_bulk ganha o argumento opcional `recorded_only` na ação 'approve' (sem ele, o
-- comportamento é o de hoje). Rollback no fim.

-- Versão que estava em vigor quando o guião foi marcado gravado da última vez (content_transitions guarda-a).
create or replace function public._content_recorded_version(p_id text) returns uuid
language sql stable security definer set search_path = public as $$
  select t.version_id from content_transitions t
   where t.content_id = p_id and t.kind = 'production' and t.to_status = 'recorded' and t.from_status is distinct from 'editing'
   order by t.at desc, t.id desc limit 1
$$;

-- A cópia de trabalho é igual a essa versão? (o que se aprova é a cópia de trabalho, fotografada em content_transition)
create or replace function public._content_same_as_version(g guioes, p_version uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from content_versions v where v.id = p_version and v.content_id = g.id
                 and v.hooks = g.hooks and v.corpo = g.corpo and v.cta is not distinct from g.cta
                 and v.formato is not distinct from g.formato and v.tema is not distinct from g.tema)
$$;

-- Recusa (por item do lote) aprovar um guião que não está gravado ou cujo texto mudou depois de gravado.
create or replace function public._content_check_recorded(g guioes) returns void
language plpgsql stable security definer set search_path = public as $$
declare rv uuid;
begin
  if g.production_status not in ('recorded', 'editing', 'ready', 'published') then
    raise exception 'nao_gravado' using errcode = '22023', detail = 'Ainda não está gravado: aprova-o no dia dele.'; end if;
  rv := public._content_recorded_version(g.id);
  if rv is null then
    raise exception 'versao_gravada_desconhecida' using errcode = '22023',
      detail = 'Não há registo da versão que foi gravada: abre o guião e aprova-o à mão.'; end if;
  if not public._content_same_as_version(g, rv) then
    raise exception 'texto_mudou' using errcode = '22023',
      detail = 'O texto mudou depois de gravado: abre o guião, vê o histórico e decide à mão.'; end if;
end $$;

-- Gravados (ou já em edição/prontos/publicados) que não estão aprovados, de todos os dias. Para quem pode aprovar.
create or replace function public.content_pending_approval(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.approve', p_ws, p_token, 'script.pending_approval', null);
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'n', x.n, 'date', x.date, 'tema', x.tema, 'hook', x.hooks->0->>'text',
               'editorial_status', x.editorial_status, 'production_status', x.production_status, 'legacy_status', x.status,
               'lock_version', x.lock_version, 'recorded_at', x.gravado_em,
               'recorded_version_no', (select v.version_no from content_versions v where v.id = x.rv),
               'current_version_no', (select v.version_no from content_versions v where v.id = x.current_version_id),
               'same_as_recorded', x.rv is not null and public._content_same_as_version(x.g, x.rv))
             order by x.date, x.n)
      from (select g.*, g as g, public._content_recorded_version(g.id) rv from guioes g
             where g.client_id = p_ws and g.deleted_at is null
               and g.editorial_status in ('in_review', 'draft', 'changes_requested')
               and g.production_status in ('recorded', 'editing', 'ready', 'published')
             order by g.date, g.n limit 500) x), '[]'),
    'can', jsonb_build_object('submit', public.ws_can('scripts.submit', p_ws, p_token), 'bulk', public._flag_on('guioes.bulk', p_ws, p_token)));
end $$;

revoke all on function public._content_recorded_version(text), public._content_same_as_version(guioes, uuid),
  public._content_check_recorded(guioes) from public, anon, authenticated;
revoke all on function public.content_pending_approval(text, text) from public;
grant execute on function public.content_pending_approval(text, text) to anon, authenticated;

-- content_bulk: corpo igual + validação de recorded_only + verificação por item na ação 'approve'.

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


/* Rollback (compatível, nada a migrar):
   1. Repor content_bulk a partir de 20261030075706_w7_busca_p2.sql (sem recorded_only).
   2. drop function public.content_pending_approval(text, text), public._content_check_recorded(guioes),
        public._content_same_as_version(guioes, uuid), public._content_recorded_version(text);
*/
