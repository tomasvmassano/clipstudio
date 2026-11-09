-- W10-25 · Radar de reacts (PRD §47, CHG-009): REACT-01 fontes vigiadas e propostas, REACT-02 candidatos com índice de
-- polémica, REACT-03 avaliação pela IA guardada com versão, REACT-04 fila por cliente com decisões, REACT-05 gravar cria
-- guião, REACT-06 contexto de aprendizagem para o agente. AGENTS §2.1 (negar por defeito), §7 (proveniência), R-13, R-20.
-- Expand (só aditivo, compatível com o código em main): 3 capacidades, 1 flag (reacts.radar, equipa da agência por defeito),
-- 2 tabelas fechadas à API (react_sources, react_candidates), RPCs de leitura/decisão para a sessão e RPCs worker_* só
-- para engine_worker/service_role (o agente diário escreve por aqui). Rollback: bloco no fim.

-- ───────────── capacidades e flag ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('reacts.read', 'Reacts', 'B', array['ws'], 'ativo', 'Ver a fila de reacts, abrir e descarregar o vídeo original (REACT-02..04)'),
  ('reacts.decide', 'Reacts', 'M', array['ws'], 'ativo', 'Gravar (cria guião), guardar, rejeitar com motivo e dar nota a um react (REACT-04/05)'),
  ('reacts.sources.manage', 'Reacts', 'M', array['ws'], 'ativo', 'Aceitar e rejeitar contas propostas e gerir as contas vigiadas (REACT-01)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes, risk = excluded.risk;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'reacts.read'), ('ws', 'workspace_admin', 'reacts.read'), ('ws', 'manager', 'reacts.read'), ('ws', 'contributor', 'reacts.read'),
  ('ws', 'workspace_owner', 'reacts.decide'), ('ws', 'workspace_admin', 'reacts.decide'), ('ws', 'manager', 'reacts.decide'), ('ws', 'contributor', 'reacts.decide'),
  ('ws', 'workspace_owner', 'reacts.sources.manage'), ('ws', 'workspace_admin', 'reacts.sources.manage'), ('ws', 'manager', 'reacts.sources.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('reacts.radar', 'Radar de reacts', 'Reacts', 'ws', 'agency',
   'Fila de takes polémicos para reagir, com avaliação da IA, vídeo para ver e descarregar e decisões que ensinam o agente (PRD §47, REACT-01..07).')
on conflict do nothing;

-- ───────────── tabelas ─────────────
create table if not exists public.react_sources (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references clients(id) on delete cascade,
  platform text not null check (platform in ('instagram', 'tiktok')),
  handle text not null check (handle ~ '^[A-Za-z0-9._-]{1,40}$'),
  status text not null default 'proposed' check (status in ('proposed', 'active', 'paused', 'rejected')),
  origin text not null default 'manual' check (origin in ('seed', 'manual', 'coauthor', 'tagged', 'related', 'commenter', 'topic_search', 'other')),
  origin_detail text check (origin_detail is null or char_length(origin_detail) <= 300),
  score numeric check (score is null or (score >= 0 and score <= 100)),
  stats jsonb not null default '{}' check (jsonb_typeof(stats) = 'object'),
  created_kind text not null default 'user' check (created_kind in ('user', 'agent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  decided_at timestamptz, decided_by uuid references auth.users(id) on delete set null, decided_label text,
  decision_note text check (decision_note is null or char_length(decision_note) <= 500)
);
create unique index if not exists react_sources_ws_handle on public.react_sources (workspace_id, platform, lower(handle));

create table if not exists public.react_candidates (
  id bigint generated always as identity primary key,
  workspace_id text not null references clients(id) on delete cascade,
  source_id uuid references react_sources(id) on delete set null,
  platform text not null check (platform in ('instagram', 'tiktok')),
  ref_key text not null check (ref_key ~ '^(instagram|tiktok):[A-Za-z0-9_-]{5,40}$'),
  url text not null check (url ~ '^https://'),
  author text check (author is null or author ~ '^[A-Za-z0-9._-]{1,40}$'),
  caption text check (caption is null or char_length(caption) <= 3000),
  posted_at timestamptz,
  duration_s numeric check (duration_s is null or duration_s >= 0),
  thumb_url text check (thumb_url is null or thumb_url ~ '^https://'),
  video_url text check (video_url is null or video_url ~ '^https://'),
  video_url_expires_at timestamptz,
  metrics jsonb not null default '{}' check (jsonb_typeof(metrics) = 'object'),
  video_type text check (video_type is null or video_type in ('react', 'talking_head', 'visual', 'frase', 'outro')),
  transcript text check (transcript is null or char_length(transcript) <= 20000),
  ai jsonb check (ai is null or jsonb_typeof(ai) = 'object'),
  score int check (score is null or (score between 0 and 100)),
  risk_level text check (risk_level is null or risk_level in ('baixo', 'medio', 'alto')),
  expires_at timestamptz not null default now() + interval '72 hours',
  status text not null default 'open' check (status in ('open', 'saved', 'recorded', 'rejected')),
  reject_reason text check (reject_reason is null or reject_reason in ('sem_interesse', 'velho', 'alvo_errado', 'angulo_fraco', 'risco', 'outro')),
  rating int check (rating is null or rating between 1 and 5),
  decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  decided_at timestamptz, decided_by uuid references auth.users(id) on delete set null, decided_label text,
  content_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint react_reject_needs_reason check ((status = 'rejected') = (reject_reason is not null)),
  constraint react_recorded_needs_content check ((status = 'recorded') = (content_id is not null))
);
create unique index if not exists react_candidates_ws_key on public.react_candidates (workspace_id, ref_key);
create index if not exists react_candidates_queue on public.react_candidates (workspace_id, status, score desc nulls last, expires_at);

alter table public.react_sources enable row level security;
alter table public.react_candidates enable row level security;
revoke all on public.react_sources, public.react_candidates from anon, authenticated;

-- A fonte de um candidato tem de ser do mesmo cliente.
create or replace function public.react_candidates_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  if new.source_id is not null and not exists (select 1 from react_sources s where s.id = new.source_id and s.workspace_id = new.workspace_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists react_candidates_guard on public.react_candidates;
create trigger react_candidates_guard before insert or update on public.react_candidates for each row execute function public.react_candidates_guard();

create or replace function public.react_sources_touch() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists react_sources_touch on public.react_sources;
create trigger react_sources_touch before insert or update on public.react_sources for each row execute function public.react_sources_touch();

-- ───────────── leitura (sessão) ─────────────
create or replace function public._react_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, null);
  if not public._flag_on('reacts.radar', p_ws, p_token) then raise exception 'funcionalidade_desligada' using errcode = '55000'; end if;
end $$;

-- Linha para a página: nunca devolve o link do vídeo (só pela rota de download, que volta a verificar a permissão).
create or replace function public._react_row(c react_candidates) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', c.id, 'platform', c.platform, 'ref_key', c.ref_key, 'url', c.url, 'author', c.author,
    'caption', c.caption, 'posted_at', c.posted_at, 'duration_s', c.duration_s, 'thumb_url', c.thumb_url,
    'has_video', c.video_url is not null and (c.video_url_expires_at is null or c.video_url_expires_at > now()),
    'metrics', c.metrics, 'video_type', c.video_type, 'transcript', c.transcript, 'ai', c.ai, 'score', c.score, 'risk_level', c.risk_level,
    'expires_at', c.expires_at, 'expired', c.status = 'open' and c.expires_at <= now(), 'status', c.status,
    'reject_reason', c.reject_reason, 'rating', c.rating, 'decision_note', c.decision_note, 'decided_at', c.decided_at,
    'decided_label', c.decided_label, 'content_id', c.content_id, 'created_at', c.created_at,
    'source', (select jsonb_build_object('id', s.id, 'handle', s.handle, 'status', s.status) from react_sources s where s.id = c.source_id))
$$;

create or replace function public.reacts_list(p_ws text, p_tab text default 'open', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tab text := coalesce(nullif(p_tab, ''), 'open');
begin
  perform public._react_require('reacts.read', p_ws, p_token, 'react.list', null);
  if tab not in ('open', 'saved', 'recorded', 'rejected', 'expired') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._react_row(c) order by
                 case when tab = 'open' then c.score end desc nulls last,
                 case when tab = 'open' then c.expires_at end asc,
                 coalesce(c.decided_at, c.created_at) desc), '[]')
              from react_candidates c
              where c.workspace_id = p_ws
                and case tab
                      when 'open' then c.status = 'open' and c.expires_at > now()
                      when 'expired' then c.status = 'open' and c.expires_at <= now()
                      else c.status = tab end),
    'counts', (select jsonb_build_object(
                 'open', count(*) filter (where status = 'open' and expires_at > now()),
                 'expired', count(*) filter (where status = 'open' and expires_at <= now()),
                 'saved', count(*) filter (where status = 'saved'),
                 'recorded', count(*) filter (where status = 'recorded'),
                 'rejected', count(*) filter (where status = 'rejected'))
               from react_candidates where workspace_id = p_ws),
    'last_run', (select max(created_at) from react_candidates where workspace_id = p_ws),
    'can', jsonb_build_object('decide', public.ws_can('reacts.decide', p_ws, p_token), 'record', public.ws_can('reacts.decide', p_ws, p_token) and public.ws_can('scripts.create', p_ws, p_token),
                              'sources', public.ws_can('reacts.sources.manage', p_ws, p_token)));
