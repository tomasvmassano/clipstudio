-- scripts/backup/pre_restore.sql: corre na base de destino ANTES de restaurar o esquema public (QA-15, ADR-0042).
-- Uma base nova do Supabase (e o scripts/db/bootstrap.sql) tem privilégios por omissão em public que dão tudo a
-- anon/authenticated/service_role. O pg_dump grava os privilégios de cada objeto em relação ao mínimo do Postgres
-- (só o dono), por isso, com esses privilégios por omissão ativos, cada tabela e função restaurada ficava ABERTA à API
-- (o ensaio apanhou isto: tabelas fechadas e funções internas como _authorize passavam a estar acessíveis a anon).
-- Retirar os privilégios por omissão do papel que restaura faz cada objeto nascer só com o dono; o dump aplica depois
-- os GRANT/REVOKE exatos da origem e, no fim, os seus próprios privilégios por omissão (entradas DEFAULT ACL).
alter default privileges in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges in schema public revoke all on functions from anon, authenticated, service_role;
