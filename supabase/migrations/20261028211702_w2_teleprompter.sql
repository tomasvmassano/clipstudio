-- W2-05 Teleprompter (PRD M03 FR-03-01/02/03/04/05/06/07, §20 "Teleprompter", FL-03, QA-06; AGENTS §6, §9).
-- Sessões de gravação por cliente e dia (partilhadas entre dispositivos), fila ordenável com conteúdos e blocos saltados,
-- takes por bloco (Hook N, Body, CTA) ligados à versão exata lida, seleção de take, notas, progresso para retoma segura e
-- preferências do teleprompter por utilizador e dispositivo.
-- Marcar takes NÃO altera o estado editorial nem o de produção: "gravado" continua a exigir confirmação explícita
-- (content_production). Ler 80% fica só como telemetria (domain_events recording.viewed_80).
-- Só aditivo (expand): o código em main não usa estas tabelas. Rollback: bloco no fim.

create table public.recording_sessions (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  date date not null,
  opened_by uuid references auth.users(id) on delete set null,
  opened_kind text not null check (opened_kind in ('user','legacy_code')),
  opened_label text,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  last_content_id text references public.guioes(id) on delete set null,
  last_block text,
  last_pct real check (last_pct is null or last_pct between 0 and 1),
  last_at timestamptz
);
-- Uma sessão aberta por cliente e dia: dois dispositivos (iPad + computador) entram na mesma.
create unique index recording_sessions_open on public.recording_sessions (workspace_id, date) where closed_at is null;
create index recording_sessions_ws_date on public.recording_sessions (workspace_id, date desc);

create table public.recording_session_items (
  session_id uuid not null references public.recording_sessions(id) on delete restrict,
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  position integer not null,
  skipped boolean not null default false,
  skipped_blocks text[] not null default '{}',
  viewed_80_at timestamptz,
  added_at timestamptz not null default now(),
  primary key (session_id, content_id)
);

create table public.takes (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  session_id uuid not null references public.recording_sessions(id) on delete restrict,
  content_id text not null references public.guioes(id) on delete restrict,
  version_id uuid references public.content_versions(id) on delete restrict,
  block_key text not null check (block_key ~ '^(hook_[1-9]|body|cta)$'),
  take_number integer not null check (take_number > 0),
  status text not null default 'ok' check (status in ('ok','discarded')),
  selected boolean not null default false,
  notes text check (notes is null or length(notes) <= 2000),
  client_ref uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_kind text not null check (created_kind in ('user','legacy_code')),
  created_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not (selected and status = 'discarded'))
);
create unique index takes_number on public.takes (content_id, block_key, take_number);
create unique index takes_client_ref on public.takes (workspace_id, client_ref);
create unique index takes_selected on public.takes (content_id, block_key) where selected;
create index takes_content on public.takes (content_id, created_at);

