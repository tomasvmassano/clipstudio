-- Parte 1 de 2 de 20261030120300_w7_learn_team_privacy_costs.sql (aplicada em produção como w7_learn_team_privacy_costs_p1).
-- W7 · Cargos como modelos de permissões (BIZ-08), exportação dos próprios dados e pedido de eliminação (FR-14-05) e
-- custo por guião, vídeo e publicação (FR-10-05). Expand: 2 capacidades, 3 flags, colunas novas em invitations, 1 tabela
-- fechada à API, 1 trigger novo e funções novas. NÃO muda invite_member, accept_invitations, grant_set nem _authorize:
--  * O convite com cargo é uma função nova (invite_member_with_title) que chama invite_member e guarda o cargo e as
--    exceções sugeridas escolhidas. Ao aceitar, um trigger em invitations (accepted_at passa a ter valor) aplica o cargo
--    ao membro e cria as exceções explícitas, com o autor do convite como responsável e auditoria. O cargo nunca dá nada
--    sozinho (AGENTS §2.4): o que dá acesso é o papel e cada exceção explícita, revogável na consola de permissões.
--  * A exportação só inclui dados da própria pessoa nos clientes a que ainda tem acesso; o histórico sai sem antes/depois
--    (pode ter dados do cliente). O pedido de eliminação fica registado para o dono da agência; nada se apaga sozinho.
--  * Custos só com costs.read (por defeito dono e admin do cliente; o código de equipa nunca). Atribuição ao guião: o
--    custo da execução do motor repartido pelos guiões que gerou (pelo custo por posição no agent_log quando existe,
--    senão em partes iguais); à publicação: o custo do guião repartido pelas suas publicações. Vídeo: indisponível até
--    haver custos de edição e render registados.
-- Rollback no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('privacy.manage', 'Agência', 'A', array['org'], 'ativo', 'Ver e tratar pedidos de eliminação de dados'),
  ('profile.export', 'Perfil', 'B', array['own'], 'ativo', 'Exportar os próprios dados (cada pessoa, só os seus)')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
insert into role_capabilities (scope, role, capability) values ('org', 'agency_owner', 'privacy.manage') on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('team.job_titles', 'Cargos no convite', 'Equipa', 'ws', 'owner',
   'Ao convidar escolhe-se o cargo (Editor, Clipper, Copywriter, SMM...), que sugere o papel e exceções típicas ajustáveis. O cargo não dá permissões sozinho (BIZ-08).'),
  ('profile.data_export', 'Exportar os meus dados', 'Perfil', 'ws', 'owner',
   'No perfil: descarregar os próprios dados em JSON e pedir a eliminação ao dono da agência (FR-14-05).'),
  ('costs.content', 'Custos por guião e publicação', 'Custos', 'ws', 'owner',
   'Custo dos agentes por guião e por publicação, tendência mensal e exportação CSV, só para quem tem costs.read (FR-10-05).')
on conflict (key) do nothing;

-- ───────────── BIZ-08: cargos como modelos ─────────────
alter table public.invitations
  add column if not exists job_title text check (job_title is null or char_length(job_title) <= 60),
  add column if not exists job_title_key text,
  add column if not exists suggested_grants text[] not null default '{}';

