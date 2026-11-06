-- W10-14 · Notificações de prazos e alterações (PRD FR-11-04, TEAM-12; FR-15-05, FR-16-03, FR-16-04, FR-17-06; ADR-0061).
-- Expand (aditivo). Até aqui só havia notificações de atribuição; prazos e mudanças de prazo não avisavam ninguém.
--   (a) tarefas com prazo nas próximas 24 h e tarefas atrasadas: avisa o responsável, uma vez por limiar e por valor de due_at
--       (mudar o prazo volta a armar os dois avisos);
--   (b) guiões com gravação amanhã (fuso do cliente) ainda por aprovar: avisa o responsável do guião e quem aprova guiões;
--   (c) vídeos em revisão com o prazo passado (a mesma regra do calendário, W9-03): avisa quem tem a tarefa e quem decide;
--   (d) mudança do prazo de uma tarefa: avisa o responsável (mudança de responsável já avisa os dois: task_update,
--       task_delegate e remoção de membro, sem alteração aqui).
-- Tudo passa por _notify (acesso atual de quem recebe, quem age não se avisa, preferências do cliente e da pessoa, dedup).
-- Os avisos agendados correm numa função SQL de 15 em 15 min (pg_cron, como agent-schedule-tick) e guardam cada envio em
-- notification_deadline_sent: o mesmo limiar nunca sai duas vezes, mesmo quando foi suprimido por preferência.
-- Flag notifications.deadlines (fase owner): verificada para quem recebe, no momento do envio.
-- Nenhuma capacidade nova: quem recebe é decidido por capacidades existentes (tasks.read, scripts.read, scripts.approve,
-- media.read, review.approve), verificadas no momento do envio. Nunca se avisa ninguém de outro cliente.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('notifications.deadlines', 'Notificações de prazos', 'Definições', 'ws', 'owner',
   'Avisos de prazos e alterações (FR-11-04, TEAM-12): tarefas a terminar em 24 h e atrasadas, guiões por aprovar com gravação amanhã, revisões de vídeo atrasadas e mudanças de prazo. Só na app.')
on conflict (key) do nothing;

-- ───────────── catálogo: tipos novos (o check é alargado a partir da definição atual, para manter os de outras migrações) ─────────────
do $$
declare def text; kinds text[]; add text[] := array['task_due_soon','task_overdue','task_due_changed','script_unapproved_recording','video_review_overdue'];
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  if def is null then raise exception 'notifications_kind_check em falta: rever W10-14'; end if;
  kinds := array(select m[1] from regexp_matches(def, '''([a-z_]+)''', 'g') m);
  if add <@ kinds then return; end if;
  kinds := kinds || array(select x from unnest(add) x where not (x = any (kinds)));
  alter table public.notifications drop constraint notifications_kind_check;
  execute format('alter table public.notifications add constraint notifications_kind_check check (kind in (%s))',
                 (select string_agg(quote_literal(k), ', ') from unnest(kinds) k));
end $$;

-- grupo novo "prazos" nas preferências (mesma técnica: a partir da definição atual)
do $$
declare def text; groups text[];
begin
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.notification_event_defs'::regclass and conname = 'notification_event_defs_group_key_check';
  if def is null then raise exception 'notification_event_defs_group_key_check em falta: rever W10-14'; end if;
  groups := array(select m[1] from regexp_matches(def, '''([a-z_]+)''', 'g') m);
  if 'prazos' = any (groups) then return; end if;
  alter table public.notification_event_defs drop constraint notification_event_defs_group_key_check;
  execute format('alter table public.notification_event_defs add constraint notification_event_defs_group_key_check check (group_key in (%s))',
                 (select string_agg(quote_literal(k), ', ') from unnest(groups || array['prazos']) k));
end $$;

insert into public.notification_event_defs (kind, group_key, label, description, recipients, channels, default_channels, mandatory, mandatory_reason, sort) values
  ('task_due_soon', 'prazos', 'Tarefa minha a terminar em 24 horas', 'Uma tarefa tua por fechar tem o prazo nas próximas 24 horas.',
   'Quem é responsável pela tarefa', '{in_app,email,digest}', '{in_app}', false, null, 310),
  ('task_overdue', 'prazos', 'Tarefa minha atrasada', 'Uma tarefa tua passou o prazo e ainda não está fechada.',
   'Quem é responsável pela tarefa', '{in_app,email,digest}', '{in_app}', false, null, 320),
  ('task_due_changed', 'prazos', 'Prazo de uma tarefa minha mudou', 'Alguém mudou ou tirou o prazo de uma tarefa tua.',
   'Quem é responsável pela tarefa', '{in_app,email,digest}', '{in_app}', false, null, 330),
  ('script_unapproved_recording', 'prazos', 'Guião por aprovar com gravação amanhã', 'Um guião marcado para gravar amanhã (no fuso do cliente) ainda não está aprovado.',
   'Quem é responsável pelo guião e quem aprova guiões no cliente', '{in_app,email,digest}', '{in_app}', false, null, 340),
  ('video_review_overdue', 'prazos', 'Revisão de vídeo atrasada', 'Um vídeo continua por rever, ou com alterações por fazer, depois do prazo da revisão (o mesmo do calendário).',
   'Quem tem a tarefa de revisão; quem decide revisões (vídeo em revisão) ou quem registou o vídeo (alterações pedidas)', '{in_app,email,digest}', '{in_app}', false, null, 350)
