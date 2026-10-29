-- supabase/tests/fixtures/seed.sql: dados sintéticos para os testes SQL numa base limpa (CI).
-- As datas são relativas a hoje (Dubai) para os testes não dependerem do dia em que correm.
-- Imitam a forma dos dados do workspace numeiro em produção (30 guiões do dia 28/10, fontes,
-- contas de referência com reels, configuração de agentes ativa) sem copiar conteúdo real.
-- Só para bases descartáveis; scripts/db/test.sh aplica-o depois das migrações.
-- 6 criadores de referência, como em produção
insert into accounts (id, client_id, role, platform, handle, label)
select 'ref' || g || '-ig', 'numeiro', 'reference', 'instagram', 'ref_' || g, 'ref_' || g || ' · Instagram' from generate_series(1, 6) g
on conflict do nothing;

insert into reels (client_id, id, platform, owner, role, url, views, likes, comments, outlier, account_id, taken_at)
select 'numeiro', 'FX' || a.handle || g, 'instagram', a.handle, a.role, 'https://www.instagram.com/reel/FX' || a.handle || g || '/',
       1000 * g, 50 * g, 5 * g, (g % 5) + 0.5, a.id, now() - make_interval(days => g)
from accounts a, generate_series(1, 100) g where a.client_id = 'numeiro' and (a.role = 'client' or g <= 8)
on conflict do nothing;

-- 14 fontes: notícias e reels com URL, livros sem
insert into ideas (client_id, fonte_tipo, titulo, fonte_url)
select 'numeiro', t, initcap(t) || ' de teste ' || g, case when t = 'livro' then null else 'https://exemplo.pt/' || t || '-' || g end
from generate_series(1, 14) g, lateral (select (array['noticia','livro','reel'])[1 + g % 3] t) x;

insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, cta, origem, status, validado, editorial_status)
select 'numeiro-2026-10-28-' || lpad(g::text, 2, '0'), 'numeiro', (now() at time zone 'Asia/Dubai')::date, g,
       (array['mecanismo','paradoxo','tabu','hipocrisia','noticia','lista'])[1 + g % 6], 'Tema de teste ' || g,
       (select jsonb_agg(jsonb_build_object('text', 'Hook ' || h || ' do guião ' || g, 'mecanismo', '')) from unnest(array['A','B','C']) h), 'Corpo de teste do guião ' || g || '.', null,
       'fixture', 'aprovado', g = 1, case when g = 1 then 'approved' else 'in_review' end
from generate_series(1, 30) g
on conflict do nothing;

-- configuração de agentes ativa (sintética, passa agent_config_validate)
insert into agent_config_versions (workspace_id, version_no, status, config, notes, validation, created_label, activated_at)
select 'numeiro', 1, 'active', c, 'fixture', agent_config_validate(c), 'fixture', now()
from (select jsonb_build_object(
  'language', 'pt-PT', 'voice', 'Voz de teste, direta.', 'lexicon', jsonb_build_array('teste'),
  'guardrails', jsonb_build_array('Sem afirmações falsas sobre terceiros.'),
  'formats', jsonb_build_object(
    'mecanismo', jsonb_build_object('share', 0.5, 'min', 0.2, 'max', 0.7, 'palavras', jsonb_build_array(60, 120)),
    'paradoxo', jsonb_build_object('share', 0.5, 'min', 0.2, 'max', 0.7, 'palavras', jsonb_build_array(60, 120))),
  'pipeline', jsonb_build_object('scripts_per_day', 30, 'hooks_per_slot', 3, 'critic_threshold', 7, 'concurrency', 4,
                                 'hook_min', 6, 'hook_threshold', 7, 'max_revisions', 2, 'idea_share', 0.3),
  'models', jsonb_build_object('writer', 'claude-sonnet-5-5'),
  'schedule', jsonb_build_object('enabled', true, 'time', '18:00'),
  'budget_eur_day', 20) c) x
where not exists (select 1 from agent_config_versions where workspace_id = 'numeiro');

-- temas do motor
insert into themes (client_id, tema, categoria, active)
select 'numeiro', 'Tema de teste ' || g, 'geral', true from generate_series(1, 5) g
on conflict do nothing;

-- W5-02: ponto de partida do catálogo de estilos e do preset de edição do numeiro (a migração só semeia se o cliente já existir)
select public._edit_seed('numeiro', 'system', 'fixture');
