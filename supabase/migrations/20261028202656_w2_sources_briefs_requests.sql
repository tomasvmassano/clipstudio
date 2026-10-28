-- W2-03 Fontes, briefs e pedidos do talento (PRD M04 FR-04-01/02/04/06, FR-17-02/03, §20; AGENTS §2.5, §7).
-- Decisão (ADR-0003): `ideas` passa a ser a entidade canónica de fontes (PRD §23, reutilizar), com `kind` para
-- distinguir fonte e pedido do talento. Estados: nova → triagem → selecionada → usada | descartada.
-- O motor continua a ler `status='nova'` e a escrever `usada` (compatível).
-- Rollback: bloco comentado no fim.

-- ───────────── capacidade nova (registo + papéis) ─────────────
insert into public.capabilities (key, module, risk, scopes, status)
values ('requests.create', 'Fontes', 'B', '{ws}', 'ativo') on conflict (key) do nothing;
insert into public.role_capabilities (scope, role, capability)
select 'ws', r, 'requests.create' from unnest(array['workspace_owner','workspace_admin','manager','contributor','reviewer']) r
on conflict do nothing;
update public.capabilities set status = 'ativo'
 where key in ('sources.read','sources.create','sources.triage','scripts.create','scripts.submit','scripts.delete');

-- ───────────── fontes ─────────────
alter table public.ideas
  add column kind text not null default 'source' check (kind in ('source','talent_request')),
  add column url_normalized text,
  add column autor text,
  add column idioma text not null default 'pt',
  add column tags text[] not null default '{}',
  add column resumo text,
  add column notas text,
  add column created_by uuid references auth.users(id) on delete set null,
  add column created_kind text not null default 'engine' check (created_kind in ('engine','user','legacy_code')),
  add column created_label text,
  add column ingested_via text not null default 'engine' check (ingested_via in ('engine','manual','url','talent')),
  add column status_reason text,
  add column status_changed_at timestamptz,
  add column updated_at timestamptz not null default now();

update public.ideas set status = 'nova' where status is null;
alter table public.ideas alter column status set not null;
-- Substitui as constraints antigas (status nova/usada/rejeitada; fonte_tipo livro/reel/noticia/comentario).
-- 'rejeitada' fica aceite por compatibilidade com o motor; a app trata-a como 'descartada'.
alter table public.ideas drop constraint ideas_status_check;
alter table public.ideas add constraint ideas_status_check check (status in ('nova','triagem','selecionada','usada','descartada','rejeitada'));
alter table public.ideas drop constraint ideas_fonte_tipo_check;
alter table public.ideas add constraint ideas_fonte_tipo_check
  check (fonte_tipo is null or fonte_tipo in ('livro','reel','noticia','comentario','artigo','video','podcast','manual','pedido','outro'));

create or replace function public.normalize_url(p text) returns text language sql immutable set search_path = public as $$
  select case when p is null or btrim(p) = '' then null else
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(btrim(p)),
      '^https?://(www\.)?', ''), '[?#].*$', ''), '/+$', ''), '\s', '', 'g') end;
$$;

update public.ideas set url_normalized = public.normalize_url(fonte_url);
-- Verificado antes de aplicar: não havia URLs duplicados depois de normalizar.
create unique index ideas_ws_url_unique on public.ideas (client_id, url_normalized) where url_normalized is not null and kind = 'source';
create index ideas_ws_status on public.ideas (client_id, status, created_at desc);

create or replace function public.ideas_before_write() returns trigger language plpgsql set search_path = public as $$
declare dup bigint;
begin
  new.url_normalized := public.normalize_url(new.fonte_url);
  -- O motor não pode falhar por um URL repetido: fica guardado como descartado, apontando para o original.
  if tg_op = 'INSERT' and new.kind = 'source' and new.url_normalized is not null and new.created_kind = 'engine' then
    select id into dup from ideas where client_id = new.client_id and kind = 'source' and url_normalized = new.url_normalized limit 1;
    if dup is not null then
      new.url_normalized := null; new.status := 'descartada'; new.status_reason := 'duplicado de #' || dup;
    end if;
  end if;
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.client_id is distinct from old.client_id then
    raise exception 'workspace_imutavel' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.status is distinct from old.status then new.status_changed_at := now(); end if;
  return new;
end $$;
create trigger ideas_before_write before insert or update on public.ideas for each row execute function public.ideas_before_write();

