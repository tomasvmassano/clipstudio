-- scripts/backup/fingerprint.sql: impressão digital do catálogo para comparar a origem com o restauro (QA-15).
-- Uma linha por objeto: categoria|identidade|md5 da definição. Os esquemas cobertos são os da app (public) e os
-- objetos que as migrações criam nos esquemas da plataforma (auth, storage, cron, realtime): políticas, RLS e dados.
-- Só lê o catálogo; não cria nada na base.
\pset tuples_only on
\pset format unaligned
with s(n) as (values ('public'), ('auth'), ('storage'), ('cron'), ('realtime'), ('extensions'))
select x from (
  -- funções e procedimentos (definição completa, security definer, search_path e privilégios)
  select 'function|' || p.oid::regprocedure::text || '|' || md5(pg_get_functiondef(p.oid) || coalesce(p.proacl::text, '')) x
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace join s on s.n = n.nspname
  where p.prokind in ('f', 'p') and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  -- tabelas: colunas (nome, tipo, not null, default, gerada), RLS ligada/forçada e privilégios
  select 'table|' || c.oid::regclass::text || '|' || md5(coalesce((
           select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' || a.attgenerated::text
                             || ':' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), ''), ',' order by a.attnum)
           from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
           where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), '') || coalesce(c.relacl::text, ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace join s on s.n = n.nspname where c.relkind in ('r', 'p')
  union all
  select 'rls|' || c.oid::regclass::text || '|' || c.relrowsecurity || ':' || c.relforcerowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace join s on s.n = n.nspname where c.relkind in ('r', 'p')
  union all
  select 'view|' || c.oid::regclass::text || '|' || md5(pg_get_viewdef(c.oid) || coalesce(c.relacl::text, '') || coalesce(array_to_string(c.reloptions, ','), ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace join s on s.n = n.nspname where c.relkind in ('v', 'm')
  union all
  select 'policy|' || schemaname || '.' || tablename || '.' || policyname || '|'
         || md5(permissive || cmd || roles::text || coalesce(qual, '') || '/' || coalesce(with_check, ''))
  from pg_policies join s on s.n = schemaname
  union all
  select 'trigger|' || t.tgrelid::regclass::text || '.' || t.tgname || '|' || md5(pg_get_triggerdef(t.oid) || t.tgenabled::text)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace join s on s.n = n.nspname
  where not t.tgisinternal
  union all
  select 'index|' || schemaname || '.' || indexname || '|' || md5(indexdef) from pg_indexes join s on s.n = schemaname
  union all
  select 'constraint|' || co.conrelid::regclass::text || '.' || co.conname || '|' || md5(translate(pg_get_constraintdef(co.oid), '()', '') || co.convalidated)
  from pg_constraint co join pg_namespace n on n.oid = co.connamespace join s on s.n = n.nspname where co.conrelid <> 0
  -- (sem parênteses: o Postgres reescreve (a AND b) AND c como a AND b AND c ao recarregar, com o mesmo significado)
  union all
  -- sequências: posição atual (last_value é nulo se nunca foi usada) e privilégios
  select 'sequence|' || q.schemaname || '.' || q.sequencename || '|' || coalesce(q.last_value::text, 'nunca usada') || ':' || q.increment_by
         || ':' || coalesce((select c.relacl::text from pg_class c where c.oid = (q.schemaname || '.' || q.sequencename)::regclass), '')
  from pg_sequences q join s on s.n = q.schemaname
  union all
  select 'schema|' || n.nspname || '|' || md5(coalesce(n.nspacl::text, '')) from pg_namespace n join s on s.n = n.nspname
  union all
  select 'default_acl|' || coalesce(d.defaclnamespace::regnamespace::text, '-') || '.' || d.defaclobjtype::text || '.' || d.defaclrole::regrole::text
         || '|' || md5(d.defaclacl::text) from pg_default_acl d
  union all
  select 'publication|' || pubname || '|' || schemaname || '.' || tablename from pg_publication_tables
  union all
  select 'extension|' || extname || '|' || extversion from pg_extension
  union all
  select 'cron|' || jobname || '|' || md5(schedule || command || active) from cron.job
) f order by 1;
