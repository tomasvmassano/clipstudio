-- W5-06 · EDL-07 documento de edição versionado (CHG-007, ADR-0046). Expand (só aditivo): 3 capacidades, 1 flag,
-- 2 tabelas fechadas à API (só por RPC), funções novas. Não muda nenhuma função existente.
-- O documento guarda a edição em tempo da FONTE (a gravação sincronizada): segmentos [in, out] por ordem, legendas e
-- câmaras na mesma escala. O tempo de saída deriva-se dos segmentos, por isso aparar um corte reflui as legendas.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('edit.timeline', 'Edição', 'M', array['ws'], 'ativo', 'Editar vídeos na linha do tempo completa'),
  ('edit.guided', 'Edição', 'M', array['ws'], 'ativo', 'Ajustar vídeos no modo guiado e deixar notas'),
  ('edit.export', 'Edição', 'A', array['ws'], 'ativo', 'Exportar uma versão editada para revisão')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'edit.timeline'), ('ws', 'workspace_admin', 'edit.timeline'), ('ws', 'manager', 'edit.timeline'),
  ('ws', 'workspace_owner', 'edit.guided'), ('ws', 'workspace_admin', 'edit.guided'), ('ws', 'manager', 'edit.guided'),
  ('ws', 'reviewer', 'edit.guided'), ('ws', 'contributor', 'edit.guided'),
  ('ws', 'workspace_owner', 'edit.export'), ('ws', 'workspace_admin', 'edit.export'), ('ws', 'manager', 'edit.export')
on conflict do nothing;
insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('edit.studio', 'Editor de vídeo', 'Edição', 'ws', 'owner',
   'Documento de edição por vídeo com versões, linha do tempo (cortes, legendas, hook, câmaras, visuais, som) e gravação de versões (EDL-07, EDL-09). Pré-visualização com imagem e exportar chegam com o armazenamento (R2) e o worker.')
on conflict do nothing;

create table if not exists public.edit_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  asset_id uuid not null unique references public.media_assets(id),
  content_id text,
  current_version_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.edit_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  document_id uuid not null references public.edit_documents(id),
  version_no int not null check (version_no >= 1),
  base_version_id uuid references public.edit_versions(id),
  doc jsonb not null,
  source text not null check (source in ('import', 'ai', 'user', 'agent')),
  note text check (note is null or char_length(note) <= 500),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  created_at timestamptz not null default now(),
  unique (document_id, version_no)
);
create index if not exists edit_documents_ws on public.edit_documents (workspace_id);
alter table public.edit_documents enable row level security;
alter table public.edit_versions enable row level security;
revoke all on public.edit_documents, public.edit_versions from anon, authenticated;

-- versões não se alteram nem se apagam (AGENTS §2.6)
create or replace function public.edit_versions_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  raise exception 'versao_imutavel' using errcode = '42501', detail = 'As versões de edição não se alteram: grava uma nova.';
end $$;
drop trigger if exists edit_versions_guard on public.edit_versions;
create trigger edit_versions_guard before update or delete on public.edit_versions for each row execute function public.edit_versions_guard();

