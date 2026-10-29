-- W7 · Experiências de hooks e formatos (FR-17-11), "repetir vencedor" (FR-17-12) e learning loop (SCALE-06).
-- Expand: 1 flag, 2 tabelas fechadas à API e funções novas. Lê o centro de desempenho (_perf_rows, mesmo índice
-- normalizado por conta e idade, ADR-0033) só para leitura: nada aqui muda perf_*, publication_lineage nem o motor.
-- Regras (ADR-0037):
--  * Os resultados calculam-se sempre a partir das publicações reais; nunca se inventa nem interpola um número.
--  * Variante com menos publicações com índice do que o mínimo da experiência = "amostra insuficiente": não há líder.
--  * O critério de decisão compara medianas do índice; é observacional e nunca se apresenta como causa.
--  * Hipótese, variantes, contas, janela e critério ficam fechados quando a experiência começa (não se mudam as regras
--    depois de ver os dados). Concluir guarda uma fotografia dos resultados como evidência.
--  * Repetir vencedor cria um guião em rascunho ligado à publicação de origem; segue a aprovação editorial de sempre e
--    nunca publica sozinho. Recomendações são só leitura: nada muda estratégia, permissões ou publicação (AGENTS §7).
-- Rollback no fim.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('learn.experiments', 'Experiências, vencedores e recomendações', 'Aprendizagem', 'ws', 'owner',
   'Experiências de hooks e formatos com hipótese, variantes, contas, janela e critério; repetir vencedor como proposta em rascunho; recomendações com evidência e limitações (FR-17-11, FR-17-12, SCALE-06).')
on conflict (key) do nothing;

create table if not exists public.learn_experiments (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  title text not null check (char_length(btrim(title)) between 3 and 120),
  hypothesis text not null check (char_length(btrim(hypothesis)) between 10 and 1000),
  dimension text not null check (dimension in ('hook_mechanism', 'hook_index', 'formato', 'edit_style_key')),
  variants jsonb not null,
  accounts text[] not null check (cardinality(accounts) between 1 and 20),
  window_start date not null,
  window_end date not null,
  age text not null default '72h' check (age in ('24h', '72h', '7d')),
  min_per_variant int not null default 10 check (min_per_variant between 3 and 500),
  decision_ratio numeric not null default 1.2 check (decision_ratio between 1.05 and 5),
  decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  include_external boolean not null default false,
  status text not null default 'rascunho' check (status in ('rascunho', 'a_decorrer', 'concluida', 'cancelada')),
  outcome text check (outcome is null or outcome in ('confirmada', 'refutada', 'inconclusiva')),
  conclusion text check (conclusion is null or char_length(conclusion) <= 2000),
  lever text check (lever is null or char_length(lever) <= 200),
  result_snapshot jsonb,
  concluded_at timestamptz,
  concluded_by uuid references auth.users(id) on delete set null,
  concluded_label text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  updated_at timestamptz not null default now(),
  check (window_end >= window_start and window_end <= window_start + 180),
  check ((status = 'concluida') = (outcome is not null))
);
create index if not exists learn_experiments_ws on public.learn_experiments (workspace_id, created_at desc);

-- Proposta "repetir vencedor": liga o guião novo (rascunho) à publicação e ao guião de origem.
create table if not exists public.learn_repeat_links (
  id bigint generated always as identity primary key,
  workspace_id text not null references public.clients(id),
  new_content_id text not null references public.guioes(id) on delete restrict,
  source_content_id text not null references public.guioes(id) on delete restrict,
  source_reel_id text not null,
  source_account_id text not null references public.accounts(id),
  source_lineage_id bigint references public.publication_lineage(id),
  source_idx numeric not null,
  source_age text not null,
  kind text not null check (kind in ('continuacao', 'variacao')),
  note text check (note is null or char_length(note) <= 1000),
  client_ref uuid,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  unique (new_content_id)
);
create unique index if not exists learn_repeat_links_ref on public.learn_repeat_links (workspace_id, client_ref) where client_ref is not null;
create index if not exists learn_repeat_links_source on public.learn_repeat_links (workspace_id, source_reel_id);
drop trigger if exists learn_repeat_links_immutable on public.learn_repeat_links;
create trigger learn_repeat_links_immutable before update or delete on public.learn_repeat_links for each row execute function public.content_append_only();