end $$;

-- Para a rota de download/visualização: devolve o link do vídeo só a quem pode ler este cliente.
create or replace function public.react_video_access(p_ws text, p_id bigint, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c react_candidates;
begin
  perform public._react_require('reacts.read', p_ws, p_token, 'react.video', null);
  select * into c from react_candidates where id = p_id and workspace_id = p_ws;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  if c.video_url is null or (c.video_url_expires_at is not null and c.video_url_expires_at <= now()) then
    raise exception 'video_expirado' using errcode = '55000', detail = 'O link do vídeo expirou. O agente renova-o na próxima corrida; entretanto abre o original.';
  end if;
  return jsonb_build_object('url', c.video_url, 'author', c.author, 'ref_key', c.ref_key, 'platform', c.platform);
end $$;

-- ───────────── decisões (sessão) ─────────────
create or replace function public.react_decide(p_id bigint, p_action text, p_reason text default null, p_rating int default null,
                                               p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c react_candidates; a jsonb; before jsonb;
begin
  select * into c from react_candidates where id = p_id;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._react_require('reacts.decide', c.workspace_id, p_token, 'react.decide', null);
  if p_action not in ('save', 'reject', 'reopen', 'rate') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then raise exception 'nota_invalida' using errcode = '22023'; end if;
  if c.status = 'recorded' and p_action <> 'rate' then raise exception 'ja_gravado' using errcode = '55000', detail = 'Este react já tem guião; muda o estado no guião.'; end if;
  a := public._content_actor(p_token);
  before := jsonb_build_object('status', c.status, 'reject_reason', c.reject_reason, 'rating', c.rating);
  if p_action = 'reject' then
    if p_reason is null or p_reason not in ('sem_interesse', 'velho', 'alvo_errado', 'angulo_fraco', 'risco', 'outro') then
      raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Escolhe o motivo da rejeição.';
    end if;
    update react_candidates set status = 'rejected', reject_reason = p_reason, rating = coalesce(p_rating, rating),
      decision_note = nullif(btrim(coalesce(p_note, '')), ''), decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label'
      where id = p_id returning * into c;
  elsif p_action = 'save' then
    update react_candidates set status = 'saved', reject_reason = null, rating = coalesce(p_rating, rating),
      decision_note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), decision_note), decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label'
      where id = p_id returning * into c;
  elsif p_action = 'reopen' then
    update react_candidates set status = 'open', reject_reason = null, decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label',
      expires_at = greatest(expires_at, now() + interval '24 hours')
      where id = p_id returning * into c;
  else
    if p_rating is null then raise exception 'nota_invalida' using errcode = '22023'; end if;
    update react_candidates set rating = p_rating, decision_note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), decision_note)
      where id = p_id returning * into c;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', c.workspace_id, 'react.' || p_action, 'react_candidate', c.id::text, before,
          jsonb_build_object('status', c.status, 'reject_reason', c.reject_reason, 'rating', c.rating));
  return public._react_row(c);
