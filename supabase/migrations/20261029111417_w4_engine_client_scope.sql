-- W4-03 (expand): dados de pesquisa do motor por cliente (PRD R-02, AGENTS §5; ADR-0016). Decisão de produto: tudo por cliente.
-- Só aditivo: colunas client_id preenchidas, índices únicos por cliente e filtros por cliente nas funções da app.
-- As chaves globais (reels.id, themes.tema, quotes.texto_pt, meta.k) só saem na migração contract, depois de o motor novo estar no main.
-- Até lá, o mesmo reel em dois clientes dá erro em vez de misturar dados. Rollback: bloco no fim.

do $$
declare t text;
begin
  foreach t in array array['reels','themes','reel_themes','quotes','meta','generated','script_analysis','comment_analysis','daily_reports'] loop
    execute format('alter table public.%I add column if not exists client_id text references public.clients(id)', t);
  end loop;
end $$;

-- preencher: os reels pelo cliente da conta; o que depende de um reel, pelo reel; o resto é do Numeiro (único cliente com motor até hoje)
update public.reels r set client_id = a.client_id from public.accounts a where a.id = r.account_id and r.client_id is null;
update public.reels set client_id = 'numeiro' where client_id is null;
update public.script_analysis s set client_id = r.client_id from public.reels r where r.id = s.reel_id and s.client_id is null;
update public.comment_analysis s set client_id = r.client_id from public.reels r where r.id = s.reel_id and s.client_id is null;
update public.reel_themes s set client_id = r.client_id from public.reels r where r.id = s.reel_id and s.client_id is null;
update public.themes set client_id = 'numeiro' where client_id is null;
update public.quotes set client_id = 'numeiro' where client_id is null;
update public.meta set client_id = 'numeiro' where client_id is null;
update public.generated set client_id = 'numeiro' where client_id is null;
update public.daily_reports set client_id = 'numeiro' where client_id is null;

create unique index if not exists reels_client_id_uq on public.reels (client_id, id);
create unique index if not exists themes_client_tema_uq on public.themes (client_id, tema);
create unique index if not exists quotes_client_texto_uq on public.quotes (client_id, texto_pt);
create unique index if not exists meta_client_k_uq on public.meta (client_id, k);
create unique index if not exists script_analysis_client_uq on public.script_analysis (client_id, reel_id);
create unique index if not exists comment_analysis_client_uq on public.comment_analysis (client_id, reel_id);
create unique index if not exists reel_themes_client_uq on public.reel_themes (client_id, reel_id, theme_id);
create index if not exists generated_client_date on public.generated (client_id, date);
create index if not exists daily_reports_client on public.daily_reports (client_id, data);

-- compatibilidade com o código antigo, que não envia client_id: herda-o do reel ou da conta
create or replace function public._engine_fill_client() returns trigger language plpgsql set search_path = public as $$
begin
  if new.client_id is null then
    if tg_table_name = 'reels' then
      select client_id into new.client_id from accounts where id = new.account_id;
    elsif tg_table_name in ('script_analysis','comment_analysis','reel_themes') then
      select client_id into new.client_id from reels where id = new.reel_id;
    end if;
  end if;
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['reels','script_analysis','comment_analysis','reel_themes'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_fill_client', t);
    execute format('create trigger %I before insert on public.%I for each row execute function public._engine_fill_client()', t || '_fill_client', t);
  end loop;
end $$;

-- funções da app que liam reels e análises só pelo id passam a exigir o mesmo cliente
create or replace function public._reference_row(x reference_items)
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select to_jsonb(x) || jsonb_build_object(
    'metrics', (select jsonb_build_object('views', r.views, 'likes', r.likes, 'comments', r.comments, 'outlier', r.outlier,
                                          'duration', r.duration, 'collected_at', r.updated_at, 'source', 'scraper')
                from reels r where r.id = x.reel_id and r.client_id = x.workspace_id),
    'analysis', (select jsonb_build_object('tese', sa.tese, 'gatilho', sa.gatilho, 'estrutura', sa.estrutura, 'porque_viraliza', sa.porque_viraliza,
                                           'formato', coalesce(sa.formato_norm, sa.formato), 'analyzed_at', sa.analyzed_at)
                 from script_analysis sa where sa.reel_id = x.reel_id and sa.client_id = x.workspace_id),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('content_id', l.content_id, 'source_id', l.source_id,
                     'label', coalesce(case when g.id is not null then to_char(g.date,'DD/MM') || ' #' || g.n || ' ' || coalesce(g.tema,'') end, s.titulo)) order by l.created_at), '[]')
              from reference_links l left join guioes g on g.id = l.content_id left join ideas s on s.id = l.source_id where l.reference_id = x.id));
$function$;

create or replace function public.reference_items_before_write()
 returns trigger language plpgsql set search_path to 'public' as $function$
begin
  new.url_normalized := public.normalize_url(new.url);
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then raise exception 'workspace_imutavel' using errcode = '42501'; end if;
  if new.reel_id is not null and not exists (
       select 1 from reels r where r.id = new.reel_id and r.client_id = new.workspace_id) then
    raise exception 'workspace_incoerente' using errcode = '23514';
  end if;
  return new;
end $function$;

