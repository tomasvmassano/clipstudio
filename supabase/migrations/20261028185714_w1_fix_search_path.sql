-- 20261028185714 w1_fix_search_path
alter function public.audit_events_immutable() set search_path = public;
alter function public.ws_role_rank(text) set search_path = public;
