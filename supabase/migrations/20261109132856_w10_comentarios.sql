-- W10-26 · Comentários como fonte de ideias (PRD §47 REACT-08, CHG-010). Separador Comentários na tab Reacts.
-- Expand (só aditivo): tabela comment_ideas fechada à API; RPCs de sessão com reacts.read / reacts.decide + flag
-- reacts.radar (reutiliza _react_require); RPCs worker_* só engine_worker/service_role. Rollback: bloco no fim.

create table if not exists public.comment_ideas (
  id bigint generated always as identity primary key,
  workspace_id text not null references clients(id) on delete cascade,
  platform text not null default 'instagram' check (platform in ('instagram', 'tiktok', 'youtube')),
  comment_key text not null check (comment_key ~ '^[a-z]+:[A-Za-z0-9_:-]{3,80}$'),
  reel_ref_key text,
  reel_url text check (reel_url is null or reel_url ~ '^https://'),
  reel_account text check (reel_account is null or reel_account ~ '^[A-Za-z0-9._-]{1,40}$'),
  reel_caption text check (reel_caption is null or char_length(reel_caption) <= 1000),
  author text check (author is null or author ~ '^[A-Za-z0-9._-]{1,40}$'),
  text text not null check (char_length(text) between 1 and 3000),
  likes int check (likes is null or likes >= 0),
  replies int check (replies is null or replies >= 0),
  posted_at timestamptz,
  kind text check (kind is null or kind in ('discorda', 'concorda', 'outro_angulo', 'pergunta')),
  ai jsonb check (ai is null or jsonb_typeof(ai) = 'object'),
  score int check (score is null or (score between 0 and 100)),
  risk_level text check (risk_level is null or risk_level in ('baixo', 'medio', 'alto')),
  status text not null default 'open' check (status in ('open', 'saved', 'recorded', 'rejected')),
  reject_reason text check (reject_reason is null or reject_reason in ('sem_interesse', 'repetido', 'fraco', 'pessoal', 'risco', 'outro')),
  rating int check (rating is null or rating between 1 and 5),
  decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  decided_at timestamptz, decided_by uuid references auth.users(id) on delete set null, decided_label text,
  content_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comment_reject_needs_reason check ((status = 'rejected') = (reject_reason is not null)),
  constraint comment_recorded_needs_content check ((status = 'recorded') = (content_id is not null))
);
create unique index if not exists comment_ideas_ws_key on public.comment_ideas (workspace_id, comment_key);
create index if not exists comment_ideas_queue on public.comment_ideas (workspace_id, status, score desc nulls last, created_at desc);
alter table public.comment_ideas enable row level security;
revoke all on public.comment_ideas from anon, authenticated;

create or replace function public.comment_ideas_touch() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists comment_ideas_touch on public.comment_ideas;
create trigger comment_ideas_touch before insert or update on public.comment_ideas for each row execute function public.comment_ideas_touch();

create or replace function public._comment_row(c comment_ideas) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', c.id, 'platform', c.platform, 'comment_key', c.comment_key, 'reel_ref_key', c.reel_ref_key, 'reel_url', c.reel_url,
    'reel_account', c.reel_account, 'reel_caption', c.reel_caption, 'author', c.author, 'text', c.text, 'likes', c.likes, 'replies', c.replies,
    'posted_at', c.posted_at, 'kind', c.kind, 'ai', c.ai, 'score', c.score, 'risk_level', c.risk_level, 'status', c.status,
    'reject_reason', c.reject_reason, 'rating', c.rating, 'decision_note', c.decision_note, 'decided_at', c.decided_at,
    'decided_label', c.decided_label, 'content_id', c.content_id, 'created_at', c.created_at)
$$;

create or replace function public.comments_list(p_ws text, p_tab text default 'open', p_kind text default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tab text := coalesce(nullif(p_tab, ''), 'open');
begin
  perform public._react_require('reacts.read', p_ws, p_token, 'comment.list', null);
  if tab not in ('open', 'saved', 'recorded', 'rejected') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if p_kind is not null and p_kind not in ('discorda', 'concorda', 'outro_angulo', 'pergunta') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(public._comment_row(c) order by
                 case when tab = 'open' then c.score end desc nulls last, coalesce(c.decided_at, c.created_at) desc), '[]')
              from comment_ideas c where c.workspace_id = p_ws and c.status = tab and (p_kind is null or c.kind = p_kind)),
    'counts', (select jsonb_build_object('open', count(*) filter (where status = 'open'), 'saved', count(*) filter (where status = 'saved'),
                 'recorded', count(*) filter (where status = 'recorded'), 'rejected', count(*) filter (where status = 'rejected'))
               from comment_ideas where workspace_id = p_ws),
    'kinds', (select jsonb_object_agg(k, n) from (select kind k, count(*) n from comment_ideas where workspace_id = p_ws and status = tab and kind is not null group by kind) x),
    'last_run', (select max(created_at) from comment_ideas where workspace_id = p_ws),
    'can', jsonb_build_object('decide', public.ws_can('reacts.decide', p_ws, p_token),
                              'record', public.ws_can('reacts.decide', p_ws, p_token) and public.ws_can('scripts.create', p_ws, p_token)));
