-- 20261028185703 w1_close_is_agency_owner
revoke all on function public.is_agency_owner(uuid) from public, anon, authenticated;
revoke all on function public.ws_role_rank(text) from public, anon, authenticated;
revoke all on function public.audit_events_immutable() from public, anon, authenticated;
