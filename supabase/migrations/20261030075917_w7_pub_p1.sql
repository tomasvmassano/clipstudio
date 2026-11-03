-- Parte 1 de 4 de 20261030110100_w7_pub.sql (aplicada em produção como w7_pub_p1).
-- W7 · Planeamento e aprovação de publicações (PRD §42 PUB-02, PUB-04, PUB-06; TEAM-10; §21 FR-21-01, FR-21-02, FR-21-04;
-- §41 VAR-01; AGENTS §2.7, §6, §8; ADR-0036).
-- Nada aqui publica: não há ação "publicar". As APIs oficiais ainda não estão aprovadas (PLAT-01..03) e não há modo
-- assistido (PUB-03 adiado). Esta camada é o que o publicador futuro (PUB-01) vai executar: cada publicação planeada
-- fica presa à versão exata do conteúdo, à variante e ao destino (conta, plataforma, hora, legenda, hashtags) e só chega a
-- `aprovada` pela RPC de aprovação. Mudar qualquer um destes campos depois cria uma revisão nova e retira a aprovação.
-- Expand (só aditivo): 4 capacidades novas, 2 ativadas, 1 flag, 6 tabelas fechadas à API, funções novas. Não muda nenhuma
-- função existente (calendar_range, content_*, perf_* ficam iguais). Única mudança a algo existente: capabilities_key_check
-- passa a aceitar chaves com 3 segmentos (só alarga). Rollback no fim.

-- ───────────── capacidades e flag ─────────────
-- O PRD nomeia `publishing.republish.approve` (PUB-06): a chave passa a aceitar até 3 segmentos. Só alarga (compatível
-- com main: todas as chaves atuais continuam válidas).
alter table public.capabilities drop constraint if exists capabilities_key_check;
alter table public.capabilities add constraint capabilities_key_check check (key ~ '^[a-z_]+(\.[a-z_]+){1,2}$');
insert into capabilities (key, module, risk, scopes, status, label) values
  ('publishing.approve', 'Publicação', 'A', array['ws'], 'ativo', 'Aprovar publicações (originais): versão e destino'),
  ('publishing.republish.approve', 'Publicação', 'A', array['ws'], 'ativo', 'Aprovar republicações'),
  ('publishing.policy.manage', 'Publicação', 'A', array['ws'], 'ativo', 'Definir quem tem de aprovar publicações neste cliente'),
  ('publishing.limits.manage', 'Publicação', 'A', array['org'], 'ativo', 'Editar os limites das APIs das plataformas')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
-- publishing.schedule e social_accounts.manage existiam como "W6" (planeadas); passam a ser usadas. publishing.publish fica W6.
update capabilities set status = 'ativo', label = 'Planear publicações (conta, hora, legenda, variante)' where key = 'publishing.schedule';
update capabilities set status = 'ativo', label = 'Gerir contas sociais do cliente' where key = 'social_accounts.manage';
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'publishing.schedule'), ('ws', 'workspace_admin', 'publishing.schedule'), ('ws', 'manager', 'publishing.schedule'),
  ('ws', 'workspace_owner', 'publishing.approve'), ('ws', 'workspace_admin', 'publishing.approve'), ('ws', 'manager', 'publishing.approve'),
  ('ws', 'workspace_owner', 'publishing.republish.approve'), ('ws', 'workspace_admin', 'publishing.republish.approve'),
  ('ws', 'workspace_owner', 'publishing.policy.manage'), ('ws', 'workspace_admin', 'publishing.policy.manage'),
  ('ws', 'workspace_owner', 'social_accounts.manage'), ('ws', 'workspace_admin', 'social_accounts.manage'),
  ('org', 'agency_owner', 'publishing.limits.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('pub.planning', 'Calendário de publicações', 'Publicação', 'ws', 'owner',
   'Publicações planeadas por conta e plataforma no calendário, limites das APIs, variantes (VAR-01) e aprovação da versão e do destino. Não publica nada: a publicação automática chega quando as plataformas aprovarem a app.')
on conflict do nothing;

