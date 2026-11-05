-- W9-04 · Pré-requisitos configuráveis nas transições de produção (PRD FR-17-05, FR-15-02; AGENTS §6; ADR-0051).
-- Cada cliente escolhe, por transição (agendar, marcar gravado, passar a edição, marcar pronto), que condições têm de se
-- verificar: guião aprovado, sem tarefas bloqueadas do guião, vídeo aprovado na revisão. content_production verifica no
-- servidor e recusa com 22023 'pre_requisito_em_falta' e um detalhe em PT com a causa e o próximo responsável.
-- A regra antiga "só se gravam guiões aprovados" (clients.require_approval_to_record) passa a ser a célula
-- gravado × guião aprovado desta matriz: continua guardada nessa coluna (fonte única; o ecrã antigo continua a funcionar).
-- Configurar: settings.manage (Definições). Ler: scripts.read. Só se aplica ao avançar (voltar atrás nunca é bloqueado).
-- Expand (só aditivo): 1 tabela fechada à API, funções novas; content_production com o mesmo corpo e a verificação nova no
-- lugar da antiga. Sem linhas = como hoje. Rollback no fim.

create table if not exists public.workflow_prerequisites (
  workspace_id text not null references public.clients(id),
  transition text not null check (transition in ('production.scheduled', 'production.recorded', 'production.editing', 'production.ready')),
  requirement text not null check (requirement in ('script_approved', 'no_blocked_tasks', 'video_approved')),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_label text,
  primary key (workspace_id, transition, requirement),
  -- a célula gravado × guião aprovado vive em clients.require_approval_to_record
  check (not (transition = 'production.recorded' and requirement = 'script_approved'))
);
alter table public.workflow_prerequisites enable row level security;
revoke all on public.workflow_prerequisites from anon, authenticated;

-- Catálogo fixo (a UI deriva dele): transições, condições e onde cada condição se aplica.
create or replace function public._prereq_catalog() returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'transitions', jsonb_build_array(
      jsonb_build_object('key', 'production.scheduled', 'label', 'Agendar gravação', 'to', 'scheduled'),
      jsonb_build_object('key', 'production.recorded', 'label', 'Marcar gravado', 'to', 'recorded'),
      jsonb_build_object('key', 'production.editing', 'label', 'Passar a edição', 'to', 'editing'),
      jsonb_build_object('key', 'production.ready', 'label', 'Marcar pronto', 'to', 'ready')),
    'requirements', jsonb_build_array(
      jsonb_build_object('key', 'script_approved', 'label', 'Guião aprovado',
        'applies', jsonb_build_array('production.scheduled', 'production.recorded', 'production.editing', 'production.ready')),
      jsonb_build_object('key', 'no_blocked_tasks', 'label', 'Sem tarefas bloqueadas do guião',
        'applies', jsonb_build_array('production.scheduled', 'production.recorded', 'production.editing', 'production.ready')),
      jsonb_build_object('key', 'video_approved', 'label', 'Vídeo aprovado na revisão',
        'applies', jsonb_build_array('production.ready'))))
$$;

create or replace function public._prereq_applies(p_transition text, p_requirement text) returns boolean
language sql immutable set search_path = public as $$
  select exists (select 1 from jsonb_array_elements(public._prereq_catalog()->'requirements') r
                 where r->>'key' = p_requirement and r->'applies' ? p_transition)
$$;