alter table public.learn_experiments enable row level security;
alter table public.learn_repeat_links enable row level security;
revoke all on public.learn_experiments, public.learn_repeat_links from anon, authenticated;   -- só pelas RPCs

-- Limiares num só sítio, devolvidos à UI para os explicar. [pressuposto] a calibrar com dados próprios.
create or replace function public._learn_params() returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'winner_idx', 1.5,        -- vencedor: índice às 72 h ≥ 1,5× a mediana da própria conta
    'winner_age', '72h',
    'winner_days', 90,        -- só publicações dos últimos 90 dias
    'lever_up', 1.2,          -- alavanca a recomendar: índice mediano ≥ 1,2 com amostra mínima (PERF-07)
    'lever_down', 0.8)        -- alavanca a evitar: índice mediano < 0,8 com amostra mínima
$$;

-- Validação das variantes: 2 a 6, chaves A-F únicas, valor obrigatório e único.
create or replace function public._learn_variants_valid(p_dim text, p jsonb) returns jsonb
language plpgsql immutable as $$
declare v jsonb; keys text[] := '{}'; vals text[] := '{}'; k text; val text;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) not between 2 and 6 then
    raise exception 'variantes_invalidas' using errcode = '22023', detail = 'Uma experiência tem de 2 a 6 variantes.'; end if;
  for v in select * from jsonb_array_elements(p) loop
    k := upper(btrim(coalesce(v->>'key', ''))); val := btrim(coalesce(v->>'value', ''));
    if k !~ '^[A-F]$' or k = any (keys) then raise exception 'variantes_invalidas' using errcode = '22023', detail = 'Cada variante tem uma letra de A a F, sem repetir.'; end if;
    if val = '' or char_length(val) > 100 or val = any (vals) then
      raise exception 'variantes_invalidas' using errcode = '22023', detail = 'Cada variante tem um valor próprio (até 100 caracteres).'; end if;
    if p_dim = 'hook_index' and val !~ '^[0-9]$' then raise exception 'variantes_invalidas' using errcode = '22023', detail = 'Hook: 1, 2, 3...'; end if;
    if p_dim = 'hook_mechanism' and val not in ('contra', 'numero', 'ego', 'confissao', 'segredo', 'pergunta') then
      raise exception 'variantes_invalidas' using errcode = '22023', detail = 'Mecanismos: contra, numero, ego, confissao, segredo, pergunta.'; end if;
    keys := keys || k; vals := vals || val;
  end loop;
  return (select jsonb_agg(jsonb_build_object('key', upper(btrim(x->>'key')), 'value', btrim(x->>'value'),
                                              'label', coalesce(nullif(left(btrim(x->>'label'), 80), ''), btrim(x->>'value'))) order by upper(btrim(x->>'key')))
          from jsonb_array_elements(p) x);
end $$;

-- Resultados de uma experiência a partir do centro de desempenho (mesmo índice, mesma idade, mesma conta).
create or replace function public._learn_exp_results(e learn_experiments) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; f timestamptz; t timestamptz; res jsonb; vs jsonb; v_lead jsonb; v_second jsonb; all_ok boolean; ratio numeric; warns jsonb := '[]'; w record;
        lin numeric;