end $$;

create or replace function public.comment_decide(p_id bigint, p_action text, p_reason text default null, p_rating int default null,
                                                 p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c comment_ideas; a jsonb; before jsonb;
begin
  select * into c from comment_ideas where id = p_id;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._react_require('reacts.decide', c.workspace_id, p_token, 'comment.decide', null);
  if p_action not in ('save', 'reject', 'reopen', 'rate') then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then raise exception 'nota_invalida' using errcode = '22023'; end if;
  if c.status = 'recorded' and p_action <> 'rate' then raise exception 'ja_gravado' using errcode = '55000', detail = 'Esta ideia já tem guião; muda o estado no guião.'; end if;
  a := public._content_actor(p_token);
  before := jsonb_build_object('status', c.status, 'reject_reason', c.reject_reason, 'rating', c.rating);
  if p_action = 'reject' then
    if p_reason is null or p_reason not in ('sem_interesse', 'repetido', 'fraco', 'pessoal', 'risco', 'outro') then
      raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Escolhe o motivo da rejeição.';
    end if;
    update comment_ideas set status = 'rejected', reject_reason = p_reason, rating = coalesce(p_rating, rating),
      decision_note = nullif(btrim(coalesce(p_note, '')), ''), decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label'
      where id = p_id returning * into c;
  elsif p_action = 'save' then
    update comment_ideas set status = 'saved', reject_reason = null, rating = coalesce(p_rating, rating),
      decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label' where id = p_id returning * into c;
  elsif p_action = 'reopen' then
    update comment_ideas set status = 'open', reject_reason = null, decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label'
      where id = p_id returning * into c;
  else
    if p_rating is null then raise exception 'nota_invalida' using errcode = '22023'; end if;
    update comment_ideas set rating = p_rating where id = p_id returning * into c;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', c.workspace_id, 'comment.' || p_action, 'comment_idea', c.id::text, before,
          jsonb_build_object('status', c.status, 'reject_reason', c.reject_reason, 'rating', c.rating));
  return public._comment_row(c);
end $$;

-- Gravar: guião em rascunho (formato resposta_comentario). O nome de quem comentou não vai para o guião (pessoa privada).
create or replace function public.comment_record(p_id bigint, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c comment_ideas; g guioes; a jsonb; hooks jsonb;
begin
  select * into c from comment_ideas where id = p_id for update;
  if not found then raise exception 'nao_encontrado' using errcode = 'P0002'; end if;
  perform public._react_require('reacts.decide', c.workspace_id, p_token, 'comment.record', null);
  if c.status = 'recorded' and c.content_id is not null then
    return jsonb_build_object('content_id', c.content_id, 'created', false, 'item', public._comment_row(c));
  end if;
  a := public._content_actor(p_token);
  hooks := coalesce((select jsonb_agg(jsonb_build_object('text', h->>'text', 'mecanismo', coalesce(h->>'mecanismo', 'comentario')))
                     from jsonb_array_elements(case when jsonb_typeof(c.ai->'hooks') = 'array' then c.ai->'hooks' else '[]' end) h
                     where coalesce(h->>'text', '') <> ''), '[]');
  g := public.content_create(c.workspace_id, jsonb_build_object('formato', 'resposta_comentario',
         'tema', left('[Comentário] ' || coalesce(nullif(c.ai->>'ideia', ''), left(c.text, 120)), 200),
         'hooks', hooks, 'corpo', coalesce(nullif(c.ai->>'resposta', ''), 'Escreve aqui a resposta ao comentário.'),
         'notas', 'Resposta ao comentário: "' || left(c.text, 500) || '"' || coalesce(E'\nReel: ' || c.reel_url, '') ||
                  coalesce(E'\nÂngulo: ' || (c.ai->>'angulo'), '') ||
                  E'\nResponder à ideia, não à pessoa. Não mostrar o nome de quem comentou sem autorização (REACT-08).',
         'origem', 'Comentários'), p_token);
  update comment_ideas set status = 'recorded', content_id = g.id, reject_reason = null,
    decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label' where id = p_id returning * into c;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', c.workspace_id, 'comment.record', 'comment_idea', c.id::text, jsonb_build_object('content_id', g.id));
  return jsonb_build_object('content_id', g.id, 'created', true, 'item', public._comment_row(c));
