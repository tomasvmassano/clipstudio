-- 20261028162355 accounts_per_platform (exportado do Supabase a 28/10/2026; segredos tapados)
create table if not exists public.accounts (
  id text primary key,
  client_id text references public.clients(id),
  role text not null default 'client' check (role in ('client','reference')),
  platform text not null default 'instagram',
  handle text not null,
  label text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.accounts enable row level security;
drop policy if exists accounts_public_read on public.accounts;
create policy accounts_public_read on public.accounts for select to anon, authenticated using (true);

-- contas existentes: o cliente (dois owners históricos) e as 7 referências
insert into public.accounts (id, client_id, role, platform, handle, label)
values ('numeiro-ig', 'numeiro', 'client', 'instagram', 'itsnumeiro', 'Numeiro · Instagram principal')
on conflict (id) do nothing;
insert into public.accounts (id, client_id, role, platform, handle, label)
select owner || '-ig', null, 'reference', 'instagram', owner, owner || ' · Instagram'
from (select distinct owner from public.reels where role='reference') o
on conflict (id) do nothing;

alter table public.reels add column if not exists account_id text references public.accounts(id);
update public.reels set account_id = 'numeiro-ig' where role='client' and account_id is null;
update public.reels r set account_id = r.owner || '-ig' where role='reference' and account_id is null;
create index if not exists reels_account_idx on public.reels(account_id);

alter table public.guioes add column if not exists account_id text references public.accounts(id);

create table if not exists public.publicacoes (
  id bigserial primary key,
  guiao_id text references public.guioes(id) on delete cascade,
  account_id text not null references public.accounts(id),
  url text,
  reel_id text,
  published_at timestamptz,
  views bigint, likes bigint, comments bigint, shares bigint,
  updated_at timestamptz not null default now()
);
alter table public.publicacoes enable row level security;
drop policy if exists publicacoes_public_read on public.publicacoes;
create policy publicacoes_public_read on public.publicacoes for select to anon, authenticated using (true);;
