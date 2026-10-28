-- 20261028112410 formato_norm (exportado do Supabase a 28/10/2026; segredos tapados)
alter table public.script_analysis add column if not exists formato_norm text;
alter table public.reels add column if not exists taken_at timestamptz;;
