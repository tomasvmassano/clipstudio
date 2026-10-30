-- W8 · Centro de integrações (PRD FR-15-03, FR-17-16; FR-21-01; §42 PLAT-01..03; §39 ING-01; FR-13-01; AGENTS §8; ADR-0039).
-- Só estados reais. Não há OAuth com nenhuma plataforma (PLAT-01 bloqueado): as contas sociais ficam "por ligar" e
-- "ligar"/"renovar" aparecem indisponíveis com o motivo, nunca simulados. O que se lê da base:
--  * contas sociais (social_accounts): estado, validade do token e âmbitos. Revogar é real (revogada + token_ref limpo,
--    pedido de purga do segredo no Vault, auditoria com motivo).
--  * recolha por scraping (Apify, motor numeiro-engine, fora da app): última sincronização = maior reels.updated_at /
--    perf_readings.captured_at (fonte scraper) das contas do cliente; atrasada depois de um limiar [pressuposto 48 h].
--  * motor de agentes (worker): últimas execuções em agent_jobs e o último contacto em agent_workers; "por alojar" quando
--    não há contacto nem execuções recentes.
--  * limites das APIs (pub_platform_limits).
--  * Google Drive (ING-01), email transacional (Resend, FR-13-01 adiado) e Cloudflare R2 (ING-01): por ligar, com o motivo.
-- O registo de tipos (integration_types) é dados: nome, âmbito, o que dá, de onde vem o estado e que ações existem.
-- Nunca se devolve token_ref nem segredos: a UI só vê estados.
-- Expand (só aditivo): 2 capacidades novas (integrations.read, integrations.agency.read), integrations.manage passa a
-- ativa, 1 flag, 3 tabelas fechadas à API, funções novas. Não muda nenhuma função existente. Rollback no fim.

-- ───────────── capacidades e flag ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('integrations.read', 'Settings', 'M', array['ws'], 'ativo', 'Ver o estado das integrações do cliente'),
  ('integrations.agency.read', 'Agência', 'M', array['org'], 'ativo', 'Ver as integrações da agência e o estado de todos os clientes')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
update capabilities set status = 'ativo', label = 'Gerir integrações (testar, revogar)' where key = 'integrations.manage';
-- integrations.manage já estava em workspace_owner e workspace_admin (W1). Leitura: também o gestor (manager).
-- Colaborador, revisor e leitor não veem integrações; o código de equipa também não (legacy_can não as inclui).
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'integrations.read'), ('ws', 'workspace_admin', 'integrations.read'), ('ws', 'manager', 'integrations.read'),
  ('ws', 'workspace_owner', 'integrations.manage'), ('ws', 'workspace_admin', 'integrations.manage'),
  ('org', 'agency_owner', 'integrations.agency.read')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('integrations.center', 'Centro de integrações', 'Definições', 'ws', 'owner',
   'Estado real de cada integração do cliente (contas sociais, recolha de métricas, motor de agentes, limites das APIs) e, para o dono da agência, as integrações da agência. Ligar contas fica indisponível até as plataformas aprovarem a app.')
on conflict do nothing;

-- ───────────── registo de tipos de integração (dados) ─────────────
-- state_kind diz de onde vem o estado: social (social_accounts), scraping (reels/perf_readings), worker (agent_jobs +
-- agent_workers), limits (pub_platform_limits), external (ainda não ligada: estado fixo por_ligar com o motivo).
-- actions: [{key, label, available, capability?, reason?}]. Só as que têm available = true existem no servidor; uma ação
-- desconhecida ou indisponível é recusada (falha fechada).
create table if not exists public.integration_types (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  label text not null check (char_length(label) between 1 and 80),
  scope text not null check (scope in ('cliente', 'agencia')),
  state_kind text not null check (state_kind in ('social', 'scraping', 'worker', 'limits', 'external')),
  platform text check (platform is null or platform in ('instagram', 'tiktok', 'youtube')),
  provides text not null,
  state_source text not null,
  requirement_ids text[] not null default '{}',
  planned_permissions text[] not null default '{}',
  blocked_reason text,
  missing text,
  stale_after interval,
  actions jsonb not null default '[]' check (jsonb_typeof(actions) = 'array'),
  sort int not null default 100,
  updated_at timestamptz not null default now()
);

