-- scripts/backup/scope.sql: âmbito do backup, uma linha por tabela "esquema.tabela<TAB>consulta" (QA-15).
-- Variável psql ws: vazia = base inteira; um id de cliente = só as linhas desse cliente (export por workspace).
-- Falha fechada: uma tabela nova em public sem coluna de cliente nem regra aqui faz o script parar, para nunca
-- exportar (ou esquecer) dados de outros clientes sem decisão explícita.
-- Só cria uma tabela temporária da sessão; não altera a base.
\set ON_ERROR_STOP on
\if :{?ws}
\else
  \set ws ''
\endif
select set_config('drill.ws', :'ws', false) \gset
create temp table _scope (tbl text primary key, q text not null);
do $$
declare
  ws text := current_setting('drill.ws');
  org uuid; r record; col text; f text; users text; refs text := '';
  -- catálogos globais: sem dados de clientes
  global_t text[] := array['agent_definitions','agent_models','agent_tool_prices','agent_workers','biz_metrics','capabilities',
                           'dashboard_widgets','feature_flag_defs','role_capabilities'];
  -- dados da agência (organização), não de outro cliente
  org_t text[] := array['agency_memberships','fx_rates','pub_platform_limits'];
  -- dados por pessoa: só as pessoas ligadas ao cliente
  user_t text[] := array['profiles','member_availability','teleprompter_prefs','privacy_requests'];
begin
  if ws = '' then
    insert into _scope select c.oid::regclass::text, 'select * from ' || c.oid::regclass::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public','auth','storage','cron','realtime') and c.relkind in ('r','p');
    return;
  end if;
  select organization_id into org from clients where id = ws;
  if org is null then raise exception 'cliente % não existe', ws using errcode = 'P0002'; end if;

  -- tabelas de public com coluna de cliente
  for r in select c.relname, (select a.attname from pg_attribute a where a.attrelid = c.oid and a.attname in ('workspace_id','client_id')
                                and not a.attisdropped order by a.attname desc limit 1) wcol
           from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') loop
    if r.wcol is not null then
      f := format('%I = %L', r.wcol, ws);
    elsif r.relname = 'clients' then f := format('id = %L', ws);
    elsif r.relname = 'organizations' then f := format('id = %L', org);
    elsif r.relname = any (global_t) then f := 'true';
    elsif r.relname = any (org_t) then f := format('organization_id = %L', org);
    elsif r.relname = 'publicacoes' then f := format('guiao_id in (select id from public.guioes where client_id = %L)', ws);
    elsif r.relname = any (user_t) then f := null; -- depois de conhecer as pessoas
    else raise exception 'tabela public.% sem regra de âmbito no export por cliente (scripts/backup/scope.sql)', r.relname using errcode = '22023';
    end if;
    insert into _scope values ('public.' || r.relname, case when f is null then '' else format('select * from public.%I where %s', r.relname, f) end);
  end loop;

  -- pessoas ligadas ao cliente: membros, equipa da agência e quem aparece nas linhas exportadas (FK para auth.users)
  for r in select co.conrelid::regclass::text tbl, a.attname from pg_constraint co
           join pg_attribute a on a.attrelid = co.conrelid and a.attnum = co.conkey[1]
           where co.contype = 'f' and co.confrelid = 'auth.users'::regclass and co.connamespace = 'public'::regnamespace
             and array_length(co.conkey, 1) = 1 loop
    select q into f from _scope where tbl = r.tbl;
    if f is not null and f <> '' then refs := refs || format(' union select %I from (%s) x where %I is not null', r.attname, f, r.attname); end if;
  end loop;
  users := format('select user_id from public.workspace_access where workspace_id = %L union select user_id from public.agency_memberships where organization_id = %L',
                  ws, org) || refs;
  update _scope set q = format('select * from %s where user_id in (%s)', tbl, users) where q = '';
  insert into _scope values
    ('auth.users', format('select * from auth.users where id in (%s)', users)),
    ('auth.mfa_factors', format('select * from auth.mfa_factors where user_id in (%s)', users)),
    ('storage.buckets', 'select * from storage.buckets'),
    -- objetos: caminhos que começam pelo id do cliente (branding) ou da pessoa (avatars)
    ('storage.objects', format('select * from storage.objects where split_part(name, ''/'', 1) = %L or split_part(name, ''/'', 1) in (select id::text from (%s) u(id))', ws, users)),
    ('cron.job', 'select * from cron.job');
  -- realtime.messages fica de fora: mensagens efémeras com tópicos de vários clientes
end $$;
select tbl || E'\t' || q from _scope order by tbl \g (tuples_only=on format=unaligned)
