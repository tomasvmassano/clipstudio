-- W2-01 Modelo canónico de conteúdo (PRD §4, §7, §23, FR-02-01..06, FR-17-04; AGENTS §2.5, §2.6, §6).
-- Decisão (ADR-0002): `guioes` passa a ser a entidade canónica (content_items) por evolução, sem tabela paralela
-- (PRD §23 "reutilizar tabelas atuais"); o nome muda no W4 com o resto (ADR-0001).
--   guioes                 = conteúdo + cópia de trabalho (o que se edita)
--   content_versions       = fotografias imutáveis (submissão, aprovação, migração, criação)
--   content_transitions    = histórico append-only de estados editorial e de produção
--   domain_events          = outbox transacional (consumidores chegam no W4)
-- As colunas antigas (status, validado, gravado) continuam sincronizadas para hoje_resumo/desempenho e o motor.
-- Rollback: ver bloco no fim deste ficheiro (comentado). Só destrói o que esta migração cria.

-- ───────────── esquema ─────────────
alter table public.guioes
  add column editorial_status text not null default 'in_review'
    check (editorial_status in ('draft','in_review','changes_requested','approved','rejected','archived')),
  add column production_status text not null default 'not_started'
    check (production_status in ('not_started','scheduled','recording','recorded','editing','ready','published','cancelled')),
  add column current_version_id uuid,
  add column approved_version_id uuid,
  add column cta text,
  add column notas text,
  add column archived_from text,
  add column created_at timestamptz not null default now(),
  add column created_by uuid references auth.users(id) on delete set null,
  add column lock_version integer not null default 0;

alter table public.clients add column require_approval_to_record boolean not null default false;

create table public.content_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  version_no integer not null,
  hooks jsonb not null default '[]'::jsonb,
  corpo text not null,
  cta text,
  formato text,
  tema text,
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user','legacy_code','engine','migration')),
  created_label text,
  created_at timestamptz not null default now(),
  unique (content_id, version_no)
);
create index content_versions_ws_created on public.content_versions (workspace_id, created_at);

create table public.content_transitions (
  id bigserial primary key,
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  version_id uuid references public.content_versions(id),
  kind text not null check (kind in ('editorial','production')),
  from_status text,
  to_status text not null,
  reason text,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('user','legacy_code','engine','migration')),
  actor_label text,
  correlation_id uuid not null default gen_random_uuid(),
  at timestamptz not null default now()
);
create index content_transitions_content on public.content_transitions (content_id, at);
create index content_transitions_ws_at on public.content_transitions (workspace_id, at);

create table public.domain_events (
  id bigserial primary key,
  workspace_id text not null references public.clients(id),
  type text not null,
  entity_type text not null,
  entity_id text not null,
  payload jsonb not null default '{}'::jsonb,
  correlation_id uuid,
  created_at timestamptz not null default now(),
  published_at timestamptz
);
create index domain_events_unpublished on public.domain_events (created_at) where published_at is null;

alter table public.guioes add constraint guioes_current_version_fk foreign key (current_version_id) references public.content_versions(id);
alter table public.guioes add constraint guioes_approved_version_fk foreign key (approved_version_id) references public.content_versions(id);
create index guioes_ws_editorial on public.guioes (client_id, editorial_status);
create index guioes_ws_created on public.guioes (client_id, created_at);

-- Imutabilidade (AGENTS §2.6) e pertença ao mesmo workspace (PRD §7).
create or replace function public.content_append_only() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% é append-only', tg_table_name using errcode = '42501'; end $$;
create trigger content_versions_immutable before update or delete on public.content_versions for each row execute function public.content_append_only();
create trigger content_transitions_immutable before update or delete on public.content_transitions for each row execute function public.content_append_only();

create or replace function public.content_same_workspace() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select client_id from guioes where id = new.content_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger content_versions_ws before insert on public.content_versions for each row execute function public.content_same_workspace();
create trigger content_transitions_ws before insert on public.content_transitions for each row execute function public.content_same_workspace();