insert into integration_types (key, label, scope, state_kind, platform, provides, state_source, requirement_ids, planned_permissions,
  blocked_reason, missing, stale_after, actions, sort) values
  ('instagram', 'Instagram', 'cliente', 'social', 'instagram',
   'Ligação oficial às contas Instagram do cliente: métricas pela API (fase A) e publicação (fase B).',
   'Contas sociais do cliente (estado da ligação, validade do token, âmbitos concedidos).',
   array['FR-17-16', 'FR-21-01', 'PLAT-02', 'PLAT-03'],
   array['instagram_business_basic', 'instagram_business_manage_insights', 'instagram_business_content_publish'],
   'A Meta ainda não aprovou a app (PLAT-01..03): não há OAuth, por isso nenhuma conta se liga por aqui.',
   'Domínio próprio, páginas públicas de privacidade, termos e eliminação de dados, Business Verification na Meta e app registada (PLAT-01); depois a revisão da fase A (PLAT-02).',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Indisponível até a Meta aprovar a app (PLAT-01..03)."},
     {"key":"renovar","label":"Renovar","available":false,"reason":"Indisponível: sem OAuth não há token para renovar."},
     {"key":"revogar","label":"Revogar","available":true,"capability":"integrations.manage"}]', 10),
  ('tiktok', 'TikTok', 'cliente', 'social', 'tiktok',
   'Ligação oficial às contas TikTok do cliente: dados de conta e vídeo (fase A) e publicação pelo Content Posting API (fase B).',
   'Contas sociais do cliente (estado da ligação, validade do token, âmbitos concedidos).',
   array['FR-17-16', 'FR-21-01', 'PLAT-02', 'PLAT-03'],
   array['Login Kit', 'dados de conta e vídeo (Business)', 'video.publish'],
   'O TikTok ainda não aprovou a app (PLAT-01..03): não há OAuth, por isso nenhuma conta se liga por aqui.',
   'Domínio próprio e páginas públicas (PLAT-01), app registada no TikTok for Developers; para publicar em público, a auditoria do Content Posting API (PLAT-03).',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Indisponível até o TikTok aprovar a app (PLAT-01..03)."},
     {"key":"renovar","label":"Renovar","available":false,"reason":"Indisponível: sem OAuth não há token para renovar."},
     {"key":"revogar","label":"Revogar","available":true,"capability":"integrations.manage"}]', 20),
  ('youtube', 'YouTube', 'cliente', 'social', 'youtube',
   'Ligação oficial aos canais YouTube do cliente: métricas pela API (fase A) e upload (fase B).',
   'Contas sociais do cliente (estado da ligação, validade do token, âmbitos concedidos).',
   array['FR-17-16', 'FR-21-01', 'PLAT-02', 'PLAT-03'],
   array['youtube.readonly', 'yt-analytics.readonly', 'youtube.upload'],
   'A Google ainda não verificou a app (PLAT-01..03): não há OAuth, por isso nenhum canal se liga por aqui.',
   'Domínio próprio verificado, páginas públicas e app na Google Cloud (PLAT-01); depois a verificação dos âmbitos (PLAT-02/03).',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Indisponível até a Google verificar a app (PLAT-01..03)."},
     {"key":"renovar","label":"Renovar","available":false,"reason":"Indisponível: sem OAuth não há token para renovar."},
     {"key":"revogar","label":"Revogar","available":true,"capability":"integrations.manage"}]', 30),
  ('scraping', 'Recolha de métricas (scraping)', 'cliente', 'scraping', null,
   'Views, gostos e comentários dos reels das contas do cliente e das referências, recolhidos pelo motor (Apify) até haver APIs oficiais.',
   'Maior atualização de reels e de leituras do scraper das contas do cliente, escritas pelo motor numeiro-engine (fora da app).',
   array['FR-17-16', 'PERF-03', 'R-19'], '{}', null,
   'A configuração do Apify vive no motor numeiro-engine; a app só vê o resultado.',
   interval '48 hours',
   '[{"key":"testar","label":"Testar","available":true,"capability":"integrations.manage"}]', 40),
  ('agents_worker', 'Motor de agentes (worker)', 'cliente', 'worker', null,
   'Corre as execuções dos agentes (pipeline diário, scouts, análise) fora dos pedidos da app.',
   'Últimas execuções deste cliente (fila de execuções) e último contacto do worker.',
   array['FR-17-16', 'FR-17-14', 'FR-06-03'], '{}', null,
   'Alojar o worker (FR-17-14): enquanto não estiver alojado, as execuções ficam na fila.',
   interval '30 minutes',
   '[{"key":"testar","label":"Testar","available":true,"capability":"integrations.manage"}]', 50),
  ('platform_limits', 'Limites das APIs', 'agencia', 'limits', null,
   'Quantas publicações cada plataforma aceita por API, por conta ou por projeto da agência (PUB-02).',
   'Limites por plataforma da organização, com a data em que foram verificados.',
   array['FR-17-16', 'PUB-02'], '{}', null, null, null,
   '[]', 60),
  ('google_drive', 'Google Drive (bruto)', 'agencia', 'external', null,
   'Arquivo do bruto das gravações na Drive da agência, sem prazo (ING-01).',
   'Ainda não ligada: não há nada na base.',
   array['ING-01'], '{}',
   'Ainda não ligada.',
   'Decidir o plano e o espaço Google Workspace para o arquivo de bruto (PRD §44) e a app OAuth da Google (PLAT-01).',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Indisponível: falta decidir o espaço Google Workspace e a app OAuth da Google (PLAT-01)."}]', 70),
  ('cloudflare_r2', 'Cloudflare R2 (media)', 'agencia', 'external', null,
   'Cópias de trabalho, proxies e finais em object storage S3-compatível, com bucket e prefixo por cliente (ING-01).',
   'Ainda não ligada: não há nada na base.',
   array['ING-01'], '{}',
   'Ainda não ligada.',
   'Criar a conta e o bucket, as chaves só no servidor e a política de retenção (ING-01).',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Indisponível: o armazenamento de media ainda não foi criado (ING-01)."}]', 80),
  ('resend', 'Email transacional (Resend)', 'agencia', 'external', null,
   'Envio de convites e notificações por email a partir do domínio da app.',
   'Ainda não ligada: não há nada na base.',
   array['FR-13-01'], '{}',
   'Adiado: sem domínio próprio verificado não há envio transacional (FR-13-01).',
   'Domínio próprio da app (PLAT-01) e verificação do domínio no Resend.',
   null,
   '[{"key":"ligar","label":"Ligar","available":false,"reason":"Adiado até haver domínio próprio (FR-13-01)."}]', 90)
on conflict (key) do nothing;

-- ───────────── testes feitos a partir da base (FR-15-03 "testar") ─────────────
create table if not exists public.integration_checks (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  integration_key text not null references public.integration_types(key),
  outcome text not null check (outcome in ('ok', 'aviso', 'falhou', 'sem_dados')),
  state text not null,
  detail jsonb not null default '{}',
  actor_user_id uuid,
  actor_label text,
  checked_at timestamptz not null default now()
);
create index if not exists integration_checks_ws on public.integration_checks (workspace_id, integration_key, checked_at desc);

-- ───────────── purga do segredo depois de revogar ─────────────
-- O token vive no Vault do Supabase; aqui fica só a referência e o pedido de purga (durável, idempotente). Se o Vault existir
-- nesta base, apaga-se já; senão o pedido fica para o serviço de OAuth (service_role).
create table if not exists public.integration_secret_purges (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  account_id text not null references public.accounts(id),
  token_ref text not null unique check (token_ref ~ '^vault:[0-9a-f-]{36}$'),
  requested_at timestamptz not null default now(),
  purged_at timestamptz,
  last_error text
);

alter table public.integration_types enable row level security;
alter table public.integration_checks enable row level security;
alter table public.integration_secret_purges enable row level security;
revoke all on public.integration_types, public.integration_checks, public.integration_secret_purges from anon, authenticated;   -- só pelas RPCs

create or replace function public.integration_checks_guard() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'testes_imutaveis' using errcode = '42501', detail = 'Os testes das integrações só se acrescentam.'; end $$;
drop trigger if exists integration_checks_guard on public.integration_checks;
create trigger integration_checks_guard before update or delete on public.integration_checks for each row execute function public.integration_checks_guard();

-- ───────────── regras ─────────────
create or replace function public._integ_require(p_cap text, p_ws text, p_token text, p_action text, p_entity text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, p_entity);
  if not public._flag_on('integrations.center', p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O centro de integrações ainda não está ligado neste cliente.';
  end if;
end $$;

-- Estado efetivo de uma conta social: um token "ligado" com validade passada conta como expirado.
create or replace function public._integ_social_state(p_state text, p_expires timestamptz) returns text
language sql stable set search_path = public as $$
  select case when p_state = 'ligada' and p_expires is not null and p_expires <= now() then 'expirada' else p_state end
$$;

create or replace function public._integ_health(p_state text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_state in ('ligada', 'em_dia', 'ativo') then 'ok'
    when p_state in ('a_expirar', 'atrasada', 'parado', 'expirada', 'parcial', 'falhou') then 'aviso'
    else 'indisponivel' end
$$;

create or replace function public._integ_action_ok(t integration_types, p_action text) returns boolean
language sql immutable set search_path = public as $$
  select exists (select 1 from jsonb_array_elements(t.actions) a where a->>'key' = p_action and (a->>'available')::boolean)
$$;

-- Recolha por scraping de um cliente: por conta e no total (fonte: motor numeiro-engine).
create or replace function public._integ_scraping(p_ws text, p_stale interval) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare accs jsonb; last_at timestamptz; refs_at timestamptz; st text; n int;
begin
  with a as (
    select a.id, a.handle, a.platform, a.label,
           (select max(r.updated_at) from reels r where r.client_id = p_ws and r.account_id = a.id) reel_at,
           (select max(pr.captured_at) from perf_readings pr join reels r on r.client_id = pr.workspace_id and r.id = pr.reel_id
             where pr.workspace_id = p_ws and r.account_id = a.id and pr.source = 'scraper') read_at,
           (select count(*) from reels r where r.client_id = p_ws and r.account_id = a.id) reels
      from accounts a where a.client_id = p_ws and a.role = 'client')
  select coalesce(jsonb_agg(jsonb_build_object('account_id', id, 'handle', handle, 'platform', platform, 'label', label, 'reels', reels,
           'last_sync_at', greatest(reel_at, read_at),
           'state', case when greatest(reel_at, read_at) is null then 'sem_dados'
                         when greatest(reel_at, read_at) < now() - p_stale then 'atrasada' else 'em_dia' end) order by platform, handle), '[]'),
         max(greatest(reel_at, read_at)), count(*)
    into accs, last_at, n from a;
  select max(r.updated_at) into refs_at from reels r join accounts a on a.id = r.account_id
   where r.client_id = p_ws and a.role = 'reference';
  st := case when last_at is null then 'sem_dados' when last_at < now() - p_stale then 'atrasada' else 'em_dia' end;
  return jsonb_build_object('state', st, 'last_sync_at', last_at, 'references_last_sync_at', refs_at, 'accounts', accs, 'account_count', n,
    'stale_after_hours', round(extract(epoch from p_stale) / 3600));
end $$;

-- Motor de agentes de um cliente: último contacto do worker (sem o identificar), última execução, fila.
create or replace function public._integ_worker(p_ws text, p_stale interval) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare seen timestamptz := (select max(last_seen) from agent_workers); j agent_jobs; q int; oldest timestamptz; recent boolean;
        failed int; st text;
begin
  select * into j from agent_jobs where workspace_id = p_ws order by coalesce(finished_at, started_at, created_at) desc limit 1;
  select count(*), min(next_attempt_at) into q, oldest from agent_jobs where workspace_id = p_ws and status = 'queued';
  select count(*) filter (where status in ('failed', 'dead')) into failed from agent_jobs where workspace_id = p_ws and created_at > now() - interval '7 days';
  recent := exists (select 1 from agent_jobs where workspace_id = p_ws and started_at > now() - interval '7 days');
  st := case when seen is not null and seen > now() - p_stale then 'ativo'
             when recent then 'parado'
             else 'por_alojar' end;
  return jsonb_build_object('state', st, 'worker_seen_at', seen, 'queued', q, 'oldest_queued_at', oldest, 'failed_7d', failed,
    'queue_late', oldest is not null and oldest < now() - interval '1 hour',
    'last_job', case when j.id is null then null else jsonb_build_object('kind', j.kind, 'status', j.status, 'created_at', j.created_at,
      'started_at', j.started_at, 'finished_at', j.finished_at, 'heartbeat_at', j.heartbeat_at,
      'last_error', left(j.last_error, 300)) end,
    'stale_after_minutes', round(extract(epoch from p_stale) / 60));
end $$;

-- Contas sociais de uma plataforma de um cliente. Nunca devolve token_ref: só se há credencial guardada.
create or replace function public._integ_social(p_ws text, p_platform text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('account_id', a.id, 'handle', a.handle, 'label', a.label,
      'connection_state', case when x.st = 'ligada' and s.token_expires_at < now() + interval '7 days' then 'a_expirar' else x.st end,
      'stored_state', coalesce(s.connection_state, 'por_ligar'),
      'credential_stored', s.token_ref is not null, 'scopes', to_jsonb(coalesce(s.scopes, '{}')), 'token_expires_at', s.token_expires_at,
      'connected_at', s.connected_at, 'connected_label', s.connected_label, 'updated_at', s.updated_at,
      'can_revoke', x.st in ('ligada', 'expirada'),
      'revoke_blocked', case when x.st = 'revogada' then 'Já está revogada.' when x.st = 'por_ligar' then 'Nada para revogar: a conta nunca foi ligada.' end)
      order by a.handle), '[]')
  from accounts a left join social_accounts s on s.account_id = a.id
  cross join lateral (select public._integ_social_state(coalesce(s.connection_state, 'por_ligar'), s.token_expires_at) st) x
  where a.client_id = p_ws and a.role = 'client' and a.platform = p_platform
$$;

create or replace function public._integ_last_check(p_ws text, p_key text) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(x) - 'workspace_id' - 'actor_user_id' from (
    select c.id, c.workspace_id, c.integration_key, c.outcome, c.state, c.detail, c.actor_user_id, c.actor_label, c.checked_at
      from integration_checks c where c.workspace_id = p_ws and c.integration_key = p_key order by c.checked_at desc limit 1) x
$$;

-- Um item do centro para um cliente: estado, detalhe e ações com disponibilidade para quem pede.
create or replace function public._integ_item(p_ws text, t integration_types, p_can_manage boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := '{}'; st text; last_at timestamptz; acts jsonb; lim jsonb;
begin
  if t.state_kind = 'social' then
    d := jsonb_build_object('accounts', public._integ_social(p_ws, t.platform));
    select x into lim from jsonb_array_elements(public._pub_limits_json(p_ws)) x where x->>'platform' = t.platform;
    d := d || jsonb_build_object('limits', lim);
    st := case
      when jsonb_array_length(d->'accounts') = 0 then 'sem_contas'
      when exists (select 1 from jsonb_array_elements(d->'accounts') a where a->>'connection_state' in ('ligada', 'a_expirar'))
        then case when exists (select 1 from jsonb_array_elements(d->'accounts') a where a->>'connection_state' not in ('ligada'))
                  then 'parcial' else 'ligada' end
      when exists (select 1 from jsonb_array_elements(d->'accounts') a where a->>'connection_state' = 'expirada') then 'expirada'
      when not exists (select 1 from jsonb_array_elements(d->'accounts') a where a->>'connection_state' <> 'revogada') then 'revogada'
      else 'por_ligar' end;
    select max((a->>'updated_at')::timestamptz) into last_at from jsonb_array_elements(d->'accounts') a where a->>'stored_state' <> 'por_ligar';
  elsif t.state_kind = 'scraping' then
    d := public._integ_scraping(p_ws, t.stale_after); st := d->>'state'; last_at := (d->>'last_sync_at')::timestamptz;
  elsif t.state_kind = 'worker' then
    d := public._integ_worker(p_ws, t.stale_after); st := d->>'state';
    last_at := coalesce((d->'last_job'->>'finished_at')::timestamptz, (d->'last_job'->>'started_at')::timestamptz);
  elsif t.state_kind = 'limits' then
    d := jsonb_build_object('limits', public._pub_limits_json(p_ws)); st := case when jsonb_array_length(d->'limits') > 0 then 'em_dia' else 'sem_dados' end;
  else
    st := 'por_ligar';
  end if;
  select coalesce(jsonb_agg(case when (a->>'available')::boolean and not p_can_manage
                                 then a || jsonb_build_object('available', false, 'reason', 'Só quem gere as integrações deste cliente.')
                                 else a end), '[]') into acts
    from jsonb_array_elements(t.actions) a;
  return jsonb_build_object('key', t.key, 'label', t.label, 'scope', t.scope, 'kind', t.state_kind, 'platform', t.platform,
    'provides', t.provides, 'state_source', t.state_source, 'requirement_ids', to_jsonb(t.requirement_ids),
    'planned_permissions', to_jsonb(t.planned_permissions), 'blocked_reason', t.blocked_reason, 'missing', t.missing,
    'state', st, 'health', public._integ_health(st), 'last_sync_at', last_at, 'detail', d, 'actions', acts,
    'last_check', case when public._integ_action_ok(t, 'testar') then public._integ_last_check(p_ws, t.key) end);
end $$;

-- ───────────── leitura: cliente ─────────────
create or replace function public.integrations_overview(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare manage boolean; c clients;
begin
  perform public._integ_require('integrations.read', p_ws, p_token, 'integrations.overview', p_ws);
  manage := public.ws_can('integrations.manage', p_ws, p_token);
  select * into c from clients where id = p_ws;
  return jsonb_build_object('workspace_id', p_ws, 'timezone', coalesce(c.timezone, 'Asia/Dubai'), 'can_manage', manage, 'generated_at', now(),
    'items', coalesce((select jsonb_agg(public._integ_item(p_ws, t, manage) order by t.sort) from integration_types t where t.scope = 'cliente'), '[]'));
end $$;

-- ───────────── leitura: agência (só o dono) ─────────────
create or replace function public.integrations_agency() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid;
begin
  select m.organization_id into org from agency_memberships m where m.user_id = uid and m.status = 'active' and m.agency_role = 'agency_owner'
   order by m.created_at limit 1;
  if org is null or not public._org_can('integrations.agency.read', org) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', 'integrations.agency', 'capability', 'integrations.agency.read');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not public._flag_on('integrations.center', null, null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O centro de integrações ainda não está ligado na agência.';
  end if;
  return jsonb_build_object('generated_at', now(),
    'workers', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'kinds', to_jsonb(w.kinds), 'version', w.version, 'last_seen', w.last_seen,
        'active', w.last_seen > now() - coalesce((select stale_after from integration_types where key = 'agents_worker'), interval '30 minutes'))
        order by w.last_seen desc) from agent_workers w), '[]'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'scope', t.scope, 'kind', t.state_kind,
        'provides', t.provides, 'state_source', t.state_source, 'requirement_ids', to_jsonb(t.requirement_ids), 'blocked_reason', t.blocked_reason,
        'missing', t.missing, 'actions', t.actions,
        'state', case when t.state_kind = 'limits' then case when exists (select 1 from pub_platform_limits l where l.organization_id = org) then 'em_dia' else 'sem_dados' end
                      else 'por_ligar' end) order by t.sort) from integration_types t where t.scope = 'agencia'), '[]'),
    'limits', coalesce((select jsonb_agg(jsonb_build_object('platform', l.platform, 'max_posts', l.max_posts, 'window_kind', l.window_kind,
        'window_tz', l.window_tz, 'scope', l.scope, 'public_requires_audit', l.public_requires_audit, 'note', l.note, 'verified_on', l.verified_on,
        'updated_at', l.updated_at, 'updated_label', l.updated_label) order by l.platform) from pub_platform_limits l where l.organization_id = org), '[]'),
    'clients', coalesce((select jsonb_agg(x order by x->>'name') from (
        select jsonb_build_object('id', c.id, 'name', c.name, 'timezone', coalesce(c.timezone, 'Asia/Dubai'),
          'enabled', public._flag_on('integrations.center', c.id, null),
          'social', (select jsonb_build_object(
              'total', count(*), 'por_ligar', count(*) filter (where e.st = 'por_ligar'), 'ligada', count(*) filter (where e.st = 'ligada'),
              'expirada', count(*) filter (where e.st = 'expirada'), 'revogada', count(*) filter (where e.st = 'revogada'))
            from accounts a left join social_accounts s on s.account_id = a.id
            cross join lateral (select public._integ_social_state(coalesce(s.connection_state, 'por_ligar'), s.token_expires_at) st) e
            where a.client_id = c.id and a.role = 'client'),
          'scraping', (select jsonb_build_object('state', sc->>'state', 'last_sync_at', sc->'last_sync_at')
            from (select public._integ_scraping(c.id, coalesce(t.stale_after, interval '48 hours')) sc from integration_types t where t.key = 'scraping') q),
          'worker', (select jsonb_build_object('state', wk->>'state', 'last_job', wk->'last_job', 'queued', wk->'queued')
            from (select public._integ_worker(c.id, coalesce(t.stale_after, interval '30 minutes')) wk from integration_types t where t.key = 'agents_worker') q)) x
          from clients c where c.organization_id = org and c.status = 'active') s), '[]'));