-- Modelos (PRD §3, matriz por especialidade). Ponto de partida igual para todos os clientes; sem papéis personalizados
-- (BIZ-08). grants = exceções sugeridas além do papel, desmarcáveis no convite.
create or replace function public._job_title_templates() returns jsonb
language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'clipper', 'label', 'Clipper', 'role', 'contributor', 'grants', '[]'::jsonb,
                       'modules', 'Clipping, Biblioteca, Tarefas, Revisão, Desempenho'),
    jsonb_build_object('key', 'smm', 'label', 'Social Media Manager', 'role', 'contributor', 'grants', jsonb_build_array('calendar.schedule', 'publishing.schedule'),
                       'modules', 'Calendário, Publicações, Biblioteca, Desempenho', 'note', 'Publicar só com exceção própria.'),
    jsonb_build_object('key', 'videografo', 'label', 'Videógrafo', 'role', 'contributor', 'grants', '[]'::jsonb,
                       'modules', 'Produção, Guiões, Teleprompter, Tarefas'),
    jsonb_build_object('key', 'editor', 'label', 'Editor', 'role', 'contributor', 'grants', jsonb_build_array('media.share'),
                       'modules', 'Edição, Biblioteca, Revisão, Tarefas'),
    jsonb_build_object('key', 'estratega', 'label', 'Estratega', 'role', 'contributor', 'grants', jsonb_build_array('references.manage', 'agents.rehearse', 'learn.read'),
                       'modules', 'Fontes, Referências, Guiões, Desempenho'),
    jsonb_build_object('key', 'copywriter', 'label', 'Copywriter', 'role', 'contributor', 'grants', '[]'::jsonb,
                       'modules', 'Fontes, Guiões, Referências, Tarefas'),
    jsonb_build_object('key', 'gestor_projeto', 'label', 'Gestor de projeto', 'role', 'contributor', 'grants', jsonb_build_array('tasks.manage', 'calendar.schedule'),
                       'modules', 'Dashboard, Tarefas, Calendário, Revisão'),
    jsonb_build_object('key', 'diretor_criativo', 'label', 'Diretor criativo', 'role', 'contributor',
                       'grants', jsonb_build_array('scripts.approve', 'scripts.reject', 'review.approve'),
                       'modules', 'Guiões, Revisão, Referências', 'note', 'Aprovar só quando autorizado.'),
    jsonb_build_object('key', 'gestor_conta', 'label', 'Gestor de conta', 'role', 'reviewer', 'grants', jsonb_build_array('calendar.schedule', 'learn.read'),
                       'modules', 'Dashboard, Calendário, Relatórios, Revisão'))
$$;

-- Modelos para o formulário de convite: papel sugerido, exceções sugeridas e o que quem convida pode dar.
create or replace function public.job_title_templates(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); owner boolean := public.is_agency_owner(uid); pm boolean;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('team.invite', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._flag_on('team.job_titles', p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os cargos no convite ainda não estão ligados neste cliente.'; end if;
  pm := public._authorize('permissions.manage', p_ws, uid);
  return jsonb_build_object('can_grant', pm,
    'templates', (select jsonb_agg(t || jsonb_build_object(
        'role_capabilities', (select coalesce(jsonb_agg(rc.capability order by rc.capability), '[]') from role_capabilities rc where rc.scope = 'ws' and rc.role = t->>'role'),
        'grant_options', (select coalesce(jsonb_agg(jsonb_build_object('key', g, 'label', coalesce(k.label, g),
              'in_role', exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = t->>'role' and rc.capability = g),
              'grantable', pm and (owner or public._authorize(g, p_ws, uid)))), '[]')
            from jsonb_array_elements_text(t->'grants') g left join capabilities k on k.key = g)))
      from jsonb_array_elements(public._job_title_templates()) t));
end $$;

-- Convidar com cargo: invite_member (mesmas regras: teto do papel, só o dono traz staff da agência) + cargo + exceções.
-- As exceções são subconjunto das sugeridas pelo cargo, só com permissions.manage e só o que quem convida tem (R-12).
create or replace function public.invite_member_with_title(p_ws text, p_email text, p_role text, p_affiliation text, p_job_title text,
                                                           p_grants text[] default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); owner boolean := public.is_agency_owner(uid); t jsonb; gs text[]; g text; v_id uuid;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._authorize('team.invite', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if not public._flag_on('team.job_titles', p_ws) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os cargos no convite ainda não estão ligados neste cliente.'; end if;
  select x into t from jsonb_array_elements(public._job_title_templates()) x where x->>'key' = p_job_title;
  if t is null then raise exception 'cargo_invalido' using errcode = '22023', detail = 'Escolhe um cargo da lista.'; end if;
  gs := array(select distinct x from unnest(coalesce(p_grants, '{}')) x where x is not null order by 1);
  foreach g in array gs loop
    if not (t->'grants') ? g then raise exception 'excecao_invalida' using errcode = '22023', detail = format('%s não é uma exceção sugerida para este cargo.', g); end if;
    -- já incluída no papel escolhido: não é exceção
    if exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = p_role and rc.capability = g) then gs := array_remove(gs, g); continue; end if;
    if not public._authorize('permissions.manage', p_ws, uid) then raise exception 'sem_permissao' using errcode = '42501', detail = 'Dar exceções precisa de "Gerir permissões".'; end if;
    if not owner and not public._authorize(g, p_ws, uid) then raise exception 'acima_do_teto' using errcode = '42501'; end if;
  end loop;
  v_id := public.invite_member(p_ws, p_email, p_role, p_affiliation);
  update invitations set job_title = t->>'label', job_title_key = t->>'key', suggested_grants = gs where id = v_id;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, after)
  values (uid, 'user', (select organization_id from clients where id = p_ws), p_ws, 'invitation.job_title', 'invitation', v_id::text,
          jsonb_build_object('job_title', t->>'label', 'role', p_role, 'grants', to_jsonb(gs)));
  return v_id;