begin
  select coalesce(timezone, 'Asia/Dubai') into tz from clients where id = e.workspace_id;
  f := e.window_start::timestamp at time zone tz;
  t := (e.window_end + 1)::timestamp at time zone tz;
  with rows as (
      select x j, (x->'snapshots'->e.age->>'idx')::numeric idx, x->>e.dimension val
      from public._perf_rows(e.workspace_id) x
      where x->>'account_id' = any (e.accounts)
        and (x->>'published_at')::timestamptz >= f and (x->>'published_at')::timestamptz < t
        and (e.include_external or x->>'origin' = 'sistema')),
    var as (select v->>'key' k, v->>'value' val, v->>'label' label, ord from jsonb_array_elements(e.variants) with ordinality o(v, ord)),
    agg as (
      select var.k, var.val, var.label, var.ord,
        count(r.j) n_pubs, count(r.idx) n,
        percentile_cont(0.5) within group (order by r.idx) med, max(r.idx) best, min(r.idx) worst,
        count(distinct r.j->>'account_id') filter (where r.idx is not null) accounts,
        count(r.j) filter (where r.j->>'lineage_mode' = 'inferida') inferred,
        coalesce(jsonb_agg(jsonb_build_object('reel_id', r.j->>'reel_id', 'handle', r.j->>'handle', 'platform', r.j->>'platform', 'url', r.j->>'url',
                   'title', r.j->>'title', 'idx', r.idx, 'published_at', r.j->>'published_at', 'content_id', r.j->>'content_id')
                 order by r.idx desc nulls last) filter (where r.j is not null), '[]') items
      from var left join rows r on r.val = var.val
      group by var.k, var.val, var.label, var.ord),
    byacc as (
      select acc, max(handle) handle, max(platform) platform, jsonb_object_agg(k, jsonb_build_object('n', n, 'median', med)) per
      from (select r.j->>'account_id' acc, max(r.j->>'handle') handle, max(r.j->>'platform') platform, var.k,
                   count(r.idx) n, round(percentile_cont(0.5) within group (order by r.idx)::numeric, 2) med
            from rows r join var on r.val = var.val group by r.j->>'account_id', var.k) z
      group by acc)
  select jsonb_build_object(
      'variants', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'value', val, 'label', label, 'n_pubs', n_pubs, 'n', n,
          'median', round(med::numeric, 2), 'best', best, 'worst', worst, 'accounts', accounts, 'inferred', inferred,
          'sufficient', n >= e.min_per_variant, 'items', (select coalesce(jsonb_agg(i), '[]') from (select i from jsonb_array_elements(items) i limit 20) z))
          order by ord) from agg), '[]'),
      'by_account', coalesce((select jsonb_agg(jsonb_build_object('account_id', acc, 'handle', handle, 'platform', platform, 'per', per) order by platform, handle) from byacc), '[]'),
      'matched', (select count(*) from rows where val in (select val from var)),
      'unmatched', (select count(*) from rows where val is null or val not in (select val from var)))
  into res;
  vs := res->'variants';
  all_ok := not exists (select 1 from jsonb_array_elements(vs) v where not (v->>'sufficient')::boolean);
  for w in select v from jsonb_array_elements(vs) v where not (v->>'sufficient')::boolean loop
    warns := warns || jsonb_build_array(format('Amostra insuficiente na variante %s: %s de %s publicações com índice.', w.v->>'key', w.v->>'n', e.min_per_variant));
  end loop;
  select v into v_lead from jsonb_array_elements(vs) v where v->>'median' is not null order by (v->>'median')::numeric desc limit 1;
  select v into v_second from jsonb_array_elements(vs) v where v->>'median' is not null and v->>'key' <> v_lead->>'key' order by (v->>'median')::numeric desc limit 1;
  if all_ok and v_lead is not null and v_second is not null and (v_second->>'median')::numeric > 0 then
    ratio := round((v_lead->>'median')::numeric / (v_second->>'median')::numeric, 2);
  end if;
  lin := (select case when sum((v->>'n_pubs')::int) > 0 then round(sum((v->>'inferred')::int)::numeric / sum((v->>'n_pubs')::int), 2) end from jsonb_array_elements(vs) v);
  if lin is not null and lin > 0 then
    warns := warns || jsonb_build_array(format('%s%% das publicações têm linhagem inferida (etiquetas deduzidas, não gravadas).', round(lin * 100)));
  end if;
  if now() < t + make_interval(secs => public._perf_age_seconds(e.age)) then
    warns := warns || jsonb_build_array('A janela de medição ainda não fechou: as publicações mais recentes ainda não têm fotografia nesta idade.');
  end if;
  return res || jsonb_build_object(
    'computed_at', now(), 'sufficient', all_ok,
    'leader', case when all_ok then v_lead->>'key' end,
    'ratio', ratio,
    'criterion_met', case when ratio is not null then ratio >= e.decision_ratio end,
    'warnings', warns,
    'inferred_share', lin,
    'note', 'Comparação observacional entre publicações reais: mostra associação, não prova que a variante causou a diferença.');
