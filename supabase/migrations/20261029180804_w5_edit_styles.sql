-- W5-02 · Catálogo de estilos (VAR-02) e preset de edição do cliente (EDL-01). Expand: capacidade, tabelas e funções novas.
-- Cada estilo é um template versionado (layout em 1080×1920, nível de transformação, plataformas). O preset diz o que o
-- pacote automático gera por guião e fixa a versão de cada estilo que usa: editar um estilo não muda pacotes em silêncio.
-- O ponto de partida do Numeiro é dado do cliente numeiro, nunca regra global (AGENTS §1, §7). Rollback no fim.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('styles.manage', 'Edição (W5)', 'M', array['ws'], 'ativo', 'Gerir estilos e o preset de edição')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'styles.manage'), ('ws', 'workspace_admin', 'styles.manage'), ('ws', 'manager', 'styles.manage')
on conflict do nothing;

create table if not exists public.edit_styles (
  workspace_id text not null references public.clients(id),
  key text not null check (key ~ '^[A-Z][A-Z0-9_]{1,15}$'),
  status text not null default 'rascunho' check (status in ('rascunho', 'ativo', 'arquivado')),
  current_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, key)
);
create table if not exists public.edit_style_versions (
  workspace_id text not null,
  key text not null,
  version int not null check (version >= 1),
  name text not null check (char_length(name) between 1 and 60),
  spec jsonb not null,
  transformation text check (transformation is null or transformation in ('baixa', 'media', 'alta')),
  platforms text[] not null default '{}' check (platforms <@ array['instagram', 'tiktok', 'youtube']),
  notes text check (notes is null or char_length(notes) <= 2000),
  actor_kind text not null,
  actor_label text,
  created_at timestamptz not null default now(),
  primary key (workspace_id, key, version),
  foreign key (workspace_id, key) references public.edit_styles(workspace_id, key)
);
create table if not exists public.edit_presets (
  workspace_id text not null references public.clients(id),
  version int not null check (version >= 1),
  outputs jsonb not null,
  actor_kind text not null,
  actor_label text,
  created_at timestamptz not null default now(),
  primary key (workspace_id, version)
);
alter table public.edit_styles enable row level security;
alter table public.edit_style_versions enable row level security;
alter table public.edit_presets enable row level security;
revoke all on public.edit_styles, public.edit_style_versions, public.edit_presets from anon, authenticated;   -- só pelas RPCs

create or replace function public.edit_versions_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'versoes_imutaveis' using errcode = '42501'; end $$;
drop trigger if exists edit_style_versions_append_only on public.edit_style_versions;
create trigger edit_style_versions_append_only before update or delete on public.edit_style_versions for each row execute function public.edit_versions_append_only();
drop trigger if exists edit_presets_append_only on public.edit_presets;
create trigger edit_presets_append_only before update or delete on public.edit_presets for each row execute function public.edit_versions_append_only();

-- Valida a especificação de layout. Texto (título, legendas, faixa com texto) tem de caber no retângulo seguro comum
-- x 60-960, y 210-1600 (EDL-03); tudo dentro de 1080×1920. Devolve a lista de problemas (vazia = válida).
create or replace function public._edit_spec_problems(p_spec jsonb, p_require_layers boolean) returns text[]
language plpgsql immutable set search_path = public as $$
declare l jsonb; p text[] := '{}'; b jsonb; x int; y int; w int; h int; k text; i int := 0; c text;
begin
  if jsonb_typeof(p_spec) <> 'object' then return array['A especificação tem de ser um objeto.']; end if;
  if (p_spec->'canvas') is distinct from '{"w":1080,"h":1920}'::jsonb then p := array_append(p, 'O formato tem de ser 1080×1920.'::text); end if;
  if jsonb_typeof(coalesce(p_spec->'layers', 'null')) <> 'array' then return array_append(p, 'Falta a lista de camadas.'); end if;
  if jsonb_array_length(p_spec->'layers') > 20 then p := array_append(p, 'No máximo 20 camadas.'::text); end if;
  if p_require_layers and jsonb_array_length(p_spec->'layers') = 0 then p := array_append(p, 'Um estilo ativo precisa de pelo menos uma camada.'::text); end if;
  for l in select * from jsonb_array_elements(p_spec->'layers') loop
    i := i + 1; k := l->>'kind'; b := l->'box';
    if k is null or k not in ('video', 'image', 'attention_video', 'title', 'captions', 'band') then
      p := array_append(p, format('Camada %s: tipo desconhecido.', i)::text); continue; end if;
    if jsonb_typeof(b) <> 'array' or jsonb_array_length(b) <> 4
       or exists (select 1 from jsonb_array_elements(b) e where jsonb_typeof(e) <> 'number') then
      p := array_append(p, format('Camada %s: a caixa tem de ser [x, y, largura, altura].', i)::text); continue; end if;
    x := (b->>0)::numeric; y := (b->>1)::numeric; w := (b->>2)::numeric; h := (b->>3)::numeric;
    if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > 1080 or y + h > 1920 then
      p := array_append(p, format('Camada %s: sai do ecrã 1080×1920.', i)::text); end if;
    if (k in ('title', 'captions') or (k = 'band' and l ? 'text')) and (x < 60 or x + w > 960 or y < 210 or y + h > 1600) then
      p := array_append(p, format('Camada %s (%s): o texto tem de ficar no retângulo seguro (x 60-960, y 210-1600).', i, k)::text); end if;
    for c in select v from (values (l->>'color'), (l->>'stroke')) t(v) where v is not null loop
      if c !~ '^#[0-9A-Fa-f]{6}$' then p := array_append(p, format('Camada %s: cor inválida (%s).', i, c)::text); end if;
    end loop;
    if l ? 'max_words' and (jsonb_typeof(l->'max_words') <> 'number' or (l->>'max_words')::numeric not between 1 and 30) then
      p := array_append(p, format('Camada %s: máximo de palavras entre 1 e 30.', i)::text); end if;
  end loop;
  return p;
