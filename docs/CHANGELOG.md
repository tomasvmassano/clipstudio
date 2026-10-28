# Changelog

## 2026-10-29 (CHG-000 processo)

- **CHG-000 PRD com fonte única e trabalho por PR** (PRD §28, §33; AGENTS §10, §11, §15; ADR-0004). O PRD só é escrito neste repo e só muda em PRs só de documentação com `docs/changes/CHG-NNN.md`; o workflow `PRD guard` chumba o resto. `CLAUDE.md` ganha a secção "Change workflow": nada de push direto para `main`, merge por PR com checks verdes e preview verificado, migrações em expandir/contrair. Sem alteração funcional.
- Por fazer: ligar a proteção do `main` no GitHub (PR obrigatório, 0 aprovações, checks `prd-guard` e Vercel obrigatórios). Até lá o guard avisa mas não bloqueia.

## 2026-10-29 (W2 Conteúdo)

- **W2-01 modelo canónico de conteúdo** (PRD §4, §7, §23, FR-02-01..06, FR-17-04; ADR-0002). Migrações `20261028195656_w2_content_core`, `20261028195905_w2_legacy_sync`, `20261028200818_w2_conflict_code_pt409`.
  - `guioes` ganha estado editorial (`draft → in_review → changes_requested/approved/rejected`, `archived`) e de produção independentes, `cta`, `notas`, `lock_version`.
  - `content_versions` imutáveis; a aprovação fica presa à versão exata (`approved_version_id`); editar um aprovado volta a rascunho sem perder a aprovação antiga.
  - `content_transitions` append-only; outbox `domain_events`; auditoria em cada ação.
  - RPCs `content_save`, `content_transition`, `content_production`, `content_create`, `content_duplicate`, `content_history`, `content_restore_version`; `guiao_update` passa a usar o modelo novo.
  - Os 30 guiões existentes migrados com versão 1 e estado "em revisão".
- **W2-02 app de guiões**: editor por blocos (Hook 1..N, Corpo, CTA, Notas) que guarda sozinho e deteta conflitos de edição; Aprovar, Pedir alterações, Rejeitar (motivo obrigatório), Retirar aprovação, Recuperar; Histórico com versões, autoria e "Usar este texto"; Novo guião, Duplicar, Arquivar conforme a capacidade; filtros por estado. Teleprompter mostra o CTA e deixa de engolir erros ao marcar gravado.
- **W2-04 referências** (PRD M07; ADR-0005; migrações `20261028205017_w2_references`, `20261028205134_w2_references_zero_duration`).
  - `/referencias` (sai de "em breve"): Biblioteca com pesquisa, coleções e favoritos; Descobrir com os reels dos criadores seguidos ainda por guardar, ordenados por quanto ficaram acima da mediana, já com a análise; Arquivo.
  - Guardar um reel na biblioteca herda hook, formato, narrativa, duração e idioma; adicionar por link; classificar (formato, estilo, narrativa, duração, idioma, tags, coleções, notas).
  - Métricas só com origem e data ("scraper · 29/10"); referências por link não mostram números.
  - Referências no painel do guião (ligar e desligar) e "Usada em" na biblioteca. Também ligáveis a fontes.
  - Corrigido antes de chegar à app: reels com duração 0 faziam falhar o guardar.
  - Testes: `w2_references` 36/36; E2E em workspace de teste isolado 13/13.
- **W2-03 fontes, briefs e pedidos do talento** (PRD M04, FR-17-02/03, §20; ADR-0003; migração `20261028202656_w2_sources_briefs_requests`).
  - `/fontes` substitui `/ideias` (redirecionamento): separadores Por triar, Selecionadas, Pedidos, Usadas, Descartadas, Todas; pesquisa; Adicionar fonte por link com deteção de repetidos; Selecionar, Em triagem, Descartar com motivo; Criar guião a partir da fonte.
  - Corrigido: o "take" e a expiração das fontes nunca apareciam (a página lia campos que não existem).
  - Pedido do talento por texto ("Pedir um tema"), também disponível no código de equipa. Nada é gerado sem aprovação.
  - Painel "Brief e fontes" em cada guião: brief estruturado com versões, fontes ligadas, ligar e desligar. A aprovação guarda o brief em vigor; se mudar depois, a app avisa.
  - Capacidade nova `requests.create`. URL repetido vindo do motor não derruba a corrida: entra descartado com a referência ao original.
  - Testes: `w2_sources` 41/41, `w2_content` 47/47 (regressão). E2E em workspace de teste isolado 16/16.
- Testes (W2-01/02): `w2_content` 47/47, `w1_review_fixes` 11/11, `w1_data_access` 25/25 (com o modelo novo). E2E de escrita num workspace de teste isolado (criado e apagado no fim) 23/23.

### Limitações conhecidas W2 (PARTIAL)

- Sem eliminação definitiva (só arquivo); sem diff visual entre versões; sem bulk actions (FR-02-05) nem vistas guardadas (FR-02-07).
- Outbox sem consumidores (W4). Estados de produção além de gravado chegam no W3.
- Fontes: sem RSS/integrações nem resumo por IA; o motor ainda não prioriza fontes selecionadas nem lê pedidos (W4). Referências (M07) entregues no W2-04.

