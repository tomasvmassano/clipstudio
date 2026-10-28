-- 20261028175847 agent_log_realtime (exportado do Supabase a 28/10/2026; segredos tapados)
alter table public.agent_log
  add column if not exists client_id text references public.clients(id),
  add column if not exists status text not null default 'done' check (status in ('start','think','talk','done','error')),
  add column if not exists to_agent text,
  add column if not exists message text,
  add column if not exists cost_eur numeric(10,5),
  add column if not exists simulated boolean not null default false;
create index if not exists agent_log_client_created on public.agent_log (client_id, created_at desc);
create index if not exists agent_log_run on public.agent_log (run_id, id);

-- leitura pública só de campos seguros (sem input/output completos)
create or replace view public.agent_feed with (security_invoker = false) as
  select id, run_id, client_id, slot, agent, to_agent, status, left(message, 280) as message, model, ms, cost_eur, simulated, created_at
  from public.agent_log;
grant select on public.agent_feed to anon, authenticated;

-- realtime: broadcast via trigger para não expor a tabela base
create or replace function public.agent_log_broadcast() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new.id, 'run_id', new.run_id, 'client_id', new.client_id, 'slot', new.slot,
      'agent', new.agent, 'to_agent', new.to_agent, 'status', new.status, 'message', left(new.message, 280),
      'model', new.model, 'ms', new.ms, 'cost_eur', new.cost_eur, 'simulated', new.simulated, 'created_at', new.created_at),
    'agent_event', 'agents:' || coalesce(new.client_id, 'all'), false);
  return new;
end $$;
drop trigger if exists agent_log_broadcast on public.agent_log;
create trigger agent_log_broadcast after insert on public.agent_log for each row execute function public.agent_log_broadcast();

-- simulação: só com código de equipa, escreve uma corrida fictícia marcada simulated=true
create or replace function public.agent_simulate(p_token text, p_events jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare v_client text; v_run text := 'sim-' || to_char(now(), 'YYYYMMDDHH24MISS'); e jsonb; n int := 0;
begin
  select client_id into v_client from studio_tokens where token = p_token;
  if v_client is null then raise exception 'codigo_invalido' using errcode = '28000'; end if;
  if jsonb_array_length(p_events) > 60 then raise exception 'demasiados_eventos'; end if;
  for e in select * from jsonb_array_elements(p_events) loop
    insert into agent_log (run_id, client_id, slot, agent, to_agent, status, message, model, ms, cost_eur, simulated)
    values (v_run, v_client, nullif(e->>'slot','')::int, e->>'agent', e->>'to', coalesce(e->>'status','talk'),
            left(e->>'message', 280), 'simulado', nullif(e->>'ms','')::int, 0, true);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.agent_simulate(text, jsonb) from public;
grant execute on function public.agent_simulate(text, jsonb) to anon, authenticated;;