end $$;

-- ───────────── ação: revogar uma conta social ─────────────
-- Idempotente: revogar outra vez devolve changed = false sem nova auditoria. Conta de outro cliente = não encontrada.
create or replace function public.integrations_social_revoke(p_ws text, p_account_id text, p_reason text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s social_accounts; eff text; ref text; r text := btrim(coalesce(p_reason, '')); t integration_types;
        purged boolean := false; perr text; acc accounts;
begin
  perform public._integ_require('integrations.manage', p_ws, p_token, 'integrations.social_revoke', p_account_id);
  select * into acc from accounts where id = p_account_id and client_id = p_ws and role = 'client';
  select * into s from social_accounts where account_id = p_account_id and workspace_id = p_ws for update;
  if acc.id is null or s.account_id is null then raise exception 'conta_nao_encontrada' using errcode = 'P0002'; end if;
  select * into t from integration_types where key = acc.platform;
  if t.key is null or not public._integ_action_ok(t, 'revogar') then
    raise exception 'acao_indisponivel' using errcode = '22023', detail = 'Esta integração não tem a ação revogar.'; end if;
  eff := public._integ_social_state(s.connection_state, s.token_expires_at);
  if eff = 'revogada' then
    return jsonb_build_object('account_id', s.account_id, 'connection_state', 'revogada', 'changed', false);
  end if;
  if eff = 'por_ligar' then
    raise exception 'nada_para_revogar' using errcode = '22023', detail = 'Nada para revogar: a conta nunca foi ligada.'; end if;
  if char_length(r) < 3 or char_length(r) > 500 then
    raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Escreve o motivo (3 a 500 caracteres).'; end if;
  ref := s.token_ref;
  update social_accounts set connection_state = 'revogada', token_ref = null, token_expires_at = null, scopes = '{}', updated_at = now()
   where account_id = s.account_id;
  if ref is not null then
    insert into integration_secret_purges (workspace_id, account_id, token_ref) values (p_ws, s.account_id, ref) on conflict (token_ref) do nothing;
    if to_regclass('vault.secrets') is not null then
      begin
        execute 'delete from vault.secrets where id = $1' using substr(ref, 7)::uuid;
        update integration_secret_purges set purged_at = now(), last_error = null where token_ref = ref;
        purged := true;
      exception when others then
        perr := left(sqlerrm, 300);
        update integration_secret_purges set last_error = perr where token_ref = ref;   -- fica pendente para o serviço de OAuth
      end;
    end if;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'integrations.social_revoked', 'social_account', s.account_id,
    jsonb_build_object('connection_state', eff, 'scopes', to_jsonb(s.scopes), 'token_expires_at', s.token_expires_at, 'credential_stored', ref is not null),
    jsonb_build_object('connection_state', 'revogada', 'reason', r, 'secret_purged', purged, 'secret_purge_pending', ref is not null and not purged),
    'integ:revoke:' || s.account_id);
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'integration.social_revoked', 'social_account', s.account_id,
    jsonb_build_object('platform', acc.platform, 'previous_state', eff, 'reason', r));
  return jsonb_build_object('account_id', s.account_id, 'connection_state', 'revogada', 'changed', true,
    'secret_purged', purged, 'secret_purge_pending', ref is not null and not purged);