create or replace function public.reference_create(p_ws text, p_fields jsonb, p_token text DEFAULT NULL::text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare a jsonb := public._content_actor(p_token); x reference_items; dup bigint; u text := nullif(btrim(p_fields->>'url'), '');
        rid text := nullif(p_fields->>'reel_id', ''); r reels; sa script_analysis; acc accounts;
begin
  perform public._content_require('references.manage', p_ws, p_token, 'reference.create', null);
  if rid is not null then
    select * into r from reels where id = rid and client_id = p_ws;
    select * into acc from accounts where id = r.account_id;
    if r.id is null or acc.client_id is distinct from p_ws then raise exception 'sem_permissao' using errcode = '42501'; end if;
    select * into sa from script_analysis where reel_id = rid and client_id = p_ws;
    u := coalesce(u, r.url);
    if exists (select 1 from reference_items where workspace_id = p_ws and reel_id = rid) then
      raise exception 'duplicado:%', (select id from reference_items where workspace_id = p_ws and reel_id = rid) using errcode = 'PT409';
    end if;
  end if;
  if u is not null and u !~* '^https?://[^\s/$.?#].[^\s]*$' then raise exception 'url_invalido' using errcode = '22023'; end if;
  if u is null then raise exception 'url_obrigatorio' using errcode = '22023'; end if;
  select id into dup from reference_items where workspace_id = p_ws and url_normalized = public.normalize_url(u) limit 1;
  if dup is not null then raise exception 'duplicado:%', dup using errcode = 'PT409'; end if;
  insert into reference_items (workspace_id, url, reel_id, platform, creator, titulo, hook, formato, estilo, narrativa, duracao_s, idioma, tags, colecoes,
                               notas, created_by, created_kind, created_label)
  values (p_ws, u, rid,
          coalesce(nullif(p_fields->>'platform',''), r.platform, case when u ~* 'instagram\.com' then 'instagram' when u ~* 'tiktok\.com' then 'tiktok'
                                                                    when u ~* 'youtu' then 'youtube' end),
          coalesce(nullif(p_fields->>'creator',''), acc.handle),
          coalesce(nullif(btrim(p_fields->>'titulo'),''), nullif(r.hook,''), nullif(left(r.caption, 120),''), u),
          coalesce(nullif(p_fields->>'hook',''), nullif(r.hook,'')),
          coalesce(nullif(p_fields->>'formato',''), sa.formato_norm, sa.formato),
          nullif(p_fields->>'estilo',''),
          coalesce(nullif(p_fields->>'narrativa',''), sa.estrutura),
          coalesce(nullif(p_fields->>'duracao_s','')::integer, nullif(least(round(r.duration)::integer, 7200), 0)),
          coalesce(nullif(p_fields->>'idioma',''), sa.language),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'tags','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          coalesce((select array_agg(distinct btrim(t)) from jsonb_array_elements_text(coalesce(p_fields->'colecoes','[]'::jsonb)) t where btrim(t) <> ''), '{}'),
          nullif(p_fields->>'notas',''), (a->>'uid')::uuid, a->>'kind', a->>'label')
  returning * into x;
  insert into audit_events (actor_user_id, actor_kind, actor_label, workspace_id, action, entity_type, entity_id, after)
  values ((a->>'uid')::uuid, a->>'kind', a->>'label', p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('url', x.url, 'reel_id', x.reel_id));
  insert into domain_events (workspace_id, type, entity_type, entity_id, payload)
  values (p_ws, 'reference.created', 'reference', x.id::text, jsonb_build_object('reel_id', x.reel_id, 'actor_kind', a->>'kind'));
  return public._reference_row(x);
end $function$;

create or replace function public.references_discover(p_ws text, p_account text DEFAULT NULL::text, p_limit integer DEFAULT 60, p_token text DEFAULT NULL::text)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  perform public._content_require('references.read', p_ws, p_token, 'reference.discover', null);
  return jsonb_build_object(
    'creators', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'handle', a.handle, 'platform', a.platform,
                   'reels', (select count(*) from reels r where r.account_id = a.id and r.client_id = p_ws)) order by a.handle), '[]')
                 from accounts a where a.client_id = p_ws and a.role = 'reference' and a.active),
    'reels', (select coalesce(jsonb_agg(z order by (z->>'outlier')::real desc nulls last), '[]') from (
       select jsonb_build_object('id', r.id, 'url', r.url, 'platform', r.platform, 'creator', a.handle, 'hook', nullif(r.hook,''),
              'caption', nullif(left(r.caption, 280), ''), 'views', r.views, 'likes', r.likes, 'comments', r.comments, 'outlier', r.outlier,
              'duration', r.duration, 'collected_at', r.updated_at,
              'analysis', (select jsonb_build_object('tese', sa.tese, 'porque_viraliza', sa.porque_viraliza, 'formato', coalesce(sa.formato_norm, sa.formato))
                           from script_analysis sa where sa.reel_id = r.id and sa.client_id = p_ws)) z
         from reels r join accounts a on a.id = r.account_id
        where a.client_id = p_ws and r.client_id = p_ws and a.role = 'reference' and (p_account is null or a.id = p_account)
          and not exists (select 1 from reference_items x where x.workspace_id = p_ws and x.reel_id = r.id)
        order by r.outlier desc nulls last limit least(greatest(p_limit, 1), 200)) q));
end $function$;

/* Rollback:
-- funções: recriar as versões anteriores (_reference_row, reference_items_before_write, reference_create, references_discover de 20261028205017)
drop trigger reels_fill_client on reels; drop trigger script_analysis_fill_client on script_analysis;
drop trigger comment_analysis_fill_client on comment_analysis; drop trigger reel_themes_fill_client on reel_themes;
drop function _engine_fill_client();
drop index reels_client_id_uq, themes_client_tema_uq, quotes_client_texto_uq, meta_client_k_uq, script_analysis_client_uq,
  comment_analysis_client_uq, reel_themes_client_uq, generated_client_date, daily_reports_client;
-- alter table <tabela> drop column client_id;  (nas 9 tabelas)
*/