-- Está ligada? (gravado × aprovado lê a coluna antiga)
create or replace function public._prereq_on(p_ws text, p_transition text, p_requirement text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_transition = 'production.recorded' and p_requirement = 'script_approved'
              then coalesce((select require_approval_to_record from clients where id = p_ws), false)
              else coalesce((select enabled from workflow_prerequisites
                             where workspace_id = p_ws and transition = p_transition and requirement = p_requirement), false) end
$$;

create or replace function public._prod_rank(s text) returns int
language sql immutable set search_path = public as $$
  select case s when 'not_started' then 0 when 'scheduled' then 1 when 'recording' then 2 when 'recorded' then 3
                when 'editing' then 4 when 'ready' then 5 when 'published' then 6 else -1 end
$$;

-- Lista das condições em falta para levar o guião a p_to (vazia = pode). Cada uma com causa e próximo responsável.
create or replace function public._prereq_missing(g guioes, p_fr text, p_to text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tr text := 'production.' || p_to; out jsonb := '[]'; who text; n int; k int; st text;
begin
  if public._prod_rank(p_to) <= public._prod_rank(p_fr) then return out; end if;   -- voltar atrás / cancelar: sem condições
  if public._prereq_on(g.client_id, tr, 'script_approved') and g.editorial_status <> 'approved' then
    who := (select coalesce(nullif(p.display_name, ''), u.email) from auth.users u left join profiles p on p.user_id = u.id where u.id = g.owner_id);
    st := case g.editorial_status when 'draft' then 'rascunho' when 'in_review' then 'em revisão' when 'changes_requested' then 'com alterações pedidas'
                                  when 'rejected' then 'rejeitado' else g.editorial_status end;
    out := out || jsonb_build_array(jsonb_build_object('requirement', 'script_approved',
      'cause', 'o guião ainda não está aprovado (está ' || st || ')',
      'next', 'aprova-o em Guiões quem tem "Aprovar guiões"' || coalesce(' (responsável do guião: ' || who || ')', '')));
  end if;
  if public._prereq_on(g.client_id, tr, 'no_blocked_tasks') then
    select count(*), min(coalesce(nullif(p.display_name, ''), u.email)) into n, who
      from tasks t left join auth.users u on u.id = t.assignee_id left join profiles p on p.user_id = t.assignee_id
     where t.content_id = g.id and t.status = 'blocked';
    if n > 0 then
      out := out || jsonb_build_array(jsonb_build_object('requirement', 'no_blocked_tasks',
        'cause', n || ' tarefa(s) do guião bloqueada(s)',
        'next', 'desbloqueia-as em Tarefas' || coalesce(' (responsável: ' || who || ')', '')));
    end if;
  end if;
  if public._prereq_on(g.client_id, tr, 'video_approved') then
    select count(*), count(*) filter (where public._review_status(v.id) <> 'approved') into n, k
      from media_assets a join media_versions v on v.id = a.current_version_id
     where a.workspace_id = g.client_id and a.content_id = g.id and a.lifecycle = 'ativo' and v.state = 'pronta'
       and a.kind in ('video', 'link_externo');
    if n = 0 or k > 0 then
      out := out || jsonb_build_array(jsonb_build_object('requirement', 'video_approved',
        'cause', case when n = 0 then 'ainda não há vídeo deste guião na revisão' else k || ' vídeo(s) por aprovar na revisão' end,
        'next', 'aprova-o em Revisão → Vídeos quem tem "Aprovar vídeos"'));
    end if;
  end if;
  return out;
end $$;

-- Recusa a transição com a causa e o próximo responsável (FR-17-05: "cada bloqueio mostra causa e próximo responsável").
create or replace function public._prereq_check(g guioes, p_fr text, p_to text) returns void
language plpgsql stable security definer set search_path = public as $$
declare m jsonb := public._prereq_missing(g, p_fr, p_to); lbl text;
begin
  if jsonb_array_length(m) = 0 then return; end if;
  lbl := (select t->>'label' from jsonb_array_elements(public._prereq_catalog()->'transitions') t where t->>'to' = p_to);
  raise exception 'pre_requisito_em_falta' using errcode = '22023',
    detail = 'Não dá para ' || lower(coalesce(lbl, p_to)) || ' o guião ' || g.n || ': '
             || (select string_agg((x->>'cause') || ' — ' || (x->>'next'), '; ') from jsonb_array_elements(m) x) || '.',
    hint = m::text;
end $$;

-- Ler a matriz do cliente (e o que falta a um guião, se p_content vier): scripts.read.
create or replace function public.workflow_prereqs(p_ws text, p_content text default null, p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g guioes; cat jsonb := public._prereq_catalog();
begin
  perform public._content_require('scripts.read', p_ws, p_token, 'workflow.prereqs', p_content);
  if p_content is not null then
    select * into g from guioes where id = p_content and client_id = p_ws;
    if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('catalog', cat,
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('transition', t->>'key', 'requirement', r->>'key',
                'enabled', public._prereq_on(p_ws, t->>'key', r->>'key'))), '[]')
              from jsonb_array_elements(cat->'transitions') t, jsonb_array_elements(cat->'requirements') r
              where r->'applies' ? (t->>'key')),
    'missing', case when g.id is null then null else (
       select jsonb_object_agg(t->>'to', public._prereq_missing(g, g.production_status, t->>'to'))
         from jsonb_array_elements(cat->'transitions') t) end,
    'can', jsonb_build_object('manage', public.ws_can('settings.manage', p_ws, p_token)));
end $$;

