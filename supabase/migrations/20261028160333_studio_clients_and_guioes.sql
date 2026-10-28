-- 20261028160333 studio_clients_and_guioes (exportado do Supabase a 28/10/2026; segredos tapados)
-- Multi-cliente desde o início: tudo o que a app lê tem client_id.
create table if not exists public.clients (
  id text primary key,                 -- slug: 'numeiro'
  name text not null,
  handle text,
  created_at timestamptz default now()
);
insert into public.clients (id, name, handle) values ('numeiro','Numeiro','itsnumeiro') on conflict (id) do nothing;

-- Guiões do dia, como a app os mostra (hooks x3 + corpo limpo). O motor escreve aqui; o Creator valida aqui.
create table if not exists public.guioes (
  id text primary key,                 -- '<client>-<data>-<nn>'
  client_id text not null references public.clients(id) default 'numeiro',
  date date not null,
  n int not null,
  formato text,
  maquina text,
  tema text,
  hooks jsonb not null default '[]',   -- [{text, mecanismo}]
  corpo text not null,
  fonte text,
  legenda text,
  comentario_fixado text,
  critic_score numeric,
  origem text,
  status text not null default 'aprovado',   -- aprovado | rejeitado
  motivo_rejeicao text,
  validado boolean not null default false,
  validado_em timestamptz,
  gravado boolean not null default false,
  gravado_em timestamptz,
  history jsonb not null default '[]',
  updated_at timestamptz default now()
);
create index if not exists guioes_client_date on public.guioes (client_id, date, n);

alter table public.clients enable row level security;
alter table public.guioes enable row level security;
-- Leitura pública (a página é partilhada por link); escrita só pelo servidor (service role).
drop policy if exists "guioes_read" on public.guioes;
create policy "guioes_read" on public.guioes for select using (true);
drop policy if exists "clients_read" on public.clients;
create policy "clients_read" on public.clients for select using (true);
drop policy if exists "ideas_read" on public.ideas;
create policy "ideas_read" on public.ideas for select using (true);;
