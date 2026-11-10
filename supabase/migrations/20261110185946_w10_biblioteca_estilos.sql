-- W10-42: Biblioteca de estilos da agência e importar para um cliente (PRD REF-07, REF-08; CHG-005; ADR-0084).
-- Os estilos passam a nascer no espaço da agência, versionados. Importar copia uma versão fixa para o catálogo do cliente
-- (VAR-02); o cliente fica nessa versão até alguém da agência carregar em "Atualizar" (pressuposto do REF-08).
-- A equipa de um cliente nunca vê a biblioteca (R-13): tudo pelas RPCs agency_style_*, que exigem staff ativo da agência
-- com a capacidade de organização. Importar exige também styles.manage no cliente e acesso a ele (_viewer_sees).
-- Expand (só aditivo): 2 capacidades (já previstas no registo), 2 tabelas fechadas à API, 3 colunas novas em edit_styles,
-- funções novas, e o trigger edit_style_versions_carry_look passa a não herdar o aspeto anterior numa importação
-- (comportamento igual em todos os outros casos). Backfill: os estilos ativos do Numeiro (S13 a S17) entram na biblioteca
-- como versão 1 e ficam marcados como importados. Rollback no fim.

-- ───────────── capacidades ─────────────
insert into capabilities (key, module, risk, scopes, status, label) values
  ('styles.library.manage', 'Edição', 'M', array['org'], 'ativo', 'Gerir a biblioteca de estilos da agência'),
  ('styles.import', 'Edição', 'M', array['org'], 'ativo', 'Importar estilos da agência para um cliente')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module, scopes = excluded.scopes;
insert into role_capabilities (scope, role, capability) values
  ('org', 'agency_owner', 'styles.library.manage'), ('org', 'agency_admin', 'styles.library.manage'),
  ('org', 'agency_owner', 'styles.import'), ('org', 'agency_admin', 'styles.import')
on conflict do nothing;

-- ───────────── tabelas ─────────────
create table if not exists public.agency_styles (
  organization_id uuid not null references public.organizations(id),
  key text not null check (key ~ '^[A-Z][A-Z0-9_]{1,15}$'),
  status text not null default 'rascunho' check (status in ('rascunho', 'ativo', 'arquivado')),
  current_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, key)
);
create table if not exists public.agency_style_versions (
  organization_id uuid not null,
  key text not null,
  version int not null,
  name text not null,
  spec jsonb not null,
  look jsonb,                         -- {captions, hook, layout}; sem música (a música é da biblioteca de cada cliente)
  transformation text check (transformation in ('baixa', 'media', 'alta')),
  platforms text[] not null default '{}',
  notes text,
  source_url text,                    -- vídeo de origem ou inspiração (REF-09, R-18)
  actor_kind text not null,
  actor_label text,
  created_at timestamptz not null default now(),
  primary key (organization_id, key, version),
  foreign key (organization_id, key) references public.agency_styles(organization_id, key)
);
alter table public.agency_styles enable row level security;
alter table public.agency_style_versions enable row level security;
revoke all on public.agency_styles, public.agency_style_versions from anon, authenticated;   -- só pelas RPCs
drop trigger if exists agency_style_versions_append_only on public.agency_style_versions;
create trigger agency_style_versions_append_only before update or delete on public.agency_style_versions
  for each row execute function public.edit_versions_append_only();

-- de onde veio um estilo do cliente (null = criado no próprio cliente)
alter table public.edit_styles
  add column if not exists origin_org uuid,
  add column if not exists origin_key text,
  add column if not exists origin_version int;

-- Numa importação o aspeto vem da agência (ou nenhum): não herdar o da versão anterior do cliente.
create or replace function public.edit_style_versions_carry_look() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.look is null and new.version > 1 and coalesce(current_setting('app.style_import', true), '') <> '1' then
    select look into new.look from edit_style_versions where workspace_id = new.workspace_id and key = new.key and version = new.version - 1;
  end if;
  return new;
end $$;

