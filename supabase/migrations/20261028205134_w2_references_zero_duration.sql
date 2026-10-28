-- W2-04b: reels com duração 0 (desconhecida no scraper) violavam o check de reference_items.duracao_s. 0 passa a "sem duração".
-- Rollback: inverter o replace.
do $$
begin
  execute replace(pg_get_functiondef('public.reference_create(text,jsonb,text)'::regprocedure),
                  'round(r.duration)::integer)', 'nullif(least(round(r.duration)::integer, 7200), 0))');
end $$;
