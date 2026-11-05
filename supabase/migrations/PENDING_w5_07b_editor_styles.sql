-- W5-08 · EDL-13 estilos guardados (CHG-007, ADR-0048). Expand (só aditivo): 1 coluna nula, 1 trigger, funções novas.
-- Reusa o catálogo versionado do VAR-02 (edit_styles / edit_style_versions, ADR-0027): "Guardar como estilo" grava as
-- escolhas do editor (aspeto das legendas e do hook, música e volume, layout) numa versão nova de um estilo do cliente,
-- na coluna look. Aplicar um estilo a outro vídeo cria uma versão nova do documento de edição. Depende de 07a.

alter table public.edit_style_versions add column if not exists look jsonb;

-- Gravar uma versão do estilo pelo catálogo (edit_style_save, que não sabe de look) mantém o aspeto da versão anterior.
create or replace function public.edit_style_versions_carry_look() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.look is null and new.version > 1 then
    select look into new.look from edit_style_versions where workspace_id = new.workspace_id and key = new.key and version = new.version - 1;
  end if;
  return new;
end $$;
drop trigger if exists edit_style_versions_carry_look on public.edit_style_versions;
create trigger edit_style_versions_carry_look before insert on public.edit_style_versions for each row execute function public.edit_style_versions_carry_look();

-- Aspeto guardado: {captions, hook} como no documento (_edit_look_problem), music {label, asset, db} ou null, layout (texto).
create or replace function public._edit_saved_look_problem(l jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare m jsonb;
begin
  if jsonb_typeof(l) is distinct from 'object' then return 'aspeto inválido'; end if;
  if exists (select 1 from jsonb_object_keys(l) k where k not in ('captions', 'hook', 'music', 'layout')) then return 'aspeto com chaves desconhecidas'; end if;
  m := nullif(l->'music', 'null'::jsonb);
  if m is not null and (jsonb_typeof(m) <> 'object' or jsonb_typeof(m->'label') is distinct from 'string' or jsonb_typeof(m->'db') is distinct from 'number'
       or (m->>'db')::numeric not between -40 and 6) then return 'música do estilo inválida'; end if;
  if l ? 'layout' and jsonb_typeof(l->'layout') not in ('string', 'null') then return 'layout inválido'; end if;
  return public._edit_look_problem(jsonb_strip_nulls(jsonb_build_object('captions', l->'captions', 'hook', l->'hook')));
end $$;

-- Estilos com aspeto guardado (para aplicar no editor). Ler: quem abre o editor neste cliente.
create or replace function public.edit_saved_styles(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.styles_read', p_ws, false);
  return jsonb_build_object('can_manage', public.ws_can('styles.manage', p_ws, p_token),
    'styles', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'status', s.status, 'version', s.current_version, 'name', v.name, 'look', v.look,
                          'updated_at', v.created_at, 'updated_label', v.actor_label) order by s.key)
      from edit_styles s join edit_style_versions v on v.workspace_id = s.workspace_id and v.key = s.key and v.version = s.current_version
      where s.workspace_id = p_ws and s.status <> 'arquivado' and v.look is not null), '[]'));
end $$;