end $$;

-- Gravar: cria um guião (formato react) com o ângulo, os ganchos e a resposta da avaliação, ligado ao vídeo de origem.
-- Idempotente: um candidato já gravado devolve o mesmo guião.
create or replace function public.react_record(p_id bigint, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c react_candidates; g guioes; a jsonb; hooks jsonb; corpo text; tema text;
begin
  select * into c from react_candidates where id = p_id for update;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._react_require('reacts.decide', c.workspace_id, p_token, 'react.record', null);
  if c.status = 'recorded' and c.content_id is not null then
    return jsonb_build_object('content_id', c.content_id, 'created', false, 'item', public._react_row(c));
  end if;
  a := public._content_actor(p_token);
  hooks := coalesce((select jsonb_agg(jsonb_build_object('text', h->>'text', 'mecanismo', coalesce(h->>'mecanismo', 'react')))
                     from jsonb_array_elements(case when jsonb_typeof(c.ai->'hooks') = 'array' then c.ai->'hooks' else '[]' end) h
                     where coalesce(h->>'text', '') <> ''), '[]');
  corpo := coalesce(nullif(c.ai->>'resposta', ''), 'Escreve aqui a resposta ao take.');
  tema := left('[React] @' || coalesce(c.author, '?') || ': ' || coalesce(nullif(c.ai->>'resumo', ''), nullif(left(c.caption, 80), ''), c.ref_key), 200);
  g := public.content_create(c.workspace_id, jsonb_build_object('formato', 'react', 'tema', tema, 'hooks', hooks, 'corpo', corpo,
         'notas', 'React ao vídeo ' || c.url || coalesce(E'\nÂngulo: ' || (c.ai->>'angulo'), '') ||
                  E'\nMostrar só um excerto curto e creditado do original (REACT-05). Nota da IA: ' || coalesce(c.score::text, '—') || '/100.',
         'origem', 'Radar de reacts'), p_token);
  update react_candidates set status = 'recorded', content_id = g.id, reject_reason = null,
    decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label' where id = p_id returning * into c;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', c.workspace_id, 'react.record', 'react_candidate', c.id::text,
          jsonb_build_object('content_id', g.id));
  return jsonb_build_object('content_id', g.id, 'created', true, 'item', public._react_row(c));