-- ───────────── FR-21-01: contas sociais por conta (credenciais nunca partilhadas) ─────────────
-- Uma linha por conta do cliente (accounts.role = 'client'). Hoje todas "por ligar": não há OAuth (PLAT-02/03).
-- Quando houver, o token vive no Vault do Supabase e aqui só fica a referência (token_ref), única por conta: um token
-- nunca serve duas contas nem dois clientes.
create table if not exists public.social_accounts (
  account_id text primary key references public.accounts(id),
  workspace_id text not null references public.clients(id),
  connection_state text not null default 'por_ligar' check (connection_state in ('por_ligar', 'ligada', 'expirada', 'revogada')),
  token_ref text unique check (token_ref is null or token_ref ~ '^vault:[0-9a-f-]{36}$'),
  scopes text[] not null default '{}',
  token_expires_at timestamptz,
  connected_at timestamptz,
  connected_label text,
  updated_at timestamptz not null default now(),
  check (token_ref is null or connection_state in ('ligada', 'expirada'))
);
create index if not exists social_accounts_ws on public.social_accounts (workspace_id);

create or replace function public.social_accounts_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from accounts a where a.id = new.account_id and a.client_id = new.workspace_id and a.role = 'client') then
    raise exception 'conta_de_outro_cliente' using errcode = '42501', detail = 'A conta social tem de ser deste cliente.';
  end if;
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then
    raise exception 'conta_de_outro_cliente' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists social_accounts_guard on public.social_accounts;
create trigger social_accounts_guard before insert or update on public.social_accounts for each row execute function public.social_accounts_guard();

insert into social_accounts (account_id, workspace_id)
select a.id, a.client_id from accounts a where a.role = 'client' and a.client_id is not null
on conflict do nothing;

-- ───────────── PUB-02: limites das APIs como dados, por organização e plataforma ─────────────
-- Valores do PRD §42 (verificados 2026-10-29). Só o dono da agência edita (publishing.limits.manage). Regras de
-- republicação de VAR-05 [pressuposto] ficam ao lado, como avisos.
create table if not exists public.pub_platform_limits (
  organization_id uuid not null references public.organizations(id),
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  max_posts int not null check (max_posts between 1 and 10000),
  window_kind text not null check (window_kind in ('rolling_24h', 'calendar_day')),
  window_tz text not null default 'UTC',
  scope text not null check (scope in ('conta', 'projeto')),
  public_requires_audit boolean not null default false,
  note text check (note is null or char_length(note) <= 500),
  verified_on date not null,
  republish_min_days int check (republish_min_days is null or republish_min_days between 0 and 365),
  republish_max_share numeric check (republish_max_share is null or republish_max_share between 0 and 1),
  republish_identical boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_label text,
  primary key (organization_id, platform)
);

create or replace function public._pub_seed_limits(p_org uuid) returns void
language sql security definer set search_path = public as $$
  insert into pub_platform_limits (organization_id, platform, max_posts, window_kind, window_tz, scope, public_requires_audit, note, verified_on,
    republish_min_days, republish_max_share, republish_identical, updated_label)
  values
    (p_org, 'instagram', 100, 'rolling_24h', 'UTC', 'conta', false,
     '100 publicações por API por conta em 24 h móveis.', date '2026-10-29', 30, 0.15, false, 'PRD §42'),
    (p_org, 'tiktok', 15, 'rolling_24h', 'UTC', 'conta', true,
     'Cerca de 15 por dia por conta de criador, partilhado entre apps (o que outras apps usam não se vê aqui); só público depois da auditoria do Content Posting API. Janela de 24 h móveis [pressuposto].',
     date '2026-10-29', 21, 0.20, true, 'PRD §42'),
    (p_org, 'youtube', 100, 'calendar_day', 'America/Los_Angeles', 'projeto', false,
     '100 uploads por dia por projeto Google por defeito: conta todos os clientes da agência. O dia reinicia à meia-noite do Pacífico [pressuposto].',
     date '2026-10-29', 30, 0.10, false, 'PRD §42')
  on conflict do nothing;