end $$;

-- Ao aceitar: cargo no membro e exceções explícitas. Volta a verificar quem convidou (pode ter perdido o direito).
create or replace function public._invitation_apply_title() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text; inviter uuid := new.created_by; ok boolean; owner boolean; gid bigint; v_role text;
begin
  if new.workspace_id is null or new.accepted_by is null then return new; end if;
  if new.job_title is null and cardinality(new.suggested_grants) = 0 then return new; end if;
  select workspace_role into v_role from workspace_access where workspace_id = new.workspace_id and user_id = new.accepted_by;
  if v_role is null then return new; end if;
  if new.job_title is not null then
    update workspace_access set job_title = new.job_title where workspace_id = new.workspace_id and user_id = new.accepted_by;
  end if;
  owner := public.is_agency_owner(inviter);
  foreach g in array new.suggested_grants loop
    ok := inviter is not null and (owner or (public._authorize('permissions.manage', new.workspace_id, inviter) and public._authorize(g, new.workspace_id, inviter)));
    if not ok
       or exists (select 1 from role_capabilities rc where rc.scope = 'ws' and rc.role = v_role and rc.capability = g)
       or exists (select 1 from permission_grants p where p.workspace_id = new.workspace_id and p.user_id = new.accepted_by and p.capability = g
                  and p.revoked_at is null and (p.expires_at is null or p.expires_at > now())) then
      insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, after)
      values (inviter, 'system', 'convite com cargo', new.organization_id, new.workspace_id, 'grant.skipped', 'member', new.accepted_by::text,
              jsonb_build_object('capability', g, 'invitation_id', new.id,
                                 'motivo', case when not ok then 'quem convidou já não pode dar esta exceção' else 'já incluída ou com exceção ativa' end));
      continue;
    end if;
    insert into permission_grants (workspace_id, user_id, capability, effect, reason, created_by)
    values (new.workspace_id, new.accepted_by, g, 'allow', left(format('Sugerida pelo cargo %s no convite', coalesce(new.job_title, '?')), 500), inviter)
    returning id into gid;
    insert into audit_events (actor_user_id, actor_kind, actor_label, organization_id, workspace_id, action, entity_type, entity_id, before, after)
    values (inviter, 'system', 'convite com cargo', new.organization_id, new.workspace_id, 'grant.set', 'member', new.accepted_by::text, null,
            jsonb_build_object('capability', g, 'effect', 'allow', 'grant_id', gid, 'source', 'job_title', 'job_title', new.job_title, 'invitation_id', new.id));
  end loop;
  return new;
