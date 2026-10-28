-- W1 revisão de segurança (2026-10-28).
-- 1) guiao_update: editar conteúdo de um guião validado invalida a validação (AGENTS §2.6: aprovado é imutável);
--    status só aceita 'aprovado'/'rejeitado' (antes qualquer texto passava só com scripts.edit).
-- 2) invite_member: convidar staff da agência exige ser dono da agência (alinha servidor e UI; ADR-0001).
-- Rollback: reaplicar as definições de 20261028185510_w1_fix_desempenho_role_and_update_caps e 20261028185124_w1_authorize_split.

create or replace function public.guiao_update(p_id text, p_patch jsonb, p_token text default null)
returns guioes
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid(); g public.guioes; before jsonb; v_kind text; v_label text; need text[] := '{}'; c text;
  content_change boolean := p_patch ?| array['hooks','corpo','formato','tema','n'];
  invalidates boolean;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if p_patch ? 'status' and p_patch->>'status' not in ('aprovado','rejeitado') then raise exception 'estado_invalido' using errcode = '22023'; end if;

  if p_patch ? 'validado' then need := array_append(need, 'scripts.approve'); end if;
  if p_patch->>'status' = 'rejeitado' or p_patch ? 'motivo_rejeicao' then need := array_append(need, 'scripts.reject'); end if;
  if p_patch->>'status' = 'aprovado' then need := array_append(need, 'scripts.approve'); end if;
  if p_patch ? 'gravado' then need := array_append(need, 'recording.confirm'); end if;
  if content_change then need := array_append(need, 'scripts.edit'); end if;
  if cardinality(need) = 0 then raise exception 'nada_a_alterar' using errcode = '22023'; end if;

  if uid is not null then v_kind := 'user'; select email into v_label from auth.users where id = uid;
  elsif public.legacy_ws(p_token) is not null then v_kind := 'legacy_code'; select label into v_label from studio_tokens where token = p_token;
  else raise exception 'nao_autenticado' using errcode = '28000'; end if;

  foreach c in array need loop
    if not public.ws_can(c, g.client_id, p_token) then
      raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'actor_kind', v_kind, 'workspace_id', g.client_id, 'action', 'script.update', 'entity_id', g.id, 'capability', c);
      raise exception 'sem_permissao' using errcode = '42501';
    end if;
  end loop;

  -- Conteúdo novo num guião validado: a validação deixa de valer (a menos que o mesmo pedido valide de novo).
  invalidates := content_change and g.validado and not (p_patch ? 'validado');

  before := jsonb_build_object('status', g.status, 'validado', g.validado, 'gravado', g.gravado, 'motivo_rejeicao', g.motivo_rejeicao,
                               'hooks', g.hooks, 'corpo', g.corpo, 'formato', g.formato, 'tema', g.tema, 'n', g.n);
  if p_patch ? 'corpo' or p_patch ? 'hooks' then
    g.history := (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select x from jsonb_array_elements(g.history || jsonb_build_array(jsonb_build_object('hooks', g.hooks, 'corpo', g.corpo, 'at', g.updated_at, 'validado', g.validado))) x
      order by 1 desc limit 10) s);
  end if;

  update guioes set
    status = coalesce(p_patch->>'status', status),
    motivo_rejeicao = case when p_patch ? 'motivo_rejeicao' then p_patch->>'motivo_rejeicao' else motivo_rejeicao end,
    validado = case when invalidates then false else coalesce((p_patch->>'validado')::boolean, validado) end,
    validado_em = case when invalidates then null
                       when p_patch ? 'validado' then (case when (p_patch->>'validado')::boolean then now() else null end)
                       else validado_em end,
    gravado = coalesce((p_patch->>'gravado')::boolean, gravado),
    gravado_em = case when p_patch ? 'gravado' then (case when (p_patch->>'gravado')::boolean then now() else null end) else gravado_em end,
    hooks = coalesce(p_patch->'hooks', hooks),
    corpo = coalesce(p_patch->>'corpo', corpo),
    formato = coalesce(p_patch->>'formato', formato),
    tema = coalesce(p_patch->>'tema', tema),
    n = coalesce((p_patch->>'n')::int, n),
    history = g.history,
    updated_at = now()
  where id = p_id returning * into g;

  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, v_kind, v_label, g.client_id,
          case when p_patch ? 'validado' then 'script.approval' when p_patch ? 'gravado' then 'recording.confirm'
               when p_patch->>'status' = 'rejeitado' then 'script.rejected' else 'script.update' end,
          'guiao', g.id, before, case when invalidates then p_patch || jsonb_build_object('validacao_anulada', true) else p_patch end);
  return g;
end $function$;

create or replace function public.invite_member(p_ws text, p_email text, p_role text, p_affiliation text default 'client_staff')
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); v_org uuid; my_role text; v_id uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'email_invalido' using errcode = '22023'; end if;
  select organization_id into v_org from clients where id = p_ws and status = 'active';
  if v_org is null or not _authorize('team.invite', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'invitation.create');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_affiliation not in ('agency_staff','client_staff') or ws_role_rank(p_role) = 0 then raise exception 'papel_invalido' using errcode = '22023'; end if;
  if not is_agency_owner(uid) then
    -- Só o dono da agência traz staff da agência (que ganha agency_membership ao aceitar).
    if p_affiliation = 'agency_staff' then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select workspace_role into my_role from workspace_access where user_id = uid and workspace_id = p_ws and status = 'active';
    if ws_role_rank(p_role) > ws_role_rank(my_role) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end if;
  insert into invitations (organization_id, workspace_id, email, invited_as, workspace_role, created_by)
  values (v_org, p_ws, lower(p_email), p_affiliation, p_role, uid) returning id into v_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', v_org, p_ws, 'invitation.create', 'invitation', v_id::text, jsonb_build_object('email', lower(p_email), 'role', p_role, 'affiliation', p_affiliation));
  return v_id;
end $function$;