$$;
do $$ declare o record; begin for o in select id from organizations loop perform public._pub_seed_limits(o.id); end loop; end $$;

-- ───────────── TEAM-10: política de aprovação por cliente ─────────────
create table if not exists public.pub_approval_policies (
  workspace_id text primary key references public.clients(id),
  required text not null default 'qualquer' check (required in ('qualquer', 'agencia', 'cliente', 'ambos')),
  forbid_self boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  updated_label text
);

-- ───────────── VAR-01: variantes como registos (conteúdo + versão + estilo + 5 elementos) ─────────────
-- elements: o que a variante muda em relação ao original em cada um dos 5 elementos (texto curto); chave ausente =
-- igual ao original. Layout, cor, letra (o estilo) não são elementos e contam zero. Imutável: mudar = variante nova.
create table if not exists public.pub_variants (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id),
  content_version_id uuid not null references public.content_versions(id),
  label text not null check (char_length(label) between 1 and 80),
  platform text check (platform is null or platform in ('instagram', 'tiktok', 'youtube')),
  edit_style_key text,
  edit_style_version int,
  elements jsonb not null default '{}',
  supersedes_id uuid references public.pub_variants(id),
  archived_at timestamptz,
  created_by uuid,
  created_label text,
  created_at timestamptz not null default now(),
  foreign key (workspace_id, edit_style_key, edit_style_version) references public.edit_style_versions(workspace_id, key, version)
);
create index if not exists pub_variants_content on public.pub_variants (workspace_id, content_id);

-- ───────────── PUB-04 / PUB-06 / FR-21-02: publicações planeadas ─────────────
-- status: planeada → aprovada (só pela RPC de aprovação) → (publicador futuro: a_publicar/publicada/falhou) ; cancelada.
-- revision sobe sempre que muda a versão, a variante ou o destino; as aprovações valem só para a revisão aprovada.
-- correlation_id = 'pub:<id>' é o que o publicador passa a perf_record_lineage (FR-21-04); lineage_id liga a linha
-- gravada de publication_lineage depois de publicar.
create table if not exists public.pub_publications (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id),
  content_version_id uuid not null references public.content_versions(id),
  variant_id uuid references public.pub_variants(id),
  account_id text not null references public.accounts(id),
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  scheduled_at timestamptz not null,
  caption text not null default '' check (char_length(caption) <= 2200),
  hashtags text[] not null default '{}' check (cardinality(hashtags) <= 30),
  kind text not null default 'original' check (kind in ('original', 'republicacao')),
  parent_publication_id uuid references public.pub_publications(id),
  status text not null default 'planeada' check (status in ('planeada', 'aprovada', 'cancelada')),
  revision int not null default 1,
  approved_revision int,
  approved_at timestamptz,
  cancelled_reason text check (cancelled_reason is null or char_length(cancelled_reason) <= 500),
  lineage_id bigint references public.publication_lineage(id),
  correlation_id text generated always as ('pub:' || id::text) stored,
  created_by uuid,
  created_label text,
  revision_by uuid,
  revision_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  lock_version int not null default 1,
  check (kind = 'original' or parent_publication_id is not null),
  check ((status = 'aprovada') = (approved_revision is not null and approved_revision = revision))
);
create index if not exists pub_publications_ws_at on public.pub_publications (workspace_id, scheduled_at);
create index if not exists pub_publications_account_at on public.pub_publications (account_id, scheduled_at) where status <> 'cancelada';
create index if not exists pub_publications_content on public.pub_publications (workspace_id, content_id) where status <> 'cancelada';

-- Cada aprovação guarda a revisão, a fotografia exata do que foi aprovado e o seu hash, a parte (agência/cliente), o
-- papel e o ator (TEAM-10). Só de acrescentar; a invalidação marca, não apaga.
create table if not exists public.pub_approvals (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  publication_id uuid not null references public.pub_publications(id),
  revision int not null,
  side text not null check (side in ('agencia', 'cliente')),
  capability text not null,
  actor_user_id uuid not null,
  actor_label text,
  actor_role text not null,
  snapshot jsonb not null,
  snapshot_hash text not null,
  decided_at timestamptz not null default now(),
  invalidated_at timestamptz,
  invalidated_reason text,
  unique (publication_id, revision, actor_user_id)
);
create index if not exists pub_approvals_pub on public.pub_approvals (publication_id, revision);

