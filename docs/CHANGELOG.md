# Changelog

## 2026-10-28

- Design system: shell e dashboard passam para o efferd `app-shell-3` + `dashboard-3`. Navegação com estado ativo por rota; módulos do PRD ainda sem página aparecem como "em breve", sem link (AGENTS.md §4).
- Hoje (`/`): layout do dashboard-3 com dados reais: guiões do dia, validados, gravados, views 30 dias vs 30 anteriores, views por dia (7/30/60), mix de formatos, produção diária, views médias por semana, agentes da última corrida real, guiões de hoje e atividade. Nova RPC só de leitura `hoje_resumo(p_client)`.
- Desempenho (`/desempenho`): passa ao layout do dashboard-3, por conta: views 30 dias e reels publicados vs 30 dias anteriores, mediana, virais, views por dia (7/30/60), reels por nível de outlier, views médias por semana, produção diária, mediana vs referências, top reels e últimos publicados. A RPC `desempenho` ganha `diario`, `bandas` e os totais dos 30 dias anteriores. Removidos os componentes de demonstração do dashboard-5 que já não eram usados.
- Teleprompter: deixa de marcar "gravado" sozinho aos 80% de leitura. Ao avançar ou sair pergunta "Gravaste?" (Enter/Esc). Cumpre AGENTS.md §6 e PRD §20.
- Sala dos agentes: o ensaio deixa de inventar resultados (AGENTS.md §7). Mensagens marcadas `[ensaio]`, só temas e hooks reais. Ensaios não contam no Hoje.
- Sessão: diálogo do código de equipa único no shell; menu do utilizador mostra a sessão real (sem perfil de demonstração).
- Documentação: `AGENTS.md` v1.1 (com regras do Next.js preservadas), `CLAUDE.md` e `docs/ClipStudio_PRD_Master_v2.1.md`.

### Limitações conhecidas (PARTIAL)

- Acesso ainda por código de equipa partilhado; Supabase Auth individual e workspaces (PRD §2, §16, MIG-04) por fazer.
- Sem testes automatizados no repo (só E2E manual com Playwright nesta sessão).
- `feature-registry.md`, `access-matrix.md`, `workflow-registry.md` e ADRs ainda por criar.