end $$;

-- ───────────── fontes (sessão) ─────────────
create or replace function public._react_source_row(s react_sources) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', s.id, 'platform', s.platform, 'handle', s.handle, 'status', s.status, 'origin', s.origin,
    'origin_detail', s.origin_detail, 'score', s.score, 'stats', s.stats, 'created_kind', s.created_kind, 'created_at', s.created_at,
    'decided_at', s.decided_at, 'decided_label', s.decided_label, 'decision_note', s.decision_note,
    'candidates', (select count(*) from react_candidates c where c.source_id = s.id))
$$;

create or replace function public.react_sources_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._react_require('reacts.read', p_ws, p_token, 'react.sources', null);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._react_source_row(s) order by
                 case s.status when 'proposed' then 0 when 'active' then 1 when 'paused' then 2 else 3 end, s.score desc nulls last, s.handle), '[]')
              from react_sources s where s.workspace_id = p_ws),
    'can', jsonb_build_object('manage', public.ws_can('reacts.sources.manage', p_ws, p_token)));
end $$;

create or replace function public.react_source_add(p_ws text, p_platform text, p_handle text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s react_sources; a jsonb; h text := lower(regexp_replace(btrim(coalesce(p_handle, '')), '^@', ''));
begin
  perform public._react_require('reacts.sources.manage', p_ws, p_token, 'react.source_add', null);
  if p_platform not in ('instagram', 'tiktok') or h !~ '^[a-z0-9._-]{1,40}$' then
    raise exception 'pedido_invalido' using errcode = '22023', detail = 'Conta inválida: escreve só o nome (ex.: kikoishot).';
  end if;
  a := public._content_actor(p_token);
  insert into react_sources (workspace_id, platform, handle, status, origin, created_kind, decided_at, decided_by, decided_label)
  values (p_ws, p_platform, h, 'active', 'manual', 'user', now(), (a->>'uid')::uuid, a->>'label')
  on conflict (workspace_id, platform, lower(handle)) do update set status = 'active', decided_at = now(),
    decided_by = (a->>'uid')::uuid, decided_label = a->>'label'
  returning * into s;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'react.source_add', 'react_source', s.id::text,
          jsonb_build_object('platform', s.platform, 'handle', s.handle));
  return public._react_source_row(s);
end $$;

