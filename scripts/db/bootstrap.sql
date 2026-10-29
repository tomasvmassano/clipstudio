-- scripts/db/bootstrap.sql: o mínimo da plataforma Supabase para aplicar supabase/migrations
-- numa base Postgres limpa (CI e testes locais). Só cria o que ainda não existe, por isso
-- também corre sobre a imagem supabase/postgres. Nunca correr contra produção.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin noinherit bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if;
end $$;
do $$ begin
  if not pg_has_role('authenticator', 'anon', 'member') then grant anon, authenticated, service_role to authenticator; end if;
  if not pg_has_role('postgres', 'anon', 'member') then grant anon, authenticated, service_role to postgres; end if;
end $$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;
do $$ begin execute format('alter database %I set search_path = public, extensions', current_database()); end $$;
set search_path = public, extensions;

create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key, instance_id uuid, aud text, role text, email text unique,
  encrypted_password text, email_confirmed_at timestamptz, last_sign_in_at timestamptz,
  raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}',
  banned_until timestamptz, deleted_at timestamptz, is_anonymous boolean default false,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists auth.mfa_factors (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  friendly_name text, factor_type text not null default 'totp', status text not null default 'unverified',
  created_at timestamptz default now(), updated_at timestamptz default now());
create or replace function auth.jwt() returns jsonb language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $f$;
create or replace function auth.uid() returns uuid language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), auth.jwt() ->> 'sub')::uuid $f$;
create or replace function auth.role() returns text language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), auth.jwt() ->> 'role') $f$;
create or replace function auth.email() returns text language sql stable as $f$
  select auth.jwt() ->> 'email' $f$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;

create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key, name text not null unique, owner uuid, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], avif_autodetection boolean default false,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text,
  owner uuid, owner_id text, metadata jsonb, path_tokens text[] generated always as (string_to_array(name, '/')) stored,
  version text, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now());
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[] language sql immutable as $f$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $f$;
create or replace function storage.filename(name text) returns text language sql immutable as $f$
  select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)] $f$;
grant usage on schema storage to anon, authenticated, service_role;
grant all on all tables in schema storage to anon, authenticated, service_role;

-- pg_cron não existe num Postgres simples: o executor tira o "create extension pg_cron" e usa isto.
create schema if not exists cron;
create table if not exists cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean not null default true);
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $f$
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
create or replace function cron.unschedule(job_name text) returns boolean language sql as $f$
  with d as (delete from cron.job where jobname = job_name returning 1) select exists (select 1 from d) $f$;

create schema if not exists realtime;
create table if not exists realtime.messages (id bigserial primary key, topic text, extension text, payload jsonb, event text,
  private boolean default false, inserted_at timestamptz default now());
alter table realtime.messages enable row level security;
create or replace function realtime.topic() returns text language sql stable as $f$
  select nullif(current_setting('realtime.topic', true), '') $f$;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void
  language sql as $f$ insert into realtime.messages (payload, event, topic, private) values (payload, event, topic, private) $f$;
grant usage on schema realtime to anon, authenticated, service_role;
grant select on realtime.messages to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
end $$;

-- privilégios por omissão como no Supabase: as migrações fazem revoke/grant explícitos por cima.
grant usage on schema public, extensions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
