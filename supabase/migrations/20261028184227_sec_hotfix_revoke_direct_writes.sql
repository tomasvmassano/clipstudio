-- 20261028184227 sec_hotfix_revoke_direct_writes (exportado do Supabase a 28/10/2026; segredos tapados)
-- SEC-HOTFIX-001 (28/10/2026). Escrita direta via REST nunca é necessária: a app escreve por RPC,
-- o motor liga-se como owner. Tira INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER a anon e authenticated.
-- Rollback: grant insert, update, delete on <tabela> to authenticated (não recomendado).
do $$ declare r record; begin
  for r in select c.relname, c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r','v','m','p') loop
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated', r.relname);
  end loop;
end $$;

-- vistas internas do motor (v_*): só o motor as usa, por ligação direta. Fecham à API pública.
do $$ declare r record; begin
  for r in select viewname from pg_views where schemaname = 'public' and viewname like 'v\_%' loop
    execute format('revoke select on public.%I from anon, authenticated', r.viewname);
  end loop;
end $$;

-- tabelas novas não herdam escrita por defeito
alter default privileges in schema public revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;

-- função de trigger não deve ser chamável pela API
revoke execute on function public.agent_log_broadcast() from public, anon, authenticated;;
