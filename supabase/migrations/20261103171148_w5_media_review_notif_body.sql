-- W5-05: notificações da revisão de vídeo (FR-05-04, ADR-0044). Só acrescenta: dois tipos novos de notificação, os seus
-- eventos no catálogo de preferências (W8), dois triggers que avisam depois de uma decisão ou de um comentário, e o link
-- da caixa para o vídeo. As RPCs de revisão (W5-04) não mudam; falhar o aviso nunca falha a decisão nem o comentário.

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('task_assigned','task_unassigned','task_mention','task_auto','task_blocked','task_done','automation_error','script_mention','script_comment',
   'script_assigned','task_delegated','video_decision','video_comment'));

insert into public.notification_event_defs (kind, group_key, label, description, recipients, channels, default_channels, mandatory, mandatory_reason, sort) values
  ('video_decision', 'guioes', 'Decisão sobre um vídeo meu', 'Um vídeo que registaste, ou de um guião teu, foi aprovado, rejeitado ou tem alterações pedidas (com o motivo).',
   'Quem registou o vídeo ou a versão e quem é responsável pelo guião', '{in_app,email,digest}', '{in_app}', false, null, 140),
  ('video_comment', 'guioes', 'Comentário num vídeo meu', 'Alguém comentou num momento de um vídeo que registaste, ou respondeu a um comentário teu.',
   'Quem registou o vídeo ou a versão e quem escreveu o comentário respondido', '{in_app,email,digest}', '{in_app}', false, null, 150)
on conflict (kind) do update set group_key = excluded.group_key, label = excluded.label, description = excluded.description,
  recipients = excluded.recipients, channels = excluded.channels, default_channels = excluded.default_channels, sort = excluded.sort;

-- Depois de uma decisão: avisa quem registou o ativo e a versão e o responsável do guião (sem repetir pessoas; quem
-- decide não se avisa a si próprio, _notify trata disso, tal como o acesso atual de quem recebe).
create or replace function public.media_decisions_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare a media_assets; v media_versions; owner uuid; who uuid; t text; b text;
begin
  select * into a from media_assets where id = new.asset_id;
  select * into v from media_versions where id = new.version_id;
  select g.owner_id into owner from guioes g where g.id = a.content_id and g.client_id = new.workspace_id;
  t := case new.to_status when 'approved' then 'Vídeo aprovado: ' when 'rejected' then 'Vídeo rejeitado: '
            else 'Pedem alterações no vídeo: ' end || coalesce(a.title, 'sem título') || ' (v' || v.version_no || ')';
  b := coalesce(new.actor_label, 'Alguém') || coalesce(' · ' || new.reason, '');
  for who in select distinct x from unnest(array[a.created_by, v.uploaded_by, owner]) x where x is not null loop
    perform public._notify(who, new.workspace_id, 'video_decision', 'media_asset', a.id::text, t, b, 'video_decision:' || new.id);
  end loop;
  return null;
exception when others then
  raise log 'media_decisions_notify % falhou: % %', new.id, sqlstate, sqlerrm;   -- o aviso nunca desfaz a decisão
  return null;
end $$;

-- Depois de um comentário: avisa quem registou o ativo e a versão; numa resposta, também quem escreveu o comentário.
create or replace function public.media_comments_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare a media_assets; v media_versions; par media_comments; who uuid; mm text; t text; b text;
begin
  if tg_op <> 'INSERT' then return null; end if;
  select * into a from media_assets where id = new.asset_id;
  select * into v from media_versions where id = new.version_id;
  if new.parent_id is not null then select * into par from media_comments where id = new.parent_id; end if;
  mm := case when new.t_ms is null then '' else ' aos ' || (new.t_ms / 60000) || ':' || lpad(((new.t_ms / 1000) % 60)::text, 2, '0') end;
  b := coalesce(new.author_label, 'Alguém') || ': ' || left(new.body, 300);
  for who in select distinct x from unnest(array[a.created_by, v.uploaded_by, par.author_id]) x where x is not null loop
    t := case when who is not distinct from par.author_id then 'Resposta ao teu comentário em ' else 'Comentário em ' end
         || coalesce(a.title, 'sem título') || mm;
    perform public._notify(who, new.workspace_id, 'video_comment', 'media_asset', a.id::text, t, b, 'video_comment:' || new.id);
  end loop;
  return null;
exception when others then
  raise log 'media_comments_notify % falhou: % %', new.id, sqlstate, sqlerrm;
  return null;
end $$;

drop trigger if exists media_decisions_notify on public.media_decisions;
create trigger media_decisions_notify after insert on public.media_decisions for each row execute function public.media_decisions_notify();
drop trigger if exists media_comments_notify on public.media_comments;
create trigger media_comments_notify after insert on public.media_comments for each row execute function public.media_comments_notify();
revoke all on function public.media_decisions_notify(), public.media_comments_notify() from public, anon, authenticated;

-- Caixa (W6): comentários de vídeo contam como menção e o item abre o vídeo na revisão. Iguais a W6 exceto estas linhas.
create or replace function public._ops_category(p_reason text) returns text language sql immutable set search_path = public as $$
  select case
    when p_reason in ('assigned','blocked','changes_requested') then 'task'
    when p_reason = 'approval' then 'approval'
    when p_reason = 'recording' then 'recording'
    when p_reason in ('unassigned','blocked_other','talent_request') then 'decision'
    when p_reason in ('task_mention','script_mention','script_comment','video_comment') then 'mention'
    when p_reason in ('automation_error','task_blocked','overdue') then 'alert'
    else 'info' end
$$;

-- _ops_queue (W6) é longa: muda só o destino do item, por substituição na definição atual, e falha se não encontrar a linha.
do $patch$
declare d text; old text := $o$when 'agent_job' then '/agentes/configuracao'$o$;
begin
  d := pg_get_functiondef('public._ops_queue(text)'::regprocedure);
  if position('media_asset' in d) > 0 then return; end if;          -- já aplicado
  if position(old in d) = 0 then raise exception '_ops_queue mudou: rever W5-05'; end if;
  execute replace(d, old, old || E'\n               when ''media_asset'' then ''/revisao?ver=videos&asset='' || n.entity_id');
end $patch$;

/* Rollback:
   drop trigger if exists media_decisions_notify on public.media_decisions;
   drop trigger if exists media_comments_notify on public.media_comments;
   drop function if exists public.media_decisions_notify(), public.media_comments_notify();
   reaplicar _ops_category e _ops_queue de 20261030075315_w6_ops_p1.sql;
   delete from notifications where kind in ('video_decision','video_comment');
   delete from notification_suppressions where kind in ('video_decision','video_comment');
   delete from notification_user_prefs where kind in ('video_decision','video_comment');
   delete from notification_ws_prefs where kind in ('video_decision','video_comment');
   delete from notification_event_defs where kind in ('video_decision','video_comment');
   e repor notifications_kind_check sem os dois tipos. */
