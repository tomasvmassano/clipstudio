-- W4-03 (expand, 2/2): preenchimento do cliente nas 9 tabelas do motor (ADR-0016).
-- Reels novos ficam ligados à conta do cliente pelo handle e plataforma (antes ficavam sem account_id e fora do Desempenho).
-- Compatibilidade temporária: código antigo que não manda client_id só servia o Numeiro, por isso cai em 'numeiro'.
-- Esse fallback sai na migração contract (client_id passa a obrigatório e sem valor por omissão).
-- Rollback: recriar _engine_fill_client de 20261029111417 e largar os triggers das 5 tabelas novas.

create or replace function public._engine_fill_client() returns trigger language plpgsql set search_path = public as $$
begin
  if new.client_id is null then
    if tg_table_name = 'reels' and new.account_id is not null then
      select client_id into new.client_id from accounts where id = new.account_id;
    elsif tg_table_name in ('script_analysis','comment_analysis','reel_themes') then
      select client_id into new.client_id from reels where id = new.reel_id;
    end if;
    new.client_id := coalesce(new.client_id, 'numeiro');
  end if;
  if tg_table_name = 'reels' and new.account_id is null then
    select id into new.account_id from accounts
     where client_id = new.client_id and lower(handle) = lower(new.owner) and platform = coalesce(new.platform, 'instagram')
     order by active desc limit 1;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['themes','quotes','meta','generated','daily_reports'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_fill_client', t);
    execute format('create trigger %I before insert on public.%I for each row execute function public._engine_fill_client()', t || '_fill_client', t);
  end loop;
end $$;
