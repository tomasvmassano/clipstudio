-- W10-23 · STU-03: notificação agrupada dos pacotes por guião (decisão do responsável de produto, 2026-11-09). ADR-0072.
-- Uma sessão de gravação tem ~30 guiões: o pacote por guião (ADR-0070) criava até 30 notificações "Pacote de edição pronto".
-- Passa a haver UMA notificação por cliente, por pessoa a notificar e por lote de gravação, atualizada à medida que os
-- pacotes acabam ("Pacotes por guião prontos: 7 de 12"), de novo por ler quando a contagem muda, e com estado final quando
-- todos acabaram (prontos ou falhados, "3 falharam" com os guiões nomeados).
-- Expand (aditivo e compatível com o código do main e com o worker de hoje):
--   1. package_script_batches / package_script_batch_items (fechadas): o lote (sessão do teleprompter das gravações ligadas,
--      se se sabe; senão o dia local do cliente em que o job foi pedido) e um item por guião com o job atual e o resultado.
--      Item por guião, não por job: voltar a pedir um guião que falhou substitui o item (o total não cresce).
--   2. Trigger AFTER INSERT em media_jobs (pacote por guião com created_by): junta o job ao lote. Nunca falha o pedido.
--   3. Trigger AFTER UPDATE OF status: resultado final do job (done -> pronto; failed/dead -> falhou; cancelled -> sai das
--      contas). Só conta se o resultado do item mudar (repetições e retries não contam duas vezes). Advisory lock por lote.
--   4. _package_script_batch_notify: a mesma regra de destinatário de hoje (quem pediu o job, via _notify: acesso atual,
--      preferências e silêncio, nunca a própria pessoa que age); tipo 'video_decision' como hoje; entity_type
--      'package_script_batch' (a app leva a Edição automática). domain_event package_script.batch_progress a cada mudança
--      e audit edit.package_script_batch_done no estado final.
--   5. _media_package_done (corpo atual de 20261105192728_w5_edit_package.sql): ignora os pacotes com mode = 'script'.
--      Pacotes da sessão: exatamente como hoje.

create table if not exists public.package_script_batches (
  id uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.clients(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  batch_key text not null check (batch_key ~ '^(session:[0-9a-f-]{36}|day:[0-9]{4}-[0-9]{2}-[0-9]{2})$'),
  session_id uuid references public.recording_sessions(id) on delete set null,
  day date,
  notified_total int, notified_done int, notified_failed int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, user_id, batch_key)
);
alter table public.package_script_batches enable row level security;
revoke all on public.package_script_batches from anon, authenticated;

create table if not exists public.package_script_batch_items (
  batch_id uuid not null references public.package_script_batches(id) on delete cascade,
  workspace_id text not null references public.clients(id),
  content_id text not null references public.guioes(id),
  job_id uuid not null references public.media_jobs(id),
  outcome text check (outcome is null or outcome in ('done', 'failed', 'cancelled')),
  finished_at timestamptz,
  primary key (batch_id, content_id)
);
create unique index if not exists package_script_batch_items_job on public.package_script_batch_items (job_id);
alter table public.package_script_batch_items enable row level security;
revoke all on public.package_script_batch_items from anon, authenticated;

-- Texto da notificação (função pura, testada no SQL; a app mostra title/body tal como vêm).
create or replace function public._package_script_batch_text(p_total int, p_done int, p_failed int, p_failed_names text)
returns jsonb language sql immutable set search_path = public as $$
  select case
    when p_done + p_failed < p_total then jsonb_build_object(
      'title', 'Pacotes por guião prontos: ' || p_done || ' de ' || p_total
               || case when p_failed = 1 then ', 1 falhou' when p_failed > 1 then ', ' || p_failed || ' falharam' else '' end,
      'body', 'Ainda a preparar ' || (p_total - p_done - p_failed) || '. Abre Edição automática para rever e exportar os que já estão prontos.',
      'final', false)
    when p_failed = 0 then jsonb_build_object(
      'title', 'Pacotes por guião prontos: ' || p_done || ' de ' || p_total,
      'body', 'Todos prontos. Abre Edição automática para rever e exportar.', 'final', true)
    else jsonb_build_object(
      'title', 'Pacotes por guião terminados: ' || p_done || ' de ' || p_total || ' prontos, '
               || case when p_failed = 1 then '1 falhou' else p_failed || ' falharam' end,
      'body', 'Falharam: ' || coalesce(nullif(p_failed_names, ''), 'sem nome') || '. Abre Edição automática para voltar a pedir'
               || case when p_done > 0 then ' e rever os prontos.' else '.' end,
      'final', true)
  end