on conflict (kind) do update set group_key = excluded.group_key, label = excluded.label, description = excluded.description, recipients = excluded.recipients,
  channels = excluded.channels, default_channels = excluded.default_channels, mandatory = excluded.mandatory, mandatory_reason = excluded.mandatory_reason, sort = excluded.sort;

-- ───────────── registo dos avisos agendados (idempotência) ─────────────
-- Uma linha por pessoa e limiar (dedup_key). Fechada à API. Limpa ao fim de 45 dias (as janelas olham no máximo 7 dias para trás).
create table if not exists public.notification_deadline_sent (
  user_id uuid not null references auth.users(id) on delete cascade,
  dedup_key text not null check (length(dedup_key) <= 200),
  workspace_id text not null references public.clients(id),
  kind text not null,
  delivered boolean not null,
  created_at timestamptz not null default now(),
  primary key (user_id, dedup_key)
);
create index if not exists notification_deadline_sent_created on public.notification_deadline_sent (created_at);
create index if not exists notification_deadline_sent_ws on public.notification_deadline_sent (workspace_id);
alter table public.notification_deadline_sent enable row level security;
revoke all on public.notification_deadline_sent from anon, authenticated;

-- índice para a janela das tarefas abertas com responsável e prazo
create index if not exists tasks_open_due on public.tasks (due_at) where status in ('todo','doing','blocked') and assignee_id is not null and due_at is not null;

-- ───────────── envio de um aviso agendado ─────────────
-- Só quem tem a flag, acesso atual ao cliente (tasks.read) e a capacidade pedida; uma vez por (pessoa, limiar).
-- delivered = a notificação foi criada (false quando _notify a suprimiu por preferência). Devolve true se criou.
create or replace function public._deadline_send(p_user uuid, p_ws text, p_cap text, p_kind text, p_entity_type text, p_entity_id text,
                                                 p_title text, p_body text, p_dedup text) returns boolean
language plpgsql security definer set search_path = public as $$
declare made boolean;
begin
  if p_user is null or p_ws is null then return false; end if;
  if not public._flag_on_for('notifications.deadlines', p_ws, p_user) then return false; end if;
  if not public._authorize('tasks.read', p_ws, p_user) then return false; end if;
  if p_cap is not null and not public._authorize(p_cap, p_ws, p_user) then return false; end if;
  insert into notification_deadline_sent (user_id, dedup_key, workspace_id, kind, delivered)
  values (p_user, p_dedup, p_ws, p_kind, false)
  on conflict (user_id, dedup_key) do nothing;
  if not found then return false; end if;                                -- este limiar já foi tratado
  perform public._notify(p_user, p_ws, p_kind, p_entity_type, p_entity_id, p_title, p_body, p_dedup);
  made := exists (select 1 from notifications where user_id = p_user and dedup_key = p_dedup);
  if made then update notification_deadline_sent set delivered = true where user_id = p_user and dedup_key = p_dedup; end if;
  return made;
end $$;

create or replace function public._deadline_fmt(p_at timestamptz, p_tz text) returns text
language sql stable set search_path = public as $$
  select to_char(p_at at time zone coalesce(p_tz, 'UTC'), 'DD/MM "às" HH24:MI') || ' (' || coalesce(p_tz, 'UTC') || ')'
$$;

