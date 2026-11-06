-- W10-20 · STU-03 (+ contrato do STU-02, EDL-01, EDL-02, ING-03): pacote de edição por guião, disparado quando chegam as
-- gravações desse guião (frente + lado). ADR-0070.
-- Expand (aditivo e compatível com o código do main e com o worker de hoje). Nada disto corre com a flag desligada.
--   1. Flag edit.package_script (por cliente, default 'owner').
--   2. recording_clips (fechada): que ficheiro da Biblioteca é a gravação de que guião e de que câmara (frente/lado), com a
--      sessão do teleprompter quando se sabe e a origem (upload, biblioteca; 'agente' fica reservado ao agente de estúdio,
--      STU-02). Uma gravação atual por guião e câmara; ligar outra substitui a anterior (auditado).
--   3. package_script_settings (fechada): por cliente, pacote automático ao chegarem as duas gravações e exportar todos
--      automaticamente quando o pacote do guião acaba, estilo. O automático corre "em nome de" quem gravou as definições
--      (enabled_by) e volta a verificar, a cada disparo, que essa pessoa ainda tem as capacidades e as flags (falha fechada).
--   4. package_script_status (fechada): último disparo automático por guião (job criado ou porque não correu), para a app.
--   5. edit_package_script_request: pede o pacote de UM guião a partir das gravações ligadas. Mesmas regras do pacote da
--      sessão (edit.timeline, R2, flag edit.studio) e o mesmo input do job (o worker de hoje já o processa: a janela do único
--      guião sai da transcrição do corte), mais mode = 'script' e guiao_id (o worker novo transcreve só o corte e usa o
--      ficheiro todo como janela: numeiro-engine stu03-pacote-por-guiao) e input.marks vazio (as marcas do teleprompter
--      são da gravação longa, não do corte; o trigger de W10-17 não as junta quando a chave já existe).
--      Idempotente por (guião, versões das duas gravações, estilo e versão do estilo); chave própria 'package_script:'.
--      Não reescreve edit_package_request (W10-17 e W10-18 mexem nela): a montagem do job é copiada (_package_script_enqueue)
--      e usa _edit_package_fill (W10-18) só se essa função existir e a flag edit.ai_visuals estiver ligada.
--   6. Disparo automático (_package_script_auto): depois de ligar uma gravação (media_clip_link) e quando uma versão nova de
--      uma gravação ligada fica pronta (trigger em media_assets.current_version_id). Locks por ativo e por guião evitam que
--      as duas pontas (ligar e ficar pronta ao mesmo tempo) se percam uma à outra. Nunca falha a transação de quem dispara.
--   7. Exportar automático (_package_script_after_done): job por guião acabado + definição ligada -> um export por vídeo,
--      com as mesmas regras de edit_export_request (copiadas em _package_script_export; não a reescreve).
--   8. edit_package_list deixa de listar os pacotes por guião (têm a lista própria): sem pacotes por guião, igual a hoje.
-- Sem flag: nenhuma RPC nova responde (55000), os triggers não fazem nada e edit_package_list devolve o mesmo de hoje.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('edit.package_script', 'Pacote por guião', 'Edição', 'ws', 'owner',
   'Pacote de edição de um guião de cada vez a partir das gravações curtas desse guião (frente + lado): pedido à mão ou automático quando chegam as duas, com exportar todos automático opcional (STU-03, ADR-0070). Precisa também de edit.studio e media.r2.')
on conflict (key) do nothing;

create table if not exists public.recording_clips (
  asset_id uuid primary key references public.media_assets(id),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id),
  camera text not null check (camera in ('front', 'side')),
  session_id uuid references public.recording_sessions(id),
  source text not null default 'biblioteca' check (source in ('upload', 'biblioteca', 'agente')),
  linked_by uuid, linked_label text,
  linked_at timestamptz not null default now(),
  unique (workspace_id, content_id, camera)
);
alter table public.recording_clips enable row level security;
revoke all on public.recording_clips from anon, authenticated;

create table if not exists public.package_script_settings (
  workspace_id text primary key references public.clients(id),
  auto_package boolean not null default false,
  auto_export boolean not null default false,
  style text not null default 'S15' check (style ~ '^[A-Za-z0-9_-]{1,40}$'),
  enabled_by uuid,
  updated_by uuid, updated_label text,
  updated_at timestamptz not null default now()
);
alter table public.package_script_settings enable row level security;
revoke all on public.package_script_settings from anon, authenticated;

create table if not exists public.package_script_status (
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id),
  job_id uuid references public.media_jobs(id),
  reason text,
  at timestamptz not null default now(),
  primary key (workspace_id, content_id)
);
alter table public.package_script_status enable row level security;
revoke all on public.package_script_status from anon, authenticated;

create index if not exists media_jobs_package_script on public.media_jobs (workspace_id, (input->>'guiao_id'), created_at desc)
  where kind = 'package' and input->>'mode' = 'script';

-- ─ auxiliares ───────────────────────────────────────────────────────────────────────────────────────────────────────────

