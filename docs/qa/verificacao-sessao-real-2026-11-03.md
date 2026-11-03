# Verificação com sessão real (R-15), 2026-11-03

Produção (`clipstudio-jchs.vercel.app`, `main` em 091713e), sessão real do dono da agência (tomas@informallabs.com) no Chrome. Sem conta de cliente nesta passagem.

## Rotas

51 rotas abertas uma a uma (26 do espaço `/c/numeiro/*`, 10 da agência, 15 atalhos globais que redirecionam para o cliente). Em todas: título da página certo, sem página de erro genérica do browser/Next, sem spinner preso, 0 erros na consola. `/c/e2e-teste/biblioteca` recusa com "Não tens acesso a este cliente" (o dono não está atribuído a esse espaço): negação correta.

## Fluxos verificados

| ID | O que se fez | Resultado |
|---|---|---|
| FR-16-02 | Cmd+K, "Munique", Enter | encontra o guião pelo texto do corpo e abre-o |
| FR-03-01 | Teleprompter, dia 30/10 | fila com 23 gravados, filtros de campanha e responsável |
| FR-03-03 / FR-03-05 | Espelho horizontal ligado, página recarregada | mantém-se ligado, vertical intacto; reposto a seguir |
| FR-11-01 | Calendário semana e mês, mês anterior, separador Publicações | guiões e tarefas no dia; aviso honesto de publicação automática indisponível |
| BIZ-07 / CAP-05 | Permissões, Ver como numeiro@gmail.com | lista só de leitura com a origem de cada capacidade; `access.simulated` no audit |
| BIZ-01..03 | Vista de negócio, novembro | estados vazios explicados; alerta real "23 guiões à espera há mais de 48 h"; aviso de câmbio em falta |
| FR-05-03 | Revisão, separador Vídeos | estado vazio (ainda sem vídeos registados) |

## Achados

1. **23 guiões gravados nunca aprovados no fluxo novo.** Em `guioes`, `status = aprovado` mas `editorial_status = in_review` (22 com `validado = false` antes da migração W2; o backfill tratou "aprovado" legado como "não rejeitado", que é o que era). Foram gravados a 30/10 porque o Numeiro não exige aprovação para gravar. A Revisão mostra-os em "Por rever" e a vista de negócio alerta. Decisão do Tomás: aprová-los em lote na Revisão ou deixá-los como estão.
2. **Clientes com papel Admin.** As três contas Gmail do Numeiro são `client_staff` com `workspace_admin`, o que inclui ver custos do cliente, gerir permissões e convidar pessoas (access-matrix). Confirmar se é o papel pretendido para cada uma.
3. **Teleprompter abre sessão ao mudar de dia.** Navegar pelos dias cria uma sessão de gravação por dia e uma linha `recording.session_opened` no audit, mesmo em dias vazios. É o desenho atual ("abre ou junta-se à sessão do dia"); fica como melhoria de baixa prioridade abrir só ao começar.
4. **Vista de negócio sem dados de base.** Sem contrato do Numeiro nem câmbio EUR/AED registados, MRR e margem ficam a zero ou "-".

## Por fazer

A mesma passagem com uma conta de cliente (por exemplo tomasmassano4602@gmail.com noutra janela) para fechar as linhas que pedem R-15 do lado do cliente, e o arrastar no calendário.
