-- Fixa o search_path das funções auxiliares novas que o aviso de segurança do Supabase acusou (function_search_path_mutable).
-- Só aditivo: não muda o corpo de nenhuma função. Corre só sobre as que existirem (três vêm de W2-08, noutro ramo).

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('_rework_defaults', '_pub_blocking', '_learn_params', '_perf_params', '_perf_age_seconds', '_perf_ts', '_perf_mech',
                         '_job_title_templates', '_block_key_ok', '_block_slug', '_content_block_keys', '_perf_families', '_perf_match',
                         '_pub_norm', '_pub_snapshot', '_learn_variants_valid')
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public', f.sig);
  end loop;
end $$;

/* Rollback (compatível): para cada função acima, alter function <assinatura> reset search_path; */
