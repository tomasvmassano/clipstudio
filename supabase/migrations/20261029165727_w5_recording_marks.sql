-- W5-01 · Tempos de gravação (ING-03, base da linha de edição): o teleprompter regista quando cada guião e cada bloco
-- começa a ser lido, pausa, muda de bloco, marca take e é confirmado. Com o relógio do dispositivo e do servidor,
-- dá as janelas de tempo que o corte automático vai usar (alinhadas depois com a transcrição e o áudio da câmara).
-- Expand: tabela e funções novas.

create table if not exists public.recording_marks (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  session_id uuid not null references public.recording_sessions(id),
  content_id text references public.guioes(id),
  block_key text check (block_key is null or block_key ~ '^(hook_[1-9]|body|cta)$'),
  kind text not null check (kind in ('open', 'play', 'pause', 'block', 'take', 'recorded', 'not_recorded', 'exit')),
  client_at timestamptz not null,
  server_at timestamptz not null default now(),
  device_id text check (device_id is null or char_length(device_id) <= 64),
  client_ref uuid not null,
  actor_kind text not null,
  actor_label text,
  unique (workspace_id, client_ref)
);
create index if not exists recording_marks_session on public.recording_marks (session_id, client_at, id);
alter table public.recording_marks enable row level security;
revoke all on public.recording_marks from anon, authenticated;   -- só pelas RPCs

create or replace function public.recording_marks_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'marcas_append_only' using errcode = '42501'; end $$;
drop trigger if exists recording_marks_append_only on public.recording_marks;
create trigger recording_marks_append_only before update or delete on public.recording_marks for each row execute function public.recording_marks_append_only();

-- Envia um lote de marcas (até 200). Idempotente por client_ref: o dispositivo reenvia sem duplicar (offline).
create or replace function public.recording_marks_add(p_session uuid, p_marks jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s recording_sessions; m jsonb; n int := 0; dup int := 0; at timestamptz; k text; c text; b text;
begin
  select * into s from recording_sessions where id = p_session;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.use', s.workspace_id, p_token, 'recording.marks', s.id::text);
  if jsonb_typeof(p_marks) <> 'array' or jsonb_array_length(p_marks) = 0 then raise exception 'marcas_vazias' using errcode = '22023'; end if;
  if jsonb_array_length(p_marks) > 200 then raise exception 'demasiadas_marcas' using errcode = '22023'; end if;
  for m in select * from jsonb_array_elements(p_marks) loop
    k := m->>'kind'; c := nullif(m->>'content', ''); b := nullif(m->>'block', '');
    begin at := (m->>'at')::timestamptz; exception when others then raise exception 'marca_invalida' using errcode = '22023'; end;
    if (m->>'ref') is null or (m->>'ref') !~ '^[0-9a-f-]{36}$' then raise exception 'marca_invalida' using errcode = '22023'; end if;
    if k is null or k not in ('open', 'play', 'pause', 'block', 'take', 'recorded', 'not_recorded', 'exit') then raise exception 'marca_invalida' using errcode = '22023'; end if;
    if b is not null and b !~ '^(hook_[1-9]|body|cta)$' then raise exception 'marca_invalida' using errcode = '22023'; end if;
    -- relógio do dispositivo: aceita desde a véspera da sessão até 10 minutos no futuro (offline envia depois)
    if at < (s.date - 1)::timestamptz or at > now() + interval '10 minutes' then raise exception 'marca_fora_de_tempo' using errcode = '22023'; end if;
    if c is not null and not exists (select 1 from recording_session_items i where i.session_id = s.id and i.content_id = c) then
      raise exception 'item_desconhecido' using errcode = '22023'; end if;
    insert into recording_marks (workspace_id, session_id, content_id, block_key, kind, client_at, device_id, client_ref, actor_kind, actor_label)
    values (s.workspace_id, s.id, c, b, k, at, left(m->>'device', 64), (m->>'ref')::uuid, a->>'kind', a->>'label')
    on conflict (workspace_id, client_ref) do nothing;
    if found then n := n + 1; else dup := dup + 1; end if;
  end loop;
  return jsonb_build_object('inserted', n, 'duplicates', dup);
end $$;

-- Linha do tempo de uma sessão: por guião, as janelas de leitura de cada bloco (de "play" ou "mudança de bloco"
-- até à marca seguinte), takes e confirmação. É o que o corte automático lê (ING-03).
create or replace function public.recording_timeline(p_session uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s recording_sessions;
begin
  select * into s from recording_sessions where id = p_session;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  if not (public.ws_can('recording.use', s.workspace_id, p_token) or public.ws_can('scripts.read', s.workspace_id, p_token)) then
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  return (
    with m as (
      select r.*, lead(r.client_at) over (partition by coalesce(r.device_id, '') order by r.client_at, r.id) as nxt
        from recording_marks r where r.session_id = s.id
    ), seg as (
      select content_id, block_key, client_at as start_at, nxt as end_at, device_id
        from m where kind in ('play', 'block') and content_id is not null and nxt is not null and nxt > client_at
    )
    select jsonb_build_object(
      'session', jsonb_build_object('id', s.id, 'date', s.date, 'opened_at', s.opened_at, 'closed_at', s.closed_at),
      'marks', (select count(*) from recording_marks r where r.session_id = s.id),
      'first_at', (select min(client_at) from recording_marks r where r.session_id = s.id),
      'last_at', (select max(client_at) from recording_marks r where r.session_id = s.id),
      'items', coalesce((select jsonb_agg(x order by (x->>'first_at') nulls last, (x->>'n')::int) from (
        select jsonb_build_object(
          'content_id', i.content_id, 'n', g.n, 'tema', g.tema, 'position', i.position,
          'first_at', (select min(start_at) from seg where seg.content_id = i.content_id),
          'read_seconds', (select coalesce(round(extract(epoch from sum(end_at - start_at))), 0) from seg where seg.content_id = i.content_id),
          'segments', coalesce((select jsonb_agg(jsonb_build_object('block', block_key, 'start', start_at, 'end', end_at,
                          'seconds', round(extract(epoch from end_at - start_at)::numeric, 1), 'device', device_id) order by start_at)
                        from seg where seg.content_id = i.content_id), '[]'),
          'takes', coalesce((select jsonb_agg(jsonb_build_object('block', t.block_key, 'n', t.take_number, 'at', t.created_at, 'status', t.status, 'selected', t.selected)
                        order by t.created_at) from takes t where t.session_id = s.id and t.content_id = i.content_id), '[]'),
          -- última decisão no teleprompter: "gravado" conta só se não foi desfeito depois
          'recorded_at', (select case when r.kind = 'recorded' then r.client_at end from recording_marks r
                           where r.session_id = s.id and r.content_id = i.content_id and r.kind in ('recorded', 'not_recorded')
                           order by r.client_at desc, r.id desc limit 1)) x
        from recording_session_items i join guioes g on g.id = i.content_id
       where i.session_id = s.id) q), '[]')));
end $$;

revoke all on function public.recording_marks_append_only() from public, anon, authenticated;
revoke all on function public.recording_marks_add(uuid, jsonb, text), public.recording_timeline(uuid, text) from public;
grant execute on function public.recording_marks_add(uuid, jsonb, text), public.recording_timeline(uuid, text) to anon, authenticated;

/* Rollback (compatível): drop function public.recording_timeline(uuid, text), public.recording_marks_add(uuid, jsonb, text);
drop trigger recording_marks_append_only on public.recording_marks; drop function public.recording_marks_append_only();
-- contract posterior: drop table public.recording_marks; */
