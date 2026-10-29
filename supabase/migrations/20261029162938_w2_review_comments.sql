-- W2-06 · Revisão de guiões: comentários contextuais (FR-05-02, FR-02-02) e caixa de revisão com filtros (FR-05-01).
-- Expand: tabela e funções novas; legacy_can ganha review.comment (o código do Numeiro já aprova, passa também a comentar);
-- notifications aceita dois tipos novos.

create table if not exists public.content_comments (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  version_id uuid references public.content_versions(id),
  parent_id uuid references public.content_comments(id),
  block text not null check (block ~ '^(geral|corpo|cta|notas|hook_([1-9]|1[0-9]|20))$'),
  quote text check (quote is null or char_length(quote) <= 500),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  mentions uuid[] not null default '{}',
  author_id uuid references auth.users(id) on delete set null,
  author_kind text not null check (author_kind in ('user', 'legacy_code')),
  author_label text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_label text
);
create index if not exists content_comments_content on public.content_comments (content_id, created_at);
create index if not exists content_comments_open on public.content_comments (workspace_id, content_id) where resolved_at is null and parent_id is null;
alter table public.content_comments enable row level security;
revoke all on public.content_comments from anon, authenticated;   -- só pelas RPCs

-- comentários não se apagam nem se reescrevem; só se marca resolvido / reaberto
create or replace function public.content_comments_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'comentarios_nao_se_apagam' using errcode = '42501'; end if;
  if (new.workspace_id, new.content_id, new.version_id, new.parent_id, new.block, new.quote, new.body, new.mentions, new.author_id, new.author_kind, new.author_label, new.created_at)
     is distinct from (old.workspace_id, old.content_id, old.version_id, old.parent_id, old.block, old.quote, old.body, old.mentions, old.author_id, old.author_kind, old.author_label, old.created_at) then
    raise exception 'comentarios_nao_se_editam' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists content_comments_guard on public.content_comments;
create trigger content_comments_guard before update or delete on public.content_comments for each row execute function public.content_comments_guard();

-- notificações de comentários
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done','automation_error','script_mention','script_comment'));

-- código de equipa do Numeiro: igual ao de 20261029074048, mais review.comment
create or replace function public.legacy_can(p_token text, p_cap text, p_ws text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from studio_tokens t where p_token is not null and t.token = p_token and t.client_id = p_ws)
     and p_cap = any (array['scripts.read','scripts.edit','scripts.submit','scripts.approve','scripts.reject','scripts.export',
                            'recording.use','recording.confirm','sources.read','requests.create','references.read','tasks.read','calendar.read',
                            'analytics.read','agents.read','agents.rehearse','review.comment']);
$$;

create or replace function public._comment_json(c public.content_comments) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', c.id, 'parent_id', c.parent_id, 'block', c.block, 'quote', c.quote, 'body', c.body,
    'author', coalesce(c.author_label, 'alguém'), 'author_id', c.author_id, 'author_kind', c.author_kind, 'at', c.created_at,
    'version_no', (select v.version_no from content_versions v where v.id = c.version_id),
    'on_current', c.version_id is not distinct from (select g.current_version_id from guioes g where g.id = c.content_id),
    'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by_label)
$$;