-- workspace_id não muda depois de criado (PRD §7).
create or replace function public.guioes_ws_locked() returns trigger language plpgsql set search_path = public as $$
begin
  if new.client_id is distinct from old.client_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  return new;
end $$;
create trigger guioes_ws_locked before update on public.guioes for each row execute function public.guioes_ws_locked();

-- Acesso: leitura por RLS + authorize; escrita só por RPC.
alter table public.content_versions enable row level security;
alter table public.content_transitions enable row level security;
alter table public.domain_events enable row level security;
revoke all on public.content_versions, public.content_transitions, public.domain_events from anon, authenticated;
grant select on public.content_versions, public.content_transitions to authenticated;
create policy content_versions_select on public.content_versions for select to authenticated using (public.authorize('scripts.read', workspace_id));
create policy content_transitions_select on public.content_transitions for select to authenticated using (public.authorize('scripts.read', workspace_id));
revoke all on sequence public.content_transitions_id_seq, public.domain_events_id_seq from anon, authenticated;

-- ───────────── backfill dos guiões existentes ─────────────
do $$
declare g record; h jsonb; v_no int; v_id uuid;
begin
  for g in select * from guioes order by date, n loop
    v_no := 0;
    for h in select x from jsonb_array_elements(coalesce(g.history, '[]'::jsonb)) x order by (x->>'at') nulls first loop
      v_no := v_no + 1;
      insert into content_versions (workspace_id, content_id, version_no, hooks, corpo, formato, tema, created_kind, created_label, created_at)
      values (g.client_id, g.id, v_no, coalesce(h->'hooks','[]'::jsonb), coalesce(h->>'corpo',''), g.formato, g.tema, 'migration',
              'histórico anterior', coalesce((h->>'at')::timestamptz, g.updated_at, now()));
    end loop;
    v_no := v_no + 1;
    insert into content_versions (workspace_id, content_id, version_no, hooks, corpo, formato, tema, created_kind, created_label, created_at)
    values (g.client_id, g.id, v_no, g.hooks, g.corpo, g.formato, g.tema, 'migration', 'versão em vigor na migração', coalesce(g.updated_at, now()))
    returning id into v_id;

    update guioes set
      current_version_id = v_id,
      approved_version_id = case when g.validado and g.status <> 'rejeitado' then v_id end,
      editorial_status = case when g.status = 'rejeitado' then 'rejected' when g.validado then 'approved' else 'in_review' end,
      production_status = case when g.gravado then 'recorded' else 'not_started' end,
      created_at = coalesce(g.updated_at, now())
    where id = g.id;

    insert into content_transitions (workspace_id, content_id, version_id, kind, from_status, to_status, reason, actor_kind, actor_label, at)
    values (g.client_id, g.id, v_id, 'editorial', null,
            case when g.status = 'rejeitado' then 'rejected' when g.validado then 'approved' else 'in_review' end,
            coalesce(g.motivo_rejeicao, 'estado importado na migração W2'), 'migration', 'migração W2', now());
    if g.gravado then
      insert into content_transitions (workspace_id, content_id, version_id, kind, from_status, to_status, reason, actor_kind, actor_label, at)
      values (g.client_id, g.id, v_id, 'production', null, 'recorded', 'estado importado na migração W2', 'migration', 'migração W2', coalesce(g.gravado_em, now()));
    end if;
  end loop;
end $$;

-- ───────────── novos guiões vindos de fora das RPCs (motor, scripts) ─────────────
create or replace function public.guioes_before_insert() returns trigger language plpgsql set search_path = public as $$
begin
  if current_setting('clipstudio.via_rpc', true) is distinct from 'on' then
    new.editorial_status := case when new.status = 'rejeitado' then 'rejected' when new.validado then 'approved' else 'in_review' end;
    new.production_status := case when new.gravado then 'recorded' else 'not_started' end;
  end if;
  return new;
