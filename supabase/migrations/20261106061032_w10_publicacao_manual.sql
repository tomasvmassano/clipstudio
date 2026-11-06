-- W10-03 · Registo da publicação manual (PRD FR-12-02; FR-21-02, FR-21-04; R-16, R-18; PERF-02; PUB-04, PUB-06; AGENTS §2.6,
-- §2.7, §6, §8; ADR-0054). Sem OAuth: alguém publicou à mão, na app da plataforma, um vídeo aprovado, e aqui regista que foi
-- publicado: o URL público do post, a hora, a versão exata do vídeo (media_versions) aprovada na revisão e a conta (a da
-- publicação planeada e aprovada). Nada aqui publica nem chama APIs das plataformas.
--
-- Regras (no servidor, a UI só reflete):
--   · só uma publicação `aprovada` (PUB-06), com a versão do guião ainda aprovada (FR-21-02: volta a verificar ao publicar);
--   · o vídeo tem de ser a versão ATUAL de um ativo deste guião e estar aprovado na revisão (AGENTS §2.6/§2.7);
--   · URL validado pela plataforma da conta (Instagram reel/p/tv, TikTok /@conta/video/ID, YouTube shorts/watch/youtu.be);
--     se o URL trouxer a conta (TikTok, Instagram com utilizador) tem de ser a desta publicação;
--   · idempotente: o mesmo URL outra vez na mesma publicação não duplica nada; o mesmo post noutra publicação é recusado;
--   · mudar o que ficou registado só por correção explícita, com motivo, auditada (antes/depois);
--   · grava a linhagem no momento (R-18, PERF-02) com _perf_record_lineage e liga-a com _pub_link_lineage, pelo
--     correlation_id `pub:<id>` (FR-21-04): as métricas do post ficam presas a este publication_id;
--   · a publicação passa a `publicada` (só por esta RPC); depois disso não se muda nem se cancela.
-- Capacidade: `publishing.publish` (existia como planeada, W6, com papéis owner/admin): passa a ativa e o manager recebe-a
-- (é quem já planeia e aprova). Sessão individual obrigatória (sem código de equipa). Flag `pub.planning`.
--
-- Expand (só aditivo para o código em main): colunas novas nulas em pub_publications, estado novo `publicada` (as checks só
-- alargam: main nunca escreve esse estado), um tipo de notificação novo, funções novas, e substituição compatível de
-- pub_publications_guard, perf_lineage_guard, _pub_json, pub_calendar e _ops_queue (mesmo comportamento para tudo o que main
-- já faz; só acrescentam o caminho novo). Rollback no fim.

-- ───────────── capacidade ─────────────
update capabilities set status = 'ativo', label = 'Registar publicações feitas à mão (URL, hora, vídeo aprovado)' where key = 'publishing.publish';
insert into role_capabilities (scope, role, capability) values ('ws', 'manager', 'publishing.publish') on conflict do nothing;

-- ───────────── dados ─────────────
alter table public.pub_publications
  add column if not exists published_at timestamptz,
  add column if not exists published_url text check (published_url is null or char_length(published_url) <= 1000),
  add column if not exists published_external_id text check (published_external_id is null or char_length(published_external_id) between 1 and 200),
  add column if not exists published_media_version_id uuid references public.media_versions(id),
  add column if not exists published_by uuid,
  add column if not exists published_label text,
  add column if not exists published_recorded_at timestamptz,
  add column if not exists publish_mode text check (publish_mode is null or publish_mode = 'manual'),
  add column if not exists published_corrections int not null default 0;

alter table public.pub_publications drop constraint if exists pub_publications_status_check;
alter table public.pub_publications add constraint pub_publications_status_check
  check (status in ('planeada', 'aprovada', 'publicada', 'cancelada'));
-- antes: (status = 'aprovada') = (approved_revision = revision). Uma publicada continua presa à revisão aprovada.
alter table public.pub_publications drop constraint if exists pub_publications_check1;
alter table public.pub_publications drop constraint if exists pub_publications_approved_check;
alter table public.pub_publications add constraint pub_publications_approved_check
  check ((status in ('aprovada', 'publicada')) = (approved_revision is not null and approved_revision = revision));
alter table public.pub_publications drop constraint if exists pub_publications_published_check;
alter table public.pub_publications add constraint pub_publications_published_check
  check (status <> 'publicada' or (published_at is not null and published_external_id is not null and published_url is not null
                                   and published_media_version_id is not null and lineage_id is not null and publish_mode is not null));
-- o mesmo post (conta + ID do post) só pode ser uma publicação
create unique index if not exists pub_publications_post on public.pub_publications (account_id, published_external_id)
  where published_external_id is not null;

