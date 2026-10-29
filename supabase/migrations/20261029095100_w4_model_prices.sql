-- W4-02b: preços públicos da Anthropic para o custo das execuções (FR-06-05; ADR-0011).
-- Fonte: platform.claude.com/docs/en/about-claude/pricing (consultada a 2026-10-29). Câmbio: BCE 2026-10-28, 1 EUR = 1,1133 USD.
-- O preço em USD é o dado de origem; o EUR é calculado com o câmbio guardado ao lado. Só aditivo. Rollback: bloco no fim.
alter table public.agent_models
  add column if not exists usd_per_mtok_in numeric check (usd_per_mtok_in >= 0),
  add column if not exists usd_per_mtok_out numeric check (usd_per_mtok_out >= 0),
  add column if not exists long_context_tokens integer check (long_context_tokens > 0),       -- acima disto aplica-se o escalão longo
  add column if not exists usd_per_mtok_in_long numeric check (usd_per_mtok_in_long >= 0),
  add column if not exists usd_per_mtok_out_long numeric check (usd_per_mtok_out_long >= 0),
  add column if not exists eur_per_mtok_in_long numeric check (eur_per_mtok_in_long >= 0),
  add column if not exists eur_per_mtok_out_long numeric check (eur_per_mtok_out_long >= 0),
  add column if not exists fx_usd_per_eur numeric check (fx_usd_per_eur > 0),
  add column if not exists price_source text,
  add column if not exists prices_updated_at timestamptz;

create table if not exists public.agent_tool_prices (
  key text primary key check (key ~ '^[a-z_]{3,40}$'),
  label text not null,
  usd_per_use numeric not null check (usd_per_use >= 0),
  fx_usd_per_eur numeric not null check (fx_usd_per_eur > 0),
  eur_per_use numeric generated always as (round(usd_per_use / fx_usd_per_eur, 6)) stored,
  price_source text not null,
  updated_at timestamptz not null default now()
);
alter table public.agent_tool_prices enable row level security;
revoke all on public.agent_tool_prices from anon, authenticated;

with p(key, usd_in, usd_out, long_tok, usd_in_l, usd_out_l) as (values
  ('claude-opus-5-5',   4.00, 20.00, null::integer, null::numeric, null::numeric),
  ('claude-sonnet-5-5', 2.00, 10.00, null, null, null),
  ('claude-haiku-5-5',  0.10,  0.50, 100000, 0.50, 2.50))
update public.agent_models m set
  usd_per_mtok_in = p.usd_in, usd_per_mtok_out = p.usd_out, long_context_tokens = p.long_tok,
  usd_per_mtok_in_long = p.usd_in_l, usd_per_mtok_out_long = p.usd_out_l, fx_usd_per_eur = 1.1133,
  eur_per_mtok_in = round(p.usd_in / 1.1133, 6), eur_per_mtok_out = round(p.usd_out / 1.1133, 6),
  eur_per_mtok_in_long = round(p.usd_in_l / 1.1133, 6), eur_per_mtok_out_long = round(p.usd_out_l / 1.1133, 6),
  price_source = 'https://platform.claude.com/docs/en/about-claude/pricing (2026-10-29); câmbio BCE 2026-10-28',
  prices_updated_at = now()
from p where m.key = p.key;

insert into public.agent_tool_prices (key, label, usd_per_use, fx_usd_per_eur, price_source)
values ('web_search', 'Pesquisa web da API', 0.01, 1.1133,
        'https://platform.claude.com/docs/en/about-claude/pricing (2026-10-29: 10 USD por 1000 pesquisas); câmbio BCE 2026-10-28')
on conflict (key) do update set usd_per_use = excluded.usd_per_use, fx_usd_per_eur = excluded.fx_usd_per_eur,
  price_source = excluded.price_source, updated_at = now();

-- o claim leva o escalão longo e os preços das ferramentas
create or replace function public.worker_claim(p_worker text, p_kinds text[] default array['daily_pipeline','scouts','analysis'], p_lease_seconds integer default 600)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; cfg jsonb; tz text; spent numeric;
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
  return jsonb_build_object('job', to_jsonb(j), 'config', cfg,
    'workspace', (select jsonb_build_object('id', id, 'name', name, 'timezone', timezone) from clients where id = j.workspace_id),
    'target_date', (j.scheduled_for at time zone tz)::date + public._agent_target_offset(cfg),
    'budget_remaining_eur', case when j.budget_cap_eur is not null then greatest(0, j.budget_cap_eur - spent - coalesce(j.cost_eur, 0)) end,
    'models', (select jsonb_object_agg(key, jsonb_strip_nulls(jsonb_build_object('in', eur_per_mtok_in, 'out', eur_per_mtok_out,
                 'long_tokens', long_context_tokens, 'in_long', eur_per_mtok_in_long, 'out_long', eur_per_mtok_out_long))) from agent_models),
    'tools', (select coalesce(jsonb_object_agg(key, eur_per_use), '{}') from agent_tool_prices));
end $$;

/* Rollback:
-- worker_claim: recriar a versão de 20261029092137
drop table agent_tool_prices;
alter table agent_models drop column usd_per_mtok_in, drop column usd_per_mtok_out, drop column long_context_tokens, drop column usd_per_mtok_in_long,
  drop column usd_per_mtok_out_long, drop column eur_per_mtok_in_long, drop column eur_per_mtok_out_long, drop column fx_usd_per_eur,
  drop column price_source, drop column prices_updated_at;
update agent_models set eur_per_mtok_in = null, eur_per_mtok_out = null;
*/
