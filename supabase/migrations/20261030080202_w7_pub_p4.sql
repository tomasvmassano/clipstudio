-- Parte 4 de 4 de 20261030110100_w7_pub.sql (aplicada em produção como w7_pub_p4).

-- ───────────── FR-21-01: acrescentar conta de destino (fica "por ligar") ─────────────
create or replace function public.pub_account_add(p_ws text, p_platform text, p_handle text, p_label text default null, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); h text := lower(btrim(regexp_replace(coalesce(p_handle, ''), '^@', ''))); v_id text; acc accounts;
begin
  perform public._pub_require('social_accounts.manage', p_ws, p_token, 'pub.account_add', p_handle);
  if p_platform not in ('instagram', 'tiktok', 'youtube') then raise exception 'plataforma_invalida' using errcode = '22023', detail = 'Plataformas: instagram, tiktok, youtube.'; end if;
  if h !~ '^[a-z0-9._-]{1,60}$' then raise exception 'conta_invalida' using errcode = '22023', detail = 'Nome da conta sem @, só letras, números, ponto, hífen e sublinhado.'; end if;
  if exists (select 1 from accounts where platform = p_platform and lower(handle) = h and role = 'client' and client_id is distinct from p_ws) then
    raise exception 'conta_de_outro_cliente' using errcode = '22023', detail = 'Esta conta já pertence a outro cliente.'; end if;
  select * into acc from accounts where platform = p_platform and lower(handle) = h and client_id = p_ws and role = 'client';
  if acc.id is null then
    v_id := p_ws || '-' || case p_platform when 'instagram' then 'ig' when 'tiktok' then 'tt' else 'yt' end || '-' || h;
    if exists (select 1 from accounts where accounts.id = v_id) then raise exception 'conta_invalida' using errcode = '22023', detail = 'Já existe uma conta com este identificador.'; end if;
    insert into accounts (id, client_id, role, platform, handle, label)
    values (v_id, p_ws, 'client', p_platform, h, coalesce(nullif(btrim(p_label), ''), h || ' · ' || initcap(p_platform))) returning * into acc;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'pub.account_added', 'account', acc.id, to_jsonb(acc));
  end if;
  insert into social_accounts (account_id, workspace_id) values (acc.id, p_ws) on conflict do nothing;
  return jsonb_build_object('id', acc.id, 'platform', acc.platform, 'handle', acc.handle, 'label', acc.label, 'connection_state',
    (select connection_state from social_accounts where account_id = acc.id));
end $$;