-- ───────────── URL público do post, por plataforma (regra pura; igual a src/lib/pub-url.ts) ─────────────
-- Devolve {external_id, url (canónico), handle (ou null)} ou null se não for um link de post dessa plataforma.
-- external_id: Instagram = shortcode (o id dos reels do motor), TikTok = ID numérico do vídeo, YouTube = ID de 11 caracteres.
create or replace function public._pub_post_url(p_platform text, p_url text) returns jsonb
language plpgsql immutable set search_path = public as $$
declare u text := btrim(coalesce(p_url, '')); m text[];
begin
  if u = '' or char_length(u) > 1000 or u ~ '\s' then return null; end if;
  if p_platform = 'instagram' then
    m := regexp_match(u, '^https?://(?:www\.|m\.)?instagram\.com/(?:([A-Za-z0-9._]{1,30})/)?(reels?|p|tv)/([A-Za-z0-9_-]{5,40})/?(?:[?#].*)?$', 'i');
    if m is null then return null; end if;
    return jsonb_build_object('external_id', m[3], 'handle', lower(m[1]),
      'url', 'https://www.instagram.com/' || case when lower(m[2]) in ('reel', 'reels') then 'reel' else lower(m[2]) end || '/' || m[3] || '/');
  elsif p_platform = 'tiktok' then
    m := regexp_match(u, '^https?://(?:www\.|m\.)?tiktok\.com/@([A-Za-z0-9._]{1,40})/(?:video|photo)/([0-9]{8,25})/?(?:[?#].*)?$', 'i');
    if m is null then return null; end if;
    return jsonb_build_object('external_id', m[2], 'handle', lower(m[1]), 'url', 'https://www.tiktok.com/@' || lower(m[1]) || '/video/' || m[2]);
  elsif p_platform = 'youtube' then
    m := coalesce(
      regexp_match(u, '^https?://(?:www\.|m\.)?youtube\.com/shorts/([A-Za-z0-9_-]{11})/?(?:[?#].*)?$', 'i'),
      regexp_match(u, '^https?://(?:www\.|m\.)?youtube\.com/watch\?(?:[^#]*&)?v=([A-Za-z0-9_-]{11})(?:[&#].*)?$', 'i'),
      regexp_match(u, '^https?://youtu\.be/([A-Za-z0-9_-]{11})/?(?:[?#].*)?$', 'i'));
    if m is null then return null; end if;
    return jsonb_build_object('external_id', m[1], 'handle', null, 'url', 'https://www.youtube.com/shorts/' || m[1]);
  end if;
  return null;
end $$;

create or replace function public._pub_url_hint(p_platform text) returns text
language sql immutable as $$
  select case p_platform
    when 'instagram' then 'Cola o link do post do Instagram (instagram.com/reel/... ou /p/...).'
    when 'tiktok' then 'Cola o link completo do TikTok (tiktok.com/@conta/video/...). Links curtos vm.tiktok.com não servem: abre-o e copia o link completo.'
    when 'youtube' then 'Cola o link do YouTube (youtube.com/shorts/..., youtube.com/watch?v=... ou youtu.be/...).'
    else 'Plataforma sem registo manual.' end
$$;

-- ───────────── guardas (substituem as de W6/W7; tudo o que main faz fica igual) ─────────────
create or replace function public.pub_publications_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare bound boolean; recording boolean;
begin
  if tg_op = 'DELETE' then raise exception 'publicacao_imutavel' using errcode = '42501', detail = 'Publicações planeadas não se apagam; cancelam-se.'; end if;
  if tg_op = 'INSERT' then
    if new.status <> 'planeada' or new.revision <> 1 or new.approved_revision is not null or new.lineage_id is not null
       or new.published_at is not null or new.published_url is not null or new.published_external_id is not null
       or new.published_media_version_id is not null or new.publish_mode is not null or new.published_corrections <> 0 then
      raise exception 'estado_inicial_invalido' using errcode = '42501', detail = 'Uma publicação nasce planeada; só a aprovação a torna aprovada.'; end if;
    return new;
  end if;
  if new.id <> old.id or new.workspace_id <> old.workspace_id or new.created_by is distinct from old.created_by then
    raise exception 'publicacao_imutavel' using errcode = '42501'; end if;
  if old.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
  if new.lineage_id is distinct from old.lineage_id and coalesce(current_setting('pub.linking', true), '') <> new.id::text then
    raise exception 'linhagem_so_pelo_publicador' using errcode = '42501'; end if;
  recording := coalesce(current_setting('pub.recording', true), '') = new.id::text;
  -- FR-12-02: o registo da publicação só pela RPC de registo
  if (new.published_at, new.published_url, new.published_external_id, new.published_media_version_id, new.published_by, new.published_label,
      new.published_recorded_at, new.publish_mode, new.published_corrections)
     is distinct from (old.published_at, old.published_url, old.published_external_id, old.published_media_version_id, old.published_by,
      old.published_label, old.published_recorded_at, old.publish_mode, old.published_corrections) and not recording then
    raise exception 'registo_so_pela_rpc' using errcode = '42501', detail = 'O registo da publicação só se faz por "Registar publicação".'; end if;
  -- depois de publicada: o que foi aprovado e publicado não muda nem se cancela (só o registo, por correção com motivo)
  if old.status = 'publicada' then
    if new.status <> 'publicada' or public._pub_snapshot(new) is distinct from public._pub_snapshot(old) or new.revision <> old.revision
       or new.approved_revision is distinct from old.approved_revision or new.lineage_id is distinct from old.lineage_id then
      raise exception 'publicacao_publicada' using errcode = '22023',
        detail = 'Esta publicação já foi publicada: não se muda nem se cancela. Para corrigir o registo, usa a correção com motivo.'; end if;
    new.updated_at := now();
    new.lock_version := old.lock_version + 1;
    return new;
  end if;
  if new.status = 'publicada' then
    if not recording or old.status <> 'aprovada' or public._pub_snapshot(new) is distinct from public._pub_snapshot(old)
       or new.revision <> old.revision or new.approved_revision is distinct from old.approved_revision or new.lineage_id is null then
      raise exception 'publicacao_so_pela_rpc' using errcode = '42501', detail = 'Só uma publicação aprovada passa a publicada, pelo registo.'; end if;
    new.updated_at := now();
    new.lock_version := old.lock_version + 1;
    return new;
  end if;
  bound := public._pub_snapshot(new) is distinct from public._pub_snapshot(old);
  if bound then
    if new.revision <> old.revision + 1 then new.revision := old.revision + 1; end if;
    -- FR-21-02: mudar versão, variante ou destino retira a aprovação (nova aprovação necessária)
    if old.status = 'aprovada' then new.status := 'planeada'; end if;
    new.approved_revision := null; new.approved_at := null;
    update pub_approvals set invalidated_at = now(), invalidated_reason = 'A versão, a variante ou o destino mudaram (revisão ' || new.revision || ').'
     where publication_id = old.id and invalidated_at is null;
  elsif new.revision <> old.revision then
    raise exception 'revisao_invalida' using errcode = '42501';
  end if;
  if new.status = 'aprovada' and (old.status <> 'aprovada' or bound) then
    if coalesce(current_setting('pub.approving', true), '') <> new.id::text then
      raise exception 'aprovacao_so_pela_rpc' using errcode = '42501', detail = 'Uma publicação só fica aprovada pela aprovação humana (pub_approve).'; end if;
    if cardinality(public._pub_missing(new)) > 0 then
      raise exception 'aprovacao_incompleta' using errcode = '42501'; end if;
  end if;
  new.updated_at := now();
  new.lock_version := old.lock_version + 1;
  return new;
