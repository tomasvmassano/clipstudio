-- W1-08: nomes legíveis das capacidades para a página "As tuas permissões" (o registo não é sensível; a tabela continua fechada).
-- Rollback: drop function capability_labels();
create or replace function public.capability_labels() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, jsonb_build_object('label', coalesce(label, key), 'module', module)), '{}') from capabilities
$$;
revoke all on function public.capability_labels() from public, anon;
grant execute on function public.capability_labels() to authenticated;
