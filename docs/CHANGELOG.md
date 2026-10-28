# Changelog

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