end $$;

create or replace function public._learn_exp_json(e learn_experiments, p_with_results boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', e.id, 'title', e.title, 'hypothesis', e.hypothesis, 'dimension', e.dimension, 'variants', e.variants,
    'accounts', to_jsonb(e.accounts), 'window_start', e.window_start, 'window_end', e.window_end, 'age', e.age,
    'min_per_variant', e.min_per_variant, 'decision_ratio', e.decision_ratio, 'decision_note', e.decision_note, 'include_external', e.include_external,
    'status', e.status, 'outcome', e.outcome, 'conclusion', e.conclusion, 'lever', e.lever, 'concluded_at', e.concluded_at,
    'concluded_label', e.concluded_label, 'created_at', e.created_at, 'created_label', e.created_label, 'updated_at', e.updated_at,
    'results', case when e.status = 'concluida' then e.result_snapshot when p_with_results and e.status = 'a_decorrer' then public._learn_exp_results(e) end)
$$;

create or replace function public.learn_experiments_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.experiments');
  return jsonb_build_object(
    'can_manage', public.ws_can('learn.manage', p_ws, p_token),
    'params', public._perf_params() || public._learn_params(),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'platform', a.platform, 'handle', a.handle) order by a.platform, a.handle)
                          from accounts a where a.client_id = p_ws and a.role = 'client'), '[]'),
    'experiments', coalesce((select jsonb_agg(public._learn_exp_json(e, false) order by (e.status in ('rascunho', 'a_decorrer')) desc, e.created_at desc)
                             from learn_experiments e where e.workspace_id = p_ws), '[]'));
end $$;