-- versão atual de uma gravação ligada, se servir para o pacote (vídeo, R2, pronta, ativo deste cliente)
create or replace function public._package_script_clip(p_ws text, p_guiao text, p_camera text) returns media_versions
language sql stable security definer set search_path = public as $$
  select v.* from recording_clips c join media_assets a on a.id = c.asset_id join media_versions v on v.id = a.current_version_id
   where c.workspace_id = p_ws and c.content_id = p_guiao and c.camera = p_camera and a.workspace_id = p_ws and a.lifecycle = 'ativo'
     and v.workspace_id = p_ws and v.state = 'pronta' and v.storage_provider = 'r2' and v.mime like 'video/%'
$$;

-- O editor e a exportação encontram as câmaras pelo nome do ficheiro (_edit_resolve_cams): outro ficheiro pronto com o
-- mesmo nome noutro ativo (pronto ou a caminho) faria a exportação usar a gravação errada. Devolve o nome repetido ou null.
create or replace function public._package_script_name_clash(p_ws text, v media_versions) returns text
language sql stable security definer set search_path = public as $$
  select v.original_name where exists (
    select 1 from media_versions x join media_assets a on a.id = x.asset_id
     where x.workspace_id = p_ws and x.asset_id <> v.asset_id and x.storage_provider = 'r2' and x.state in ('pendente', 'pronta') and a.lifecycle = 'ativo'
       and x.original_name = regexp_replace(coalesce(v.original_name, ''), '^.*/', ''))
$$;

create or replace function public._package_script_audit(p_ws text, p_uid uuid, p_label text, p_action text, p_type text, p_id text,
                                                        p_before jsonb, p_after jsonb) returns void
language sql security definer set search_path = public as $$
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  select case when auth.uid() is not null and auth.uid() = p_uid then p_uid end,
         case when auth.uid() is not null and auth.uid() = p_uid then 'user' else 'system' end,
         left(coalesce(p_label, public._media_label(p_uid), 'sistema'), 200), c.organization_id, p_ws, p_action, p_type, p_id, p_before, p_after,
         'package_script:' || p_ws || ':' || coalesce(p_id, '')
    from clients c where c.id = p_ws
$$;

-- Monta e enfileira o job do pacote de um guião. Sem verificações de quem pede: só é chamada por edit_package_script_request
-- (depois das verificações da sessão) e por _package_script_auto (depois de verificar quem ligou o automático).
-- O corpo do job é o de edit_package_request (20261106060134_w10_pacote_estilo_alternativas.sql) com um só guião.
create or replace function public._package_script_enqueue(p_ws text, p_guiao text, p_style text, p_uid uuid, p_origin text, p_fill boolean)
returns media_jobs
language plpgsql security definer set search_path = public as $$
declare f media_versions; s media_versions; gs jsonb; k text; j media_jobs; st text := coalesce(nullif(p_style, ''), 'S15');
        lk jsonb; lv int; fill jsonb; nm text; lbl text;