end $$;

-- Linhagem gravada continua imutável (R-18). Única exceção nova: a correção explícita do registo manual (pub_record_published
-- com motivo), que pode mudar o post, a hora e o vídeo registados, nunca o conteúdo, a versão do guião, a conta nem a ligação.
create or replace function public.perf_lineage_guard() returns trigger
language plpgsql set search_path = public as $$
declare fixed text[] := array['origin', 'origin_source', 'origin_reason', 'updated_at'];
        correctable text[] := array['external_id', 'url', 'published_at', 'local_hour', 'asset_ref', 'duration_s', 'hook_index', 'hook_text',
                                    'hook_mechanism', 'edit_style_key', 'edit_style_version'];
begin
  if tg_op = 'DELETE' then
    if old.lineage_mode = 'gravada' then raise exception 'linhagem_imutavel' using errcode = '42501'; end if;
    return old;
  end if;
  if old.lineage_mode = 'gravada' then
    if coalesce(current_setting('pub.correcting', true), '') = old.id::text then
      if (to_jsonb(new) - (fixed || correctable)) is distinct from (to_jsonb(old) - (fixed || correctable)) then
        raise exception 'linhagem_imutavel' using errcode = '42501', detail = 'A correção só muda o post, a hora e o vídeo registados.'; end if;
    elsif (to_jsonb(new) - fixed) is distinct from (to_jsonb(old) - fixed) then
      raise exception 'linhagem_imutavel' using errcode = '42501', detail = 'A linhagem gravada no momento da publicação não se altera (R-18).';
    end if;
  end if;
  return new;
end $$;

-- ───────────── auxiliares ─────────────
-- O vídeo que se regista como publicado: versão pronta de um ativo ativo deste guião, aprovada na revisão e a atual do ativo
-- (p_keep: a versão já registada continua aceite numa correção mesmo que entretanto haja uma versão nova).
create or replace function public._pub_record_video(p_ws text, p_content text, p_version uuid, p_keep uuid default null) returns media_versions
language plpgsql stable security definer set search_path = public as $$
declare v media_versions; a media_assets;
begin
  select * into v from media_versions where id = p_version and workspace_id = p_ws and state = 'pronta';
  select * into a from media_assets where id = v.asset_id and workspace_id = p_ws and lifecycle = 'ativo';
  if v.id is null or a.id is null then raise exception 'video_nao_encontrado' using errcode = 'P0002', detail = 'Escolhe o vídeo que foi publicado.'; end if;
  if a.content_id is distinct from p_content then
    raise exception 'video_de_outro_guiao' using errcode = '22023', detail = 'Este vídeo não é do guião desta publicação.'; end if;
  if public._review_status(v.id) <> 'approved' then
    raise exception 'video_por_aprovar' using errcode = '22023', detail = 'Esta versão do vídeo não está aprovada na revisão. Só se regista o que foi aprovado.'; end if;
  if a.current_version_id is distinct from v.id and v.id is distinct from p_keep then
    raise exception 'versao_antiga' using errcode = '22023', detail = 'Esta já não é a versão atual do vídeo. Regista a versão atual (aprovada).'; end if;
  return v;
end $$;