-- ───────────── o tick (de 15 em 15 minutos) ─────────────
-- p_now só existe para os testes (fronteiras de fuso); o pg_cron chama sem argumentos.
create or replace function public.deadline_notify_tick(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; u uuid; k text; n_soon int := 0; n_over int := 0; n_script int := 0; n_review int := 0; today date;
begin
  -- dois ticks ao mesmo tempo: o segundo não faz nada (o registo já impediria repetidos)
  if not pg_try_advisory_xact_lock(hashtext('deadline_notify_tick')) then return jsonb_build_object('skipped', true); end if;

  -- (a) tarefas abertas com responsável: prazo nas próximas 24 h, ou atrasadas há no máximo 7 dias
  for r in select t.id, t.workspace_id, t.title, t.due_at, t.assignee_id, c.timezone tz
             from tasks t join clients c on c.id = t.workspace_id
            where c.status = 'active' and t.status in ('todo','doing','blocked') and t.assignee_id is not null
              and t.due_at > p_now - interval '7 days' and t.due_at <= p_now + interval '24 hours' loop
    k := case when r.due_at <= p_now then 'task_overdue' else 'task_due_soon' end;
    if public._deadline_send(r.assignee_id, r.workspace_id, 'tasks.read', k, 'task', r.id::text,
         case k when 'task_overdue' then 'Tarefa atrasada: ' else 'Prazo nas próximas 24 horas: ' end || r.title,
         case k when 'task_overdue' then 'O prazo era ' else 'Termina ' end || public._deadline_fmt(r.due_at, r.tz) || '.',
         k || ':' || r.id || ':' || floor(extract(epoch from r.due_at))::bigint) then
      if k = 'task_overdue' then n_over := n_over + 1; else n_soon := n_soon + 1; end if;
    end if;
  end loop;

  -- (b) guiões com gravação amanhã no fuso do cliente e ainda por aprovar
  for r in select g.id, g.client_id ws, g.n, g.tema, g.date, g.owner_id, c.require_approval_to_record req
             from guioes g join clients c on c.id = g.client_id
            where c.status = 'active' and g.deleted_at is null
              and g.date = (p_now at time zone coalesce(c.timezone, 'UTC'))::date + 1
              and g.editorial_status in ('draft','in_review','changes_requested')
              and g.production_status in ('not_started','scheduled') loop
    for u in select x from (
               select r.owner_id x where public._authorize('scripts.read', r.ws, r.owner_id)
               union
               select a.user_id from workspace_access a
                where a.workspace_id = r.ws and a.status = 'active' and public._authorize('scripts.approve', r.ws, a.user_id)) z
              where x is not null loop
      if public._deadline_send(u, r.ws, 'scripts.read', 'script_unapproved_recording', 'content', r.id,
           'Gravação amanhã, guião ' || r.n || ' por aprovar' || coalesce(': ' || r.tema, ''),
           case when r.req then 'Este cliente só grava guiões aprovados: sem aprovação a gravação não avança.'
                else 'A gravação está marcada para amanhã e o guião ainda não foi aprovado.' end,
           'script_unapproved_recording:' || r.id || ':' || r.date) then
        n_script := n_script + 1;
      end if;
    end loop;
  end loop;

  -- (c) revisões de vídeo atrasadas: a regra do calendário (W9-03, calendar_range): prazo = a tarefa de revisão/edição aberta
  --     com prazo mais cedo, senão o dia do guião; atrasada quando esse dia já passou no fuso do cliente (até 7 dias)
  for r in select x.* from (
             select a.id asset_id, a.workspace_id ws, a.title, a.created_by, v.id version_id, v.version_no, v.uploaded_by,
                    public._review_status(v.id) status, g.n, t.id task_id, t.assignee_id,
                    coalesce((t.due_at at time zone coalesce(c.timezone, 'UTC'))::date, g.date) due_day,
                    (p_now at time zone coalesce(c.timezone, 'UTC'))::date today
               from media_assets a join clients c on c.id = a.workspace_id and c.status = 'active'
               join guioes g on g.id = a.content_id and g.client_id = a.workspace_id
               join media_versions v on v.id = a.current_version_id
               left join lateral (select * from tasks k where k.workspace_id = a.workspace_id and k.content_id = g.id
                                    and k.status in ('todo','doing','blocked') and k.kind in ('review','edit') and k.due_at is not null
                                  order by k.due_at limit 1) t on true
              where a.lifecycle = 'ativo' and public._review_eligible(v) and g.deleted_at is null
                and public._review_status(v.id) in ('in_review', 'changes_requested')) x
            where x.due_day < x.today and x.due_day >= x.today - 7 loop
    for u in select y from (
               select r.assignee_id y
               union
               select a.user_id from workspace_access a
                where r.status = 'in_review' and a.workspace_id = r.ws and a.status = 'active' and public._authorize('review.approve', r.ws, a.user_id)
               union select r.created_by where r.status = 'changes_requested'
               union select r.uploaded_by where r.status = 'changes_requested') z
              where y is not null loop
      if public._flag_on_for('media.library', r.ws, u)
         and public._deadline_send(u, r.ws, 'media.read', 'video_review_overdue', 'media_asset', r.asset_id::text,
           case r.status when 'in_review' then 'Revisão atrasada: ' else 'Alterações atrasadas: ' end
             || coalesce(r.title, 'sem título') || ' (v' || r.version_no || ')',
           'Guião ' || r.n || ' · o prazo da revisão era ' || to_char(r.due_day, 'DD/MM') || '.',
           'video_review_overdue:' || r.version_id || ':' || r.due_day) then
        n_review := n_review + 1;
      end if;
    end loop;
  end loop;

  delete from notification_deadline_sent where created_at < p_now - interval '45 days';
  return jsonb_build_object('task_due_soon', n_soon, 'task_overdue', n_over, 'script_unapproved_recording', n_script, 'video_review_overdue', n_review);
end $$;

-- ───────────── (d) mudança do prazo de uma tarefa ─────────────
-- Avisa o responsável (quem muda não se avisa: _notify). Se o responsável também mudou no mesmo passo, o aviso de
-- atribuição já diz tudo. Falhar o aviso nunca falha a alteração.
create or replace function public.tasks_due_changed_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.due_at is not distinct from old.due_at or new.assignee_id is null or new.assignee_id is distinct from old.assignee_id
     or new.status not in ('todo','doing','blocked') then return null; end if;
  if not public._flag_on_for('notifications.deadlines', new.workspace_id, new.assignee_id) then return null; end if;
  perform public._notify(new.assignee_id, new.workspace_id, 'task_due_changed', 'task', new.id::text,
    'Prazo alterado: ' || new.title,
    case when new.due_at is null then 'A tarefa ficou sem prazo.'
         else 'Novo prazo: ' || public._deadline_fmt(new.due_at, (select timezone from clients where id = new.workspace_id))
              || case when old.due_at is not null then ' (era ' || public._deadline_fmt(old.due_at, (select timezone from clients where id = new.workspace_id)) || ')' else '' end
              || '.' end,
    'due_changed:' || new.id || ':' || new.lock_version);
  return null;
exception when others then
  raise log 'tasks_due_changed_notify % falhou: % %', new.id, sqlstate, sqlerrm;
  return null;
end $$;
drop trigger if exists tasks_due_changed_notify on public.tasks;
create trigger tasks_due_changed_notify after update of due_at on public.tasks for each row execute function public.tasks_due_changed_notify();

-- ───────────── caixa (W6): os avisos de prazo contam como alerta, a mudança de prazo como tarefa ─────────────
-- Por substituição na definição atual (outras migrações também acrescentam tipos); falha se não encontrar a linha.
do $patch$
declare d text; old text := $o$else 'info' end$o$;
begin
  d := pg_get_functiondef('public._ops_category(text)'::regprocedure);
  if position('task_due_soon' in d) > 0 then return; end if;          -- já aplicado
  if position(old in d) = 0 then raise exception '_ops_category mudou: rever W10-14'; end if;
  execute replace(d, old, $n$when p_reason in ('task_due_soon','task_overdue','script_unapproved_recording','video_review_overdue') then 'alert'
    when p_reason = 'task_due_changed' then 'task'
    else 'info' end$n$);
end $patch$;

revoke all on function public._deadline_send(uuid, text, text, text, text, text, text, text, text), public._deadline_fmt(timestamptz, text),
  public.deadline_notify_tick(timestamptz), public.tasks_due_changed_notify() from public, anon, authenticated;

-- agenda: de 15 em 15 minutos
create extension if not exists pg_cron;
do $$ begin
  if not exists (select 1 from cron.job where jobname = 'deadline-notify-tick') then
    perform cron.schedule('deadline-notify-tick', '*/15 * * * *', 'select public.deadline_notify_tick()');
  end if;
end $$;

/* Rollback (compatível; o código da app não depende de nada daqui):
   select cron.unschedule('deadline-notify-tick');
   drop trigger if exists tasks_due_changed_notify on public.tasks;
   drop function if exists public.tasks_due_changed_notify(), public.deadline_notify_tick(timestamptz),
     public._deadline_send(uuid, text, text, text, text, text, text, text, text), public._deadline_fmt(timestamptz, text);
   reaplicar _ops_category da definição anterior (sem a linha dos tipos de prazo);
   drop index if exists public.tasks_open_due; drop table if exists public.notification_deadline_sent;
   delete from notifications where kind in ('task_due_soon','task_overdue','task_due_changed','script_unapproved_recording','video_review_overdue');
   delete from notification_suppressions where kind in (os mesmos); delete from notification_user_prefs where kind in (os mesmos);
   delete from notification_ws_prefs where kind in (os mesmos); delete from notification_event_defs where kind in (os mesmos);
   recriar notifications_kind_check e notification_event_defs_group_key_check a partir da definição atual sem esses valores;
   delete from feature_flags where key = 'notifications.deadlines'; delete from feature_flag_defs where key = 'notifications.deadlines'; */