$$;

-- Atualiza (ou cria) a notificação do lote. Chamada com o lock do lote já tomado.
create or replace function public._package_script_batch_notify(p_batch uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b package_script_batches; tot int; dn int; fl int; names text; txt jsonb; dk text; nid uuid;
begin
  select * into b from package_script_batches where id = p_batch;
  if b.id is null then return; end if;
  select count(*) filter (where i.outcome is distinct from 'cancelled'), count(*) filter (where i.outcome = 'done'),
         count(*) filter (where i.outcome = 'failed'),
         string_agg(coalesce('guião ' || g.n, i.content_id), ', ' order by g.date, g.n, i.content_id) filter (where i.outcome = 'failed')
    into tot, dn, fl, names
    from package_script_batch_items i left join guioes g on g.id = i.content_id and g.client_id = i.workspace_id
   where i.batch_id = b.id;
  if tot = 0 or dn + fl = 0 then return; end if;                       -- nada acabou ainda: não avisa "0 de 12"
  if b.notified_total is not distinct from tot and b.notified_done is not distinct from dn and b.notified_failed is not distinct from fl then
    return; end if;                                                    -- a mesma contagem: não volta a pôr por ler
  txt := public._package_script_batch_text(tot, dn, fl, names);
  update package_script_batches set notified_total = tot, notified_done = dn, notified_failed = fl, updated_at = now() where id = b.id;
  dk := 'package_script_batch:' || b.id;
  select id into nid from notifications where user_id = b.user_id and dedup_key = dk;
  if nid is null then
    perform public._notify(b.user_id, b.workspace_id, 'video_decision', 'package_script_batch', b.id::text, txt->>'title', txt->>'body', dk);
  elsif b.user_id is distinct from auth.uid() and public._authorize('tasks.read', b.workspace_id, b.user_id)
        and public._notif_suppress_reason(b.user_id, b.workspace_id, 'video_decision') is null then
    -- a mesma regra de _notify (acesso atual, preferências, silêncio); volta ao topo da caixa e fica por ler
    update notifications set title = left(txt->>'title', 200), body = left(txt->>'body', 500), read_at = null, created_at = now()
     where id = nid and workspace_id = b.workspace_id;
  end if;
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (b.workspace_id, 'package_script.batch_progress', 'package_script_batch', b.id::text,
          jsonb_build_object('batch_key', b.batch_key, 'user_id', b.user_id, 'total', tot, 'done', dn, 'failed', fl, 'final', (txt->>'final')::boolean));
  if (txt->>'final')::boolean then
    perform public._package_script_audit(b.workspace_id, null, 'pacote por guião', 'edit.package_script_batch_done', 'package_script_batch', b.id::text,
      null, jsonb_build_object('batch_key', b.batch_key, 'user_id', b.user_id, 'total', tot, 'done', dn, 'failed', fl));
  end if;
end $$;

-- Job de pacote por guião criado: entra no lote de quem pediu. Nunca falha o pedido do pacote.
create or replace function public._package_script_batch_on_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare sess uuid; tz text; d date; k text; bid uuid;
begin
  if new.kind <> 'package' or new.input->>'mode' is distinct from 'script' or new.created_by is null
     or coalesce(new.input->>'guiao_id', '') = '' then return new; end if;
  select c.session_id into sess from recording_clips c
   where c.workspace_id = new.workspace_id and c.content_id = new.input->>'guiao_id' and c.session_id is not null
   order by (c.camera = 'side') desc, c.linked_at desc limit 1;
  if sess is not null then
    k := 'session:' || sess;
  else
    select coalesce(timezone, 'UTC') into tz from clients where id = new.workspace_id;
    d := (new.created_at at time zone coalesce(tz, 'UTC'))::date;
    k := 'day:' || to_char(d, 'YYYY-MM-DD');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('package_script_batch:' || new.workspace_id || ':' || new.created_by || ':' || k, 0));
  insert into package_script_batches (workspace_id, user_id, batch_key, session_id, day)
  values (new.workspace_id, new.created_by, k, sess, d)
  on conflict (workspace_id, user_id, batch_key) do nothing;
  select id into bid from package_script_batches where workspace_id = new.workspace_id and user_id = new.created_by and batch_key = k;
  perform pg_advisory_xact_lock(hashtextextended('package_script_batch:' || bid, 0));
  insert into package_script_batch_items (batch_id, workspace_id, content_id, job_id)
  values (bid, new.workspace_id, new.input->>'guiao_id', new.id)
  on conflict (batch_id, content_id) do update set job_id = excluded.job_id, outcome = null, finished_at = null;
  return new;