-- Linhagem a gravar (PERF-02): hook pela etiqueta hook_N do ativo, estilo pela variante ou pela etiqueta Sxx, duração do ficheiro.
create or replace function public._pub_record_lineage_input(p pub_publications, v media_versions, p_ext text, p_url text, p_at timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a media_assets; cv content_versions; pv pub_variants; hi int; tag text; sk text; sv int; par pub_publications; parent_lineage bigint;
begin
  select * into a from media_assets where id = v.asset_id;
  select * into cv from content_versions where id = p.content_version_id;
  tag := public._review_variant(a.tags);
  if tag like 'hook_%' then
    hi := substr(tag, 6)::int - 1;
    if hi > 9 or hi >= coalesce(jsonb_array_length(case when jsonb_typeof(cv.hooks) = 'array' then cv.hooks end), 0) then hi := null; end if;
  end if;
  if p.variant_id is not null then
    select * into pv from pub_variants where id = p.variant_id;
    sk := pv.edit_style_key; sv := pv.edit_style_version;
  end if;
  if sk is null and public._review_style(a.tags) is not null then
    select e.key, e.version into sk, sv from edit_style_versions e
     where e.workspace_id = p.workspace_id and upper(e.key) = public._review_style(a.tags) order by e.version desc limit 1;
  end if;
  if p.parent_publication_id is not null then
    select * into par from pub_publications where id = p.parent_publication_id;
    parent_lineage := par.lineage_id;
  end if;
  return jsonb_build_object('account_id', p.account_id, 'external_id', p_ext, 'url', p_url, 'published_at', p_at,
    'content_id', p.content_id, 'content_version_id', p.content_version_id, 'hook_index', hi,
    'edit_style_key', sk, 'edit_style_version', sv, 'asset_ref', 'media_version:' || v.id,
    'duration_s', case when (v.media_info->>'duration') ~ '^[0-9]+(\.[0-9]+)?$' and (v.media_info->>'duration')::numeric <= 36000
                       then (v.media_info->>'duration')::numeric end,
    'source_type', 'guiao', 'generation', case when p.kind = 'republicacao' and parent_lineage is null then 1 else 0 end,
    'parent_lineage_id', parent_lineage, 'correlation_id', p.correlation_id);
end $$;

-- Pode registar? (null = sim). Para a UI explicar porque não; a RPC volta a verificar tudo.
create or replace function public._pub_record_blocked(p pub_publications, p_token text) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  return case
    when p.status not in ('aprovada', 'publicada') then case when p.status = 'planeada' then 'por_aprovar' else 'cancelada' end
    when auth.uid() is null or not public.ws_can('publishing.publish', p.workspace_id, p_token) then 'sem_capacidade'
    when p.status = 'aprovada' and (select g.approved_version_id from guioes g where g.id = p.content_id) is distinct from p.content_version_id then 'versao_por_aprovar'
    when not exists (select 1 from media_assets a join media_versions v on v.id = a.current_version_id
                      where a.workspace_id = p.workspace_id and a.content_id = p.content_id and a.lifecycle = 'ativo' and v.state = 'pronta'
                        and public._review_status(v.id) = 'approved') and p.status = 'aprovada' then 'sem_video_aprovado'
  end;
end $$;

-- ───────────── leitura: o que entra no registo ─────────────
-- Dada uma publicação: os vídeos do guião (aprovados e atuais primeiro, os outros com o motivo). Dado um vídeo (revisão): as
-- publicações aprovadas ou publicadas desse guião. Ler: calendar.read + flag; os vídeos só com media.read e a biblioteca ligada.
create or replace function public.pub_record_options(p_ws text, p_id uuid default null, p_version uuid default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p pub_publications; v media_versions; a media_assets; content text; media_ok boolean; tz text;
begin
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.record_options', coalesce(p_id::text, p_version::text));
  if (p_id is null) = (p_version is null) then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
  media_ok := public.ws_can('media.read', p_ws, p_token) and public._flag_on('media.library', p_ws, p_token);
  if p_id is not null then
    select * into p from pub_publications where id = p_id and workspace_id = p_ws;
    if p.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
    content := p.content_id;
  else
    if not media_ok then raise exception 'video_nao_encontrado' using errcode = 'P0002'; end if;
    select * into v from media_versions where id = p_version and workspace_id = p_ws and state = 'pronta';
    select * into a from media_assets where id = v.asset_id and workspace_id = p_ws and lifecycle = 'ativo';
    if v.id is null or a.id is null then raise exception 'video_nao_encontrado' using errcode = 'P0002'; end if;
    content := a.content_id;
  end if;
  return jsonb_build_object(
    'timezone', tz,
    'can_record', auth.uid() is not null and public.ws_can('publishing.publish', p_ws, p_token),
    'media_available', media_ok,
    'video', case when v.id is not null then jsonb_build_object('version_id', v.id, 'version', v.version_no, 'asset_id', a.id, 'title', a.title,
               'approved', public._review_status(v.id) = 'approved', 'current', a.current_version_id = v.id) end,
    'publications', case when content is null then '[]'::jsonb else coalesce((select jsonb_agg(public._pub_json(x, p_token) order by x.scheduled_at, x.id)
       from pub_publications x where x.workspace_id = p_ws and x.content_id = content and x.status in ('aprovada', 'publicada')
         and (p_id is null or x.id = p_id)), '[]') end,
    'videos', case when not media_ok or content is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
         'version_id', cv.id, 'version', cv.version_no, 'asset_id', ma.id, 'title', ma.title, 'variant', public._review_variant(ma.tags),
         'style', public._review_style(ma.tags), 'status', public._review_status(cv.id),
         'eligible', public._review_status(cv.id) = 'approved')
       order by (public._review_status(cv.id) = 'approved') desc, ma.title, ma.id)
       from media_assets ma join media_versions cv on cv.id = ma.current_version_id
       where ma.workspace_id = p_ws and ma.content_id = content and ma.lifecycle = 'ativo' and cv.state = 'pronta'
         and ma.kind in ('video', 'link_externo')), '[]') end);
end $$;

