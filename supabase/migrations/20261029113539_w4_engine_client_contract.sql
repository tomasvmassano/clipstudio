-- W4-03 (contract): chaves do motor por cliente (ADR-0016). Só depois de o PgDB por cliente estar no main do numeiro-engine (#3).
-- 1) client_id obrigatório e sem fallback 'numeiro'; 2) chaves e FKs compostas (cliente, id); 3) saem as chaves globais;
-- 4) o engine_worker só vê e escreve o cliente da sessão (engine.client_id, que o PgDB grava ao ligar);
-- 5) saem os grants de leitura antigos de anon/authenticated (sem efeito hoje: RLS sem política); 6) vistas e Desempenho filtram cliente.
-- Rollback: bloco no fim (repõe as chaves globais; só funciona enquanto não houver o mesmo id em dois clientes).

do $$
declare t text; n bigint;
begin
  foreach t in array array['reels','themes','reel_themes','quotes','meta','generated','script_analysis','comment_analysis','daily_reports'] loop
    execute format('select count(*) from public.%I where client_id is null', t) into n;
    if n > 0 then raise exception 'contract: % linhas sem cliente em %', n, t; end if;
  end loop;
  if exists (select 1 from reference_items x join reels r on r.id = x.reel_id where r.client_id <> x.workspace_id) then
    raise exception 'contract: referências ligadas a reels de outro cliente';
  end if;
end $$;

-- 1. trigger sem fallback: herda o cliente do reel ou da conta; se não houver, o NOT NULL recusa
create or replace function public._engine_fill_client() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'reels' then
    if new.client_id is null and new.account_id is not null then
      select client_id into new.client_id from accounts where id = new.account_id;
    end if;
    if new.account_id is null and new.client_id is not null then
      select id into new.account_id from accounts
       where client_id = new.client_id and lower(handle) = lower(new.owner) and platform = coalesce(new.platform, 'instagram')
       order by active desc limit 1;
    end if;
  elsif tg_table_name in ('script_analysis','comment_analysis','reel_themes') then
    if new.client_id is null then
      raise exception 'client_id_obrigatorio' using errcode = '23502';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public._engine_fill_client() from public, anon, authenticated;
