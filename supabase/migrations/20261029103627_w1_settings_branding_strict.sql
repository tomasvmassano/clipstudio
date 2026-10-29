-- W1-07: as políticas do bucket branding exigem caminho válido (sem isso authorize(cap, null) avaliaria capacidades de agência).
-- Rollback: recriar as políticas de 20261029103605.
drop policy if exists branding_read on storage.objects;
create policy branding_read on storage.objects for select to authenticated
  using (bucket_id = 'branding' and public._branding_ws(name) is not null
         and (public.authorize('scripts.read', public._branding_ws(name)) or public.authorize('team.read', public._branding_ws(name))));
drop policy if exists branding_insert on storage.objects;
create policy branding_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'branding' and public._branding_ws(name) is not null and public.authorize('settings.manage', public._branding_ws(name)));
drop policy if exists branding_update on storage.objects;
create policy branding_update on storage.objects for update to authenticated
  using (bucket_id = 'branding' and public._branding_ws(name) is not null and public.authorize('settings.manage', public._branding_ws(name)))
  with check (bucket_id = 'branding' and public._branding_ws(name) is not null and public.authorize('settings.manage', public._branding_ws(name)));
drop policy if exists branding_delete on storage.objects;
create policy branding_delete on storage.objects for delete to authenticated
  using (bucket_id = 'branding' and public._branding_ws(name) is not null and public.authorize('settings.manage', public._branding_ws(name)));