end $$;

-- ───────────── ação: testar (só o que se pode testar a partir da base) ─────────────
-- Recalcula o estado agora e guarda o resultado. Repetir em 30 s devolve o mesmo teste (reused = true), sem duplicar.
create or replace function public.integrations_test(p_ws text, p_key text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); t integration_types; d jsonb; st text; oc text; c integration_checks;
begin
  perform public._integ_require('integrations.manage', p_ws, p_token, 'integrations.test', p_key);
  select * into t from integration_types where key = p_key and scope = 'cliente';
  if t.key is null or not public._integ_action_ok(t, 'testar') then
    raise exception 'acao_indisponivel' using errcode = '22023', detail = 'Esta integração não se pode testar a partir da app.'; end if;
  perform pg_advisory_xact_lock(hashtext('integ_test:' || p_ws || ':' || p_key));
  select * into c from integration_checks where workspace_id = p_ws and integration_key = p_key and checked_at > now() - interval '30 seconds'
   order by checked_at desc limit 1;
  if c.id is not null then
    return (to_jsonb(c) - 'workspace_id' - 'actor_user_id') || jsonb_build_object('reused', true);
  end if;
  if t.state_kind = 'scraping' then d := public._integ_scraping(p_ws, t.stale_after);
  else d := public._integ_worker(p_ws, t.stale_after); end if;
  st := d->>'state';
  oc := case when st in ('em_dia', 'ativo') then case when coalesce((d->>'queue_late')::boolean, false) then 'aviso' else 'ok' end
             when st = 'sem_dados' then 'sem_dados'
             when st in ('atrasada', 'parado') then 'aviso'
             else 'falhou' end;
  insert into integration_checks (workspace_id, integration_key, outcome, state, detail, actor_user_id, actor_label)
  values (p_ws, p_key, oc, st, d - 'accounts', (a->>'uid')::uuid, a->>'label') returning * into c;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, correlation_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'integrations.tested', 'integration', p_key,
    jsonb_build_object('outcome', oc, 'state', st), 'integ:test:' || c.id);
  return (to_jsonb(c) - 'workspace_id' - 'actor_user_id') || jsonb_build_object('reused', false);