## 2026-10-28 (W1 Fundação)

- **Produção**: app no Vercel em `https://clipstudio-c8h1.vercel.app` (deploy automático a cada push no `main`). Projeto Supabase `numeiro-engine` transferido para a organização **Informal Labs** (mesmo ref, mesmas chaves). Auth: Site URL = Vercel; Redirect URLs = `https://clipstudio-c8h1.vercel.app/**` e `http://localhost:3000/**`. E2E em produção 21/21; anónimo continua sem acesso (401/42501).

- **W1-01 identidade e tenancy** (PRD §2, §3, §16, CAP-01..04, TEAM-01..03): organização ClipStudio, `workspace_access`, `agency_memberships`, `permission_grants` (allow/deny com expiração), `invitations`, `audit_events` append-only, registo de capacidades e `authorize(cap, ws)` deny-by-default. ADR-0001.
- **W1-02 corte do acesso aos dados**: fim das leituras anónimas; RLS por `authorize()`; RPCs verificam o workspace (login) ou o token legado (`legacy_can`); escritas auditadas; canal de agentes privado (`agents:<ws>`); guiões no realtime.
- **W1-03 app com login individual**: `/login` (email+palavra-passe; Google aparece só quando o fornecedor estiver ativo no Supabase; código de equipa como opção de transição), `/auth/callback` (PKCE, destino só interno), `src/proxy.ts` (verificação otimista, renova cookies), contexto de workspace com troca entre clientes autorizados, todas as páginas atrás de `WorkspaceGate` com a capacidade certa, menu lateral derivado das capacidades.
- **Ecrã de entrada novo (efferd `auth-5`)**: email primeiro, depois palavra-passe (entrar ou criar conta); Google só aparece quando o fornecedor estiver ligado; código de equipa como opção discreta. Removidos do bloco os botões Apple/GitHub, o testemunho inventado e os links `#` (AGENTS §4). Links de email que caiam na Site URL com `?code=` passam a ir para `/auth/callback`; `otp_expired` (link já usado) mostra uma mensagem clara em PT-PT.
- **Equipa (`/equipa`)**: membros, convites pendentes, convidar (papel até ao teu teto; staff da agência só pelo dono), cancelar convite. RPCs `workspace_team`, `revoke_invitation` (migração `20261028185835_w1_team_rpcs`).
- **Revisão de segurança independente** (migração `20261028191546_w1_review_fixes`):
  - Open redirect em `next` (`/%09/evil.com` virava `//evil.com`): helper único `src/lib/safe-next.ts` que recusa caracteres de controlo e confirma a origem.
  - Editar um guião validado anula a validação (AGENTS §2.6), com a versão anterior no histórico e `validacao_anulada` no audit; `status` só aceita `aprovado`/`rejeitado`.
  - Convidar staff da agência passa a exigir o dono da agência também no servidor (antes só a UI escondia).
  - Entrar com conta apaga o código de equipa guardado nesse browser.
  - Testes negativos passam a exigir o SQLSTATE certo (antes qualquer erro contava como recusa).
- Testes SQL (com rollback): `w1_isolation` 38/38, `w1_team` 21/21, `w1_data_access` 25/25, `w1_review_fixes` 10/10. `tests/safe-next.test.mts` 10/10. E2E Playwright (modo código e anónimo) 11/11.

### Limitações conhecidas W1 (PARTIAL)

- Tentativas negadas vão para o log da base (`RAISE LOG audit_denied`), não para `audit_events` (o rollback da exceção apagava-as).
- Convites não enviam email: quem convida avisa a pessoa.
- Google OAuth por configurar no Supabase (o botão fica escondido até lá).
- Motor ainda não integrado (escreve em `generated`, `agent_log` sem `client_id`).
- Consola de permissões (CAP-02: overrides por pessoa, papéis custom) fica para W1.1.
- `tmp_import` ainda pode ser chamada por anónimos (protegida só por token fixo) e escreve em `reels`/`script_analysis`: apagar quando confirmares que já não é usada.
- Código de equipa: sem expiração nem limite de tentativas em `studio_whoami`, e o `?k=` fica nos logs do servidor antes de sair do URL. Aceitável só durante a transição; retirar quando o Numeiro tiver conta.
- Extensão `citext` no schema `public`.
- E2E com contas reais (agência A+B, cliente A, cliente B) depende de contas criadas pelo Tomás; os testes SQL cobrem esses casos com utilizadores simulados.

## 2026-10-28

- **W0 (inventário e contratos)**: `docs/inventory/supabase.md`, `docs/inventory/engine-and-app.md`, `docs/feature-registry.md`, `docs/access-matrix.md`, `docs/workflow-registry.md`. As 15 migrações aplicadas estão agora em `supabase/migrations/` (segredos tapados; o repo é público).
- **SEC-HOTFIX-001**: `anon`/`authenticated` tinham INSERT/UPDATE/DELETE por defeito; a vista `agent_feed` (security definer) permitia apagar `agent_log` com a chave pública. Revogada toda a escrita direta, fechadas as vistas `v_*` à API, privilégios por defeito corrigidos. Reteste: escrita 401, app 200.
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
