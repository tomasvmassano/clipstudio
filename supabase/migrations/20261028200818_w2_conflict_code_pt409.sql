-- W2-01c: o conflito de edição usava SQLSTATE 40001 (serialization_failure). O PostgREST trata 40001 como
-- caso especial e a ligação ficava pendurada sem resposta. PT409 é a convenção do PostgREST para HTTP 409.
-- Rollback: trocar 'PT409' por '40001' da mesma forma.
do $$
declare f text;
begin
  foreach f in array array['public.content_save(text,jsonb,integer,text)', 'public.content_transition(text,text,text,integer,text)'] loop
    execute replace(pg_get_functiondef(f::regprocedure), '''conflito_edicao'' using errcode = ''40001''', '''conflito_edicao'' using errcode = ''PT409''');
  end loop;
end $$;