-- ───────────── ligação fonte ↔ guião (N:N, mesmo workspace) ─────────────
create table public.content_sources (
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  source_id bigint not null references public.ideas(id) on delete restrict,
  added_by uuid references auth.users(id) on delete set null,
  added_kind text not null check (added_kind in ('user','legacy_code','engine')),
  created_at timestamptz not null default now(),
  primary key (content_id, source_id)
);
create index content_sources_source on public.content_sources (source_id);

create or replace function public.content_sources_same_ws() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select client_id from guioes where id = new.content_id)
     or new.workspace_id is distinct from (select client_id from ideas where id = new.source_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger content_sources_ws before insert on public.content_sources for each row execute function public.content_sources_same_ws();

-- ───────────── briefs (versões append-only) ─────────────
create table public.content_briefs (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  version_no integer not null,
  objetivo text, audiencia text, tese text, formato text, duracao_s integer check (duracao_s is null or duracao_s between 1 and 3600),
  plataformas text[] not null default '{}', cta text, referencias text, restricoes text, dono text, deadline date,
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user','legacy_code','engine','migration')),
  created_label text,
  created_at timestamptz not null default now(),
  unique (content_id, version_no)
);
create trigger content_briefs_immutable before update or delete on public.content_briefs for each row execute function public.content_append_only();
create trigger content_briefs_ws before insert on public.content_briefs for each row execute function public.content_same_workspace();

alter table public.guioes add column brief_id uuid references public.content_briefs(id);
alter table public.content_versions add column brief_id uuid references public.content_briefs(id);

-- A versão fotografa também o brief em vigor (FR-17-03: aprovações referenciam o briefing em vigor).
create or replace function public._content_snapshot(p_id text, p_actor jsonb, p_label text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g guioes; cv content_versions; v_id uuid;
begin
  select * into g from guioes where id = p_id;
  select * into cv from content_versions where id = g.current_version_id;
  if cv.id is not null and cv.hooks = g.hooks and cv.corpo = g.corpo and cv.cta is not distinct from g.cta
     and cv.formato is not distinct from g.formato and cv.tema is not distinct from g.tema and cv.brief_id is not distinct from g.brief_id then
    return cv.id;
  end if;
  insert into content_versions (workspace_id, content_id, version_no, hooks, corpo, cta, formato, tema, brief_id, created_by, created_kind, created_label)
  values (g.client_id, g.id, coalesce((select max(version_no) from content_versions where content_id = g.id), 0) + 1,
          g.hooks, g.corpo, g.cta, g.formato, g.tema, g.brief_id, (p_actor->>'uid')::uuid, p_actor->>'kind', coalesce(p_label, p_actor->>'label'))
  returning id into v_id;
  update guioes set current_version_id = v_id where id = g.id;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'script.version_created', 'content', g.id, jsonb_build_object('version_id', v_id, 'brief_id', g.brief_id));
  return v_id;
end $$;

-- ───────────── acesso ─────────────
alter table public.content_sources enable row level security;
alter table public.content_briefs enable row level security;
revoke all on public.content_sources, public.content_briefs from anon, authenticated;
grant select on public.content_sources, public.content_briefs to authenticated;
create policy content_sources_select on public.content_sources for select to authenticated using (public.authorize('scripts.read', workspace_id));
create policy content_briefs_select on public.content_briefs for select to authenticated using (public.authorize('scripts.read', workspace_id));

create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','analytics.read','agents.read','agents.rehearse']);
$$;

-- ───────────── RPCs: fontes ─────────────
create or replace function public._source_row(s ideas) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) || jsonb_build_object(
    'take', s.data->>'take_numeiro',
    'linked', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'date', g.date, 'n', g.n, 'tema', g.tema, 'editorial_status', g.editorial_status) order by g.date desc), '[]')
               from content_sources cs join guioes g on g.id = cs.content_id where cs.source_id = s.id));
$$;