begin
  if st !~ '^[A-Za-z0-9_-]{1,40}$' then raise exception 'estilo_invalido' using errcode = '22023'; end if;
  select jsonb_build_array(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'hooks', g.hooks, 'corpo', g.corpo))
    into gs from guioes g where g.id = p_guiao and g.client_id = p_ws and g.deleted_at is null;
  if gs is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'O guião não é deste cliente ou foi eliminado.'; end if;
  f := public._package_script_clip(p_ws, p_guiao, 'front');
  s := public._package_script_clip(p_ws, p_guiao, 'side');
  if f.id is null or s.id is null then
    raise exception 'gravacoes_em_falta' using errcode = 'P0002',
      detail = format('Falta a gravação %s deste guião pronta na Biblioteca (no R2).',
                      concat_ws(' e a ', case when f.id is null then 'da câmara da frente' end, case when s.id is null then 'da câmara do lado (com o som)' end)); end if;
  if f.id = s.id or f.asset_id = s.asset_id then
    raise exception 'camaras_invalidas' using errcode = '22023', detail = 'A frente e o lado têm de ser gravações diferentes.'; end if;
  if f.original_name = s.original_name then
    raise exception 'nome_repetido' using errcode = '22023', detail = format('As duas gravações chamam-se %s: o editor encontra as câmaras pelo nome. Renomeia uma (ex.: g07_frente.mp4) e carrega de novo.', f.original_name); end if;
  nm := coalesce(public._package_script_name_clash(p_ws, f), public._package_script_name_clash(p_ws, s));
  if nm is not null then
    raise exception 'nome_repetido' using errcode = '22023', detail = format('Há outro ficheiro chamado %s na Biblioteca: o editor e a exportação encontram as câmaras pelo nome. Renomeia a gravação deste guião (ex.: g07_frente.mp4) e carrega de novo.', nm); end if;
  -- aspeto guardado do estilo pedido (versão atual, deste cliente, não arquivado), como em edit_package_request
  select v.look, v.version into lk, lv from edit_styles x
    join edit_style_versions v on v.workspace_id = x.workspace_id and v.key = x.key and v.version = x.current_version
   where x.workspace_id = p_ws and x.key = st and x.status <> 'arquivado' and v.look is not null;
  if lk is not null and nullif(lk->'music', 'null'::jsonb) is not null
     and not exists (select 1 from media_assets m where m.id::text = lk->'music'->>'asset' and m.workspace_id = p_ws and m.kind = 'audio' and m.lifecycle = 'ativo') then
    lk := jsonb_set(lk, '{music}', 'null'::jsonb);
  end if;
  -- visuais e música da IA (W10-18): só se essa migração existir e a flag estiver ligada para quem pede
  if p_fill and to_regprocedure('public._edit_package_fill(text)') is not null then
    execute 'select public._edit_package_fill($1)' into fill using p_ws;
  end if;
  k := 'package_script:' || p_guiao || ':' || f.id || ':' || s.id || ':' || st || coalesce(':v' || lv, '') || case when fill is null then '' else ':ia1' end;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is not null then return j; end if;
  lbl := coalesce(public._media_label(p_uid), 'sistema') || case when p_origin = 'auto' then ' (automático)' else '' end;
  insert into media_jobs (workspace_id, kind, idempotency_key, version_id, input, created_by, created_label, max_attempts)
  values (p_ws, 'package', k, s.id,
          jsonb_build_object('front', jsonb_build_object('version_id', f.id, 'key', f.storage_path, 'name', f.original_name, 'info', f.media_info),
                             'side', jsonb_build_object('version_id', s.id, 'key', s.storage_path, 'name', s.original_name, 'info', s.media_info),
                             'guioes', gs, 'style', st,
                             'mode', 'script', 'guiao_id', p_guiao, 'origin', p_origin,
                             -- marcas vazias: o corte já é só deste guião (o trigger de W10-17 não junta as da gravação longa)
                             'marks', jsonb_build_object('v', 1, 'session', null, 'reason', 'pedido_sem_marcas', 'items', '{}'::jsonb))
          || case when lk is null then '{}'::jsonb else jsonb_build_object('look', lk, 'style_version', lv) end
          || case when fill is null then '{}'::jsonb else jsonb_build_object('fill', fill) end,
          p_uid, left(lbl, 200), 2)
  returning * into j;
  perform public._package_script_audit(p_ws, p_uid, lbl, 'edit.package_script_requested', 'media_job', j.id::text, null,
    jsonb_build_object('guiao_id', p_guiao, 'front', f.id, 'side', s.id, 'style', st, 'style_version', lv, 'origin', p_origin, 'fill', fill is not null));
  return j;
end $$;

-- Export de um vídeo do pacote em nome de p_uid. Mesmo job que edit_export_request (20261106055840_w10_qc_irmas.sql);
-- copiado para não reescrever essa função. Só é chamada por _package_script_after_done depois de verificar p_uid.
create or replace function public._package_script_export(p_ws text, p_asset uuid, p_uid uuid, p_label text) returns media_jobs
language plpgsql security definer set search_path = public as $$
declare d edit_documents; v edit_versions; cams jsonb; missing text; j media_jobs; k text; music jsonb; mv media_versions; vis jsonb; sib jsonb;
begin
  if not public._media_r2(p_ws) then raise exception 'funcionalidade_desligada' using errcode = '55000'; end if;
  select * into d from edit_documents where asset_id = p_asset and workspace_id = p_ws;
  if d.id is null then raise exception 'documento_nao_encontrado' using errcode = 'P0002'; end if;
  select * into v from edit_versions where id = d.current_version_id and document_id = d.id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  cams := public._edit_resolve_cams(p_ws, v.doc);
  select string_agg(coalesce(v.doc->'source'->'cams'->>key, key), ', ') into missing from jsonb_each(cams) where value = 'null'::jsonb;
  if missing is not null or cams = '{}'::jsonb then
    raise exception 'camaras_em_falta' using errcode = '22023',
      detail = format('Carrega primeiro na Biblioteca as gravações: %s.', coalesce(missing, 'nenhuma câmara no documento')); end if;
  -- só neste caminho automático: as câmaras encontradas pelo nome têm de ser as gravações do pacote (outro ficheiro com o
  -- mesmo nome carregado depois faria o render usar a gravação errada; à mão fica como edit_export_request hoje)
  select string_agg(c.key, ', ') into missing
    from jsonb_each(cams) c join media_job_outputs o on o.asset_id = p_asset join media_jobs pj on pj.id = o.job_id
   where c.key in ('front', 'side') and pj.input->'mode' = '"script"'::jsonb
     and c.value->>'version_id' is distinct from pj.input->c.key->>'version_id';
  if missing is not null then
    raise exception 'nome_repetido' using errcode = '22023',
      detail = format('A câmara %s encontrada pelo nome não é a gravação do pacote (há outro ficheiro com o mesmo nome). Renomeia e exporta à mão.', missing); end if;
  if v.doc->'audio'->'music'->>'asset' is not null then
    select x.* into mv from media_versions x join media_assets a on a.id = x.asset_id
     where a.id::text = v.doc->'audio'->'music'->>'asset' and a.workspace_id = p_ws and x.id = a.current_version_id and x.state = 'pronta' and x.source = 'upload';
    if mv.id is null then raise exception 'musica_em_falta' using errcode = '22023', detail = 'A música escolhida já não está na biblioteca.'; end if;
    music := jsonb_build_object('key', mv.storage_path, 'bucket', mv.storage_bucket, 'db', coalesce((v.doc->'audio'->'music'->>'db')::numeric, -18));
  end if;
  vis := public._edit_resolve_visuals(p_ws, v.doc);
  sib := public._edit_resolve_siblings(p_ws, p_asset);
  k := 'export:' || v.id;
  select * into j from media_jobs where idempotency_key = k;
  if j.id is not null and j.status in ('failed', 'dead', 'cancelled') then
    update media_jobs set idempotency_key = k || ':' || j.id where id = j.id;
    j := null;
  end if;
  if j.id is null then
    insert into media_jobs (workspace_id, kind, idempotency_key, asset_id, edit_version_id, input, created_by, created_label, max_attempts)
    values (p_ws, 'export', k, p_asset, v.id,
            jsonb_build_object('doc', v.doc, 'cams', cams, 'music', music, 'visuals', vis, 'siblings', sib, 'edit_version_no', v.version_no,
                               'out_key', p_ws || '/' || p_asset || '/exports/' || v.id || '.mp4'),
            p_uid, left(p_label, 200), 3)
    returning * into j;
    perform public._package_script_audit(p_ws, p_uid, p_label, 'edit.export_requested', 'media_asset', p_asset::text, null,
      jsonb_build_object('job_id', j.id, 'edit_version_id', v.id, 'edit_version_no', v.version_no, 'origin', 'package_script_auto'));
  end if;
  return j;