-- ───────────── escrita: registar a publicação manual (FR-12-02) ─────────────
-- p_input: {url, published_at, media_version_id, revision?}. p_reason só para corrigir um registo já feito (3 a 500 caracteres).
create or replace function public.pub_record_published(p_ws text, p_id uuid, p_input jsonb, p_reason text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a jsonb; cur pub_publications; n pub_publications; g guioes; acc accounts; v media_versions;
        post jsonb; ext text; v_url text; v_at timestamptz; reason text := nullif(btrim(coalesce(p_reason, '')), ''); lin jsonb; l publication_lineage;
        lid bigint; tz text; who uuid; before jsonb; li jsonb; dup boolean;
begin
  perform public._pub_require('publishing.publish', p_ws, p_token, 'pub.record_published', p_id::text);
  if uid is null then raise exception 'identidade_individual' using errcode = '42501', detail = 'Registar uma publicação exige sessão individual.'; end if;
  a := public._content_actor(p_token);
  if jsonb_typeof(coalesce(p_input, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
  if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if cur.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
  if cur.status = 'planeada' then
    raise exception 'publicacao_por_aprovar' using errcode = '22023',
      detail = 'Esta publicação ainda não está aprovada. Só se regista uma publicação com a versão e o destino aprovados.'; end if;
  if nullif(p_input->>'revision', '') is not null and (p_input->>'revision')::int <> cur.revision then
    raise exception 'revisao_mudou' using errcode = '40001', detail = 'A publicação mudou desde que a abriste. Fecha e abre outra vez.'; end if;
  select * into acc from accounts where id = cur.account_id and client_id = p_ws and role = 'client';
  if acc.id is null then raise exception 'conta_nao_encontrada' using errcode = 'P0002'; end if;

  -- URL do post, pela plataforma da conta
  post := public._pub_post_url(cur.platform, p_input->>'url');
  if post is null then raise exception 'url_invalido' using errcode = '22023', detail = public._pub_url_hint(cur.platform); end if;
  if nullif(post->>'handle', '') is not null and post->>'handle' <> lower(acc.handle) then
    raise exception 'url_de_outra_conta' using errcode = '22023', detail = format('Este link é de @%s, não de @%s (a conta desta publicação).', post->>'handle', acc.handle); end if;
  ext := post->>'external_id'; v_url := post->>'url';

  -- hora da publicação: não no futuro, nem antes da aprovação (AGENTS §2.7)
  begin v_at := nullif(p_input->>'published_at', '')::timestamptz; exception when others then v_at := null; end;
  if v_at is null then raise exception 'hora_obrigatoria' using errcode = '22023', detail = 'Indica o dia e a hora em que foi publicado.'; end if;
  if v_at > now() + interval '5 minutes' then raise exception 'hora_futura' using errcode = '22023', detail = 'A hora de publicação não pode ser no futuro.'; end if;
  if cur.approved_at is not null and v_at < cur.approved_at - interval '5 minutes' then
    raise exception 'publicado_antes_da_aprovacao' using errcode = '22023',
      detail = 'A hora indicada é anterior à aprovação. Só se regista o que saiu depois de aprovado.'; end if;

  -- o vídeo exato, aprovado e atual
  v := public._pub_record_video(p_ws, cur.content_id, nullif(p_input->>'media_version_id', '')::uuid, cur.published_media_version_id);

  -- o mesmo post noutra publicação, ou já gravado na linhagem por outro caminho: recusa (sem duplicar)
  dup := exists (select 1 from pub_publications x where x.account_id = cur.account_id and x.published_external_id = ext and x.id <> cur.id)
      or exists (select 1 from publication_lineage x where x.workspace_id = p_ws and x.account_id = cur.account_id and x.external_id = ext
                 and x.lineage_mode = 'gravada' and x.id is distinct from cur.lineage_id);
  if dup then raise exception 'url_ja_registada' using errcode = '22023', detail = 'Este post já está registado noutra publicação.'; end if;
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);

  if cur.status = 'publicada' then
    -- repetir o mesmo registo: nada a fazer (idempotente)
    if cur.published_external_id = ext and cur.published_media_version_id = v.id and date_trunc('minute', cur.published_at) = date_trunc('minute', v_at) then
      return public._pub_json(cur, p_token) || jsonb_build_object('replayed', true, 'corrected', false);
    end if;
    if reason is null then
      raise exception 'ja_publicada' using errcode = '22023',
        detail = 'Esta publicação já está registada. Para mudar o link, a hora ou o vídeo, corrige com um motivo.'; end if;
    if char_length(reason) < 3 or char_length(reason) > 500 then
      raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Explica porque corriges (3 a 500 caracteres).'; end if;
    -- correção auditada: atualiza a mesma linhagem gravada (o publication_id e a ligação não mudam)
    select * into l from publication_lineage where id = cur.lineage_id for update;
    before := jsonb_build_object('url', cur.published_url, 'external_id', cur.published_external_id, 'published_at', cur.published_at,
                                 'media_version_id', cur.published_media_version_id);
    li := public._pub_record_lineage_input(cur, v, ext, v_url, v_at);
    if l.external_id <> ext then
      delete from publication_lineage where workspace_id = p_ws and account_id = cur.account_id and external_id = ext and lineage_mode = 'inferida';
    end if;
    perform set_config('pub.correcting', l.id::text, true);
    update publication_lineage set external_id = ext, url = v_url, published_at = v_at,
           local_hour = extract(hour from v_at at time zone coalesce(l.local_tz, tz))::int, asset_ref = li->>'asset_ref',
           duration_s = nullif(li->>'duration_s', '')::numeric, hook_index = nullif(li->>'hook_index', '')::int,
           hook_text = (select left(cv.hooks -> (li->>'hook_index')::int ->> 'text', 500) from content_versions cv where cv.id = cur.content_version_id and li->>'hook_index' is not null),
           hook_mechanism = (select public._perf_mech(cv.hooks -> (li->>'hook_index')::int ->> 'mecanismo') from content_versions cv where cv.id = cur.content_version_id and li->>'hook_index' is not null),
           edit_style_key = li->>'edit_style_key', edit_style_version = nullif(li->>'edit_style_version', '')::int, updated_at = now()
     where id = l.id;
    perform set_config('pub.correcting', '', true);
    perform set_config('pub.recording', cur.id::text, true);
    update pub_publications set published_at = v_at, published_url = v_url, published_external_id = ext, published_media_version_id = v.id,
           published_corrections = published_corrections + 1
     where id = cur.id returning * into n;
    perform set_config('pub.recording', '', true);
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
    values (uid, 'user', a->>'label', p_ws, 'pub.published_corrected', 'pub_publication', n.id::text, before,
            jsonb_build_object('url', v_url, 'external_id', ext, 'published_at', v_at, 'media_version_id', v.id, 'reason', reason, 'lineage_id', l.id),
            n.correlation_id);
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (p_ws, 'publication.published_corrected', 'publication', n.id::text,
            jsonb_build_object('lineage_id', l.id, 'account_id', n.account_id, 'external_id', ext, 'published_at', v_at, 'media_version_id', v.id));
    return public._pub_json(n, p_token) || jsonb_build_object('replayed', false, 'corrected', true);
  end if;

  -- primeira vez: volta a verificar a aprovação (FR-21-02) e grava a linhagem no momento (R-18)
  if cardinality(public._pub_missing(cur)) > 0 then
    raise exception 'aprovacao_invalida' using errcode = '22023', detail = 'A aprovação desta publicação já não vale. Aprova outra vez.'; end if;
  select * into g from guioes where id = cur.content_id;
  if g.approved_version_id is distinct from cur.content_version_id then
    raise exception 'versao_por_aprovar' using errcode = '22023', detail = 'A versão do guião desta publicação já não é a aprovada. Revê a publicação antes de registar.'; end if;
  lin := public._perf_record_lineage(p_ws, public._pub_record_lineage_input(cur, v, ext, v_url, v_at), a);
  lid := (lin->>'id')::bigint;
  perform public._pub_link_lineage(cur.id, lid);
  perform set_config('pub.recording', cur.id::text, true);
  update pub_publications set status = 'publicada', published_at = v_at, published_url = v_url, published_external_id = ext,
         published_media_version_id = v.id, published_by = uid, published_label = a->>'label', published_recorded_at = now(), publish_mode = 'manual'
   where id = cur.id returning * into n;
  perform set_config('pub.recording', '', true);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values (uid, 'user', a->>'label', p_ws, 'pub.published_recorded', 'pub_publication', n.id::text,
          jsonb_build_object('status', cur.status, 'revision', cur.revision),
          jsonb_build_object('status', n.status, 'revision', n.revision, 'mode', 'manual', 'url', v_url, 'external_id', ext, 'published_at', v_at,
                             'media_version_id', v.id, 'lineage_id', lid, 'account_id', n.account_id, 'platform', n.platform), n.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'publication.published', 'publication', n.id::text,
          jsonb_build_object('mode', 'manual', 'revision', n.revision, 'lineage_id', lid, 'account_id', n.account_id, 'platform', n.platform,
                             'external_id', ext, 'published_at', v_at, 'media_version_id', v.id, 'local_day', (v_at at time zone tz)::date));
  -- avisa quem planeou, quem aprovou esta revisão e o responsável do guião; falhar o aviso nunca desfaz o registo
  begin
    for who in select distinct x from (
        select cur.created_by x union all select cur.revision_by union all select g.owner_id
        union all select ap.actor_user_id from pub_approvals ap where ap.publication_id = cur.id and ap.revision = cur.revision and ap.invalidated_at is null) s
      where x is not null loop
      perform public._notify(who, p_ws, 'publication_published', 'publication', n.id::text,
        'Publicado: guião ' || g.n || ' em @' || acc.handle, coalesce(a->>'label', 'Alguém') || ' registou ' || v_url, 'publication_published:' || n.id);
    end loop;
  exception when others then
    raise log 'pub_record_published_notify % falhou: % %', n.id, sqlstate, sqlerrm;
  end;
  return public._pub_json(n, p_token) || jsonb_build_object('replayed', false, 'corrected', false);
end $$;

-- ───────────── leitura existente: acrescenta o registo (igual a W7 + chaves novas) ─────────────
create or replace function public._pub_json(p pub_publications, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); me jsonb := case when uid is not null then public._pub_actor_side(p.workspace_id, uid) end;
        agency boolean := coalesce(me->>'side', '') = 'agencia'; tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p.workspace_id);
        pol pub_approval_policies := public._pub_policy(p.workspace_id); missing text[] := public._pub_missing(p);
        cap text := case when p.kind = 'republicacao' then 'publishing.republish.approve' else 'publishing.approve' end; g guioes; cv content_versions;
        v pub_variants; acc accounts; conflicts jsonb; why text; rec text; pmv media_versions; pma media_assets;
begin
  select * into g from guioes where id = p.content_id;
  select * into cv from content_versions where id = p.content_version_id;
  select * into acc from accounts where id = p.account_id;
  if p.variant_id is not null then select * into v from pub_variants where id = p.variant_id; end if;
  if p.published_media_version_id is not null then
    select * into pmv from media_versions where id = p.published_media_version_id;
    select * into pma from media_assets where id = pmv.asset_id;
  end if;
  conflicts := case when p.status in ('cancelada', 'publicada') then '[]'::jsonb else public._pub_conflicts(p, agency) end;
  why := case
    when p.status <> 'planeada' then null
    when uid is null or not public.ws_can(cap, p.workspace_id, p_token) then 'sem_capacidade'
    when pol.forbid_self and uid in (p.created_by, p.revision_by) then 'autoaprovacao'
    when exists (select 1 from pub_approvals a where a.publication_id = p.id and a.revision = p.revision and a.actor_user_id = uid and a.invalidated_at is null) then 'ja_aprovaste'
    when cardinality(missing) > 0 and not ('qualquer' = any(missing) or (me->>'side') = any(missing)) then 'parte_errada'
    when g.approved_version_id is distinct from p.content_version_id then 'versao_por_aprovar'
    when public._pub_blocking(conflicts) is not null then 'conflito'
    when p.scheduled_at <= now() then 'hora_passada'
  end;
  rec := public._pub_record_blocked(p, p_token);
  return jsonb_build_object(
    'id', p.id, 'status', p.status, 'kind', p.kind, 'revision', p.revision, 'approved_revision', p.approved_revision, 'approved_at', p.approved_at,
    'lock_version', p.lock_version, 'correlation_id', p.correlation_id, 'lineage_id', p.lineage_id, 'parent_publication_id', p.parent_publication_id,
    'content_id', p.content_id, 'content_n', g.n, 'content_date', g.date, 'content_tema', g.tema, 'content_hook', g.hooks->0->>'text',
    'content_version_id', p.content_version_id, 'version_no', cv.version_no, 'version_approved', g.approved_version_id = p.content_version_id,
    'variant', case when v.id is not null then jsonb_build_object('id', v.id, 'label', v.label, 'elements', v.elements,
                 'changes', public._pub_variant_diff(v.elements, '{}'), 'counts_as_new', public._pub_variant_diff(v.elements, '{}') >= 2,
                 'edit_style_key', v.edit_style_key, 'edit_style_version', v.edit_style_version) end,
    'account_id', p.account_id, 'account_handle', acc.handle, 'account_label', acc.label, 'platform', p.platform,
    'scheduled_at', p.scheduled_at, 'local_day', (p.scheduled_at at time zone tz)::date, 'local_time', to_char(p.scheduled_at at time zone tz, 'HH24:MI'),
    'caption', p.caption, 'hashtags', to_jsonb(p.hashtags), 'cancelled_reason', p.cancelled_reason,
    'created_label', p.created_label, 'revision_label', p.revision_label, 'updated_at', p.updated_at,
    'missing', to_jsonb(case when p.status = 'planeada' then missing else '{}'::text[] end),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('side', a.side, 'actor_label', a.actor_label, 'actor_role', a.actor_role,
        'revision', a.revision, 'decided_at', a.decided_at, 'invalidated_at', a.invalidated_at, 'invalidated_reason', a.invalidated_reason) order by a.decided_at)
      from pub_approvals a where a.publication_id = p.id), '[]'),
    'conflicts', conflicts,
    'can_approve', why is null and p.status = 'planeada', 'approve_blocked', why,
    'published', case when p.status = 'publicada' then jsonb_build_object('mode', p.publish_mode, 'url', p.published_url,
        'external_id', p.published_external_id, 'at', p.published_at, 'local_day', (p.published_at at time zone tz)::date,
        'local_time', to_char(p.published_at at time zone tz, 'HH24:MI'), 'media_version_id', p.published_media_version_id,
        'media_version_no', pmv.version_no, 'asset_id', pma.id, 'asset_title', pma.title, 'by_label', p.published_label,
        'recorded_at', p.published_recorded_at, 'corrections', p.published_corrections,
        'history', coalesce((select jsonb_agg(jsonb_build_object('action', e.action, 'at', e.at, 'by', e.actor_label,
            'reason', e.after->>'reason', 'before_url', e.before->>'url', 'url', e.after->>'url') order by e.at)
          from audit_events e where e.workspace_id = p.workspace_id and e.entity_type = 'pub_publication' and e.entity_id = p.id::text
            and e.action in ('pub.published_recorded', 'pub.published_corrected')), '[]')) end,
    'can_record', rec is null, 'record_blocked', rec);