end $$;
create trigger guioes_before_insert before insert on public.guioes for each row execute function public.guioes_before_insert();

create or replace function public.guioes_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_kind text := coalesce(nullif(current_setting('clipstudio.actor_kind', true), ''), 'engine');
        v_label text := nullif(current_setting('clipstudio.actor_label', true), '');
        v_uid uuid := auth.uid();
begin
  insert into content_versions (workspace_id, content_id, version_no, hooks, corpo, cta, formato, tema, created_by, created_kind, created_label)
  values (new.client_id, new.id, 1, new.hooks, new.corpo, new.cta, new.formato, new.tema, v_uid, v_kind, coalesce(v_label, 'motor'))
  returning id into v_id;
  update guioes set current_version_id = v_id,
                    approved_version_id = case when new.editorial_status = 'approved' then v_id end
   where id = new.id;
  insert into content_transitions (workspace_id, content_id, version_id, kind, from_status, to_status, reason, actor_user_id, actor_kind, actor_label)
  values (new.client_id, new.id, v_id, 'editorial', null, new.editorial_status, 'criado', v_uid, v_kind, coalesce(v_label, 'motor'));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (new.client_id, 'script.created', 'content', new.id, jsonb_build_object('version_id', v_id, 'editorial_status', new.editorial_status, 'actor_kind', v_kind));
  return new;
end $$;
create trigger guioes_after_insert after insert on public.guioes for each row execute function public.guioes_after_insert();