end $$;

-- Valida o preset: o que o pacote gera por guião. Estilos referidos têm de existir e estar ativos; fixa a versão.
create or replace function public._edit_preset_resolve(p_ws text, p_outputs jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o jsonb; out jsonb := '[]'; k text; s edit_styles; i int := 0;
begin
  if jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs) = 0 then
    raise exception 'preset_vazio' using errcode = '22023', detail = 'O preset precisa de pelo menos uma saída.'; end if;
  if jsonb_array_length(p_outputs) > 12 then raise exception 'preset_grande' using errcode = '22023', detail = 'No máximo 12 saídas por guião.'; end if;
  for o in select * from jsonb_array_elements(p_outputs) loop
    i := i + 1; k := o->>'kind';
    if k is null or k not in ('master', 'split_image_persona', 'split_attention', 'style') then
      raise exception 'saida_invalida' using errcode = '22023', detail = format('Saída %s: tipo desconhecido.', i); end if;
    if coalesce(o->>'captions', 'burned') not in ('burned', 'none') then
      raise exception 'saida_invalida' using errcode = '22023', detail = format('Saída %s: legendas têm de ser "burned" ou "none".', i); end if;
    if k = 'style' then
      select * into s from edit_styles where workspace_id = p_ws and key = o->>'style';
      if s.key is null then raise exception 'estilo_desconhecido' using errcode = '22023', detail = format('Saída %s: o estilo %s não existe neste cliente.', i, coalesce(o->>'style', '?')); end if;
      if s.status <> 'ativo' then raise exception 'estilo_inativo' using errcode = '22023', detail = format('Saída %s: o estilo %s não está ativo.', i, s.key); end if;
      out := out || jsonb_build_object('kind', k, 'style', s.key, 'style_version', s.current_version, 'captions', coalesce(o->>'captions', 'burned'));
    else
      out := out || jsonb_build_object('kind', k, 'captions', coalesce(o->>'captions', 'burned'),
        'per_hook', case when k = 'master' then coalesce((o->>'per_hook')::boolean, true) end) - case when k = 'master' then '' else 'per_hook' end;
    end if;
  end loop;
  return out;
end $$;

create or replace function public._edit_catalog_json(p_ws text, p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'can_manage', public.ws_can('styles.manage', p_ws, p_token),
    'styles', coalesce((select jsonb_agg(jsonb_build_object(
        'key', s.key, 'status', s.status, 'version', s.current_version, 'name', v.name, 'spec', v.spec,
        'transformation', v.transformation, 'platforms', v.platforms, 'notes', v.notes,
        'updated_at', v.created_at, 'updated_label', v.actor_label,
        'problems', to_jsonb(public._edit_spec_problems(v.spec, true))) order by s.key)
      from edit_styles s join edit_style_versions v on v.workspace_id = s.workspace_id and v.key = s.key and v.version = s.current_version
      where s.workspace_id = p_ws), '[]'),
    'preset', (select jsonb_build_object('version', p.version, 'outputs', p.outputs, 'created_at', p.created_at, 'created_label', p.actor_label,
        'stale', exists (select 1 from jsonb_array_elements(p.outputs) o join edit_styles s on s.workspace_id = p_ws and s.key = o->>'style'
                          where (o->>'style_version')::int <> s.current_version or s.status <> 'ativo'))
      from edit_presets p where p.workspace_id = p_ws order by p.version desc limit 1));
