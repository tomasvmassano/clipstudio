-- Parte 1 de 4 de 20261030000100_w6_biz.sql (aplicada em produção como w6_biz_p1).
-- W6 · Vista de negócio da agência (PRD §38): BIZ-01 atingimento de entrega, BIZ-02 faixa "Precisa da tua atenção",
-- BIZ-03 KPIs e tabela por cliente, BIZ-04 dois níveis de acesso, BIZ-05 contratos por cliente, BIZ-06 custos e margem.
-- BIZ-09 (saúde do cliente) fica registada como indisponível: precisa de ~6 meses de histórico e de sentimento, que não existem.
-- Expand: 3 capacidades, 1 flag, 4 tabelas novas fechadas à API e funções novas. Não muda nenhuma função existente.
-- Espaço: agência. O servidor constrói a resposta por pessoa: os campos financeiros só saem a quem tem biz.finance
-- (por defeito só o dono da agência), nunca escondidos só no browser. Rollback no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('biz.read', 'Agência', 'M', array['org'], 'ativo', 'Ver a vista de negócio (operacional, só clientes atribuídos)'),
  ('biz.finance', 'Agência', 'A', array['org'], 'ativo', 'Ver contratos, receita, custos e margens dos clientes'),
  ('contracts.manage', 'Agência', 'A', array['org'], 'ativo', 'Gerir contratos, câmbio e custos dos clientes')
on conflict (key) do update set status = 'ativo', label = excluded.label;
insert into role_capabilities (scope, role, capability) values
  ('org', 'agency_owner', 'biz.read'), ('org', 'agency_admin', 'biz.read'), ('org', 'agency_manager', 'biz.read'), ('org', 'agency_member', 'biz.read'),
  ('org', 'agency_owner', 'biz.finance'), ('org', 'agency_owner', 'contracts.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('biz.view', 'Vista de negócio', 'Agência', 'org', 'owner',
   'Atingimento de entrega, faixa "Precisa da tua atenção", KPIs por cliente, contratos, custos e margem (PRD §38). A parte financeira continua só para quem tem a capacidade.')
on conflict (key) do nothing;

-- ───────────── contratos por cliente (BIZ-05): só de acrescentar, cada gravação é uma versão nova ─────────────
create table if not exists public.client_contracts (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  version int not null check (version >= 1),
  status text not null default 'ativo' check (status in ('ativo', 'terminado')),
  amount numeric(12,2) not null check (amount >= 0 and amount <= 10000000),
  currency text not null check (currency in ('EUR', 'AED')),
  billing_period text not null default 'mensal' check (billing_period in ('mensal', 'trimestral', 'anual')),
  scripts_per_month int check (scripts_per_month between 0 and 10000),
  videos_per_month int check (videos_per_month between 0 and 10000),
  platforms text[] not null default '{}' check (platforms <@ array['instagram', 'tiktok', 'youtube']),
  -- [pressuposto] prazo de cada vídeo = data do guião no calendário + N dias
  deadline_days int not null default 7 check (deadline_days between 0 and 60),
  starts_on date,
  renewal_on date,
  effective_from date not null default current_date,
  payment_status text not null default 'em_dia' check (payment_status in ('em_dia', 'pendente', 'vencido')),
  payment_due_on date,
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  unique (workspace_id, version),
  check (renewal_on is null or starts_on is null or renewal_on >= starts_on)
);
create index if not exists client_contracts_ws_eff on public.client_contracts (workspace_id, effective_from desc, version desc);
drop trigger if exists client_contracts_append_only on public.client_contracts;
create trigger client_contracts_append_only before update or delete on public.client_contracts for each row execute function public.content_append_only();

-- câmbio EUR→AED escrito pelo dono [pressuposto: sem API de câmbio; a taxa e a data ficam visíveis]
create table if not exists public.fx_rates (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id),
  base text not null default 'EUR' check (base = 'EUR'),
  quote text not null default 'AED' check (quote = 'AED'),
  rate numeric(14,6) not null check (rate > 0 and rate < 1000),
  as_of date not null,
  source text check (source is null or char_length(source) <= 120),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_label text
);
create index if not exists fx_rates_org on public.fx_rates (organization_id, as_of desc, id desc);
drop trigger if exists fx_rates_append_only on public.fx_rates;
create trigger fx_rates_append_only before update or delete on public.fx_rates for each row execute function public.content_append_only();