create or replace function public.learn_experiment_get(p_ws text, p_id uuid, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e learn_experiments;
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.experiment');
  select * into e from learn_experiments where id = p_id and workspace_id = p_ws;
  if e.id is null then raise exception 'experiencia_nao_encontrada' using errcode = 'P0002'; end if;
  -- um rascunho também mostra o que já haveria com as regras atuais (pré-visualização, nunca guardada)
  return public._learn_exp_json(e, true) || case when e.status = 'rascunho' then jsonb_build_object('preview', public._learn_exp_results(e)) else '{}' end;
end $$;

-- Criar (p_id nulo) ou mudar um rascunho. Depois de começar as regras não mudam.
create or replace function public.learn_experiment_save(p_ws text, p_id uuid, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); old learn_experiments; e learn_experiments; k text; vars jsonb; accs text[]; dim text;
begin
  perform public._learn_require('learn.experiments', 'learn.manage', p_ws, p_token, 'learn.experiment_save');
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campos_invalidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('title', 'hypothesis', 'dimension', 'variants', 'accounts', 'window_start', 'window_end', 'age', 'min_per_variant',
                 'decision_ratio', 'decision_note', 'include_external') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k); end if;
  end loop;
  if p_id is not null then
    select * into old from learn_experiments where id = p_id and workspace_id = p_ws for update;
    if old.id is null then raise exception 'experiencia_nao_encontrada' using errcode = 'P0002'; end if;
    if old.status <> 'rascunho' then
      raise exception 'experiencia_fechada' using errcode = '22023', detail = 'Depois de começar, a hipótese, as variantes e o critério já não mudam.'; end if;
  end if;
  dim := coalesce(p_fields->>'dimension', old.dimension);
  vars := case when p_fields ? 'variants' or old.id is null then public._learn_variants_valid(dim, p_fields->'variants') else old.variants end;
  if p_fields ? 'dimension' and not p_fields ? 'variants' and old.id is not null then vars := public._learn_variants_valid(dim, old.variants); end if;
  if p_fields ? 'accounts' then
    if jsonb_typeof(p_fields->'accounts') <> 'array' then raise exception 'contas_invalidas' using errcode = '22023'; end if;
    accs := array(select distinct x from jsonb_array_elements_text(p_fields->'accounts') x order by 1);
    if exists (select 1 from unnest(accs) x where not exists (select 1 from accounts c where c.id = x and c.client_id = p_ws and c.role = 'client')) then
      raise exception 'contas_invalidas' using errcode = '22023', detail = 'Só contas deste cliente.'; end if;
  end if;
  begin
    if old.id is null then
      insert into learn_experiments (workspace_id, title, hypothesis, dimension, variants, accounts, window_start, window_end, age, min_per_variant,
                                     decision_ratio, decision_note, include_external, created_by, created_label)
      values (p_ws, btrim(coalesce(p_fields->>'title', '')), btrim(coalesce(p_fields->>'hypothesis', '')), dim, vars, coalesce(accs, '{}'),
              (p_fields->>'window_start')::date, (p_fields->>'window_end')::date, coalesce(p_fields->>'age', '72h'),
              coalesce((p_fields->>'min_per_variant')::int, 10), coalesce((p_fields->>'decision_ratio')::numeric, 1.2),
              nullif(btrim(p_fields->>'decision_note'), ''), coalesce((p_fields->>'include_external')::boolean, false), (a->>'uid')::uuid, a->>'label')
      returning * into e;
    else
      update learn_experiments set
        title = coalesce(nullif(btrim(p_fields->>'title'), ''), title), hypothesis = coalesce(nullif(btrim(p_fields->>'hypothesis'), ''), hypothesis),
        dimension = dim, variants = vars, accounts = coalesce(accs, accounts),
        window_start = coalesce((p_fields->>'window_start')::date, window_start), window_end = coalesce((p_fields->>'window_end')::date, window_end),
        age = coalesce(p_fields->>'age', age), min_per_variant = coalesce((p_fields->>'min_per_variant')::int, min_per_variant),
        decision_ratio = coalesce((p_fields->>'decision_ratio')::numeric, decision_ratio),
        decision_note = case when p_fields ? 'decision_note' then nullif(btrim(p_fields->>'decision_note'), '') else decision_note end,
        include_external = coalesce((p_fields->>'include_external')::boolean, include_external), updated_at = now()
      where id = p_id returning * into e;
    end if;
  exception
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'experiencia_invalida' using errcode = '22023',
        detail = 'Título (3 a 120), hipótese (10 a 1000), pelo menos uma conta, janela com início e fim (até 180 dias), idade 24h/72h/7d, mínimo 3 a 500 por variante, critério entre 1,05 e 5.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when old.id is null then 'learn.experiment_created' else 'learn.experiment_updated' end,
          'learn_experiment', e.id::text, to_jsonb(old) - 'result_snapshot', to_jsonb(e) - 'result_snapshot');
  return public._learn_exp_json(e, false);
end $$;

-- Estados: start (rascunho → a_decorrer), conclude (a_decorrer → concluida, com fotografia), cancel.
create or replace function public.learn_experiment_act(p_ws text, p_id uuid, p_action text, p_fields jsonb default '{}', p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); old learn_experiments; e learn_experiments; snap jsonb; oc text; f jsonb := coalesce(p_fields, '{}');
begin
  perform public._learn_require('learn.experiments', 'learn.manage', p_ws, p_token, 'learn.experiment_act');
  select * into old from learn_experiments where id = p_id and workspace_id = p_ws for update;
  if old.id is null then raise exception 'experiencia_nao_encontrada' using errcode = 'P0002'; end if;
  if p_action = 'start' then
    if old.status <> 'rascunho' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    update learn_experiments set status = 'a_decorrer', updated_at = now() where id = p_id returning * into e;
  elsif p_action = 'conclude' then
    if old.status <> 'a_decorrer' then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    oc := f->>'outcome';
    if oc is null or oc not in ('confirmada', 'refutada', 'inconclusiva') then
      raise exception 'resultado_invalido' using errcode = '22023', detail = 'Resultado: confirmada, refutada ou inconclusiva.'; end if;
    if char_length(btrim(coalesce(f->>'conclusion', ''))) < 10 then
      raise exception 'conclusao_obrigatoria' using errcode = '22023', detail = 'Escreve a conclusão (pelo menos 10 caracteres).'; end if;
    snap := public._learn_exp_results(old);
    -- sem amostra suficiente ou sem critério cumprido não se declara "confirmada"
    if oc = 'confirmada' and not coalesce((snap->>'criterion_met')::boolean, false) then
      raise exception 'criterio_nao_cumprido' using errcode = '22023',
        detail = 'Só se confirma com amostra suficiente em todas as variantes e o critério de decisão cumprido. Conclui como inconclusiva.'; end if;
    update learn_experiments set status = 'concluida', outcome = oc, conclusion = left(btrim(f->>'conclusion'), 2000),
      lever = nullif(left(btrim(coalesce(f->>'lever', '')), 200), ''), result_snapshot = snap,
      concluded_at = now(), concluded_by = (a->>'uid')::uuid, concluded_label = a->>'label', updated_at = now()
    where id = p_id returning * into e;
  elsif p_action = 'cancel' then
    if old.status not in ('rascunho', 'a_decorrer') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
    update learn_experiments set status = 'cancelada', updated_at = now() where id = p_id returning * into e;
  else
    raise exception 'acao_invalida' using errcode = '22023';
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'learn.experiment_' || p_action, 'learn_experiment', e.id::text,
          jsonb_build_object('status', old.status), jsonb_build_object('status', e.status, 'outcome', e.outcome, 'lever', e.lever));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'learn.experiment_' || p_action, 'learn_experiment', e.id::text, jsonb_build_object('status', e.status, 'outcome', e.outcome));
  return public._learn_exp_json(e, true);