create or replace function public.react_source_decide(p_id uuid, p_action text, p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s react_sources; a jsonb; prev text; nxt text;
begin
  select * into s from react_sources where id = p_id;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._react_require('reacts.sources.manage', s.workspace_id, p_token, 'react.source_decide', null);
  nxt := case p_action when 'accept' then 'active' when 'reject' then 'rejected' when 'pause' then 'paused' when 'resume' then 'active' end;
  if nxt is null then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  a := public._content_actor(p_token); prev := s.status;
  update react_sources set status = nxt, decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label',
    decision_note = nullif(btrim(coalesce(p_note, '')), '') where id = p_id returning * into s;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', s.workspace_id, 'react.source_' || p_action, 'react_source', s.id::text,
          jsonb_build_object('status', prev), jsonb_build_object('status', s.status));
  return public._react_source_row(s);
end $$;

-- ───────────── agente (engine_worker / service_role) ─────────────
-- Propõe uma conta ou atualiza as estatísticas de uma conta conhecida. Nunca muda uma decisão humana.
create or replace function public.worker_react_source_upsert(p_ws text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s react_sources; h text := lower(regexp_replace(btrim(coalesce(p_fields->>'handle', '')), '^@', ''));
        st text := coalesce(p_fields->>'status', 'proposed');
begin
  if not exists (select 1 from clients where id = p_ws) then raise exception 'workspace_desconhecido' using errcode = 'P0002'; end if;
  if st not in ('proposed', 'active') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  insert into react_sources (workspace_id, platform, handle, status, origin, origin_detail, score, stats, created_kind)
  values (p_ws, coalesce(p_fields->>'platform', 'instagram'), h, st, coalesce(p_fields->>'origin', 'other'),
          left(p_fields->>'origin_detail', 300), (p_fields->>'score')::numeric, coalesce(p_fields->'stats', '{}'), 'agent')
  on conflict (workspace_id, platform, lower(handle)) do update set
    score = coalesce(excluded.score, react_sources.score),
    stats = react_sources.stats || excluded.stats,
    status = case when react_sources.status = 'proposed' and excluded.status = 'active' and react_sources.decided_at is null then 'active' else react_sources.status end
  returning * into s;
  return public._react_source_row(s);
end $$;

-- Cria ou atualiza um candidato pela identidade do vídeo (idempotente). Métricas, link do vídeo e avaliação atualizam-se;
-- o estado e as decisões humanas nunca são tocados.
create or replace function public.worker_react_candidate_upsert(p_ws text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c react_candidates; k text := coalesce(p_fields->>'ref_key', public.reel_ref_key(p_fields->>'url')); src uuid; sc int;
begin
  if not exists (select 1 from clients where id = p_ws) then raise exception 'workspace_desconhecido' using errcode = 'P0002'; end if;
  if k is null then raise exception 'link_sem_identidade' using errcode = '22023'; end if;
  if p_fields ? 'source_handle' then
    select id into src from react_sources where workspace_id = p_ws and lower(handle) = lower(p_fields->>'source_handle')
      and platform = coalesce(p_fields->>'platform', 'instagram');
  end if;
  sc := (p_fields->'ai'->>'score')::int;
  insert into react_candidates (workspace_id, source_id, platform, ref_key, url, author, caption, posted_at, duration_s, thumb_url,
    video_url, video_url_expires_at, metrics, video_type, transcript, ai, score, risk_level, expires_at)
  values (p_ws, src, coalesce(p_fields->>'platform', split_part(k, ':', 1)), k, p_fields->>'url', nullif(p_fields->>'author', ''),
    left(p_fields->>'caption', 3000), (p_fields->>'posted_at')::timestamptz, (p_fields->>'duration_s')::numeric, nullif(p_fields->>'thumb_url', ''),
    nullif(p_fields->>'video_url', ''), (p_fields->>'video_url_expires_at')::timestamptz, coalesce(p_fields->'metrics', '{}'),
    nullif(p_fields->>'video_type', ''), left(p_fields->>'transcript', 20000), p_fields->'ai', sc, nullif(p_fields->'ai'->>'risk_level', ''),
    coalesce((p_fields->>'posted_at')::timestamptz, now()) + interval '72 hours')
  on conflict (workspace_id, ref_key) do update set
    source_id = coalesce(excluded.source_id, react_candidates.source_id),
    caption = coalesce(excluded.caption, react_candidates.caption),
    duration_s = coalesce(excluded.duration_s, react_candidates.duration_s),
    thumb_url = coalesce(excluded.thumb_url, react_candidates.thumb_url),
    video_url = coalesce(excluded.video_url, react_candidates.video_url),
    video_url_expires_at = case when excluded.video_url is not null then excluded.video_url_expires_at else react_candidates.video_url_expires_at end,
    metrics = react_candidates.metrics || excluded.metrics,
    video_type = coalesce(excluded.video_type, react_candidates.video_type),
    transcript = coalesce(excluded.transcript, react_candidates.transcript),
    ai = coalesce(excluded.ai, react_candidates.ai),
    score = coalesce(excluded.score, react_candidates.score),
    risk_level = coalesce(excluded.risk_level, react_candidates.risk_level)
  returning * into c;
  return jsonb_build_object('id', c.id, 'ref_key', c.ref_key, 'status', c.status);
end $$;

-- Contexto para o agente: contas, decisões recentes (aprendizagem, REACT-06) e candidatos abertos ou guardados cujo link
-- de vídeo precisa de ser renovado (REACT-07).
create or replace function public.worker_react_context(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return jsonb_build_object(
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'handle', handle, 'status', status, 'origin', origin, 'score', score)), '[]')
                from react_sources where workspace_id = p_ws),
    'decisions', (select coalesce(jsonb_agg(jsonb_build_object('ref_key', ref_key, 'author', author, 'status', status, 'reject_reason', reject_reason,
                    'rating', rating, 'note', decision_note, 'score', score, 'ai', ai->'parts', 'video_type', video_type) order by decided_at desc), '[]')
                  from (select * from react_candidates where workspace_id = p_ws and decided_at is not null order by decided_at desc limit 200) d),
    'refresh', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'url', url, 'ref_key', ref_key)), '[]')
                from react_candidates where workspace_id = p_ws and status in ('open', 'saved')
                  and (video_url is null or video_url_expires_at is null or video_url_expires_at < now() + interval '12 hours')));