end $$;

create or replace function public.pub_calendar(p_ws text, p_from date, p_to date, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; org uuid; pol pub_approval_policies;
begin
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.calendar', null);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then raise exception 'intervalo_invalido' using errcode = '22023'; end if;
  select coalesce(timezone, 'Asia/Dubai'), organization_id into tz, org from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  pol := public._pub_policy(p_ws);
  return jsonb_build_object(
    'today', today, 'timezone', tz,
    'publications', coalesce((select jsonb_agg(public._pub_json(p, p_token) order by p.scheduled_at, p.id) from pub_publications p
       where p.workspace_id = p_ws and (p.scheduled_at at time zone tz)::date between p_from and p_to), '[]'),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'platform', a.platform, 'handle', a.handle, 'label', a.label, 'active', a.active,
         'connection_state', coalesce(s.connection_state, 'por_ligar'), 'token_expires_at', s.token_expires_at) order by a.platform, a.handle)
       from accounts a left join social_accounts s on s.account_id = a.id where a.client_id = p_ws and a.role = 'client'), '[]'),
    'limits', public._pub_limits_json(p_ws),
    'policy', jsonb_build_object('required', pol.required, 'forbid_self', pol.forbid_self, 'updated_at', pol.updated_at, 'updated_label', pol.updated_label),
    'me', case when auth.uid() is not null then public._pub_actor_side(p_ws, auth.uid()) end,
    'can', jsonb_build_object('schedule', public.ws_can('publishing.schedule', p_ws, p_token), 'approve', public.ws_can('publishing.approve', p_ws, p_token),
      'republish_approve', public.ws_can('publishing.republish.approve', p_ws, p_token), 'policy', public.ws_can('publishing.policy.manage', p_ws, p_token),
      'accounts', public.ws_can('social_accounts.manage', p_ws, p_token), 'limits', org is not null and public._org_can('publishing.limits.manage', org),
      'record', auth.uid() is not null and public.ws_can('publishing.publish', p_ws, p_token)),
    'publish_available', false,
    'publish_unavailable_reason', 'Publicação automática chega quando as plataformas aprovarem a app.');