end $$;

-- Vencedores (FR-17-12): publicações com índice ≥ limiar à idade de vencedor, com as propostas já feitas a partir delas.
create or replace function public.learn_winners(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prm jsonb := public._learn_params();
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.winners');
  return jsonb_build_object('params', prm, 'can_create', public.ws_can('scripts.create', p_ws, p_token),
    'items', coalesce((select jsonb_agg(w order by (w->>'idx')::numeric desc) from (
        select jsonb_build_object('reel_id', x->>'reel_id', 'account_id', x->>'account_id', 'handle', x->>'handle', 'platform', x->>'platform',
          'url', x->>'url', 'title', x->>'title', 'published_at', x->>'published_at', 'origin', x->>'origin', 'lineage_mode', x->>'lineage_mode',
          'idx', (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric, 'content_id', x->>'content_id', 'hook_text', x->>'hook_text', 'formato', x->>'formato',
          'repeats', coalesce((select jsonb_agg(jsonb_build_object('content_id', l.new_content_id, 'kind', l.kind, 'created_at', l.created_at,
                                   'status', (select editorial_status from guioes where id = l.new_content_id)) order by l.created_at desc)
                               from learn_repeat_links l where l.workspace_id = p_ws and l.source_reel_id = x->>'reel_id'), '[]')) w
        from public._perf_rows(p_ws) x
        where (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric >= (prm->>'winner_idx')::numeric
          and (x->>'published_at')::timestamptz >= now() - make_interval(days => (prm->>'winner_days')::int)
        order by (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric desc limit 50) z), '[]'));
end $$;

-- Repetir vencedor: cria um guião em rascunho a partir do guião da publicação vencedora, ligado a ela. Idempotente por client_ref.
create or replace function public.learn_repeat_winner(p_ws text, p_reel_id text, p_kind text, p_note text default null,
                                                      p_client_ref uuid default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); prm jsonb := public._learn_params(); x jsonb; src guioes; g guioes; l learn_repeat_links;
        idx numeric; tz text; lid bigint; nt text;
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.repeat_winner');
  perform public._content_require('scripts.create', p_ws, p_token, 'learn.repeat_winner', p_reel_id);
  if p_kind is null or p_kind not in ('continuacao', 'variacao') then raise exception 'tipo_invalido' using errcode = '22023', detail = 'Continuação ou variação.'; end if;
  if p_client_ref is not null then
    select * into l from learn_repeat_links where workspace_id = p_ws and client_ref = p_client_ref;
    if l.id is not null then return jsonb_build_object('content_id', l.new_content_id, 'created', false); end if;
  end if;
  select r into x from public._perf_rows(p_ws) r where r->>'reel_id' = p_reel_id limit 1;
  if x is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  idx := (x->'snapshots'->(prm->>'winner_age')->>'idx')::numeric;
  if idx is null or idx < (prm->>'winner_idx')::numeric then
    raise exception 'nao_e_vencedor' using errcode = '22023',
      detail = format('Só publicações com índice às %s de pelo menos %s.', prm->>'winner_age', replace((prm->>'winner_idx'), '.', ',')); end if;
  select * into src from guioes where id = x->>'content_id' and client_id = p_ws;
  if src.id is null then
    raise exception 'sem_guiao_de_origem' using errcode = '22023', detail = 'Esta publicação não está ligada a um guião deste cliente: liga-a primeiro no centro de desempenho.'; end if;
  select coalesce(timezone, 'Asia/Dubai') into tz from clients where id = p_ws;
  nt := format('%s da publicação %s (@%s, índice %s às %s). Proposta: rever antes de submeter.',
               case when p_kind = 'continuacao' then 'Continuação' else 'Variação' end, p_reel_id, x->>'handle', idx, prm->>'winner_age')
        || coalesce(E'\n' || nullif(left(btrim(p_note), 1000), ''), '') || coalesce(E'\n\nNotas do original: ' || src.notas, '');
  g := public.content_create(p_ws, jsonb_build_object('date', (now() at time zone tz)::date, 'formato', src.formato, 'tema', src.tema, 'hooks', src.hooks,
         'corpo', src.corpo, 'cta', src.cta, 'notas', left(nt, 4000), 'origem', 'repetir:' || p_reel_id), p_token);
  select id into lid from publication_lineage where workspace_id = p_ws and account_id = x->>'account_id' and external_id = p_reel_id;
  insert into learn_repeat_links (workspace_id, new_content_id, source_content_id, source_reel_id, source_account_id, source_lineage_id, source_idx,
                                  source_age, kind, note, client_ref, created_by, created_label)
  values (p_ws, g.id, src.id, p_reel_id, x->>'account_id', lid, idx, prm->>'winner_age', p_kind, nullif(left(btrim(p_note), 1000), ''), p_client_ref,
          (a->>'uid')::uuid, a->>'label');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'learn.repeat_proposed', 'guiao', g.id,
          jsonb_build_object('source_reel_id', p_reel_id, 'source_content_id', src.id, 'idx', idx, 'kind', p_kind));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'learn.repeat_proposed', 'content', g.id, jsonb_build_object('source_reel_id', p_reel_id, 'source_content_id', src.id, 'kind', p_kind));
  return jsonb_build_object('content_id', g.id, 'date', g.date, 'created', true, 'editorial_status', g.editorial_status);
end $$;

-- Learning loop (SCALE-06): recomendações com evidência e limitações. Só leitura: nada se aplica sozinho.
create or replace function public.learn_recommendations(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prm jsonb := public._learn_params(); lv jsonb; recs jsonb := '[]'; e learn_experiments; r jsonb; tot jsonb; inferred numeric;
begin
  perform public._learn_require('learn.experiments', 'learn.read', p_ws, p_token, 'learn.recommendations');
  for e in select * from learn_experiments where workspace_id = p_ws and status = 'concluida' and outcome in ('confirmada', 'refutada')
           order by concluded_at desc limit 20 loop
    r := e.result_snapshot;
    recs := recs || jsonb_build_array(jsonb_build_object(
      'kind', 'experiencia', 'direction', case when e.outcome = 'confirmada' then 'repetir' else 'rever' end,
      'title', coalesce(e.lever, e.title), 'detail', e.conclusion, 'experiment_id', e.id,
      'evidence', jsonb_build_object('hypothesis', e.hypothesis, 'dimension', e.dimension, 'window_start', e.window_start, 'window_end', e.window_end,
        'age', e.age, 'accounts', to_jsonb(e.accounts), 'leader', r->>'leader', 'ratio', r->'ratio', 'decision_ratio', e.decision_ratio,
        'variants', (select coalesce(jsonb_agg(jsonb_build_object('key', v->>'key', 'label', v->>'label', 'n', v->'n', 'median', v->'median')), '[]')
                     from jsonb_array_elements(r->'variants') v),
        'concluded_at', e.concluded_at, 'concluded_label', e.concluded_label),
      'limitations', jsonb_build_array(r->>'note') || coalesce(r->'warnings', '[]')));
  end loop;
  -- alavancas do centro de desempenho (PERF-07), só para quem também vê o desempenho
  if public.ws_can('analytics.read', p_ws, p_token) and public._flag_on('perf.center', p_ws, p_token) then
    lv := public.perf_levers(p_ws, true, p_token);
    recs := recs || coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'alavanca', 'direction', case when (l->>'idx_median')::numeric >= (prm->>'lever_up')::numeric then 'repetir' else 'evitar' end,
        'title', format('%s: %s', l->>'dimension', l->>'key'),
        'detail', format('Índice mediano %s às 72 h em %s publicações de origem sistema (últimos 90 dias).', l->>'idx_median', l->>'n'),
        'evidence', jsonb_build_object('dimension', l->>'dimension', 'key', l->>'key', 'n', l->'n', 'median', l->'idx_median', 'age', '72h', 'days', 90),
        'limitations', jsonb_build_array('Comparação observacional: outras diferenças entre as publicações podem explicar o resultado.',
                                         'Atributos deduzidos das etiquetas; nas publicações sem linhagem gravada podem estar errados.'))
        order by abs((l->>'idx_median')::numeric - 1) desc)
      from jsonb_array_elements(lv->'levers') l
      where (l->>'shown')::boolean and ((l->>'idx_median')::numeric >= (prm->>'lever_up')::numeric or (l->>'idx_median')::numeric < (prm->>'lever_down')::numeric)), '[]');
  end if;
  select jsonb_build_object('n', count(*), 'inferred', count(*) filter (where x->>'lineage_mode' = 'inferida'))
    into tot from public._perf_rows(p_ws) x;
  inferred := case when (tot->>'n')::int > 0 then round((tot->>'inferred')::numeric / (tot->>'n')::numeric, 2) end;
  return jsonb_build_object('params', prm, 'items', recs,
    'limitations', jsonb_build_array(
      'Nenhuma recomendação muda a estratégia, os prompts, as permissões ou a publicação sozinha: quem decide é uma pessoa (AGENTS §7).',
      'Métricas da recolha por scraping: sem alcance, retenção nem seguidores até as contas estarem ligadas pela API oficial.',
      'O índice compara cada publicação com a mediana da própria conta nos 30 dias anteriores; contas com menos de 5 publicações não têm índice.')
      || case when inferred > 0 then jsonb_build_array(format('%s%% das publicações deste cliente têm linhagem inferida.', round(inferred * 100))) else '[]'::jsonb end);