alter table public.social_accounts enable row level security;
alter table public.pub_platform_limits enable row level security;
alter table public.pub_approval_policies enable row level security;
alter table public.pub_variants enable row level security;
alter table public.pub_publications enable row level security;
alter table public.pub_approvals enable row level security;
revoke all on public.social_accounts, public.pub_platform_limits, public.pub_approval_policies, public.pub_variants,
  public.pub_publications, public.pub_approvals from anon, authenticated;   -- só pelas RPCs

-- ───────────── regras puras ─────────────
create or replace function public._pub_norm(p text) returns text
language sql immutable as $$ select nullif(lower(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))), '') $$;

-- VAR-01: quantos dos 5 elementos diferem entre duas variantes ('{}' = o original). Troca de ativo de contexto sem tese
-- de título nova conta zero.
create or replace function public._pub_variant_diff(a jsonb, b jsonb) returns int
language sql immutable set search_path = public as $$
  select (case when public._pub_norm(a->>'segment') is distinct from public._pub_norm(b->>'segment') then 1 else 0 end)
       + (case when public._pub_norm(a->>'title_thesis') is distinct from public._pub_norm(b->>'title_thesis') then 1 else 0 end)
       + (case when public._pub_norm(a->>'context_asset') is distinct from public._pub_norm(b->>'context_asset')
                and public._pub_norm(a->>'title_thesis') is distinct from public._pub_norm(b->>'title_thesis') then 1 else 0 end)
       + (case when public._pub_norm(a->>'narration') is distinct from public._pub_norm(b->>'narration') then 1 else 0 end)
       + (case when public._pub_norm(a->>'structure') is distinct from public._pub_norm(b->>'structure') then 1 else 0 end)
$$;

create or replace function public._pub_elements_clean(p jsonb) returns jsonb
language plpgsql immutable set search_path = public as $$
declare k text; out jsonb := '{}';
begin
  if p is null or p = 'null'::jsonb then return '{}'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'elementos_invalidos' using errcode = '22023', detail = 'Os elementos têm de ser um objeto.'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('segment', 'title_thesis', 'context_asset', 'narration', 'structure') then
      raise exception 'elementos_invalidos' using errcode = '22023', detail = format('Elemento desconhecido: %s.', k); end if;
    if jsonb_typeof(p->k) not in ('string', 'null') then raise exception 'elementos_invalidos' using errcode = '22023'; end if;
    if char_length(coalesce(p->>k, '')) > 300 then
      raise exception 'elementos_invalidos' using errcode = '22023', detail = 'Cada elemento até 300 caracteres.'; end if;
    if public._pub_norm(p->>k) is not null then out := out || jsonb_build_object(k, btrim(p->>k)); end if;
  end loop;
  return out;
end $$;

