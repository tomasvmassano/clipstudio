-- W2-07 · Campanha, responsável, plataformas e etiquetas no guião (FR-02-03) e fila do teleprompter filtrável por
-- campanha e responsável (FR-03-01). Expand: tabela, colunas novas com valor por defeito, capacidade e funções novas;
-- _tp_session_row passa a incluir os campos novos (só acrescenta chaves). Rollback no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('projects.manage', 'Guiões', 'M', array['ws'], 'ativo', 'Gerir campanhas e séries')
on conflict (key) do update set status = 'ativo', label = excluded.label;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'projects.manage'), ('ws', 'workspace_admin', 'projects.manage'), ('ws', 'manager', 'projects.manage')
on conflict do nothing;

-- Campanhas e séries (PRD §3: Workspace → Projects/Campaigns → Content)
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  name text not null check (char_length(trim(name)) between 1 and 80),
  kind text not null default 'campanha' check (kind in ('campanha', 'serie')),
  status text not null default 'ativa' check (status in ('ativa', 'arquivada')),
  starts_on date,
  ends_on date check (ends_on is null or starts_on is null or ends_on >= starts_on),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists projects_ws_name on public.projects (workspace_id, lower(trim(name)));
alter table public.projects enable row level security;
revoke all on public.projects from anon, authenticated;   -- só pelas RPCs

alter table public.guioes add column if not exists project_id uuid references public.projects(id);
alter table public.guioes add column if not exists owner_id uuid references auth.users(id) on delete set null;
alter table public.guioes add column if not exists tags text[] not null default '{}';
alter table public.guioes add column if not exists platforms text[] not null default '{}';
create index if not exists guioes_project on public.guioes (project_id) where project_id is not null;
create index if not exists guioes_owner on public.guioes (owner_id) where owner_id is not null;

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done','automation_error','script_mention','script_comment',
   'script_assigned'));

-- Quem pode ficar responsável por guiões neste cliente: quem tem acesso e pode editar guiões.
create or replace function public.content_owners(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.read', p_ws, p_token, 'script.owners', null);
  return (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'email', u.email, 'label', coalesce(nullif(p.display_name, ''), u.email)) order by coalesce(nullif(p.display_name, ''), u.email)), '[]')
          from auth.users u left join profiles p on p.user_id = u.id
          where (exists (select 1 from workspace_access a where a.user_id = u.id and a.workspace_id = p_ws)
                 or exists (select 1 from agency_memberships m join clients c on c.organization_id = m.organization_id
                            where m.user_id = u.id and c.id = p_ws and m.agency_role = 'agency_owner'))
            and public._authorize('scripts.edit', p_ws, u.id));
end $$;

create or replace function public.projects_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.read', p_ws, p_token, 'project.list', null);
  return jsonb_build_object(
    'can_manage', public.ws_can('projects.manage', p_ws, p_token),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name, 'kind', pr.kind, 'status', pr.status,
        'starts_on', pr.starts_on, 'ends_on', pr.ends_on,
        'scripts', (select count(*) from guioes g where g.project_id = pr.id and g.editorial_status <> 'archived'))
        order by pr.status, lower(pr.name)) from projects pr where pr.workspace_id = p_ws), '[]'));
end $$;