create or replace function public.sources_list(p_ws text, p_status text default null, p_kind text default null, p_q text default null,
                                               p_limit integer default 200, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('sources.read', p_ws, p_token, 'source.list', null);
  return (select coalesce(jsonb_agg(public._source_row(s) order by s.created_at desc), '[]') from (
    select * from ideas s
     where s.client_id = p_ws
       and (p_status is null or s.status = p_status)
       and (p_kind is null or s.kind = p_kind)
       and (p_q is null or s.titulo ilike '%' || p_q || '%' or s.resumo ilike '%' || p_q || '%' or s.fonte ilike '%' || p_q || '%'
            or s.data->>'take_numeiro' ilike '%' || p_q || '%' or p_q = any (s.tags))
     order by s.created_at desc limit least(greatest(p_limit, 1), 500)) s);
end $$;

-- Adicionar manualmente / por URL (FR-04-01/02). Duplicado por URL normalizado = PT409 com o id existente.
create or replace function public.source_create(p_ws text, p_fields jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s ideas; dup bigint; u text := nullif(btrim(p_fields->>'fonte_url'), '');
begin
  perform public._content_require('sources.create', p_ws, p_token, 'source.create', null);
  if coalesce(btrim(p_fields->>'titulo'), '') = '' then raise exception 'titulo_obrigatorio' using errcode = '22023'; end if;
  if u is not null and u !~* '^https?://[^\s/$.?#].[^\s]*$' then raise exception 'url_invalido' using errcode = '22023'; end if;
  select id into dup from ideas where client_id = p_ws and kind = 'source' and url_normalized = public.normalize_url(u) limit 1;
  if dup is not null then raise exception 'duplicado:%', dup using errcode = 'PT409'; end if;
  insert into ideas (client_id, kind, fonte_tipo, titulo, fonte, fonte_url, categoria, autor, idioma, tags, resumo, notas, expira_em, status,
                     agent, created_by, created_kind, created_label, ingested_via)
  values (p_ws, 'source', coalesce(nullif(p_fields->>'fonte_tipo',''), 'manual'), btrim(p_fields->>'titulo'), nullif(p_fields->>'fonte',''), u,
          nullif(p_fields->>'categoria',''), nullif(p_fields->>'autor',''), coalesce(nullif(p_fields->>'idioma',''), 'pt'),
          coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(coalesce(p_fields->'tags','[]'::jsonb)) x where btrim(x) <> ''), '{}'),
          nullif(p_fields->>'resumo',''), nullif(p_fields->>'notas',''), nullif(p_fields->>'expira_em','')::date, 'nova',
          'manual', (a->>'uid')::uuid, a->>'kind', a->>'label', case when u is null then 'manual' else 'url' end)
  returning * into s;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'source.created', 'source', s.id::text, jsonb_build_object('titulo', s.titulo, 'url', s.fonte_url));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'source.created', 'source', s.id::text, jsonb_build_object('ingested_via', s.ingested_via, 'actor_kind', a->>'kind'));
  return public._source_row(s);
end $$;

-- Pedido do talento por texto (PRD §20, FR-17-02). Entra na mesma caixa, como pedido.
create or replace function public.talent_request_create(p_ws text, p_text text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s ideas; t text := btrim(coalesce(p_text, ''));
begin
  perform public._content_require('requests.create', p_ws, p_token, 'request.create', null);
  if length(t) < 3 then raise exception 'texto_curto' using errcode = '22023'; end if;
  if length(t) > 2000 then raise exception 'texto_longo' using errcode = '22023'; end if;
  insert into ideas (client_id, kind, fonte_tipo, titulo, resumo, status, agent, created_by, created_kind, created_label, ingested_via, urgencia)
  values (p_ws, 'talent_request', 'pedido', left(regexp_replace(t, '\s+', ' ', 'g'), 120), t, 'nova', 'talento',
          (a->>'uid')::uuid, a->>'kind', a->>'label', 'talent', 'semana')
  returning * into s;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'request.created', 'source', s.id::text, jsonb_build_object('texto', t));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'request.created', 'source', s.id::text, jsonb_build_object('actor_kind', a->>'kind'));
  return public._source_row(s);
end $$;

