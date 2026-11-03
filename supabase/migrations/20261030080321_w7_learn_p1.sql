-- W7 · Aprendizagem e qualidade (PRD §19.5): FR-17-10 taxonomia de motivos de rejeição e retrabalho por etapa.
-- Expand: 2 capacidades, 1 flag, 2 tabelas fechadas à API e funções novas. NÃO muda content_transition: o motivo por
-- categoria entra por uma função nova (content_transition_reasoned) que chama a de sempre e etiqueta a transição que
-- ela acabou de gravar, na mesma transação. Quem chama content_transition como hoje (cartão sem flag, código de equipa,
-- guiao_update, motor) continua igual. O texto livre continua obrigatório (regra da função original). Rollback no fim.
--
-- Definições (ADR-0037):
--  * Decisão de revisão = transição editorial para approved, changes_requested ou rejected feita por uma pessoa ou código
--    de equipa (as importadas na migração W2 não contam: não têm data real).
--  * Taxa de retrabalho da etapa = (pedidos de alterações + rejeições) ÷ decisões, no mês (fuso do cliente).
--  * Tempo perdido = de cada pedido de alterações até à volta a revisão do mesmo guião. Sem volta ainda: "em aberto",
--    nunca estimado.
--  * Etapas: guião (revisão editorial). Vídeo fica indisponível até existir revisão de media (M08); a taxonomia já pode
--    marcar motivos que se aplicam a vídeo.

insert into capabilities (key, module, risk, scopes, status, label) values
  ('learn.read', 'Aprendizagem', 'B', array['ws'], 'ativo', 'Ver retrabalho, experiências e recomendações'),
  ('learn.manage', 'Aprendizagem', 'M', array['ws'], 'ativo', 'Gerir motivos de rejeição e experiências')
on conflict (key) do update set status = 'ativo', label = excluded.label, module = excluded.module;
insert into role_capabilities (scope, role, capability) values
  ('ws', 'workspace_owner', 'learn.read'), ('ws', 'workspace_admin', 'learn.read'), ('ws', 'manager', 'learn.read'), ('ws', 'reviewer', 'learn.read'),
  ('ws', 'workspace_owner', 'learn.manage'), ('ws', 'workspace_admin', 'learn.manage'), ('ws', 'manager', 'learn.manage')
on conflict do nothing;

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('learn.rework', 'Motivos de rejeição e retrabalho', 'Aprendizagem', 'ws', 'owner',
   'Categoria obrigatória ao rejeitar ou pedir alterações a um guião (o texto continua obrigatório) e painel de retrabalho por etapa e mês (FR-17-10).')
on conflict (key) do nothing;

-- Taxonomia por cliente. code é estável (relatórios); label muda; desativar esconde da escolha sem perder o histórico.
create table if not exists public.rework_reasons (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,39}$'),
  label text not null check (char_length(btrim(label)) between 2 and 60),
  description text check (description is null or char_length(description) <= 300),
  applies_to text[] not null default array['guiao'] check (cardinality(applies_to) between 1 and 2 and applies_to <@ array['guiao', 'video']),
  active boolean not null default true,
  sort int not null default 100 check (sort between 0 and 10000),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (workspace_id, code)
);

-- Categoria escolhida numa transição (só de acrescentar; uma por transição).
create table if not exists public.content_transition_reasons (
  transition_id bigint primary key references public.content_transitions(id),
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id) on delete restrict,
  stage text not null default 'guiao' check (stage in ('guiao', 'video')),
  reason_id uuid not null references public.rework_reasons(id),
  code text not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create index if not exists content_transition_reasons_ws on public.content_transition_reasons (workspace_id, created_at);
drop trigger if exists content_transition_reasons_immutable on public.content_transition_reasons;
create trigger content_transition_reasons_immutable before update or delete on public.content_transition_reasons
  for each row execute function public.content_append_only();
drop trigger if exists content_transition_reasons_ws on public.content_transition_reasons;
create trigger content_transition_reasons_ws before insert on public.content_transition_reasons
  for each row execute function public.content_same_workspace();