-- Criar (p_id nulo) ou mudar uma campanha/série. Arquivar não tira os guiões da campanha; só deixa de aparecer para escolher.
create or replace function public.project_save(p_ws text, p_id uuid, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); old projects; pr projects; nm text := nullif(trim(p_fields->>'name'), '');
begin
  perform public._content_require('projects.manage', p_ws, p_token, 'project.save', p_id::text);
  if p_id is null then
    if nm is null then raise exception 'nome_obrigatorio' using errcode = '22023', detail = 'Dá um nome à campanha.'; end if;
    begin
      insert into projects (workspace_id, name, kind, starts_on, ends_on)
      values (p_ws, nm, coalesce(nullif(p_fields->>'kind', ''), 'campanha'), nullif(p_fields->>'starts_on', '')::date, nullif(p_fields->>'ends_on', '')::date)
      returning * into pr;
    exception
      when unique_violation then raise exception 'nome_repetido' using errcode = '22023', detail = 'Já há uma campanha com esse nome.';
      when check_violation then raise exception 'campanha_invalida' using errcode = '22023', detail = 'Tipo ou datas inválidos.';
    end;
  else
    select * into old from projects where id = p_id and workspace_id = p_ws for update;
    if old.id is null then raise exception 'campanha_nao_encontrada' using errcode = 'P0002'; end if;
    begin
      update projects set
        name = coalesce(nm, name),
        kind = coalesce(nullif(p_fields->>'kind', ''), kind),
        status = coalesce(nullif(p_fields->>'status', ''), status),
        starts_on = case when p_fields ? 'starts_on' then nullif(p_fields->>'starts_on', '')::date else starts_on end,
        ends_on = case when p_fields ? 'ends_on' then nullif(p_fields->>'ends_on', '')::date else ends_on end,
        updated_at = now()
      where id = p_id returning * into pr;
    exception
      when unique_violation then raise exception 'nome_repetido' using errcode = '22023', detail = 'Já há uma campanha com esse nome.';
      when check_violation then raise exception 'campanha_invalida' using errcode = '22023', detail = 'Tipo, estado ou datas inválidos.';
    end;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when p_id is null then 'project.created' else 'project.updated' end,
          'project', pr.id::text, to_jsonb(old), to_jsonb(pr));
  return public.projects_list(p_ws, p_token);
end $$;

-- Campanha, responsável, plataformas e etiquetas de um guião. Não são texto do guião: não criam versão nem tiram a aprovação.
create or replace function public.content_meta_set(p_id text, p_patch jsonb, p_token text default null) returns guioes
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); g guioes; n guioes; pid uuid; oid uuid; tg text[]; pl text[]; k text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  perform public._content_require('scripts.edit', g.client_id, p_token, 'script.meta', g.id);
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('project_id', 'owner_id', 'tags', 'platforms') then raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k); end if;
  end loop;
  pid := g.project_id; oid := g.owner_id; tg := g.tags; pl := g.platforms;
  if p_patch ? 'project_id' then
    pid := nullif(p_patch->>'project_id', '')::uuid;
    if pid is not null and pid is distinct from g.project_id
       and not exists (select 1 from projects where id = pid and workspace_id = g.client_id and status = 'ativa') then
      raise exception 'campanha_invalida' using errcode = '22023', detail = 'Essa campanha não existe neste cliente ou está arquivada.'; end if;
  end if;
  if p_patch ? 'owner_id' then
    oid := nullif(p_patch->>'owner_id', '')::uuid;
    if oid is not null and oid is distinct from g.owner_id and not public._authorize('scripts.edit', g.client_id, oid) then
      raise exception 'responsavel_invalido' using errcode = '22023', detail = 'Essa pessoa não pode editar guiões neste cliente.'; end if;
  end if;
  if p_patch ? 'tags' then
    if jsonb_typeof(p_patch->'tags') <> 'array' then raise exception 'etiquetas_invalidas' using errcode = '22023'; end if;
    tg := array(select distinct lower(trim(x)) from jsonb_array_elements_text(p_patch->'tags') x where trim(x) <> '' order by 1);
    if coalesce(array_length(tg, 1), 0) > 10 or exists (select 1 from unnest(tg) t where char_length(t) > 30) then
      raise exception 'etiquetas_invalidas' using errcode = '22023', detail = 'No máximo 10 etiquetas, cada uma com até 30 caracteres.'; end if;
  end if;
  if p_patch ? 'platforms' then
    if jsonb_typeof(p_patch->'platforms') <> 'array' then raise exception 'plataformas_invalidas' using errcode = '22023'; end if;
    pl := array(select distinct x from jsonb_array_elements_text(p_patch->'platforms') x order by 1);
    if not pl <@ array['instagram', 'tiktok', 'youtube'] then raise exception 'plataformas_invalidas' using errcode = '22023', detail = 'Plataformas: instagram, tiktok, youtube.'; end if;
  end if;
  update guioes set project_id = pid, owner_id = oid, tags = coalesce(tg, '{}'), platforms = coalesce(pl, '{}'), updated_at = now()
   where id = g.id returning * into n;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'script.meta_changed', 'content', g.id,
          jsonb_build_object('project_id', g.project_id, 'owner_id', g.owner_id, 'tags', g.tags, 'platforms', g.platforms),
          jsonb_build_object('project_id', n.project_id, 'owner_id', n.owner_id, 'tags', n.tags, 'platforms', n.platforms));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (g.client_id, 'script.meta_changed', 'content', g.id,
          jsonb_build_object('project_id', n.project_id, 'owner_id', n.owner_id, 'previous_owner_id', g.owner_id));
  if n.owner_id is not null and n.owner_id is distinct from g.owner_id then
    perform public._notify(n.owner_id, g.client_id, 'script_assigned', 'content', g.id,
      format('Ficaste responsável pelo guião %s', g.n), coalesce(g.tema, left(g.corpo, 120)), 'script_assigned:' || g.id || ':' || n.owner_id || ':' || extract(epoch from now())::bigint);
  end if;
  return n;
