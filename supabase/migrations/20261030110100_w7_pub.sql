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

-- ───────────── conflitos (PUB-04) e limites (PUB-02) ─────────────
-- Devolve [{code, severity: bloqueia|aviso, message}]. p_agency: quem vê é da agência (pode ver contagens do projeto).
create or replace function public._pub_conflicts(p pub_publications, p_agency boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'; tz text; org uuid; lim pub_platform_limits; n int; v pub_variants; ve jsonb := '{}'; other record;
        par pub_publications; pv jsonb := '{}'; g guioes; tot int; rep int; day_start timestamptz;
begin
  select coalesce(timezone, 'Asia/Dubai'), organization_id into tz, org from clients where id = p.workspace_id;
  if p.variant_id is not null then select * into v from pub_variants where id = p.variant_id; ve := coalesce(v.elements, '{}'); end if;

  -- variantes do mesmo corpo nunca na mesma conta no mesmo dia
  if exists (select 1 from pub_publications x where x.workspace_id = p.workspace_id and x.id <> p.id and x.status <> 'cancelada'
             and x.content_id = p.content_id and x.account_id = p.account_id
             and (x.scheduled_at at time zone tz)::date = (p.scheduled_at at time zone tz)::date) then
    out := out || jsonb_build_object('code', 'mesmo_dia_conta', 'severity', 'bloqueia',
      'message', 'Já há uma publicação deste guião nesta conta neste dia. Variantes do mesmo corpo nunca saem na mesma conta no mesmo dia.');
  end if;

  -- limite da API
  select * into lim from pub_platform_limits where organization_id = org and platform = p.platform;
  if lim.platform is not null then
    if lim.window_kind = 'rolling_24h' then
      select max(c) into n from (
        select (select count(*) from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
                  and y.scheduled_at >= w.s and y.scheduled_at < w.s + interval '24 hours'
                  and (case when lim.scope = 'conta' then y.account_id = p.account_id
                            else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end)) + 1 c
        from (select p.scheduled_at s union
              select y.scheduled_at from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
                and y.scheduled_at > p.scheduled_at - interval '24 hours' and y.scheduled_at <= p.scheduled_at
                and (case when lim.scope = 'conta' then y.account_id = p.account_id
                          else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end)) w) q;
    else
      day_start := ((p.scheduled_at at time zone lim.window_tz)::date)::timestamp at time zone lim.window_tz;
      select count(*) + 1 into n from pub_publications y where y.status <> 'cancelada' and y.id <> p.id
        and y.scheduled_at >= day_start and y.scheduled_at < day_start + interval '1 day'
        and (case when lim.scope = 'conta' then y.account_id = p.account_id
                  else y.platform = p.platform and y.workspace_id in (select id from clients where organization_id = org) end);
    end if;
    if n > lim.max_posts then
      out := out || jsonb_build_object('code', 'limite_api', 'severity', 'bloqueia', 'message',
        case when lim.scope = 'projeto' and not p_agency
             then format('O limite da API do %s para esse dia já está esgotado. Escolhe outro dia.', initcap(p.platform))
             else format('Passa o limite da API: %s de %s %s (verificado a %s).', n, lim.max_posts,
                         case when lim.scope = 'conta' then case when lim.window_kind = 'rolling_24h' then 'por conta em 24 h móveis' else 'por conta por dia' end
                              else 'por dia no projeto da agência' end, to_char(lim.verified_on, 'DD/MM/YYYY')) end);
    end if;
    if lim.public_requires_audit then
      out := out || jsonb_build_object('code', 'so_privado', 'severity', 'aviso',
        'message', 'Até à auditoria do Content Posting API, o que for publicado por API nesta plataforma fica privado.');
    end if;
  end if;

  -- VAR-01: variantes irmãs para a mesma plataforma diferem em pelo menos 2 elementos
  if p.kind = 'original' then
    for other in select x.id, coalesce(xv.elements, '{}') el, xv.label, x.variant_id from pub_publications x left join pub_variants xv on xv.id = x.variant_id
                 where x.workspace_id = p.workspace_id and x.id <> p.id and x.status <> 'cancelada' and x.kind = 'original'
                   and x.content_id = p.content_id and x.platform = p.platform loop
      if public._pub_variant_diff(ve, other.el) < 2 then
        out := out || jsonb_build_object('code', 'variante_repetida', 'severity', 'bloqueia', 'message',
          format('Nesta plataforma já está planeada %s deste guião que difere em menos de 2 dos 5 elementos (segmento, tese do título, ativo de contexto, narração, estrutura).',
                 coalesce('a variante "' || other.label || '"', 'a versão original')));
        exit;
      end if;
    end loop;
  end if;
  if p.variant_id is not null and public._pub_variant_diff(ve, '{}') < 2 then
    out := out || jsonb_build_object('code', 'variante_nao_nova', 'severity', 'aviso',
      'message', 'Esta variante muda menos de 2 dos 5 elementos em relação ao original: não conta como variante nova (layout, cor e letra contam zero).');
  end if;

  -- a versão escolhida é a aprovada editorialmente?
  select * into g from guioes where id = p.content_id;
  if g.approved_version_id is distinct from p.content_version_id then
    out := out || jsonb_build_object('code', 'versao_por_aprovar', 'severity', 'aviso',
      'message', 'Esta versão do guião não é a versão aprovada. A publicação só se aprova com a versão aprovada do guião.');
  end if;

  -- republicação (VAR-05, avisos [pressuposto])
  if p.kind = 'republicacao' and lim.platform is not null then
    select * into par from pub_publications where id = p.parent_publication_id;
    if lim.republish_min_days is not null and par.id is not null and p.scheduled_at < par.scheduled_at + make_interval(days => lim.republish_min_days) then
      out := out || jsonb_build_object('code', 'republicacao_cedo', 'severity', 'aviso',
        'message', format('Republicação a menos de %s dias da original nesta plataforma [pressuposto VAR-05].', lim.republish_min_days));
    end if;
    if not lim.republish_identical and par.id is not null then
      if par.variant_id is not null then select coalesce(elements, '{}') into pv from pub_variants where id = par.variant_id; end if;
      if public._pub_variant_diff(ve, pv) < 2 then
        out := out || jsonb_build_object('code', 'republicacao_identica', 'severity', 'aviso',
          'message', 'Esta plataforma não aceita republicações idênticas: precisa de mudar pelo menos 2 elementos [pressuposto VAR-05].');
      end if;
    end if;
    if lim.republish_max_share is not null then
      select count(*) + 1, count(*) filter (where y.kind = 'republicacao') + 1 into tot, rep from pub_publications y
       where y.account_id = p.account_id and y.status <> 'cancelada' and y.id <> p.id
         and y.scheduled_at > p.scheduled_at - interval '30 days' and y.scheduled_at <= p.scheduled_at;
      if rep::numeric / tot > lim.republish_max_share then
        out := out || jsonb_build_object('code', 'republicacao_quota', 'severity', 'aviso',
          'message', format('Republicações nesta conta nos últimos 30 dias: %s de %s, acima de %s%% [pressuposto VAR-05].', rep, tot, round(lim.republish_max_share * 100)));
      end if;
    end if;
  end if;
  return out;
end $$;

create or replace function public._pub_blocking(c jsonb) returns text
language sql immutable as $$
  select string_agg(x->>'message', ' ') from jsonb_array_elements(c) x where x->>'severity' = 'bloqueia'
$$;

-- ───────────── leitura ─────────────
create or replace function public._pub_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, p_entity);
  -- disponibilidade não é autorização, mas uma flag desligada bloqueia com erro explícito (CAP-09)
  if not public._flag_on('pub.planning', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O calendário de publicações ainda não está ligado neste cliente.';
  end if;
end $$;

create or replace function public._pub_json(p pub_publications, p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); me jsonb := case when uid is not null then public._pub_actor_side(p.workspace_id, uid) end;
        agency boolean := coalesce(me->>'side', '') = 'agencia'; tz text := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p.workspace_id);
        pol pub_approval_policies := public._pub_policy(p.workspace_id); missing text[] := public._pub_missing(p);
        cap text := case when p.kind = 'republicacao' then 'publishing.republish.approve' else 'publishing.approve' end; g guioes; cv content_versions;
        v pub_variants; acc accounts; conflicts jsonb; why text;
