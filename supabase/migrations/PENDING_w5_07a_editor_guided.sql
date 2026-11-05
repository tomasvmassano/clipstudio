-- W5-07 · EDL-10 modo guiado (CHG-007, ADR-0047). Substitui duas funções existentes com a mesma assinatura e junta uma nova.
-- edit_doc_get: mais chaves na resposta (hooks do guião, escolha da IA, cortes de versões anteriores) — aditivo.
-- edit_doc_save: quem só tem edit.guided passa a gravar apenas as mudanças do modo guiado (diferença validada aqui).
--   É um aperto de regra para revisor e colaborador; hoje ninguém com só edit.guided chega ao editor (flag edit.studio
--   no estágio 'owner' em produção), por isso não parte o código no main. Para quem tem edit.timeline nada muda.
-- O documento ganha também uma chave opcional "look" (aspeto das legendas e do hook, EDL-13), validada aqui.

-- Aspeto (opcional): cores #RRGGBB, tamanhos e posição vertical do centro em px de 1080×1920, dentro do retângulo seguro.
create or replace function public._edit_look_problem(l jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare part text; o jsonb; k text;
begin
  if l is null or jsonb_typeof(l) = 'null' then return null; end if;
  if jsonb_typeof(l) <> 'object' then return 'aspeto inválido'; end if;
  if exists (select 1 from jsonb_object_keys(l) x where x not in ('captions', 'hook', 'from')) then return 'aspeto com chaves desconhecidas'; end if;
  foreach part in array array['captions', 'hook'] loop
    o := l->part;
    if o is null or jsonb_typeof(o) = 'null' then continue; end if;
    if jsonb_typeof(o) <> 'object' then return 'aspeto inválido'; end if;
    for k in select jsonb_object_keys(o) loop
      if k in ('color', 'highlight', 'background') then
        if jsonb_typeof(o->k) <> 'null' and (jsonb_typeof(o->k) <> 'string' or (o->>k) !~ '^#[0-9A-Fa-f]{6}$') then return 'cor inválida no aspeto'; end if;
      elsif k = 'size' then
        if jsonb_typeof(o->k) <> 'number' or (o->>k)::numeric not between 30 and 140 then return 'tamanho do texto entre 30 e 140'; end if;
      elsif k = 'y' then
        if jsonb_typeof(o->k) <> 'number' or (o->>k)::numeric not between 260 and 1550 then return 'texto fora do retângulo seguro (y 260-1550)'; end if;
      elsif k = 'upper' then
        if jsonb_typeof(o->k) <> 'boolean' then return 'aspeto inválido'; end if;
      else return 'aspeto com chaves desconhecidas'; end if;
    end loop;
  end loop;
  if l ? 'from' and jsonb_typeof(l->'from') <> 'null' and (jsonb_typeof(l->'from') <> 'object' or jsonb_typeof(l->'from'->'key') <> 'string'
       or jsonb_typeof(l->'from'->'version') <> 'number') then return 'origem do aspeto inválida'; end if;
  return null;
end $$;

create or replace function public._edit_doc_problem(d jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare s jsonb;
begin
  if jsonb_typeof(d) <> 'object' then return 'o documento não é um objeto'; end if;
  if (d->>'schema') is distinct from '1' then return 'versão do formato desconhecida'; end if;
  if octet_length(d::text) > 1500000 then return 'documento demasiado grande'; end if;
  if jsonb_typeof(d->'segments') <> 'array' or jsonb_array_length(d->'segments') = 0 then return 'sem segmentos'; end if;
  if jsonb_array_length(d->'segments') > 400 then return 'segmentos a mais'; end if;
  for s in select x from jsonb_array_elements(d->'segments') x loop
    if jsonb_typeof(s->'in') <> 'number' or jsonb_typeof(s->'out') <> 'number' then return 'segmento sem entrada ou saída'; end if;
    if (s->>'in')::numeric < 0 or (s->>'out')::numeric - (s->>'in')::numeric < 0.1 then return 'segmento com menos de 0,1 s'; end if;
  end loop;
  if jsonb_typeof(coalesce(d->'captions'->'words', '[]')) <> 'array' or jsonb_array_length(coalesce(d->'captions'->'words', '[]')) > 5000 then
    return 'legendas inválidas'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(d->'captions'->'words', '[]')) w
              where jsonb_typeof(w->'s') <> 'number' or jsonb_typeof(w->'e') <> 'number' or (w->>'e')::numeric < (w->>'s')::numeric
                 or char_length(coalesce(w->>'w', '')) > 60) then return 'palavra de legenda inválida'; end if;
  if char_length(coalesce(d->'hook'->>'text', '')) > 200 then return 'hook demasiado longo'; end if;
  return public._edit_look_problem(d->'look');
end $$;

