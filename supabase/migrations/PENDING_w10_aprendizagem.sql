-- W10-19 · Aprendizagem contínua, parte 1 (PRD §46.2 LRN-01, LRN-02, LRN-03; restrições de LRN-04..07). ADR-0069.
-- Expand (só aditivo, compatível com o código em main): 3 capacidades, 2 flags, 3 tabelas fechadas à API, um tipo novo
-- de execução ('lesson_editor') e funções novas. Não reescreve nenhuma função existente: content_transition,
-- content_transition_reasoned, content_save, worker_claim e worker_finish ficam iguais. Quem decide como hoje (cartão
-- sem flag, código de equipa, guiao_update, motor) continua igual; o par motor → aprovada só é guardado pelas funções novas.
--
-- LRN-01 · Motivo em cada edição: lrn_edit_signals guarda, por guião gerado pelo motor, o par (versão do motor → versão
--   humana), a distância de edição em palavras, os chips (taxonomia FR-17-10 do cliente + categorias fixas do PRD) e o
--   texto livre. Decisão do PRD: motivo opcional, obrigatório quando a edição muda mais de ~30% do texto; aprovar sem
--   editar conta como sinal positivo. Guardar (autosave) nunca é bloqueado: a regra dos 30% só se aplica ao aprovar.
-- LRN-02 · Editor de lições: o motor recebe os pares do dia (worker_lesson_pairs) e grava propostas com evidência
--   (worker_lesson_save, idempotente por execução e posição). O número de edições e os exemplos são calculados aqui a
--   partir dos ids enviados: o texto do motor nunca é evidência.
-- LRN-03 · Aprovação: lições propostas → aprovadas/rejeitadas por quem tem a capacidade. Aprovar, retirar ou voltar atrás
--   cria uma nova versão imutável do conjunto de lições (lrn_lesson_versions) que o motor lê (LRN-05, worker_lessons).
-- LRN-04 · Dois níveis: cliente (workspace) e agência (organização). As lições da agência guardam só a regra (texto e
--   categoria), nunca guiões, números ou ids de outro cliente; aprovam-se com uma capacidade da agência (scope org) que a
--   equipa de um cliente nunca tem. Em conflito prevalece a lição do cliente (worker_lessons devolve a precedência).
-- LRN-07 · Nada de treino de modelo: lições e exemplos vão no prompt.

-- ───────────── capacidades e flags ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('learn.lessons.approve', 'Aprendizagem', 'A', array['ws'], 'ativo', 'Aprovar, editar e rejeitar lições do motor neste cliente'),
  ('learn.lessons.agency', 'Aprendizagem', 'A', array['org'], 'ativo', 'Aprovar lições gerais da agência (herdadas por todos os clientes)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, risk = excluded.risk, scopes = excluded.scopes;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'learn.lessons.approve'), ('ws', 'workspace_admin', 'learn.lessons.approve'), ('ws', 'manager', 'learn.lessons.approve'),
  ('org', 'agency_owner', 'learn.lessons.agency'), ('org', 'agency_admin', 'learn.lessons.agency')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('learn.edits', 'Motivo em cada edição', 'Aprendizagem', 'ws', 'owner',
   'Ao concluir uma edição, aprovar, pedir alterações ou rejeitar um guião do motor, chips de um toque com o motivo; obrigatório ao aprovar quando a edição muda mais de 30% do texto (LRN-01).'),
  ('learn.lessons', 'Lições do motor', 'Aprendizagem', 'ws', 'owner',
   'Aprendizagem → Lições: o Editor de lições propõe lições diárias a partir das edições e quem tem a capacidade aprova, edita ou rejeita (LRN-02, LRN-03).')
on conflict (key) do nothing;

-- ───────────── tipo de execução novo (reconstruído a partir da definição atual) ─────────────
do $$
declare def text; kinds text[];
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.agent_jobs'::regclass and conname = 'agent_jobs_kind_check';
  if def is not null and position('''lesson_editor''' in def) > 0 then return; end if;
  kinds := coalesce(array(select m[1] from regexp_matches(coalesce(def, ''), '''([a-z_]+)''', 'g') m), '{}') || array['lesson_editor'];
  alter table public.agent_jobs drop constraint if exists agent_jobs_kind_check;
  execute format('alter table public.agent_jobs add constraint agent_jobs_kind_check check (kind in (%s))',
                 (select string_agg(quote_literal(k), ', ') from unnest(kinds) k));
end $$;

-- ───────────── LRN-01: sinais de edição ─────────────
create table if not exists public.lrn_edit_signals (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  kind text not null check (kind in ('edit', 'approved', 'approved_unedited', 'changes_requested', 'rejected')),
  engine_version_id uuid not null references public.content_versions(id),
  version_id uuid not null references public.content_versions(id),
  codes text[] not null default '{}' check (cardinality(codes) <= 8),
  note text check (note is null or char_length(note) between 1 and 500),
  edit_ratio numeric(4,3) not null check (edit_ratio between 0 and 1),
  transition_id bigint references public.content_transitions(id),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('user', 'legacy_code')),
  actor_label text,
  created_at timestamptz not null default now()
);
create index if not exists lrn_edit_signals_ws on public.lrn_edit_signals (workspace_id, created_at);
create index if not exists lrn_edit_signals_content on public.lrn_edit_signals (content_id, created_at);
-- uma edição com motivo por versão (repetir devolve a que já existe)
create unique index if not exists lrn_edit_signals_edit_once on public.lrn_edit_signals (content_id, version_id) where kind = 'edit';
drop trigger if exists lrn_edit_signals_immutable on public.lrn_edit_signals;
create trigger lrn_edit_signals_immutable before update or delete on public.lrn_edit_signals
  for each row execute function public.content_append_only();
drop trigger if exists lrn_edit_signals_ws on public.lrn_edit_signals;
create trigger lrn_edit_signals_ws before insert on public.lrn_edit_signals
  for each row execute function public.content_same_workspace();

-- ───────────── LRN-02/03: lições e versões do conjunto ─────────────
create table if not exists public.lrn_lessons (
  id uuid primary key default gen_random_uuid(),
  level text not null check (level in ('client', 'agency')),
  organization_id uuid not null references public.organizations(id),
  workspace_id text references public.clients(id),
  status text not null default 'proposed' check (status in ('proposed', 'approved', 'rejected')),
  category text not null check (category in ('hook', 'corpo', 'cta', 'facto', 'tom', 'outro')),
  proposed_text text not null check (char_length(btrim(proposed_text)) between 5 and 400),
  text text not null check (char_length(btrim(text)) between 5 and 400),
  rationale text check (rationale is null or char_length(rationale) <= 600),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  source text not null check (source in ('engine', 'promoted')),
  job_id uuid references public.agent_jobs(id),
  slot integer check (slot is null or slot between 1 and 50),
  model text, prompt_version text, agent_version text,
  proposed_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  decided_label text,
  decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  check ((level = 'client') = (workspace_id is not null)),
  check ((source = 'engine') = (job_id is not null and slot is not null)),
  check ((status = 'proposed') = (decided_at is null)),
  unique (job_id, slot)
);
create index if not exists lrn_lessons_ws on public.lrn_lessons (workspace_id, status, proposed_at desc) where level = 'client';
create index if not exists lrn_lessons_org on public.lrn_lessons (organization_id, status, proposed_at desc) where level = 'agency';

