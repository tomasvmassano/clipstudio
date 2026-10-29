-- W4-03 (expand): correção de 20261029111654. O trigger lia new.account_id numa condição que também corre em tabelas
-- sem essa coluna (PL/pgSQL não garante curto-circuito no AND). Passa a ramos separados por tabela. Mesmo comportamento.
-- Rollback: recriar a versão de 20261029111654.

create or replace function public._engine_fill_client() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'reels' then
    if new.client_id is null and new.account_id is not null then
      select client_id into new.client_id from accounts where id = new.account_id;
    end if;
    new.client_id := coalesce(new.client_id, 'numeiro');
    if new.account_id is null then
      select id into new.account_id from accounts
       where client_id = new.client_id and lower(handle) = lower(new.owner) and platform = coalesce(new.platform, 'instagram')
       order by active desc limit 1;
    end if;
  elsif tg_table_name in ('script_analysis','comment_analysis','reel_themes') then
    if new.client_id is null then
      select client_id into new.client_id from reels where id = new.reel_id;
    end if;
    new.client_id := coalesce(new.client_id, 'numeiro');
  else
    new.client_id := coalesce(new.client_id, 'numeiro');
  end if;
  return new;
end $$;
