-- W10-16 · tentativas recusadas em audit_events (PRD R-05, FR-13-05, CAP-05, CAP-07, OPS-08; ADR-0066).
-- Problema: as RPCs recusam com RAISE (42501), o que desfaz a transação; um insert em audit_events no mesmo pedido perde-se.
-- Por isso continuavam só com RAISE LOG 'audit_denied …' (logs do Postgres). No Supabase não há transação autónoma
-- (dblink/pg_background) e o Vercel não mantém um ouvinte de pg_notify. Solução: quem recebe o 42501 (o browser, através do
-- fetch do cliente Supabase, ou a rota /api no servidor) faz um SEGUNDO pedido, com a mesma sessão, a audit_denied_record,
-- que grava a recusa numa transação própria. O RAISE LOG fica como segunda via.
-- Expand (aditivo, compatível com o main): três índices parciais e duas funções novas; nenhuma tabela nem coluna nova,
-- nenhuma função existente alterada. Sem tabela nova, scripts/backup/scope.sql não muda.
--
-- Rollback:
--   drop function if exists public.audit_denials_list(text, bigint, integer);
--   drop function if exists public.audit_denied_record(text, text, text, text, text, text, text);
--   drop index if exists public.audit_events_denied_actor; drop index if exists public.audit_events_denied_ws;
--   drop index if exists public.audit_events_denied_org;
--   (as linhas 'access.denied' já gravadas ficam: audit_events é append-only.)

-- limite por pessoa (30 por minuto) e listas por cliente / por organização
create index if not exists audit_events_denied_actor on public.audit_events (actor_user_id, at desc) where action = 'access.denied';
create index if not exists audit_events_denied_ws on public.audit_events (workspace_id, id desc) where action = 'access.denied';
create index if not exists audit_events_denied_org on public.audit_events (organization_id, id desc)
  where action = 'access.denied' and workspace_id is null;

-- Grava a recusa que a própria sessão acabou de receber.
--  · Quem: sempre auth.uid() (nunca um id vindo do browser); anónimo e código de equipa recusados.
--  · Onde: se a pessoa tem acesso ativo ao cliente (ou é dona da agência), a linha fica no histórico desse cliente.
--    Se não tem (tentativa a outro cliente, cliente inexistente), fica fora de qualquer cliente (workspace_id null,
--    after.target_ws) e só a agência dona do cliente a vê: o admin do cliente B nunca fica a saber quem é a pessoa do cliente A,
--    e ninguém de fora escreve no histórico de B.
--  · A resposta é igual nos três casos (não revela se o cliente existe nem se a pessoa lá está).
--  · Limite: 30 por pessoa por minuto; acima disso não grava (fica só no RAISE LOG) e devolve recorded=false.
--  · É uma declaração de quem foi recusado: a pessoa só se pode "acusar" a si própria. Quando vem a capacidade, confirma-se
--    agora se a pessoa de facto não a tem (after.verified).
--  · Nunca grava tokens: o id do recurso é limpo e o browser/servidor nunca enviam p_token.
create or replace function public.audit_denied_record(p_ws text, p_action text, p_entity text default null, p_code text default '42501',
                                                      p_capability text default null, p_via text default 'browser',
                                                      p_correlation text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); v_ws text; v_org uuid; v_member boolean := false; v_aff text := 'none'; v_cap text; v_verified boolean;
  v_entity text; v_corr text; v_hdr jsonb; v_ip text; v_ua text; v_day text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD');
  v_preview boolean := false; v_after jsonb; n int;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_action is null or p_action !~ '^[a-z0-9_.:/-]{1,80}$' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  if coalesce(p_code, '42501') <> '42501' then raise exception 'pedido_invalido' using errcode = '22023'; end if;
  v_ws := case when p_ws ~ '^[a-z0-9_-]{1,60}$' then p_ws end;
  v_entity := nullif(left(regexp_replace(coalesce(p_entity, ''), '[^A-Za-z0-9_.:/-]', '', 'g'), 120), '');
  v_corr := case when p_correlation ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then lower(p_correlation)
                 else gen_random_uuid()::text end;

  -- limite por pessoa, serializado para dois separadores não passarem os dois
  perform pg_advisory_xact_lock(hashtextextended('audit_denied:' || uid::text, 0));
  select count(*) into n from audit_events where action = 'access.denied' and actor_user_id = uid and at > now() - interval '1 minute';
  if n >= 30 then
    raise log 'audit_denied_throttled %', jsonb_build_object('actor_user_id', uid, 'workspace_id', v_ws, 'action', p_action);
    return jsonb_build_object('recorded', false, 'reason', 'limite', 'correlation_id', v_corr);
  end if;

  if v_ws is not null then
    select organization_id into v_org from clients where id = v_ws;
    if v_org is not null then
      if exists (select 1 from agency_memberships m where m.user_id = uid and m.organization_id = v_org
                 and m.agency_role = 'agency_owner' and m.status = 'active') then
        v_member := true; v_aff := 'agency_owner';
      else
        select a.affiliation_type into v_aff from workspace_access a
         where a.user_id = uid and a.workspace_id = v_ws and a.status = 'active' and (a.expires_at is null or a.expires_at > now());
        v_member := v_aff is not null;
        if not v_member then
          v_aff := case when exists (select 1 from agency_memberships m where m.user_id = uid and m.organization_id = v_org and m.status = 'active')
                        then 'agency_staff_sem_atribuicao' else 'none' end;
        end if;
      end if;
    end if;
  end if;

  select key into v_cap from capabilities where key = p_capability;
  if v_cap is not null and v_member then v_verified := not public._authorize(v_cap, v_ws, uid); end if;
  if v_member then
    v_preview := exists (select 1 from access_previews where user_id = uid and workspace_id = v_ws and expires_at > now());
  end if;

  -- IP e browser só como pseudónimo do dia (sha256 truncado, muda à meia-noite UTC); nunca o valor em claro
  begin v_hdr := nullif(current_setting('request.headers', true), '')::jsonb; exception when others then v_hdr := null; end;
  v_ip := nullif(btrim(coalesce(v_hdr->>'cf-connecting-ip', v_hdr->>'x-real-ip', split_part(v_hdr->>'x-forwarded-for', ',', 1))), '');
  v_ua := nullif(v_hdr->>'user-agent', '');

  v_after := jsonb_strip_nulls(jsonb_build_object(
    'attempted', p_action, 'capability', v_cap, 'verified', v_verified, 'code', '42501',
    'via', case when p_via in ('browser', 'api') then p_via else 'browser' end,
    'affiliation', v_aff, 'scope', case when v_member then 'cliente' else 'fora' end,
    'target_ws', case when not v_member then v_ws end, 'preview', case when v_preview then true end,
    'ip_hash', case when v_ip is not null then left(encode(sha256(convert_to(v_day || ':ip:' || v_ip, 'UTF8')), 'hex'), 16) end,
    'ua_hash', case when v_ua is not null then left(encode(sha256(convert_to(v_day || ':ua:' || v_ua, 'UTF8')), 'hex'), 16) end));

  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after, result, correlation_id)
  values (uid, 'user', v_org, case when v_member then v_ws end, 'access.denied', case when v_entity is not null then 'recurso' end, v_entity,
          v_after, 'denied', v_corr);
  raise log 'audit_denied %', v_after || jsonb_build_object('actor_user_id', uid, 'workspace_id', v_ws, 'recorded', true);
  return jsonb_build_object('recorded', true, 'correlation_id', v_corr);