end $$;
drop trigger if exists invitations_apply_title on public.invitations;
create trigger invitations_apply_title after update of accepted_at on public.invitations
  for each row when (old.accepted_at is null and new.accepted_at is not null) execute function public._invitation_apply_title();

-- ───────────── FR-14-05: exportação e pedido de eliminação ─────────────
create table if not exists public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  kind text not null default 'eliminacao' check (kind in ('eliminacao')),
  reason text check (reason is null or char_length(reason) <= 1000),
  status text not null default 'pendente' check (status in ('pendente', 'tratado', 'recusado', 'cancelado')),
  resolution text check (resolution is null or char_length(resolution) <= 1000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null
);
create unique index if not exists privacy_requests_one_open on public.privacy_requests (user_id, kind) where status = 'pendente';
alter table public.privacy_requests enable row level security;
revoke all on public.privacy_requests from anon, authenticated;

-- A exportação está disponível se a flag estiver ligada para a pessoa em algum dos clientes a que tem acesso.
create or replace function public._data_export_on(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_access a join clients c on c.id = a.workspace_id and c.status = 'active'
                 where a.user_id = p_uid and a.status = 'active' and public._flag_on('profile.data_export', a.workspace_id))
      or exists (select 1 from agency_memberships m join clients c on c.organization_id = m.organization_id and c.status = 'active'
                 where m.user_id = p_uid and m.status = 'active' and m.agency_role = 'agency_owner' and public._flag_on('profile.data_export', c.id))
$$;

create or replace function public._privacy_req_json(r privacy_requests) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'status', r.status, 'reason', r.reason, 'resolution', r.resolution,
                            'created_at', r.created_at, 'resolved_at', r.resolved_at)
$$;

create or replace function public.my_data_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  return jsonb_build_object('available', public._data_export_on(uid),
    'requests', coalesce((select jsonb_agg(public._privacy_req_json(r) order by r.created_at desc) from privacy_requests r where r.user_id = uid), '[]'));
end $$;

create or replace function public.my_data_export() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._data_export_on(uid) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'A exportação dos teus dados ainda não está ligada para ti.'; end if;
  with ws as (select a.workspace_id id, c.name, a.workspace_role, a.affiliation_type, a.job_title, a.created_at
              from workspace_access a join clients c on c.id = a.workspace_id where a.user_id = uid and a.status = 'active')
  select jsonb_build_object(
    'format', 'clipstudio.my_data.v1', 'exported_at', now(),
    'scope', 'Só os teus dados, nos clientes a que tens acesso hoje. O histórico de ações não inclui o conteúdo antes e depois (pode ter dados do cliente).',
    'profile', (select jsonb_build_object('user_id', u.id, 'email', u.email, 'created_at', u.created_at, 'last_sign_in_at', u.last_sign_in_at,
                  'display_name', p.display_name, 'timezone', p.timezone, 'theme', p.theme, 'preferred_workspace', p.preferred_workspace)
                from auth.users u left join profiles p on p.user_id = u.id where u.id = uid),
    'agency', coalesce((select jsonb_agg(jsonb_build_object('organization', o.name, 'role', m.agency_role, 'status', m.status, 'since', m.created_at))
                        from agency_memberships m join organizations o on o.id = m.organization_id where m.user_id = uid), '[]'),
    'workspaces', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', workspace_role, 'affiliation', affiliation_type,
                              'job_title', job_title, 'since', created_at) order by name) from ws), '[]'),
    'script_comments', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'workspace_id', x.workspace_id, 'content_id', x.content_id, 'block', x.block,
                              'body', x.body, 'created_at', x.created_at, 'resolved_at', x.resolved_at) order by x.created_at)
                         from content_comments x where x.author_id = uid and x.workspace_id in (select id from ws)
                           and public._authorize('scripts.read', x.workspace_id, uid)), '[]'),
    'task_comments', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'workspace_id', x.workspace_id, 'task_id', x.task_id, 'body', x.body,
                              'created_at', x.created_at) order by x.created_at)
                         from task_comments x where x.author_id = uid and x.workspace_id in (select id from ws)
                           and public._authorize('tasks.read', x.workspace_id, uid)), '[]'),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'workspace_id', t.workspace_id, 'title', t.title, 'status', t.status,
                              'priority', t.priority, 'due_at', t.due_at, 'assigned_to_me', t.assignee_id = uid, 'created_by_me', t.created_by = uid,
                              'created_at', t.created_at, 'completed_at', t.completed_at) order by t.created_at)
                       from tasks t where (t.assignee_id = uid or t.created_by = uid) and t.workspace_id in (select id from ws)
                         and public._authorize('tasks.read', t.workspace_id, uid)), '[]'),
    'audit_trail', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'workspace_id', e.workspace_id,
                              'entity_type', e.entity_type, 'entity_id', e.entity_id, 'result', e.result) order by e.at)
                       from (select * from audit_events where actor_user_id = uid and (workspace_id is null or workspace_id in (select id from ws))
                             order by at desc limit 5000) e), '[]'),
    'privacy_requests', coalesce((select jsonb_agg(public._privacy_req_json(r) order by r.created_at) from privacy_requests r where r.user_id = uid), '[]'))
  into res;
  insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
  values (uid, 'user', (select email from auth.users where id = uid), 'privacy.data_exported', 'user', uid::text,
          jsonb_build_object('comments', jsonb_array_length(res->'script_comments') + jsonb_array_length(res->'task_comments'),
                             'tasks', jsonb_array_length(res->'tasks'), 'audit', jsonb_array_length(res->'audit_trail')));
  return res;
