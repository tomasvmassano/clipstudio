-- W4-02: custo desconhecido (modelos sem preço) fica vazio em vez de 0,00 EUR. Rollback: recriar worker_finish de 20261029084441.
create or replace function public.worker_finish(p_job uuid, p_worker text, p_ok boolean, p_result jsonb default null, p_error text default null,
                                                p_retryable boolean default true, p_cost_eur numeric default null, p_tokens_in bigint default null,
                                                p_tokens_out bigint default null, p_run_id text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j agent_jobs; st text; u record;
begin
  select * into j from agent_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.locked_by is distinct from p_worker then raise exception 'lease_perdida' using errcode = 'PT409'; end if;
  st := case when p_ok then 'succeeded'
             when j.cancel_requested then 'cancelled'
             when p_retryable and j.attempts < j.max_attempts then 'queued'
             else 'dead' end;
  update agent_jobs set status = st, locked_by = null, locked_until = null, result = coalesce(p_result, result),
         last_error = case when p_ok then null else left(p_error, 2000) end,
         next_attempt_at = case when st = 'queued' then now() + make_interval(mins => least(60, power(2, j.attempts)::integer)) else next_attempt_at end,
         finished_at = case when st in ('succeeded','cancelled','dead') then now() end,
         cost_eur = case when cost_eur is null and p_cost_eur is null then null else coalesce(cost_eur, 0) + coalesce(p_cost_eur, 0) end, tokens_in = coalesce(tokens_in, 0) + coalesce(p_tokens_in, 0),
         tokens_out = coalesce(tokens_out, 0) + coalesce(p_tokens_out, 0), run_id = coalesce(p_run_id, run_id)
   where id = j.id returning * into j;
  update agent_job_attempts set status = case when p_ok then 'succeeded' when st = 'cancelled' then 'cancelled' else 'failed' end,
         finished_at = now(), error = left(p_error, 2000), cost_eur = p_cost_eur
   where job_id = j.id and attempt = j.attempts;
  update agent_workers set last_seen = now() where id = p_worker;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (j.workspace_id, 'agent.job_' || case st when 'queued' then 'failed' else st end, 'agent_job', j.id::text,
          jsonb_build_object('attempt', j.attempts, 'error', left(p_error, 300), 'will_retry', st = 'queued'));
  if st = 'dead' then
    -- fila de exceções: quem configura os agentes é avisado
    for u in select a.user_id from workspace_access a where a.workspace_id = j.workspace_id and a.status = 'active'
              and public._authorize('agents.configure', j.workspace_id, a.user_id) loop
      perform public._notify(u.user_id, j.workspace_id, 'automation_error', 'agent_job', j.id::text,
                             'Execução dos agentes falhou: ' || j.kind, left(p_error, 300), 'job_dead:' || j.id);
    end loop;
  end if;
  return jsonb_build_object('status', st, 'next_attempt_at', j.next_attempt_at);
end $$;