-- Guardar como estilo: lê a versão gravada do documento (não o que o browser diz) e grava o aspeto num estilo do cliente.
-- p_key null = estilo novo (chave E01..E99, nome obrigatório); senão versão nova desse estilo (p_expected = versão vista).
create or replace function public.edit_style_from_doc(p_ws text, p_asset uuid, p_version uuid, p_key text, p_name text, p_expected int,
                                                      p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; d edit_documents; ev edit_versions; s edit_styles; sv edit_style_versions; base_sv edit_style_versions;
        k text := nullif(btrim(coalesce(p_key, '')), ''); nm text := nullif(btrim(coalesce(p_name, '')), ''); lk jsonb; why text; nv int; st text;
        before jsonb; spec jsonb;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.style_from_doc', p_asset::text, true);
  if not public.ws_can('styles.manage', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'edit.style_from_doc');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  select x.* into d from edit_documents x join media_assets a on a.id = x.asset_id
   where x.asset_id = p_asset and x.workspace_id = p_ws and a.workspace_id = p_ws and a.lifecycle = 'ativo';
  if d.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into ev from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
  if ev.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  if nm is not null and char_length(nm) > 60 then raise exception 'nome_longo' using errcode = '22023', detail = 'Nome até 60 caracteres.'; end if;
  lk := jsonb_build_object('captions', ev.doc->'look'->'captions', 'hook', ev.doc->'look'->'hook',
                           'music', nullif(ev.doc->'audio'->'music', 'null'::jsonb), 'layout', ev.doc->'style');
  why := public._edit_saved_look_problem(lk);
  if why is not null then raise exception 'estilo_invalido' using errcode = '22023', detail = why; end if;

  if k is null then
    if nm is null then raise exception 'nome_obrigatorio' using errcode = '22023', detail = 'Dá um nome ao estilo.'; end if;
    perform pg_advisory_xact_lock(hashtext('edit_style_key:' || p_ws));
    select 'E' || lpad(n::text, 2, '0') into k from generate_series(1, 99) n
     where not exists (select 1 from edit_styles x where x.workspace_id = p_ws and x.key = 'E' || lpad(n::text, 2, '0')) order by n limit 1;
    if k is null then raise exception 'estilos_a_mais' using errcode = '22023', detail = 'Este cliente já tem 99 estilos guardados.'; end if;
    -- o layout vem do estilo que o vídeo usa, se existir no catálogo deste cliente (senão fica sem camadas, em rascunho)
    select v.* into base_sv from edit_styles x join edit_style_versions v on v.workspace_id = x.workspace_id and v.key = x.key and v.version = x.current_version
     where x.workspace_id = p_ws and x.key = ev.doc->>'style';
    spec := coalesce(base_sv.spec, '{"canvas":{"w":1080,"h":1920},"layers":[]}'::jsonb);
    st := case when coalesce(array_length(public._edit_spec_problems(spec, true), 1), 0) = 0 then 'ativo' else 'rascunho' end;
    insert into edit_styles (workspace_id, key, status) values (p_ws, k, st);
    nv := 1;
    insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, notes, actor_kind, actor_label, look)
    values (p_ws, k, 1, nm, spec, base_sv.transformation, coalesce(base_sv.platforms, '{}'),
            format('Guardado no editor a partir de %s (versão %s do documento).', coalesce((select title from media_assets where id = p_asset), 'um vídeo'), ev.version_no),
            'user', public._media_label(uid), lk);
  else
    select * into s from edit_styles where workspace_id = p_ws and key = k for update;
    if s.key is null then raise exception 'estilo_nao_encontrado' using errcode = 'P0002'; end if;
    if s.status = 'arquivado' then raise exception 'estilo_arquivado' using errcode = '22023', detail = 'Reativa o estilo antes de o editar.'; end if;
    if s.current_version <> coalesce(p_expected, -1) then
      raise exception 'versao_mudou' using errcode = '40001', detail = 'Outra pessoa gravou este estilo entretanto. Recarrega antes de gravar.'; end if;
    select * into sv from edit_style_versions where workspace_id = p_ws and key = k and version = s.current_version;
    nv := s.current_version + 1; before := to_jsonb(sv) - 'workspace_id';
    insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, notes, actor_kind, actor_label, look)
    values (p_ws, k, nv, coalesce(nm, sv.name), sv.spec, sv.transformation, sv.platforms, sv.notes, 'user', public._media_label(uid), lk);
    update edit_styles set current_version = nv, updated_at = now() where workspace_id = p_ws and key = k;
  end if;
  perform public._media_audit(p_ws, 'edit.style_saved', 'edit_style', k, before,
                              (select to_jsonb(x) - 'workspace_id' from edit_style_versions x where workspace_id = p_ws and key = k and version = nv)
                              || jsonb_build_object('from_asset', p_asset, 'from_version_id', ev.id));
  return public.edit_saved_styles(p_ws, p_token);
end $$;