-- custos humanos, ferramentas e outros por mês (BIZ-06). Diretos a um cliente, ou da agência repartidos por regra.
create table if not exists public.agency_costs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  workspace_id text references public.clients(id),
  month date not null check (extract(day from month) = 1),
  kind text not null check (kind in ('humano', 'ferramentas', 'outro')),
  label text not null check (char_length(trim(label)) between 2 and 120),
  amount numeric(12,2) not null check (amount >= 0 and amount <= 10000000),
  currency text not null check (currency in ('EUR', 'AED')),
  allocation text not null default 'direto' check (allocation in ('direto', 'igual', 'por_videos')),
  client_ref uuid,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text check (void_reason is null or char_length(void_reason) <= 300),
  check ((workspace_id is null) = (allocation <> 'direto'))
);
create index if not exists agency_costs_month on public.agency_costs (organization_id, month);
create unique index if not exists agency_costs_client_ref on public.agency_costs (organization_id, client_ref) where client_ref is not null;

-- um custo não se apaga nem se muda: só se anula (com motivo), uma vez
create or replace function public.agency_costs_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'agency_costs é append-only' using errcode = '42501'; end if;
  if old.voided_at is not null or new.voided_at is null
     or (to_jsonb(new) - array['voided_at', 'voided_by', 'void_reason']) is distinct from (to_jsonb(old) - array['voided_at', 'voided_by', 'void_reason']) then
    raise exception 'agency_costs só se anula' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists agency_costs_guard on public.agency_costs;
create trigger agency_costs_guard before update or delete on public.agency_costs for each row execute function public.agency_costs_guard();

-- registo de métricas da vista: cada KPI e coluna tem a sua capacidade (BIZ-04)
create table if not exists public.biz_metrics (
  key text primary key check (key ~ '^(ops|fin)\.[a-z0-9_]+$'),
  level text not null check (level in ('operacional', 'financeiro')),
  label text not null,
  description text not null,
  capability text not null references public.capabilities(key),
  cap_scope text not null check (cap_scope in ('ws', 'org')),
  available boolean not null default true,
  unavailable_reason text,
  sort int not null
);

alter table public.client_contracts enable row level security;
alter table public.fx_rates enable row level security;
alter table public.agency_costs enable row level security;
alter table public.biz_metrics enable row level security;
revoke all on public.client_contracts, public.fx_rates, public.agency_costs, public.biz_metrics from anon, authenticated;

insert into public.biz_metrics (key, level, label, description, capability, cap_scope, available, unavailable_reason, sort) values
  ('ops.today', 'operacional', 'Produção do dia', 'Guiões planeados para hoje no calendário do cliente e quantos já estão gravados.', 'scripts.read', 'ws', true, null, 10),
  ('ops.stalled', 'operacional', 'Itens parados', 'Guiões há mais tempo na etapa atual do que 70% dos que passaram por ela nos últimos 90 dias (aviso a partir de 50%). Só etapas com pelo menos 10 passagens.', 'scripts.read', 'ws', true, null, 20),
  ('ops.approvals', 'operacional', 'Aprovações pendentes', 'Guiões à espera de aprovação agora, e quantos esperam há mais de 48 h.', 'scripts.read', 'ws', true, null, 30),
  ('ops.attainment', 'operacional', 'Atingimento de entrega', 'Vídeos publicados no prazo ÷ vídeos contratados no mês. Meta 95%; alerta quando o ritmo até hoje fica abaixo de 90%. Atrasos do cliente (aprovação, gravação) à parte.', 'scripts.read', 'ws', true, null, 40),
  ('ops.first_pass', 'operacional', 'Aprovação à primeira', 'Guiões aprovados no mês sem pedido de alterações nem rejeição antes da aprovação.', 'scripts.read', 'ws', true, null, 50),
  ('ops.approval_time', 'operacional', 'Tempo de aprovação do cliente', 'Mediana das horas entre o envio para revisão e a aprovação feita pela equipa do cliente, no mês.', 'scripts.read', 'ws', true, null, 60),
  ('ops.performance', 'operacional', 'Índice de desempenho', 'Mediana de views ÷ mediana dos 30 dias anteriores da própria conta, nos reels do mês (PERF-04). Usa a última leitura de views.', 'analytics.read', 'ws', true, null, 70),
  ('ops.reach', 'operacional', 'Views 7 d vs 30 d', 'Mediana de views dos últimos 7 dias ÷ mediana dos 30 dias anteriores. Abaixo de 60% é possível supressão.', 'analytics.read', 'ws', true, null, 80),
  ('ops.health', 'operacional', 'Saúde do cliente', 'Score 0-100 (entrega, aprovações, resultados, sentimento, comercial).', 'scripts.read', 'ws', false,
   'Ainda não há dados para isto: precisa de cerca de 6 meses de histórico e de sentimento do cliente (BIZ-09).', 90),
  ('fin.mrr', 'financeiro', 'MRR', 'Receita mensal recorrente dos contratos ativos, na moeda escolhida.', 'biz.finance', 'org', true, null, 110),
  ('fin.cost', 'financeiro', 'Custo do mês', 'Custo de IA das execuções dos agentes + custos humanos, ferramentas e outros (diretos e a parte repartida da agência).', 'biz.finance', 'org', true, null, 120),
  ('fin.margin', 'financeiro', 'Margem de entrega', '(Receita do mês - custo do mês) ÷ receita do mês.', 'biz.finance', 'org', true, null, 130),
  ('fin.cost_per_video', 'financeiro', 'Custo por vídeo', 'Custo do mês ÷ vídeos publicados no mês.', 'biz.finance', 'org', true, null, 140),
  ('fin.cost_per_1k', 'financeiro', 'Custo por 1.000 views', 'Custo do mês ÷ views dos reels do mês × 1.000.', 'biz.finance', 'org', true, null, 150),
  ('fin.payment', 'financeiro', 'Pagamento', 'Estado de pagamento registado no contrato (registo interno, não faturação).', 'biz.finance', 'org', true, null, 160),
  ('fin.renewal', 'financeiro', 'Renovação', 'Data de renovação do contrato e dias que faltam.', 'biz.finance', 'org', true, null, 170)
