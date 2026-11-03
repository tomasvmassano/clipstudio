-- supabase/tests/w8_notif.sql : notificações por evento com canais e preferências (FR-15-05, FR-14-02 notificações). ADR-0040.
-- Prova: sem flag nada muda (as preferências gravadas são ignoradas para quem não a tem); com flag o cliente desliga tipos,
-- marca obrigatórios, a pessoa desliga e silencia dentro do que o cliente permite; obrigatórios nunca são suprimidos;
-- supressões contadas sem duplicar; isolamento entre clientes, staff sem atribuição, código de equipa e acesso removido.
-- Rollback no fim (raise).
do $$
declare
  org uuid := (select id from organizations where slug='clipstudio');
  u_adm uuid := gen_random_uuid(); u_ed uuid := gen_random_uuid(); u_v uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_own uuid := gen_random_uuid(); u_ag uuid := gen_random_uuid(); u_aga uuid := gen_random_uuid(); u_rm uuid := gen_random_uuid();
  tok text := 'nt-a-team-code-0123456789abcdef';
  j jsonb; st text; ok int := 0; bad int := 0; res text := ''; r record; tid uuid; kinds text[];
begin
  insert into clients (id, name, handle, organization_id) values ('nt_a', 'Notif A', 'nta', org), ('nt_b', 'Notif B', 'ntb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) select x, e, now(), 'authenticated', 'authenticated' from (values
    (u_adm,'nt-adm@test.invalid'),(u_ed,'nt-ed@test.invalid'),(u_v,'nt-v@test.invalid'),(u_b,'nt-b@test.invalid'),
    (u_own,'nt-own@test.invalid'),(u_ag,'nt-ag@test.invalid'),(u_aga,'nt-aga@test.invalid'),(u_rm,'nt-rm@test.invalid')) v(x, e);
  insert into agency_memberships (organization_id, user_id, agency_role) values (org, u_own, 'agency_owner'), (org, u_ag, 'agency_member'), (org, u_aga, 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('nt_a', u_adm, 'client_staff', 'workspace_admin'), ('nt_a', u_ed, 'client_staff', 'manager'), ('nt_a', u_v, 'client_staff', 'viewer'),
    ('nt_b', u_b, 'client_staff', 'workspace_admin'), ('nt_a', u_aga, 'agency_staff', 'manager'), ('nt_a', u_rm, 'client_staff', 'manager');
  update workspace_access set status = 'removed' where workspace_id = 'nt_a' and user_id = u_rm;
  insert into studio_tokens (token, client_id, label) values (tok, 'nt_a', 'Equipa NT');

  create temp table t(name text, expected boolean, got boolean) on commit drop;
  grant all on t to authenticated, anon;

  -- ═════ catálogo ═════
  select array_agg(m[1]) into kinds from regexp_matches(
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'notifications_kind_check'), '''([a-z_]+)''', 'g') m;
  insert into t values ('catálogo cobre todos os tipos de notifications.kind', true,
    cardinality(kinds) = 11 and not exists (select 1 from unnest(kinds) k where k not in (select kind from notification_event_defs))
    and (select count(*) from notification_event_defs) = 11);
  insert into t values ('obrigatórios: atribuições e erro de automação', true,
    (select array_agg(kind order by kind) from notification_event_defs where mandatory) = array['automation_error','script_assigned','task_assigned','task_auto','task_delegated']);
  insert into t values ('só "na app" está disponível; email e resumo com motivo', true,
    (select array_agg(key order by sort) from notification_channel_defs where available) = array['in_app']
    and not exists (select 1 from notification_channel_defs where not available and coalesce(unavailable_reason, '') = ''));
  insert into t values ('flag registada só para o dono da agência', true,
    (select default_stage from feature_flag_defs where key = 'notifications.prefs') = 'owner');

  -- ═════ flag desligada (fase owner por omissão): preferências gravadas são ignoradas para quem não tem a flag ═════
  insert into notification_ws_prefs (workspace_id, kind, channel, enabled) values ('nt_a', 'task_done', 'in_app', false);
  insert into notification_user_prefs (user_id, workspace_id, kind, channel, enabled) values (u_ed, 'nt_a', 'task_mention', 'in_app', false);
  insert into notification_mutes (user_id, workspace_id) values (u_ed, 'nt_a');
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x1', 'Feita', null, 'off:done:1');
  perform _notify(u_ed, 'nt_a', 'task_mention', 'task', 'x1', 'Menção', null, 'off:mention:1');
  perform _notify(u_ed, 'nt_a', 'task_blocked', 'task', 'x1', 'Bloqueada', null, 'off:blocked:1');
  insert into t values ('flag desligada: cliente, pessoa e silêncio não suprimem nada', true,
    (select count(*) from notifications where user_id = u_ed and dedup_key like 'off:%') = 3
    and not exists (select 1 from notification_suppressions where user_id = u_ed));
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x1', 'Feita', null, 'off:done:1');
  insert into t values ('flag desligada: deduplicação igual (sem repetidos)', true,
    (select count(*) from notifications where user_id = u_ed and dedup_key = 'off:done:1') = 1);
  perform _notify(u_adm, 'nt_a', 'task_done', 'task', 'x1', 'Feita', null, 'off:self:1');
  insert into t values ('quem age continua a não se notificar', true, not exists (select 1 from notifications where dedup_key = 'off:self:1'));
  perform _notify(u_rm, 'nt_a', 'task_done', 'task', 'x1', 'Feita', null, 'off:rm:1');
  insert into t values ('acesso removido continua a não receber', true, not exists (select 1 from notifications where dedup_key = 'off:rm:1'));
  -- a fase owner liga a flag só para o dono da agência: é o único para quem o "desligado" do cliente vale
  perform _notify(u_own, 'nt_a', 'task_done', 'task', 'x1', 'Feita', null, 'owner:done:1');
  insert into t values ('fase owner: só o dono da agência vê o efeito', true,
    not exists (select 1 from notifications where dedup_key = 'owner:done:1')
    and (select n from notification_suppressions where user_id = u_own and kind = 'task_done' and reason = 'org_off') = 1);
  delete from notification_ws_prefs where workspace_id = 'nt_a'; delete from notification_user_prefs where user_id = u_ed;
  delete from notification_mutes where user_id = u_ed; delete from notification_suppressions where workspace_id = 'nt_a';

  execute 'set local role authenticated';
  j := notif_settings('nt_a');
  insert into t values ('flag desligada: página diz desligada (sem dados)', true, not (j->>'enabled')::boolean and j->'events' is null and (j->>'can_manage')::boolean);
  begin perform notif_settings_set('nt_a', 'task_done', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: mudar recusa (55000)', true, st = '55000');
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  insert into t values ('flag desligada: perfil sem clientes com notificações', true, jsonb_array_length(my_notif_workspaces()) = 0);
  begin perform my_notif_pref_set('nt_a', 'task_done', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('flag desligada: preferência pessoal recusa (55000)', true, st = '55000');
  execute 'reset role';

  insert into feature_flags (key, organization_id, workspace_id, stage) values
    ('notifications.prefs', org, 'nt_a', 'all'), ('notifications.prefs', org, 'nt_b', 'all');

  -- ═════ definições do cliente ═════
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  j := notif_settings('nt_a');
  insert into t values ('admin vê 11 tipos e 3 canais, gere, sem supressões', true,
    (j->>'enabled')::boolean and (j->>'can_manage')::boolean and jsonb_array_length(j->'events') = 11
    and jsonb_array_length(j->'channels') = 3 and jsonb_array_length(j->'suppressed_30d') = 0);
  insert into t values ('predefinição: tudo ligado na app, email desligado', true,
    not exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
                 where (c->>'channel' = 'in_app') <> (c->>'enabled')::boolean));
  j := notif_settings_set('nt_a', 'task_done', 'in_app', false);
  insert into t values ('admin desliga "tarefa concluída" na app', true,
    exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
             where e->>'kind' = 'task_done' and c->>'channel' = 'in_app' and not (c->>'enabled')::boolean));
  execute 'reset role';
  insert into t values ('mudança do cliente fica no histórico com antes/depois', true,
    (select count(*) from audit_events where workspace_id = 'nt_a' and action = 'notif.ws_pref_set' and entity_id = 'task_done:in_app'
       and after->>'enabled' = 'false') = 1);
  execute 'set local role authenticated';
  perform notif_settings_set('nt_a', 'task_done', 'in_app', false);
  execute 'reset role';
  insert into t values ('repetir a mesma mudança não duplica o histórico', true,
    (select count(*) from audit_events where workspace_id = 'nt_a' and action = 'notif.ws_pref_set' and entity_id = 'task_done:in_app') = 1);
  execute 'set local role authenticated';
  begin perform notif_settings_set('nt_a', 'automation_error', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('erro de automação não se desliga (22023)', true, st = '22023');
  begin perform notif_settings_set('nt_a', 'task_assigned', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('atribuição não se desliga (22023)', true, st = '22023');
  begin perform notif_settings_set('nt_a', 'task_mention', 'email', true, true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('obrigatório só na app (22023)', true, st = '22023');
  begin perform notif_settings_set('nt_a', 'nao_existe', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('tipo desconhecido recusado (22023)', true, st = '22023');
  begin perform notif_settings_set('nt_a', 'task_done', 'sms', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('canal desconhecido recusado (22023)', true, st = '22023');
  perform notif_settings_set('nt_a', 'script_mention', 'in_app', true, true);
  perform notif_settings_set('nt_a', 'task_blocked', 'email', true);
  insert into t values ('email do cliente guardado como preferência', true,
    exists (select 1 from jsonb_array_elements(notif_settings('nt_a')->'events') e, jsonb_array_elements(e->'channels') c
             where e->>'kind' = 'task_blocked' and c->>'channel' = 'email' and (c->>'enabled')::boolean));

  -- quem não gere
  perform set_config('request.jwt.claims', json_build_object('sub', u_v, 'role','authenticated')::text, true);
  begin perform notif_settings('nt_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor sem team.read não abre as definições (42501)', true, st = '42501');
  begin perform notif_settings_set('nt_a', 'task_mention', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('leitor não muda definições (42501)', true, st = '42501');
  j := my_notif_prefs('nt_a');
  insert into t values ('leitor tem as suas preferências pessoais', true, (j->>'enabled')::boolean);
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  j := notif_settings('nt_a');
  insert into t values ('manager vê, não gere, não vê contagens da equipa', true,
    (j->>'enabled')::boolean and not (j->>'can_manage')::boolean and j->'suppressed_30d' = 'null'::jsonb);
  begin perform notif_settings_set('nt_a', 'task_mention', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('manager sem settings.manage não muda (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  begin perform notif_settings('nt_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não vê as definições de A', true, st = '42501');
  begin perform notif_settings_set('nt_a', 'task_mention', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('cliente B não muda A', true, st = '42501');
  j := notif_settings('nt_b');
  insert into t values ('B não herda o que A desligou', true,
    not exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
                 where c->>'channel' = 'in_app' and not (c->>'enabled')::boolean));
  perform set_config('request.jwt.claims', json_build_object('sub', u_ag, 'role','authenticated')::text, true);
  begin perform notif_settings('nt_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff da agência sem atribuição não vê (42501)', true, st = '42501');
  begin perform my_notif_prefs('nt_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff sem atribuição sem preferências em A (42501)', true, st = '42501');
  perform set_config('request.jwt.claims', json_build_object('sub', u_rm, 'role','authenticated')::text, true);
  begin perform my_notif_prefs('nt_a'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('acesso removido: sem preferências (42501)', true, st = '42501');
  execute 'reset role'; execute 'set local role anon';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform notif_settings('nt_a', tok); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('código de equipa não abre definições de notificações', true, st in ('42501', '42883'));
  execute 'reset role';
  insert into t values ('anon não pode executar as RPCs', true,
    not has_function_privilege('anon', 'public.notif_settings(text, text)', 'execute')
    and not has_function_privilege('anon', 'public.my_notif_prefs(text)', 'execute'));

  -- ═════ aplicação em _notify (flag ligada) ═════
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x2', 'Feita', null, 'on:done:1');
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x2', 'Feita', null, 'on:done:1');
  insert into t values ('cliente desligou: não cria e conta uma vez (repetição não conta)', true,
    not exists (select 1 from notifications where dedup_key = 'on:done:1')
    and (select n from notification_suppressions where user_id = u_ed and kind = 'task_done' and reason = 'org_off') = 1);
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x3', 'Feita', null, 'on:done:2');
  insert into t values ('outro evento soma ao contador do dia', true,
    (select n from notification_suppressions where user_id = u_ed and kind = 'task_done' and reason = 'org_off') = 2);
  insert into t values ('supressão não escreve audit por evento', true,
    not exists (select 1 from audit_events where workspace_id = 'nt_a' and action like 'notif.suppress%'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role','authenticated')::text, true);
  perform _notify(u_b, 'nt_b', 'task_done', 'task', 'y', 'Feita', null, 'b:self');   -- ignorado (é quem age)
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform _notify(u_b, 'nt_b', 'task_done', 'task', 'y', 'Feita', null, 'b:done:1');
  insert into t values ('B continua a receber "concluída" (preferência é de A)', true, exists (select 1 from notifications where dedup_key = 'b:done:1'));

  -- fluxo real: criar tarefa atribuída (obrigatória) e comentar (menção/comentário, desligável)
  execute 'set local role authenticated';
  j := task_create('nt_a', jsonb_build_object('title', 'Gravar take', 'assignee_id', u_ed));
  tid := (j->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  j := my_notif_prefs('nt_a');
  insert into t values ('pessoa vê: concluída não permitida pelo cliente; atribuição travada', true,
    (j->>'enabled')::boolean
    and exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
                 where e->>'kind' = 'task_done' and c->>'channel' = 'in_app' and not (c->>'allowed')::boolean and not (c->>'effective')::boolean)
    and exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
                 where e->>'kind' = 'task_assigned' and c->>'channel' = 'in_app' and (c->>'locked')::boolean));
  insert into t values ('pessoa vê só as próprias supressões', true,
    (select sum((x->>'n')::int) from jsonb_array_elements(j->'suppressed_30d') x) = 2);
  begin perform my_notif_pref_set('nt_a', 'task_done', 'in_app', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa não liga o que o cliente desligou (22023)', true, st = '22023');
  begin perform my_notif_pref_set('nt_a', 'task_assigned', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa não desliga atribuições (22023)', true, st = '22023');
  begin perform my_notif_pref_set('nt_a', 'script_mention', 'in_app', false); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa não desliga o que o cliente tornou obrigatório (22023)', true, st = '22023');
  j := my_notif_pref_set('nt_a', 'task_mention', 'in_app', false);
  insert into t values ('pessoa desliga menções em tarefas', true,
    exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
             where e->>'kind' = 'task_mention' and c->>'channel' = 'in_app' and not (c->>'mine')::boolean));
  begin perform my_notif_pref_set('nt_a', 'task_mention', 'email', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('email que o cliente não ligou não se escolhe (22023)', true, st = '22023');
  j := my_notif_pref_set('nt_a', 'task_blocked', 'email', true);
  insert into t values ('email pessoal guardado (o cliente ligou) mas canal indisponível', true,
    exists (select 1 from jsonb_array_elements(j->'channels') c where c->>'key' = 'email' and not (c->>'available')::boolean)
    and exists (select 1 from jsonb_array_elements(j->'events') e, jsonb_array_elements(e->'channels') c
                 where e->>'kind' = 'task_blocked' and c->>'channel' = 'email' and (c->>'mine')::boolean));
  begin perform my_notif_prefs('nt_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa de A não abre preferências em B (42501)', true, st = '42501');
  begin perform my_notif_mute('nt_b', true); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('pessoa de A não silencia B (42501)', true, st = '42501');
  insert into t values ('perfil: só o cliente A aparece', true,
    (select array_agg(x->>'id') from jsonb_array_elements(my_notif_workspaces()) x) = array['nt_a']);
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform task_comment(tid, 'Vê isto, por favor');
  execute 'reset role';
  insert into t values ('fluxo real: atribuição chega (obrigatória)', true,
    exists (select 1 from notifications where user_id = u_ed and kind = 'task_assigned' and entity_id = tid::text));
  insert into t values ('fluxo real: comentário suprimido pela pessoa', true,
    not exists (select 1 from notifications where user_id = u_ed and kind = 'task_mention' and entity_id = tid::text)
    and (select n from notification_suppressions where user_id = u_ed and kind = 'task_mention' and reason = 'user_off') = 1);
  insert into t values ('preferência pessoal no histórico', true,
    exists (select 1 from audit_events where actor_user_id = u_ed and action = 'notif.my_pref_set' and entity_id = 'task_mention:in_app'));

  -- silêncio por cliente
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  begin perform my_notif_mute('nt_a', true, now() - interval '1 hour'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('silenciar até ao passado recusado (22023)', true, st = '22023');
  begin perform my_notif_mute('nt_a', true, now() + interval '120 days'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('silenciar mais de 90 dias recusado (22023)', true, st = '22023');
  j := my_notif_mute('nt_a', true, now() + interval '8 hours');
  insert into t values ('silenciado até daqui a 8 h', true, (j->>'muted')::boolean and j->>'muted_until' is not null);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform _notify(u_ed, 'nt_a', 'script_comment', 'content', 'g1', 'Resposta', null, 'mute:comment:1');
  perform _notify(u_ed, 'nt_a', 'script_mention', 'content', 'g1', 'Menção', null, 'mute:mention:1');
  perform _notify(u_ed, 'nt_a', 'automation_error', 'agent_job', 'j1', 'Falhou', null, 'mute:auto:1');
  insert into t values ('silêncio suprime o não obrigatório', true,
    not exists (select 1 from notifications where dedup_key = 'mute:comment:1')
    and exists (select 1 from notification_suppressions where user_id = u_ed and kind = 'script_comment' and reason = 'muted'));
  insert into t values ('silêncio não suprime o obrigatório do cliente nem o do catálogo', true,
    exists (select 1 from notifications where dedup_key = 'mute:mention:1') and exists (select 1 from notifications where dedup_key = 'mute:auto:1'));
  update notification_mutes set muted_until = now() - interval '1 minute' where user_id = u_ed;
  perform _notify(u_ed, 'nt_a', 'script_comment', 'content', 'g1', 'Resposta', null, 'mute:comment:2');
  insert into t values ('silêncio expirado deixa de valer', true, exists (select 1 from notifications where dedup_key = 'mute:comment:2'));
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_ed, 'role','authenticated')::text, true);
  perform my_notif_mute('nt_a', true);
  j := my_notif_mute('nt_a', false);
  insert into t values ('silenciar sem fim e voltar a ligar', true, not (j->>'muted')::boolean);
  execute 'reset role';
  insert into t values ('silêncio no histórico', true,
    (select count(*) from audit_events where actor_user_id = u_ed and action = 'notif.mute_set') = 3);

  -- staff da agência atribuído a A
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', u_aga, 'role','authenticated')::text, true);
  j := my_notif_prefs('nt_a');
  insert into t values ('staff da agência atribuído a A tem preferências em A', true, (j->>'enabled')::boolean);
  begin perform my_notif_prefs('nt_b'); st := 'none'; exception when others then st := sqlstate; end;
  insert into t values ('staff atribuído a A não abre B', true, st = '42501');

  -- voltar à predefinição apaga a linha
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  perform notif_settings_set('nt_a', 'task_done', 'in_app', true);
  execute 'reset role';
  insert into t values ('voltar à predefinição apaga a linha do cliente', true,
    not exists (select 1 from notification_ws_prefs where workspace_id = 'nt_a' and kind = 'task_done'));
  perform _notify(u_ed, 'nt_a', 'task_done', 'task', 'x9', 'Feita', null, 'on:done:9');
  insert into t values ('religado: volta a chegar', true, exists (select 1 from notifications where dedup_key = 'on:done:9'));
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  j := notif_settings('nt_a');
  execute 'reset role';
  insert into t values ('admin vê contagens de supressão do cliente', true,
    (select sum((x->>'n')::int) from jsonb_array_elements(j->'suppressed_30d') x) = 4);

  -- desligar a flag outra vez: preferências ficam guardadas mas deixam de valer
  update feature_flags set stage = 'off' where key = 'notifications.prefs' and workspace_id = 'nt_a';
  perform _notify(u_ed, 'nt_a', 'task_mention', 'task', 'x9', 'Menção', null, 'flagoff:mention:1');
  insert into t values ('flag desligada outra vez: preferência pessoal deixa de valer', true,
    exists (select 1 from notifications where dedup_key = 'flagoff:mention:1')
    and exists (select 1 from notification_user_prefs where user_id = u_ed and kind = 'task_mention'));

  insert into t values ('tabelas novas fechadas à leitura direta', true,
    not has_table_privilege('authenticated', 'public.notification_ws_prefs', 'select')
    and not has_table_privilege('authenticated', 'public.notification_user_prefs', 'select')
    and not has_table_privilege('authenticated', 'public.notification_mutes', 'select')
    and not has_table_privilege('authenticated', 'public.notification_suppressions', 'select')
    and not has_table_privilege('authenticated', 'public.notification_event_defs', 'select')
    and not has_table_privilege('authenticated', 'public.notification_channel_defs', 'select'));
  insert into t values ('_notify e auxiliares não são chamáveis pela API', true,
    not has_function_privilege('authenticated', 'public._notify(uuid,text,text,text,text,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public._notif_suppress_reason(uuid,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public._flag_on_for(text,text,uuid)', 'execute'));
  insert into t values ('funções novas com search_path fixo', true,
    not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('_flag_on_for','_notif_suppress_reason','_notify','_notif_channels_json','_notif_ws_json','_notif_require_me',
                                   'notif_settings','notif_settings_set','my_notif_workspaces','my_notif_prefs','my_notif_pref_set','my_notif_mute')
                 and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));

  for r in select * from t loop
    if r.expected = r.got then ok := ok + 1; else bad := bad + 1; res := res || ' FAIL[' || r.name || ']'; end if;
  end loop;
  raise exception 'RESULT ok=% fail=% %', ok, bad, res;
end $$;