end $$;

revoke all on function public._react_require(text, text, text, text, text), public._react_row(react_candidates), public._react_source_row(react_sources),
  public.worker_react_source_upsert(text, jsonb), public.worker_react_candidate_upsert(text, jsonb), public.worker_react_context(text)
  from public, anon, authenticated;
grant execute on function public.worker_react_source_upsert(text, jsonb), public.worker_react_candidate_upsert(text, jsonb),
  public.worker_react_context(text) to engine_worker, service_role;
revoke all on function public.reacts_list(text, text, text), public.react_video_access(text, bigint, text),
  public.react_decide(bigint, text, text, int, text, text), public.react_record(bigint, text),
  public.react_sources_list(text, text), public.react_source_add(text, text, text, text),
  public.react_source_decide(uuid, text, text, text) from public;
grant execute on function public.reacts_list(text, text, text), public.react_video_access(text, bigint, text),
  public.react_decide(bigint, text, text, int, text, text), public.react_record(bigint, text),
  public.react_sources_list(text, text), public.react_source_add(text, text, text, text),
  public.react_source_decide(uuid, text, text, text) to authenticated, anon;

/* Rollback (contract manual, só depois de reverter o código):
   1. update feature_flags set stage = 'off' where key = 'reacts.radar';
   2. drop function if exists public.reacts_list(text, text, text), public.react_video_access(text, bigint, text),
        public.react_decide(bigint, text, text, int, text, text), public.react_record(bigint, text), public.react_sources_list(text, text),
        public.react_source_add(text, text, text, text), public.react_source_decide(uuid, text, text, text),
        public.worker_react_source_upsert(text, jsonb), public.worker_react_candidate_upsert(text, jsonb), public.worker_react_context(text),
        public._react_require(text, text, text, text, text), public._react_row(react_candidates), public._react_source_row(react_sources);
   3. drop table if exists public.react_candidates, public.react_sources;  -- perde as decisões: exportar antes
   4. delete from role_capabilities where capability like 'reacts.%'; update capabilities set status = 'planeado' where key like 'reacts.%';
      delete from feature_flags where key = 'reacts.radar'; delete from feature_flag_defs where key = 'reacts.radar';
*/