-- Triagem e edição (FR-04-04). Descartar exige motivo.
create or replace function public.source_update(p_id bigint, p_patch jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s ideas; before jsonb; k text; st text := p_patch->>'status'; reason text := nullif(btrim(coalesce(p_patch->>'status_reason','')), '');
begin
  select * into s from ideas where id = p_id for update;
  if s.id is null then raise exception 'fonte_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('sources.triage', s.client_id, p_token, 'source.update', s.id::text);
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('status','status_reason','titulo','resumo','notas','categoria','tags','autor','fonte','expira_em') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
  end loop;
  if st is not null and st not in ('nova','triagem','selecionada','usada','descartada') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if st = 'descartada' and reason is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  if p_patch ? 'titulo' and coalesce(btrim(p_patch->>'titulo'), '') = '' then raise exception 'titulo_obrigatorio' using errcode = '22023'; end if;
  before := jsonb_build_object('status', s.status, 'titulo', s.titulo, 'tags', s.tags);
  update ideas set
    status = coalesce(st, status),
    status_reason = case when st is not null then reason else status_reason end,
    used_at = case when st = 'usada' and used_at is null then now() else used_at end,
    titulo = coalesce(nullif(btrim(p_patch->>'titulo'),''), titulo),
    resumo = case when p_patch ? 'resumo' then nullif(p_patch->>'resumo','') else resumo end,
    notas = case when p_patch ? 'notas' then nullif(p_patch->>'notas','') else notas end,
    categoria = case when p_patch ? 'categoria' then nullif(p_patch->>'categoria','') else categoria end,
    autor = case when p_patch ? 'autor' then nullif(p_patch->>'autor','') else autor end,
    fonte = case when p_patch ? 'fonte' then nullif(p_patch->>'fonte','') else fonte end,
    expira_em = case when p_patch ? 'expira_em' then nullif(p_patch->>'expira_em','')::date else expira_em end,
    tags = case when p_patch ? 'tags' then coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(p_patch->'tags') x where btrim(x) <> ''), '{}') else tags end
  where id = p_id returning * into s;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', s.client_id, case when st is not null then 'source.status' else 'source.update' end,
          'source', s.id::text, before, p_patch);
  if st is not null and st is distinct from before->>'status' then
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (s.client_id, case st when 'selecionada' then 'source.approved' when 'descartada' then 'source.discarded' else 'source.status_changed' end,
            'source', s.id::text, jsonb_build_object('from', before->>'status', 'to', st, 'reason', reason));
  end if;
  return public._source_row(s);
end $$;

-- Ligar / desligar fonte a um guião (FR-04-06, FR-17-04). Mesmo workspace obrigatório.
create or replace function public.content_link_source(p_content text, p_source bigint, p_link boolean default true, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes; s ideas;
begin
  select * into g from guioes where id = p_content;
  select * into s from ideas where id = p_source;
  if g.id is null or s.id is null then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.edit', g.client_id, p_token, 'content.link_source', g.id);
  if s.client_id <> g.client_id then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_link then
    insert into content_sources (workspace_id, content_id, source_id, added_by, added_kind)
    values (g.client_id, g.id, s.id, (a->>'uid')::uuid, a->>'kind') on conflict do nothing;
    if s.status in ('nova','triagem','selecionada') and s.kind = 'source' then update ideas set status = 'usada', used_at = coalesce(used_at, now()) where id = s.id; end if;
  else
    -- Ligações não são histórico de decisão: desligar remove a linha e fica auditado.
    delete from content_sources where content_id = g.id and source_id = s.id;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, case when p_link then 'content.source_linked' else 'content.source_unlinked' end,
          'guiao', g.id, jsonb_build_object('source_id', s.id));
  return public.content_context(g.id, p_token);
end $$;

-- Converter fonte em guião (FR-04-06): cria rascunho com tema e fonte, e liga-os.
create or replace function public.source_to_script(p_source bigint, p_date date default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare s ideas; g guioes;
begin
  select * into s from ideas where id = p_source;
  if s.id is null then raise exception 'fonte_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('sources.read', s.client_id, p_token, 'source.to_script', s.id::text);
  g := public.content_create(s.client_id, jsonb_build_object(
         'date', coalesce(p_date, (now() at time zone 'Asia/Dubai')::date),
         'tema', s.titulo,
         'formato', s.formato_sugerido,
         'hooks', coalesce((select jsonb_agg(jsonb_build_object('text', h, 'mecanismo', '')) from jsonb_array_elements_text(coalesce(s.data->'hooks','[]'::jsonb)) h), '[]'::jsonb),
         'corpo', coalesce(nullif(s.data->>'take_numeiro',''), nullif(s.resumo,''), s.titulo),
         'notas', case when s.kind = 'talent_request' then 'Pedido do talento: ' || coalesce(s.resumo, s.titulo) end,
         'origem', 'fonte:' || s.id), p_token);
  update guioes set fonte = coalesce(s.fonte_url, s.fonte) where id = g.id returning * into g;
  perform public.content_link_source(g.id, s.id, true, p_token);
  select * into g from guioes where id = g.id;
  return g;
end $$;

-- ───────────── RPCs: brief ─────────────
create or replace function public.brief_save(p_content text, p_fields jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes; b content_briefs; k text;
begin
  select * into g from guioes where id = p_content for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.edit', g.client_id, p_token, 'brief.save', g.id);
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('objetivo','audiencia','tese','formato','duracao_s','plataformas','cta','referencias','restricoes','dono','deadline') then
      raise exception 'campo_invalido: %', k using errcode = '22023';
    end if;
  end loop;
  insert into content_briefs (workspace_id, content_id, version_no, objetivo, audiencia, tese, formato, duracao_s, plataformas, cta, referencias,
                              restricoes, dono, deadline, created_by, created_kind, created_label)
  values (g.client_id, g.id, coalesce((select max(version_no) from content_briefs where content_id = g.id), 0) + 1,
          nullif(p_fields->>'objetivo',''), nullif(p_fields->>'audiencia',''), nullif(p_fields->>'tese',''), nullif(p_fields->>'formato',''),
          nullif(p_fields->>'duracao_s','')::integer,
          coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_fields->'plataformas','[]'::jsonb)) x where x <> ''), '{}'),
          nullif(p_fields->>'cta',''), nullif(p_fields->>'referencias',''), nullif(p_fields->>'restricoes',''), nullif(p_fields->>'dono',''),
          nullif(p_fields->>'deadline','')::date, (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into b;
  update guioes set brief_id = b.id, updated_at = now() where id = g.id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'brief.saved', 'guiao', g.id, jsonb_build_object('brief_id', b.id, 'version_no', b.version_no));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'brief.updated', 'content', g.id, jsonb_build_object('brief_id', b.id, 'version_no', b.version_no));
  return public.content_context(g.id, p_token);
