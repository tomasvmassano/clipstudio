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

-- Números operacionais de um cliente num mês (só as métricas cujas capacidades estão em p_caps).
-- Devolve também _hours e _idx (amostras) para a agência calcular medianas reais; a RPC pública tira-as antes de responder.
create or replace function public._biz_ops(p_ws text, p_month date, p_caps text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; m0 date := p_month; m1 date := (p_month + interval '1 month')::date; f timestamptz; t timestamptz;
        dim int; elapsed int; c client_contracts; lag int; v_out jsonb := '{}'; a record; target int; contracted int; expected numeric;
        hours numeric[]; idx numeric[]; fpr record; r7 record; r30 record;
begin
  select timezone into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  f := m0::timestamp at time zone tz;
  t := least(m1::timestamp at time zone tz, now());
  dim := m1 - m0;
  elapsed := case when today >= m1 then dim when today < m0 then 0 else today - m0 + 1 end;
  c := public._biz_contract_at(p_ws, least(m1 - 1, today));
  lag := coalesce(c.deadline_days, 7);

  if 'scripts.read' = any(p_caps) then
    select nullif(v.config #>> '{pipeline,scripts_per_day}', '')::int into target
      from agent_config_versions v where v.workspace_id = p_ws and v.status = 'active' limit 1;
    v_out := v_out || jsonb_build_object('ops.today', (
      select jsonb_build_object('date', today, 'planned', count(*),
               'recorded', count(*) filter (where g.gravado or g.production_status in ('recorded', 'editing', 'ready', 'published')),
               'target', target)
        from guioes g where g.client_id = p_ws and g.date = today and g.editorial_status not in ('rejected', 'archived') and g.production_status <> 'cancelled'));

    v_out := v_out || jsonb_build_object('ops.approvals', (
      select jsonb_build_object('pending', count(*), 'over_48h', count(*) filter (where since < now() - interval '48 hours'))
        from (select coalesce((select max(ct.at) from content_transitions ct where ct.content_id = g.id and ct.kind = 'editorial' and ct.to_status = 'in_review'),
                              g.created_at) since
                from guioes g where g.client_id = p_ws and g.editorial_status = 'in_review') x));

    v_out := v_out || jsonb_build_object('ops.stalled', public._biz_stalled(p_ws));

    -- BIZ-01: atingimento de entrega
    select
      count(*) filter (where x.first_at >= f and x.first_at < t and x.pub_day <= x.deadline) on_time,
      count(*) filter (where x.first_at >= f and x.first_at < t and x.pub_day > x.deadline) late_pub,
      count(*) filter (where x.first_at is null and x.open and x.deadline >= m0 and x.deadline < least(today, m1)) overdue,
      count(*) filter (where x.first_at is null and x.open and x.deadline = today) due_today,
      count(*) filter (where ((x.first_at >= f and x.first_at < t and x.pub_day > x.deadline)
                              or (x.first_at is null and x.open and x.deadline >= m0 and x.deadline < least(today, m1))) and x.client_cause) late_client
      into a
      from (
        select g.id, g.date + lag deadline, fp.first_at, (fp.first_at at time zone tz)::date pub_day,
               g.editorial_status not in ('rejected', 'archived') and g.production_status <> 'cancelled' open,
               -- [pressuposto] atraso do cliente: aprovação feita pela equipa do cliente mais de 48 h depois do envio, guião ainda à espera
               -- de aprovação há mais de 48 h, ou gravação depois do dia planeado (a gravação é do criador)
               (exists (select 1 from content_transitions ap where ap.content_id = g.id and ap.kind = 'editorial' and ap.to_status = 'approved'
                          and public._biz_is_client_actor(p_ws, ap.actor_kind, ap.actor_user_id)
                          and ap.at - coalesce((select max(s.at) from content_transitions s where s.content_id = g.id and s.kind = 'editorial'
                                                  and s.to_status = 'in_review' and s.at <= ap.at), g.created_at) > interval '48 hours')
                or (g.editorial_status = 'in_review' and coalesce((select max(s.at) from content_transitions s where s.content_id = g.id and s.kind = 'editorial'
                                                                     and s.to_status = 'in_review'), g.created_at) < now() - interval '48 hours')
                or (g.gravado_em is not null and (g.gravado_em at time zone tz)::date > g.date)
                or (g.gravado_em is null and g.production_status in ('not_started', 'scheduled') and g.date < today)) client_cause
          from guioes g left join public._biz_first_pub(p_ws) fp on fp.content_id = g.id
         where g.client_id = p_ws) x;
    contracted := c.videos_per_month;
    expected := case when contracted is not null and c.status = 'ativo' then round(contracted::numeric * elapsed / dim, 1) end;
    v_out := v_out || jsonb_build_object('ops.attainment', jsonb_build_object(
      'contract', contracted is not null and c.status = 'ativo',
      'contracted', case when c.status = 'ativo' then contracted end, 'expected_to_date', expected, 'deadline_days', lag,
      'on_time', a.on_time, 'late_published', a.late_pub, 'overdue', a.overdue, 'due_today', a.due_today,
      'late_client', a.late_client, 'late_agency', a.late_pub + a.overdue - a.late_client,
      'pct', case when contracted > 0 and c.status = 'ativo' then round(100.0 * a.on_time / contracted, 1) end,
      'pace', case when expected >= 1 then round(100.0 * a.on_time / expected, 1) end,
      'target', 95, 'alert_below', 90,
      'alert', expected >= 1 and 100.0 * a.on_time / expected < 90));

    -- aprovação à primeira: primeira aprovação no mês sem changes_requested/rejected antes
    select count(*) n, count(*) filter (where not exists (select 1 from content_transitions b where b.content_id = x.content_id and b.kind = 'editorial'
                                                             and b.to_status in ('changes_requested', 'rejected') and b.at < x.at)) ok
      into fpr
      from (select content_id, min(at) at from content_transitions where workspace_id = p_ws and kind = 'editorial' and to_status = 'approved' group by content_id) x
     where x.at >= f and x.at < t;
    v_out := v_out || jsonb_build_object('ops.first_pass', jsonb_build_object('approved', fpr.n, 'first_pass', fpr.ok,
      'pct', case when fpr.n > 0 then round(100.0 * fpr.ok / fpr.n, 1) end));

    -- tempo de aprovação do cliente (aprovações feitas pela equipa do cliente ou pelo código de equipa)
    select array_agg(h order by h) into hours from (
      select round((extract(epoch from ap.at - coalesce((select max(s.at) from content_transitions s where s.content_id = ap.content_id and s.kind = 'editorial'
                                                           and s.to_status = 'in_review' and s.at <= ap.at), g.created_at)) / 3600)::numeric, 2) h
        from content_transitions ap join guioes g on g.id = ap.content_id
       where ap.workspace_id = p_ws and ap.kind = 'editorial' and ap.to_status = 'approved' and ap.at >= f and ap.at < t
         and coalesce(ap.reason, '') <> 'criado' and public._biz_is_client_actor(p_ws, ap.actor_kind, ap.actor_user_id)) y;
    v_out := v_out || jsonb_build_object('ops.approval_time', jsonb_build_object('n', coalesce(cardinality(hours), 0),
      'median_h', (select round(percentile_cont(0.5) within group (order by h)::numeric, 1) from unnest(hours) h), '_hours', to_jsonb(coalesce(hours, '{}'))));
  end if;

  if 'analytics.read' = any(p_caps) then
    -- PERF-04: views ÷ mediana dos 30 dias anteriores da mesma conta (mínimo 5 reels de base [pressuposto])
    with r as (
      select r.account_id, r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select array_agg(i order by i) into idx from (
      select round(cur.views::numeric / nullif(b.med, 0)::numeric, 3) i
        from r cur cross join lateral (select percentile_cont(0.5) within group (order by r2.views) med, count(*) n
                                         from r r2 where r2.account_id = cur.account_id and r2.at >= cur.at - interval '30 days' and r2.at < cur.at) b
       where cur.at >= f and cur.at < t and b.n >= 5 and b.med > 0) z;
    v_out := v_out || jsonb_build_object('ops.performance', jsonb_build_object('n', coalesce(cardinality(idx), 0),
      'median', (select round(percentile_cont(0.5) within group (order by i)::numeric, 2) from unnest(idx) i), '_idx', to_jsonb(coalesce(idx, '{}'))));

    -- supressão: mediana dos últimos 7 dias vs mediana dos 30 dias anteriores (mínimos 3 e 5 reels [pressuposto])
    with r as (
      select r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select count(*) n, percentile_cont(0.5) within group (order by views) med into r7 from r where at >= now() - interval '7 days';
    with r as (
      select r.views, coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) at
        from reels r join accounts ac on ac.id = r.account_id where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client')
    select count(*) n, percentile_cont(0.5) within group (order by views) med into r30 from r where at >= now() - interval '37 days' and at < now() - interval '7 days';
    v_out := v_out || jsonb_build_object('ops.reach', jsonb_build_object('n7', r7.n, 'n30', r30.n,
      'median_7d', round(r7.med::numeric), 'median_30d', round(r30.med::numeric),
      'ratio', case when r7.n >= 3 and r30.n >= 5 and r30.med > 0 then round((r7.med / r30.med)::numeric * 100, 1) end));
  end if;
  return v_out;
end $$;

-- Números financeiros de um cliente num mês, já na moeda pedida. p_shared: custo repartido da agência para este cliente.
create or replace function public._biz_fin(p_ws text, p_month date, p_cur text, p_rate numeric, p_shared numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; today date; m0 date := p_month; m1 date := (p_month + interval '1 month')::date; f timestamptz; t timestamptz; ref date;
        c client_contracts; mrr_o numeric; mrr numeric; ai numeric; direct numeric; direct_missing boolean; cost numeric; vids int; views bigint;
begin
  select timezone into tz from clients where id = p_ws;
  today := (now() at time zone tz)::date;
  f := m0::timestamp at time zone tz;
  t := least(m1::timestamp at time zone tz, now());
  ref := least(m1 - 1, today);
  c := public._biz_contract_at(p_ws, ref);
  mrr_o := public._biz_monthly(c, ref);
  mrr := public._biz_conv(mrr_o, c.currency, p_cur, p_rate);
  select round(coalesce(sum(cost_eur), 0), 2) into ai from agent_jobs where workspace_id = p_ws and finished_at >= f and finished_at < t
     and status in ('succeeded', 'failed', 'dead', 'cancelled');
  select coalesce(sum(public._biz_conv(amount, currency, p_cur, p_rate)), 0), bool_or(public._biz_conv(amount, currency, p_cur, p_rate) is null)
    into direct, direct_missing
    from agency_costs where workspace_id = p_ws and month = m0 and voided_at is null;
  cost := case when coalesce(direct_missing, false) or (ai > 0 and public._biz_conv(ai, 'EUR', p_cur, p_rate) is null) or p_shared is null then null
               else public._biz_conv(ai, 'EUR', p_cur, p_rate) + direct + p_shared end;
  vids := public._biz_published(p_ws, f, t);
  select coalesce(sum(r.views), 0) into views from reels r join accounts ac on ac.id = r.account_id
   where r.client_id = p_ws and ac.client_id = p_ws and ac.role = 'client'
     and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) >= f and coalesce(r.taken_at, nullif(r."timestamp", '')::timestamptz) < t;
  return jsonb_build_object(
    'contract', c.id is not null,
    'contract_status', c.status,
    'amount', c.amount, 'contract_currency', c.currency, 'billing_period', c.billing_period,
    'fin.mrr', mrr, 'mrr_original', mrr_o,
    'fin.cost', cost, 'cost_ai', public._biz_conv(ai, 'EUR', p_cur, p_rate), 'cost_direct', direct, 'cost_shared', p_shared,
    'fin.margin', case when mrr > 0 and cost is not null then round(100 * (mrr - cost) / mrr, 1) end,
    'videos', vids, 'views', views,
    'fin.cost_per_video', case when vids > 0 and cost is not null then round(cost / vids, 2) end,
    'fin.cost_per_1k', case when views > 0 and cost is not null then round(cost / views * 1000, 2) end,
    'fin.payment', case when c.id is not null then jsonb_build_object('status', c.payment_status, 'due_on', c.payment_due_on,
                     'overdue_days', case when c.payment_status = 'vencido' and c.payment_due_on is not null and c.payment_due_on < today then today - c.payment_due_on end) end,
    'fin.renewal', case when c.renewal_on is not null then jsonb_build_object('on', c.renewal_on, 'days', c.renewal_on - today) end,
    'fx_missing', (mrr_o is not null and mrr is null) or cost is null);
end $$;

-- custo de IA por vídeo nos últimos 30 dias vs os 30 anteriores (para o alerta de +25% sem subida de volume)
create or replace function public._biz_ai_trend(p_ws text) returns jsonb language sql stable security definer set search_path = public as $$
  with w as (select
    (select coalesce(sum(cost_eur), 0) from agent_jobs where workspace_id = p_ws and finished_at >= now() - interval '30 days') c1,
    (select coalesce(sum(cost_eur), 0) from agent_jobs where workspace_id = p_ws and finished_at >= now() - interval '60 days' and finished_at < now() - interval '30 days') c0,
    public._biz_published(p_ws, now() - interval '30 days', now()) v1,
    public._biz_published(p_ws, now() - interval '60 days', now() - interval '30 days') v0)
  select jsonb_build_object('cpv_now', case when v1 > 0 then round(c1 / v1, 2) end, 'cpv_prev', case when v0 > 0 then round(c0 / v0, 2) end,
                            'videos_now', v1, 'videos_prev', v0,
                            'alert', v1 > 0 and v0 > 0 and c0 > 0 and (c1 / v1) > 1.25 * (c0 / v0) and v1 <= v0) from w
$$;

revoke execute on function public._biz_org(uuid), public._biz_require(text, text), public._biz_contract_at(text, date), public._biz_is_client_actor(text, text, uuid),
  public._biz_first_pub(text), public._biz_published(text, timestamptz, timestamptz), public._biz_stalled(text), public._biz_ops(text, date, text[]),
  public._biz_fin(text, date, text, numeric, numeric), public._biz_ai_trend(text) from public, anon, authenticated;

-- ───────────── RPC pública da vista ─────────────
-- Uma resposta por pessoa: clientes a que tem acesso (dono: todos os ativos), métricas operacionais por capacidade no cliente,
-- e os campos e totais financeiros só com biz.finance. Sem biz.finance não sai nenhuma chave financeira (BIZ-04).
create or replace function public.biz_overview(p_month date, p_currency text default 'EUR') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid; m date; fin boolean; fx fx_rates; rate numeric; cl record; caps text[]; ops jsonb; fj jsonb;
        rows jsonb := '[]'; n int := 0; missing jsonb := '{}'; k text;
        att_on int := 0; att_con int := 0; att_exp numeric := 0; fp_n int := 0; fp_ok int := 0; hours numeric[] := '{}'; idx numeric[] := '{}';
        over70 int := 0; pend int := 0; pend48 int := 0;
        shared jsonb := '{}'; alloc numeric; tot_mrr numeric := 0; tot_cost numeric := 0; tot_vids int := 0; tot_views bigint := 0; fx_missing boolean := false;
        risk int := 0; cards jsonb := '[]'; unavailable jsonb; conc jsonb := '[]'; s record; mm date; share numeric; trend jsonb; ai jsonb;
        sev int; nm text; href text;
begin
  org := public._biz_require('biz.read', 'biz.overview');
  m := public._biz_month(p_month);
  if p_currency is null or p_currency not in ('EUR', 'AED') then raise exception 'moeda_invalida' using errcode = '22023', detail = 'Moedas: EUR ou AED.'; end if;
  fin := public._org_can('biz.finance', org, uid);
  if fin then
    select * into fx from fx_rates where organization_id = org order by as_of desc, id desc limit 1;
    rate := fx.rate;
    -- custos da agência repartidos [pressuposto: por todos os clientes ativos; "por_videos" pelos vídeos publicados no mês, igual se não houver nenhum]
    with act as (select c.id, public._biz_published(c.id, (m::timestamp at time zone c.timezone), least(((m + interval '1 month')::date)::timestamp at time zone c.timezone, now())) v
                   from clients c where c.organization_id = org and c.status = 'active'),
         tot as (select count(*) n, sum(v) v from act),
         sc as (select public._biz_conv(amount, currency, p_currency, rate) amt, allocation from agency_costs
                 where organization_id = org and workspace_id is null and month = m and voided_at is null)
    select coalesce(jsonb_object_agg(act.id, (select case when bool_or(sc.amt is null) then null else coalesce(round(sum(
             case when sc.allocation = 'por_videos' and tot.v > 0 then sc.amt * act.v / tot.v else sc.amt / tot.n end), 2), 0) end from sc)), '{}')
      into shared from act, tot;
  end if;

  for cl in select c.* from clients c where c.organization_id = org and c.status = 'active'
              and (public._org_can('workspaces.read', org, uid) and public.is_agency_owner(uid)
                   or exists (select 1 from workspace_access a where a.workspace_id = c.id and a.user_id = uid and a.status = 'active'
                                and a.affiliation_type = 'agency_staff' and (a.expires_at is null or a.expires_at > now())))
            order by lower(c.name) loop
    caps := array(select x from unnest(array['scripts.read', 'analytics.read']) x where public._authorize(x, cl.id, uid));
    if cardinality(caps) = 0 and not fin then continue; end if;
    n := n + 1;
    ops := public._biz_ops(cl.id, m, caps);
    for k in select key from biz_metrics where level = 'operacional' and available loop
      if not ops ? k then missing := jsonb_set(missing, array[k], to_jsonb(coalesce((missing ->> k)::int, 0) + 1)); end if;
    end loop;
    if ops ? 'ops.attainment' then
      att_on := att_on + (ops #>> '{ops.attainment,on_time}')::int;
      if (ops #>> '{ops.attainment,contract}')::boolean then
        att_con := att_con + coalesce((ops #>> '{ops.attainment,contracted}')::int, 0);
        att_exp := att_exp + coalesce((ops #>> '{ops.attainment,expected_to_date}')::numeric, 0);
      end if;
      fp_n := fp_n + (ops #>> '{ops.first_pass,approved}')::int; fp_ok := fp_ok + (ops #>> '{ops.first_pass,first_pass}')::int;
      hours := hours || array(select jsonb_array_elements_text(ops #> '{ops.approval_time,_hours}')::numeric);
      over70 := over70 + (ops #>> '{ops.stalled,over_p70}')::int;
      pend := pend + (ops #>> '{ops.approvals,pending}')::int; pend48 := pend48 + (ops #>> '{ops.approvals,over_48h}')::int;
      ops := jsonb_set(ops, '{ops.approval_time}', (ops -> 'ops.approval_time') - '_hours');
    end if;
    if ops ? 'ops.performance' then
      idx := idx || array(select jsonb_array_elements_text(ops #> '{ops.performance,_idx}')::numeric);
      ops := jsonb_set(ops, '{ops.performance}', (ops -> 'ops.performance') - '_idx');
    end if;

    -- cartões operacionais (BIZ-02). rank: 3 crítico, 2 alto, 1 aviso
    nm := cl.name;
    if (ops #>> '{ops.attainment,alert}')::boolean then
      sev := case when (ops #>> '{ops.attainment,pace}')::numeric < 75 then 3 else 2 end;
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'delivery', 'rank', sev, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('Entrega em risco: %s%% do ritmo', public._biz_pt((ops #>> '{ops.attainment,pace}')::numeric)),
        'detail', format('%s no prazo de %s esperados até hoje; %s com prazo hoje por publicar; %s em atraso (%s do cliente).',
                         ops #>> '{ops.attainment,on_time}', public._biz_pt(round((ops #>> '{ops.attainment,expected_to_date}')::numeric)), ops #>> '{ops.attainment,due_today}',
                         ops #>> '{ops.attainment,overdue}', ops #>> '{ops.attainment,late_client}'),
        'action_label', 'Abrir calendário', 'action_href', '/c/' || cl.id || '/calendario'));
    end if;
    if coalesce((ops #>> '{ops.stalled,over_p70}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'stalled', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s parados acima do p70', ops #>> '{ops.stalled,over_p70}', case when (ops #>> '{ops.stalled,over_p70}')::int = 1 then 'item' else 'itens' end),
        'detail', 'Estão há mais tempo na etapa do que 70% das passagens dos últimos 90 dias.',
        'action_label', 'Ver guiões', 'action_href', '/c/' || cl.id || '/guioes'));
    elsif coalesce((ops #>> '{ops.stalled,over_p50}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'stalled', 'rank', 1, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s a ficar parados', ops #>> '{ops.stalled,over_p50}', case when (ops #>> '{ops.stalled,over_p50}')::int = 1 then 'item' else 'itens' end),
        'detail', 'Já passaram a mediana do tempo da etapa (aviso a partir do p50).',
        'action_label', 'Ver guiões', 'action_href', '/c/' || cl.id || '/guioes'));
    end if;
    if coalesce((ops #>> '{ops.approvals,over_48h}')::int, 0) > 0 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'approval', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('%s %s à espera de aprovação há mais de 48 h', ops #>> '{ops.approvals,over_48h}',
                        case when (ops #>> '{ops.approvals,over_48h}')::int = 1 then 'guião' else 'guiões' end),
        'detail', 'Pede a aprovação ao cliente ou revê as prioridades da revisão.',
        'action_label', 'Abrir revisão', 'action_href', '/c/' || cl.id || '/revisao'));
    end if;
    if (ops #>> '{ops.reach,ratio}')::numeric < 60 then
      cards := cards || jsonb_build_array(jsonb_build_object('key', 'suppression', 'rank', 2, 'level', 'operacional', 'client_id', cl.id, 'client_name', nm,
        'title', format('Possível supressão: views a %s%% do normal', public._biz_pt((ops #>> '{ops.reach,ratio}')::numeric)),
        'detail', format('Mediana de %s views nos últimos 7 dias contra %s nos 30 anteriores.', ops #>> '{ops.reach,median_7d}', ops #>> '{ops.reach,median_30d}'),
        'action_label', 'Abrir desempenho', 'action_href', '/c/' || cl.id || '/desempenho'));
    end if;

    fj := null;
    if fin then
      alloc := case when shared ? cl.id then (shared ->> cl.id)::numeric else 0 end;
      if shared ? cl.id and shared -> cl.id = 'null'::jsonb then alloc := null; end if;
      fj := public._biz_fin(cl.id, m, p_currency, rate, alloc);
      if (fj ->> 'fx_missing')::boolean then fx_missing := true; end if;
      tot_mrr := tot_mrr + coalesce((fj ->> 'fin.mrr')::numeric, 0);
      tot_cost := case when tot_cost is null or (fj ->> 'fin.cost') is null then null else tot_cost + (fj ->> 'fin.cost')::numeric end;
      tot_vids := tot_vids + (fj ->> 'videos')::int; tot_views := tot_views + (fj ->> 'views')::bigint;
      -- [pressuposto] cliente em risco: fatura vencida há mais de 15 dias, margem abaixo de 50%, ou renovação em 30 dias com entrega abaixo de 90%
      if coalesce((fj #>> '{fin.payment,overdue_days}')::int, 0) > 15 or (fj ->> 'fin.margin')::numeric < 50
         or (coalesce((fj #>> '{fin.renewal,days}')::int, 999) between 0 and 30 and (ops #>> '{ops.attainment,pace}')::numeric < 90) then
        risk := risk + 1;
      end if;
      if (fj ->> 'fin.margin')::numeric < 50 then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'margin', 'rank', 2, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', format('Margem de entrega a %s%%', public._biz_pt((fj ->> 'fin.margin')::numeric)), 'detail', 'Abaixo dos 50%: revê custos e volume contratado.',
          'action_label', 'Ver custos', 'action_href', '/negocio/contratos?ws=' || cl.id));
      end if;
      if coalesce((fj #>> '{fin.payment,overdue_days}')::int, 0) > 15 then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'invoice', 'rank', 3, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', format('Pagamento vencido há %s dias', fj #>> '{fin.payment,overdue_days}'), 'detail', 'Registado como vencido no contrato.',
          'action_label', 'Abrir contrato', 'action_href', '/negocio/contratos?ws=' || cl.id));
      end if;
      ai := public._biz_ai_trend(cl.id);
      if (ai ->> 'alert')::boolean then
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'ai_cost', 'rank', 1, 'level', 'financeiro', 'client_id', cl.id, 'client_name', nm,
          'title', 'Custo de IA por vídeo subiu mais de 25%',
          'detail', format('%s EUR por vídeo nos últimos 30 dias contra %s EUR nos 30 anteriores, sem mais vídeos.', replace(ai ->> 'cpv_now', '.', ','), replace(ai ->> 'cpv_prev', '.', ',')),
          'action_label', 'Ver agentes', 'action_href', '/c/' || cl.id || '/agentes/configuracao'));
      end if;
    end if;

    rows := rows || jsonb_build_array(jsonb_build_object('id', cl.id, 'name', cl.name, 'handle', cl.handle, 'logo_path', cl.logo_path,
      'brand_color', cl.brand_color, 'timezone', cl.timezone, 'ops', ops) || case when fin then jsonb_build_object('fin', fj) else '{}' end);
  end loop;

  if fin then
    -- concentração: cliente com mais de 20% do MRR em cada um dos últimos 3 fins de mês (mostrado como tendência)
    for s in select c.id, c.name from clients c where c.organization_id = org and c.status = 'active' loop
      trend := '[]';
      for mm in select (date_trunc('month', m) - make_interval(months => g) + interval '1 month' - interval '1 day')::date from generate_series(2, 0, -1) g loop
        mm := least(mm, (now() at time zone 'Asia/Dubai')::date);
        select round(100 * sum(case when c2.id = s.id then v end) / nullif(sum(v), 0), 1) into share
          from (select c2.id, public._biz_conv(public._biz_monthly(public._biz_contract_at(c2.id, mm), mm), (public._biz_contract_at(c2.id, mm)).currency, p_currency, rate) v
                  from clients c2 where c2.organization_id = org and c2.status = 'active') c2;
        trend := trend || jsonb_build_array(jsonb_build_object('date', mm, 'share', share));
      end loop;
      if (select bool_and(coalesce((x ->> 'share')::numeric, 0) > 20) from jsonb_array_elements(trend) x) then
        conc := conc || jsonb_build_array(jsonb_build_object('client_id', s.id, 'client_name', s.name, 'trend', trend));
        cards := cards || jsonb_build_array(jsonb_build_object('key', 'concentration', 'rank', 1, 'level', 'financeiro', 'client_id', s.id, 'client_name', s.name,
          'title', format('%s%% do MRR há 3 meses', public._biz_pt((trend -> 2 ->> 'share')::numeric)),
          'detail', format('Peso no MRR: %s%%, %s%%, %s%% nos últimos 3 fins de mês.', public._biz_pt((trend -> 0 ->> 'share')::numeric), public._biz_pt((trend -> 1 ->> 'share')::numeric), public._biz_pt((trend -> 2 ->> 'share')::numeric)),
          'trend', trend, 'action_label', 'Ver contratos', 'action_href', '/negocio/contratos?ws=' || s.id));
      end if;
    end loop;
  end if;

  unavailable := jsonb_build_array(
    jsonb_build_object('key', 'health_drop', 'label', 'Saúde do cliente a cair', 'reason', 'Ainda não há score de saúde: precisa de cerca de 6 meses de histórico e de sentimento (BIZ-09).'),
    jsonb_build_object('key', 'near_zero', 'label', 'Posts perto de zero a duplicar', 'reason', 'Ainda não há leituras das publicações por idade (PERF-03).'))
    || case when fin then jsonb_build_array(jsonb_build_object('key', 'renewal_health', 'label', 'Renovação em 30 dias com saúde amarela ou vermelha',
         'reason', 'Depende da saúde do cliente (BIZ-09). A data de renovação aparece na tabela.')) else '[]' end;

  return jsonb_build_object(
    'month', m, 'currency', p_currency, 'finance', fin, 'can_manage', fin and public._org_can('contracts.manage', org, uid), 'count', n,
    'metrics', (select jsonb_agg(jsonb_build_object('key', key, 'level', level, 'label', label, 'description', description, 'capability', capability,
                  'available', available, 'unavailable_reason', unavailable_reason) order by sort) from biz_metrics where fin or level = 'operacional'),
    'clients', rows, 'missing', missing,
    'totals', jsonb_build_object(
      'ops.attainment', jsonb_build_object('on_time', att_on, 'contracted', att_con, 'expected_to_date', round(att_exp, 1),
                          'pct', case when att_con > 0 then round(100.0 * att_on / att_con, 1) end,
                          'pace', case when att_exp >= 1 then round(100.0 * att_on / att_exp, 1) end, 'target', 95, 'alert_below', 90),
      'ops.first_pass', jsonb_build_object('approved', fp_n, 'first_pass', fp_ok, 'pct', case when fp_n > 0 then round(100.0 * fp_ok / fp_n, 1) end),
      'ops.approval_time', jsonb_build_object('n', cardinality(hours), 'median_h', (select round(percentile_cont(0.5) within group (order by h)::numeric, 1) from unnest(hours) h)),
      'ops.performance', jsonb_build_object('n', cardinality(idx), 'median', (select round(percentile_cont(0.5) within group (order by i)::numeric, 2) from unnest(idx) i)),
      'ops.stalled', jsonb_build_object('over_p70', over70),
      'ops.approvals', jsonb_build_object('pending', pend, 'over_48h', pend48))
      || case when fin then jsonb_build_object(
        'fin.mrr', tot_mrr, 'fin.cost', tot_cost,
        'fin.margin', case when tot_mrr > 0 and tot_cost is not null then round(100 * (tot_mrr - tot_cost) / tot_mrr, 1) end,
        'fin.cost_per_video', case when tot_vids > 0 and tot_cost is not null then round(tot_cost / tot_vids, 2) end,
        'fin.cost_per_1k', case when tot_views > 0 and tot_cost is not null then round(tot_cost / tot_views * 1000, 2) end,
        'at_risk', risk, 'concentration', conc) else '{}' end,
    'attention', jsonb_build_object(
      'cards', coalesce((select jsonb_agg(x - 'rank' || jsonb_build_object('severity', case (x ->> 'rank')::int when 3 then 'critico' when 2 then 'alto' else 'aviso' end)
                          order by (x ->> 'rank')::int desc, x ->> 'level' desc, x ->> 'client_name')
                         from (select x from jsonb_array_elements(cards) x order by (x ->> 'rank')::int desc, x ->> 'level' desc, x ->> 'client_name' limit 5) y), '[]'),
      'more', greatest(jsonb_array_length(cards) - 5, 0),
      'unavailable', unavailable))
    || case when fin then jsonb_build_object('fx', case when fx.id is not null then jsonb_build_object('base', 'EUR', 'quote', 'AED', 'rate', fx.rate, 'as_of', fx.as_of, 'source', fx.source) end,
                                             'fx_missing', fx_missing) else '{}' end;
end $$;

-- ───────────── contratos, câmbio e custos (só o dono por defeito) ─────────────
create or replace function public.biz_contracts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.contracts');
begin
  return jsonb_build_object(
    'can_manage', public._org_can('contracts.manage', org, auth.uid()),
    'fx', (select jsonb_build_object('rate', rate, 'as_of', as_of, 'source', source, 'created_label', created_label)
             from fx_rates where organization_id = org order by as_of desc, id desc limit 1),
    'fx_history', coalesce((select jsonb_agg(jsonb_build_object('rate', rate, 'as_of', as_of, 'source', source, 'created_at', created_at, 'created_label', created_label)
                              order by as_of desc, id desc) from (select * from fx_rates where organization_id = org order by as_of desc, id desc limit 10) h), '[]'),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'currency', c.currency,
        'versions', (select count(*) from client_contracts k where k.workspace_id = c.id),
        'contract', (select to_jsonb(k) - 'created_by' from client_contracts k where k.workspace_id = c.id order by k.version desc limit 1))
        order by lower(c.name)) from clients c where c.organization_id = org and c.status = 'active'), '[]'));
end $$;

create or replace function public.biz_contract_history(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.contract_history');
begin
  if not exists (select 1 from clients where id = p_ws and organization_id = org) then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  return coalesce((select jsonb_agg(to_jsonb(k) - 'created_by' order by k.version desc) from client_contracts k where k.workspace_id = p_ws), '[]');
end $$;

-- Gravar o contrato cria uma versão nova (as anteriores ficam). p_expected: versão que a pessoa estava a ver (0 sem contrato).
create or replace function public.biz_contract_save(p_ws text, p_fields jsonb, p_expected int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.contract_save'); uid uuid := auth.uid(); old client_contracts; nw client_contracts; k text; cur int;
begin
  if not exists (select 1 from clients where id = p_ws and organization_id = org and status = 'active') then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campo_invalido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('status', 'amount', 'currency', 'billing_period', 'scripts_per_month', 'videos_per_month', 'platforms', 'deadline_days',
                 'starts_on', 'renewal_on', 'effective_from', 'payment_status', 'payment_due_on', 'notes') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k);
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtext('biz_contract:' || p_ws));
  select * into old from client_contracts where workspace_id = p_ws order by version desc limit 1;
  cur := coalesce(old.version, 0);
  if p_expected is distinct from cur then
    raise exception 'conflito_versao' using errcode = '40001', detail = 'Alguém mudou este contrato entretanto. Recarrega e volta a gravar.';
  end if;
  if old.id is null and (nullif(p_fields ->> 'amount', '') is null or nullif(p_fields ->> 'currency', '') is null) then
    raise exception 'campo_obrigatorio' using errcode = '22023', detail = 'Indica o valor e a moeda do contrato.';
  end if;
  begin
    insert into client_contracts (workspace_id, version, status, amount, currency, billing_period, scripts_per_month, videos_per_month, platforms,
                                  deadline_days, starts_on, renewal_on, effective_from, payment_status, payment_due_on, notes, created_by, created_label)
    values (p_ws, cur + 1,
      case when p_fields ? 'status' then p_fields ->> 'status' else coalesce(old.status, 'ativo') end,
      case when p_fields ? 'amount' then (p_fields ->> 'amount')::numeric else old.amount end,
      case when p_fields ? 'currency' then p_fields ->> 'currency' else old.currency end,
      case when p_fields ? 'billing_period' then p_fields ->> 'billing_period' else coalesce(old.billing_period, 'mensal') end,
      case when p_fields ? 'scripts_per_month' then nullif(p_fields ->> 'scripts_per_month', '')::int else old.scripts_per_month end,
      case when p_fields ? 'videos_per_month' then nullif(p_fields ->> 'videos_per_month', '')::int else old.videos_per_month end,
      case when p_fields ? 'platforms' then array(select distinct x from jsonb_array_elements_text(p_fields -> 'platforms') x order by 1) else coalesce(old.platforms, '{}') end,
      case when p_fields ? 'deadline_days' then coalesce(nullif(p_fields ->> 'deadline_days', '')::int, 7) else coalesce(old.deadline_days, 7) end,
      case when p_fields ? 'starts_on' then nullif(p_fields ->> 'starts_on', '')::date else old.starts_on end,
      case when p_fields ? 'renewal_on' then nullif(p_fields ->> 'renewal_on', '')::date else old.renewal_on end,
      case when p_fields ? 'effective_from' then coalesce(nullif(p_fields ->> 'effective_from', '')::date, current_date) else current_date end,
      case when p_fields ? 'payment_status' then p_fields ->> 'payment_status' else coalesce(old.payment_status, 'em_dia') end,
      case when p_fields ? 'payment_due_on' then nullif(p_fields ->> 'payment_due_on', '')::date else old.payment_due_on end,
      case when p_fields ? 'notes' then nullif(trim(p_fields ->> 'notes'), '') else old.notes end,
      uid, (select email from auth.users where id = uid))
    returning * into nw;
  exception
    when check_violation or not_null_violation then
      raise exception 'contrato_invalido' using errcode = '22023', detail = 'Valores fora do permitido: valor de 0 a 10 000 000, moeda EUR ou AED, volumes de 0 a 10 000, prazo de 0 a 60 dias, renovação depois do início.';
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
      raise exception 'contrato_invalido' using errcode = '22023', detail = 'Há um número ou uma data com formato inválido.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', nw.created_label, org, p_ws, 'biz.contract_saved', 'client_contract', nw.id::text, to_jsonb(old) - 'created_by', to_jsonb(nw) - 'created_by');
  return public.biz_contracts();
end $$;

create or replace function public.biz_fx_save(p_rate numeric, p_as_of date, p_source text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.fx_save'); uid uuid := auth.uid(); r fx_rates;
begin
  if p_rate is null or p_rate <= 0 or p_rate >= 1000 then raise exception 'taxa_invalida' using errcode = '22023', detail = 'A taxa tem de ser maior que 0 (AED por 1 EUR).'; end if;
  if p_as_of is null or p_as_of > current_date + 1 then raise exception 'data_invalida' using errcode = '22023', detail = 'Indica a data da taxa (não pode ser futura).'; end if;
  insert into fx_rates (organization_id, rate, as_of, source, created_by, created_label)
  values (org, round(p_rate, 6), p_as_of, nullif(left(trim(coalesce(p_source, '')), 120), ''), uid, (select email from auth.users where id = uid))
  returning * into r;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', r.created_label, org, 'biz.fx_saved', 'fx_rate', r.id::text, null, to_jsonb(r) - 'created_by');
  return public.biz_contracts();
end $$;

create or replace function public.biz_costs(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._biz_require('biz.finance', 'biz.costs'); m date := public._biz_month(p_month);
begin
  return jsonb_build_object('month', m, 'can_manage', public._org_can('contracts.manage', org, auth.uid()),
    'costs', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'workspace_id', k.workspace_id, 'client_name', c.name, 'month', k.month, 'kind', k.kind,
        'label', k.label, 'amount', k.amount, 'currency', k.currency, 'allocation', k.allocation, 'created_at', k.created_at, 'created_label', k.created_label,
        'voided_at', k.voided_at, 'void_reason', k.void_reason) order by k.voided_at nulls first, k.created_at desc)
      from agency_costs k left join clients c on c.id = k.workspace_id where k.organization_id = org and k.month = m), '[]'));
end $$;

-- Acrescentar um custo. p_client_ref torna a gravação idempotente (repetir o pedido não duplica).
create or replace function public.biz_cost_save(p_fields jsonb, p_client_ref uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.cost_save'); uid uuid := auth.uid(); r agency_costs; m date; ws text; k text;
begin
  if p_client_ref is null then raise exception 'referencia_obrigatoria' using errcode = '22023'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campo_invalido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('workspace_id', 'month', 'kind', 'label', 'amount', 'currency', 'allocation') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k);
    end if;
  end loop;
  select * into r from agency_costs where organization_id = org and client_ref = p_client_ref;
  if r.id is not null then return public.biz_costs(r.month); end if;
  begin
    m := public._biz_month((p_fields ->> 'month')::date);
  exception when invalid_datetime_format or datetime_field_overflow or invalid_text_representation then
    raise exception 'periodo_invalido' using errcode = '22023', detail = 'Mês inválido.';
  end;
  ws := nullif(p_fields ->> 'workspace_id', '');
  if ws is not null and not exists (select 1 from clients where id = ws and organization_id = org) then raise exception 'cliente_desconhecido' using errcode = 'P0002'; end if;
  begin
    insert into agency_costs (organization_id, workspace_id, month, kind, label, amount, currency, allocation, client_ref, created_by, created_label)
    values (org, ws, m, p_fields ->> 'kind', trim(coalesce(p_fields ->> 'label', '')), (p_fields ->> 'amount')::numeric, p_fields ->> 'currency',
            coalesce(nullif(p_fields ->> 'allocation', ''), case when ws is null then 'igual' else 'direto' end), p_client_ref, uid, (select email from auth.users where id = uid))
    returning * into r;
  exception
    when check_violation or not_null_violation then
      raise exception 'custo_invalido' using errcode = '22023', detail = 'Indica tipo, descrição (2 a 120 caracteres), valor e moeda. Custo de um cliente é direto; da agência reparte-se por igual ou por vídeos.';
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'custo_invalido' using errcode = '22023', detail = 'Valor inválido.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', r.created_label, org, ws, 'biz.cost_saved', 'agency_cost', r.id::text, null, to_jsonb(r) - 'created_by');
  return public.biz_costs(m);
end $$;

create or replace function public.biz_cost_void(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._biz_require('contracts.manage', 'biz.cost_void'); uid uuid := auth.uid(); old agency_costs; r agency_costs;
begin
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'motivo_obrigatorio' using errcode = '22023'; end if;
  select * into old from agency_costs where id = p_id and organization_id = org for update;
  if old.id is null then raise exception 'custo_nao_encontrado' using errcode = 'P0002'; end if;
  if old.voided_at is not null then return public.biz_costs(old.month); end if;
  update agency_costs set voided_at = now(), voided_by = uid, void_reason = left(trim(p_reason), 300) where id = p_id returning * into r;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', (select email from auth.users where id = uid), org, r.workspace_id, 'biz.cost_voided', 'agency_cost', r.id::text,
          to_jsonb(old) - 'created_by', to_jsonb(r) - 'created_by');
  return public.biz_costs(r.month);
end $$;

revoke all on function public.biz_overview(date, text), public.biz_contracts(), public.biz_contract_history(text), public.biz_contract_save(text, jsonb, int),
  public.biz_fx_save(numeric, date, text), public.biz_costs(date), public.biz_cost_save(jsonb, uuid), public.biz_cost_void(uuid, text) from public, anon;
grant execute on function public.biz_overview(date, text), public.biz_contracts(), public.biz_contract_history(text), public.biz_contract_save(text, jsonb, int),
  public.biz_fx_save(numeric, date, text), public.biz_costs(date), public.biz_cost_save(jsonb, uuid), public.biz_cost_void(uuid, text) to authenticated;

/* Rollback (compatível, nada existente depende disto):
drop function public.biz_cost_void(uuid, text), public.biz_cost_save(jsonb, uuid), public.biz_costs(date), public.biz_fx_save(numeric, date, text),
  public.biz_contract_save(text, jsonb, int), public.biz_contract_history(text), public.biz_contracts(), public.biz_overview(date, text),
  public._biz_ai_trend(text), public._biz_fin(text, date, text, numeric, numeric), public._biz_ops(text, date, text[]), public._biz_stalled(text),
  public._biz_published(text, timestamptz, timestamptz), public._biz_first_pub(text), public._biz_is_client_actor(text, text, uuid),
  public._biz_monthly(client_contracts, date), public._biz_contract_at(text, date), public._biz_month(date), public._biz_conv(numeric, text, text, numeric),
  public._biz_require(text, text), public._biz_pt(numeric), public._biz_org(uuid);
delete from feature_flags where key = 'biz.view'; delete from feature_flag_defs where key = 'biz.view';
delete from role_capabilities where capability in ('biz.read', 'biz.finance', 'contracts.manage');
-- contract posterior (destrutivo, só depois de backup): drop table public.biz_metrics, public.agency_costs, public.fx_rates, public.client_contracts;
--   drop function public.agency_costs_guard(); delete from capabilities where key in ('biz.read', 'biz.finance', 'contracts.manage');
*/