create table public.teleprompter_prefs (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (device_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  prefs jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

-- Pertença: item, take e versão têm de ser do mesmo cliente da sessão.
create or replace function public.recording_same_ws() returns trigger language plpgsql set search_path = public as $$
begin
  if new.workspace_id is distinct from (select workspace_id from recording_sessions where id = new.session_id)
     or new.workspace_id is distinct from (select client_id from guioes where id = new.content_id)
     or (tg_table_name = 'takes' and new.version_id is not null
         and new.workspace_id is distinct from (select workspace_id from content_versions where id = new.version_id)) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.workspace_id, new.session_id, new.content_id) is distinct from (old.workspace_id, old.session_id, old.content_id) then
    raise exception 'imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger recording_items_ws before insert or update on public.recording_session_items for each row execute function public.recording_same_ws();
create trigger takes_ws before insert or update on public.takes for each row execute function public.recording_same_ws();

-- Takes nunca se apagam (rejeitados ficam como "discarded"); número, bloco e versão são imutáveis.
create or replace function public.takes_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'take_nao_apagavel' using errcode = '42501'; end if;
  if (new.block_key, new.take_number, new.version_id, new.client_ref, new.created_at)
     is distinct from (old.block_key, old.take_number, old.version_id, old.client_ref, old.created_at) then
    raise exception 'imutavel' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger takes_guard before update or delete on public.takes for each row execute function public.takes_guard();

alter table public.recording_sessions enable row level security;
alter table public.recording_session_items enable row level security;
alter table public.takes enable row level security;
alter table public.teleprompter_prefs enable row level security;
revoke all on public.recording_sessions, public.recording_session_items, public.takes, public.teleprompter_prefs from anon, authenticated;
grant select on public.recording_sessions, public.recording_session_items, public.takes, public.teleprompter_prefs to authenticated;
create policy recording_sessions_select on public.recording_sessions for select to authenticated using (public.authorize('recording.use', workspace_id));
create policy recording_items_select on public.recording_session_items for select to authenticated using (public.authorize('recording.use', workspace_id));
create policy takes_select on public.takes for select to authenticated using (public.authorize('recording.use', workspace_id));
create policy teleprompter_prefs_select on public.teleprompter_prefs for select to authenticated using (user_id = auth.uid());

-- ───────────── leitura ─────────────
create or replace function public._tp_eligible(g guioes, p_date date, p_req boolean) returns boolean language sql immutable as $$
  select g.editorial_status not in ('rejected','archived') and (not p_req or g.editorial_status = 'approved')
     and (g.date = p_date or (g.date < p_date and g.production_status <> 'recorded'));
$$;

create or replace function public._tp_session_row(p_session uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) || jsonb_build_object(
    'require_approval', c.require_approval_to_record,
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'content_id', i.content_id, 'position', i.position, 'skipped', i.skipped, 'skipped_blocks', to_jsonb(i.skipped_blocks),
                'carried', g.date < s.date,
                'content', jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'formato', g.formato, 'hooks', g.hooks,
                                              'corpo', g.corpo, 'cta', g.cta, 'editorial_status', g.editorial_status,
                                              'production_status', g.production_status, 'current_version_id', g.current_version_id),
                'takes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'block_key', t.block_key, 'take_number', t.take_number,
                                  'status', t.status, 'selected', t.selected, 'notes', t.notes, 'version_id', t.version_id,
                                  'session_id', t.session_id, 'created_label', t.created_label, 'created_at', t.created_at)
                                  order by t.block_key, t.take_number), '[]')
                          from takes t where t.content_id = g.id))
              order by i.position), '[]')
              from recording_session_items i join guioes g on g.id = i.content_id
              where i.session_id = s.id and g.editorial_status not in ('rejected','archived')))
  from recording_sessions s join clients c on c.id = s.workspace_id where s.id = p_session;
$$;

-- Abre (ou junta-se à) sessão do dia e acrescenta à fila os conteúdos elegíveis que ainda não estão lá.
create or replace function public.recording_session_open(p_ws text, p_date date, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); sid uuid; req boolean; nxt integer;
begin
  perform public._content_require('recording.use', p_ws, p_token, 'recording.session_open', p_date::text);
  if p_date is null then raise exception 'data_obrigatoria' using errcode = '22023'; end if;
  select require_approval_to_record into req from clients where id = p_ws;
  select id into sid from recording_sessions where workspace_id = p_ws and date = p_date and closed_at is null;
  if sid is null then
    insert into recording_sessions (workspace_id, date, opened_by, opened_kind, opened_label)
    values (p_ws, p_date, (a->>'uid')::uuid, a->>'kind', a->>'label')
    on conflict (workspace_id, date) where closed_at is null do nothing
    returning id into sid;
    if sid is null then
      select id into sid from recording_sessions where workspace_id = p_ws and date = p_date and closed_at is null;
    else
      insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
      values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'recording.session_opened', 'recording_session', sid::text,
              jsonb_build_object('date', p_date));
      insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
      values (p_ws, 'recording.session_opened', 'recording_session', sid::text, jsonb_build_object('date', p_date, 'actor_kind', a->>'kind'));
    end if;
  end if;
  perform 1 from recording_sessions where id = sid for update;
  select coalesce(max(position), 0) into nxt from recording_session_items where session_id = sid;
  insert into recording_session_items (session_id, workspace_id, content_id, position)
  select sid, p_ws, g.id, nxt + row_number() over (order by (g.date < p_date) desc, g.date, g.n)
    from guioes g
   where g.client_id = p_ws and public._tp_eligible(g, p_date, coalesce(req, false))
     and not exists (select 1 from recording_session_items i where i.session_id = sid and i.content_id = g.id);
  return public._tp_session_row(sid);
end $$;