alter table public.rework_reasons enable row level security;
alter table public.content_transition_reasons enable row level security;
revoke all on public.rework_reasons, public.content_transition_reasons from anon, authenticated;   -- só pelas RPCs

-- Capacidade primeiro (42501), depois a flag (55000): disponibilidade não é autorização (CAP-09).
create or replace function public._learn_require(p_flag text, p_cap text, p_ws text, p_token text, p_action text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require(p_cap, p_ws, p_token, p_action, p_ws);
  if p_flag is not null and not public._flag_on(p_flag, p_ws, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Esta funcionalidade ainda está em teste e não está ligada para ti.';
  end if;
end $$;

-- Lista sugerida (ponto de partida genérico, nunca regra global: cada cliente copia e muda à vontade).
create or replace function public._rework_defaults() returns jsonb
language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('code', 'hook_fraco', 'label', 'Hook fraco', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 10),
    jsonb_build_object('code', 'factos', 'label', 'Factos ou fonte por verificar', 'applies_to', jsonb_build_array('guiao'), 'sort', 20),
    jsonb_build_object('code', 'voz', 'label', 'Fora do tom ou da voz', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 30),
    jsonb_build_object('code', 'estrutura', 'label', 'Estrutura ou ritmo', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 40),
    jsonb_build_object('code', 'duracao', 'label', 'Demasiado longo', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 50),
    jsonb_build_object('code', 'tema', 'label', 'Tema fora da estratégia', 'applies_to', jsonb_build_array('guiao'), 'sort', 60),
    jsonb_build_object('code', 'cta', 'label', 'CTA em falta ou fraco', 'applies_to', jsonb_build_array('guiao'), 'sort', 70),
    jsonb_build_object('code', 'risco', 'label', 'Risco legal ou de reputação', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 80),
    jsonb_build_object('code', 'edicao', 'label', 'Edição, legendas ou áudio', 'applies_to', jsonb_build_array('video'), 'sort', 90),
    jsonb_build_object('code', 'outro', 'label', 'Outro', 'applies_to', jsonb_build_array('guiao', 'video'), 'sort', 999))
$$;

create or replace function public._rework_reasons_json(p_ws text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'code', r.code, 'label', r.label, 'description', r.description,
           'applies_to', to_jsonb(r.applies_to), 'active', r.active, 'sort', r.sort,
           'uses', (select count(*) from content_transition_reasons x where x.reason_id = r.id))
         order by r.active desc, r.sort, lower(r.label)), '[]')
  from rework_reasons r where r.workspace_id = p_ws
$$;

-- Para escolher ao rejeitar: quem lê guiões vê a lista (inclui o código de equipa). enabled diz se a flag está ligada.
create or replace function public.rework_reasons_list(p_ws text, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._content_require('scripts.read', p_ws, p_token, 'rework.reasons', p_ws);
  return jsonb_build_object('enabled', public._flag_on('learn.rework', p_ws, p_token),
                            'can_manage', public.ws_can('learn.manage', p_ws, p_token),
                            'reasons', public._rework_reasons_json(p_ws));
end $$;

-- Copia a lista sugerida (só se ainda não houver nenhuma). Idempotente.
create or replace function public.rework_reasons_seed(p_ws text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); n int;
begin
  perform public._learn_require('learn.rework', 'learn.manage', p_ws, p_token, 'rework.seed');
  if not exists (select 1 from rework_reasons where workspace_id = p_ws) then
    insert into rework_reasons (workspace_id, code, label, applies_to, sort, created_by)
    select p_ws, d->>'code', d->>'label', array(select jsonb_array_elements_text(d->'applies_to')), (d->>'sort')::int, (a->>'uid')::uuid
    from jsonb_array_elements(public._rework_defaults()) d;
    get diagnostics n = row_count;
    insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
    values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'rework.reasons_seeded', 'rework_reasons', p_ws, jsonb_build_object('n', n));
  end if;
  return public.rework_reasons_list(p_ws, p_token);
end $$;

