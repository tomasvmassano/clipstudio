-- scripts/backup/activity.sql: atividade de amostra para o ensaio de backup (QA-15). Só para bases descartáveis.
-- Dois clientes do ensaio (bk_a, bk_b) além do numeiro do seed, com pessoas reais da app (auth.users sintéticos,
-- domínio .invalid, sem passwords) e escrita feita pelas RPCs como cada pessoa, para gerar o rasto que existe em
-- produção: guiões e versões, transições, fontes, tarefas, comentários, notificações, auditoria e eventos de domínio.
-- Variável psql: rows (guiões por cliente; fontes e tarefas = rows/2). Termos exclusivos por cliente:
-- "zebraquantica" (só em B) e "alfarrobeira" (só em A), usados depois para provar o isolamento A/B no restauro.
\set ON_ERROR_STOP on
\if :{?rows}
\else
  \set rows 40
\endif
select set_config('drill.rows', :'rows', false);

do $$
declare
  org uuid := (select id from organizations where slug = 'clipstudio');
begin
  if org is null then raise exception 'organização clipstudio em falta (migrações por aplicar?)'; end if;
  insert into clients (id, name, handle, organization_id) values
    ('bk_a', 'Ensaio Backup A', 'bka', org), ('bk_b', 'Ensaio Backup B', 'bkb', org);
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
    ('00000000-0000-4000-8000-00000000b001', 'bk-dono@backup-drill.invalid',    now(), 'authenticated', 'authenticated'),
    ('00000000-0000-4000-8000-00000000b002', 'bk-staff-a@backup-drill.invalid', now(), 'authenticated', 'authenticated'),
    ('00000000-0000-4000-8000-00000000b003', 'bk-cli-a@backup-drill.invalid',   now(), 'authenticated', 'authenticated'),
    ('00000000-0000-4000-8000-00000000b004', 'bk-cli-b@backup-drill.invalid',   now(), 'authenticated', 'authenticated');
  insert into profiles (user_id, display_name) values
    ('00000000-0000-4000-8000-00000000b003', 'Cliente A do ensaio'), ('00000000-0000-4000-8000-00000000b004', 'Cliente B do ensaio');
  insert into agency_memberships (organization_id, user_id, agency_role) values
    (org, '00000000-0000-4000-8000-00000000b001', 'agency_owner'), (org, '00000000-0000-4000-8000-00000000b002', 'agency_member');
  insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
    ('bk_a', '00000000-0000-4000-8000-00000000b002', 'agency_staff', 'manager'),
    ('bk_a', '00000000-0000-4000-8000-00000000b003', 'client_staff', 'workspace_admin'),
    ('bk_b', '00000000-0000-4000-8000-00000000b004', 'client_staff', 'workspace_admin');
  insert into feature_flags (key, organization_id, workspace_id, stage)
  select 'busca.global', org, w, 'all' from unnest(array['bk_a', 'bk_b']) w;
  -- metadados de objetos do Storage (os bytes nunca estão no pg_dump: ver docs/runbooks/restauro.md)
  insert into storage.objects (bucket_id, name, metadata) values
    ('branding', 'bk_a/logo.png', '{"mimetype":"image/png","size":1234}'),
    ('branding', 'bk_b/logo.png', '{"mimetype":"image/png","size":4321}'),
    ('avatars', '00000000-0000-4000-8000-00000000b003/avatar.jpg', '{"mimetype":"image/jpeg","size":999}'),
    ('avatars', '00000000-0000-4000-8000-00000000b004/avatar.jpg', '{"mimetype":"image/jpeg","size":888}');
end $$;

-- escrita pelas RPCs, como cada pessoa (role authenticated + JWT), tal como a app faz
do $$
declare
  n int := current_setting('drill.rows')::int;
  ws text; who uuid; term text; g guioes; j jsonb; t uuid; i int;
  d date := (now() at time zone 'Asia/Dubai')::date;
begin
  for ws, who, term in values ('bk_a', '00000000-0000-4000-8000-00000000b003'::uuid, 'alfarrobeira'),
                              ('bk_b', '00000000-0000-4000-8000-00000000b004'::uuid, 'zebraquantica') loop
    perform set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    for i in 1..n loop
      g := public.content_create(ws, jsonb_build_object('corpo', 'Corpo do guião ' || i || ' sobre ' || term || '.',
             'tema', initcap(term) || ' ' || i, 'date', (d - (i % 7))::text,
             'hooks', jsonb_build_array(jsonb_build_object('text', 'Hook ' || i, 'mecanismo', 'teste'))));
      if i % 2 = 0 then g := public.content_transition(g.id, 'in_review', null, null, null); end if;
      if i % 8 = 0 then g := public.content_transition(g.id, 'rejected', 'motivo de teste ' || i, null, null);
      elsif i % 4 = 0 then g := public.content_transition(g.id, 'approved', null, null, null); end if;
    end loop;
    for i in 1..greatest(n / 2, 1) loop
      j := public.source_create(ws, jsonb_build_object('titulo', 'Fonte ' || i || ' ' || term,
             'fonte_url', 'https://exemplo.test/' || ws || '/' || i, 'fonte_tipo', 'artigo', 'tags', jsonb_build_array(term)));
      j := public.task_create(ws, jsonb_build_object('title', 'Tarefa ' || i || ' ' || term, 'assignee_id', who,
             'due_at', (now() + make_interval(days => i))::text));
      t := (j->>'id')::uuid;
      perform public.task_comment(t, 'Comentário ' || i || ' sobre ' || term, '{}', null);
    end loop;
    execute 'reset role';
  end loop;
end $$;

-- volume opcional (variável bulk, omissão 0): linhas de auditoria sintéticas metade em cada cliente, só para medir
-- tempos de backup/restauro com mais dados. Não passam pelas RPCs (é volume, não comportamento).
\if :{?bulk}
\else
  \set bulk 0
\endif
insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after, at)
select case when g % 2 = 0 then '00000000-0000-4000-8000-00000000b003'::uuid else '00000000-0000-4000-8000-00000000b004'::uuid end,
       'user', 'ensaio', case when g % 2 = 0 then 'bk_a' else 'bk_b' end, 'drill.volume', 'drill', g::text,
       jsonb_build_object('n', g, 'texto', repeat(md5(g::text), 4)), now() - make_interval(secs => g)
from generate_series(1, :bulk) g;