end $$;

-- Disparo automático para um guião. Nunca levanta erro: o motivo fica em package_script_status.
create or replace function public._package_script_auto(p_ws text, p_guiao text) returns void
language plpgsql security definer set search_path = public as $$
declare cfg package_script_settings; j media_jobs; why text;
begin
  select * into cfg from package_script_settings where workspace_id = p_ws;
  if cfg.workspace_id is null or not cfg.auto_package then return; end if;
  -- lock antes de ver se as duas estão prontas: duas verificações a acabar ao mesmo tempo (frente e lado) ficam em fila e a
  -- segunda já vê a primeira (cada instrução depois do lock lê o que foi confirmado entretanto)
  perform pg_advisory_xact_lock(hashtext('package_script:guiao:' || p_ws || ':' || p_guiao));
  -- as duas gravações ainda não estão prontas: não é um erro, espera pela outra
  if (public._package_script_clip(p_ws, p_guiao, 'front')).id is null or (public._package_script_clip(p_ws, p_guiao, 'side')).id is null then return; end if;
  -- em nome de quem ligou o automático: volta a verificar tudo agora (removido, suspenso, sem capacidade ou flag = não corre)
  if cfg.enabled_by is null then why := 'sem_responsavel';
  elsif not public._flag_on_for('edit.package_script', p_ws, cfg.enabled_by) or not public._flag_on_for('edit.studio', p_ws, cfg.enabled_by)
        or not public._flag_on_for('media.library', p_ws, cfg.enabled_by) then why := 'funcionalidade_desligada';
  elsif not public._media_r2(p_ws) then why := 'sem_r2';
  elsif not (public._authorize('edit.timeline', p_ws, cfg.enabled_by) and public._authorize('media.read', p_ws, cfg.enabled_by)) then why := 'sem_permissao';
  end if;
  if why is null then
    begin
      j := public._package_script_enqueue(p_ws, p_guiao, cfg.style, cfg.enabled_by, 'auto',
                                          public._flag_on_for('edit.ai_visuals', p_ws, cfg.enabled_by));
    exception when others then
      why := left(coalesce(nullif(sqlerrm, ''), 'erro'), 200);
    end;
  end if;
  if why is not null then
    raise log 'package_script_auto_skipped %', jsonb_build_object('workspace_id', p_ws, 'guiao_id', p_guiao, 'reason', why);
  end if;
  insert into package_script_status (workspace_id, content_id, job_id, reason, at) values (p_ws, p_guiao, j.id, why, now())
  on conflict (workspace_id, content_id) do update set job_id = coalesce(excluded.job_id, package_script_status.job_id), reason = excluded.reason, at = now();
exception when others then
  raise log 'package_script_auto_failed %', jsonb_build_object('workspace_id', p_ws, 'guiao_id', p_guiao, 'error', sqlerrm);
end $$;

-- Uma versão nova de uma gravação ficou atual (upload verificado pelo worker ou no Supabase Storage).
create or replace function public._package_script_on_asset() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text;
begin
  if new.current_version_id is null or new.current_version_id is not distinct from old.current_version_id then return new; end if;
  perform pg_advisory_xact_lock(hashtext('package_script:asset:' || new.id));
  select content_id into g from recording_clips where asset_id = new.id and workspace_id = new.workspace_id;
  if g is not null then perform public._package_script_auto(new.workspace_id, g); end if;
  return new;
exception when others then
  raise log 'package_script_on_asset_failed %', jsonb_build_object('asset_id', new.id, 'error', sqlerrm);
  return new;