-- ───────────── leitura ─────────────
create or replace function public._agency_style_json(p_org uuid, p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'key', s.key, 'status', s.status, 'version', s.current_version, 'name', v.name, 'spec', v.spec, 'look', v.look,
      'transformation', v.transformation, 'platforms', v.platforms, 'notes', v.notes, 'source_url', v.source_url,
      'updated_at', v.created_at, 'updated_label', v.actor_label,
      'problems', to_jsonb(public._edit_spec_problems(v.spec, true)),
      -- clientes que têm este estilo (só os que quem vê também vê) e a versão que têm
      'imports', coalesce((select jsonb_agg(jsonb_build_object('ws', c.id, 'name', c.name, 'key', e.key, 'version', e.origin_version,
                                                               'status', e.status) order by c.name)
                           from edit_styles e join clients c on c.id = e.workspace_id
                          where e.origin_org = p_org and e.origin_key = s.key and c.status = 'active'
                            and public._viewer_sees(c.id, p_uid)), '[]')) order by s.key), '[]')
  from agency_styles s join agency_style_versions v on v.organization_id = s.organization_id and v.key = s.key and v.version = s.current_version
  where s.organization_id = p_org
$$;
revoke all on function public._agency_style_json(uuid, uuid) from public, anon, authenticated;

create or replace function public._agency_style_org(p_cap text, p_action text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare org uuid;
begin
  if auth.uid() is null then raise exception 'nao_autenticado' using errcode = '28000'; end if;
  org := public._agency_org(p_cap);
  if org is null then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', auth.uid(), 'action', p_action, 'capability', p_cap);
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return org;
end $$;
revoke all on function public._agency_style_org(text, text) from public, anon, authenticated;

-- A biblioteca, com os clientes a que posso importar (styles.manage em cada um).
create or replace function public.agency_style_library() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._agency_style_org('styles.library.manage', 'agency.style_library');
begin
  return jsonb_build_object(
    'can_import', public._org_can('styles.import', org),
    'styles', public._agency_style_json(org, auth.uid()),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('ws', c.id, 'name', c.name) order by c.name) from clients c
                          where c.organization_id = org and c.status = 'active' and public._viewer_sees(c.id, auth.uid())
                            and public._authorize('styles.manage', c.id, auth.uid())), '[]'));
end $$;

create or replace function public.agency_style_history(p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare org uuid := public._agency_style_org('styles.library.manage', 'agency.style_history');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('version', v.version, 'name', v.name, 'spec', v.spec, 'look', v.look,
                     'transformation', v.transformation, 'platforms', v.platforms, 'notes', v.notes, 'source_url', v.source_url,
                     'created_at', v.created_at, 'created_label', v.actor_label) order by v.version desc)
                   from agency_style_versions v where v.organization_id = org and v.key = p_key), '[]');
end $$;