-- ───────────── helpers internos (não expostos à API) ─────────────
create or replace function public._content_actor(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is not null then
    return jsonb_build_object('kind','user','uid',uid,'label',(select email from auth.users where id = uid));
  elsif public.legacy_ws(p_token) is not null then
    return jsonb_build_object('kind','legacy_code','uid',null,'label',(select label from studio_tokens where token = p_token));
  end if;
  raise exception 'nao_autenticado' using errcode = '28000';
end $$;

create or replace function public._content_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ws_can(p_cap, p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', p_action, 'entity_id', p_entity, 'capability', p_cap);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
end $$;

-- Fotografa a cópia de trabalho se for diferente da versão atual. Devolve o id da versão em vigor.
create or replace function public._content_snapshot(p_id text, p_actor jsonb, p_label text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g guioes; cv content_versions; v_id uuid;
begin
  select * into g from guioes where id = p_id;
  select * into cv from content_versions where id = g.current_version_id;
  if cv.id is not null and cv.hooks = g.hooks and cv.corpo = g.corpo and cv.cta is not distinct from g.cta
     and cv.formato is not distinct from g.formato and cv.tema is not distinct from g.tema then
    return cv.id;
  end if;
  insert into content_versions (workspace_id, content_id, version_no, hooks, corpo, cta, formato, tema, created_by, created_kind, created_label)
  values (g.client_id, g.id, coalesce((select max(version_no) from content_versions where content_id = g.id), 0) + 1,
          g.hooks, g.corpo, g.cta, g.formato, g.tema, (p_actor->>'uid')::uuid, p_actor->>'kind', coalesce(p_label, p_actor->>'label'))
  returning id into v_id;
  update guioes set current_version_id = v_id where id = g.id;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'script.version_created', 'content', g.id, jsonb_build_object('version_id', v_id));
  return v_id;
end $$;

create or replace function public._content_log(p_g guioes, p_kind text, p_from text, p_to text, p_version uuid, p_reason text,
                                               p_actor jsonb, p_event text, p_corr uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into content_transitions (workspace_id, content_id, version_id, kind, from_status, to_status, reason, actor_user_id, actor_kind, actor_label, correlation_id)
  values (p_g.client_id, p_g.id, p_version, p_kind, p_from, p_to, p_reason, (p_actor->>'uid')::uuid, p_actor->>'kind', p_actor->>'label', p_corr);
  if p_event is not null then
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload, correlation_id)
    values (p_g.client_id, p_event, 'content', p_g.id,
            jsonb_build_object('version_id', p_version, 'from', p_from, 'to', p_to, 'reason', p_reason, 'actor_kind', p_actor->>'kind'), p_corr);
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((p_actor->>'uid')::uuid, p_actor->>'kind', p_actor->>'label', p_g.client_id, coalesce(p_event, p_kind || '.transition'), 'guiao', p_g.id,
          jsonb_build_object(p_kind || '_status', p_from), jsonb_build_object(p_kind || '_status', p_to, 'version_id', p_version, 'reason', p_reason), p_corr::text);
end $$;

-- ───────────── RPCs ─────────────

-- Editar a cópia de trabalho (autosave). p_lock: lock_version que o cliente viu; diferente = conflito (FR-02-06).
create or replace function public.content_save(p_id text, p_patch jsonb, p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); before jsonb; corr uuid := gen_random_uuid(); k text; fr text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.edit', g.client_id, p_token, 'script.update', g.id);
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  if p_lock is not null and p_lock <> g.lock_version then raise exception 'conflito_edicao' using errcode = '40001'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('hooks','corpo','cta','notas','tema','formato') then raise exception 'campo_invalido: %', k using errcode = '22023'; end if;
  end loop;
  if p_patch ? 'hooks' and jsonb_typeof(p_patch->'hooks') <> 'array' then raise exception 'hooks_invalidos' using errcode = '22023'; end if;
  if p_patch ? 'corpo' and coalesce(p_patch->>'corpo','') = '' then raise exception 'corpo_vazio' using errcode = '22023'; end if;

  fr := g.editorial_status;
  before := jsonb_build_object('hooks', g.hooks, 'corpo', g.corpo, 'cta', g.cta, 'notas', g.notas, 'tema', g.tema, 'formato', g.formato);
  update guioes set
    hooks = coalesce(p_patch->'hooks', hooks),
    corpo = coalesce(p_patch->>'corpo', corpo),
    cta = case when p_patch ? 'cta' then nullif(p_patch->>'cta','') else cta end,
    notas = case when p_patch ? 'notas' then nullif(p_patch->>'notas','') else notas end,
    tema = coalesce(p_patch->>'tema', tema),
    formato = coalesce(p_patch->>'formato', formato),
    lock_version = lock_version + 1,
    updated_at = now()
  where id = p_id returning * into g;

  -- Editar uma versão aprovada (ou rejeitada) abre uma revisão nova: a aprovação fica na versão antiga (R-06).
  if g.editorial_status in ('approved','rejected') and (p_patch ?| array['hooks','corpo','cta','tema','formato']) then
    update guioes set editorial_status = 'draft', status = 'aprovado', validado = false, validado_em = null, motivo_rejeicao = null
     where id = p_id returning * into g;
    perform public._content_log(g, 'editorial', fr, 'draft', g.current_version_id, 'conteúdo editado', a, 'script.reopened', corr);
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'script.update', 'guiao', g.id, before, p_patch, corr::text);
  return g;
end $$;

-- Transições editoriais (PRD §4, docs/workflow-registry.md).
create or replace function public.content_transition(p_id text, p_to text, p_reason text default null, p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); v uuid; corr uuid := gen_random_uuid(); fr text; ev text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if p_lock is not null and p_lock <> g.lock_version then raise exception 'conflito_edicao' using errcode = '40001'; end if;
  fr := g.editorial_status;
  p_reason := nullif(btrim(coalesce(p_reason, '')), '');

  if p_to = 'in_review' then
    if fr in ('draft','changes_requested') then perform public._content_require('scripts.submit', g.client_id, p_token, 'script.submit', g.id); ev := 'script.submitted';
    elsif fr = 'rejected' then perform public._content_require('scripts.approve', g.client_id, p_token, 'script.reopen', g.id); ev := 'script.reopened';
    elsif fr = 'approved' then perform public._content_require('scripts.approve', g.client_id, p_token, 'script.unapprove', g.id); ev := 'script.unapproved';
    else raise exception 'transicao_invalida' using errcode = '22023'; end if;
  elsif p_to = 'approved' then
    if fr not in ('in_review','draft','changes_requested') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    perform public._content_require('scripts.approve', g.client_id, p_token, 'script.approve', g.id);
    if fr <> 'in_review' then perform public._content_require('scripts.submit', g.client_id, p_token, 'script.submit', g.id); end if;
    ev := 'script.approved';
  elsif p_to = 'changes_requested' then
    if fr <> 'in_review' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    perform public._content_require('scripts.reject', g.client_id, p_token, 'script.request_changes', g.id);
    if p_reason is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
    ev := 'review.changes_requested';
  elsif p_to = 'rejected' then
    if fr not in ('in_review','draft','changes_requested') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    perform public._content_require('scripts.reject', g.client_id, p_token, 'script.reject', g.id);
    if p_reason is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
    ev := 'script.rejected';
  elsif p_to = 'archived' then
    if fr = 'archived' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    perform public._content_require('scripts.delete', g.client_id, p_token, 'script.archive', g.id);
    ev := 'script.archived';
  elsif p_to = 'restore' then
    if fr <> 'archived' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    perform public._content_require('scripts.delete', g.client_id, p_token, 'script.restore', g.id);
    p_to := coalesce(g.archived_from, 'draft'); ev := 'script.restored';
  else
    raise exception 'estado_invalido' using errcode = '22023';
  end if;

  -- A decisão fica presa à versão exata que foi vista (AGENTS §2.6).
  v := public._content_snapshot(g.id, a, null);
  if fr in ('draft','changes_requested') and p_to = 'approved' then
    perform public._content_log(g, 'editorial', fr, 'in_review', v, null, a, 'script.submitted', corr);
    fr := 'in_review';
  end if;

  update guioes set
    editorial_status = p_to,
    approved_version_id = case when p_to = 'approved' then v when p_to = 'in_review' and fr = 'approved' then null else approved_version_id end,
    archived_from = case when p_to = 'archived' then fr when ev = 'script.restored' then null else archived_from end,
    status = case when p_to = 'rejected' then 'rejeitado' when p_to in ('in_review','approved','draft','changes_requested') then 'aprovado' else status end,
    motivo_rejeicao = case when p_to in ('rejected','changes_requested') then p_reason when p_to in ('approved','in_review') then null else motivo_rejeicao end,
    validado = (p_to = 'approved'),
    validado_em = case when p_to = 'approved' then now() else null end,
    lock_version = lock_version + 1,
    updated_at = now()
  where id = p_id returning * into g;

  perform public._content_log(g, 'editorial', fr, p_to, v, p_reason, a, ev, corr);
  return g;
end $$;

-- Produção: nesta fase só gravado / por gravar (resto no W3). Confirmação explícita (AGENTS §6).
create or replace function public.content_production(p_id text, p_to text, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); fr text; corr uuid := gen_random_uuid(); req boolean;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('recording.confirm', g.client_id, p_token, 'recording.confirm', g.id);
  if p_to not in ('recorded','not_started') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if p_to = 'recorded' then
    if g.editorial_status in ('rejected','archived') then raise exception 'nao_elegivel' using errcode = '22023'; end if;
    select require_approval_to_record into req from clients where id = g.client_id;
    if req and g.editorial_status <> 'approved' then raise exception 'aprovacao_necessaria' using errcode = '22023'; end if;
  end if;
  fr := g.production_status;
  if fr = p_to then return g; end if; -- idempotente
  update guioes set production_status = p_to, gravado = (p_to = 'recorded'),
                    gravado_em = case when p_to = 'recorded' then now() else null end, updated_at = now()
   where id = p_id returning * into g;
  perform public._content_log(g, 'production', fr, p_to, g.current_version_id, null, a,
                              case when p_to = 'recorded' then 'recording.confirmed' else 'recording.undone' end, corr);
  return g;
end $$;

-- Criar e duplicar (FR-02-01). Entram como rascunho.
create or replace function public.content_create(p_ws text, p_fields jsonb, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); d date := coalesce((p_fields->>'date')::date, (now() at time zone 'Asia/Dubai')::date);
        v_n int; v_id text;
begin
  perform public._content_require('scripts.create', p_ws, p_token, 'script.create', null);
  if coalesce(p_fields->>'corpo','') = '' then raise exception 'corpo_vazio' using errcode = '22023'; end if;
  select coalesce(max(n), 0) + 1 into v_n from guioes where client_id = p_ws and date = d;
  v_id := p_ws || '-' || to_char(d, 'YYYY-MM-DD') || '-' || lpad(v_n::text, 2, '0');
  while exists (select 1 from guioes where id = v_id) loop v_n := v_n + 1; v_id := p_ws || '-' || to_char(d, 'YYYY-MM-DD') || '-' || lpad(v_n::text, 2, '0'); end loop;
  perform set_config('clipstudio.via_rpc', 'on', true);
  perform set_config('clipstudio.actor_kind', a->>'kind', true);
  perform set_config('clipstudio.actor_label', coalesce(a->>'label', ''), true);
  insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, cta, notas, origem, editorial_status, created_by)
  values (v_id, p_ws, d, v_n, p_fields->>'formato', p_fields->>'tema', coalesce(p_fields->'hooks', '[]'::jsonb), p_fields->>'corpo',
          nullif(p_fields->>'cta',''), nullif(p_fields->>'notas',''), coalesce(p_fields->>'origem', 'manual'), 'draft', (a->>'uid')::uuid)
  returning * into g;
  perform set_config('clipstudio.via_rpc', 'off', true);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'script.created', 'guiao', g.id, jsonb_build_object('date', d, 'n', v_n));
  select * into g from guioes where id = g.id;
  return g;