-- Modo guiado (EDL-10): o que muda entre a versão base b e o documento novo n. null = permitido.
-- Permitido: texto das palavras (tempos ficam), texto do hook, tirar cortes ou repor cortes que já existiram neste documento
-- (sem aparar nem reordenar os que ficam), trocar a música por um áudio ativo da biblioteca do cliente, juntar notas com o
-- autor da sessão e marcar notas como feitas. O resto do documento tem de ficar igual.
create or replace function public._edit_guided_problem(p_ws text, p_doc_id uuid, b jsonb, n jsonb, p_label text) returns text
language plpgsql stable security definer set search_path = public as $$
declare nm jsonb; bm jsonb; free text[] := array['segments', 'captions', 'hook', 'audio', 'notes'];
begin
  if (n - free) is distinct from (b - free) then
    return 'no modo guiado só mudam as legendas, o hook, os cortes, a música e as notas'; end if;
  if (coalesce(n->'hook', '{}') - 'text') is distinct from (coalesce(b->'hook', '{}') - 'text') then return 'no modo guiado só muda o texto do hook'; end if;

  if (coalesce(n->'captions', '{}') - 'words') is distinct from (coalesce(b->'captions', '{}') - 'words')
     or jsonb_array_length(coalesce(n->'captions'->'words', '[]')) <> jsonb_array_length(coalesce(b->'captions'->'words', '[]')) then
    return 'no modo guiado as palavras das legendas corrigem-se, não se tiram nem se juntam'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(n->'captions'->'words', '[]')) with ordinality x(w, i)
               join jsonb_array_elements(coalesce(b->'captions'->'words', '[]')) with ordinality y(w, i) using (i)
              where (x.w - 'w') is distinct from (y.w - 'w') or jsonb_typeof(x.w->'w') is distinct from 'string' or btrim(x.w->>'w') = '') then
    return 'no modo guiado só se corrige o texto das palavras (os tempos ficam)'; end if;

  if (coalesce(n->'audio', '{}') - array['music', 'gains']) is distinct from (coalesce(b->'audio', '{}') - array['music', 'gains']) then
    return 'no modo guiado o som só muda na música'; end if;
  nm := nullif(n->'audio'->'music', 'null'::jsonb); bm := nullif(b->'audio'->'music', 'null'::jsonb);
  if coalesce(n->'audio'->'gains', '[]') is distinct from coalesce(b->'audio'->'gains', '[]')
     and not (nm is null and coalesce(n->'audio'->'gains', '[]') = '[]') then
    return 'no modo guiado o volume por trecho não muda'; end if;
  if nm is distinct from bm and nm is not null then
    if jsonb_typeof(nm) <> 'object' or exists (select 1 from jsonb_object_keys(nm) k where k not in ('label', 'asset', 'db'))
       or jsonb_typeof(nm->'label') is distinct from 'string' or char_length(nm->>'label') > 120
       or jsonb_typeof(nm->'db') is distinct from 'number' or (nm->>'db')::numeric not between -40 and 6
       or jsonb_typeof(nm->'asset') is distinct from 'string' or (nm->>'asset') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or not exists (select 1 from media_assets a where a.id = (nm->>'asset')::uuid and a.workspace_id = p_ws and a.kind = 'audio' and a.lifecycle = 'ativo') then
      return 'no modo guiado a música tem de ser um áudio da biblioteca deste cliente'; end if;
  end if;

  if exists (select 1 from jsonb_array_elements(n->'segments') s where jsonb_typeof(s->'id') is distinct from 'string')
     or exists (select 1 from jsonb_array_elements(n->'segments') s group by s->>'id' having count(*) > 1) then
    return 'cortes repetidos'; end if;
  if exists (select 1 from jsonb_array_elements(n->'segments') s
              where not exists (select 1 from jsonb_array_elements(b->'segments') p where p = s)
                and not exists (select 1 from edit_versions v, jsonb_array_elements(v.doc->'segments') p where v.document_id = p_doc_id and p = s)) then
    return 'no modo guiado só se tiram cortes ou se repõem cortes de versões anteriores (sem aparar nem criar cortes)'; end if;
  if exists (select 1 from (
      select y.bi, lag(y.bi) over (order by x.ni) as prev
        from jsonb_array_elements(n->'segments') with ordinality x(s, ni)
        join jsonb_array_elements(b->'segments') with ordinality y(s, bi) on y.s->>'id' = x.s->>'id') q where q.prev > q.bi) then
    return 'no modo guiado a ordem dos cortes não muda'; end if;

  if jsonb_typeof(coalesce(n->'notes', '[]')) <> 'array' or jsonb_array_length(coalesce(n->'notes', '[]')) > 300 then return 'notas a mais'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(n->'notes', '[]')) x group by x->>'id' having count(*) > 1) then return 'notas repetidas'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(b->'notes', '[]')) o
              where not exists (select 1 from jsonb_array_elements(coalesce(n->'notes', '[]')) x
                                 where x->>'id' = o->>'id' and (x - 'done') = (o - 'done') and jsonb_typeof(x->'done') = 'boolean')) then
    return 'no modo guiado as notas não se apagam nem se reescrevem (só se marcam como feitas)'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(n->'notes', '[]')) x
              where not exists (select 1 from jsonb_array_elements(coalesce(b->'notes', '[]')) o where o->>'id' = x->>'id')
                and ((x - array['id', 's', 'text', 'by', 'done']) <> '{}'::jsonb
                     or jsonb_typeof(x->'id') is distinct from 'string'
                     or case when jsonb_typeof(x->'s') = 'number' then (x->>'s')::numeric < 0 else true end
                     or case when jsonb_typeof(x->'text') = 'string' then char_length(btrim(x->>'text')) not between 1 and 500 else true end
                     or coalesce(x->'done', 'false') <> 'false'::jsonb
                     or (jsonb_typeof(x->'by') = 'string' and x->>'by' is distinct from p_label)
                     or jsonb_typeof(x->'by') not in ('string', 'null'))) then
    return 'nota nova inválida (momento, texto ou autor)'; end if;
  return null;