end $$;

-- ───────────── notificação (catálogo W8) e destino na caixa ─────────────
-- o check é refeito a partir da definição atual (outras migrações juntam tipos: system_health, prazos)
do $$
declare def text; kinds text[];
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  if def is not null and position('''publication_published''' in def) > 0 then return; end if;
  kinds := coalesce(array(select m[1] from regexp_matches(coalesce(def, ''), '''([a-z_]+)''', 'g') m), '{}') || array['publication_published'];
  alter table public.notifications drop constraint if exists notifications_kind_check;
  execute format('alter table public.notifications add constraint notifications_kind_check check (kind in (%s))',
                 (select string_agg(quote_literal(k), ', ') from unnest(kinds) k));
end $$;
insert into public.notification_event_defs (kind, group_key, label, description, recipients, channels, default_channels, mandatory, mandatory_reason, sort) values
  ('publication_published', 'guioes', 'Publicação registada', 'Uma publicação que planeaste ou aprovaste, ou de um guião teu, foi registada como publicada, com o link.',
   'Quem planeou ou mudou a publicação, quem a aprovou e quem é responsável pelo guião', '{in_app,email,digest}', '{in_app}', false, null, 160)
on conflict (kind) do update set group_key = excluded.group_key, label = excluded.label, description = excluded.description,
  recipients = excluded.recipients, channels = excluded.channels, default_channels = excluded.default_channels, sort = excluded.sort;

