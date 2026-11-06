-- W10-13 · Comparar versões de um guião e restaurar (PRD FR-02-06, FR-05-06, FR-05-07; AGENTS §2.6, §6).
-- Expand (só aditivo, compatível com o código em main):
--   1. content_history devolve também formato e tema de cada versão (para o diff), a versão gravada (a mesma regra de
--      _content_recorded_version, W9-02), os ids da versão em vigor/aprovada e os restauros auditados. As chaves antigas ficam iguais.
--   2. content_restore_version mantém o caminho de sempre (content_save: scripts.edit, lock_version → PT409, editar uma
--      versão aprovada abre revisão nova e a aprovação fica presa à versão antiga) e passa a deixar um registo
--      'script.version_restored' no audit com a versão de origem. Nada é apagado nem reescrito.
-- Permissões: as mesmas (scripts.read para ler, scripts.edit para restaurar). Rollback no fim.

create or replace function public.content_history(p_id text, p_token text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g guioes; rv uuid;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.read', g.client_id, p_token, 'script.history', g.id);
  rv := public._content_recorded_version(g.id);
  return jsonb_build_object(
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'hooks', v.hooks, 'corpo', v.corpo, 'cta', v.cta,
                    'formato', v.formato, 'tema', v.tema,
                    'created_at', v.created_at, 'created_kind', v.created_kind, 'author', coalesce(v.created_label, u.email),
                    'is_current', v.id = g.current_version_id, 'is_approved', v.id = g.approved_version_id,
                    'is_recorded', v.id is not distinct from rv) order by v.version_no desc), '[]')
                 from content_versions v left join auth.users u on u.id = v.created_by where v.content_id = g.id),
    'transitions', (select coalesce(jsonb_agg(jsonb_build_object('kind', t.kind, 'from', t.from_status, 'to', t.to_status, 'reason', t.reason,
                    'at', t.at, 'actor', coalesce(t.actor_label, t.actor_kind),
                    'version_no', (select version_no from content_versions where id = t.version_id)) order by t.at desc, t.id desc), '[]')
                 from content_transitions t where t.content_id = g.id),
    'restores', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'actor', coalesce(e.actor_label, e.actor_kind),
                    'version_no', (e.after->>'version_no')::int) order by e.at desc, e.id desc), '[]')
                 from audit_events e where e.workspace_id = g.client_id and e.entity_type = 'guiao' and e.entity_id = g.id
                  and e.action = 'script.version_restored'),
    'current_version_id', g.current_version_id,
    'approved_version_id', g.approved_version_id,
    'recorded_version_id', rv);
end $$;

-- Restaurar uma versão antiga para a cópia de trabalho (o caminho de sempre, content_save) e auditar de onde veio.
create or replace function public.content_restore_version(p_id text, p_version uuid, p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare v content_versions; g guioes; a jsonb; fr text; cur int;
begin
  select * into v from content_versions where id = p_version and content_id = p_id;
  if v.id is null then raise exception 'versao_nao_encontrada' using errcode = 'P0002'; end if;
  select editorial_status, (select version_no from content_versions where id = x.current_version_id) into fr, cur from guioes x where x.id = p_id;
  -- content_save verifica scripts.edit, arquivo e conflito de edição antes de mudar o que quer que seja.
  g := public.content_save(p_id, jsonb_build_object('hooks', v.hooks, 'corpo', v.corpo, 'cta', coalesce(v.cta, ''),
                                                    'formato', v.formato, 'tema', v.tema), p_lock, p_token);
  a := public._content_actor(p_token);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'script.version_restored', 'guiao', g.id,
          jsonb_build_object('editorial_status', fr, 'current_version_no', cur),
          jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'editorial_status', g.editorial_status));
  return g;
end $$;

revoke all on function public.content_history(text,text), public.content_restore_version(text,uuid,integer,text) from public;
grant execute on function public.content_history(text,text), public.content_restore_version(text,uuid,integer,text) to anon, authenticated;

/* Rollback (sem perda de dados: os registos 'script.version_restored' ficam no audit):
   reaplicar content_history e content_restore_version de 20261028195656_w2_content_core.sql (a UI antiga só lê as chaves de sempre).
*/
