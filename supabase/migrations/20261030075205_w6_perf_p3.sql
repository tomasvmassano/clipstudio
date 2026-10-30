-- Parte 3 de 3 de 20261030010100_w6_perf.sql (aplicada em produção como w6_perf_p3).

-- R-16: corrigir a origem à mão (motivo obrigatório, auditado).
create or replace function public.perf_origin_set(p_ws text, p_account text, p_external_id text, p_origin text, p_reason text, p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); l publication_lineage;
begin
  perform public._content_require('analytics.manage', p_ws, p_token, 'perf.origin_set', p_external_id);
  if p_origin not in ('sistema', 'externo') then raise exception 'origem_invalida' using errcode = '22023', detail = 'Origem: sistema ou externo.'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 500 then
    raise exception 'motivo_obrigatorio' using errcode = '22023', detail = 'Explica porque mudas a origem (3 a 500 caracteres).'; end if;
  if not exists (select 1 from accounts where id = p_account and client_id = p_ws and role = 'client') then
    raise exception 'conta_nao_encontrada' using errcode = 'P0002'; end if;
  select * into l from publication_lineage where workspace_id = p_ws and account_id = p_account and external_id = p_external_id for update;
  if l.id is null then
    if not exists (select 1 from reels where client_id = p_ws and id = p_external_id and account_id = p_account) then
      raise exception 'publicacao_nao_encontrada' using errcode = 'P0002'; end if;
    perform public.perf_sync_lineage(p_ws);
    select * into l from publication_lineage where workspace_id = p_ws and account_id = p_account and external_id = p_external_id for update;
  end if;
  update publication_lineage set origin = p_origin, origin_source = 'manual', origin_reason = btrim(p_reason), updated_at = now() where id = l.id;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'perf.origin_set', 'publication', p_account || '/' || p_external_id,
          jsonb_build_object('origin', l.origin, 'origin_source', l.origin_source),
          jsonb_build_object('origin', p_origin, 'origin_source', 'manual', 'reason', btrim(p_reason)));
  return (select to_jsonb(x) - 'workspace_id' from publication_lineage x where id = l.id);
end $$;