-- Criar (p_id nulo) ou mudar um motivo. O code não muda depois de criado (os relatórios dependem dele).
create or replace function public.rework_reason_save(p_ws text, p_id uuid, p_fields jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := public._content_actor(p_token); old rework_reasons; r rework_reasons; k text; ap text[];
begin
  perform public._learn_require('learn.rework', 'learn.manage', p_ws, p_token, 'rework.reason_save');
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'campos_invalidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('code', 'label', 'description', 'applies_to', 'active', 'sort') then
      raise exception 'campo_invalido' using errcode = '22023', detail = format('Campo desconhecido: %s.', k); end if;
  end loop;
  if p_fields ? 'applies_to' then
    if jsonb_typeof(p_fields->'applies_to') <> 'array' then raise exception 'etapas_invalidas' using errcode = '22023'; end if;
    ap := array(select distinct x from jsonb_array_elements_text(p_fields->'applies_to') x order by 1);
  end if;
  begin
    if p_id is null then
      insert into rework_reasons (workspace_id, code, label, description, applies_to, active, sort, created_by)
      values (p_ws, lower(btrim(coalesce(p_fields->>'code', ''))), btrim(coalesce(p_fields->>'label', '')), nullif(btrim(p_fields->>'description'), ''),
              coalesce(ap, array['guiao']), coalesce((p_fields->>'active')::boolean, true), coalesce((p_fields->>'sort')::int, 100), (a->>'uid')::uuid)
      returning * into r;
    else
      select * into old from rework_reasons where id = p_id and workspace_id = p_ws for update;
      if old.id is null then raise exception 'motivo_nao_encontrado' using errcode = 'P0002'; end if;
      if p_fields ? 'code' and lower(btrim(p_fields->>'code')) <> old.code then
        raise exception 'codigo_imutavel' using errcode = '22023', detail = 'O código de um motivo não muda (os relatórios usam-no). Cria um motivo novo.'; end if;
      update rework_reasons set
        label = coalesce(nullif(btrim(p_fields->>'label'), ''), label),
        description = case when p_fields ? 'description' then nullif(btrim(p_fields->>'description'), '') else description end,
        applies_to = coalesce(ap, applies_to),
        active = coalesce((p_fields->>'active')::boolean, active),
        sort = coalesce((p_fields->>'sort')::int, sort),
        updated_at = now()
      where id = p_id returning * into r;
    end if;
  exception
    when unique_violation then raise exception 'codigo_repetido' using errcode = '22023', detail = 'Já há um motivo com esse código.';
    when check_violation then raise exception 'motivo_invalido' using errcode = '22023',
      detail = 'Código com 2 a 40 letras minúsculas, números ou _; nome com 2 a 60 caracteres; etapa guião e/ou vídeo.';
    when invalid_text_representation then raise exception 'motivo_invalido' using errcode = '22023', detail = 'Valores inválidos.';
  end;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, case when p_id is null then 'rework.reason_created' else 'rework.reason_updated' end,
          'rework_reason', r.id::text, to_jsonb(old), to_jsonb(r));
  return public.rework_reasons_list(p_ws, p_token);
end $$;

-- Rejeitar ou pedir alterações com categoria (FR-17-10). Mesma regra e mesma função de sempre; a categoria fica ligada
-- à transição que content_transition acabou de gravar (a linha do guião está presa por "for update" nessa função).
create or replace function public.content_transition_reasoned(p_id text, p_to text, p_reason text, p_reason_code text,
                                                              p_lock integer default null, p_token text default null)
returns guioes language plpgsql security definer set search_path = public as $$
declare g guioes; a jsonb; rr rework_reasons; tid bigint;
begin
  select * into g from guioes where id = p_id;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  if p_to not in ('changes_requested', 'rejected') then raise exception 'transicao_invalida' using errcode = '22023'; end if;
  perform public._content_require('scripts.reject', g.client_id, p_token, 'script.reject_reasoned', g.id);
  if not public._flag_on('learn.rework', g.client_id, p_token) then
    raise exception 'funcionalidade_desligada' using errcode = '55000', detail = 'Os motivos por categoria ainda não estão ligados neste cliente.';
  end if;
  select * into rr from rework_reasons where workspace_id = g.client_id and code = lower(btrim(coalesce(p_reason_code, ''))) and active
     and 'guiao' = any (applies_to);
  if rr.id is null then raise exception 'motivo_categoria_invalido' using errcode = '22023', detail = 'Escolhe uma categoria da lista deste cliente.'; end if;
  a := public._content_actor(p_token);
  g := public.content_transition(p_id, p_to, p_reason, p_lock, p_token);
  select id into tid from content_transitions where content_id = g.id and kind = 'editorial' and to_status = p_to order by id desc limit 1;
  insert into content_transition_reasons (transition_id, workspace_id, content_id, stage, reason_id, code, created_by)
  values (tid, g.client_id, g.id, 'guiao', rr.id, rr.code, (a->>'uid')::uuid);
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', g.client_id, 'script.reason_tagged', 'guiao', g.id,
          jsonb_build_object('transition_id', tid, 'to', p_to, 'code', rr.code));
  return g;