end $$;

create or replace function public.content_duplicate(p_id text, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'script.duplicate', g.id);
  return public.content_create(g.client_id, jsonb_build_object('date', g.date, 'formato', g.formato, 'tema', g.tema, 'hooks', g.hooks,
                                                             'corpo', g.corpo, 'cta', g.cta, 'notas', g.notas, 'origem', 'duplicado:' || g.id), p_token);
end $$;

-- Histórico: versões + transições (FR-02-06).
create or replace function public.content_history(p_id text, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g guioes;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'script.history', g.id);
  return jsonb_build_object(
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'hooks', v.hooks, 'corpo', v.corpo, 'cta', v.cta,
                    'created_at', v.created_at, 'created_kind', v.created_kind, 'author', coalesce(v.created_label, u.email),
                    'is_current', v.id = g.current_version_id, 'is_approved', v.id = g.approved_version_id) order by v.version_no desc), '[]')
                 from content_versions v left join auth.users u on u.id = v.created_by where v.content_id = g.id),
    'transitions', (select coalesce(jsonb_agg(jsonb_build_object('kind', t.kind, 'from', t.from_status, 'to', t.to_status, 'reason', t.reason,
                    'at', t.at, 'actor', coalesce(t.actor_label, t.actor_kind),
                    'version_no', (select version_no from content_versions where id = t.version_id)) order by t.at desc, t.id desc), '[]')
                 from content_transitions t where t.content_id = g.id));