-- R-18: o publicador grava a linhagem no momento da publicação. Valida tudo contra o próprio cliente; idempotente por
-- (conta, id externo): repetir devolve a linha existente sem duplicar. Uso interno (publicador com service_role) e RPC.
create or replace function public._perf_record_lineage(p_ws text, p jsonb, p_actor jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare acc accounts; g guioes; cv content_versions; l publication_lineage; parent publication_lineage; st edit_style_versions;
  ext text := btrim(coalesce(p->>'external_id', '')); hi int; mech text; tz text; pub timestamptz; created boolean := false;
begin
  if jsonb_typeof(coalesce(p, 'null')) <> 'object' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  select * into acc from accounts where id = p->>'account_id' and client_id = p_ws and role = 'client';
  if acc.id is null then raise exception 'conta_nao_encontrada' using errcode = '22023', detail = 'A conta não é deste cliente.'; end if;
  if ext = '' or char_length(ext) > 200 then raise exception 'id_externo_invalido' using errcode = '22023'; end if;
  select * into l from publication_lineage where workspace_id = p_ws and account_id = acc.id and external_id = ext for update;
  if l.lineage_mode = 'gravada' then
    return (to_jsonb(l) - 'workspace_id') || jsonb_build_object('created', false);
  end if;
  select * into g from guioes where id = p->>'content_id' and client_id = p_ws;
  if g.id is null then raise exception 'conteudo_nao_encontrado' using errcode = '22023', detail = 'O conteúdo não é deste cliente.'; end if;
  select * into cv from content_versions where id = nullif(p->>'content_version_id', '')::uuid and content_id = g.id and workspace_id = p_ws;
  if cv.id is null then raise exception 'versao_invalida' using errcode = '22023', detail = 'Indica a versão exata que foi publicada.'; end if;
  hi := nullif(p->>'hook_index', '')::int;
  if hi is not null and (hi < 0 or hi >= jsonb_array_length(cv.hooks)) then raise exception 'hook_invalido' using errcode = '22023'; end if;
  mech := coalesce(p->>'hook_mechanism', case when hi is not null then cv.hooks->hi->>'mecanismo' end);
  if nullif(btrim(coalesce(p->>'hook_mechanism', '')), '') is not null and public._perf_mech(mech) is null then
    raise exception 'mecanismo_invalido' using errcode = '22023', detail = 'Mecanismos: contra, numero, ego, confissao, segredo, pergunta.'; end if;
  if p ? 'edit_style_key' and nullif(p->>'edit_style_key', '') is not null then
    select * into st from edit_style_versions where workspace_id = p_ws and key = p->>'edit_style_key' and version = nullif(p->>'edit_style_version', '')::int;
    if st.key is null then raise exception 'estilo_invalido' using errcode = '22023', detail = 'Estilo e versão têm de existir neste cliente.'; end if;
  end if;
  if coalesce(p->>'source_type', 'guiao') not in ('guiao', 'fonte_longa', 'telemovel', 'lifestyle') then raise exception 'tipo_fonte_invalido' using errcode = '22023'; end if;
  if nullif(p->>'parent_lineage_id', '') is not null then
    select * into parent from publication_lineage where id = (p->>'parent_lineage_id')::bigint and workspace_id = p_ws;
    if parent.id is null then raise exception 'origem_republicacao_invalida' using errcode = '22023'; end if;
  end if;
  pub := coalesce(nullif(p->>'published_at', '')::timestamptz, now());
  tz := (select coalesce(timezone, 'Asia/Dubai') from clients where id = p_ws);
  if l.id is not null then delete from publication_lineage where id = l.id; end if;   -- a inferida dá lugar à gravada
  insert into publication_lineage (workspace_id, account_id, platform, external_id, url, published_at, origin, origin_source, lineage_mode,
    content_id, content_version_id, version_no, hook_index, hook_text, hook_mechanism, formato, maquina, tema, edit_style_key, edit_style_version,
    persona_phrase, asset_ref, duration_s, source_type, generation, parent_lineage_id, tier, local_tz, local_hour, correlation_id,
    recorded_kind, recorded_label)
  values (p_ws, acc.id, acc.platform, ext, left(p->>'url', 1000), pub, 'sistema', 'publicador', 'gravada',
    g.id, cv.id, cv.version_no, hi, left(coalesce(case when hi is not null then cv.hooks->hi->>'text' end, p->>'hook_text'), 500), public._perf_mech(mech),
    left(coalesce(cv.formato, g.formato), 60), left(g.maquina, 60), left(coalesce(cv.tema, g.tema), 300), st.key, st.version,
    nullif(left(p->>'persona_phrase', 200), ''), nullif(left(p->>'asset_ref', 500), ''), nullif(p->>'duration_s', '')::numeric,
    coalesce(p->>'source_type', 'guiao'), case when parent.id is not null then coalesce(parent.generation, 0) + 1 else coalesce(nullif(p->>'generation', '')::int, 0) end,
    parent.id, (select tier from perf_accounts where account_id = acc.id), tz, extract(hour from pub at time zone tz)::int,
    nullif(left(p->>'correlation_id', 200), ''), coalesce(p_actor->>'kind', 'system'), p_actor->>'label')
  returning * into l;
  created := true;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after, correlation_id)
  values ((p_actor->>'uid')::uuid, coalesce(p_actor->>'kind', 'system'), p_actor->>'label', p_ws, 'perf.lineage_recorded', 'publication',
          acc.id || '/' || ext, null, to_jsonb(l) - 'workspace_id', l.correlation_id);
  return (to_jsonb(l) - 'workspace_id') || jsonb_build_object('created', created);
end $$;

create or replace function public.perf_record_lineage(p_ws text, p_lineage jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token);
begin
  perform public._content_require('publishing.publish', p_ws, p_token, 'perf.lineage_record', p_lineage->>'external_id');
  return public._perf_record_lineage(p_ws, p_lineage, a);
end $$;