-- Reordenar a fila e saltar conteúdos/blocos. p_items = [{content_id, skipped?, skipped_blocks?}] pela nova ordem.
create or replace function public.recording_queue_set(p_session uuid, p_items jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s recording_sessions; it jsonb; pos integer := 0; b text;
begin
  select * into s from recording_sessions where id = p_session for update;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.use', s.workspace_id, p_token, 'recording.queue_set', s.id::text);
  if s.closed_at is not null then raise exception 'sessao_fechada' using errcode = '22023'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 then raise exception 'fila_invalida' using errcode = '22023'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if not exists (select 1 from recording_session_items where session_id = s.id and content_id = it->>'content_id') then
      raise exception 'item_desconhecido' using errcode = '22023';
    end if;
    for b in select jsonb_array_elements_text(coalesce(it->'skipped_blocks', '[]'::jsonb)) loop
      if b !~ '^(hook_[1-9]|body|cta)$' then raise exception 'bloco_invalido: %', b using errcode = '22023'; end if;
    end loop;
  end loop;
  -- Posições temporárias negativas para reordenar sem colisões; os não referidos ficam no fim pela ordem antiga.
  for it in select * from jsonb_array_elements(p_items) loop
    pos := pos + 1;
    update recording_session_items set position = -pos,
           skipped = coalesce((it->>'skipped')::boolean, skipped),
           skipped_blocks = case when it ? 'skipped_blocks'
                                 then coalesce((select array_agg(distinct x) from jsonb_array_elements_text(it->'skipped_blocks') x), '{}')
                                 else skipped_blocks end
     where session_id = s.id and content_id = it->>'content_id';
  end loop;
  update recording_session_items i set position = q.rn
    from (select content_id, row_number() over (order by (position < 0) desc, case when position < 0 then -position else position end) rn
            from recording_session_items where session_id = s.id) q
   where i.session_id = s.id and i.content_id = q.content_id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', s.workspace_id, 'recording.queue_set', 'recording_session', s.id::text, p_items);
  return public._tp_session_row(s.id);
end $$;

-- Progresso para retoma segura (chamado com throttle). Ler 80% regista telemetria uma vez por conteúdo e sessão; não marca gravado.
create or replace function public.recording_progress(p_session uuid, p_content text, p_block text, p_pct real, p_token text default null)
returns void language plpgsql security definer set search_path = public as $$
declare s recording_sessions; n integer;
begin
  select * into s from recording_sessions where id = p_session;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.use', s.workspace_id, p_token, 'recording.progress', s.id::text);
  if s.closed_at is not null then return; end if;
  if p_pct is null or p_pct < 0 or p_pct > 1 then raise exception 'progresso_invalido' using errcode = '22023'; end if;
  if p_block is not null and p_block !~ '^(hook_[1-9]|body|cta)$' then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from recording_session_items where session_id = s.id and content_id = p_content) then
    raise exception 'item_desconhecido' using errcode = '22023';
  end if;
  update recording_sessions set last_content_id = p_content, last_block = p_block, last_pct = p_pct, last_at = now() where id = s.id;
  if p_pct >= 0.8 then
    update recording_session_items set viewed_80_at = now()
     where session_id = s.id and content_id = p_content and viewed_80_at is null;
    get diagnostics n = row_count;
    if n > 0 then
      insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
      values (s.workspace_id, 'recording.viewed_80', 'content', p_content, jsonb_build_object('session_id', s.id));
    end if;
  end if;
end $$;