on conflict (key) do nothing;

-- ───────────── ajudantes (sem verificação de acesso: só chamados pelas RPCs abaixo) ─────────────
create or replace function public._biz_org(p_uid uuid) returns uuid language sql stable security definer set search_path = public as $$
  select organization_id from agency_memberships where user_id = p_uid and status = 'active' order by created_at limit 1
$$;

-- número em texto à portuguesa (vírgula decimal, sem ",0") para os títulos dos cartões
create or replace function public._biz_pt(p numeric) returns text language sql immutable set search_path = public as $$
  select case when p is null then '-' else regexp_replace(replace(round(p, 1)::text, '.', ','), ',0$', '') end
$$;

-- capacidade de agência + flag ligada; devolve a organização
create or replace function public._biz_require(p_cap text, p_action text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  org := public._biz_org(uid);
  if org is null or not public._org_can(p_cap, org, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'action', p_action, 'capability', p_cap);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  -- disponibilidade não é autorização, mas uma flag desligada bloqueia com erro explícito (CAP-09)
  if not public._flag_on('biz.view', null) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A vista de negócio ainda não está ligada para ti.';
  end if;
  return org;
end $$;

-- p_rate = AED por 1 EUR
create or replace function public._biz_conv(p_amount numeric, p_from text, p_to text, p_rate numeric) returns numeric
language sql immutable set search_path = public as $$
  select case when p_amount is null then null
              when p_from = p_to then round(p_amount, 2)
              when p_rate is null then null
              when p_from = 'EUR' and p_to = 'AED' then round(p_amount * p_rate, 2)
              when p_from = 'AED' and p_to = 'EUR' then round(p_amount / p_rate, 2) end
$$;

create or replace function public._biz_month(p_month date) returns date language plpgsql stable set search_path = public as $$
declare m date := date_trunc('month', p_month)::date;
begin
  if p_month is null or m > date_trunc('month', now() + interval '1 day')::date or m < (date_trunc('month', now()) - interval '24 months')::date then
    raise exception 'periodo_invalido' using errcode = '22023', detail = 'Escolhe um mês dos últimos 24 meses.';
  end if;
  return m;
end $$;

-- contrato em vigor numa data (a versão mais recente com efeito até essa data)
create or replace function public._biz_contract_at(p_ws text, p_date date) returns client_contracts
language sql stable security definer set search_path = public as $$
  select * from client_contracts where workspace_id = p_ws and effective_from <= p_date order by effective_from desc, version desc limit 1
$$;

-- receita mensal equivalente de um contrato numa data, na moeda original
create or replace function public._biz_monthly(c client_contracts, p_date date) returns numeric language sql immutable set search_path = public as $$
  select case when c.id is null or c.status <> 'ativo' or (c.starts_on is not null and c.starts_on > p_date) then null
              else round(c.amount / case c.billing_period when 'trimestral' then 3 when 'anual' then 12 else 1 end, 2) end
$$;

create or replace function public._biz_is_client_actor(p_ws text, p_kind text, p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_kind = 'legacy_code' or exists (select 1 from workspace_access a where a.workspace_id = p_ws and a.user_id = p_uid and a.affiliation_type = 'client_staff')
$$;

-- primeira publicação de cada conteúdo (publicação ligada ou transição para publicado)
create or replace function public._biz_first_pub(p_ws text) returns table (content_id text, first_at timestamptz)
language sql stable security definer set search_path = public as $$
  select x.cid, min(x.at) from (
    select p.guiao_id cid, p.published_at at from publicacoes p join guioes g on g.id = p.guiao_id where g.client_id = p_ws and p.published_at is not null
    union all
    select ct.content_id, ct.at from content_transitions ct where ct.workspace_id = p_ws and ct.kind = 'production' and ct.to_status = 'published') x
  group by x.cid
$$;

-- vídeos (conteúdos canónicos) publicados pela primeira vez numa janela [pressuposto: um conteúdo em 3 plataformas conta 1 vídeo]
create or replace function public._biz_published(p_ws text, f timestamptz, t timestamptz) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public._biz_first_pub(p_ws) where first_at >= f and first_at < t
$$;

-- Itens parados por etapa (BIZ-02): idade na etapa atual vs p50/p70 das passagens dos últimos 90 dias deste cliente.
create or replace function public._biz_stalled(p_ws text) returns jsonb language sql stable security definer set search_path = public as $$
  with tr as (
    select ct.content_id, ct.kind, ct.to_status, ct.at,
           lead(ct.at) over (partition by ct.content_id, ct.kind order by ct.at, ct.id) next_at
      from content_transitions ct where ct.workspace_id = p_ws and ct.at >= now() - interval '180 days'),
  stages(kind, st, sort) as (values ('editorial', 'draft', 1), ('editorial', 'in_review', 2), ('editorial', 'changes_requested', 3),
                                   ('production', 'scheduled', 4), ('production', 'recording', 5), ('production', 'recorded', 6),
                                   ('production', 'editing', 7), ('production', 'ready', 8)),
  hist as (
    select s.kind, s.st, count(tr.next_at) n,
           percentile_cont(0.5) within group (order by extract(epoch from tr.next_at - tr.at) / 3600) p50,
           percentile_cont(0.7) within group (order by extract(epoch from tr.next_at - tr.at) / 3600) p70
      from stages s left join tr on tr.kind = s.kind and tr.to_status = s.st and tr.next_at is not null and tr.at >= now() - interval '90 days'
     group by s.kind, s.st),
  open_items as (
    select g.id,
           case when g.production_status in ('scheduled', 'recording', 'recorded', 'editing', 'ready') then 'production' else 'editorial' end kind,
           case when g.production_status in ('scheduled', 'recording', 'recorded', 'editing', 'ready') then g.production_status else g.editorial_status end st,
           g.created_at
      from guioes g
     where g.client_id = p_ws and g.editorial_status not in ('rejected', 'archived') and g.production_status not in ('cancelled', 'published')
       and (g.production_status in ('scheduled', 'recording', 'recorded', 'editing', 'ready') or g.editorial_status in ('draft', 'in_review', 'changes_requested'))),
  aged as (
    select o.kind, o.st, extract(epoch from now() - coalesce(
             (select max(ct.at) from content_transitions ct where ct.content_id = o.id and ct.kind = o.kind and ct.to_status = o.st), o.created_at)) / 3600 age_h
      from open_items o),
  per as (
    select s.kind, s.st, s.sort, h.n, h.p50, h.p70,
           (select count(*) from aged a where a.kind = s.kind and a.st = s.st) open_n,
           (select count(*) from aged a where a.kind = s.kind and a.st = s.st and h.n >= 10 and a.age_h > h.p70) over70,
           (select count(*) from aged a where a.kind = s.kind and a.st = s.st and h.n >= 10 and a.age_h > h.p50 and a.age_h <= h.p70) over50
      from stages s join hist h on h.kind = s.kind and h.st = s.st)
  select jsonb_build_object(
    'over_p70', coalesce(sum(over70), 0), 'over_p50', coalesce(sum(over50), 0),
    'open', coalesce(sum(open_n), 0),
    'unmeasured', coalesce(sum(open_n) filter (where n < 10), 0),
    'stages', coalesce(jsonb_agg(jsonb_build_object('stage', st, 'kind', kind, 'samples', n, 'open', open_n,
                'p50_h', case when n >= 10 then round(p50::numeric, 1) end, 'p70_h', case when n >= 10 then round(p70::numeric, 1) end,
                'over_p70', over70, 'over_p50', over50) order by sort) filter (where open_n > 0 or n >= 10), '[]'))
  from per
$$;