end $$;
revoke all on function public.audit_denied_record(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.audit_denied_record(text, text, text, text, text, text, text) to authenticated;

-- Tentativas recusadas de um cliente (quem, o quê, quando).
--  · audit.read no cliente: as recusas de quem tem acesso ao cliente.
--  · audit.read da organização dona do cliente (agency_owner/agency_admin): também as tentativas de fora (outros clientes,
--    staff sem atribuição). Nunca para quem está a pré-visualizar outro papel neste cliente.
create or replace function public.audit_denials_list(p_ws text, p_before bigint default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); lim integer := least(greatest(coalesce(p_limit, 50), 1), 200); v_org uuid;
  can_ws boolean; can_org boolean; rows jsonb; last_id bigint; n integer;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  select organization_id into v_org from clients where id = p_ws;
  can_ws := public._authorize('audit.read', p_ws, uid);
  can_org := v_org is not null and public._mfa_ok(uid)
    and not exists (select 1 from access_previews where user_id = uid and workspace_id = p_ws and expires_at > now())
    and exists (select 1 from agency_memberships m join role_capabilities rc on rc.scope = 'org' and rc.role = m.agency_role and rc.capability = 'audit.read'
                where m.user_id = uid and m.organization_id = v_org and m.status = 'active');
  if not (can_ws or can_org) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'audit.denials');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  with page as (
    select e.* from audit_events e
     where e.action = 'access.denied'
       and ((can_ws and e.workspace_id = p_ws)
            or (can_org and e.workspace_id is null and e.organization_id = v_org and e.after->>'target_ws' = p_ws))
       and (p_before is null or e.id < p_before)
     order by e.id desc limit lim
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'at', p.at,
           'actor', coalesce((select email from auth.users where id = p.actor_user_id), p.actor_label),
           'affiliation', p.after->>'affiliation', 'scope', p.after->>'scope', 'attempted', p.after->>'attempted',
           'capability', p.after->>'capability', 'verified', (p.after->>'verified')::boolean, 'via', p.after->>'via',
           'preview', coalesce((p.after->>'preview')::boolean, false), 'entity_id', p.entity_id, 'correlation_id', p.correlation_id)
           order by p.id desc), '[]'),
         min(p.id), count(*)
    into rows, last_id, n from page p;
  return jsonb_build_object('rows', rows, 'next_before', case when n = lim then last_id end, 'includes_outside', can_org);
end $$;
revoke all on function public.audit_denials_list(text, bigint, integer) from public, anon;
grant execute on function public.audit_denials_list(text, bigint, integer) to authenticated;
