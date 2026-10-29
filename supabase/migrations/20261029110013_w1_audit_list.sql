-- W1-09: histórico de ações por cliente (PRD R-05, CAP-07 parcial, FR-15-06 parcial; ADR-0015). Só leitura; audit_events continua append-only.
-- Rollback: drop function audit_list(text,text,uuid,timestamptz,timestamptz,bigint,integer); drop index audit_events_ws_id;
-- update capabilities set status = 'W1' where key = 'audit.read';

create index if not exists audit_events_ws_id on public.audit_events (workspace_id, id desc);
update public.capabilities set status = 'ativo' where key = 'audit.read';

create or replace function public.audit_list(p_ws text, p_action text default null, p_actor uuid default null,
                                             p_from timestamptz default null, p_to timestamptz default null,
                                             p_before bigint default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); lim integer := least(greatest(coalesce(p_limit, 50), 1), 200); rows jsonb; last_id bigint; n integer;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('audit.read', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'audit.read');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_action is not null and p_action !~ '^[a-z_]+(\.[a-z_]+)?$' then raise exception 'filtro_invalido' using errcode = '22023'; end if;
  with page as (
    select e.* from audit_events e
     where e.workspace_id = p_ws
       and (p_action is null or e.action = p_action or e.action like p_action || '.%')
       and (p_actor is null or e.actor_user_id = p_actor)
       and (p_from is null or e.at >= p_from) and (p_to is null or e.at < p_to)
       and (p_before is null or e.id < p_before)
     order by e.id desc limit lim
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'at', p.at, 'action', p.action, 'actor_kind', p.actor_kind,
           'actor', coalesce((select email from auth.users where id = p.actor_user_id), p.actor_label,
                             case p.actor_kind when 'engine' then 'Motor' when 'system' then 'Sistema' when 'legacy_code' then 'Código de equipa' end),
           'entity_type', p.entity_type, 'entity_id', p.entity_id, 'before', p.before, 'after', p.after, 'result', p.result) order by p.id desc), '[]'),
         min(p.id), count(*)
    into rows, last_id, n from page p;
  return jsonb_build_object('rows', rows, 'next_before', case when n = lim then last_id end,
    'actors', (select coalesce(jsonb_agg(jsonb_build_object('id', x.actor_user_id, 'label', coalesce(u.email, x.actor_label)) order by coalesce(u.email, x.actor_label)), '[]')
               from (select distinct on (actor_user_id) actor_user_id, actor_label from audit_events where workspace_id = p_ws and actor_user_id is not null order by actor_user_id, id desc) x
               left join auth.users u on u.id = x.actor_user_id),
    'actions', (select coalesce(jsonb_agg(a order by a), '[]') from (select distinct action a from audit_events where workspace_id = p_ws) s));
end $$;

revoke all on function public.audit_list(text,text,uuid,timestamptz,timestamptz,bigint,integer) from public, anon;
grant execute on function public.audit_list(text,text,uuid,timestamptz,timestamptz,bigint,integer) to authenticated;
