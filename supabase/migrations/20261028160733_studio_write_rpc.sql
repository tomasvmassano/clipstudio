-- 20261028160733 studio_write_rpc (exportado do Supabase a 28/10/2026; segredos tapados)
-- Códigos de acesso da equipa (não expostos pela API: RLS sem políticas).
create table if not exists public.studio_tokens (
  token text primary key,
  client_id text not null references public.clients(id),
  role text not null default 'creator',   -- admin | creator | editor
  label text,
  created_at timestamptz default now()
);
alter table public.studio_tokens enable row level security;
revoke all on public.studio_tokens from anon, authenticated;

insert into public.studio_tokens (token, client_id, role, label)
values ('<TEAM_CODE_REDACTED>', 'numeiro', 'creator', 'Equipa Numeiro (outubro 2026)')
on conflict (token) do nothing;

-- Escrita controlada: só campos de decisão/edição; nunca client_id nem id.
create or replace function public.guiao_update(p_id text, p_patch jsonb, p_token text)
returns public.guioes
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.studio_tokens;
  g public.guioes;
begin
  select * into t from public.studio_tokens where token = p_token;
  if t.token is null then
    raise exception 'codigo_invalido' using errcode = '28000';
  end if;
  select * into g from public.guioes where id = p_id and client_id = t.client_id for update;
  if g.id is null then
    raise exception 'guiao_nao_encontrado' using errcode = 'P0002';
  end if;

  -- edição de texto: guarda a versão anterior no histórico (máx. 10)
  if p_patch ? 'corpo' or p_patch ? 'hooks' then
    g.history := (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select x from jsonb_array_elements(g.history || jsonb_build_array(jsonb_build_object('hooks', g.hooks, 'corpo', g.corpo, 'at', g.updated_at))) x
      order by 1 desc limit 10) s);
  end if;

  update public.guioes set
    status           = coalesce(p_patch->>'status', status),
    motivo_rejeicao  = case when p_patch ? 'motivo_rejeicao' then p_patch->>'motivo_rejeicao' else motivo_rejeicao end,
    validado         = coalesce((p_patch->>'validado')::boolean, validado),
    validado_em      = case when p_patch ? 'validado' then (case when (p_patch->>'validado')::boolean then now() else null end) else validado_em end,
    gravado          = coalesce((p_patch->>'gravado')::boolean, gravado),
    gravado_em       = case when p_patch ? 'gravado' then (case when (p_patch->>'gravado')::boolean then now() else null end) else gravado_em end,
    hooks            = coalesce(p_patch->'hooks', hooks),
    corpo            = coalesce(p_patch->>'corpo', corpo),
    formato          = coalesce(p_patch->>'formato', formato),
    tema             = coalesce(p_patch->>'tema', tema),
    n                = coalesce((p_patch->>'n')::int, n),
    history          = g.history,
    updated_at       = now()
  where id = p_id
  returning * into g;
  return g;
end $$;

revoke all on function public.guiao_update(text, jsonb, text) from public;
grant execute on function public.guiao_update(text, jsonb, text) to anon, authenticated;

-- Verificar um código sem expor a tabela
create or replace function public.studio_whoami(p_token text)
returns table (client_id text, role text, label text)
language sql security definer set search_path = public as $$
  select client_id, role, label from public.studio_tokens where token = p_token;
$$;
revoke all on function public.studio_whoami(text) from public;
grant execute on function public.studio_whoami(text) to anon, authenticated;;