end $$;

-- Teleprompter: o conteúdo de cada item passa a trazer campanha, responsável, plataformas e etiquetas (filtros da fila).
create or replace function public._tp_session_row(p_session uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) || jsonb_build_object(
    'require_approval', c.require_approval_to_record,
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'content_id', i.content_id, 'position', i.position, 'skipped', i.skipped, 'skipped_blocks', to_jsonb(i.skipped_blocks),
                'carried', g.date < s.date,
                'content', jsonb_build_object('id', g.id, 'n', g.n, 'date', g.date, 'tema', g.tema, 'formato', g.formato, 'hooks', g.hooks,
                                              'corpo', g.corpo, 'cta', g.cta, 'editorial_status', g.editorial_status,
                                              'production_status', g.production_status, 'current_version_id', g.current_version_id,
                                              'project_id', g.project_id, 'owner_id', g.owner_id, 'tags', to_jsonb(g.tags), 'platforms', to_jsonb(g.platforms)),
                'takes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'block_key', t.block_key, 'take_number', t.take_number,
                                  'status', t.status, 'selected', t.selected, 'notes', t.notes, 'version_id', t.version_id,
                                  'session_id', t.session_id, 'created_label', t.created_label, 'created_at', t.created_at)
                                  order by t.block_key, t.take_number), '[]')
                          from takes t where t.content_id = g.id))
              order by i.position), '[]')
              from recording_session_items i join guioes g on g.id = i.content_id
              where i.session_id = s.id and g.editorial_status not in ('rejected','archived')))
  from recording_sessions s join clients c on c.id = s.workspace_id where s.id = p_session;
$$;

revoke all on function public.content_owners(text, text), public.projects_list(text, text), public.project_save(text, uuid, jsonb, text),
  public.content_meta_set(text, jsonb, text) from public;
grant execute on function public.content_owners(text, text), public.projects_list(text, text), public.project_save(text, uuid, jsonb, text),
  public.content_meta_set(text, jsonb, text) to anon, authenticated;

/* Rollback (compatível): drop function public.content_meta_set(text, jsonb, text), public.project_save(text, uuid, jsonb, text),
   public.projects_list(text, text), public.content_owners(text, text); repor _tp_session_row de 20261028211702;
   repor notifications_kind_check sem script_assigned; delete from role_capabilities where capability = 'projects.manage';
-- contract posterior: alter table guioes drop column project_id, owner_id, tags, platforms; drop table projects; */