end $$;

-- Painel de retrabalho (FR-17-10): por etapa e por mês, contagens por motivo, taxa de retrabalho e tempo perdido.
-- Não revela quem decidiu (é um relatório de processo, não de pessoas).
create or replace function public.rework_dashboard(p_ws text, p_months int default 6, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text; n int := least(24, greatest(1, coalesce(p_months, 6))); since timestamptz;
begin
  perform public._learn_require('learn.rework', 'learn.read', p_ws, p_token, 'rework.dashboard');
  select coalesce(timezone, 'Asia/Dubai') into tz from clients where id = p_ws;
  since := (date_trunc('month', now() at time zone tz) - make_interval(months => n - 1)) at time zone tz;
  return (with tr as (
      select t.id, t.content_id, t.to_status, t.at, date_trunc('month', t.at at time zone tz)::date m
      from content_transitions t
      where t.workspace_id = p_ws and t.kind = 'editorial' and t.actor_kind <> 'migration' and t.at >= since),
    dec as (select * from tr where to_status in ('approved', 'changes_requested', 'rejected')),
    rw as (
      select d.*, x.code, coalesce(r.label, x.code) label,
        case when d.to_status = 'changes_requested' then (select min(n2.at) from content_transitions n2
             where n2.content_id = d.content_id and n2.kind = 'editorial' and n2.to_status = 'in_review' and n2.id > d.id) end back_at
      from dec d left join content_transition_reasons x on x.transition_id = d.id left join rework_reasons r on r.id = x.reason_id
      where d.to_status in ('changes_requested', 'rejected')),
    months as (select (date_trunc('month', now() at time zone tz) - make_interval(months => i))::date m from generate_series(0, n - 1) i),
    per as (
      select mo.m,
        (select count(*) from dec where dec.m = mo.m) decisions,
        (select count(*) from rw where rw.m = mo.m and rw.to_status = 'changes_requested') changes,
        (select count(*) from rw where rw.m = mo.m and rw.to_status = 'rejected') rejected,
        (select count(distinct content_id) from dec where dec.m = mo.m) contents,
        (select count(distinct content_id) from rw where rw.m = mo.m) contents_rework,
        (select count(*) from rw where rw.m = mo.m and rw.to_status = 'changes_requested' and rw.back_at is not null) cycles_closed,
        (select count(*) from rw where rw.m = mo.m and rw.to_status = 'changes_requested' and rw.back_at is null) cycles_open,
        (select round((sum(extract(epoch from rw.back_at - rw.at)) / 3600)::numeric, 1) from rw where rw.m = mo.m and rw.back_at is not null) hours_lost,
        (select round((percentile_cont(0.5) within group (order by extract(epoch from rw.back_at - rw.at)) / 3600)::numeric, 1)
           from rw where rw.m = mo.m and rw.back_at is not null) hours_median
      from months mo),
    byr as (select m, coalesce(code, 'sem_categoria') code, max(case when code is null then 'Sem categoria' else label end) label,
                   count(*) filter (where to_status = 'changes_requested') changes, count(*) filter (where to_status = 'rejected') rejected,
                   round((sum(extract(epoch from back_at - at)) filter (where back_at is not null) / 3600)::numeric, 1) hours_lost
            from rw group by m, coalesce(code, 'sem_categoria'))
    select jsonb_build_object(
      'timezone', tz, 'months', n, 'since', since,
      'stages', jsonb_build_array(
        jsonb_build_object('key', 'guiao', 'label', 'Guião (revisão editorial)', 'available', true),
        jsonb_build_object('key', 'video', 'label', 'Vídeo (revisão de media)', 'available', false,
                           'reason', 'A revisão de vídeos ainda não existe na app. Os motivos marcados para vídeo ficam prontos para quando existir.')),
      'reasons', public._rework_reasons_json(p_ws),
      'by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(per.m, 'YYYY-MM'), 'stage', 'guiao',
          'decisions', decisions, 'changes', changes, 'rejected', rejected, 'contents', contents, 'contents_rework', contents_rework,
          'rework_rate', case when decisions > 0 then round((changes + rejected)::numeric / decisions, 3) end,
          'cycles_closed', cycles_closed, 'cycles_open', cycles_open, 'hours_lost', coalesce(hours_lost, 0), 'hours_median', hours_median,
          'by_reason', coalesce((select jsonb_agg(jsonb_build_object('code', b.code, 'label', b.label, 'changes', b.changes, 'rejected', b.rejected,
                              'hours_lost', coalesce(b.hours_lost, 0)) order by (b.changes + b.rejected) desc, b.code) from byr b where b.m = per.m), '[]'))
        order by per.m desc) from per), '[]'),
      'totals', jsonb_build_object(
        'decisions', (select count(*) from dec), 'changes', (select count(*) from rw where to_status = 'changes_requested'),
        'rejected', (select count(*) from rw where to_status = 'rejected'),
        'uncategorized', (select count(*) from rw where code is null),
        'rework_rate', (select case when count(*) > 0 then round((select count(*) from rw)::numeric / count(*), 3) end from dec),
        'hours_lost', coalesce((select round((sum(extract(epoch from back_at - at)) / 3600)::numeric, 1) from rw where back_at is not null), 0),
        'cycles_open', (select count(*) from rw where to_status = 'changes_requested' and back_at is null)),
      'by_reason', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'changes', ch, 'rejected', rj, 'hours_lost', coalesce(hl, 0))
                                               order by ch + rj desc, code)
          from (select coalesce(code, 'sem_categoria') code, max(case when code is null then 'Sem categoria' else label end) label,
                       count(*) filter (where to_status = 'changes_requested') ch, count(*) filter (where to_status = 'rejected') rj,
                       round((sum(extract(epoch from back_at - at)) filter (where back_at is not null) / 3600)::numeric, 1) hl
                from rw group by coalesce(code, 'sem_categoria')) z), '[]')));