-- Uma lição decidida não volta atrás; nível, dono, proposta e evidência nunca mudam.
create or replace function public.lrn_lessons_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'lrn_lessons é só de acrescentar' using errcode = '42501'; end if;
  if (new.level, new.organization_id, new.workspace_id, new.category, new.proposed_text, new.evidence, new.source, new.job_id, new.slot, new.proposed_at)
     is distinct from (old.level, old.organization_id, old.workspace_id, old.category, old.proposed_text, old.evidence, old.source, old.job_id, old.slot, old.proposed_at)
     or old.status <> 'proposed' then
    raise exception 'licao_imutavel' using errcode = '42501', detail = 'Uma lição decidida não se altera.';
  end if;
  return new;
end $$;
drop trigger if exists lrn_lessons_guard on public.lrn_lessons;
create trigger lrn_lessons_guard before update or delete on public.lrn_lessons for each row execute function public.lrn_lessons_guard();

create table if not exists public.lrn_lesson_versions (
  id uuid primary key default gen_random_uuid(),
  level text not null check (level in ('client', 'agency')),
  organization_id uuid not null references public.organizations(id),
  workspace_id text references public.clients(id),
  version_no integer not null check (version_no > 0),
  lessons jsonb not null default '[]'::jsonb check (jsonb_typeof(lessons) = 'array'),
  parent_id uuid references public.lrn_lesson_versions(id),
  change jsonb not null check (jsonb_typeof(change) = 'object'),
  active boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  created_at timestamptz not null default now(),
  check ((level = 'client') = (workspace_id is not null))
);
create unique index if not exists lrn_lesson_versions_no on public.lrn_lesson_versions (organization_id, level, coalesce(workspace_id, ''), version_no);
create unique index if not exists lrn_lesson_versions_active on public.lrn_lesson_versions (organization_id, level, coalesce(workspace_id, '')) where active;

-- Versões imutáveis: só "active" muda (quando outra versão passa a valer).
create or replace function public.lrn_versions_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'lrn_lesson_versions é só de acrescentar' using errcode = '42501'; end if;
  if (new.level, new.organization_id, new.workspace_id, new.version_no, new.lessons, new.parent_id, new.change, new.created_at)
     is distinct from (old.level, old.organization_id, old.workspace_id, old.version_no, old.lessons, old.parent_id, old.change, old.created_at) then
    raise exception 'versao_imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists lrn_versions_guard on public.lrn_lesson_versions;
create trigger lrn_versions_guard before update or delete on public.lrn_lesson_versions for each row execute function public.lrn_versions_guard();

alter table public.lrn_edit_signals enable row level security;
alter table public.lrn_lessons enable row level security;
alter table public.lrn_lesson_versions enable row level security;
revoke all on public.lrn_edit_signals, public.lrn_lessons, public.lrn_lesson_versions from anon, authenticated;   -- só pelas RPCs

-- ───────────── helpers ─────────────
-- Limiar do PRD (LRN-01): acima disto o motivo é obrigatório ao aprovar.
create or replace function public._lrn_threshold() returns numeric language sql immutable as $$ select 0.30::numeric $$;

-- Categorias fixas do PRD (LRN-01), sempre disponíveis; "group" liga cada chip a uma categoria de lição (e ao agente).
create or replace function public._lrn_fixed_codes() returns jsonb language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('code', 'hook_fraco', 'label', 'Hook fraco', 'group', 'hook'),
    jsonb_build_object('code', 'frase_longa', 'label', 'Frase longa', 'group', 'corpo'),
    jsonb_build_object('code', 'nao_soa_cliente', 'label', 'Não soa ao cliente', 'group', 'tom'),
    jsonb_build_object('code', 'pt_br', 'label', 'PT-BR', 'group', 'tom'),
    jsonb_build_object('code', 'factual', 'label', 'Factual', 'group', 'facto'),
    jsonb_build_object('code', 'palavra_proibida', 'label', 'Palavra proibida', 'group', 'tom'),
    jsonb_build_object('code', 'ritmo', 'label', 'Ritmo', 'group', 'corpo'),
    jsonb_build_object('code', 'fecho_fraco', 'label', 'Fecho fraco', 'group', 'cta'))
$$;

-- Grupo de um motivo FR-17-10 do cliente (os da lista sugerida têm grupo; os criados pelo cliente ficam em "outro").
create or replace function public._lrn_rework_group(p_code text) returns text language sql immutable as $$
  select case p_code when 'hook_fraco' then 'hook' when 'factos' then 'facto' when 'risco' then 'facto' when 'voz' then 'tom'
                     when 'estrutura' then 'corpo' when 'duracao' then 'corpo' when 'cta' then 'cta' else 'outro' end
$$;

-- Chips do cliente: fixos do PRD + taxonomia FR-17-10 ativa para guiões (sem repetir códigos).
create or replace function public._lrn_codes(p_ws text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'source', (x->>'sort')::int, x->>'label'), '[]') from (
    select f || jsonb_build_object('source', 'lrn', 'sort', ord) x from jsonb_array_elements(public._lrn_fixed_codes()) with ordinality e(f, ord)
    union all
    select jsonb_build_object('code', r.code, 'label', r.label, 'group', public._lrn_rework_group(r.code), 'source', 'rework', 'sort', r.sort)
      from rework_reasons r
     where r.workspace_id = p_ws and r.active and 'guiao' = any (r.applies_to)
       and not exists (select 1 from jsonb_array_elements(public._lrn_fixed_codes()) f where f->>'code' = r.code)
  ) s
$$;

-- Códigos válidos e limpos (minúsculas, sem repetidos); recusa os que não existem na lista do cliente.
create or replace function public._lrn_clean_codes(p_ws text, p_codes text[]) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare c text[] := coalesce(array(select distinct lower(btrim(x)) from unnest(coalesce(p_codes, '{}')) x where btrim(x) <> ''), '{}'); bad text;
begin
  if cardinality(c) > 8 then raise exception 'motivos_demais' using errcode = '22023', detail = 'Escolhe no máximo 8 motivos.'; end if;
  select x into bad from unnest(c) x where not exists (select 1 from jsonb_array_elements(public._lrn_codes(p_ws)) k where k->>'code' = x) limit 1;
  if bad is not null then raise exception 'motivo_desconhecido' using errcode = '22023', detail = format('O motivo "%s" não existe neste cliente.', bad); end if;
  return c;