-- Ligar/desligar uma condição: settings.manage, sessão individual, auditado (antes/depois).
create or replace function public.workflow_prereq_set(p_ws text, p_transition text, p_requirement text, p_enabled boolean,
                                                      p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare before boolean; lbl text;
begin
  if auth.uid() is null then raise exception 'sessao_individual' using errcode = '42501'; end if;
  perform public._content_require('settings.manage', p_ws, p_token, 'workflow.prerequisite_set', null);
  if p_enabled is null or not public._prereq_applies(p_transition, p_requirement) then
    raise exception 'regra_invalida' using errcode = '22023', detail = 'Esta condição não existe para esta transição.'; end if;
  before := public._prereq_on(p_ws, p_transition, p_requirement);
  if before = p_enabled then return public.workflow_prereqs(p_ws, null, p_token); end if;
  lbl := (select email from auth.users where id = auth.uid());
  if p_transition = 'production.recorded' and p_requirement = 'script_approved' then
    update clients set require_approval_to_record = p_enabled where id = p_ws;
  else
    insert into workflow_prerequisites (workspace_id, transition, requirement, enabled, updated_by, updated_label)
    values (p_ws, p_transition, p_requirement, p_enabled, auth.uid(), lbl)
    on conflict (workspace_id, transition, requirement)
    do update set enabled = excluded.enabled, updated_at = now(), updated_by = excluded.updated_by, updated_label = excluded.updated_label;
  end if;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, before, after)
  values (auth.uid(), 'user', lbl, p_ws, 'workflow.prerequisite_set', 'workflow_prerequisite', p_transition || ':' || p_requirement,
          jsonb_build_object('enabled', before), jsonb_build_object('enabled', p_enabled));
  return public.workflow_prereqs(p_ws, null, p_token);
end $$;

revoke all on function public._prereq_catalog(), public._prereq_applies(text, text), public._prereq_on(text, text, text), public._prod_rank(text),
  public._prereq_missing(guioes, text, text), public._prereq_check(guioes, text, text) from public, anon, authenticated;
revoke all on function public.workflow_prereqs(text, text, text), public.workflow_prereq_set(text, text, text, boolean, text) from public;
grant execute on function public.workflow_prereqs(text, text, text), public.workflow_prereq_set(text, text, text, boolean, text) to anon, authenticated;

-- content_production: corpo igual; a verificação de require_approval_to_record passa para _prereq_check (depois do "já está").

CREATE OR REPLACE FUNCTION public.content_production(p_id text, p_to text, p_token text DEFAULT NULL::text)
 RETURNS guioes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g guioes; a jsonb := public._content_actor(p_token); fr text; corr uuid := gen_random_uuid(); req boolean; cap text; ev text;
begin
  select * into g from guioes where id = p_id for update;
  if g.id is null then raise exception 'guiao_nao_encontrado' using errcode = 'P0002'; end if;
  fr := g.production_status;
  if p_to not in ('not_started','scheduled','recorded','editing','ready','cancelled') then raise exception 'estado_invalido' using errcode = '22023'; end if;
  cap := case
    when p_to = 'recorded' and fr in ('not_started','scheduled','recording','recorded') then 'recording.confirm'
    when p_to = 'recorded' and fr = 'editing' then 'production.update'
    when p_to = 'not_started' and fr in ('recorded','recording','not_started') then 'recording.confirm'
    when p_to = 'not_started' and fr in ('scheduled','cancelled') then 'calendar.schedule'
    when p_to = 'scheduled' and fr in ('not_started','scheduled') then 'calendar.schedule'
    when p_to = 'editing' and fr in ('recorded','ready','editing') then 'production.update'
    when p_to = 'ready' and fr in ('editing','ready') then 'production.update'
    when p_to = 'cancelled' and fr not in ('published') then 'calendar.schedule'
  end;
  if cap is null then
    perform public._content_require('scripts.read', g.client_id, p_token, 'production.transition', g.id);
    raise exception 'transicao_invalida' using errcode = '22023';
  end if;
  perform public._content_require(cap, g.client_id, p_token, 'production.' || p_to, g.id);
  if p_to in ('scheduled','recorded') then
    if g.editorial_status in ('rejected','archived') then raise exception 'nao_elegivel' using errcode = '22023'; end if;
  end if;
  if fr = p_to then return g; end if;
  -- pré-requisitos configuráveis do cliente (FR-17-05, W9-04); inclui o antigo 'só se gravam guiões aprovados'
  perform public._prereq_check(g, fr, p_to);
  update guioes set production_status = p_to,
                    gravado = p_to in ('recorded','editing','ready','published'),
                    gravado_em = case when p_to in ('recorded','editing','ready','published') then coalesce(gravado_em, now()) else null end,
                    updated_at = now()
   where id = p_id returning * into g;
  ev := case when p_to = 'recorded' and fr in ('not_started','scheduled','recording') then 'recording.confirmed'
             when p_to = 'not_started' and fr in ('recorded','recording') then 'recording.undone'
             else 'production.' || p_to end;
  perform public._content_log(g, 'production', fr, p_to, g.current_version_id, null, a, ev, corr);
  return g;
end $function$;


/* Rollback (compatível; as regras configuradas perdem-se, a de gravar continua em clients.require_approval_to_record):
   1. Repor content_production a partir de 20261029074048_w3_calendar_production.sql.
   2. drop function public.workflow_prereq_set(text, text, text, boolean, text), public.workflow_prereqs(text, text, text),
        public._prereq_check(guioes, text, text), public._prereq_missing(guioes, text, text), public._prod_rank(text),
        public._prereq_on(text, text, text), public._prereq_applies(text, text), public._prereq_catalog();
   3. drop table public.workflow_prerequisites;
*/
