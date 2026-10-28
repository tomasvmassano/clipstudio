-- 20261028185611 w1_denials_to_db_log
-- Negações não podem ir para audit_events: o RAISE que se segue desfaz a transação.
-- Passam a RAISE LOG estruturado (logs do Postgres no Supabase), prefixo 'audit_denied'.
do $$ declare src text; begin
  select pg_get_functiondef('public.guiao_update(text,jsonb,text)'::regprocedure) into src;
  src := replace(src,
    E'      insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, result)\n      values (uid, v_kind, v_label, g.client_id, ''script.update'', ''guiao'', g.id, jsonb_build_object(''capability'', c), ''denied'');',
    E'      raise log ''audit_denied %'', jsonb_build_object(''actor_user_id'', uid, ''actor_kind'', v_kind, ''workspace_id'', g.client_id, ''action'', ''script.update'', ''entity_id'', g.id, ''capability'', c);');
  if position('audit_denied' in src) = 0 then raise exception 'patch guiao_update falhou'; end if;
  execute src;

  select pg_get_functiondef('public.invite_member(text,text,text,text)'::regprocedure) into src;
  src := replace(src,
    E'    insert into audit_events (actor_user_id, actor_kind, workspace_id, action, entity_type, result) values (uid, ''user'', p_ws, ''invitation.create'', ''invitation'', ''denied'');',
    E'    raise log ''audit_denied %'', jsonb_build_object(''actor_user_id'', uid, ''workspace_id'', p_ws, ''action'', ''invitation.create'');');
  if position('audit_denied' in src) = 0 then raise exception 'patch invite_member falhou'; end if;
  execute src;
end $$;