end $$;

-- Agente: cria ou atualiza pela identidade do comentário; nunca toca no estado nem nas decisões.
create or replace function public.worker_comment_upsert(p_ws text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c comment_ideas;
begin
  if not exists (select 1 from clients where id = p_ws) then raise exception 'workspace_desconhecido' using errcode = 'P0002'; end if;
  insert into comment_ideas (workspace_id, platform, comment_key, reel_ref_key, reel_url, reel_account, reel_caption, author, text, likes, replies,
    posted_at, kind, ai, score, risk_level)
  values (p_ws, coalesce(p_fields->>'platform', 'instagram'), p_fields->>'comment_key', coalesce(p_fields->>'reel_ref_key', public.reel_ref_key(p_fields->>'reel_url')),
    p_fields->>'reel_url', nullif(p_fields->>'reel_account', ''), left(p_fields->>'reel_caption', 1000), nullif(p_fields->>'author', ''),
    left(p_fields->>'text', 3000), (p_fields->>'likes')::int, (p_fields->>'replies')::int, (p_fields->>'posted_at')::timestamptz,
    nullif(p_fields->>'kind', ''), p_fields->'ai', (p_fields->'ai'->>'score')::int, nullif(p_fields->'ai'->>'risk_level', ''))
  on conflict (workspace_id, comment_key) do update set
    likes = coalesce(excluded.likes, comment_ideas.likes), replies = coalesce(excluded.replies, comment_ideas.replies),
    kind = coalesce(excluded.kind, comment_ideas.kind), ai = coalesce(excluded.ai, comment_ideas.ai),
    score = coalesce(excluded.score, comment_ideas.score), risk_level = coalesce(excluded.risk_level, comment_ideas.risk_level)
  returning * into c;
  return jsonb_build_object('id', c.id, 'status', c.status);
end $$;

-- Contexto: a mensagem do cliente (configuração ativa do motor e frases-persona), comentários já vistos e decisões recentes.
create or replace function public.worker_comment_context(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return jsonb_build_object(
    'config', (select jsonb_build_object('voice', config->'voice', 'guardrails', config->'guardrails', 'news_beats', config->'news_beats',
                 'formats', config->'formats', 'lexicon', config->'lexicon', 'notes', notes)
               from agent_config_versions where workspace_id = p_ws and status = 'active' order by activated_at desc nulls last limit 1),
    'persona', (select phrases from persona_lists where workspace_id = p_ws order by version desc limit 1),
    'accounts', (select coalesce(jsonb_agg(distinct a.handle), '[]') from accounts a where a.client_id = p_ws and a.role = 'client' and a.active),
    'seen', (select coalesce(jsonb_agg(comment_key), '[]') from comment_ideas where workspace_id = p_ws and created_at > now() - interval '60 days'),
    'last_run', (select max(created_at) from comment_ideas where workspace_id = p_ws),
    'decisions', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'reject_reason', reject_reason, 'rating', rating,
                    'score', score, 'text', left(text, 200)) order by decided_at desc), '[]')
                  from (select * from comment_ideas where workspace_id = p_ws and decided_at is not null order by decided_at desc limit 200) d));
end $$;

revoke all on function public._comment_row(comment_ideas), public.worker_comment_upsert(text, jsonb), public.worker_comment_context(text) from public, anon, authenticated;
grant execute on function public.worker_comment_upsert(text, jsonb), public.worker_comment_context(text) to engine_worker, service_role;
revoke all on function public.comments_list(text, text, text, text), public.comment_decide(bigint, text, text, int, text, text), public.comment_record(bigint, text) from public;
grant execute on function public.comments_list(text, text, text, text), public.comment_decide(bigint, text, text, int, text, text), public.comment_record(bigint, text) to authenticated, anon;

/* Rollback (só depois de reverter o código):
   drop function if exists public.comments_list(text, text, text, text), public.comment_decide(bigint, text, text, int, text, text),
     public.comment_record(bigint, text), public.worker_comment_upsert(text, jsonb), public.worker_comment_context(text), public._comment_row(comment_ideas);
   drop table if exists public.comment_ideas;  -- perde as decisões: exportar antes
*/