$$;

-- Leitura: quem vê guiões no cliente ou gere estilos.
create or replace function public.edit_catalog(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.ws_can('scripts.read', p_ws, p_token) or public.ws_can('styles.manage', p_ws, p_token)) then
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  return public._edit_catalog_json(p_ws, p_token);
end $$;

-- Gravar um estilo cria sempre uma versão nova. p_expected é a versão que a pessoa estava a ver (0 para um estilo novo):
-- se entretanto mudou, recusa (40001) em vez de apagar o trabalho de outra pessoa.
create or replace function public.edit_style_save(p_ws text, p_key text, p_style jsonb, p_expected int, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s edit_styles; v edit_style_versions; nv int; probs text[]; plats text[]; spec jsonb; before jsonb;
begin
  perform public._content_require('styles.manage', p_ws, p_token, 'edit.style_save', p_key);
  if p_key is null or p_key !~ '^[A-Z][A-Z0-9_]{1,15}$' then raise exception 'chave_invalida' using errcode = '22023', detail = 'Chave em maiúsculas, 2 a 16 caracteres (ex.: S14).'; end if;
  select * into s from edit_styles where workspace_id = p_ws and key = p_key for update;
  if coalesce(s.current_version, 0) <> coalesce(p_expected, -1) then
    raise exception 'versao_mudou' using errcode = '40001', detail = 'Outra pessoa gravou este estilo entretanto. Recarrega antes de gravar.'; end if;
  if s.status = 'arquivado' then raise exception 'estilo_arquivado' using errcode = '22023', detail = 'Reativa o estilo antes de o editar.'; end if;
  select * into v from edit_style_versions where workspace_id = p_ws and key = p_key and version = s.current_version;
  spec := coalesce(p_style->'spec', v.spec, '{"canvas":{"w":1080,"h":1920},"layers":[]}'::jsonb);
  probs := public._edit_spec_problems(spec, coalesce(s.status, 'rascunho') = 'ativo');
  if array_length(probs, 1) > 0 then raise exception 'especificacao_invalida' using errcode = '22023', detail = array_to_string(probs, ' '); end if;
  if p_style ? 'platforms' then
    if jsonb_typeof(p_style->'platforms') <> 'array' then raise exception 'plataformas_invalidas' using errcode = '22023'; end if;
    plats := array(select jsonb_array_elements_text(p_style->'platforms'));
    if not plats <@ array['instagram', 'tiktok', 'youtube'] then raise exception 'plataformas_invalidas' using errcode = '22023', detail = 'Plataformas: instagram, tiktok, youtube.'; end if;
  else plats := coalesce(v.platforms, '{}'); end if;
  if p_style ? 'transformation' and nullif(p_style->>'transformation', '') is not null and p_style->>'transformation' not in ('baixa', 'media', 'alta') then
    raise exception 'transformacao_invalida' using errcode = '22023', detail = 'Transformação: baixa, media ou alta.'; end if;
  if s.key is null then
    insert into edit_styles (workspace_id, key) values (p_ws, p_key);
    nv := 1;
  else nv := s.current_version + 1; before := to_jsonb(v) - 'workspace_id'; end if;
  insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, notes, actor_kind, actor_label)
  values (p_ws, p_key, nv, coalesce(nullif(trim(p_style->>'name'), ''), v.name, p_key), spec,
          case when p_style ? 'transformation' then nullif(p_style->>'transformation', '') else v.transformation end, plats,
          case when p_style ? 'notes' then nullif(trim(p_style->>'notes'), '') else v.notes end, a->>'kind', a->>'label');
  update edit_styles set current_version = nv, updated_at = now() where workspace_id = p_ws and key = p_key;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'edit.style_saved', 'edit_style', p_key, before,
          (select to_jsonb(x) - 'workspace_id' from edit_style_versions x where workspace_id = p_ws and key = p_key and version = nv));
  return public._edit_catalog_json(p_ws, p_token);
end $$;

