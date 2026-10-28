-- Advisor: search_path fixo nos dois auxiliares novos.
alter function public._tp_eligible(guioes, date, boolean) set search_path = public;
alter function public._tp_prefs_clean(jsonb) set search_path = public;