exception when others then
  raise log 'package_script_batch_insert_failed %', jsonb_build_object('job_id', new.id, 'error', sqlerrm);
  return new;
end $$;
drop trigger if exists media_jobs_package_script_batch_ins on public.media_jobs;
create trigger media_jobs_package_script_batch_ins after insert on public.media_jobs
  for each row when (new.kind = 'package') execute function public._package_script_batch_on_insert();

-- Resultado final de um job do lote: conta uma vez (só se o resultado do item mudar) e atualiza a notificação.
create or replace function public._package_script_batch_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare oc text; it package_script_batch_items;
begin
  if new.kind <> 'package' or new.input->>'mode' is distinct from 'script' or new.status is not distinct from old.status then return new; end if;
  oc := case new.status when 'done' then 'done' when 'failed' then 'failed' when 'dead' then 'failed' when 'cancelled' then 'cancelled' end;
  if oc is null then return new; end if;
  select * into it from package_script_batch_items where job_id = new.id;
  if it.batch_id is null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('package_script_batch:' || it.batch_id, 0));
  update package_script_batch_items set outcome = oc, finished_at = now()
   where job_id = new.id and workspace_id = new.workspace_id and outcome is distinct from oc;
  if not found then return new; end if;                                -- repetição: já contado
  perform public._package_script_batch_notify(it.batch_id);
  return new;
exception when others then
  raise log 'package_script_batch_status_failed %', jsonb_build_object('job_id', new.id, 'error', sqlerrm);
  return new;
end $$;
drop trigger if exists media_jobs_package_script_batch_st on public.media_jobs;
create trigger media_jobs_package_script_batch_st after update of status on public.media_jobs
  for each row when (new.kind = 'package') execute function public._package_script_batch_on_status();

-- Fim de um pacote: avisa quem pediu. Corpo de 20261105192728_w5_edit_package.sql; os pacotes por guião têm a notificação
-- agrupada acima.
create or replace function public._media_package_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if new.kind = 'package' and new.status = 'done' and old.status is distinct from 'done' and new.created_by is not null
     and new.input->>'mode' is distinct from 'script' then
    select count(*) into n from media_job_outputs where job_id = new.id;
    perform public._notify(new.created_by, new.workspace_id, 'video_decision', 'media_job', new.id::text,
      'Pacote de edição pronto: ' || n || ' vídeos para rever', 'Abre Edição automática para rever e exportar.', 'package:' || new.id);
  end if;
  return new;
end $$;

revoke all on function public._package_script_batch_text(int, int, int, text), public._package_script_batch_notify(uuid),
  public._package_script_batch_on_insert(), public._package_script_batch_on_status(), public._media_package_done()
  from public, anon, authenticated;

/* Rollback (compatível, por esta ordem; o código do main e o worker não dependem de nada disto):
   1. drop trigger if exists media_jobs_package_script_batch_st on public.media_jobs;
      drop trigger if exists media_jobs_package_script_batch_ins on public.media_jobs;
   2. repor _media_package_done de 20261105192728_w5_edit_package.sql (sem a condição de mode; volta uma notificação por job):
      create or replace function public._media_package_done() returns trigger language plpgsql security definer set search_path = public as $f$
      declare n int;
      begin
        if new.kind = 'package' and new.status = 'done' and old.status is distinct from 'done' and new.created_by is not null then
          select count(*) into n from media_job_outputs where job_id = new.id;
          perform public._notify(new.created_by, new.workspace_id, 'video_decision', 'media_job', new.id::text,
            'Pacote de edição pronto: ' || n || ' vídeos para rever', 'Abre Edição automática para rever e exportar.', 'package:' || new.id);
        end if;
        return new;
      end $f$;
   3. drop function if exists public._package_script_batch_on_status(), public._package_script_batch_on_insert(),
        public._package_script_batch_notify(uuid), public._package_script_batch_text(int, int, int, text);
   4. contract posterior (as notificações já criadas ficam na caixa; levam ao início se a app não conhecer o tipo):
      drop table public.package_script_batch_items; drop table public.package_script_batches. */