-- Forma mínima do documento (a app valida o resto; o servidor recusa o que partiria o render ou a UI).
create or replace function public._edit_doc_problem(d jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare s jsonb; prev numeric := -1;
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
  return null;
end $$;

create or replace function public._edit_require(p_ws text, p_token text, p_action text, p_entity text, p_write boolean) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._media_require('media.read', p_ws, p_token, p_action, p_entity);
  if not public._flag_on('edit.studio', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O editor de vídeo ainda não está ligado neste cliente.';
  end if;
  if not (public.ws_can('edit.timeline', p_ws, p_token) or public.ws_can('edit.guided', p_ws, p_token)) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', p_action);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return public._media_uid();
end $$;

create or replace function public._edit_version_json(v edit_versions, p_with_doc boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version_no', v.version_no, 'base_version_id', v.base_version_id, 'source', v.source,
           'note', v.note, 'created_label', v.created_label, 'created_at', v.created_at)
         || case when p_with_doc then jsonb_build_object('doc', v.doc) else '{}'::jsonb end
$$;

-- Abrir: documento do ativo (ou null se ainda não há), a versão pedida (ou a atual) e a lista de versões.
create or replace function public.edit_doc_get(p_ws text, p_asset uuid, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a media_assets; d edit_documents; v edit_versions; mv media_versions;
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_asset::text, false);
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo';
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into mv from media_versions where id = a.current_version_id;
  select * into d from edit_documents where asset_id = a.id;
  if d.id is not null then
    select * into v from edit_versions where id = coalesce(p_version, d.current_version_id) and document_id = d.id;
    if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object(
    'asset', jsonb_build_object('id', a.id, 'title', a.title, 'content_id', a.content_id, 'tags', to_jsonb(a.tags),
               'variant', public._review_variant(a.tags), 'style', public._review_style(a.tags),
               'drive_file_id', public._drive_file_id(mv.external_url), 'media_version_no', mv.version_no),
    'guiao', (select jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema) from guioes g where g.id = a.content_id and g.client_id = p_ws),
    'document', case when d.id is null then null else jsonb_build_object('id', d.id, 'current_version_id', d.current_version_id, 'updated_at', d.updated_at) end,
    'version', case when v.id is null then null else public._edit_version_json(v, true) end,
    'versions', coalesce((select jsonb_agg(public._edit_version_json(x, false) order by x.version_no desc) from edit_versions x where x.document_id = d.id), '[]'),
    'can', jsonb_build_object('timeline', public.ws_can('edit.timeline', p_ws, p_token), 'guided', public.ws_can('edit.guided', p_ws, p_token),
               'export', public.ws_can('edit.export', p_ws, p_token)));
end $$;

-- Gravar: versão nova a partir da atual (base). Se alguém gravou entretanto, recusa (40001) sem perder a do outro.
create or replace function public.edit_doc_save(p_ws text, p_asset uuid, p_base_version uuid, p_doc jsonb, p_note text default null,
                                                p_source text default 'user', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; d edit_documents; v edit_versions; why text; n int; src text := coalesce(p_source, 'user');
begin
  uid := public._edit_require(p_ws, p_token, 'edit.save', p_asset::text, true);
  if src not in ('import', 'ai', 'user', 'agent') then raise exception 'origem_invalida' using errcode = '22023'; end if;
  if src in ('import', 'ai') and not public.ws_can('edit.timeline', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  why := public._edit_doc_problem(p_doc);
  if why is not null then raise exception 'documento_invalido: %', why using errcode = '22023'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'nota_longa' using errcode = '22023'; end if;
  select * into a from media_assets where id = p_asset and workspace_id = p_ws and lifecycle = 'ativo' for update;
  if a.id is null then raise exception 'media_nao_encontrado' using errcode = 'P0002'; end if;
  select * into d from edit_documents where asset_id = a.id for update;
  if d.id is null then
    if p_base_version is not null then raise exception 'conflito_versao_edicao' using errcode = '40001'; end if;
    insert into edit_documents (workspace_id, asset_id, content_id) values (p_ws, a.id, a.content_id) returning * into d;
  elsif d.current_version_id is distinct from p_base_version then
    raise exception 'conflito_versao_edicao' using errcode = '40001';
  end if;
  -- repetir a mesma gravação (rede) não cria outra versão
  select * into v from edit_versions where id = d.current_version_id;
  if v.id is not null and v.doc = p_doc and v.created_by = uid then return public.edit_doc_get(p_ws, p_asset, v.id, p_token); end if;
  select coalesce(max(version_no), 0) + 1 into n from edit_versions where document_id = d.id;
  insert into edit_versions (workspace_id, document_id, version_no, base_version_id, doc, source, note, created_by, created_label)
  values (p_ws, d.id, n, p_base_version, p_doc, src, nullif(btrim(coalesce(p_note, '')), ''), uid, public._media_label(uid)) returning * into v;
  update edit_documents set current_version_id = v.id, updated_at = now() where id = d.id;
  perform public._media_audit(p_ws, 'edit.version_saved', 'media_asset', a.id::text, jsonb_build_object('version_id', p_base_version),
                              jsonb_build_object('version_id', v.id, 'version_no', n, 'source', src));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'edit.version_saved', 'media_asset', a.id::text, jsonb_build_object('version_id', v.id, 'version_no', n, 'source', src));
  return public.edit_doc_get(p_ws, p_asset, v.id, p_token);
end $$;

revoke all on function public.edit_versions_guard(), public._edit_doc_problem(jsonb), public._edit_require(text, text, text, text, boolean),
  public._edit_version_json(public.edit_versions, boolean) from public, anon, authenticated;
revoke all on function public.edit_doc_get(text, uuid, uuid, text), public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text) from public;
grant execute on function public.edit_doc_get(text, uuid, uuid, text), public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text) to authenticated;

/* Rollback (só se nada depender ainda disto):
   drop function if exists public.edit_doc_save(text, uuid, uuid, jsonb, text, text, text), public.edit_doc_get(text, uuid, uuid, text),
     public._edit_version_json(public.edit_versions, boolean), public._edit_require(text, text, text, text, boolean), public._edit_doc_problem(jsonb);
   drop table if exists public.edit_versions, public.edit_documents;
   drop function if exists public.edit_versions_guard();
   delete from feature_flags where key = 'edit.studio'; delete from feature_flag_defs where key = 'edit.studio';
   delete from role_capabilities where capability in ('edit.timeline', 'edit.guided', 'edit.export');
   delete from capabilities where key in ('edit.timeline', 'edit.guided', 'edit.export'); */