-- Aplicar um estilo guardado a um vídeo: versão nova do documento a partir da atual (p_base_version), com o aspeto e a
-- música do estilo. Também no modo guiado (EDL-10, passo Estilo): o servidor monta o documento a partir do estilo do cliente.
create or replace function public.edit_style_apply(p_ws text, p_asset uuid, p_base_version uuid, p_key text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; d edit_documents; v edit_versions; s edit_styles; sv edit_style_versions; nd jsonb; m jsonb; why text; n int;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.style_apply', p_asset::text, true);
  select * into s from edit_styles where workspace_id = p_ws and key = p_key;
  if s.key is null or s.status = 'arquivado' then raise exception 'estilo_nao_encontrado' using errcode = 'P0002'; end if;
  select * into sv from edit_style_versions where workspace_id = p_ws and key = s.key and version = s.current_version;
  if sv.look is null then raise exception 'estilo_sem_aspeto' using errcode = '22023', detail = 'Este estilo não tem aspeto guardado no editor.'; end if;
  m := nullif(sv.look->'music', 'null'::jsonb);
  if m is not null and not exists (select 1 from media_assets x where x.id::text = m->>'asset' and x.workspace_id = p_ws and x.kind = 'audio' and x.lifecycle = 'ativo') then
    raise exception 'musica_indisponivel' using errcode = '22023', detail = 'A música deste estilo já não está na biblioteca do cliente.'; end if;
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo' for update;
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into d from edit_documents where asset_id = a.id for update;
  if d.id is null or d.current_version_id is distinct from p_base_version then raise exception 'conflito_versao_edicao' using errcode = '40001'; end if;
  select * into v from edit_versions where id = d.current_version_id;
  nd := v.doc || jsonb_build_object('look', jsonb_strip_nulls(jsonb_build_object('captions', sv.look->'captions', 'hook', sv.look->'hook',
                                      'from', jsonb_build_object('key', s.key, 'version', sv.version))));
  nd := jsonb_set(nd, '{audio,music}', coalesce(m, 'null'::jsonb), true);
  if m is null then nd := jsonb_set(nd, '{audio,gains}', '[]', true); end if;
  why := public._edit_doc_problem(nd);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  if nd = v.doc then return public.edit_doc_get(p_ws, p_asset, v.id, p_token); end if;   -- já tem este estilo
  select coalesce(max(version_no), 0) + 1 into n from edit_versions where document_id = d.id;
  insert into edit_versions (workspace_id, document_id, version_no, base_version_id, doc, source, note, created_by, created_label)
  values (p_ws, d.id, n, v.id, nd, 'user', format('estilo %s (%s v%s) aplicado', sv.name, s.key, sv.version), uid, public._media_label(uid)) returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  perform public._media_audit(p_ws, 'edit.style_applied', 'media_asset', a.id::text, jsonb_build_object('version_id', p_base_version),
                              jsonb_build_object('version_id', v.id, 'version_no', n, 'style', s.key, 'style_version', sv.version));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'edit.version_saved', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', n, 'source', 'user', 'style', s.key));
  return public.edit_doc_get(p_ws, p_asset, v.id, p_token);
end $$;

revoke all on function public.edit_style_versions_carry_look(), public._edit_saved_look_problem(jsonb) from public, anon, authenticated;
revoke all on function public.edit_saved_styles(text, text), public.edit_style_from_doc(text, uuid, uuid, text, text, int, text),
  public.edit_style_apply(text, uuid, uuid, text, text) from public;
grant execute on function public.edit_saved_styles(text, text), public.edit_style_from_doc(text, uuid, uuid, text, text, int, text),
  public.edit_style_apply(text, uuid, uuid, text, text) to authenticated;

/* Rollback (compatível; o código do W5-07 não usa nada disto):
   drop function if exists public.edit_style_apply(text, uuid, uuid, text, text), public.edit_style_from_doc(text, uuid, uuid, text, text, int, text),
     public.edit_saved_styles(text, text), public._edit_saved_look_problem(jsonb);
   drop trigger if exists edit_style_versions_carry_look on public.edit_style_versions; drop function if exists public.edit_style_versions_carry_look();
-- contract posterior, se se quiser apagar os aspetos: alter table public.edit_style_versions drop column look; */