end $$;

revoke all on function public._learn_require(text, text, text, text, text), public._rework_defaults(), public._rework_reasons_json(text)
  from public, anon, authenticated;
revoke all on function public.rework_reasons_list(text, text), public.rework_reasons_seed(text, text), public.rework_reason_save(text, uuid, jsonb, text),
  public.content_transition_reasoned(text, text, text, text, integer, text), public.rework_dashboard(text, int, text) from public;
grant execute on function public.rework_reasons_list(text, text), public.rework_reasons_seed(text, text), public.rework_reason_save(text, uuid, jsonb, text),
  public.content_transition_reasoned(text, text, text, text, integer, text), public.rework_dashboard(text, int, text) to anon, authenticated;
-- anon só passa com código de equipa válido (_content_require/_content_actor recusam sem sessão nem código).

/* Rollback (compatível: nada do que existia mudou):
   drop function public.rework_dashboard(text, int, text), public.content_transition_reasoned(text, text, text, text, integer, text),
     public.rework_reason_save(text, uuid, jsonb, text), public.rework_reasons_seed(text, text), public.rework_reasons_list(text, text),
     public._rework_reasons_json(text), public._rework_defaults(), public._learn_require(text, text, text, text, text);
   delete from feature_flags where key = 'learn.rework'; delete from feature_flag_defs where key = 'learn.rework';
   delete from role_capabilities where capability in ('learn.read', 'learn.manage');  -- (só depois do rollback das migrações 120200/120300)
-- contract posterior (só depois de exportar): drop table public.content_transition_reasons, public.rework_reasons; */