begin
  select * into g from guioes where id = p.content_id;
  select * into cv from content_versions where id = p.content_version_id;
  select * into acc from accounts where id = p.account_id;
  if p.variant_id is not null then select * into v from pub_variants where id = p.variant_id; end if;
  conflicts := case when p.status = 'cancelada' then '[]'::jsonb else public._pub_conflicts(p, agency) end;
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
    'can_approve', why is null and p.status = 'planeada', 'approve_blocked', why);
end $$;

create or replace function public._pub_limits_json(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('platform', l.platform, 'max_posts', l.max_posts, 'window_kind', l.window_kind, 'window_tz', l.window_tz,
    'scope', l.scope, 'public_requires_audit', l.public_requires_audit, 'note', l.note, 'verified_on', l.verified_on,
    'republish_min_days', l.republish_min_days, 'republish_max_share', l.republish_max_share, 'republish_identical', l.republish_identical,
    'updated_at', l.updated_at, 'updated_label', l.updated_label) order by l.platform), '[]')
  from pub_platform_limits l join clients c on c.organization_id = l.organization_id where c.id = p_ws
$$;

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
      'accounts', public.ws_can('social_accounts.manage', p_ws, p_token), 'limits', org is not null and public._org_can('publishing.limits.manage', org)),
    'publish_available', false,
    'publish_unavailable_reason', 'Publicação automática chega quando as plataformas aprovarem a app.');
end $$;

-- Guiões e versões para escolher ao planear, com as variantes de cada um e a comparação VAR-01.
create or replace function public.pub_content_options(p_ws text, p_content_id text default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.content_options', p_content_id);
  if not public.ws_can('scripts.read', p_ws, p_token) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_content_id is null then
    return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'hook', g.hooks->0->>'text',
        'editorial_status', g.editorial_status, 'approved', g.approved_version_id is not null) order by g.date desc, g.n)
      from (select * from guioes where client_id = p_ws and editorial_status not in ('archived', 'rejected') order by date desc, n limit 200) g), '[]');
  end if;
  if not exists (select 1 from guioes where id = p_content_id and client_id = p_ws) then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'created_at', v.created_at,
        'approved', v.id = g.approved_version_id, 'current', v.id = g.current_version_id) order by v.version_no desc)
      from content_versions v join guioes g on g.id = v.content_id where v.content_id = p_content_id and v.workspace_id = p_ws), '[]'),
    'approved_version_id', (select approved_version_id from guioes where id = p_content_id),
    'variants', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'label', v.label, 'platform', v.platform, 'content_version_id', v.content_version_id,
        'edit_style_key', v.edit_style_key, 'edit_style_version', v.edit_style_version, 'elements', v.elements, 'archived', v.archived_at is not null,
        'changes', public._pub_variant_diff(v.elements, '{}'), 'counts_as_new', public._pub_variant_diff(v.elements, '{}') >= 2,
        'created_at', v.created_at, 'created_label', v.created_label,
        'siblings', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label, 'diff', public._pub_variant_diff(v.elements, o.elements)) order by o.created_at)
                              from pub_variants o where o.content_id = v.content_id and o.id <> v.id and o.archived_at is null
                                and (v.platform is null or o.platform is null or o.platform = v.platform)), '[]')) order by v.created_at)
      from pub_variants v where v.workspace_id = p_ws and v.content_id = p_content_id), '[]'),
    'styles', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'version', s.current_version, 'name', sv.name) order by s.key)
      from edit_styles s join edit_style_versions sv on sv.workspace_id = s.workspace_id and sv.key = s.key and sv.version = s.current_version
      where s.workspace_id = p_ws and s.status = 'ativo'), '[]'));
