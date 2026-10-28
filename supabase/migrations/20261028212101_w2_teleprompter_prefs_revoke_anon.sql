-- As preferências no servidor são só para contas individuais; o código de equipa guarda no próprio dispositivo.
revoke all on function public.tp_prefs_get(text), public.tp_prefs_set(text,jsonb) from anon;