create or replace function public._pub_snapshot(p pub_publications) returns jsonb
language sql immutable as $$
  select jsonb_build_object('content_id', p.content_id, 'content_version_id', p.content_version_id, 'variant_id', p.variant_id,
    'account_id', p.account_id, 'platform', p.platform, 'scheduled_at', to_char(p.scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'caption', p.caption, 'hashtags', to_jsonb(p.hashtags), 'kind', p.kind, 'parent_publication_id', p.parent_publication_id)
$$;
create or replace function public._pub_hash(p pub_publications) returns text
language sql immutable set search_path = public as $$ select md5(public._pub_snapshot(p)::text) $$;

create or replace function public._pub_policy(p_ws text) returns pub_approval_policies
language sql stable security definer set search_path = public as $$
  select coalesce((select x from pub_approval_policies x where x.workspace_id = p_ws),
                  row(p_ws, 'qualquer', false, null, null, null)::pub_approval_policies)
$$;

-- Que partes ainda faltam para a revisão atual (vazio = política cumprida).
create or replace function public._pub_missing(p pub_publications) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare pol pub_approval_policies := public._pub_policy(p.workspace_id); h text := public._pub_hash(p); sides text[];
begin
  sides := array(select distinct side from pub_approvals a where a.publication_id = p.id and a.revision = p.revision
                   and a.invalidated_at is null and a.snapshot_hash = h);
  return case pol.required
    when 'qualquer' then case when cardinality(sides) > 0 then '{}'::text[] else array['qualquer'] end
    when 'agencia' then case when 'agencia' = any(sides) then '{}'::text[] else array['agencia'] end
    when 'cliente' then case when 'cliente' = any(sides) then '{}'::text[] else array['cliente'] end
    else array(select s from unnest(array['agencia', 'cliente']) s where not s = any(sides)) end;
end $$;

-- Parte de quem aprova: agência (dono da agência ou staff da agência no cliente) ou cliente (equipa do cliente).
create or replace function public._pub_actor_side(p_ws text, p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from agency_memberships m join clients c on c.organization_id = m.organization_id
                 where c.id = p_ws and m.user_id = p_uid and m.agency_role = 'agency_owner' and m.status = 'active')
      then jsonb_build_object('side', 'agencia', 'role', 'agency_owner')
    else (select jsonb_build_object('side', case when a.affiliation_type = 'agency_staff' then 'agencia' else 'cliente' end, 'role', a.workspace_role)
          from workspace_access a where a.workspace_id = p_ws and a.user_id = p_uid and a.status = 'active') end
$$;

-- ───────────── guardas (a última palavra é dos dados, não da UI) ─────────────
create or replace function public.pub_publications_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare bound boolean;
begin
  if tg_op = 'DELETE' then raise exception 'publicacao_imutavel' using errcode = '42501', detail = 'Publicações planeadas não se apagam; cancelam-se.'; end if;
  if tg_op = 'INSERT' then
    if new.status <> 'planeada' or new.revision <> 1 or new.approved_revision is not null or new.lineage_id is not null then
      raise exception 'estado_inicial_invalido' using errcode = '42501', detail = 'Uma publicação nasce planeada; só a aprovação a torna aprovada.'; end if;
    return new;
  end if;
  if new.id <> old.id or new.workspace_id <> old.workspace_id or new.created_by is distinct from old.created_by then
    raise exception 'publicacao_imutavel' using errcode = '42501'; end if;
  if old.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
  if new.lineage_id is distinct from old.lineage_id and coalesce(current_setting('pub.linking', true), '') <> new.id::text then
    raise exception 'linhagem_so_pelo_publicador' using errcode = '42501'; end if;
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
drop trigger if exists pub_publications_guard on public.pub_publications;
create trigger pub_publications_guard before insert or update or delete on public.pub_publications for each row execute function public.pub_publications_guard();

create or replace function public.pub_approvals_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'aprovacoes_imutaveis' using errcode = '42501'; end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('pub.approving', true), '') <> new.publication_id::text then
      raise exception 'aprovacao_so_pela_rpc' using errcode = '42501'; end if;
    return new;
  end if;
  if old.invalidated_at is not null or (to_jsonb(new) - array['invalidated_at', 'invalidated_reason']) is distinct from (to_jsonb(old) - array['invalidated_at', 'invalidated_reason']) then
    raise exception 'aprovacoes_imutaveis' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists pub_approvals_guard on public.pub_approvals;
create trigger pub_approvals_guard before insert or update or delete on public.pub_approvals for each row execute function public.pub_approvals_guard();

create or replace function public.pub_variants_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'variante_imutavel' using errcode = '42501'; end if;
  if (to_jsonb(new) - 'archived_at') is distinct from (to_jsonb(old) - 'archived_at') then
    raise exception 'variante_imutavel' using errcode = '42501', detail = 'Uma variante não se edita: cria uma variante nova.'; end if;
  return new;
end $$;
drop trigger if exists pub_variants_guard on public.pub_variants;
create trigger pub_variants_guard before update or delete on public.pub_variants for each row execute function public.pub_variants_guard();
