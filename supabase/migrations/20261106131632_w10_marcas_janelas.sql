-- W10-17 · ING-03 + EDL-01 + EDL-08: o pacote automático usa as marcas do teleprompter para cortar as janelas de cada guião
-- na gravação longa da sessão. ADR-0065.
-- Expand (aditivo e compatível com o código do main e com o worker atual):
--   1. Flag edit.package_marks (default 'owner'): só com ela ligada PARA QUEM PEDE o pacote é que o job leva as marcas.
--   2. _package_marks(ws, guiões): escolhe a sessão do teleprompter deste cliente com mais destes guiões lidos e devolve,
--      por guião, as leituras de cada bloco (como recording_timeline: de "play"/"mudança de bloco" até à marca seguinte do
--      mesmo dispositivo), os takes e o "Gravaste? sim" final; e, por dispositivo, o desvio mínimo server_at - client_at
--      (para o worker corrigir o relógio do iPad pelo do servidor). Só leitura, só deste cliente.
--   3. Trigger BEFORE INSERT em media_jobs (só kind = 'package'): junta input.marks ao job. Não reescreve
--      edit_package_request (mesma assinatura, mesma chave de idempotência, mesma auditoria). Nunca falha o pedido: um erro
--      ao juntar as marcas fica como input.marks.error e o worker faz o caminho só pela transcrição, dizendo porquê.
-- Sem a flag, ou com o worker de hoje (ignora chaves que não conhece), o pacote faz exatamente o que faz hoje.
-- O worker novo (numeiro-engine ing03-marcas-janelas) grava em result.windows a origem da janela de cada guião.

insert into feature_flag_defs (key, label, module, scope, default_stage, description) values
  ('edit.package_marks', 'Pacote automático pelas marcas do teleprompter', 'Edição', 'ws', 'owner',
   'O pacote automático usa as marcas de gravação do teleprompter (ING-03) para cortar as janelas de cada guião na gravação longa; sem marcas que batam certo, usa só a transcrição e diz porquê.')
on conflict (key) do nothing;

create or replace function public._package_marks(p_ws text, p_guioes text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sid uuid; s recording_sessions;
begin
  if p_ws is null or coalesce(cardinality(p_guioes), 0) = 0 then
    return jsonb_build_object('v', 1, 'session', null, 'reason', 'sem_sessao', 'items', '{}'::jsonb); end if;
  -- a sessão deste cliente onde mais destes guiões têm leituras; empate: a mais recente
  select i.session_id into sid
    from recording_session_items i join recording_sessions rs on rs.id = i.session_id and rs.workspace_id = p_ws
   where i.workspace_id = p_ws and i.content_id = any (p_guioes)
     and exists (select 1 from recording_marks m where m.session_id = i.session_id and m.workspace_id = p_ws and m.content_id = i.content_id
                    and m.kind in ('play', 'block'))
   group by i.session_id, rs.date, rs.opened_at
   order by count(*) desc, rs.date desc, rs.opened_at desc
   limit 1;
  if sid is null then
    return jsonb_build_object('v', 1, 'session', null, 'reason', 'sem_sessao', 'items', '{}'::jsonb); end if;
  select * into s from recording_sessions where id = sid;
  return (
    with m as (
      select r.*, lead(r.client_at) over (partition by coalesce(r.device_id, '') order by r.client_at, r.id) as nxt
        from recording_marks r where r.session_id = sid and r.workspace_id = p_ws
    ), seg as (
      select content_id, block_key, client_at as st, nxt as en, coalesce(device_id, '') as dev,
             row_number() over (partition by content_id order by client_at, id) as k
        from m where kind in ('play', 'block') and content_id = any (p_guioes) and nxt is not null and nxt > client_at
    )
    select jsonb_build_object(
      'v', 1, 'reason', null,
      'session', jsonb_build_object('id', s.id, 'date', s.date, 'opened_at', s.opened_at, 'closed_at', s.closed_at),
      'devices', coalesce((select jsonb_object_agg(d.dev, jsonb_build_object('skew_s', d.skew, 'n', d.n)) from (
                   select coalesce(device_id, '') as dev, round(extract(epoch from min(server_at - client_at))::numeric, 3) as skew, count(*) as n
                     from recording_marks where session_id = sid and workspace_id = p_ws group by 1) d), '{}'),
      'items', coalesce((select jsonb_object_agg(c.id, jsonb_build_object(
                 'segments', coalesce((select jsonb_agg(jsonb_build_object('block', x.block_key, 'start', x.st, 'end', x.en, 'device', x.dev) order by x.st)
                                         from seg x where x.content_id = c.id and x.k <= 300), '[]'),
                 'takes', coalesce((select jsonb_agg(jsonb_build_object('block', t.block_key, 'n', t.take_number, 'at', t.created_at, 'status', t.status,
                                                                        'selected', t.selected) order by t.created_at)
                                      from takes t where t.session_id = sid and t.workspace_id = p_ws and t.content_id = c.id), '[]'),
                 -- última decisão no teleprompter: "gravado" conta só se não foi desfeito depois (igual a recording_timeline)
                 'recorded_at', (select case when r.kind = 'recorded' then r.client_at end from recording_marks r
                                  where r.session_id = sid and r.workspace_id = p_ws and r.content_id = c.id and r.kind in ('recorded', 'not_recorded')
                                  order by r.client_at desc, r.id desc limit 1)))
               from (select distinct x.content_id as id from seg x) c), '{}')));
end $$;

create or replace function public.media_jobs_package_marks() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text[];
begin
  if new.kind is distinct from 'package' or new.input ? 'marks' or jsonb_typeof(new.input->'guioes') is distinct from 'array' then
    return new; end if;
  if not public._flag_on_for('edit.package_marks', new.workspace_id, new.created_by) then return new; end if;
  begin
    g := array(select x->>'id' from jsonb_array_elements(new.input->'guioes') x where jsonb_typeof(x) = 'object' and x->>'id' is not null);
    new.input := new.input || jsonb_build_object('marks', public._package_marks(new.workspace_id, g));
  exception when others then
    -- nunca bloquear o pedido do pacote: o worker volta ao caminho só pela transcrição e diz porquê
    raise log 'package_marks_failed %', jsonb_build_object('workspace_id', new.workspace_id, 'error', sqlerrm);
    new.input := new.input || jsonb_build_object('marks', jsonb_build_object('v', 1, 'error', 'marcas_indisponiveis'));
  end;
  return new;
end $$;

drop trigger if exists media_jobs_package_marks on public.media_jobs;
create trigger media_jobs_package_marks before insert on public.media_jobs
  for each row when (new.kind = 'package') execute function public.media_jobs_package_marks();

revoke all on function public._package_marks(text, text[]), public.media_jobs_package_marks() from public, anon, authenticated;

/* Rollback (compatível, por esta ordem; o código do main e o worker não dependem de nada disto):
   1. drop trigger if exists media_jobs_package_marks on public.media_jobs;
   2. drop function if exists public.media_jobs_package_marks(); drop function if exists public._package_marks(text, text[]);
   3. delete from feature_flags where key = 'edit.package_marks'; delete from feature_flag_defs where key = 'edit.package_marks';
   Jobs já criados com input.marks continuam válidos: o worker novo usa-as, o antigo ignora-as.
   Desligar sem rollback: flag_set('edit.package_marks', null, 'off') na consola de funcionalidades. */
