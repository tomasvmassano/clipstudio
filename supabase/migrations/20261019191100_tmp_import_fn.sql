-- 20261019191100 tmp_import_fn (exportado do Supabase a 28/10/2026; segredos tapados)
create or replace function public.tmp_import(token text, kind text, payload jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0;
begin
  if token <> '<IMPORT_TOKEN_REDACTED>' then raise exception 'denied'; end if;
  if kind = 'tx' then
    update reels r set transcript = x.t, hook = coalesce(nullif(split_part(x.t, '. ', 1), ''), r.hook), duration = x.dur, updated_at = now()
    from jsonb_to_recordset(payload) as x(id text, t text, lang text, dur real) where r.id = x.id;
    get diagnostics n = row_count;
  elsif kind = 'an' then
    insert into script_analysis (reel_id, language, hook, tese, alvo, formato, gatilho, estrutura, porque_viraliza, polemica, risco_plataforma, angulo_numeiro)
    select x.id, null, x.hook, x.tese, x.alvo, x.formato, x.gatilho, x.estrutura, x.porque_viraliza, x.polemica, x.risco_plataforma, x.angulo_numeiro
    from jsonb_to_recordset(payload) as x(id text, hook text, tese text, alvo text, formato text, gatilho text, estrutura text, porque_viraliza text, polemica int, risco_plataforma text, angulo_numeiro text)
    on conflict (reel_id) do update set hook=excluded.hook, tese=excluded.tese, alvo=excluded.alvo, formato=excluded.formato, gatilho=excluded.gatilho,
      estrutura=excluded.estrutura, porque_viraliza=excluded.porque_viraliza, polemica=excluded.polemica, risco_plataforma=excluded.risco_plataforma,
      angulo_numeiro=excluded.angulo_numeiro, analyzed_at=now();
    get diagnostics n = row_count;
  end if;
  return n;
end $$;
revoke all on function public.tmp_import(text, text, jsonb) from public;
grant execute on function public.tmp_import(text, text, jsonb) to anon;;