-- ───────────── FR-21-04: ligar a linhagem gravada pelo publicador (uso interno, service_role) ─────────────
-- O publicador futuro chama _perf_record_lineage com correlation_id = pub_publications.correlation_id e depois esta função.
-- Valida que a linha é deste cliente, desta conta, desta versão e desta publicação aprovada.
create or replace function public._pub_link_lineage(p_pub uuid, p_lineage_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p pub_publications; l publication_lineage;
begin
  select * into p from pub_publications where id = p_pub for update;
  if p.id is null then raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
  if p.status <> 'aprovada' then raise exception 'sem_aprovacao' using errcode = '42501', detail = 'Só publicações aprovadas se ligam à linhagem.'; end if;
  select * into l from publication_lineage where id = p_lineage_id;
  if l.id is null or l.workspace_id <> p.workspace_id or l.account_id <> p.account_id or l.content_version_id is distinct from p.content_version_id
     or l.correlation_id is distinct from p.correlation_id or l.lineage_mode <> 'gravada' then
    raise exception 'linhagem_nao_corresponde' using errcode = '22023'; end if;
  if p.lineage_id = l.id then return jsonb_build_object('id', p.id, 'lineage_id', l.id, 'linked', false); end if;
  if p.lineage_id is not null then raise exception 'ja_ligada' using errcode = '22023'; end if;
  perform set_config('pub.linking', p.id::text, true);
  update pub_publications set lineage_id = l.id where id = p.id;
  perform set_config('pub.linking', '', true);
  return jsonb_build_object('id', p.id, 'lineage_id', l.id, 'linked', true);
end $$;

-- ───────────── privilégios ─────────────
revoke all on function public.social_accounts_guard(), public._pub_seed_limits(uuid), public._pub_norm(text), public._pub_variant_diff(jsonb, jsonb),
  public._pub_elements_clean(jsonb), public._pub_snapshot(pub_publications), public._pub_hash(pub_publications), public._pub_policy(text),
  public._pub_missing(pub_publications), public._pub_actor_side(text, uuid), public.pub_publications_guard(), public.pub_approvals_guard(),
  public.pub_variants_guard(), public._pub_conflicts(pub_publications, boolean), public._pub_blocking(jsonb), public._pub_require(text, text, text, text, text),
  public._pub_json(pub_publications, text), public._pub_limits_json(text), public._pub_link_lineage(uuid, bigint) from public, anon, authenticated;
grant execute on function public._pub_link_lineage(uuid, bigint) to service_role;
revoke all on function public.pub_calendar(text, date, date, text), public.pub_content_options(text, text, text), public.pub_variant_save(text, jsonb, text),
  public.pub_variant_archive(text, uuid, text), public.pub_save(text, uuid, jsonb, int, text), public.pub_cancel(text, uuid, text, text),
  public.pub_approve(text, uuid, int, text), public.pub_approve_batch(text, jsonb, text), public.pub_policy_save(text, jsonb, text),
  public.pub_limit_save(text, text, jsonb, text), public.pub_account_add(text, text, text, text, text) from public;
grant execute on function public.pub_calendar(text, date, date, text), public.pub_content_options(text, text, text), public.pub_variant_save(text, jsonb, text),
  public.pub_variant_archive(text, uuid, text), public.pub_save(text, uuid, jsonb, int, text), public.pub_cancel(text, uuid, text, text),
  public.pub_approve(text, uuid, int, text), public.pub_approve_batch(text, jsonb, text), public.pub_policy_save(text, jsonb, text),
  public.pub_limit_save(text, text, jsonb, text), public.pub_account_add(text, text, text, text, text) to anon, authenticated;
-- anon só passa com código de equipa válido e a flag "para todos"; sem publishing.* no código de equipa, só lê.

/* Rollback (compatível; contas criadas por pub_account_add ficam em accounts). A chave de capacidade volta a 2 segmentos só
   depois de apagar as 3 capacidades de 3 segmentos: alter table capabilities drop constraint capabilities_key_check;
   alter table capabilities add constraint capabilities_key_check check (key ~ '^[a-z_]+\.[a-z_]+$');
   drop function public.pub_account_add(text, text, text, text, text), public.pub_limit_save(text, text, jsonb, text), public.pub_policy_save(text, jsonb, text),
     public.pub_approve_batch(text, jsonb, text), public.pub_approve(text, uuid, int, text), public.pub_cancel(text, uuid, text, text),
     public.pub_save(text, uuid, jsonb, int, text), public.pub_variant_archive(text, uuid, text), public.pub_variant_save(text, jsonb, text),
     public.pub_content_options(text, text, text), public.pub_calendar(text, date, date, text), public._pub_link_lineage(uuid, bigint),
     public._pub_limits_json(text), public._pub_json(pub_publications, text), public._pub_require(text, text, text, text, text), public._pub_blocking(jsonb),
     public._pub_conflicts(pub_publications, boolean);
   delete from role_capabilities where capability in ('publishing.approve', 'publishing.republish.approve', 'publishing.policy.manage', 'publishing.limits.manage')
      or (capability = 'publishing.schedule' and role = 'manager');
   update capabilities set status = 'W6' where key in ('publishing.schedule', 'social_accounts.manage', 'publishing.approve', 'publishing.republish.approve',
      'publishing.policy.manage', 'publishing.limits.manage');
   delete from feature_flags where key = 'pub.planning'; delete from feature_flag_defs where key = 'pub.planning';
-- contract posterior (depois de exportar): drop table public.pub_approvals, public.pub_publications, public.pub_variants, public.pub_approval_policies,
   public.pub_platform_limits, public.social_accounts; drop function public.pub_variants_guard(), public.pub_approvals_guard(), public.pub_publications_guard(),
   public._pub_actor_side(text, uuid), public._pub_missing(pub_publications), public._pub_policy(text), public._pub_hash(pub_publications),
   public._pub_snapshot(pub_publications), public._pub_elements_clean(jsonb), public._pub_variant_diff(jsonb, jsonb), public._pub_norm(text),
   public._pub_seed_limits(uuid), public.social_accounts_guard(); */