end $$;

-- ───────────── privilégios ─────────────
revoke all on function public._integ_require(text, text, text, text, text), public._integ_social_state(text, timestamptz), public._integ_health(text),
  public._integ_action_ok(integration_types, text), public._integ_scraping(text, interval), public._integ_worker(text, interval),
  public._integ_social(text, text), public._integ_last_check(text, text), public._integ_item(text, integration_types, boolean),
  public.integration_checks_guard() from public, anon, authenticated;
revoke all on function public.integrations_overview(text, text), public.integrations_agency(), public.integrations_social_revoke(text, text, text, text),
  public.integrations_test(text, text, text) from public;
revoke all on function public.integrations_agency() from anon;
grant execute on function public.integrations_overview(text, text), public.integrations_social_revoke(text, text, text, text),
  public.integrations_test(text, text, text) to anon, authenticated;
grant execute on function public.integrations_agency() to authenticated;
-- anon passa a função mas é recusado: o código de equipa não tem integrations.* (legacy_can).

/* Rollback (compatível com main; revogações feitas ficam em social_accounts e na auditoria):
   drop function public.integrations_test(text, text, text), public.integrations_social_revoke(text, text, text, text),
     public.integrations_agency(), public.integrations_overview(text, text), public._integ_item(text, integration_types, boolean),
     public._integ_last_check(text, text), public._integ_social(text, text), public._integ_worker(text, interval),
     public._integ_scraping(text, interval), public._integ_action_ok(integration_types, text), public._integ_health(text),
     public._integ_social_state(text, timestamptz), public._integ_require(text, text, text, text, text);
   delete from role_capabilities where capability in ('integrations.read', 'integrations.agency.read');
   delete from capabilities where key in ('integrations.read', 'integrations.agency.read');
   update capabilities set status = 'W6', label = 'Gerir integrações' where key = 'integrations.manage';
   delete from feature_flags where key = 'integrations.center'; delete from feature_flag_defs where key = 'integrations.center';
-- contract posterior (depois de exportar integration_checks e integration_secret_purges pendentes):
   drop trigger integration_checks_guard on public.integration_checks; drop function public.integration_checks_guard();
   drop table public.integration_secret_purges, public.integration_checks, public.integration_types; */