end $$;

-- Contexto de um guião: brief em vigor, brief da versão aprovada e fontes ligadas.
create or replace function public.content_context(p_content text, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g guioes;
begin
  select * into g from guioes where id = p_content;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'content.context', g.id);
  return jsonb_build_object(
    'brief', (select to_jsonb(b) from content_briefs b where b.id = g.brief_id),
    'brief_versions', (select count(*) from content_briefs where content_id = g.id),
    'approved_brief_id', (select v.brief_id from content_versions v where v.id = g.approved_version_id),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo, 'kind', s.kind, 'fonte_tipo', s.fonte_tipo,
                       'fonte', s.fonte, 'fonte_url', s.fonte_url, 'status', s.status) order by cs.created_at), '[]')
                from content_sources cs join ideas s on s.id = cs.source_id where cs.content_id = g.id));
end $$;

-- ───────────── permissões das funções ─────────────
revoke all on function public._source_row(ideas), public.ideas_before_write(), public.content_sources_same_ws(),
  public._content_snapshot(text,jsonb,text) from public, anon, authenticated;
revoke all on function public.sources_list(text,text,text,text,integer,text), public.source_create(text,jsonb,text),
  public.talent_request_create(text,text,text), public.source_update(bigint,jsonb,text), public.content_link_source(text,bigint,boolean,text),
  public.source_to_script(bigint,date,text), public.brief_save(text,jsonb,text), public.content_context(text,text) from public;
grant execute on function public.sources_list(text,text,text,text,integer,text), public.source_create(text,jsonb,text),
  public.talent_request_create(text,text,text), public.source_update(bigint,jsonb,text), public.content_link_source(text,bigint,boolean,text),
  public.source_to_script(bigint,date,text), public.brief_save(text,jsonb,text), public.content_context(text,text) to anon, authenticated;
grant execute on function public.normalize_url(text) to anon, authenticated;

/* Rollback:
drop function sources_list, source_create, talent_request_create, source_update, content_link_source, source_to_script, brief_save,
  content_context, _source_row, normalize_url; -- e reaplicar _content_snapshot de 20261028195656_w2_content_core
drop trigger ideas_before_write on ideas; drop function ideas_before_write();
alter table content_versions drop column brief_id; alter table guioes drop column brief_id;
drop table content_briefs, content_sources;
alter table ideas drop constraint ideas_status_check; alter table ideas drop constraint ideas_fonte_tipo_check; -- e repor as antigas
alter table ideas drop column kind, drop column url_normalized, drop column autor, drop column idioma, drop column tags, drop column resumo,
  drop column notas, drop column created_by, drop column created_kind, drop column created_label, drop column ingested_via,
  drop column status_reason, drop column status_changed_at, drop column updated_at;
delete from role_capabilities where capability = 'requests.create'; delete from capabilities where key = 'requests.create';
-- e reaplicar legacy_can de 20261028195656_w2_content_core.
*/
