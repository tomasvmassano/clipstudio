-- W5-14 · Lista de frases-persona por cliente (PRD R-17, CHG-003; VAR-03, VAR-04, REF-03; AGENTS §7; ADR-0053). Expand (aditivo).
-- Hipérbole sobre o próprio criador ("o homem mais rico de Portugal") só a partir de uma lista aprovada por workspace,
-- versionada (cada gravação cria uma versão nova, imutável) e auditada. Frases que envolvam outra pessoa exigem o
-- consentimento registado dessa pessoa. O worker recebe a versão em vigor no claim (worker_claim.persona) e regista-a.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('persona.manage', 'Agentes', 'A', array['ws'], 'ativo', 'Aprovar a lista de frases-persona do cliente (R-17)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'persona.manage'), ('ws', 'workspace_admin', 'persona.manage')
on conflict do nothing;

create table if not exists public.persona_lists (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  version integer not null check (version > 0),
  phrases jsonb not null check (jsonb_typeof(phrases) = 'array'),
  note text check (note is null or char_length(note) <= 500),
  created_by uuid references auth.users(id) on delete set null,
  created_label text,
  created_at timestamptz not null default now(),
  unique (workspace_id, version)
);
alter table public.persona_lists enable row level security;
revoke all on public.persona_lists from anon, authenticated;   -- só pelas RPCs; nunca se altera uma versão

create or replace function public._persona_lists_immutable() returns trigger
language plpgsql set search_path = public as $$
begin
  raise exception 'versao_imutavel' using errcode = '42501', detail = 'As versões da lista de frases-persona não se alteram: grava uma nova.';
end $$;
drop trigger if exists persona_lists_immutable on public.persona_lists;
create trigger persona_lists_immutable before update or delete on public.persona_lists
  for each row execute function public._persona_lists_immutable();

-- Validação de uma lista: [{id, text, involves?: {name, consent_by, consent_at, consent_note?}}], até 100 frases, textos únicos.
create or replace function public._persona_problem(p jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare x jsonb; n int := 0; seen text[] := '{}'; t text; ids text[] := '{}'; inv jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' then return 'a lista tem de ser uma lista de frases'; end if;
  if jsonb_array_length(p) > 100 then return 'no máximo 100 frases'; end if;
  for x in select * from jsonb_array_elements(p) loop
    n := n + 1;
    if jsonb_typeof(x) <> 'object' then return format('frase %s inválida', n); end if;
    if coalesce(x->>'id', '') !~ '^[a-z0-9_-]{1,40}$' then return format('frase %s sem identificador válido', n); end if;
    if x->>'id' = any (ids) then return format('identificador repetido: %s', x->>'id'); end if;
    ids := ids || (x->>'id');
    t := btrim(coalesce(x->>'text', ''));
    if char_length(t) < 3 or char_length(t) > 160 then return format('frase %s: entre 3 e 160 caracteres', n); end if;
    if lower(t) = any (seen) then return format('frase repetida: %s', t); end if;
    seen := seen || lower(t);
    inv := x->'involves';
    if inv is not null and inv <> 'null'::jsonb then
      if jsonb_typeof(inv) <> 'object' or char_length(btrim(coalesce(inv->>'name', ''))) < 2 then
        return format('frase %s: diz quem é a outra pessoa', n); end if;
      if char_length(btrim(coalesce(inv->>'consent_by', ''))) < 2 or coalesce(inv->>'consent_at', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        return format('frase %s envolve %s: regista o consentimento (quem o deu e em que dia)', n, inv->>'name'); end if;
      if char_length(coalesce(inv->>'consent_note', '')) > 300 then return format('frase %s: nota do consentimento demasiado longa', n); end if;
    end if;
  end loop;
  return null;
end $$;

create or replace function public._persona_current(p_ws text) returns persona_lists
language sql stable security definer set search_path = public as $$
  select * from persona_lists where workspace_id = p_ws order by version desc limit 1
$$;

create or replace function public.persona_list_get(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cur persona_lists := public._persona_current(p_ws);
begin
  perform public._content_require('agents.read', p_ws, p_token, 'persona.read', null);
  return jsonb_build_object(
    'version', coalesce(cur.version, 0), 'phrases', coalesce(cur.phrases, '[]'::jsonb), 'note', cur.note,
    'saved_by', cur.created_label, 'saved_at', cur.created_at,
    'history', (select coalesce(jsonb_agg(jsonb_build_object('version', l.version, 'count', jsonb_array_length(l.phrases), 'note', l.note,
                  'by', l.created_label, 'at', l.created_at) order by l.version desc), '[]')
                from (select * from persona_lists where workspace_id = p_ws order by version desc limit 30) l),
    'can', jsonb_build_object('manage', public.ws_can('persona.manage', p_ws, p_token)));
end $$;

create or replace function public.persona_list_version(p_ws text, p_version int, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l persona_lists;
begin
  perform public._content_require('agents.read', p_ws, p_token, 'persona.read', null);
  select * into l from persona_lists where workspace_id = p_ws and version = p_version;
  if l.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  return jsonb_build_object('version', l.version, 'phrases', l.phrases, 'note', l.note, 'by', l.created_label, 'at', l.created_at);
end $$;

-- Gravar = versão nova. p_expected é a versão que a pessoa estava a ver (conflito se outra pessoa gravou entretanto).
create or replace function public.persona_list_save(p_ws text, p_phrases jsonb, p_expected int, p_note text default null,
                                                    p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cur persona_lists; why text; lbl text; clean jsonb; added jsonb; removed jsonb; nv int;
begin
  if auth.uid() is null then raise exception 'sessao_individual' using errcode = '42501',
    detail = 'Aprovar frases-persona precisa de uma conta individual.'; end if;
  perform public._content_require('persona.manage', p_ws, p_token, 'persona.save', null);
  why := public._persona_problem(p_phrases);
  if why is not null then raise exception 'lista_invalida' using errcode = '22023', detail = why; end if;
  if p_note is not null and char_length(p_note) > 500 then raise exception 'nota_longa' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('persona:' || p_ws));
  cur := public._persona_current(p_ws);
  if coalesce(cur.version, 0) <> coalesce(p_expected, -1) then
    raise exception 'conflito_versao' using errcode = '40001',
      detail = format('Outra pessoa gravou a versão %s entretanto. Recarrega e volta a aplicar as tuas alterações.', coalesce(cur.version, 0)); end if;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', x->>'id', 'text', btrim(x->>'text'),
           'involves', case when x->'involves' is not null and x->'involves' <> 'null'::jsonb then jsonb_strip_nulls(jsonb_build_object(
             'name', btrim(x->'involves'->>'name'), 'consent_by', btrim(x->'involves'->>'consent_by'),
             'consent_at', x->'involves'->>'consent_at', 'consent_note', nullif(btrim(coalesce(x->'involves'->>'consent_note', '')), ''))) end)))
    into clean from jsonb_array_elements(p_phrases) x;
  clean := coalesce(clean, '[]');
  if cur.id is not null and clean = cur.phrases then return public.persona_list_get(p_ws, p_token); end if;   -- nada mudou
  lbl := public._media_label(auth.uid());
  nv := coalesce(cur.version, 0) + 1;
  insert into persona_lists (workspace_id, version, phrases, note, created_by, created_label)
  values (p_ws, nv, clean, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), lbl);
  select coalesce(jsonb_agg(x->>'text'), '[]') into added from jsonb_array_elements(clean) x
   where not exists (select 1 from jsonb_array_elements(coalesce(cur.phrases, '[]')) y where y->>'text' = x->>'text');
  select coalesce(jsonb_agg(y->>'text'), '[]') into removed from jsonb_array_elements(coalesce(cur.phrases, '[]')) y
   where not exists (select 1 from jsonb_array_elements(clean) x where x->>'text' = y->>'text');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (auth.uid(), 'user', lbl, p_ws, 'persona.list_saved', 'persona_list', p_ws || ':' || nv,
          jsonb_build_object('version', coalesce(cur.version, 0), 'count', jsonb_array_length(coalesce(cur.phrases, '[]'))),
          jsonb_build_object('version', nv, 'count', jsonb_array_length(clean), 'added', added, 'removed', removed));
  return public.persona_list_get(p_ws, p_token);
end $$;

revoke all on function public._persona_problem(jsonb), public._persona_current(text), public._persona_lists_immutable() from public, anon, authenticated;
revoke all on function public.persona_list_get(text, text), public.persona_list_version(text, int, text),
  public.persona_list_save(text, jsonb, int, text, text) from public, anon;
grant execute on function public.persona_list_get(text, text), public.persona_list_version(text, int, text),
  public.persona_list_save(text, jsonb, int, text, text) to authenticated;

-- O worker recebe a lista em vigor (só os textos e quem está envolvido; o consentimento fica na app) e regista a versão.
CREATE OR REPLACE FUNCTION public.worker_claim(p_worker text, p_kinds text[] DEFAULT ARRAY['daily_pipeline'::text, 'scouts'::text, 'analysis'::text], p_lease_seconds integer DEFAULT 600)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j agent_jobs; cfg jsonb; tz text; spent numeric; pl persona_lists;
begin
  if p_worker is null or length(p_worker) not between 3 and 80 then raise exception 'worker_invalido' using errcode = '22023'; end if;
  insert into agent_workers (id, kinds, last_seen) values (p_worker, p_kinds, now())
  on conflict (id) do update set kinds = excluded.kinds, last_seen = now();
  perform public.agent_schedule_tick();
  update agent_job_attempts ja set status = 'lost', finished_at = now()
    from agent_jobs x where ja.job_id = x.id and ja.status = 'running' and x.status = 'running' and x.locked_until < now();
  update agent_jobs set status = case when attempts >= max_attempts then 'dead' else 'queued' end,
         next_attempt_at = now(), locked_by = null, locked_until = null,
         last_error = coalesce(last_error, 'worker deixou de responder'), finished_at = case when attempts >= max_attempts then now() end
   where status = 'running' and locked_until < now();
  select * into j from agent_jobs
   where status = 'queued' and next_attempt_at <= now() and scheduled_for <= now() and kind = any (p_kinds)
   order by scheduled_for, created_at limit 1 for update skip locked;
  if j.id is null then return null; end if;
  update agent_jobs set status = 'running', attempts = attempts + 1, locked_by = p_worker, locked_until = now() + make_interval(secs => p_lease_seconds),
         heartbeat_at = now(), started_at = coalesce(started_at, now()), last_error = null
   where id = j.id returning * into j;
  insert into agent_job_attempts (job_id, workspace_id, attempt, worker) values (j.id, j.workspace_id, j.attempts, p_worker);
  select config into cfg from agent_config_versions where id = j.config_version_id;
  select coalesce(timezone, 'UTC') into tz from clients where id = j.workspace_id;
  select coalesce(sum(cost_eur), 0) into spent from agent_jobs
   where workspace_id = j.workspace_id and id <> j.id and (created_at at time zone tz)::date = (now() at time zone tz)::date;
  pl := public._persona_current(j.workspace_id);
  return jsonb_build_object('job', to_jsonb(j), 'config', cfg,
    'workspace', (select jsonb_build_object('id', id, 'name', name, 'timezone', timezone) from clients where id = j.workspace_id),
    'target_date', (j.scheduled_for at time zone tz)::date + public._agent_target_offset(cfg),
    'budget_remaining_eur', case when j.budget_cap_eur is not null then greatest(0, j.budget_cap_eur - spent - coalesce(j.cost_eur, 0)) end,
    'models', (select jsonb_object_agg(key, jsonb_strip_nulls(jsonb_build_object('in', eur_per_mtok_in, 'out', eur_per_mtok_out,
                 'long_tokens', long_context_tokens, 'in_long', eur_per_mtok_in_long, 'out_long', eur_per_mtok_out_long))) from agent_models),
    'tools', (select coalesce(jsonb_object_agg(key, eur_per_use), '{}') from agent_tool_prices),
    'persona', jsonb_build_object('version', coalesce(pl.version, 0),
      'phrases', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('text', x->>'text', 'involves', x->'involves'->>'name'))), '[]')
                  from jsonb_array_elements(coalesce(pl.phrases, '[]')) x)));
end $function$;

/* Rollback (compatível): repor worker_claim de 20261029095100_w4_model_prices.sql; drop function public.persona_list_save(text, jsonb, int, text, text),
   public.persona_list_version(text, int, text), public.persona_list_get(text, text), public._persona_current(text), public._persona_problem(jsonb);
   contract posterior: drop table public.persona_lists; drop function public._persona_lists_immutable();
   delete from role_capabilities where capability = 'persona.manage'; update capabilities set status = 'W5' where key = 'persona.manage'. */