-- ───────────── escrita ─────────────
-- Gravar cria sempre uma versão nova. p_expected = versão que a pessoa via (0 para um estilo novo).
-- p_from = {ws, key}: duplicar o estilo de um cliente para a biblioteca (precisa de ver esse cliente e de scripts.read nele).
create or replace function public.agency_style_save(p_key text, p_style jsonb, p_expected int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._agency_style_org('styles.library.manage', 'agency.style_save'); uid uuid := auth.uid();
        s agency_styles; v agency_style_versions; nv int; spec jsonb; look jsonb; probs text[]; plats text[]; why text; before jsonb; src text;
begin
  if p_key is null or p_key !~ '^[A-Z][A-Z0-9_]{1,15}$' then
    raise exception 'chave_invalida' using errcode = '22023', detail = 'Chave em maiúsculas, 2 a 16 caracteres (ex.: S18).'; end if;
  select * into s from agency_styles where organization_id = org and key = p_key for update;
  if coalesce(s.current_version, 0) <> coalesce(p_expected, -1) then
    raise exception 'versao_mudou' using errcode = '40001', detail = 'Outra pessoa gravou este estilo entretanto. Recarrega antes de gravar.'; end if;
  if s.status = 'arquivado' then raise exception 'estilo_arquivado' using errcode = '22023', detail = 'Recupera o estilo antes de o editar.'; end if;
  select * into v from agency_style_versions where organization_id = org and key = p_key and version = s.current_version;
  spec := coalesce(p_style->'spec', v.spec, '{"canvas":{"w":1080,"h":1920},"layers":[]}'::jsonb);
  probs := public._edit_spec_problems(spec, coalesce(s.status, 'rascunho') = 'ativo');
  if array_length(probs, 1) > 0 then raise exception 'especificacao_invalida' using errcode = '22023', detail = array_to_string(probs, ' '); end if;
  look := case when p_style ? 'look' then nullif(p_style->'look', 'null'::jsonb) else v.look end;
  if look is not null then
    look := look - 'music';                                          -- a música é de cada cliente
    why := public._edit_saved_look_problem(look);
    if why is not null then raise exception 'aspeto_invalido' using errcode = '22023', detail = why; end if;
  end if;
  if p_style ? 'platforms' then
    if jsonb_typeof(p_style->'platforms') <> 'array' then raise exception 'plataformas_invalidas' using errcode = '22023'; end if;
    plats := array(select jsonb_array_elements_text(p_style->'platforms'));
    if not plats <@ array['instagram', 'tiktok', 'youtube'] then raise exception 'plataformas_invalidas' using errcode = '22023'; end if;
  else plats := coalesce(v.platforms, '{}'); end if;
  if p_style ? 'transformation' and nullif(p_style->>'transformation', '') is not null and p_style->>'transformation' not in ('baixa', 'media', 'alta') then
    raise exception 'transformacao_invalida' using errcode = '22023'; end if;
  src := case when p_style ? 'source_url' then nullif(trim(p_style->>'source_url'), '') else v.source_url end;
  if src is not null and (length(src) > 500 or src !~* '^https?://') then
    raise exception 'link_invalido' using errcode = '22023', detail = 'O link de origem tem de começar por http(s)://.'; end if;
  if s.key is null then
    insert into agency_styles (organization_id, key) values (org, p_key);
    nv := 1;
  else nv := s.current_version + 1; before := to_jsonb(v) - 'organization_id'; end if;
  insert into agency_style_versions (organization_id, key, version, name, spec, look, transformation, platforms, notes, source_url, actor_kind, actor_label)
  values (org, p_key, nv, left(coalesce(nullif(trim(p_style->>'name'), ''), v.name, p_key), 60), spec, look,
          case when p_style ? 'transformation' then nullif(p_style->>'transformation', '') else v.transformation end, plats,
          left(case when p_style ? 'notes' then nullif(trim(p_style->>'notes'), '') else v.notes end, 2000), src,
          'user', (select email from auth.users where id = uid));
  update agency_styles set current_version = nv, updated_at = now() where organization_id = org and key = p_key;
  insert into audit_events (actor_user_id, actor_kind, organization_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', org, 'agency.style_saved', 'agency_style', p_key, before,
          (select to_jsonb(x) - 'organization_id' from agency_style_versions x where organization_id = org and key = p_key and version = nv));
  return public.agency_style_library();
end $$;

create or replace function public.agency_style_set_status(p_key text, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._agency_style_org('styles.library.manage', 'agency.style_status'); s agency_styles; probs text[];
begin
  if p_status not in ('rascunho', 'ativo', 'arquivado') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  select * into s from agency_styles where organization_id = org and key = p_key for update;
  if s.key is null then raise exception 'estilo_nao_encontrado' using errcode = 'P0002'; end if;
  if p_status = 'ativo' then
    probs := public._edit_spec_problems((select spec from agency_style_versions where organization_id = org and key = p_key and version = s.current_version), true);
    if array_length(probs, 1) > 0 then raise exception 'especificacao_invalida' using errcode = '22023', detail = array_to_string(probs, ' '); end if;
  end if;
  if s.status <> p_status then
    update agency_styles set status = p_status, updated_at = now() where organization_id = org and key = p_key;
    insert into audit_events (actor_user_id, actor_kind, organization_id, action, entity_type, entity_id, before, after)
    values (auth.uid(), 'user', org, 'agency.style_status', 'agency_style', p_key, jsonb_build_object('status', s.status), jsonb_build_object('status', p_status));
  end if;
  return public.agency_style_library();
end $$;

-- Importar (ou atualizar) um estilo ativo da biblioteca num cliente: copia a versão atual da agência como versão nova do
-- estilo do cliente, fixa a origem e ativa-o. p_as = chave no cliente (por defeito a mesma). Se o cliente já tem essa chave
-- e não veio deste estilo da agência, recusa (nunca escreve por cima de um estilo do cliente).
create or replace function public.agency_style_import(p_key text, p_ws text, p_as text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare org uuid := public._agency_style_org('styles.import', 'agency.style_import'); uid uuid := auth.uid();
        a agency_styles; av agency_style_versions; e edit_styles; k text := coalesce(nullif(trim(p_as), ''), p_key); nv int; st text;
begin
  if p_ws is null or not exists (select 1 from clients c where c.id = p_ws and c.organization_id = org and c.status = 'active')
     or not public._viewer_sees(p_ws, uid) or not public._authorize('styles.manage', p_ws, uid) then
    raise log 'audit_denied %', jsonb_build_object('actor_user_id', uid, 'workspace_id', p_ws, 'action', 'agency.style_import', 'capability', 'styles.manage');
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if k !~ '^[A-Z][A-Z0-9_]{1,15}$' then raise exception 'chave_invalida' using errcode = '22023'; end if;
  select * into a from agency_styles where organization_id = org and key = p_key;
  if a.key is null then raise exception 'estilo_nao_encontrado' using errcode = 'P0002'; end if;
  if a.status <> 'ativo' then raise exception 'estilo_nao_ativo' using errcode = '22023', detail = 'Só se importam estilos ativos da biblioteca.'; end if;
  select * into av from agency_style_versions where organization_id = org and key = p_key and version = a.current_version;
  select * into e from edit_styles where workspace_id = p_ws and key = k for update;
  if e.key is not null and (e.origin_org is distinct from org or e.origin_key is distinct from p_key) then
    raise exception 'chave_em_uso' using errcode = 'PT409', detail = format('Este cliente já tem um estilo %s que não veio deste estilo da agência. Importa com outra chave.', k); end if;
  if e.key is not null and e.origin_version = av.version and e.status = 'ativo' then return public.agency_style_library(); end if;   -- já está
  perform set_config('app.style_import', '1', true);
  if e.key is null then
    insert into edit_styles (workspace_id, key, status, current_version, origin_org, origin_key, origin_version)
    values (p_ws, k, 'rascunho', 0, org, p_key, av.version);
    nv := 1;
  else nv := e.current_version + 1; end if;
  insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, notes, look, actor_kind, actor_label)
  values (p_ws, k, nv, av.name, av.spec, av.transformation, av.platforms,
          left(concat_ws(E'\n', av.notes, format('Importado da biblioteca da agência: %s v%s.', p_key, av.version)), 2000), av.look,
          'user', (select email from auth.users where id = uid));
  perform set_config('app.style_import', '', true);
  st := case when array_length(public._edit_spec_problems(av.spec, true), 1) > 0 then 'rascunho' else 'ativo' end;
  update edit_styles set current_version = nv, origin_version = av.version, status = st, updated_at = now() where workspace_id = p_ws and key = k;
  insert into audit_events (actor_user_id, actor_kind, organization_id, workspace_id, action, entity_type, entity_id, before, after)
  values (uid, 'user', org, p_ws, case when e.key is null then 'edit.style_imported' else 'edit.style_import_updated' end, 'edit_style', k,
          case when e.key is null then null else jsonb_build_object('version', e.current_version, 'origin_version', e.origin_version, 'status', e.status) end,
          jsonb_build_object('version', nv, 'origin_key', p_key, 'origin_version', av.version, 'status', st));
  return public.agency_style_library();
end $$;

revoke all on function public.agency_style_library(), public.agency_style_history(text), public.agency_style_save(text, jsonb, int),
  public.agency_style_set_status(text, text), public.agency_style_import(text, text, text) from public, anon;
grant execute on function public.agency_style_library(), public.agency_style_history(text), public.agency_style_save(text, jsonb, int),
  public.agency_style_set_status(text, text), public.agency_style_import(text, text, text) to authenticated;

-- O catálogo do cliente diz de onde veio cada estilo (só a chave e a versão de origem; nada da biblioteca).
create or replace function public._edit_catalog_json(p_ws text, p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'can_manage', public.ws_can('styles.manage', p_ws, p_token),
    'styles', coalesce((select jsonb_agg(jsonb_build_object(
        'key', s.key, 'status', s.status, 'version', s.current_version, 'name', v.name, 'spec', v.spec,
        'transformation', v.transformation, 'platforms', v.platforms, 'notes', v.notes,
        'updated_at', v.created_at, 'updated_label', v.actor_label,
        'origin', case when s.origin_key is null then null else jsonb_build_object('key', s.origin_key, 'version', s.origin_version) end,
        'problems', to_jsonb(public._edit_spec_problems(v.spec, true))) order by s.key)
      from edit_styles s join edit_style_versions v on v.workspace_id = s.workspace_id and v.key = s.key and v.version = s.current_version
      where s.workspace_id = p_ws), '[]'),
    'preset', (select jsonb_build_object('version', p.version, 'outputs', p.outputs, 'created_at', p.created_at, 'created_label', p.actor_label,
        'stale', exists (select 1 from jsonb_array_elements(p.outputs) o join edit_styles s on s.workspace_id = p_ws and s.key = o->>'style'
                          where (o->>'style_version')::int <> s.current_version or s.status <> 'ativo'))
      from edit_presets p where p.workspace_id = p_ws order by p.version desc limit 1));
$$;

-- ───────────── backfill: estilos ativos do Numeiro entram na biblioteca ─────────────
do $$
declare org uuid; r record;
begin
  select organization_id into org from clients where id = 'numeiro';
  if org is null then return; end if;
  for r in select s.key, v.* from edit_styles s join edit_style_versions v on v.workspace_id = s.workspace_id and v.key = s.key and v.version = s.current_version
            where s.workspace_id = 'numeiro' and s.status = 'ativo' and s.origin_key is null
              and not exists (select 1 from agency_styles x where x.organization_id = org and x.key = s.key) loop
    insert into agency_styles (organization_id, key, status, current_version) values (org, r.key, 'ativo', 1);
    insert into agency_style_versions (organization_id, key, version, name, spec, look, transformation, platforms, notes, actor_kind, actor_label)
    values (org, r.key, 1, r.name, r.spec, case when r.look is null then null else r.look - 'music' end, r.transformation, r.platforms,
            r.notes, 'system', 'migração W10-42 (a partir do Numeiro)');
    update edit_styles set origin_org = org, origin_key = r.key, origin_version = 1 where workspace_id = 'numeiro' and key = r.key;
  end loop;
end $$;

-- Rollback (só se nada depender ainda; correr à mão):
-- drop function if exists public.agency_style_import(text, text, text), public.agency_style_set_status(text, text),
--   public.agency_style_save(text, jsonb, int), public.agency_style_history(text), public.agency_style_library(),
--   public._agency_style_org(text, text), public._agency_style_json(uuid, uuid);
-- repor _edit_catalog_json e edit_style_versions_carry_look da W5 (20261029180804, 20261105195936);
-- alter table public.edit_styles drop column if exists origin_org, drop column if exists origin_key, drop column if exists origin_version;
-- drop table if exists public.agency_style_versions, public.agency_styles;
-- delete from role_capabilities where capability in ('styles.library.manage', 'styles.import');
-- update capabilities set status = 'W5' where key in ('styles.library.manage', 'styles.import');