end $$;

-- ───────────── escrita: variantes ─────────────
create or replace function public.pub_variant_save(p_ws text, p_input jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes; cv content_versions; el jsonb; v pub_variants; o record; plat text; sup pub_variants;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.variant_save', p_input->>'content_id');
  if jsonb_typeof(coalesce(p_input, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  select * into g from guioes where id = p_input->>'content_id' and client_id = p_ws;
  if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
  select * into cv from content_versions where id = coalesce(nullif(p_input->>'content_version_id', '')::uuid, g.approved_version_id, g.current_version_id)
    and content_id = g.id and workspace_id = p_ws;
  if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Escolhe uma versão deste guião.'; end if;
  if char_length(btrim(coalesce(p_input->>'label', ''))) not between 1 and 80 then
    raise exception 'nome_invalido' using errcode = '22023', detail = 'Dá um nome à variante (1 a 80 caracteres).'; end if;
  plat := nullif(p_input->>'platform', '');
  if plat is not null and plat not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
  el := public._pub_elements_clean(p_input->'elements');
  if nullif(p_input->>'edit_style_key', '') is not null and not exists (select 1 from edit_style_versions where workspace_id = p_ws
       and key = p_input->>'edit_style_key' and version = nullif(p_input->>'edit_style_version', '')::int) then
    raise exception 'estilo_invalido' using errcode = '22023', detail = 'Estilo e versão têm de existir neste cliente.'; end if;
  if nullif(p_input->>'supersedes_id', '') is not null then
    select * into sup from pub_variants where id = (p_input->>'supersedes_id')::uuid and workspace_id = p_ws and content_id = g.id;
    if sup.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
  end if;
  -- VAR-01: variantes irmãs para a mesma plataforma diferem em >= 2 elementos (bloqueia)
  if plat is not null then
    for o in select * from pub_variants x where x.workspace_id = p_ws and x.content_id = g.id and x.archived_at is null and x.platform = plat
               and (sup.id is null or x.id <> sup.id) loop
      if public._pub_variant_diff(el, o.elements) < 2 then
        raise exception 'variante_repetida' using errcode = '22023',
          detail = format('Difere da variante "%s" (mesma plataforma) em menos de 2 dos 5 elementos.', o.label); end if;
    end loop;
  end if;
  insert into pub_variants (workspace_id, content_id, content_version_id, label, platform, edit_style_key, edit_style_version, elements, supersedes_id, created_by, created_label)
  values (p_ws, g.id, cv.id, btrim(p_input->>'label'), plat, nullif(p_input->>'edit_style_key', ''),
          case when nullif(p_input->>'edit_style_key', '') is not null then nullif(p_input->>'edit_style_version', '')::int end, el, sup.id,
          (a->>'uid')::uuid, a->>'label')
  returning * into v;
  if sup.id is not null then update pub_variants set archived_at = now() where id = sup.id and archived_at is null; end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.variant_created', 'pub_variant', v.id::text, null, to_jsonb(v) - 'workspace_id');
  return public.pub_content_options(p_ws, g.id, p_token);
end $$;

create or replace function public.pub_variant_archive(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); v pub_variants;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.variant_archive', p_id::text);
  select * into v from pub_variants where id = p_id and workspace_id = p_ws for update;
  if v.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
  if v.archived_at is null then
    update pub_variants set archived_at = now() where id = v.id;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.variant_archived', 'pub_variant', v.id::text);
  end if;
  return public.pub_content_options(p_ws, v.content_id, p_token);
end $$;

-- ───────────── escrita: planear / mudar / cancelar ─────────────
-- p_id nulo cria. Ao mudar, p_lock é o lock_version que a pessoa via (conflito PT409 se mudou). Campos ausentes mantêm-se.
create or replace function public.pub_save(p_ws text, p_id uuid, p_input jsonb, p_lock int default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); cur pub_publications; n pub_publications; g guioes; cv content_versions; acc accounts;
        v pub_variants; par pub_publications; tags text[]; t text; blk text; tz text; me jsonb; created boolean := p_id is null;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, case when created then 'pub.plan' else 'pub.update' end, p_id::text);
  if (a->>'uid') is null then raise exception 'identidade_individual' using errcode = '42501', detail = 'Planear publicações exige sessão individual.'; end if;
  if jsonb_typeof(coalesce(p_input, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if not created then
    select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
    if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
    if cur.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
    if p_lock is not null and p_lock <> cur.lock_version then raise exception 'conflito_edicao' using errcode = 'PT409'; end if;
    n := cur;
  else
    n.id := gen_random_uuid(); n.workspace_id := p_ws; n.kind := 'original'; n.caption := ''; n.hashtags := '{}';
  end if;

  if p_input ? 'content_id' or created then
    select * into g from guioes where id = coalesce(p_input->>'content_id', n.content_id) and client_id = p_ws;
    if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = 'P0002'; end if;
    if g.editorial_status in ('archived', 'rejected') then raise exception 'nao_elegivel' using errcode = '22023', detail = 'Guiões rejeitados ou arquivados não se publicam.'; end if;
    if not created and g.id <> cur.content_id then raise exception 'conteudo_fixo' using errcode = '22023', detail = 'Para outro guião, planeia uma publicação nova.'; end if;
    n.content_id := g.id;
  else select * into g from guioes where id = n.content_id; end if;
  if p_input ? 'content_version_id' or created then
    select * into cv from content_versions where id = coalesce(nullif(p_input->>'content_version_id', '')::uuid, g.approved_version_id, g.current_version_id)
      and content_id = g.id and workspace_id = p_ws;
    if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Escolhe uma versão deste guião.'; end if;
    n.content_version_id := cv.id;
  end if;
  if p_input ? 'variant_id' then n.variant_id := nullif(p_input->>'variant_id', '')::uuid; end if;
  if n.variant_id is not null then
    select * into v from pub_variants where id = n.variant_id and workspace_id = p_ws and content_id = n.content_id;
    if v.id is null then raise exception 'variante_nao_encontrada' using errcode = 'P0002'; end if;
    if v.archived_at is not null and (created or n.variant_id is distinct from cur.variant_id) then
      raise exception 'variante_arquivada' using errcode = '22023', detail = 'Esta variante foi arquivada.'; end if;
    if v.content_version_id <> n.content_version_id then
      raise exception 'variante_de_outra_versao' using errcode = '22023', detail = 'A variante foi feita a partir de outra versão do guião.'; end if;
  end if;
  if p_input ? 'account_id' or created then
    select * into acc from accounts where id = coalesce(p_input->>'account_id', n.account_id) and client_id = p_ws and role = 'client';
    if acc.id is null then raise exception 'conta_nao_encontrada' using errcode = 'P0002', detail = 'A conta não é deste cliente.'; end if;
    if not acc.active then raise exception 'conta_inativa' using errcode = '22023', detail = 'Esta conta está inativa.'; end if;
    if acc.platform not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
    n.account_id := acc.id; n.platform := acc.platform;
  end if;
  if p_input ? 'scheduled_at' or created then
    n.scheduled_at := nullif(p_input->>'scheduled_at', '')::timestamptz;
    if n.scheduled_at is null then raise exception 'hora_obrigatoria' using errcode = '22023', detail = 'Indica o dia e a hora.'; end if;
    if n.scheduled_at <= now() then raise exception 'hora_passada' using errcode = '22023', detail = 'A hora tem de ser no futuro.'; end if;
    if n.scheduled_at > now() + interval '400 days' then raise exception 'data_longe' using errcode = '22023', detail = 'No máximo 400 dias à frente.'; end if;
  end if;
  if p_input ? 'caption' then
    if char_length(coalesce(p_input->>'caption', '')) > 2200 then raise exception 'legenda_longa' using errcode = '22023', detail = 'Legenda até 2200 caracteres.'; end if;
    n.caption := btrim(coalesce(p_input->>'caption', ''));
  end if;
  if p_input ? 'hashtags' then
    if jsonb_typeof(p_input->'hashtags') <> 'array' then raise exception 'hashtags_invalidas' using errcode = '22023'; end if;
    tags := '{}';
    for t in select btrim(x) from jsonb_array_elements_text(p_input->'hashtags') x loop
      if t = '' then continue; end if;
      if left(t, 1) <> '#' then t := '#' || t; end if;
      if t !~ '^#[^\s#]{1,100}$' then raise exception 'hashtags_invalidas' using errcode = '22023', detail = format('Hashtag inválida: %s', t); end if;
      if not t = any(tags) then tags := tags || t; end if;
    end loop;
    if cardinality(tags) > 30 then raise exception 'hashtags_invalidas' using errcode = '22023', detail = 'No máximo 30 hashtags.'; end if;
    n.hashtags := tags;
  end if;
  if created and p_input ? 'kind' then
    if p_input->>'kind' not in ('original', 'republicacao') then raise exception 'tipo_invalido' using errcode = '22023'; end if;
    n.kind := p_input->>'kind';
  end if;
  if created and n.kind = 'republicacao' then
    select * into par from pub_publications where id = nullif(p_input->>'parent_publication_id', '')::uuid and workspace_id = p_ws and content_id = n.content_id;
    if par.id is null or par.status = 'cancelada' then
      raise exception 'origem_republicacao_invalida' using errcode = '22023', detail = 'Indica a publicação original (do mesmo guião, não cancelada).'; end if;
    if par.scheduled_at >= n.scheduled_at then
      raise exception 'origem_republicacao_invalida' using errcode = '22023', detail = 'A republicação tem de ser depois da original.'; end if;
    n.parent_publication_id := par.id;
  end if;

  if not created and public._pub_snapshot(n) is not distinct from public._pub_snapshot(cur) then
    return public._pub_json(cur, p_token);
  end if;
  me := public._pub_actor_side(p_ws, (a->>'uid')::uuid);
  blk := public._pub_blocking(public._pub_conflicts(n, coalesce(me->>'side', '') = 'agencia'));
  if blk is not null then raise exception 'conflito_publicacao' using errcode = '22023', detail = blk; end if;

  if created then
    insert into pub_publications (id, workspace_id, content_id, content_version_id, variant_id, account_id, platform, scheduled_at, caption, hashtags, kind,
      parent_publication_id, created_by, created_label, revision_by, revision_label)
    values (n.id, p_ws, n.content_id, n.content_version_id, n.variant_id, n.account_id, n.platform, n.scheduled_at, n.caption, n.hashtags, n.kind,
      n.parent_publication_id, (a->>'uid')::uuid, a->>'label', (a->>'uid')::uuid, a->>'label')
    returning * into n;
  else
    update pub_publications set content_version_id = n.content_version_id, variant_id = n.variant_id, account_id = n.account_id, platform = n.platform,
      scheduled_at = n.scheduled_at, caption = n.caption, hashtags = n.hashtags, revision_by = (a->>'uid')::uuid, revision_label = a->>'label'
     where id = cur.id returning * into n;
  end if;
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when created then 'pub.planned' else 'pub.changed' end, 'pub_publication', n.id::text,
          case when created then null else public._pub_snapshot(cur) || jsonb_build_object('status', cur.status, 'revision', cur.revision) end,
          public._pub_snapshot(n) || jsonb_build_object('status', n.status, 'revision', n.revision), n.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, case when created then 'publication.planned' when cur.status = 'aprovada' then 'publication.approval_invalidated' else 'publication.changed' end,
          'publication', n.id::text, jsonb_build_object('revision', n.revision, 'from_status', cur.status, 'status', n.status,
          'scheduled_at', n.scheduled_at, 'local_day', (n.scheduled_at at time zone tz)::date, 'account_id', n.account_id));
  return public._pub_json(n, p_token);
end $$;

create or replace function public.pub_cancel(p_ws text, p_id uuid, p_reason text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); cur pub_publications; n pub_publications;
begin
  perform public._pub_require('publishing.schedule', p_ws, p_token, 'pub.cancel', p_id::text);
  select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
  if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if cur.status = 'cancelada' then return public._pub_json(cur, p_token); end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 500 then
    raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Explica porque cancelas (3 a 500 caracteres).'; end if;
  update pub_publications set status = 'cancelada', approved_revision = null, approved_at = null, cancelled_reason = btrim(p_reason) where id = cur.id returning * into n;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.cancelled', 'pub_publication', n.id::text,
          jsonb_build_object('status', cur.status), jsonb_build_object('status', 'cancelada', 'reason', btrim(p_reason)), n.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'publication.cancelled', 'publication', n.id::text, jsonb_build_object('from_status', cur.status, 'revision', n.revision));
  return public._pub_json(n, p_token);
end $$;

-- ───────────── PUB-06 / TEAM-10 / FR-21-02: aprovar ─────────────
-- p_revision é a revisão que a pessoa estava a ver: se entretanto mudou, recusa (40001) em vez de aprovar outra coisa.
create or replace function public.pub_approve(p_ws text, p_id uuid, p_revision int, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a jsonb; cur pub_publications; n pub_publications; cap text; pol pub_approval_policies; me jsonb; missing text[];
        g guioes; blk text; snap jsonb;
begin
  select * into cur from pub_publications where id = p_id and workspace_id = p_ws for update;
  cap := case when cur.kind = 'republicacao' then 'publishing.republish.approve' else 'publishing.approve' end;
  perform public._pub_require(cap, p_ws, p_token, 'pub.approve', p_id::text);
  if uid is null then raise exception 'identidade_individual' using errcode = '42501', detail = 'Aprovar exige sessão individual.'; end if;
  a := public._content_actor(p_token);
  if cur.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if cur.status = 'cancelada' then raise exception 'publicacao_cancelada' using errcode = '22023', detail = 'Esta publicação foi cancelada.'; end if;
  if p_revision is null or p_revision <> cur.revision then
    raise exception 'revisao_mudou' using errcode = '40001', detail = 'A publicação mudou desde que a abriste. Revê a versão nova antes de aprovar.'; end if;
  if cur.status = 'aprovada' then return public._pub_json(cur, p_token); end if;
  pol := public._pub_policy(p_ws);
  if pol.forbid_self and uid in (cur.created_by, cur.revision_by) then
    raise exception 'autoaprovacao_proibida' using errcode = '42501', detail = 'Neste cliente quem planeou ou mudou a publicação não a pode aprovar.'; end if;
  if exists (select 1 from pub_approvals x where x.publication_id = cur.id and x.revision = cur.revision and x.actor_user_id = uid and x.invalidated_at is null) then
    return public._pub_json(cur, p_token); end if;
  me := public._pub_actor_side(p_ws, uid);
  if me is null then raise exception 'sem_permissao' using errcode = '42501'; end if;
  missing := public._pub_missing(cur);
  -- (sem partes em falta, p.ex. depois de a política ficar mais leve, qualquer pessoa com a capacidade confirma)
  if cardinality(missing) > 0 and not ('qualquer' = any(missing) or (me->>'side') = any(missing)) then
    raise exception 'parte_errada' using errcode = '42501', detail = case pol.required
      when 'agencia' then 'Neste cliente a aprovação é da agência (direção criativa).'
      when 'cliente' then 'Neste cliente a aprovação é do cliente.'
      else format('A parte %s já aprovou; falta a outra parte.', case when me->>'side' = 'agencia' then 'da agência' else 'do cliente' end) end;
  end if;
  select * into g from guioes where id = cur.content_id;
  if g.approved_version_id is distinct from cur.content_version_id then
    raise exception 'versao_por_aprovar' using errcode = '22023', detail = 'A versão do guião desta publicação não é a versão aprovada. Aprova o guião ou muda a versão.'; end if;
  if cur.scheduled_at <= now() then raise exception 'hora_passada' using errcode = '22023', detail = 'A hora já passou. Muda a hora antes de aprovar.'; end if;
  blk := public._pub_blocking(public._pub_conflicts(cur, me->>'side' = 'agencia'));
  if blk is not null then raise exception 'conflito_publicacao' using errcode = '22023', detail = blk; end if;

  perform set_config('pub.approving', cur.id::text, true);
  snap := public._pub_snapshot(cur);
  insert into pub_approvals (workspace_id, publication_id, revision, side, capability, actor_user_id, actor_label, actor_role, snapshot, snapshot_hash)
  values (p_ws, cur.id, cur.revision, me->>'side', cap, uid, a->>'label', me->>'role', snap, public._pub_hash(cur));
  if cardinality(public._pub_missing(cur)) = 0 then
    update pub_publications set status = 'aprovada', approved_revision = revision, approved_at = now() where id = cur.id returning * into n;
  else n := cur; end if;
  perform set_config('pub.approving', '', true);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values (uid, 'user', a->>'label', p_ws, case when n.status = 'aprovada' then 'pub.approved' else 'pub.approval_partial' end, 'pub_publication', cur.id::text,
          jsonb_build_object('status', cur.status, 'revision', cur.revision),
          jsonb_build_object('status', n.status, 'revision', n.revision, 'side', me->>'side', 'role', me->>'role', 'capability', cap, 'snapshot', snap), cur.correlation_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, case when n.status = 'aprovada' then 'publication.approved' else 'publication.approval_partial' end, 'publication', cur.id::text,
          jsonb_build_object('revision', cur.revision, 'side', me->>'side'));
  return public._pub_json(n, p_token);
end $$;

-- Aprovar em lote (PUB-01: aprovar em lote = autorizar a publicação agendada). Cada item é independente.
create or replace function public.pub_approve_batch(p_ws text, p_items jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it jsonb; out jsonb := '[]'; r jsonb; m text; d text;
begin
  if jsonb_typeof(coalesce(p_items, 'null')) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'pedido_invalido' using errcode = '22023', detail = 'Entre 1 e 100 publicações.'; end if;
  perform public._pub_require('calendar.read', p_ws, p_token, 'pub.approve_batch', null);
  for it in select * from jsonb_array_elements(p_items) loop
    begin
      r := public.pub_approve(p_ws, (it->>'id')::uuid, (it->>'revision')::int, p_token);
      out := out || jsonb_build_object('id', it->>'id', 'ok', true, 'status', r->>'status');
    exception when others then
      get stacked diagnostics m = message_text, d = pg_exception_detail;
      out := out || jsonb_build_object('id', it->>'id', 'ok', false, 'code', sqlstate, 'error', m, 'detail', nullif(d, ''));
    end;
  end loop;
  return out;
end $$;

-- ───────────── TEAM-10: política (dono/admin do cliente) ─────────────
create or replace function public.pub_policy_save(p_ws text, p_policy jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); before pub_approval_policies := public._pub_policy(p_ws); req text; fs boolean; p pub_publications; n int := 0;
begin
  perform public._pub_require('publishing.policy.manage', p_ws, p_token, 'pub.policy_save', p_ws);
  if (a->>'uid') is null then raise exception 'identidade_individual' using errcode = '42501'; end if;
  req := coalesce(p_policy->>'required', before.required);
  fs := coalesce((p_policy->>'forbid_self')::boolean, before.forbid_self);
  if req not in ('qualquer', 'agencia', 'cliente', 'ambos') then
    raise exception 'politica_invalida' using errcode = '22023', detail = 'Quem aprova: qualquer, agencia, cliente ou ambos.'; end if;
  insert into pub_approval_policies (workspace_id, required, forbid_self, updated_at, updated_by, updated_label)
  values (p_ws, req, fs, now(), (a->>'uid')::uuid, a->>'label')
  on conflict (workspace_id) do update set required = excluded.required, forbid_self = excluded.forbid_self, updated_at = now(),
    updated_by = excluded.updated_by, updated_label = excluded.updated_label;
  -- aprovadas que deixam de cumprir a política nova voltam a planeadas (as aprovações ficam; falta a parte nova)
  for p in select * from pub_publications where workspace_id = p_ws and status = 'aprovada' for update loop
    if cardinality(public._pub_missing(p)) > 0 then
      update pub_publications set status = 'planeada', approved_revision = null, approved_at = null where id = p.id;
      n := n + 1;
    end if;
  end loop;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.policy_saved', 'pub_policy', p_ws,
          jsonb_build_object('required', before.required, 'forbid_self', before.forbid_self),
          jsonb_build_object('required', req, 'forbid_self', fs, 'reopened', n));
  return jsonb_build_object('required', req, 'forbid_self', fs, 'reopened', n);
end $$;

-- ───────────── PUB-02: limites (só dono da agência) ─────────────
create or replace function public.pub_limit_save(p_ws text, p_platform text, p_patch jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid := (select organization_id from clients where id = p_ws); cur pub_platform_limits; nw pub_platform_limits;
begin
  if uid is null or org is null or not public._org_can('publishing.limits.manage', org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'pub.limit_save', 'capability', 'publishing.limits.manage');
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._flag_on('pub.planning', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O calendário de publicações ainda não está ligado neste cliente.'; end if;
  if jsonb_typeof(coalesce(p_patch, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  perform public._pub_seed_limits(org);
  select * into cur from pub_platform_limits where organization_id = org and platform = p_platform for update;
  if cur.platform is null then raise exception 'plataforma_invalida' using errcode = '22023'; end if;
  if p_patch ? 'max_posts' and (jsonb_typeof(p_patch->'max_posts') <> 'number' or (p_patch->>'max_posts')::numeric not between 1 and 10000) then
    raise exception 'limite_invalido' using errcode = '22023', detail = 'O máximo tem de estar entre 1 e 10000.'; end if;
  if p_patch ? 'window_kind' and p_patch->>'window_kind' not in ('rolling_24h', 'calendar_day') then raise exception 'limite_invalido' using errcode = '22023'; end if;
  if p_patch ? 'scope' and p_patch->>'scope' not in ('conta', 'projeto') then raise exception 'limite_invalido' using errcode = '22023'; end if;
  if p_patch ? 'window_tz' and not exists (select 1 from pg_timezone_names where name = p_patch->>'window_tz') then
    raise exception 'limite_invalido' using errcode = '22023', detail = 'Fuso horário desconhecido.'; end if;
  if nullif(p_patch->>'verified_on', '') is null then
    raise exception 'data_verificacao_obrigatoria' using errcode = '22023', detail = 'Indica a data em que verificaste o limite na documentação da plataforma.'; end if;
  if (p_patch->>'verified_on')::date > (now() at time zone 'UTC')::date + 1 then
    raise exception 'data_verificacao_invalida' using errcode = '22023', detail = 'A data de verificação não pode ser no futuro.'; end if;
  update pub_platform_limits set
    max_posts = coalesce((p_patch->>'max_posts')::int, max_posts),
    window_kind = coalesce(p_patch->>'window_kind', window_kind),
    window_tz = coalesce(p_patch->>'window_tz', window_tz),
    scope = coalesce(p_patch->>'scope', scope),
    public_requires_audit = coalesce((p_patch->>'public_requires_audit')::boolean, public_requires_audit),
    note = case when p_patch ? 'note' then left(nullif(btrim(p_patch->>'note'), ''), 500) else note end,
    verified_on = (p_patch->>'verified_on')::date,
    republish_min_days = case when p_patch ? 'republish_min_days' then nullif(p_patch->>'republish_min_days', '')::int else republish_min_days end,
    republish_max_share = case when p_patch ? 'republish_max_share' then nullif(p_patch->>'republish_max_share', '')::numeric else republish_max_share end,
    republish_identical = coalesce((p_patch->>'republish_identical')::boolean, republish_identical),
    updated_at = now(), updated_label = (select email from auth.users where id = uid)
  where organization_id = org and platform = p_platform returning * into nw;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), org, p_ws, 'pub.limit_saved', 'pub_platform_limit', p_platform,
          to_jsonb(cur) - 'organization_id', to_jsonb(nw) - 'organization_id');
  return public._pub_limits_json(p_ws);
end $$;

-- ───────────── FR-21-01: acrescentar conta de destino (fica "por ligar") ─────────────
create or replace function public.pub_account_add(p_ws text, p_platform text, p_handle text, p_label text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); h text := lower(btrim(regexp_replace(coalesce(p_handle, ''), '^@', ''))); v_id text; acc accounts;
begin
  perform public._pub_require('social_accounts.manage', p_ws, p_token, 'pub.account_add', p_handle);
  if p_platform not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023', detail = 'Plataformas: instagram, tiktok, youtube.'; end if;
  if h !~ '^[a-z0-9._-]{1,60}$' then raise exception 'conta_invalida' using errcode = '22023', detail = 'Nome da conta sem @, só letras, números, ponto, hífen e sublinhado.'; end if;
  if exists (select 1 from accounts where platform = p_platform and lower(handle) = h and role = 'client' and client_id is distinct from p_ws) then
    raise exception 'conta_de_outro_cliente' using errcode = '22023', detail = 'Esta conta já pertence a outro cliente.'; end if;
  select * into acc from accounts where platform = p_platform and lower(handle) = h and client_id = p_ws and role = 'client';
  if acc.id is null then
    v_id := p_ws || '-' || case p_platform when 'instagram' then 'ig' when 'tiktok' then 'tt' else 'yt' end || '-' || h;
    if exists (select 1 from accounts where accounts.id = v_id) then raise exception 'conta_invalida' using errcode = '22023', detail = 'Já existe uma conta com este identificador.'; end if;
    insert into accounts (id, client_id, role, platform, handle, label)
    values (v_id, p_ws, 'client', p_platform, h, coalesce(nullif(btrim(p_label), ''), h || ' · ' || initcap(p_platform))) returning * into acc;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.account_added', 'account', acc.id, to_jsonb(acc));
  end if;
  insert into social_accounts (account_id, workspace_id) values (acc.id, p_ws) on conflict do nothing;
  return jsonb_build_object('id', acc.id, 'platform', acc.platform, 'handle', acc.handle, 'label', acc.label, 'connection_state',
    (select connection_state from social_accounts where account_id = acc.id));
end $$;

-- ───────────── FR-21-04: ligar a linhagem gravada pelo publicador (uso interno, service_role) ─────────────
-- O publicador futuro chama _perf_record_lineage com correlation_id = pub_publications.correlation_id e depois esta função.
-- Valida que a linha é deste cliente, desta conta, desta versão e desta publicação aprovada.
create or replace function public._pub_link_lineage(p_pub uuid, p_lineage_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p pub_publications; l publication_lineage;
begin
  select * into p from pub_publications where id = p_pub for update;
  if p.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if p.status <> 'aprovada' then raise exception 'sem_aprovacao' using errcode = '42501', detail = 'Só publicações aprovadas se ligam à linhagem.'; end if;
  select * into l from publication_lineage where id = p_lineage_id;
  if l.id is null or l.workspace_id <> p.workspace_id or l.account_id <> p.account_id or l.content_version_id is distinct from p.content_version_id
     or l.correlation_id is distinct from p.correlation_id or l.lineage_mode <> 'gravada' then
    raise exception 'linhagem_nao_corresponde' using errcode = '22023'; end if;
  if p.lineage_id = l.id then return jsonb_build_object('id', p.id, 'lineage_id', l.id, 'linked', false); end if;
  if p.lineage_id is not null then raise exception 'ja_ligada' using errcode = '22023'; end if;
  perform set_config('pub.linking', p.id::text, true);
  update pub_publications set lineage_id = l.id where id = p.id;
  perform set_config('pub.linking', '', true);
  return jsonb_build_object('id', p.id, 'lineage_id', l.id, 'linked', true);
end $$;

-- ───────────── privilégios ─────────────
revoke all on function public.social_accounts_guard(), public._pub_seed_limits(uuid), public._pub_norm(text), public._pub_variant_diff(jsonb, jsonb),
  public._pub_elements_clean(jsonb), public._pub_snapshot(pub_publications), public._pub_hash(pub_publications), public._pub_policy(text),
  public._pub_missing(pub_publications), public._pub_actor_side(text, uuid), public.pub_publications_guard(), public.pub_approvals_guard(),
  public.pub_variants_guard(), public._pub_conflicts(pub_publications, boolean), public._pub_blocking(jsonb), public._pub_require(text, text, text, text, text),
  public._pub_json(pub_publications, text), public._pub_limits_json(text), public._pub_link_lineage(uuid, bigint) from public, anon, authenticated;
grant execute on function public._pub_link_lineage(uuid, bigint) to service_role;
revoke all on function public.pub_calendar(text, date, date, text), public.pub_content_options(text, text, text), public.pub_variant_save(text, jsonb, text),
  public.pub_variant_archive(text, uuid, text), public.pub_save(text, uuid, jsonb, int, text), public.pub_cancel(text, uuid, text, text),
  public.pub_approve(text, uuid, int, text), public.pub_approve_batch(text, jsonb, text), public.pub_policy_save(text, jsonb, text),
  public.pub_limit_save(text, text, jsonb, text), public.pub_account_add(text, text, text, text, text) from public;
grant execute on function public.pub_calendar(text, date, date, text), public.pub_content_options(text, text, text), public.pub_variant_save(text, jsonb, text),
  public.pub_variant_archive(text, uuid, text), public.pub_save(text, uuid, jsonb, int, text), public.pub_cancel(text, uuid, text, text),
  public.pub_approve(text, uuid, int, text), public.pub_approve_batch(text, jsonb, text), public.pub_policy_save(text, jsonb, text),
  public.pub_limit_save(text, text, jsonb, text), public.pub_account_add(text, text, text, text, text) to anon, authenticated;
-- anon só passa com código de equipa válido e a flag "para todos"; sem publishing.* no código de equipa, só lê.

/* Rollback (compatível; contas criadas por pub_account_add ficam em accounts). A chave de capacidade volta a 2 segmentos só
   depois de apagar as 3 capacidades de 3 segmentos: alter table capabilities drop constraint capabilities_key_check;
   alter table capabilities add constraint capabilities_key_check check (key ~ '^[a-z_]+\.[a-z_]+$');
   drop function public.pub_account_add(text, text, text, text, text), public.pub_limit_save(text, text, jsonb, text), public.pub_policy_save(text, jsonb, text),
     public.pub_approve_batch(text, jsonb, text), public.pub_approve(text, uuid, int, text), public.pub_cancel(text, uuid, text, text),
     public.pub_save(text, uuid, jsonb, int, text), public.pub_variant_archive(text, uuid, text), public.pub_variant_save(text, jsonb, text),
     public.pub_content_options(text, text, text), public.pub_calendar(text, date, date, text), public._pub_link_lineage(uuid, bigint),
     public._pub_limits_json(text), public._pub_json(pub_publications, text), public._pub_require(text, text, text, text, text), public._pub_blocking(jsonb),
     public._pub_conflicts(pub_publications, boolean);
   delete from role_capabilities where capability in ('publishing.approve', 'publishing.republish.approve', 'publishing.policy.manage', 'publishing.limits.manage')
      or (capability = 'publishing.schedule' and role = 'manager');
   update capabilities set status = 'W6' where key in ('publishing.schedule', 'social_accounts.manage', 'publishing.approve', 'publishing.republish.approve',
      'publishing.policy.manage', 'publishing.limits.manage');
   delete from feature_flags where key = 'pub.planning'; delete from feature_flag_defs where key = 'pub.planning';
-- contract posterior (depois de exportar): drop table public.pub_approvals, public.pub_publications, public.pub_variants, public.pub_approval_policies,
   public.pub_platform_limits, public.social_accounts; drop function public.pub_variants_guard(), public.pub_approvals_guard(), public.pub_publications_guard(),
   public._pub_actor_side(text, uuid), public._pub_missing(pub_publications), public._pub_policy(text), public._pub_hash(pub_publications),
   public._pub_snapshot(pub_publications), public._pub_elements_clean(jsonb), public._pub_variant_diff(jsonb, jsonb), public._pub_norm(text),
   public._pub_seed_limits(uuid), public.social_accounts_guard(); */