end $$;
drop trigger if exists media_assets_package_script on public.media_assets;
create trigger media_assets_package_script after update of current_version_id on public.media_assets
  for each row execute function public._package_script_on_asset();

-- Pacote por guião acabado e "exportar todos automaticamente" ligado: um export por vídeo, em nome de quem ligou.
create or replace function public._package_script_after_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare cfg package_script_settings; o record; ok int := 0; fails jsonb := '[]'; lbl text;
begin
  if new.kind <> 'package' or new.status <> 'done' or old.status is not distinct from 'done' or new.input->>'mode' is distinct from 'script' then
    return new; end if;
  select * into cfg from package_script_settings where workspace_id = new.workspace_id;
  if cfg.workspace_id is null or not cfg.auto_export or cfg.enabled_by is null then return new; end if;
  if not (public._flag_on_for('edit.package_script', new.workspace_id, cfg.enabled_by) and public._flag_on_for('edit.studio', new.workspace_id, cfg.enabled_by)
          and public._flag_on_for('media.library', new.workspace_id, cfg.enabled_by)
          and public._authorize('edit.export', new.workspace_id, cfg.enabled_by) and public._authorize('media.read', new.workspace_id, cfg.enabled_by)) then
    perform public._package_script_audit(new.workspace_id, cfg.enabled_by, 'pacote por guião (automático)', 'edit.package_script_auto_export', 'media_job',
      new.id::text, null, jsonb_build_object('queued', 0, 'skipped', 'sem_permissao_ou_flag'));
    return new;
  end if;
  lbl := coalesce(public._media_label(cfg.enabled_by), 'sistema') || ' (automático)';
  for o in select x.asset_id, a.title from media_job_outputs x join media_assets a on a.id = x.asset_id
            where x.job_id = new.id and a.lifecycle = 'ativo' order by x.guiao_id, x.hook loop
    begin
      perform public._package_script_export(new.workspace_id, o.asset_id, cfg.enabled_by, lbl);
      ok := ok + 1;
    exception when others then
      fails := fails || jsonb_build_array(jsonb_build_object('asset_id', o.asset_id, 'title', o.title, 'error', left(coalesce(nullif(sqlerrm, ''), 'erro'), 200)));
    end;
  end loop;
  perform public._package_script_audit(new.workspace_id, cfg.enabled_by, lbl, 'edit.package_script_auto_export', 'media_job', new.id::text, null,
    jsonb_build_object('queued', ok, 'failed', fails));
  return new;
exception when others then
  raise log 'package_script_after_done_failed %', jsonb_build_object('job_id', new.id, 'error', sqlerrm);
  return new;
end $$;
drop trigger if exists media_jobs_package_script_done on public.media_jobs;
create trigger media_jobs_package_script_done after update of status on public.media_jobs
  for each row when (new.kind = 'package') execute function public._package_script_after_done();