end $$;

-- Texto comparável de uma versão: hooks, corpo e CTA (as marcas "## Bloco" contam como texto).
create or replace function public._lrn_text(p_hooks jsonb, p_corpo text, p_cta text) returns text language sql immutable as $$
  select btrim(concat_ws(E'\n',
    (select string_agg(h->>'text', E'\n' order by o) from jsonb_array_elements(case when jsonb_typeof(p_hooks) = 'array' then p_hooks else '[]' end) with ordinality x(h, o)
      where coalesce(h->>'text', '') <> ''),
    p_corpo, p_cta))
$$;

-- Distância de edição em palavras: 1 − LCS / max(n, m). 0 = igual, 1 = tudo novo. Textos enormes: aproximação por multiconjunto.
create or replace function public._lrn_edit_ratio(a text, b text) returns numeric language plpgsql immutable set search_path = public as $$
declare x text[]; y text[]; n int; m int; prev int[]; cur int[]; i int; j int;
begin
  x := case when btrim(coalesce(a, '')) = '' then '{}' else regexp_split_to_array(lower(btrim(a)), '\s+') end;
  y := case when btrim(coalesce(b, '')) = '' then '{}' else regexp_split_to_array(lower(btrim(b)), '\s+') end;
  n := cardinality(x); m := cardinality(y);
  if n = 0 and m = 0 then return 0; end if;
  if n = 0 or m = 0 then return 1; end if;
  if x = y then return 0; end if;
  if n::bigint * m > 360000 then
    return round(1 - (select count(*) from (select unnest(x) intersect all select unnest(y)) s)::numeric / greatest(n, m), 3);
  end if;
  prev := array_fill(0, array[m + 1]);
  for i in 1..n loop
    cur := array_fill(0, array[m + 1]);
    for j in 1..m loop
      if x[i] = y[j] then cur[j + 1] := prev[j] + 1; else cur[j + 1] := greatest(prev[j + 1], cur[j]); end if;
    end loop;
    prev := cur;
  end loop;
  return round(1 - prev[m + 1]::numeric / greatest(n, m), 3);
end $$;

-- Versão do motor de um guião (a primeira gravada pelo motor). Nula = guião escrito à mão (fora de LRN-01).
create or replace function public._lrn_engine_version(p_id text) returns content_versions
language sql stable security definer set search_path = public as $$
  select * from content_versions where content_id = p_id and created_kind = 'engine' order by version_no limit 1
$$;

-- Distância entre a versão do motor e a cópia de trabalho atual.
create or replace function public._lrn_ratio_now(p_g guioes, p_ev content_versions) returns numeric
language sql stable set search_path = public as $$
  select public._lrn_edit_ratio(public._lrn_text(p_ev.hooks, p_ev.corpo, p_ev.cta), public._lrn_text(p_g.hooks, p_g.corpo, p_g.cta))
$$;