-- Ativar exige layout completo e válido; arquivar recusa se o preset atual usa o estilo.
create or replace function public.edit_style_set_status(p_ws text, p_key text, p_status text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); s edit_styles; probs text[];
begin
  perform public._content_require('styles.manage', p_ws, p_token, 'edit.style_status', p_key);
  if p_status not in ('rascunho', 'ativo', 'arquivado') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  select * into s from edit_styles where workspace_id = p_ws and key = p_key for update;
  if s.key is null then raise exception 'estilo_nao_encontrado' using errcode = 'P0002'; end if;
  if p_status = 'ativo' then
    probs := public._edit_spec_problems((select spec from edit_style_versions where workspace_id = p_ws and key = p_key and version = s.current_version), true);
    if array_length(probs, 1) > 0 then raise exception 'especificacao_invalida' using errcode = '22023', detail = array_to_string(probs, ' '); end if;
  elsif s.status = 'ativo' and exists (select 1 from jsonb_array_elements((select outputs from edit_presets where workspace_id = p_ws order by version desc limit 1)) o
                                       where o->>'style' = p_key) then
    raise exception 'estilo_em_uso' using errcode = '22023', detail = 'O preset de edição usa este estilo. Tira-o do preset primeiro.';
  end if;
  if s.status <> p_status then
    update edit_styles set status = p_status, updated_at = now() where workspace_id = p_ws and key = p_key;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'edit.style_status', 'edit_style', p_key,
            jsonb_build_object('status', s.status), jsonb_build_object('status', p_status));
  end if;
  return public._edit_catalog_json(p_ws, p_token);
end $$;

create or replace function public.edit_style_history(p_ws text, p_key text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.ws_can('scripts.read', p_ws, p_token) or public.ws_can('styles.manage', p_ws, p_token)) then
    raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('version', version, 'name', name, 'spec', spec, 'transformation', transformation,
      'platforms', platforms, 'notes', notes, 'created_at', created_at, 'created_label', actor_label) order by version desc)
    from edit_style_versions where workspace_id = p_ws and key = p_key), '[]');
end $$;

create or replace function public.edit_preset_save(p_ws text, p_outputs jsonb, p_expected int, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); cur edit_presets; outs jsonb;
begin
  perform public._content_require('styles.manage', p_ws, p_token, 'edit.preset_save', p_ws);
  perform pg_advisory_xact_lock(hashtext('edit_preset:' || p_ws));
  select * into cur from edit_presets where workspace_id = p_ws order by version desc limit 1;
  if coalesce(cur.version, 0) <> coalesce(p_expected, -1) then
    raise exception 'versao_mudou' using errcode = '40001', detail = 'Outra pessoa gravou o preset entretanto. Recarrega antes de gravar.'; end if;
  outs := public._edit_preset_resolve(p_ws, p_outputs);
  insert into edit_presets (workspace_id, version, outputs, actor_kind, actor_label)
  values (p_ws, coalesce(cur.version, 0) + 1, outs, a->>'kind', a->>'label');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'edit.preset_saved', 'edit_preset', p_ws, cur.outputs, outs);
  return public._edit_catalog_json(p_ws, p_token);
end $$;

