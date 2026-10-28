-- W2-01b: escritas diretas nas colunas antigas mantêm o estado novo coerente. Rollback: drop trigger guioes_legacy_sync on guioes; drop function guioes_legacy_sync();
create or replace function public.guioes_legacy_sync() returns trigger language plpgsql set search_path = public as $$
begin
  if new.editorial_status = old.editorial_status and (new.status is distinct from old.status or new.validado is distinct from old.validado) then
    new.editorial_status := case when new.status = 'rejeitado' then 'rejected' when new.validado then 'approved'
                                 when old.editorial_status in ('approved','rejected') then 'in_review' else old.editorial_status end;
    new.approved_version_id := case when new.editorial_status = 'approved' then coalesce(new.current_version_id, old.approved_version_id) else old.approved_version_id end;
    if new.editorial_status <> 'approved' and old.editorial_status = 'approved' then new.approved_version_id := null; end if;
  end if;
  if new.production_status = old.production_status and new.gravado is distinct from old.gravado then
    new.production_status := case when new.gravado then 'recorded' else 'not_started' end;
  end if;
  return new;
end $$;
create trigger guioes_legacy_sync before update on public.guioes for each row execute function public.guioes_legacy_sync();
revoke all on function public.guioes_legacy_sync() from public, anon, authenticated;
