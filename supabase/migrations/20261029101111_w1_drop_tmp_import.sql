-- W1: remove a função de importação temporária (token fixo no corpo). Nenhum código do main a usa (verificado em app e motor).
-- Rollback: recriar a partir de 20261019191100_tmp_import_fn.sql (sem o token, que nunca esteve no repositório).
drop function if exists public.tmp_import(text, text, jsonb);