end $$;

-- Abrir: igual ao W5-06 e mais os hooks do guião, a escolha da IA (a última versão import/ai) e os cortes de versões
-- anteriores que não estão nesta versão (para os repor no modo guiado).
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
                from guioes g where g.id = a.content_id and g.client_id = p_ws),
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

-- Gravar: igual ao W5-06; sem edit.timeline só o modo guiado (_edit_guided_problem) e só como pessoa ('user').
create or replace function public.edit_doc_save(p_ws text, p_asset uuid, p_base_version uuid, p_doc jsonb, p_note text default null,
                                                p_source text default 'user', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; d edit_documents; v edit_versions; why text; n int; src text := coalesce(p_source, 'user');
        full_mode boolean; base_doc jsonb;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.save', p_asset::text, true);
  full_mode := public.ws_can('edit.timeline', p_ws, p_token);
  if src not in ('import', 'ai', 'user', 'agent') then raise exception 'origem_invalida' using errcode = '22023'; end if;
  if src <> 'user' and not full_mode then raise exception 'sem_permissao' using errcode = '42501'; end if;
  why := public._edit_doc_problem(p_doc);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'nota_longa' using errcode = '22023'; end if;
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo' for update;
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into d from edit_documents where asset_id = a.id for update;
  if d.id is null then
    if p_base_version is not null then raise exception 'conflito_versao_edicao' using errcode = '40001'; end if;
    if not full_mode then raise exception 'modo_guiado: o modo guiado ajusta um documento que já existe' using errcode = '42501'; end if;
    insert into edit_documents (workspace_id, asset_id, content_id) values (p_ws, a.id, a.content_id) returning * into d;
  elsif d.current_version_id is distinct from p_base_version then
    raise exception 'conflito_versao_edicao' using errcode = '40001';
  end if;
  -- repetir a mesma gravação (rede) não cria outra versão
  select * into v from edit_versions where id = d.current_version_id;
  if v.id is not null and v.doc = p_doc and v.created_by = uid then return public.edit_doc_get(p_ws, p_asset, v.id, p_token); end if;
  if not full_mode then
    base_doc := v.doc;
    why := public._edit_guided_problem(p_ws, d.id, base_doc, p_doc, public._media_label(uid));
    if why is not null then
      raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'edit.save_guided', 'reason', why);
      raise exception 'modo_guiado: %', why using errcode = '42501';
    end if;
  end if;
  select coalesce(max(version_no), 0) + 1 into n from edit_versions where document_id = d.id;
  insert into edit_versions (workspace_id, document_id, version_no, base_version_id, doc, source, note, created_by, created_label)
  values (p_ws, d.id, n, p_base_version, p_doc, src, nullif(btrim(coalesce(p_note, '')), ''), uid, public._media_label(uid)) returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  perform public._media_audit(p_ws, 'edit.version_saved', 'media_asset', a.id::text, jsonb_build_object('version_id', p_base_version),
                              jsonb_build_object('version_id', v.id, 'version_no', n, 'source', src, 'mode', case when full_mode then 'completo' else 'guiado' end));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'edit.version_saved', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', n, 'source', src));
  return public.edit_doc_get(p_ws, p_asset, v.id, p_token);
end $$;

revoke all on function public._edit_look_problem(jsonb), public._edit_guided_problem(text, uuid, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function public.edit_doc_get(text, uuid, uuid, text), public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text) from public;
grant execute on function public.edit_doc_get(text, uuid, uuid, text), public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text) to authenticated;

/* Rollback: voltar a aplicar as definições de edit_doc_get, edit_doc_save e _edit_doc_problem de
   20261104180102_w5_editor_doc.sql (o código do W5-06 ignora as chaves novas) e depois
   drop function if exists public._edit_guided_problem(text, uuid, jsonb, jsonb, text), public._edit_look_problem(jsonb); */
