-- W2-08 · Blocos personalizados no teleprompter (FR-03-02). O corpo pode dividir-se em blocos com nome: uma linha
-- "## Nome" começa um bloco novo (chave x_<nome>), o texto antes da primeira marca é o Body. O texto continua a ser o corpo
-- versionado do guião (sem coluna nova). Takes, marcas de tempo, saltos de bloco e retoma aceitam as chaves novas.
-- Expand: só alarga o que é aceite. Rollback no fim.

-- hook_N, body, cta ou x_<slug> (minúsculas, números e _, até 24)
create or replace function public._block_key_ok(p text) returns boolean language sql immutable as $$
  select p ~ '^(hook_[1-9]|body|cta|x_[a-z0-9_]{1,24})$'
$$;

-- Chave de um bloco personalizado a partir do nome (igual a blockSlug em src/lib/recording.ts)
create or replace function public._block_slug(p_label text) returns text language sql immutable as $$
  select coalesce(nullif(left(btrim(regexp_replace(translate(lower(btrim(p_label)), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
                                                   '[^a-z0-9]+', '_', 'g'), '_'), 24), ''), 'bloco')
$$;

-- Blocos de um guião pela ordem de gravação (igual a blocksOf em src/lib/recording.ts)
create or replace function public._content_block_keys(p_hooks jsonb, p_corpo text, p_cta text) returns text[] language plpgsql immutable as $$
declare hooks text[] := '{}'; parts text[] := '{}'; i int := 0; h jsonb; line text; pre boolean := false; inpart boolean := false; k text; base text; n int;
begin
  for h in select * from jsonb_array_elements(coalesce(p_hooks, '[]'::jsonb)) loop
    i := i + 1;
    if btrim(coalesce(h->>'text', '')) <> '' then hooks := hooks || ('hook_' || i); end if;
  end loop;
  foreach line in array string_to_array(coalesce(p_corpo, ''), E'\n') loop
    if line ~ '^\s*##\s*\S' then
      base := 'x_' || public._block_slug(regexp_replace(line, '^\s*##\s*', '')); k := base; n := 1;
      while k = any(parts) loop n := n + 1; k := left(base, 23) || '_' || n; end loop;
      parts := parts || k; inpart := true;
    elsif not inpart and btrim(line) <> '' then
      pre := true;
    end if;
  end loop;
  return hooks || (case when pre then array['body'] else '{}'::text[] end) || parts
         || (case when btrim(coalesce(p_cta, '')) <> '' then array['cta'] else '{}'::text[] end);
end $$;

alter table public.takes drop constraint if exists takes_block_key_check;
alter table public.takes add constraint takes_block_key_check check (public._block_key_ok(block_key));
alter table public.recording_marks drop constraint if exists recording_marks_block_key_check;
alter table public.recording_marks add constraint recording_marks_block_key_check check (block_key is null or public._block_key_ok(block_key));

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
      if not public._block_key_ok(b) then raise exception 'bloco_invalido: %', b using errcode = '22023'; end if;
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

create or replace function public.recording_progress(p_session uuid, p_content text, p_block text, p_pct real, p_token text default null)
returns void language plpgsql security definer set search_path = public as $$
declare s recording_sessions; n integer;
begin
  select * into s from recording_sessions where id = p_session;
  if s.id is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._content_require('recording.use', s.workspace_id, p_token, 'recording.progress', s.id::text);
  if s.closed_at is not null then return; end if;
  if p_pct is null or p_pct < 0 or p_pct > 1 then raise exception 'progresso_invalido' using errcode = '22023'; end if;
  if p_block is not null and not public._block_key_ok(p_block) then raise exception 'bloco_invalido' using errcode = '22023'; end if;
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
  if p_block is null or not public._block_key_ok(p_block) then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from recording_session_items where session_id = s.id and content_id = p_content) then
    raise exception 'item_desconhecido' using errcode = '22023';
  end if;
  select * into g from guioes where id = p_content;
  if g.editorial_status in ('rejected','archived') then raise exception 'nao_elegivel' using errcode = '22023'; end if;
  if p_block like 'hook_%' and substr(p_block, 6)::integer > jsonb_array_length(coalesce(g.hooks, '[]'::jsonb)) then
    raise exception 'bloco_invalido' using errcode = '22023';
  end if;
  if p_block = 'cta' and coalesce(btrim(g.cta), '') = '' then raise exception 'bloco_invalido' using errcode = '22023'; end if;
  -- blocos do corpo (body e personalizados) têm de existir no texto atual do guião
  if (p_block = 'body' or p_block like 'x\_%') and not (p_block = any(public._content_block_keys(g.hooks, g.corpo, g.cta))) then
    raise exception 'bloco_invalido' using errcode = '22023'; end if;
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
    if b is not null and not public._block_key_ok(b) then raise exception 'marca_invalida' using errcode = '22023'; end if;
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

revoke all on function public._block_key_ok(text), public._block_slug(text), public._content_block_keys(jsonb, text, text) from public, anon, authenticated;

/* Rollback (compatível enquanto não houver takes nem marcas com chaves x_): repor as quatro funções de 20261028211702 e
   20261029165727 e as checks '^(hook_[1-9]|body|cta)$'; drop function public._content_block_keys(jsonb, text, text),
   public._block_slug(text), public._block_key_ok(text). */