do $$
declare t text;
begin
  foreach t in array array['themes','quotes','meta','generated','daily_reports'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_fill_client', t);
  end loop;
  foreach t in array array['reels','themes','reel_themes','quotes','meta','generated','script_analysis','comment_analysis','daily_reports'] loop
    execute format('alter table public.%I alter column client_id set not null', t);
  end loop;
end $$;

-- 2. FKs que apontavam para chaves globais
alter table public.reel_themes drop constraint reel_themes_reel_id_fkey, drop constraint reel_themes_theme_id_fkey;
alter table public.comment_analysis drop constraint comment_analysis_reel_id_fkey;
alter table public.script_analysis drop constraint script_analysis_reel_id_fkey;
alter table public.generated drop constraint generated_posted_reel_id_fkey, drop constraint generated_theme_id_fkey, drop constraint generated_quote_id_fkey;
alter table public.reference_items drop constraint reference_items_reel_id_fkey;

-- 3. chaves por cliente
alter table public.reels drop constraint reels_pkey;
alter table public.reels add constraint reels_pkey primary key using index reels_client_id_uq;
alter table public.script_analysis drop constraint script_analysis_pkey;
alter table public.script_analysis add constraint script_analysis_pkey primary key using index script_analysis_client_uq;
alter table public.comment_analysis drop constraint comment_analysis_pkey;
alter table public.comment_analysis add constraint comment_analysis_pkey primary key using index comment_analysis_client_uq;
alter table public.reel_themes drop constraint reel_themes_pkey;
alter table public.reel_themes add constraint reel_themes_pkey primary key using index reel_themes_client_uq;
alter table public.meta drop constraint meta_pkey;
alter table public.meta add constraint meta_pkey primary key using index meta_client_k_uq;
alter table public.themes drop constraint themes_tema_key;
alter table public.quotes drop constraint quotes_texto_pt_key;
create unique index themes_client_id_uq on public.themes (client_id, id);
create unique index quotes_client_id_uq on public.quotes (client_id, id);
alter table public.themes add constraint themes_client_id_key unique using index themes_client_id_uq;
alter table public.quotes add constraint quotes_client_id_key unique using index quotes_client_id_uq;

alter table public.reel_themes
  add constraint reel_themes_reel_fkey foreign key (client_id, reel_id) references public.reels (client_id, id) on delete cascade,
  add constraint reel_themes_theme_fkey foreign key (client_id, theme_id) references public.themes (client_id, id) on delete cascade;
alter table public.comment_analysis add constraint comment_analysis_reel_fkey foreign key (client_id, reel_id) references public.reels (client_id, id) on delete cascade;
alter table public.script_analysis add constraint script_analysis_reel_fkey foreign key (client_id, reel_id) references public.reels (client_id, id) on delete cascade;
alter table public.generated
  add constraint generated_posted_reel_fkey foreign key (client_id, posted_reel_id) references public.reels (client_id, id) on delete set null (posted_reel_id),
  add constraint generated_theme_fkey foreign key (client_id, theme_id) references public.themes (client_id, id) on delete set null (theme_id),
  add constraint generated_quote_fkey foreign key (client_id, quote_id) references public.quotes (client_id, id) on delete set null (quote_id);
alter table public.reference_items add constraint reference_items_reel_fkey foreign key (workspace_id, reel_id) references public.reels (client_id, id) on delete set null (reel_id);
create index if not exists reel_themes_client_theme on public.reel_themes (client_id, theme_id);

-- 4. engine_worker só no cliente da sessão
do $$
declare t text; e text := 'client_id = current_setting(''engine.client_id'', true)';
begin
  foreach t in array array['reels','themes','reel_themes','quotes','meta','generated','script_analysis','comment_analysis','daily_reports','ideas','agent_log'] loop
    execute format('alter policy %I on public.%I using (%s) with check (%s)', t || '_engine_worker', t, e, e);
  end loop;
end $$;

-- 5. grants antigos
revoke select on public.reels, public.themes, public.reel_themes, public.quotes, public.meta, public.generated,
  public.script_analysis, public.comment_analysis, public.daily_reports from anon, authenticated;

-- 6. Desempenho e Hoje: além da conta, o reel tem de ser do cliente
do $$
declare d text;
begin
  d := pg_get_functiondef('public.desempenho(text,text,text)'::regprocedure);
  d := replace(d, 'where a.client_id = p_client and a.role = ''client'' and (p_account is null or a.id = p_account)',
                  'where a.client_id = p_client and r.client_id = p_client and a.role = ''client'' and (p_account is null or a.id = p_account)');
  d := replace(d, 'left join reels r on r.account_id = a.id', 'left join reels r on r.account_id = a.id and r.client_id = a.client_id');
  d := replace(d, 'where a.role=''reference'' and a.client_id = p_client', 'where a.role=''reference'' and a.client_id = p_client and r.client_id = p_client');
  if (length(d) - length(replace(d, 'r.client_id', ''))) / length('r.client_id') <> 3 then raise exception 'contract: desempenho não bate certo'; end if;
  execute d;
  d := pg_get_functiondef('public.hoje_resumo(text,text)'::regprocedure);
  d := replace(d, 'from reels r where r.account_id in (select id from acc)', 'from reels r where r.account_id in (select id from acc) and r.client_id = p_client');
  if position('r.client_id = p_client' in d) = 0 then raise exception 'contract: hoje_resumo não bate certo'; end if;
  execute d;
end $$;

-- vistas antigas (só SQL editor): juntam por cliente e mostram o cliente
create or replace view public.v_top_reels as
 select r.owner, r.heat, r.outlier, r.debate_idx, r.views, r.comments, ca.polarizacao, ca.ponto_de_fricao, r.hook, r.url, r.client_id
   from reels r left join comment_analysis ca on ca.reel_id = r.id and ca.client_id = r.client_id
  where r.heat is not null order by r.heat desc limit 200;
create or replace view public.v_formatos as
 select g.formato, count(*) as gerados, count(*) filter (where g.status = 'posted') as publicados,
        round(avg(g.critic_score)::numeric, 2) as critic_medio,
        round((avg(r.outlier) filter (where g.status = 'posted'))::numeric, 2) as outlier_real, g.client_id
   from generated g left join reels r on r.id = g.posted_reel_id and r.client_id = g.client_id
  group by g.client_id, g.formato order by 5 desc nulls last;
create or replace view public.v_guioes_hoje as
 select g.id, g.status, g.formato, t.tema, g.critic_score, g.angulo, g.hook, g.guiao, g.data ->> 'texto_ecra' as texto_ecra,
        g.data ->> 'fecho_cta' as fecho_cta, g.data ->> 'legenda' as legenda, g.data ->> 'comentario_fixado' as comentario_fixado,
        g.data ->> 'cenario' as cenario, q.autor as citacao_autor, q.obra as citacao_obra, g.client_id
   from generated g left join themes t on t.id = g.theme_id and t.client_id = g.client_id
   left join quotes q on q.id = g.quote_id and q.client_id = g.client_id
  where g.date = current_date order by g.critic_score desc nulls last;
create or replace view public.v_guioes_virais as
 select r.owner, r.views, r.likes, r.comments, round(r.heat::numeric, 2) as heat, round(r.debate_idx::numeric, 2) as debate, s.polemica,
        s.hook, s.tese, s.alvo, s.formato, s.gatilho, s.porque_viraliza, s.angulo_numeiro, s.risco_plataforma, r.transcript, r.url, r.client_id
   from reels r join script_analysis s on s.reel_id = r.id and s.client_id = r.client_id order by r.views desc;
create or replace view public.v_temas as
 select tema, categoria, alvo, heat_medio, fit, risco, client_posts, round(client_avg_outlier::numeric, 2) as numeiro_outlier,
        (select count(*) from reel_themes rt where rt.theme_id = t.id and rt.client_id = t.client_id) as n_exemplos,
        porque_viraliza, ponto_de_fricao, t.client_id
   from themes t where active order by heat_medio desc nulls last;

/* Rollback (só enquanto nenhum id se repetir entre clientes):
-- vistas: recriar as de 20261019171228 (sem client_id) com drop view + create view
-- desempenho / hoje_resumo: recriar as versões de 20261028184500
grant select on reels, themes, reel_themes, quotes, meta, generated, script_analysis, comment_analysis, daily_reports to anon, authenticated;
-- políticas: alter policy <t>_engine_worker on <t> using (true) with check (true);
alter table reference_items drop constraint reference_items_reel_fkey;
alter table generated drop constraint generated_posted_reel_fkey, drop constraint generated_theme_fkey, drop constraint generated_quote_fkey;
alter table script_analysis drop constraint script_analysis_reel_fkey; alter table comment_analysis drop constraint comment_analysis_reel_fkey;
alter table reel_themes drop constraint reel_themes_reel_fkey, drop constraint reel_themes_theme_fkey;
alter table themes drop constraint themes_client_id_key; alter table quotes drop constraint quotes_client_id_key;
alter table quotes add constraint quotes_texto_pt_key unique (texto_pt); alter table themes add constraint themes_tema_key unique (tema);
alter table meta drop constraint meta_pkey; alter table meta add primary key (k);
alter table reel_themes drop constraint reel_themes_pkey; alter table reel_themes add primary key (reel_id, theme_id);
alter table comment_analysis drop constraint comment_analysis_pkey; alter table comment_analysis add primary key (reel_id);
alter table script_analysis drop constraint script_analysis_pkey; alter table script_analysis add primary key (reel_id);
alter table reels drop constraint reels_pkey; alter table reels add primary key (id);
-- e repor as FKs simples de 20261019171228, os índices *_client_uq e o trigger de 20261029111826
*/