do $patch$
declare d text; old text := $o$when 'agent_job' then '/agentes/configuracao'$o$;
begin
  d := pg_get_functiondef('public._ops_queue(text)'::regprocedure);
  if position($q$when 'publication' then$q$ in d) > 0 then return; end if;          -- já aplicado
  if position(old in d) = 0 then raise exception '_ops_queue mudou: rever W10-03'; end if;
  execute replace(d, old, old || E'\n               when ''publication'' then coalesce((select ''/calendario?l=pub&v=day&d='' || (pp.scheduled_at at time zone coalesce(cc.timezone, ''Asia/Dubai''))::date || ''&pub='' || pp.id from pub_publications pp join clients cc on cc.id = pp.workspace_id where pp.id::text = n.entity_id), ''/calendario?l=pub'')');
end $patch$;

-- ───────────── privilégios ─────────────
revoke all on function public._pub_post_url(text, text), public._pub_url_hint(text), public._pub_record_video(text, text, uuid, uuid),
  public._pub_record_lineage_input(pub_publications, media_versions, text, text, timestamptz), public._pub_record_blocked(pub_publications, text)
  from public, anon, authenticated;
revoke all on function public.pub_record_options(text, uuid, uuid, text), public.pub_record_published(text, uuid, jsonb, text, text) from public;
grant execute on function public.pub_record_options(text, uuid, uuid, text), public.pub_record_published(text, uuid, jsonb, text, text) to anon, authenticated;
-- anon (código de equipa) chega à função mas é recusado: sem publishing.publish no código e sem sessão individual.

/* Rollback (compatível enquanto nenhuma publicação estiver `publicada`; se houver, exportar antes e decidir com o owner):
   drop function if exists public.pub_record_published(text, uuid, jsonb, text, text), public.pub_record_options(text, uuid, uuid, text),
     public._pub_record_blocked(pub_publications, text), public._pub_record_lineage_input(pub_publications, media_versions, text, text, timestamptz),
     public._pub_record_video(text, text, uuid, uuid), public._pub_url_hint(text), public._pub_post_url(text, text);
   reaplicar pub_publications_guard de 20261030075917_w7_pub_p1.sql, perf_lineage_guard de 20261030075020_w6_perf_p1.sql,
     _pub_json e pub_calendar de 20261030080025_w7_pub_p2.sql, e _ops_queue sem a linha 'publication' (como em W5-05);
   delete from notifications where kind = 'publication_published'; delete from notification_suppressions where kind = 'publication_published';
   delete from notification_user_prefs where kind = 'publication_published'; delete from notification_ws_prefs where kind = 'publication_published';
   delete from notification_event_defs where kind = 'publication_published'; repor notifications_kind_check sem o tipo;
   drop index if exists public.pub_publications_post;
   alter table public.pub_publications drop constraint if exists pub_publications_published_check;
   alter table public.pub_publications drop constraint if exists pub_publications_approved_check;
   alter table public.pub_publications add constraint pub_publications_check1 check ((status = 'aprovada') = (approved_revision is not null and approved_revision = revision));
   alter table public.pub_publications drop constraint pub_publications_status_check;
   alter table public.pub_publications add constraint pub_publications_status_check check (status in ('planeada', 'aprovada', 'cancelada'));
   delete from role_capabilities where scope = 'ws' and role = 'manager' and capability = 'publishing.publish';
   update capabilities set status = 'W6', label = 'Publicar' where key = 'publishing.publish';
   contract posterior (só depois de exportar): alter table public.pub_publications drop column published_at, drop column published_url,
     drop column published_external_id, drop column published_media_version_id, drop column published_by, drop column published_label,
     drop column published_recorded_at, drop column publish_mode, drop column published_corrections; */