end $$;

-- Restaurar uma versão antiga para a cópia de trabalho (cria revisão nova, nunca apaga).
create or replace function public.content_restore_version(p_id text, p_version uuid, p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare v content_versions;
begin
  select * into v from content_versions where id = p_version and content_id = p_id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  return public.content_save(p_id, jsonb_build_object('hooks', v.hooks, 'corpo', v.corpo, 'cta', coalesce(v.cta, ''),
                                                      'formato', v.formato, 'tema', v.tema), p_lock, p_token);
end $$;

-- Compatibilidade: a API antiga passa a usar o modelo novo (sem caminho paralelo de escrita).
create or replace function public.guiao_update(p_id text, p_patch jsonb, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; content jsonb;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if not (p_patch ?| array['hooks','corpo','formato','tema','status','validado','gravado']) then raise exception 'nada_a_alterar' using errcode = '22023'; end if;
  content := (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(p_patch) where key in ('hooks','corpo','formato','tema'));
  if p_patch ? 'n' then raise exception 'campo_invalido: n' using errcode = '22023'; end if;
  if content <> '{}'::jsonb then g := public.content_save(p_id, content, null, p_token); end if;
  if p_patch->>'status' = 'rejeitado' then g := public.content_transition(p_id, 'rejected', coalesce(p_patch->>'motivo_rejeicao', 'sem motivo'), null, p_token);
  elsif p_patch->>'status' = 'aprovado' and g.editorial_status = 'rejected' then g := public.content_transition(p_id, 'in_review', null, null, p_token);
  elsif p_patch ? 'status' and p_patch->>'status' not in ('aprovado','rejeitado') then raise exception 'estado_invalido' using errcode = '22023';
  end if;
  if p_patch ? 'validado' then
    if (p_patch->>'validado')::boolean and g.editorial_status <> 'approved' then g := public.content_transition(p_id, 'approved', null, null, p_token);
    elsif not (p_patch->>'validado')::boolean and g.editorial_status = 'approved' then g := public.content_transition(p_id, 'in_review', null, null, p_token);
    end if;
  end if;
  if p_patch ? 'gravado' then
    g := public.content_production(p_id, case when (p_patch->>'gravado')::boolean then 'recorded' else 'not_started' end, p_token);
  end if;
  select * into g from guioes where id = p_id;
  return g;
end $$;

-- O código de equipa (Numeiro) precisa de submeter para poder reaprovar depois de editar.
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','analytics.read','agents.read','agents.rehearse']);
$$;

-- ───────────── permissões das funções ─────────────
revoke all on function public._content_actor(text), public._content_require(text,text,text,text,text), public._content_snapshot(text,jsonb,text),
  public._content_log(guioes,text,text,text,uuid,text,jsonb,text,uuid), public.content_append_only(), public.content_same_workspace(),
  public.guioes_ws_locked(), public.guioes_before_insert(), public.guioes_after_insert() from public, anon, authenticated;
revoke all on function public.content_save(text,jsonb,integer,text), public.content_transition(text,text,text,integer,text),
  public.content_production(text,text,text), public.content_create(text,jsonb,text), public.content_duplicate(text,text),
  public.content_history(text,text), public.content_restore_version(text,uuid,integer,text) from public;
grant execute on function public.content_save(text,jsonb,integer,text), public.content_transition(text,text,text,integer,text),
  public.content_production(text,text,text), public.content_create(text,jsonb,text), public.content_duplicate(text,text),
  public.content_history(text,text), public.content_restore_version(text,uuid,integer,text) to anon, authenticated;
-- anon só passa com código de equipa válido (_content_actor recusa sem sessão nem código).

/* Rollback (manual, depois de exportar content_versions/content_transitions se tiverem dados novos):
drop trigger guioes_after_insert on guioes; drop trigger guioes_before_insert on guioes; drop trigger guioes_ws_locked on guioes;
drop function content_save, content_transition, content_production, content_create, content_duplicate, content_history, content_restore_version,
  _content_actor, _content_require, _content_snapshot, _content_log, guioes_after_insert, guioes_before_insert, guioes_ws_locked;
alter table guioes drop constraint guioes_current_version_fk, drop constraint guioes_approved_version_fk;
drop table domain_events, content_transitions, content_versions;
alter table guioes drop column editorial_status, drop column production_status, drop column current_version_id, drop column approved_version_id,
  drop column cta, drop column notas, drop column archived_from, drop column created_at, drop column created_by, drop column lock_version;
alter table clients drop column require_approval_to_record;
-- e reaplicar guiao_update/legacy_can de 20261028191546_w1_review_fixes e 20261028185427_w1_data_access_cutover.
*/