-- ─ RPCs da app ──────────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._package_script_flag(p_ws text, p_token text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._flag_on('edit.package_script', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pacote por guião ainda não está ligado neste cliente.'; end if;
end $$;

create or replace function public._recording_clip_json(c recording_clips) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('asset_id', c.asset_id, 'content_id', c.content_id, 'camera', c.camera, 'session_id', c.session_id, 'source', c.source,
    'linked_label', c.linked_label, 'linked_at', c.linked_at,
    'title', a.title, 'name', v.original_name, 'state', case when v.id is null then 'sem_versao' else v.state end,
    'storage', v.storage_provider, 'version_id', v.id, 'version_no', v.version_no, 'duration', v.media_info->'duration')
    from media_assets a left join media_versions v on v.id = a.current_version_id where a.id = c.asset_id
$$;

-- Ligar um ficheiro da Biblioteca a um guião e a uma câmara (no fim do upload ou na Biblioteca). Mesma capacidade que mudar
-- os dados do ativo (media.upload). O agente de estúdio (STU-02) chamará esta mesma função com p_source = 'agente' quando
-- tiver identidade própria (studio.capture); até lá a app só manda 'upload' ou 'biblioteca'.
create or replace function public.media_clip_link(p_ws text, p_asset uuid, p_guiao text, p_camera text, p_session uuid default null,
                                                  p_source text default 'biblioteca', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; a media_assets; old_c recording_clips; prev recording_clips; c recording_clips; src text := coalesce(nullif(p_source, ''), 'biblioteca');
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.clip_link', coalesce(p_asset::text, ''));
  uid := public._media_uid();
  perform public._package_script_flag(p_ws, p_token);
  if p_camera is null or p_camera not in ('front', 'side') then
    raise exception 'camara_invalida' using errcode = '22023', detail = 'A câmara tem de ser a da frente ou a do lado.'; end if;
  if src not in ('upload', 'biblioteca') then raise exception 'origem_invalida' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('package_script:asset:' || coalesce(p_asset::text, '')));
  select * into a from media_assets where id = p_asset and workspace_id = p_ws for update;
  if a.id is null then raise exception 'ativo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.lifecycle <> 'ativo' then raise exception 'ativo_no_lixo' using errcode = '22023', detail = 'Recupera o ativo do lixo antes de o ligar.'; end if;
  if a.kind <> 'video' then raise exception 'nao_e_video' using errcode = '22023', detail = 'Só um vídeo pode ser a gravação de uma câmara.'; end if;
  if 'pacote' = any (a.tags) then raise exception 'nao_e_gravacao' using errcode = '22023', detail = 'Este vídeo saiu de um pacote: liga a gravação original.'; end if;
  if not exists (select 1 from guioes where id = p_guiao and client_id = p_ws and deleted_at is null) then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002', detail = 'O guião não é deste cliente ou foi eliminado.'; end if;
  if a.content_id is not null and a.content_id <> p_guiao then
    raise exception 'ligado_a_outro_guiao' using errcode = '22023', detail = 'Este ficheiro está ligado a outro guião. Muda o guião do ficheiro na Biblioteca primeiro.'; end if;
  if p_session is not null and not exists (select 1 from recording_sessions where id = p_session and workspace_id = p_ws) then
    raise exception 'sessao_nao_encontrada' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtext('package_script:guiao:' || p_ws || ':' || p_guiao));
  select * into old_c from recording_clips where asset_id = a.id;
  if old_c.asset_id is not null and old_c.content_id = p_guiao and old_c.camera = p_camera and old_c.session_id is not distinct from coalesce(p_session, old_c.session_id) then
    return public._recording_clip_json(old_c) || jsonb_build_object('repeated', true);
  end if;
  -- outra gravação nesta câmara deste guião: sai (a nova substitui-a)
  delete from recording_clips where workspace_id = p_ws and content_id = p_guiao and camera = p_camera and asset_id <> a.id returning * into prev;
  delete from recording_clips where asset_id = a.id;
  insert into recording_clips (asset_id, workspace_id, content_id, camera, session_id, source, linked_by, linked_label)
  values (a.id, p_ws, p_guiao, p_camera, coalesce(p_session, old_c.session_id), src, uid, public._media_label(uid))
  returning * into c;
  if a.content_id is null then update media_assets set content_id = p_guiao where id = a.id; end if;
  perform public._media_audit(p_ws, 'media.clip_linked', 'media_asset', a.id::text,
    case when old_c.asset_id is null and prev.asset_id is null then null
         else jsonb_strip_nulls(jsonb_build_object('this', case when old_c.asset_id is not null then to_jsonb(old_c) end,
                                                   'replaced', case when prev.asset_id is not null then to_jsonb(prev) end)) end,
    to_jsonb(c));
  perform public._package_script_auto(p_ws, p_guiao);
  return public._recording_clip_json(c) || jsonb_build_object('repeated', false);
end $$;

create or replace function public.media_clip_unlink(p_ws text, p_asset uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c recording_clips;
begin
  perform public._media_require('media.upload', p_ws, p_token, 'media.clip_unlink', coalesce(p_asset::text, ''));
  perform public._media_uid();
  perform public._package_script_flag(p_ws, p_token);
  delete from recording_clips where asset_id = p_asset and workspace_id = p_ws returning * into c;
  if c.asset_id is null then return jsonb_build_object('unlinked', false); end if;
  perform public._media_audit(p_ws, 'media.clip_unlinked', 'media_asset', p_asset::text, to_jsonb(c), null);
  return jsonb_build_object('unlinked', true);
end $$;

create or replace function public.media_clip_get(p_ws text, p_asset uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c recording_clips;
begin
  perform public._media_require('media.read', p_ws, p_token, 'media.clip_get', coalesce(p_asset::text, ''));
  perform public._package_script_flag(p_ws, p_token);
  select * into c from recording_clips where asset_id = p_asset and workspace_id = p_ws;
  return case when c.asset_id is null then null else public._recording_clip_json(c) end;
end $$;

-- Pedir à mão o pacote de um guião (Edição automática, botão por guião). Mesmas regras que o pacote da sessão.
create or replace function public.edit_package_script_request(p_ws text, p_guiao text, p_style text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; j media_jobs; st text;
begin
  uid := public._edit_require(p_ws, p_token, 'edit.package_script', coalesce(p_guiao, ''), true);
  perform public._package_script_flag(p_ws, p_token);
  if not public.ws_can('edit.timeline', p_ws, p_token) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package_script');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._media_r2(p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pacote automático precisa do armazenamento de vídeo (R2) ligado neste cliente.'; end if;
  st := coalesce(nullif(p_style, ''), (select style from package_script_settings where workspace_id = p_ws), 'S15');
  perform pg_advisory_xact_lock(hashtext('package_script:guiao:' || p_ws || ':' || coalesce(p_guiao, '')));
  j := public._package_script_enqueue(p_ws, p_guiao, st, uid, 'manual', public._flag_on('edit.ai_visuals', p_ws, p_token));
  return public._media_job_json(j) || jsonb_build_object('guiao_id', p_guiao);
end $$;

-- Lista para a app: definições, o que a pessoa pode fazer e, por guião com gravações ligadas ou pacotes por guião, as duas
-- gravações, o último pacote (com as saídas e o estado dos exports) e o último disparo automático.
create or replace function public.edit_package_script_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cfg package_script_settings; delegate_ok boolean;
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  perform public._package_script_flag(p_ws, p_token);
  select * into cfg from package_script_settings where workspace_id = p_ws;
  delegate_ok := cfg.enabled_by is not null and public._flag_on_for('edit.package_script', p_ws, cfg.enabled_by)
                 and public._flag_on_for('edit.studio', p_ws, cfg.enabled_by) and public._authorize('edit.timeline', p_ws, cfg.enabled_by)
                 and (not cfg.auto_export or public._authorize('edit.export', p_ws, cfg.enabled_by));
  return jsonb_build_object(
    'settings', jsonb_build_object('auto_package', coalesce(cfg.auto_package, false), 'auto_export', coalesce(cfg.auto_export, false),
                  'style', coalesce(cfg.style, 'S15'), 'enabled_label', (select public._media_label(cfg.enabled_by)),
                  'updated_label', cfg.updated_label, 'updated_at', cfg.updated_at,
                  'delegate_ok', case when coalesce(cfg.auto_package, false) or coalesce(cfg.auto_export, false) then delegate_ok end),
    'can', jsonb_build_object('request', public.ws_can('edit.timeline', p_ws, p_token), 'export', public.ws_can('edit.export', p_ws, p_token),
              'link', public.ws_can('media.upload', p_ws, p_token), 'settings', public.ws_can('styles.manage', p_ws, p_token)),
    'scripts', coalesce((
      select jsonb_agg(jsonb_build_object(
          'guiao', jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema),
          'front', (select public._recording_clip_json(c) from recording_clips c where c.workspace_id = p_ws and c.content_id = g.id and c.camera = 'front'),
          'side', (select public._recording_clip_json(c) from recording_clips c where c.workspace_id = p_ws and c.content_id = g.id and c.camera = 'side'),
          'job', (select public._media_job_json(j) || jsonb_build_object(
                     'origin', j.input->>'origin', 'front_name', j.input->'front'->>'name', 'side_name', j.input->'side'->>'name',
                     'front_version', j.input->'front'->>'version_id', 'side_version', j.input->'side'->>'version_id',
                     'outputs', (select coalesce(jsonb_agg(jsonb_build_object('guiao_id', o.guiao_id, 'hook', o.hook, 'asset_id', o.asset_id, 'title', a.title,
                                   'export', (select jsonb_build_object('status', e.status, 'progress', e.progress) from media_jobs e
                                               where e.asset_id = o.asset_id and e.kind = 'export' order by e.created_at desc limit 1))
                                 order by o.hook), '[]')
                                 from media_job_outputs o join media_assets a on a.id = o.asset_id where o.job_id = j.id and a.lifecycle = 'ativo'))
                    from media_jobs j where j.workspace_id = p_ws and j.kind = 'package' and j.input->>'mode' = 'script' and j.input->>'guiao_id' = g.id
                   order by j.created_at desc limit 1),
          'auto', (select jsonb_build_object('reason', s.reason, 'at', s.at, 'job_id', s.job_id) from package_script_status s
                    where s.workspace_id = p_ws and s.content_id = g.id))
        order by g.date desc, g.n)
        from guioes g
       where g.client_id = p_ws and g.deleted_at is null
         and g.id in (select content_id from recording_clips where workspace_id = p_ws
                      union select input->>'guiao_id' from media_jobs where workspace_id = p_ws and kind = 'package' and input->>'mode' = 'script'
                                                                        and created_at > now() - interval '30 days')
       limit 120), '[]'));
end $$;

create or replace function public.package_script_settings_set(p_ws text, p_auto_package boolean, p_auto_export boolean, p_style text default 'S15',
                                                              p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; b package_script_settings; c package_script_settings; st text := coalesce(nullif(btrim(p_style), ''), 'S15');
begin
  uid := public._edit_require(p_ws, p_token, 'edit.package_script_settings', p_ws, true);
  perform public._package_script_flag(p_ws, p_token);
  if not public.ws_can('styles.manage', p_ws, p_token) or (coalesce(p_auto_export, false) and not public.ws_can('edit.export', p_ws, p_token))
     or (coalesce(p_auto_package, false) and not public.ws_can('edit.timeline', p_ws, p_token)) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'workspace_id', p_ws, 'action', 'edit.package_script_settings');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if st !~ '^[A-Za-z0-9_-]{1,40}$' then raise exception 'estilo_invalido' using errcode = '22023'; end if;
  select * into b from package_script_settings where workspace_id = p_ws for update;
  insert into package_script_settings (workspace_id, auto_package, auto_export, style, enabled_by, updated_by, updated_label, updated_at)
  values (p_ws, coalesce(p_auto_package, false), coalesce(p_auto_export, false), st,
          case when coalesce(p_auto_package, false) or coalesce(p_auto_export, false) then uid end, uid, public._media_label(uid), now())
  on conflict (workspace_id) do update set auto_package = excluded.auto_package, auto_export = excluded.auto_export, style = excluded.style,
    enabled_by = excluded.enabled_by, updated_by = excluded.updated_by, updated_label = excluded.updated_label, updated_at = now()
  returning * into c;
  perform public._media_audit(p_ws, 'edit.package_script_settings', 'workspace', p_ws, to_jsonb(b), to_jsonb(c));
  return jsonb_build_object('auto_package', c.auto_package, 'auto_export', c.auto_export, 'style', c.style, 'enabled_label', public._media_label(c.enabled_by),
                            'updated_label', c.updated_label, 'updated_at', c.updated_at);
end $$;

-- edit_package_list: igual a 20261105215624_w5_auditoria_fix.sql, sem os pacotes por guião (têm a lista própria; com 30
-- guiões por sessão empurravam o pacote da sessão para fora dos últimos 20). Sem pacotes por guião devolve o mesmo de hoje.
create or replace function public.edit_package_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._edit_require(p_ws, p_token, 'edit.read', p_ws, false);
  return coalesce((select jsonb_agg(public._media_job_json(j) || jsonb_build_object(
      'front_name', j.input->'front'->>'name', 'side_name', j.input->'side'->>'name',
      'guioes', (select jsonb_agg(jsonb_build_object('id', g->>'id', 'n', (g->>'n')::int, 'tema', case when x.live then g->>'tema' end, 'deleted', not x.live))
                   from jsonb_array_elements(j.input->'guioes') g,
                        lateral (select exists (select 1 from guioes z where z.id = g->>'id' and z.client_id = p_ws and z.deleted_at is null) as live) x),
      'outputs', (select coalesce(jsonb_agg(jsonb_build_object('guiao_id', o.guiao_id, 'hook', o.hook, 'asset_id', o.asset_id, 'title', a.title)
                                           order by o.guiao_id, o.hook), '[]')
                    from media_job_outputs o join media_assets a on a.id = o.asset_id where o.job_id = j.id))
      order by j.created_at desc)
    from (select * from media_jobs where workspace_id = p_ws and kind = 'package' and input->>'mode' is distinct from 'script'
           order by created_at desc limit 20) j), '[]');
end $$;

revoke all on function public._package_script_clip(text, text, text), public._package_script_name_clash(text, media_versions),
  public._package_script_audit(text, uuid, text, text, text, text, jsonb, jsonb),
  public._package_script_enqueue(text, text, text, uuid, text, boolean), public._package_script_export(text, uuid, uuid, text),
  public._package_script_auto(text, text), public._package_script_on_asset(), public._package_script_after_done(),
  public._package_script_flag(text, text), public._recording_clip_json(recording_clips) from public, anon, authenticated;
revoke all on function public.media_clip_link(text, uuid, text, text, uuid, text, text), public.media_clip_unlink(text, uuid, text),
  public.media_clip_get(text, uuid, text), public.edit_package_script_request(text, text, text, text), public.edit_package_script_list(text, text),
  public.package_script_settings_set(text, boolean, boolean, text, text) from public, anon;
grant execute on function public.media_clip_link(text, uuid, text, text, uuid, text, text), public.media_clip_unlink(text, uuid, text),
  public.media_clip_get(text, uuid, text), public.edit_package_script_request(text, text, text, text), public.edit_package_script_list(text, text),
  public.package_script_settings_set(text, boolean, boolean, text, text) to authenticated;

/* Rollback (compatível, por esta ordem; o código do main e o worker de hoje não dependem de nada disto):
   0. Desligar sem rollback: flag_set('edit.package_script', <ws>, 'off') (RPCs param com 55000, o automático deixa de correr
      porque _flag_on_for falha para quem o ligou).
   1. drop trigger if exists media_jobs_package_script_done on public.media_jobs;
      drop trigger if exists media_assets_package_script on public.media_assets;
   2. repor edit_package_list de 20261105215624_w5_auditoria_fix.sql.
   3. drop function if exists public.package_script_settings_set(text, boolean, boolean, text, text), public.edit_package_script_list(text, text),
        public.edit_package_script_request(text, text, text, text), public.media_clip_get(text, uuid, text), public.media_clip_unlink(text, uuid, text),
        public.media_clip_link(text, uuid, text, text, uuid, text, text), public._recording_clip_json(recording_clips), public._package_script_flag(text, text),
        public._package_script_after_done(), public._package_script_on_asset(), public._package_script_auto(text, text),
        public._package_script_export(text, uuid, uuid, text), public._package_script_enqueue(text, text, text, uuid, text, boolean),
        public._package_script_audit(text, uuid, text, text, text, text, jsonb, jsonb), public._package_script_name_clash(text, media_versions),
        public._package_script_clip(text, text, text);
   4. drop index if exists public.media_jobs_package_script;
   5. contract posterior (dados de ligação perdem-se; os ativos, jobs e documentos criados ficam):
      drop table public.package_script_status; drop table public.package_script_settings; drop table public.recording_clips;
      delete from feature_flags where key = 'edit.package_script'; delete from feature_flag_defs where key = 'edit.package_script'.
   Jobs por guião já criados continuam válidos: o worker de hoje ignora mode/guiao_id e encontra a janela pela transcrição. */