-- Ponto de partida (VAR-02, EDL-01): S01..S13 e o preset por defeito. S13 tem o layout descrito no PRD §41 e entra ativo;
-- os outros só têm nome e ficam em rascunho até alguém lhes desenhar o layout (não se inventa especificação).
create or replace function public._edit_seed(p_ws text, p_actor_kind text, p_actor_label text) returns void
language plpgsql security definer set search_path = public as $$
declare r record; empty jsonb := '{"canvas":{"w":1080,"h":1920},"layers":[]}';
begin
  if exists (select 1 from edit_styles where workspace_id = p_ws) then return; end if;
  for r in select * from (values
    ('S01', 'Prova'), ('S02', 'Gancho visual'), ('S03', 'Manchete'), ('S04', 'Contraponto'), ('S05', 'Responde ao comentário'),
    ('S06', 'Número'), ('S07', 'Narrador'), ('S08', 'Reação'), ('S09', 'Top 3 narrado'), ('S10', 'Série'), ('S11', 'Carrossel'),
    ('S12', 'Cortes de contexto')) v(k, n) loop
    insert into edit_styles (workspace_id, key) values (p_ws, r.k);
    insert into edit_style_versions (workspace_id, key, version, name, spec, actor_kind, actor_label, notes)
    values (p_ws, r.k, 1, r.n, empty, p_actor_kind, p_actor_label, 'Ponto de partida do catálogo (PRD VAR-02). Falta desenhar o layout.');
  end loop;
  insert into edit_styles (workspace_id, key, status) values (p_ws, 'S13', 'ativo');
  insert into edit_style_versions (workspace_id, key, version, name, spec, transformation, platforms, actor_kind, actor_label, notes)
  values (p_ws, 'S13', 1, 'Faixa de estatuto', jsonb_build_object('canvas', jsonb_build_object('w', 1080, 'h', 1920), 'layers', jsonb_build_array(
      jsonb_build_object('kind', 'image', 'role', 'foto de estatuto', 'box', jsonb_build_array(0, 0, 1080, 880)),
      jsonb_build_object('kind', 'video', 'role', 'lifestyle', 'box', jsonb_build_array(0, 960, 1080, 960)),
      jsonb_build_object('kind', 'band', 'brush', true, 'color', '#C8102E', 'box', jsonb_build_array(0, 800, 1080, 240)),
      jsonb_build_object('kind', 'title', 'color', '#FFD400', 'stroke', '#000000', 'weight', 'bold', 'max_words', 7, 'box', jsonb_build_array(80, 830, 860, 180)))),
    'media', array['instagram', 'tiktok', 'youtube'], p_actor_kind, p_actor_label,
    'Foto de estatuto em cima, faixa vermelha em pincelada na junção com título amarelo em negrito e contorno preto, vídeo de lifestyle em baixo (PRD §41). Título 3-7 palavras (VAR-03).');
  if not exists (select 1 from edit_presets where workspace_id = p_ws) then
    insert into edit_presets (workspace_id, version, outputs, actor_kind, actor_label) values (p_ws, 1, jsonb_build_array(
      jsonb_build_object('kind', 'master', 'per_hook', true, 'captions', 'burned'),
      jsonb_build_object('kind', 'split_image_persona', 'captions', 'burned'),
      jsonb_build_object('kind', 'split_attention', 'captions', 'burned'),
      jsonb_build_object('kind', 'style', 'style', 'S13', 'style_version', 1, 'captions', 'burned')), p_actor_kind, p_actor_label);
  end if;
end $$;

-- Para outro cliente começar pelo mesmo ponto de partida (só se ainda não tiver estilos).
create or replace function public.edit_catalog_init(p_ws text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token);
begin
  perform public._content_require('styles.manage', p_ws, p_token, 'edit.catalog_init', p_ws);
  if exists (select 1 from edit_styles where workspace_id = p_ws) then raise exception 'catalogo_existe' using errcode = '22023', detail = 'Este cliente já tem estilos.'; end if;
  perform public._edit_seed(p_ws, a->>'kind', a->>'label');
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'edit.catalog_init', 'edit_catalog', p_ws);
  return public._edit_catalog_json(p_ws, p_token);
end $$;

-- Numeiro: ponto de partida do PRD (preset do cliente, não regra global)
do $$ begin
  if exists (select 1 from clients where id = 'numeiro') then perform public._edit_seed('numeiro', 'system', 'migração W5-02'); end if;
end $$;

revoke all on function public.edit_versions_append_only(), public._edit_spec_problems(jsonb, boolean), public._edit_preset_resolve(text, jsonb),
  public._edit_catalog_json(text, text), public._edit_seed(text, text, text) from public, anon, authenticated;
revoke all on function public.edit_catalog(text, text), public.edit_style_save(text, text, jsonb, int, text), public.edit_style_set_status(text, text, text, text),
  public.edit_style_history(text, text, text), public.edit_preset_save(text, jsonb, int, text), public.edit_catalog_init(text, text) from public;
grant execute on function public.edit_catalog(text, text), public.edit_style_save(text, text, jsonb, int, text), public.edit_style_set_status(text, text, text, text),
  public.edit_style_history(text, text, text), public.edit_preset_save(text, jsonb, int, text), public.edit_catalog_init(text, text) to anon, authenticated;

/* Rollback (compatível): drop function public.edit_catalog_init(text, text), public.edit_preset_save(text, jsonb, int, text),
   public.edit_style_history(text, text, text), public.edit_style_set_status(text, text, text, text), public.edit_style_save(text, text, jsonb, int, text),
   public.edit_catalog(text, text), public._edit_seed(text, text, text), public._edit_catalog_json(text, text), public._edit_preset_resolve(text, jsonb),
   public._edit_spec_problems(jsonb, boolean);
   delete from role_capabilities where capability = 'styles.manage'; update capabilities set status = 'W5' where key = 'styles.manage';
-- contract posterior: drop table public.edit_presets, public.edit_style_versions, public.edit_styles; drop function public.edit_versions_append_only(); */