end $$;

revoke all on function public._learn_params(), public._learn_variants_valid(text, jsonb), public._learn_exp_results(learn_experiments),
  public._learn_exp_json(learn_experiments, boolean) from public, anon, authenticated;
revoke all on function public.learn_experiments_list(text, text), public.learn_experiment_get(text, uuid, text), public.learn_experiment_save(text, uuid, jsonb, text),
  public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_winners(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text),
  public.learn_recommendations(text, text) from public;
grant execute on function public.learn_experiments_list(text, text), public.learn_experiment_get(text, uuid, text), public.learn_experiment_save(text, uuid, jsonb, text),
  public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_winners(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text),
  public.learn_recommendations(text, text) to anon, authenticated;

/* Rollback (compatível: nada do que existia mudou):
   drop function public.learn_recommendations(text, text), public.learn_repeat_winner(text, text, text, text, uuid, text), public.learn_winners(text, text),
     public.learn_experiment_act(text, uuid, text, jsonb, text), public.learn_experiment_save(text, uuid, jsonb, text),
     public.learn_experiment_get(text, uuid, text), public.learn_experiments_list(text, text), public._learn_exp_json(learn_experiments, boolean),
     public._learn_exp_results(learn_experiments), public._learn_variants_valid(text, jsonb), public._learn_params();
   delete from feature_flags where key = 'learn.experiments'; delete from feature_flag_defs where key = 'learn.experiments';
-- contract posterior (só depois de exportar): drop table public.learn_repeat_links, public.learn_experiments;
-- os guiões criados por "repetir vencedor" ficam (origem 'repetir:<reel>'), são conteúdo normal. */
