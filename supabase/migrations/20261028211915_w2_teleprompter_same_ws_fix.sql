-- recording_same_ws é partilhado por recording_session_items (sem version_id) e takes: ler version_id via jsonb.
create or replace function public.recording_same_ws() returns trigger language plpgsql set search_path = public as $$
declare v uuid := (to_jsonb(new)->>'version_id')::uuid;
begin
  if new.workspace_id is distinct from (select workspace_id from recording_sessions where id = new.session_id)
     or new.workspace_id is distinct from (select client_id from guioes where id = new.content_id)
     or (v is not null and new.workspace_id is distinct from (select workspace_id from content_versions where id = v)) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.workspace_id, new.session_id, new.content_id) is distinct from (old.workspace_id, old.session_id, old.content_id) then
    raise exception 'imutavel' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.recording_same_ws() from public, anon, authenticated;
