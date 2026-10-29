-- W4-03 (expand): o trigger de preenchimento lê accounts e reels, que o engine_worker não pode ler diretamente
-- (o teste w4_engine_isolation apanhou o 42501 nas escritas do worker). Passa a security definer; só corre como trigger.
-- Rollback: alter function public._engine_fill_client() security invoker;
alter function public._engine_fill_client() security definer;
revoke execute on function public._engine_fill_client() from public, anon, authenticated;