end $$;

-- Pedir eliminação: fica registado para o dono da agência tratar conforme a política. Nada se apaga sozinho. Idempotente.
create or replace function public.my_data_deletion_request(p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r privacy_requests;
begin
  if uid is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  if not public._data_export_on(uid) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'O pedido de eliminação ainda não está ligado para ti.'; end if;
  select * into r from privacy_requests where user_id = uid and kind = 'eliminacao' and status = 'pendente';
  if r.id is null then
    insert into privacy_requests (user_id, email, reason) values (uid, (select email from auth.users where id = uid), nullif(left(btrim(coalesce(p_reason, '')), 1000), ''))
    returning * into r;
    insert into audit_events (actor_user_id, actor_kind, actor_label, action, entity_type, entity_id, after)
    values (uid, 'user', r.email, 'privacy.deletion_requested', 'privacy_request', r.id::text, jsonb_build_object('reason', r.reason));
  end if;
  return public._privacy_req_json(r);
end $$;

-- Quem pertence a esta agência (staff ou equipa de um dos seus clientes).
create or replace function public._privacy_in_org(p_uid uuid, p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from agency_memberships m where m.user_id = p_uid and m.organization_id = p_org)
      or exists (select 1 from workspace_access a join clients c on c.id = a.workspace_id where a.user_id = p_uid and c.organization_id = p_org)
$$;

create or replace function public.privacy_requests_admin() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); org uuid := (select organization_id from agency_memberships where user_id = uid and status = 'active' order by created_at limit 1);
begin
  if org is null or not public._org_can('privacy.manage', org, uid) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return jsonb_build_object('items', coalesce((select jsonb_agg(public._privacy_req_json(r) || jsonb_build_object('email', r.email, 'user_id', r.user_id,
            'workspaces', (select coalesce(jsonb_agg(c.name order by c.name), '[]') from workspace_access a join clients c on c.id = a.workspace_id
                           where a.user_id = r.user_id and c.organization_id = org))
          order by (r.status = 'pendente') desc, r.created_at desc)
        from privacy_requests r where public._privacy_in_org(r.user_id, org)), '[]'));
end $$;