create or replace function public._lrn_require_flag(p_flag text, p_ws text, p_token text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._flag_on(p_flag, p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
end $$;

-- ───────────── LRN-01: RPCs dos guiões ─────────────
-- Chips e regra (para o cartão do guião). enabled = flag learn.edits ligada para quem pede.
create or replace function public.lrn_edit_options(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.read', p_ws, p_token, 'lrn.edit_options', p_ws);
  return jsonb_build_object('enabled', public._flag_on('learn.edits', p_ws, p_token), 'threshold', public._lrn_threshold(),
                            'codes', public._lrn_codes(p_ws));
end $$;

-- Quanto a cópia de trabalho mudou em relação ao motor (o cartão decide se pede o motivo antes de aprovar).
create or replace function public.content_edit_ratio(p_id text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g guioes; ev content_versions; r numeric;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'lrn.edit_ratio', g.id);
  ev := public._lrn_engine_version(g.id);
  if ev.id is null then return jsonb_build_object('engine', false, 'ratio', null, 'required', false); end if;
  r := public._lrn_ratio_now(g, ev);
  return jsonb_build_object('engine', true, 'ratio', r, 'required', r > public._lrn_threshold(), 'threshold', public._lrn_threshold(),
    'edits', (select coalesce(jsonb_agg(jsonb_build_object('codes', to_jsonb(s.codes), 'note', s.note, 'at', s.created_at) order by s.created_at), '[]')
                from lrn_edit_signals s where s.content_id = g.id and s.kind = 'edit'
                 and s.created_at > coalesce((select max(t.at) from content_transitions t where t.content_id = g.id and t.kind = 'editorial'
                                               and t.to_status in ('approved','rejected')), '-infinity')));
end $$;

-- Motivo de uma edição, ao concluir (opcional). Fotografa a cópia de trabalho e guarda o par motor → esta versão.
create or replace function public.content_edit_reason(p_id text, p_codes text[], p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb; ev content_versions; v uuid; c text[]; nt text := nullif(btrim(coalesce(p_note, '')), ''); s lrn_edit_signals; r numeric;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.edit', g.client_id, p_token, 'lrn.edit_reason', g.id);
  perform public._lrn_require_flag('learn.edits', g.client_id, p_token);
  if g.editorial_status = 'archived' then raise exception 'arquivado' using errcode = '22023'; end if;
  ev := public._lrn_engine_version(g.id);
  if ev.id is null then raise exception 'guiao_manual' using errcode = '22023', detail = 'Este guião não foi escrito pelo motor.'; end if;
  c := public._lrn_clean_codes(g.client_id, p_codes);
  if cardinality(c) = 0 and nt is null then raise exception 'motivo_vazio' using errcode = '22023', detail = 'Escolhe um motivo ou escreve porquê.'; end if;
  if char_length(nt) > 500 then raise exception 'motivo_longo' using errcode = '22023', detail = 'O motivo tem no máximo 500 caracteres.'; end if;
  a := public._content_actor(p_token);
  r := public._lrn_ratio_now(g, ev);
  if r = 0 then return jsonb_build_object('recorded', false, 'ratio', 0); end if;
  v := public._content_snapshot(g.id, a, null);
  select * into s from lrn_edit_signals where content_id = g.id and version_id = v and kind = 'edit';
  if s.id is null then
    insert into lrn_edit_signals (workspace_id, content_id, kind, engine_version_id, version_id, codes, note, edit_ratio, actor_user_id, actor_kind, actor_label)
    values (g.client_id, g.id, 'edit', ev.id, v, c, nt, r, (a->>'uid')::uuid, a->>'kind', a->>'label')
    returning * into s;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'lrn.edit_reason', 'guiao', g.id,
            jsonb_build_object('signal_id', s.id, 'version_id', v, 'codes', to_jsonb(c), 'ratio', r));
  end if;
  return jsonb_build_object('recorded', true, 'signal_id', s.id, 'ratio', s.edit_ratio);
end $$;

-- Aprovar, pedir alterações ou rejeitar guardando o sinal de aprendizagem na mesma transação. Usa as funções de sempre
-- (content_transition / content_transition_reasoned): mesmas capacidades, mesmo lock, mesma versão presa à decisão.
create or replace function public.content_decide_learned(p_id text, p_to text, p_codes text[] default '{}', p_note text default null,
                                                         p_reason text default null, p_reason_code text default null,
                                                         p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb; ev content_versions; c text[]; nt text := nullif(btrim(coalesce(p_note, '')), ''); r numeric; tid bigint; v uuid; k text;
        sid uuid;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if p_to not in ('approved', 'changes_requested', 'rejected') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
  perform public._content_require(case when p_to = 'approved' then 'scripts.approve' else 'scripts.reject' end, g.client_id, p_token, 'lrn.decide', g.id);
  perform public._lrn_require_flag('learn.edits', g.client_id, p_token);
  c := public._lrn_clean_codes(g.client_id, p_codes);
  if char_length(nt) > 500 then raise exception 'motivo_longo' using errcode = '22023', detail = 'O motivo tem no máximo 500 caracteres.'; end if;
  ev := public._lrn_engine_version(g.id);
  if ev.id is not null then r := public._lrn_ratio_now(g, ev); end if;
  if p_to = 'approved' and r > public._lrn_threshold() and cardinality(c) = 0 and nt is null then
    raise exception 'motivo_obrigatorio' using errcode = '22023',
      detail = format('Mudaste %s%% do texto do motor: diz porquê (um toque chega).', round(r * 100));
  end if;

  if p_to <> 'approved' and nullif(btrim(coalesce(p_reason_code, '')), '') is not null then
    g := public.content_transition_reasoned(p_id, p_to, p_reason, p_reason_code, p_lock, p_token);
  else
    g := public.content_transition(p_id, p_to, p_reason, p_lock, p_token);
  end if;
  if ev.id is null then return g; end if;   -- guião escrito à mão: fora de LRN-01

  a := public._content_actor(p_token);
  select id, version_id into tid, v from content_transitions where content_id = g.id and kind = 'editorial' and to_status = p_to order by id desc limit 1;
  k := case when p_to = 'approved' and r = 0 then 'approved_unedited' else p_to end;
  insert into lrn_edit_signals (workspace_id, content_id, kind, engine_version_id, version_id, codes, note, edit_ratio, transition_id,
                                actor_user_id, actor_kind, actor_label)
  values (g.client_id, g.id, k, ev.id, coalesce(v, g.current_version_id), c,
          coalesce(nt, case when p_to <> 'approved' then left(nullif(btrim(coalesce(p_reason, '')), ''), 500) end),
          coalesce(r, 0), tid, (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning id into sid;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'lrn.decision_signal', 'guiao', g.id,
          jsonb_build_object('signal_id', sid, 'kind', k, 'codes', to_jsonb(c), 'ratio', r, 'no_reason', cardinality(c) = 0 and nt is null));
  return g;
end $$;

-- ───────────── LRN-03: lições ─────────────
create or replace function public._lrn_is_agency_staff(p_org uuid, p_uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid is not null and exists (select 1 from agency_memberships where user_id = p_uid and organization_id = p_org and status = 'active')
$$;

create or replace function public._lrn_lesson_json(l lrn_lessons, p_detail boolean) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', l.id, 'level', l.level, 'status', l.status, 'category', l.category, 'text', l.text,
    'proposed_text', l.proposed_text, 'edited', l.text <> l.proposed_text, 'rationale', l.rationale, 'source', l.source,
    'proposed_at', l.proposed_at, 'decided_at', l.decided_at, 'decided_label', l.decided_label, 'decision_note', l.decision_note,
    'evidence', case when p_detail then l.evidence else jsonb_build_object('edits', l.evidence->'edits') end)
$$;

create or replace function public._lrn_version_json(v lrn_lesson_versions) returns jsonb language sql stable set search_path = public as $$
  select case when v.id is null then null else jsonb_build_object('id', v.id, 'version_no', v.version_no, 'active', v.active, 'lessons', v.lessons,
    'change', v.change, 'created_label', v.created_label, 'created_at', v.created_at) end
$$;

-- Nova versão do conjunto (imutável) e passa a valer; a anterior fica guardada. Serializado por âmbito.
create or replace function public._lrn_new_version(p_level text, p_org uuid, p_ws text, p_lessons jsonb, p_change jsonb, p_actor jsonb)
returns lrn_lesson_versions language plpgsql security definer set search_path = public as $$
declare cur lrn_lesson_versions; v lrn_lesson_versions;
begin
  perform pg_advisory_xact_lock(hashtext('lrn_versions:' || p_org || ':' || p_level || ':' || coalesce(p_ws, '')));
  select * into cur from lrn_lesson_versions where organization_id = p_org and level = p_level and workspace_id is not distinct from p_ws and active for update;
  update lrn_lesson_versions set active = false where id = cur.id;
  insert into lrn_lesson_versions (level, organization_id, workspace_id, version_no, lessons, parent_id, change, active, created_by, created_label)
  values (p_level, p_org, p_ws, coalesce((select max(version_no) from lrn_lesson_versions where organization_id = p_org and level = p_level
                                          and workspace_id is not distinct from p_ws), 0) + 1,
          p_lessons, cur.id, p_change, true, (p_actor->>'uid')::uuid, p_actor->>'label')
  returning * into v;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values ((p_actor->>'uid')::uuid, p_actor->>'kind', p_actor->>'label', p_org, p_ws, 'lrn.version_created', 'lrn_lesson_version', v.id::text,
          jsonb_build_object('version_id', cur.id, 'version_no', cur.version_no, 'lessons', jsonb_array_length(coalesce(cur.lessons, '[]'))),
          jsonb_build_object('version_no', v.version_no, 'lessons', jsonb_array_length(v.lessons), 'change', p_change));
  if p_ws is not null then
    insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
    values (p_ws, 'learn.lessons_version_activated', 'lrn_lesson_version', v.id::text, jsonb_build_object('version_no', v.version_no, 'previous', cur.id));
  end if;
  return v;
end $$;

create or replace function public._lrn_active(p_level text, p_org uuid, p_ws text) returns lrn_lesson_versions
language sql stable security definer set search_path = public as $$
  select * from lrn_lesson_versions where organization_id = p_org and level = p_level and workspace_id is not distinct from p_ws and active
$$;

-- Quem pode decidir sobre uma lição: cliente → learn.lessons.approve nesse cliente (+ flag); agência → learn.lessons.agency
-- na organização da lição (só equipa da agência a tem; a equipa de um cliente nunca).
create or replace function public._lrn_require_decide(l lrn_lessons, p_token text, p_action text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if l.level = 'client' then
    perform public._content_require('learn.lessons.approve', l.workspace_id, p_token, p_action, l.id::text);
    perform public._lrn_require_flag('learn.lessons', l.workspace_id, p_token);
  else
    if not public._org_can('learn.lessons.agency', l.organization_id) then
      raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'organization_id', l.organization_id, 'action', p_action, 'entity_id', l.id, 'capability', 'learn.lessons.agency');
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
  end if;
end $$;

-- Página Aprendizagem → Lições.
create or replace function public.lrn_lessons_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid; staff boolean; agency boolean; cv lrn_lesson_versions; av lrn_lesson_versions; last_job agent_jobs; since timestamptz;
begin
  perform public._content_require('learn.read', p_ws, p_token, 'lrn.lessons_list', p_ws);
  perform public._lrn_require_flag('learn.lessons', p_ws, p_token);
  select organization_id into org from clients where id = p_ws;
  staff := public._lrn_is_agency_staff(org);
  agency := staff and public._org_can('learn.lessons.agency', org);
  cv := public._lrn_active('client', org, p_ws);
  select * into last_job from agent_jobs where workspace_id = p_ws and kind = 'lesson_editor' order by created_at desc limit 1;
  since := coalesce((select max((j.params->>'until')::timestamptz) from agent_jobs j where j.workspace_id = p_ws and j.kind = 'lesson_editor' and j.status = 'succeeded'),
                    now() - interval '7 days');
  return jsonb_build_object(
    'can', jsonb_build_object('approve', public.ws_can('learn.lessons.approve', p_ws, p_token), 'agency', agency),
    'proposed', (select coalesce(jsonb_agg(public._lrn_lesson_json(l, true) order by l.proposed_at desc), '[]') from lrn_lessons l
                  where l.level = 'client' and l.workspace_id = p_ws and l.status = 'proposed'),
    'decided', (select coalesce(jsonb_agg(public._lrn_lesson_json(l, true) order by l.decided_at desc), '[]') from
                  (select * from lrn_lessons where level = 'client' and workspace_id = p_ws and status <> 'proposed' order by decided_at desc limit 100) l),
    'active', public._lrn_version_json(cv),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'active', v.active, 'n', jsonb_array_length(v.lessons),
                    'change', v.change, 'created_label', v.created_label, 'created_at', v.created_at) order by v.version_no desc), '[]')
                  from (select * from lrn_lesson_versions where level = 'client' and organization_id = org and workspace_id = p_ws order by version_no desc limit 50) v),
    'signals', (select jsonb_build_object('since', since,
                    'edits', count(*) filter (where kind in ('edit', 'approved')),
                    'no_reason', count(*) filter (where kind in ('approved', 'changes_requested', 'rejected') and cardinality(codes) = 0 and note is null),
                    'unedited', count(*) filter (where kind = 'approved_unedited'),
                    'rejected', count(*) filter (where kind in ('changes_requested', 'rejected')))
                  from lrn_edit_signals where workspace_id = p_ws and created_at >= since),
    'job', public._reference_job_json(last_job),
    -- espaço da agência: só para a equipa da agência (R-13). Só regras, sem dados de outro cliente (LRN-04).
    'agency', case when not staff then null else jsonb_build_object(
       'active', public._lrn_version_json(public._lrn_active('agency', org, null)),
       'proposed', case when agency then (select coalesce(jsonb_agg(public._lrn_lesson_json(l, false) order by l.proposed_at desc), '[]')
                    from lrn_lessons l where l.level = 'agency' and l.organization_id = org and l.status = 'proposed') else '[]'::jsonb end) end);
end $$;

-- Aprovar (com texto editado ou não), rejeitar. Aprovar cria uma nova versão do conjunto com a lição.
create or replace function public.lrn_lesson_decide(p_id uuid, p_action text, p_text text default null, p_note text default null, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l lrn_lessons; old lrn_lessons; a jsonb; cv lrn_lesson_versions; nt text := nullif(btrim(coalesce(p_note, '')), ''); tx text := nullif(btrim(coalesce(p_text, '')), '');
begin
  select * into l from lrn_lessons where id = p_id for update;
  if l.id is null then raise exception 'licao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._lrn_require_decide(l, p_token, 'lrn.lesson_' || coalesce(p_action, ''));
  if p_action not in ('approve', 'reject') then raise exception 'acao_invalida' using errcode = '22023'; end if;
  if l.status <> 'proposed' then raise exception 'licao_ja_decidida' using errcode = '22023', detail = 'Esta lição já foi decidida.'; end if;
  if tx is not null and char_length(tx) not between 5 and 400 then raise exception 'texto_invalido' using errcode = '22023', detail = 'A lição tem entre 5 e 400 caracteres.'; end if;
  if char_length(nt) > 500 then raise exception 'motivo_longo' using errcode = '22023', detail = 'A nota tem no máximo 500 caracteres.'; end if;
  a := public._content_actor(p_token);
  if a->>'kind' <> 'user' then raise exception 'sem_permissao' using errcode = '42501'; end if;   -- decidir lições exige sessão individual
  old := l;
  update lrn_lessons set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
         text = case when p_action = 'approve' then coalesce(tx, text) else text end,
         decided_at = now(), decided_by = (a->>'uid')::uuid, decided_label = a->>'label', decision_note = nt
   where id = l.id returning * into l;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', l.organization_id, l.workspace_id, 'lrn.lesson_' || p_action || 'd', 'lrn_lesson', l.id::text,
          jsonb_build_object('status', old.status, 'text', old.text), jsonb_build_object('status', l.status, 'text', l.text, 'note', nt));
  if p_action = 'approve' then
    cv := public._lrn_active(l.level, l.organization_id, l.workspace_id);
    perform public._lrn_new_version(l.level, l.organization_id, l.workspace_id,
      coalesce(cv.lessons, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('id', l.id, 'category', l.category, 'text', l.text)),
      jsonb_build_object('action', 'approve', 'lesson_id', l.id), a);
  end if;
  return public._lrn_lesson_json(l, l.level = 'client');
end $$;

-- Retirar uma lição em vigor: nova versão sem ela (a lição continua aprovada no histórico).
create or replace function public.lrn_lesson_retire(p_id uuid, p_note text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l lrn_lessons; a jsonb; cv lrn_lesson_versions; v lrn_lesson_versions;
begin
  select * into l from lrn_lessons where id = p_id;
  if l.id is null then raise exception 'licao_nao_encontrada' using errcode = 'P0002'; end if;
  perform public._lrn_require_decide(l, p_token, 'lrn.lesson_retire');
  a := public._content_actor(p_token);
  if a->>'kind' <> 'user' then raise exception 'sem_permissao' using errcode = '42501'; end if;
  cv := public._lrn_active(l.level, l.organization_id, l.workspace_id);
  if cv.id is null or not exists (select 1 from jsonb_array_elements(cv.lessons) x where x->>'id' = l.id::text) then
    raise exception 'licao_fora_de_vigor' using errcode = '22023', detail = 'Esta lição não está em vigor.';
  end if;
  v := public._lrn_new_version(l.level, l.organization_id, l.workspace_id,
         (select coalesce(jsonb_agg(x order by o), '[]') from jsonb_array_elements(cv.lessons) with ordinality e(x, o) where x->>'id' <> l.id::text),
         jsonb_build_object('action', 'retire', 'lesson_id', l.id, 'note', nullif(left(btrim(coalesce(p_note, '')), 500), '')), a);
  return public._lrn_version_json(v);
end $$;

-- Voltar atrás: nova versão com as lições de uma versão anterior (nada é apagado nem reescrito).
create or replace function public.lrn_version_restore(p_version uuid, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o lrn_lesson_versions; a jsonb; v lrn_lesson_versions;
begin
  select * into o from lrn_lesson_versions where id = p_version;
  if o.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  if o.level = 'client' then
    perform public._content_require('learn.lessons.approve', o.workspace_id, p_token, 'lrn.version_restore', o.id::text);
    perform public._lrn_require_flag('learn.lessons', o.workspace_id, p_token);
  elsif not public._org_can('learn.lessons.agency', o.organization_id) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  a := public._content_actor(p_token);
  if a->>'kind' <> 'user' then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if o.active then return public._lrn_version_json(o); end if;
  v := public._lrn_new_version(o.level, o.organization_id, o.workspace_id, o.lessons,
                               jsonb_build_object('action', 'restore', 'from_version', o.version_no, 'from_id', o.id), a);
  return public._lrn_version_json(v);
end $$;

-- Promover uma lição aprovada de um cliente a proposta da agência: copia só a regra (texto editável, para generalizar)
-- e a categoria. Nada do cliente segue (nem id, nem evidência, nem números): fica apenas no histórico do cliente.
create or replace function public.lrn_lesson_promote(p_id uuid, p_text text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l lrn_lessons; n lrn_lessons; a jsonb; tx text := nullif(btrim(coalesce(p_text, '')), '');
begin
  select * into l from lrn_lessons where id = p_id;
  if l.id is null then raise exception 'licao_nao_encontrada' using errcode = 'P0002'; end if;
  if l.level <> 'client' or l.status <> 'approved' then raise exception 'licao_invalida' using errcode = '22023', detail = 'Só se promovem lições aprovadas de um cliente.'; end if;
  perform public._content_require('learn.read', l.workspace_id, p_token, 'lrn.lesson_promote', l.id::text);
  if not public._org_can('learn.lessons.agency', l.organization_id) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  tx := coalesce(tx, l.text);
  if char_length(tx) not between 5 and 400 then raise exception 'texto_invalido' using errcode = '22023', detail = 'A lição tem entre 5 e 400 caracteres.'; end if;
  a := public._content_actor(p_token);
  insert into lrn_lessons (level, organization_id, workspace_id, category, proposed_text, text, source, evidence)
  values ('agency', l.organization_id, null, l.category, tx, tx, 'promoted', '{}'::jsonb)
  returning * into n;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', l.organization_id, l.workspace_id, 'lrn.lesson_promoted', 'lrn_lesson', l.id::text,
          jsonb_build_object('agency_lesson_id', n.id));
  return public._lrn_lesson_json(n, false);
end $$;

-- "Propor lições agora": põe o Editor de lições na fila para as edições desde a última proposta (uma por dia).
create or replace function public._lrn_enqueue(p_ws text, p_until timestamptz, p_key text, p_actor jsonb) returns agent_jobs
language plpgsql security definer set search_path = public as $$
declare since timestamptz;
begin
  since := coalesce((select max((j.params->>'until')::timestamptz) from agent_jobs j where j.workspace_id = p_ws and j.kind = 'lesson_editor' and j.status = 'succeeded'),
                    p_until - interval '7 days');
  return public._agent_enqueue(p_ws, 'lesson_editor', p_key, null, p_actor, jsonb_build_object('since', since, 'until', p_until));
end $$;

create or replace function public.lrn_lessons_run(p_ws text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb; j agent_jobs; tz text;
begin
  perform public._content_require('learn.lessons.approve', p_ws, p_token, 'lrn.lessons_run', p_ws);
  perform public._lrn_require_flag('learn.lessons', p_ws, p_token);
  a := public._content_actor(p_token);
  select * into j from agent_jobs where workspace_id = p_ws and kind = 'lesson_editor' and status in ('queued', 'running') order by created_at desc limit 1;
  if j.id is not null then return public._reference_job_json(j); end if;
  select coalesce(timezone, 'UTC') into tz from clients where id = p_ws;
  j := public._lrn_enqueue(p_ws, now(), 'lesson_editor:manual:' || to_char(now() at time zone tz, 'YYYY-MM-DD"T"HH24MI'), a);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'agent_job.enqueued', 'agent_job', j.id::text, jsonb_build_object('kind', 'lesson_editor'));
  return public._reference_job_json(j);
end $$;

-- Agenda (pg_cron, de hora a hora): depois das 06:00 do cliente, uma execução por dia com as edições do dia anterior,
-- só onde a flag não está desligada e houve pelo menos um sinal. p_now só existe para os testes.
create or replace function public.lrn_lessons_tick(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path = public as $$
declare c record; n int := 0; j agent_jobs; local_now timestamp; day_end timestamptz; k text;
begin
  for c in select cl.id, cl.organization_id, coalesce(cl.timezone, 'UTC') tz from clients cl
            where cl.status = 'active' and exists (select 1 from agent_config_versions v where v.workspace_id = cl.id and v.status = 'active') loop
    if public._flag_stage('learn.lessons', c.organization_id, c.id) = 'off' then continue; end if;
    local_now := p_now at time zone c.tz;
    if extract(hour from local_now) < 6 then continue; end if;
    day_end := (date_trunc('day', local_now)) at time zone c.tz;
    if not exists (select 1 from lrn_edit_signals s where s.workspace_id = c.id and s.created_at >= day_end - interval '1 day' and s.created_at < day_end) then continue; end if;
    k := 'lesson_editor:' || to_char(local_now::date - 1, 'YYYY-MM-DD');
    if exists (select 1 from agent_jobs where workspace_id = c.id and idempotency_key = k) then continue; end if;   -- já pedido hoje
    begin
      j := public._lrn_enqueue(c.id, day_end, k, jsonb_build_object('kind', 'system', 'uid', null, 'label', 'Agenda'));
      n := n + 1;
    exception when sqlstate '22023' then null;   -- sem orçamento ou sem configuração ativa: não enfileira
    end;
  end loop;
  return n;
end $$;

-- ───────────── LRN-02: worker (engine_worker) ─────────────
create or replace function public._lrn_worker_job(p_job uuid, p_worker text) returns agent_jobs
language plpgsql security definer set search_path = public as $$
declare j agent_jobs;
begin
  j := public._reference_worker_job(p_job, p_worker, 'lesson_editor');
  return j;
end $$;

-- Pares da janela do job: versão do motor → versão humana, motivos (com rótulo e grupo), distância; mais as lições em
-- vigor e as já propostas (para não repetir). Só deste cliente.
create or replace function public.worker_lesson_pairs(p_job uuid, p_worker text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; since timestamptz; until_ timestamptz; v_codes jsonb; org uuid;
begin
  j := public._lrn_worker_job(p_job, p_worker);
  since := coalesce((j.params->>'since')::timestamptz, j.created_at - interval '1 day');
  until_ := coalesce((j.params->>'until')::timestamptz, j.created_at);
  v_codes := public._lrn_codes(j.workspace_id);
  select organization_id into org from clients where id = j.workspace_id;
  return jsonb_build_object(
    'workspace_id', j.workspace_id, 'since', since, 'until', until_, 'threshold', public._lrn_threshold(), 'codes', v_codes,
    'pairs', (select coalesce(jsonb_agg(jsonb_build_object(
                 'signal_id', s.id, 'content_id', s.content_id, 'kind', s.kind, 'edit_ratio', s.edit_ratio,
                 'codes', (select coalesce(jsonb_agg(jsonb_build_object('code', k->>'code', 'label', k->>'label', 'group', k->>'group')), '[]')
                             from jsonb_array_elements(v_codes) k where k->>'code' = any (s.codes)),
                 'note', s.note, 'no_reason', cardinality(s.codes) = 0 and s.note is null, 'at', s.created_at,
                 'formato', g.formato, 'tema', g.tema,
                 'before', jsonb_build_object('hooks', ev.hooks, 'corpo', ev.corpo, 'cta', ev.cta),
                 'after', case when s.kind = 'approved_unedited' then null else jsonb_build_object('hooks', hv.hooks, 'corpo', hv.corpo, 'cta', hv.cta) end)
               order by s.created_at), '[]')
               from (select * from lrn_edit_signals where workspace_id = j.workspace_id and created_at >= since and created_at < until_
                      order by created_at limit 300) s
               join guioes g on g.id = s.content_id
               join content_versions ev on ev.id = s.engine_version_id
               join content_versions hv on hv.id = s.version_id),
    'active', coalesce((public._lrn_active('client', org, j.workspace_id)).lessons, '[]'::jsonb),
    'proposed', (select coalesce(jsonb_agg(jsonb_build_object('category', l.category, 'text', l.text)), '[]')
                   from lrn_lessons l where l.level = 'client' and l.workspace_id = j.workspace_id and l.status = 'proposed'));
end $$;

-- Grava uma lição proposta (idempotente por execução e posição). A evidência é refeita aqui a partir dos sinais citados:
-- só sinais deste cliente e desta janela contam; o número de edições e os exemplos antes/depois vêm da base.
create or replace function public.worker_lesson_save(p_job uuid, p_worker text, p_slot integer, p_lesson jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; l lrn_lessons; since timestamptz; until_ timestamptz; ids uuid[]; cat text; tx text; org uuid; ev jsonb;
begin
  j := public._lrn_worker_job(p_job, p_worker);
  if p_slot is null or p_slot not between 1 and 50 then raise exception 'slot_invalido' using errcode = '22023'; end if;
  select * into l from lrn_lessons where job_id = j.id and slot = p_slot;
  if l.id is not null then return jsonb_build_object('lesson_id', l.id, 'created', false); end if;
  if jsonb_typeof(p_lesson) <> 'object' then raise exception 'licao_invalida' using errcode = '22023'; end if;
  cat := public._ref_txt(p_lesson->'category', 10);
  if cat is null or cat not in ('hook', 'corpo', 'cta', 'facto', 'tom', 'outro') then raise exception 'categoria_invalida' using errcode = '22023'; end if;
  tx := public._ref_txt(p_lesson->'text', 400);
  if tx is null or char_length(tx) < 5 then raise exception 'texto_invalido' using errcode = '22023'; end if;
  since := coalesce((j.params->>'since')::timestamptz, j.created_at - interval '1 day');
  until_ := coalesce((j.params->>'until')::timestamptz, j.created_at);
  begin
    ids := array(select distinct x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_lesson->'signal_ids') = 'array' then p_lesson->'signal_ids' else '[]' end) x);
  exception when others then raise exception 'evidencia_invalida' using errcode = '22023';
  end;
  ids := array(select s.id from lrn_edit_signals s where s.id = any (ids) and s.workspace_id = j.workspace_id
                 and s.created_at >= since and s.created_at < until_);
  if cardinality(ids) = 0 then raise exception 'sem_evidencia' using errcode = '22023', detail = 'Uma lição precisa de pelo menos um par deste cliente.'; end if;
  ev := jsonb_build_object(
    'edits', cardinality(ids),
    'signal_ids', to_jsonb(ids),
    'content_ids', (select coalesce(jsonb_agg(distinct s.content_id), '[]') from lrn_edit_signals s where s.id = any (ids)),
    'codes', (select coalesce(jsonb_object_agg(c, n), '{}') from (select c, count(*) n from lrn_edit_signals s, unnest(s.codes) c where s.id = any (ids) group by c) x),
    'examples', (select coalesce(jsonb_agg(jsonb_build_object('signal_id', s.id, 'content_id', s.content_id, 'kind', s.kind, 'edit_ratio', s.edit_ratio,
                    'before', left(public._lrn_text(ev2.hooks, ev2.corpo, ev2.cta), 600),
                    'after', case when s.kind = 'approved_unedited' then null else left(public._lrn_text(hv.hooks, hv.corpo, hv.cta), 600) end,
                    'note', s.note) order by s.edit_ratio desc), '[]')
                 from (select * from lrn_edit_signals where id = any (ids) order by edit_ratio desc limit 3) s
                 join content_versions ev2 on ev2.id = s.engine_version_id join content_versions hv on hv.id = s.version_id),
    'window', jsonb_build_object('since', since, 'until', until_));
  select organization_id into org from clients where id = j.workspace_id;
  insert into lrn_lessons (level, organization_id, workspace_id, category, proposed_text, text, rationale, evidence, source, job_id, slot,
                           model, prompt_version, agent_version)
  values ('client', org, j.workspace_id, cat, tx, tx, public._ref_txt(p_lesson->'rationale', 600), ev, 'engine', j.id, p_slot,
          public._ref_txt(p_lesson->'model', 80), public._ref_txt(p_lesson->'prompt_version', 80), public._ref_txt(p_lesson->'agent_version', 80))
  on conflict (job_id, slot) do nothing
  returning * into l;
  if l.id is null then select * into l from lrn_lessons where job_id = j.id and slot = p_slot; return jsonb_build_object('lesson_id', l.id, 'created', false); end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (null, 'system', 'Editor de lições', org, j.workspace_id, 'lrn.lesson_proposed', 'lrn_lesson', l.id::text,
          jsonb_build_object('job_id', j.id, 'slot', p_slot, 'edits', cardinality(ids), 'category', cat));
  return jsonb_build_object('lesson_id', l.id, 'created', true);
end $$;

-- Lições em vigor para qualquer execução deste cliente (LRN-05 consome): agência + cliente; em conflito prevalece o cliente.
create or replace function public.worker_lessons(p_job uuid, p_worker text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j agent_jobs; org uuid; cv lrn_lesson_versions; av lrn_lesson_versions;
begin
  select * into j from agent_jobs where id = p_job;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  select organization_id into org from clients where id = j.workspace_id;
  cv := public._lrn_active('client', org, j.workspace_id);
  av := public._lrn_active('agency', org, null);
  return jsonb_build_object('precedence', 'client',
    'client', jsonb_build_object('version_id', cv.id, 'version_no', cv.version_no, 'lessons', coalesce(cv.lessons, '[]'::jsonb)),
    'agency', jsonb_build_object('version_id', av.id, 'version_no', av.version_no, 'lessons', coalesce(av.lessons, '[]'::jsonb)));
end $$;

-- ───────────── privilégios ─────────────
revoke all on function public._lrn_threshold(), public._lrn_fixed_codes(), public._lrn_rework_group(text), public._lrn_codes(text),
  public._lrn_clean_codes(text, text[]), public._lrn_text(jsonb, text, text), public._lrn_edit_ratio(text, text), public._lrn_engine_version(text),
  public._lrn_ratio_now(guioes, content_versions), public._lrn_require_flag(text, text, text), public._lrn_is_agency_staff(uuid, uuid),
  public._lrn_lesson_json(lrn_lessons, boolean), public._lrn_version_json(lrn_lesson_versions),
  public._lrn_new_version(text, uuid, text, jsonb, jsonb, jsonb), public._lrn_active(text, uuid, text), public._lrn_require_decide(lrn_lessons, text, text),
  public._lrn_enqueue(text, timestamptz, text, jsonb), public._lrn_worker_job(uuid, text), public.lrn_lessons_guard(), public.lrn_versions_guard(),
  public.lrn_lessons_tick(timestamptz) from public, anon, authenticated;
revoke all on function public.lrn_edit_options(text, text), public.content_edit_ratio(text, text), public.content_edit_reason(text, text[], text, text),
  public.content_decide_learned(text, text, text[], text, text, text, integer, text), public.lrn_lessons_list(text, text),
  public.lrn_lesson_decide(uuid, text, text, text, text), public.lrn_lesson_retire(uuid, text, text), public.lrn_version_restore(uuid, text),
  public.lrn_lesson_promote(uuid, text, text), public.lrn_lessons_run(text, text) from public;
-- anon = código de equipa: lê opções e decide guiões como hoje (o servidor verifica); lições exigem sessão individual.
grant execute on function public.lrn_edit_options(text, text), public.content_edit_ratio(text, text), public.content_edit_reason(text, text[], text, text),
  public.content_decide_learned(text, text, text[], text, text, text, integer, text), public.lrn_lessons_list(text, text),
  public.lrn_lesson_decide(uuid, text, text, text, text), public.lrn_lesson_retire(uuid, text, text), public.lrn_version_restore(uuid, text),
  public.lrn_lesson_promote(uuid, text, text), public.lrn_lessons_run(text, text) to anon, authenticated;
revoke all on function public.worker_lesson_pairs(uuid, text), public.worker_lesson_save(uuid, text, integer, jsonb), public.worker_lessons(uuid, text)
  from public, anon, authenticated;
grant execute on function public.worker_lesson_pairs(uuid, text), public.worker_lesson_save(uuid, text, integer, jsonb), public.worker_lessons(uuid, text)
  to engine_worker, service_role;

-- agenda: de hora a hora
create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'lrn-lessons-tick') then
    perform cron.schedule('lrn-lessons-tick', '7 * * * *', 'select public.lrn_lessons_tick()');
  end if;
end $$;

/* Rollback (compatível; o código em main não usa nada daqui), por esta ordem:
   select cron.unschedule('lrn-lessons-tick');
   drop function public.worker_lessons(uuid, text), public.worker_lesson_save(uuid, text, integer, jsonb), public.worker_lesson_pairs(uuid, text),
     public._lrn_worker_job(uuid, text), public.lrn_lessons_tick(timestamptz), public.lrn_lessons_run(text, text), public._lrn_enqueue(text, timestamptz, text, jsonb),
     public.lrn_lesson_promote(uuid, text, text), public.lrn_version_restore(uuid, text), public.lrn_lesson_retire(uuid, text, text),
     public.lrn_lesson_decide(uuid, text, text, text, text), public.lrn_lessons_list(text, text), public._lrn_require_decide(lrn_lessons, text, text),
     public._lrn_active(text, uuid, text), public._lrn_new_version(text, uuid, text, jsonb, jsonb, jsonb), public._lrn_version_json(lrn_lesson_versions),
     public._lrn_lesson_json(lrn_lessons, boolean), public._lrn_is_agency_staff(uuid, uuid),
     public.content_decide_learned(text, text, text[], text, text, text, integer, text), public.content_edit_reason(text, text[], text, text),
     public.content_edit_ratio(text, text), public.lrn_edit_options(text, text), public._lrn_require_flag(text, text, text),
     public._lrn_ratio_now(guioes, content_versions), public._lrn_engine_version(text), public._lrn_edit_ratio(text, text), public._lrn_text(jsonb, text, text),
     public._lrn_clean_codes(text, text[]), public._lrn_codes(text), public._lrn_rework_group(text), public._lrn_fixed_codes(), public._lrn_threshold();
   delete from feature_flags where key in ('learn.edits', 'learn.lessons'); delete from feature_flag_defs where key in ('learn.edits', 'learn.lessons');
   delete from role_capabilities where capability in ('learn.lessons.approve', 'learn.lessons.agency');
   delete from permission_grants where capability in ('learn.lessons.approve', 'learn.lessons.agency');
   update capabilities set status = 'W10' where key in ('learn.lessons.approve', 'learn.lessons.agency');
   contract posterior (só depois de exportar os dados e de o motor deixar de pedir 'lesson_editor'):
     drop table public.lrn_lesson_versions, public.lrn_lessons, public.lrn_edit_signals; drop function public.lrn_versions_guard(), public.lrn_lessons_guard();
     agent_jobs_kind_check sem 'lesson_editor' (reconstruído a partir da definição em vigor) só sem linhas desse tipo;
     delete from capabilities where key in ('learn.lessons.approve', 'learn.lessons.agency'). */
