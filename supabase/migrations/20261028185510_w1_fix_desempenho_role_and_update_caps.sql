-- 20261028185510 w1_fix_desempenho_role_and_update_caps
-- desempenho: números do cliente só das contas role='client' (as referências agora pertencem ao workspace)
do $$ declare src text; begin
  select pg_get_functiondef('public.desempenho(text,text,text)'::regprocedure) into src;
  src := replace(src, '  where a.client_id = p_client and (p_account is null or a.id = p_account)',
                      '  where a.client_id = p_client and a.role = ''client'' and (p_account is null or a.id = p_account)');
  src := replace(src, '  where a.client_id = p_client group by a.id order by a.platform, a.handle',
                      '  where a.client_id = p_client and a.role = ''client'' group by a.id order by a.platform, a.handle');
  if position('a.role = ''client'' and (p_account' in src) = 0 or position('a.role = ''client'' group by a.id' in src) = 0 then
    raise exception 'patch falhou'; end if;
  execute src;
end $$;

-- guiao_update: array_append em vez de || com literal
do $$ declare src text; begin
  select pg_get_functiondef('public.guiao_update(text,jsonb,text)'::regprocedure) into src;
  src := regexp_replace(src, 'need := need \|\| ''([a-z_.]+)'';', 'need := array_append(need, ''\1'');', 'g');
  if position('need || ' in src) > 0 then raise exception 'patch falhou'; end if;
  execute src;
end $$;