-- Recolha: guarda uma leitura por cada atualização do scraper (reels.updated_at). Idempotente. Corre de hora a hora.
create or replace function public.perf_capture(p_ws text) returns int
language sql security definer set search_path = public as $$
  with ins as (
    insert into perf_readings (workspace_id, reel_id, captured_at, views, likes, comments, shares, source)
    select r.client_id, r.id, r.updated_at, r.views, r.likes, r.comments, r.shares, 'scraper'
    from reels r join accounts a on a.id = r.account_id and a.client_id = r.client_id and a.role = 'client'
    where r.client_id = p_ws and r.updated_at is not null
    on conflict do nothing returning 1)
  select count(*)::int from ins
$$;

create or replace function public.perf_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record; res jsonb := '{}';
begin
  for c in select id from clients where status = 'active' order by id loop
    begin
      res := res || jsonb_build_object(c.id, jsonb_build_object('readings', public.perf_capture(c.id), 'lineage', public.perf_sync_lineage(c.id)));
    exception when others then
      raise log 'perf_tick_failed %', jsonb_build_object('workspace_id', c.id, 'error', sqlerrm);
      res := res || jsonb_build_object(c.id, jsonb_build_object('error', sqlstate));
    end;
  end loop;
  return res;
end $$;

create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'perf-tick') then
    perform cron.schedule('perf-tick', '17 * * * *', 'select public.perf_tick()');
  end if;
end $$;

revoke all on function public.perf_lineage_guard(), public._perf_params(), public._perf_age_seconds(text), public._perf_ts(text), public._perf_mech(text),
  public._perf_inferred(text), public._perf_pubs(text), public._perf_snapshots(text), public._perf_index(text), public._perf_families(),
  public._perf_match(jsonb, jsonb), public._perf_rows(text), public._perf_record_lineage(text, jsonb, jsonb),
  public.perf_sync_lineage(text), public.perf_capture(text), public.perf_tick() from public, anon, authenticated;
grant execute on function public._perf_record_lineage(text, jsonb, jsonb), public.perf_sync_lineage(text), public.perf_capture(text), public.perf_tick()
  to service_role;
revoke all on function public.perf_center(text, text), public.perf_publications(text, jsonb, text), public.perf_breakdown(text, text, text, jsonb, text),
  public.perf_levers(text, boolean, text), public.perf_account_set(text, text, jsonb, text),
  public.perf_origin_set(text, text, text, text, text, text), public.perf_record_lineage(text, jsonb, text) from public;
grant execute on function public.perf_center(text, text), public.perf_publications(text, jsonb, text), public.perf_breakdown(text, text, text, jsonb, text),
  public.perf_levers(text, boolean, text), public.perf_account_set(text, text, jsonb, text),
  public.perf_origin_set(text, text, text, text, text, text), public.perf_record_lineage(text, jsonb, text) to anon, authenticated;

/* Rollback (compatível, nada do que existia mudou):
   select cron.unschedule('perf-tick');
   drop function public.perf_tick(), public.perf_capture(text), public.perf_record_lineage(text, jsonb, text), public._perf_record_lineage(text, jsonb, jsonb),
     public.perf_origin_set(text, text, text, text, text, text), public.perf_sync_lineage(text), public.perf_account_set(text, text, jsonb, text),
     public.perf_levers(text, boolean, text), public.perf_breakdown(text, text, text, jsonb, text), public.perf_publications(text, jsonb, text),
     public.perf_center(text, text), public._perf_rows(text), public._perf_match(jsonb, jsonb), public._perf_families(), public._perf_index(text),
     public._perf_snapshots(text), public._perf_pubs(text), public._perf_inferred(text), public._perf_mech(text), public._perf_ts(text),
     public._perf_age_seconds(text), public._perf_params();
   delete from feature_flags where key = 'perf.center'; delete from feature_flag_defs where key = 'perf.center';
   delete from role_capabilities where capability = 'analytics.manage'; update capabilities set status = 'W6' where key = 'analytics.manage';
-- contract posterior (só depois de o código deixar de depender): drop table public.publication_lineage, public.perf_readings, public.perf_accounts;
   drop function public.perf_lineage_guard(); */