create or replace function public.recording_session_close(p_session uuid, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s recording_sessions;
begin
  select * into s from recording_sessions where id = p_session for update;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.use', s.workspace_id, p_token, 'recording.session_close', s.id::text);
  if s.closed_at is null then
    update recording_sessions set closed_at = now() where id = s.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', s.workspace_id, 'recording.session_closed', 'recording_session', s.id::text);
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (s.workspace_id, 'recording.session_closed', 'recording_session', s.id::text, jsonb_build_object('date', s.date));
  end if;
  return public._tp_session_row(s.id);
end $$;

-- ───────────── takes ─────────────
-- Idempotente por client_ref: repetir o pedido (offline, retry) devolve o mesmo take, nunca cria outro.
create or replace function public.take_create(p_session uuid, p_content text, p_block text, p_client_ref uuid,
                                              p_notes text default null, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s recording_sessions; t takes; g guioes; v uuid;
begin
  select * into s from recording_sessions where id = p_session;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.confirm', s.workspace_id, p_token, 'take.create', p_content);
  if p_client_ref is null then raise exception 'client_ref_obrigatorio' using errcode = '22023'; end if;
  select * into t from takes where workspace_id = s.workspace_id and client_ref = p_client_ref;
  if t.id is not null then
    if t.content_id <> p_content or t.block_key <> p_block then raise exception 'client_ref_reutilizado' using errcode = '22023'; end if;
    return to_jsonb(t);
  end if;
  if s.closed_at is not null then raise exception 'sessao_fechada' using errcode = '22023'; end if;
  if p_block is null or p_block !~ '^(hook_[1-9]|body|cta)$' then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from recording_session_items where session_id = s.id and content_id = p_content) then
    raise exception 'item_desconhecido' using errcode = '22023';
  end if;
  select * into g from guioes where id = p_content;
  if g.editorial_status in ('rejected','archived') then raise exception 'nao_elegivel' using errcode = '22023'; end if;
  if p_block like 'hook_%' and substr(p_block, 6)::integer > jsonb_array_length(coalesce(g.hooks, '[]'::jsonb)) then
    raise exception 'bloco_invalido' using errcode = '22023';
  end if;
  if p_block = 'cta' and coalesce(btrim(g.cta), '') = '' then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  -- O take fica ligado à versão exata que estava no ecrã (fotografa a cópia de trabalho se ainda não houver versão igual).
  v := public._content_snapshot(g.id, a, 'take');
  perform pg_advisory_xact_lock(hashtext('take:' || p_content || ':' || p_block));
  insert into takes (workspace_id, session_id, content_id, version_id, block_key, take_number, notes, client_ref, created_by, created_kind, created_label)
  values (s.workspace_id, s.id, p_content, v, p_block,
          coalesce((select max(take_number) from takes where content_id = p_content and block_key = p_block), 0) + 1,
          nullif(btrim(p_notes), ''), p_client_ref, (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into t;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', s.workspace_id, 'take.recorded', 'take', t.id::text,
          jsonb_build_object('content_id', p_content, 'block', p_block, 'take_number', t.take_number, 'version_id', v, 'session_id', s.id));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (s.workspace_id, 'take.recorded', 'take', t.id::text,
          jsonb_build_object('content_id', p_content, 'block', p_block, 'take_number', t.take_number, 'session_id', s.id));
  return to_jsonb(t);
end $$;

-- Selecionar (desmarca os outros do mesmo bloco), descartar/recuperar e notas.
create or replace function public.take_update(p_take uuid, p_patch jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t takes; k text; before jsonb;
begin
  select * into t from takes where id = p_take for update;
  if t.id is null then raise exception 'take_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('recording.confirm', t.workspace_id, p_token, 'take.update', t.id::text);
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('selected','status','notes') then raise exception 'campo_invalido: %', k using errcode = '22023'; end if;
  end loop;
  if p_patch ? 'status' and p_patch->>'status' not in ('ok','discarded') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  if p_patch ? 'notes' and length(p_patch->>'notes') > 2000 then raise exception 'notas_demasiado_longas' using errcode = '22023'; end if;
  before := jsonb_build_object('selected', t.selected, 'status', t.status, 'notes', t.notes);
  if coalesce((p_patch->>'selected')::boolean, false) then
    if coalesce(p_patch->>'status', t.status) = 'discarded' then raise exception 'take_descartado' using errcode = '22023'; end if;
    update takes set selected = false where content_id = t.content_id and block_key = t.block_key and selected and id <> t.id;
  end if;
  update takes set
    status = coalesce(p_patch->>'status', status),
    selected = case when coalesce(p_patch->>'status', status) = 'discarded' then false else coalesce((p_patch->>'selected')::boolean, selected) end,
    notes = case when p_patch ? 'notes' then nullif(btrim(p_patch->>'notes'), '') else notes end
  where id = t.id returning * into t;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', t.workspace_id, 'take.update', 'take', t.id::text, before, p_patch);
  if t.selected and not (before->>'selected')::boolean then
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (t.workspace_id, 'take.selected', 'take', t.id::text, jsonb_build_object('content_id', t.content_id, 'block', t.block_key, 'take_number', t.take_number));
  end if;
  return to_jsonb(t);
end $$;

-- ───────────── preferências (por utilizador e dispositivo; o código de equipa só guarda no próprio dispositivo) ─────────────
create or replace function public._tp_prefs_clean(p jsonb) returns jsonb language plpgsql immutable as $$
declare k text; out jsonb := '{}'::jsonb; act text;
begin
  if jsonb_typeof(p) <> 'object' or length(p::text) > 4000 then raise exception 'preferencias_invalidas' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('speed','font','line_height','margin','mirror_h','mirror_v','contrast','keys','confirm_on_advance') then
      raise exception 'preferencia_desconhecida: %', k using errcode = '22023';
    end if;
  end loop;
  if p ? 'speed' then out := out || jsonb_build_object('speed', least(greatest((p->>'speed')::integer, 1), 10)); end if;
  if p ? 'font' then out := out || jsonb_build_object('font', least(greatest((p->>'font')::integer, 32), 96)); end if;
  if p ? 'line_height' then out := out || jsonb_build_object('line_height', least(greatest((p->>'line_height')::numeric, 1.0), 2.2)); end if;
  if p ? 'margin' then out := out || jsonb_build_object('margin', least(greatest((p->>'margin')::integer, 0), 25)); end if;
  if p ? 'mirror_h' then out := out || jsonb_build_object('mirror_h', (p->>'mirror_h')::boolean); end if;
  if p ? 'mirror_v' then out := out || jsonb_build_object('mirror_v', (p->>'mirror_v')::boolean); end if;
  if p ? 'confirm_on_advance' then out := out || jsonb_build_object('confirm_on_advance', (p->>'confirm_on_advance')::boolean); end if;
  if p ? 'contrast' then
    if p->>'contrast' not in ('normal','alto','ambar') then raise exception 'contraste_invalido' using errcode = '22023'; end if;
    out := out || jsonb_build_object('contrast', p->>'contrast');
  end if;
  if p ? 'keys' then
    if jsonb_typeof(p->'keys') <> 'object' then raise exception 'atalhos_invalidos' using errcode = '22023'; end if;
    for act in select jsonb_object_keys(p->'keys') loop
      if act not in ('play','faster','slower','next','prev','next_block','prev_block','take','mirror','font_up','font_down','fullscreen','exit') then
        raise exception 'atalho_desconhecido: %', act using errcode = '22023';
      end if;
      if jsonb_typeof(p->'keys'->act) <> 'array' or jsonb_array_length(p->'keys'->act) > 4
         or exists (select 1 from jsonb_array_elements(p->'keys'->act) e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > 20) then
        raise exception 'atalhos_invalidos' using errcode = '22023';
      end if;
    end loop;
    out := out || jsonb_build_object('keys', p->'keys');
  end if;
  return out;
end $$;

create or replace function public.tp_prefs_get(p_device text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return null; end if;
  return (select prefs from teleprompter_prefs where user_id = auth.uid() and device_id = p_device);
end $$;

create or replace function public.tp_prefs_set(p_device text, p_prefs jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb;
begin
  if auth.uid() is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_device is null or p_device !~ '^[A-Za-z0-9_-]{8,64}$' then raise exception 'dispositivo_invalido' using errcode = '22023'; end if;
  c := public._tp_prefs_clean(p_prefs);
  insert into teleprompter_prefs (user_id, device_id, prefs) values (auth.uid(), p_device, c)
  on conflict (user_id, device_id) do update set prefs = excluded.prefs, updated_at = now();
  return c;
end $$;

revoke all on function public.recording_same_ws(), public.takes_guard(), public._tp_eligible(guioes, date, boolean),
  public._tp_session_row(uuid), public._tp_prefs_clean(jsonb) from public, anon, authenticated;
revoke all on function public.recording_session_open(text,date,text), public.recording_queue_set(uuid,jsonb,text),
  public.recording_progress(uuid,text,text,real,text), public.recording_session_close(uuid,text),
  public.take_create(uuid,text,text,uuid,text,text), public.take_update(uuid,jsonb,text),
  public.tp_prefs_get(text), public.tp_prefs_set(text,jsonb) from public;
grant execute on function public.recording_session_open(text,date,text), public.recording_queue_set(uuid,jsonb,text),
  public.recording_progress(uuid,text,text,real,text), public.recording_session_close(uuid,text),
  public.take_create(uuid,text,text,uuid,text,text), public.take_update(uuid,jsonb,text) to anon, authenticated;
grant execute on function public.tp_prefs_get(text), public.tp_prefs_set(text,jsonb) to authenticated;

/* Rollback (exportar takes antes, se já houver takes reais):
drop function recording_session_open, recording_queue_set, recording_progress, recording_session_close, take_create, take_update,
  tp_prefs_get, tp_prefs_set, _tp_prefs_clean, _tp_session_row, _tp_eligible, takes_guard, recording_same_ws;
drop table takes, recording_session_items, recording_sessions, teleprompter_prefs;
*/