create or replace function public.content_comments(p_id text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token);
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if not public.ws_can('scripts.read', g.client_id, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object(
    'comments', (select coalesce(jsonb_agg(public._comment_json(c) order by c.created_at), '[]') from content_comments c where c.content_id = p_id),
    'can', jsonb_build_object('comment', public.ws_can('review.comment', g.client_id, p_token),
                              'resolve', public.ws_can('scripts.approve', g.client_id, p_token) or public.ws_can('scripts.edit', g.client_id, p_token)),
    'me', a->>'uid');
end $$;

-- Comentar um bloco (hook N, corpo, CTA, notas ou geral), opcionalmente com a frase citada; responder a um comentário.
create or replace function public.content_comment_add(p_id text, p_block text, p_body text, p_quote text default null,
                                                     p_mentions uuid[] default '{}', p_parent uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb := public._content_actor(p_token); c content_comments; par content_comments; m uuid; hk int; blk text := coalesce(p_block, 'geral');
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('review.comment', g.client_id, p_token, 'script.comment', g.id);
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  if coalesce(btrim(p_body), '') = '' then raise exception 'comentario_vazio' using errcode = '22023'; end if;
  if char_length(p_body) > 4000 then raise exception 'comentario_longo' using errcode = '22023'; end if;
  if blk !~ '^(geral|corpo|cta|notas|hook_([1-9]|1[0-9]|20))$' then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  if blk like 'hook_%' then
    hk := substr(blk, 6)::int;
    if hk > jsonb_array_length(coalesce(g.hooks, '[]')) then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  end if;
  if p_parent is not null then
    select * into par from content_comments where id = p_parent;
    if par.id is null or par.content_id <> g.id or par.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
    blk := par.block;
  end if;
  foreach m in array coalesce(p_mentions, '{}') loop
    if not public._authorize('scripts.read', g.client_id, m) then raise exception 'mencao_sem_acesso' using errcode = '22023'; end if;
  end loop;
  insert into content_comments (workspace_id, content_id, version_id, parent_id, block, quote, body, mentions, author_id, author_kind, author_label)
  values (g.client_id, g.id, g.current_version_id, p_parent, blk, nullif(left(btrim(coalesce(p_quote, '')), 500), ''), btrim(p_body),
          coalesce(p_mentions, '{}'), (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into c;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'script.commented', 'content', g.id, jsonb_build_object('comment_id', c.id, 'block', c.block, 'parent_id', c.parent_id));
  foreach m in array coalesce(p_mentions, '{}') loop
    perform public._notify(m, g.client_id, 'script_mention', 'content', g.id, coalesce(a->>'label', 'Alguém') || ' mencionou-te no guião ' || g.n,
                           left(c.body, 300), 'cmention:' || c.id || ':' || m);
  end loop;
  if par.id is not null and par.author_id is not null and not (par.author_id = any (coalesce(p_mentions, '{}'))) then
    perform public._notify(par.author_id, g.client_id, 'script_comment', 'content', g.id, 'Resposta ao teu comentário no guião ' || g.n,
                           left(c.body, 300), 'creply:' || c.id);
  end if;
  return public._comment_json(c);
end $$;

-- Resolver / reabrir: quem escreveu, ou quem edita ou aprova guiões.
create or replace function public.content_comment_resolve(p_comment uuid, p_resolved boolean default true, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c content_comments; a jsonb := public._content_actor(p_token);
begin
  select * into c from content_comments where id = p_comment for update;
  if c.id is null then raise exception 'comentario_nao_encontrado' using errcode = 'P0002'; end if;
  if not public.ws_can('scripts.read', c.workspace_id, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if c.parent_id is not null then raise exception 'resposta_invalida' using errcode = '22023'; end if;
  if not ((c.author_id is not null and c.author_id = (a->>'uid')::uuid)
          or public.ws_can('scripts.approve', c.workspace_id, p_token) or public.ws_can('scripts.edit', c.workspace_id, p_token)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update content_comments set resolved_at = case when p_resolved then now() end, resolved_by_label = case when p_resolved then a->>'label' end
   where id = c.id returning * into c;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (c.workspace_id, case when p_resolved then 'script.comment_resolved' else 'script.comment_reopened' end, 'content', c.content_id,
          jsonb_build_object('comment_id', c.id));
  return public._comment_json(c);
end $$;

-- Caixa de revisão (FR-05-01): guiões por rever com filtros por estado, responsável, prioridade, prazo e texto.
-- Responsável, prioridade e prazo vêm da tarefa de revisão ligada ao guião (a mais recente em aberto), se existir.
create or replace function public.review_inbox(p_ws text, p_filters jsonb default '{}', p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); uid uuid := (a->>'uid')::uuid; tz text;
  st text[]; who text := p_filters->>'assignee'; pr text := p_filters->>'priority'; due text := p_filters->>'due'; q text := nullif(btrim(p_filters->>'q'), '');
  today date;
begin
  if not public.ws_can('scripts.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  st := coalesce((select array_agg(x) from jsonb_array_elements_text(p_filters->'status') x), array['in_review', 'changes_requested', 'draft']);
  if exists (select 1 from unnest(st) s where s not in ('draft', 'in_review', 'changes_requested', 'approved', 'rejected')) then
    raise exception 'filtro_invalido' using errcode = '22023'; end if;
  if pr is not null and pr not in ('low', 'normal', 'high', 'urgent') then raise exception 'filtro_invalido' using errcode = '22023'; end if;
  if due is not null and due not in ('overdue', 'today', 'week') then raise exception 'filtro_invalido' using errcode = '22023'; end if;
  if q is not null and char_length(q) > 100 then raise exception 'filtro_invalido' using errcode = '22023'; end if;
  return (
    with base as (
      select g, t.id as task_id, t.assignee_id, t.priority, t.due_at, coalesce(t.due_at::date, g.date) as due_day,
             (select count(*) from content_comments c where c.content_id = g.id and c.parent_id is null and c.resolved_at is null) as open_comments,
             (select count(*) from content_comments c where c.content_id = g.id) as all_comments,
             (select max(x) from (values (g.updated_at), ((select max(c.created_at) from content_comments c where c.content_id = g.id))) v(x)) as last_activity
        from guioes g
        left join lateral (select * from tasks t where t.workspace_id = p_ws and t.content_id = g.id and t.status in ('todo','doing','blocked')
                            order by (t.kind = 'review') desc, t.created_at desc limit 1) t on true
       where g.client_id = p_ws and g.editorial_status = any (st)
         and (q is null or g.tema ilike '%' || q || '%' or g.corpo ilike '%' || q || '%' or g.hooks::text ilike '%' || q || '%')
    ), filtered as (
      select * from base b
       where (who is null or (who = 'me' and b.assignee_id = uid) or (who = 'none' and b.assignee_id is null)
              or (who ~ '^[0-9a-f-]{36}$' and b.assignee_id = who::uuid))
         and (pr is null or b.priority = pr)
         and (due is null or (due = 'overdue' and b.due_day < today) or (due = 'today' and b.due_day = today)
              or (due = 'week' and b.due_day between today and today + 6))
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object(
          'guiao', to_jsonb(f.g), 'open_comments', f.open_comments, 'all_comments', f.all_comments, 'last_activity', f.last_activity,
          'version_no', (select v.version_no from content_versions v where v.id = (f.g).current_version_id),
          'task', case when f.task_id is null then null else jsonb_build_object('id', f.task_id, 'priority', f.priority, 'due_at', f.due_at,
                  'assignee_id', f.assignee_id, 'assignee', (select coalesce(p.display_name, u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = f.assignee_id)) end)
          order by case (f.g).editorial_status when 'in_review' then 0 when 'changes_requested' then 1 when 'draft' then 2 else 3 end,
                   case f.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 when 'low' then 3 else 2 end, f.due_day, (f.g).n)
        from filtered f), '[]'),
      'counts', (select jsonb_object_agg(s, (select count(*) from guioes g where g.client_id = p_ws and g.editorial_status = s))
                   from unnest(array['draft', 'in_review', 'changes_requested', 'approved', 'rejected']) s),
      'assignees', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', b.assignee_id,
                      'label', (select coalesce(p.display_name, u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = b.assignee_id)))
                      filter (where b.assignee_id is not null), '[]') from base b),
      'today', today)
  );
end $$;

revoke all on function public.content_comments_guard(), public._comment_json(public.content_comments) from public, anon, authenticated;
revoke all on function public.content_comments(text, text), public.content_comment_add(text, text, text, text, uuid[], uuid, text),
  public.content_comment_resolve(uuid, boolean, text), public.review_inbox(text, jsonb, text) from public;
-- anon só para o código de equipa (as funções recusam sem token válido ou sessão)
grant execute on function public.content_comments(text, text), public.content_comment_add(text, text, text, text, uuid[], uuid, text),
  public.content_comment_resolve(uuid, boolean, text), public.review_inbox(text, jsonb, text) to anon, authenticated;

/* Rollback (compatível): repor legacy_can de 20261029074048; repor notifications_kind_check sem script_mention/script_comment
   (depois de apagar essas notificações);
drop function public.review_inbox(text, jsonb, text), public.content_comment_resolve(uuid, boolean, text),
  public.content_comment_add(text, text, text, text, uuid[], uuid, text), public.content_comments(text, text), public._comment_json(public.content_comments);
drop trigger content_comments_guard on public.content_comments; drop function public.content_comments_guard();
-- contract posterior: drop table public.content_comments; */
