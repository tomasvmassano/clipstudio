# ADR-0012 — Criar e gerir clientes e a equipa de cada cliente (W1-06)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD §2, §3, R-03, R-04, R-05, R-11, R-12, CAP-03, CAP-06, CAP-08, SCALE-07, FL-01, TEAM-15, M15 (parcial).

## Decisão

1. **Cliente continua a ser uma linha de `clients`** (ADR-0001). `workspace_create` gera o id a partir do nome (minúsculas, sem acentos, com sufixo se repetir), valida fuso (IANA), moeda (3 letras) e @, e liga o cliente à organização de quem cria. Só quem tem `workspaces.create` na organização (hoje o dono da agência).
2. **Começar com a estrutura de outro cliente** (SCALE-07, FR-06-07 parcial): copia a configuração ativa dos agentes como rascunho sem voz, léxico, notícias, leituras nem orçamento e com a agenda desligada (fica inválida até alguém escrever a voz), os templates ativos pela mesma função de clonagem (sem responsáveis) e as automações sem responsável. Nunca copia pessoas, guiões, fontes, métricas nem segredos. Cada parte só é copiada se quem cria puder gerir essa parte na origem.
3. **Arquivar em vez de apagar.** `workspace_archive` exige motivo; o cliente deixa de ser aceite por `authorize` (que já exigia cliente ativo), por isso a equipa perde o acesso a tudo de uma vez (API, realtime, RPCs). Execuções em fila são canceladas e as que correm recebem pedido de cancelamento; a agenda já ignorava clientes arquivados. Recuperar devolve o estado anterior.
4. **Membros: suspender, reativar, mudar papel, remover** com regras no servidor: nunca a si próprio (R-12); só quem está ao seu nível ou abaixo, e só para papéis até ao seu (teto de autoridade); staff da agência só pelo dono da agência; o último dono do lado do cliente não perde o papel nem é removido por outra pessoa que não o dono da agência. Remover marca `status = removed` (a linha fica para autoria e auditoria) e reatribui as tarefas abertas a quem for escolhido, que tem de ter `tasks.work`, com evento e notificação (TEAM-15).
5. **Atribuir staff da agência sem convite** (`agency_staff_assign`): só o dono da agência, só a pessoas que já são da agência e não são equipa do cliente.
6. **`my_context` passa a trazer as capacidades de âmbito agência**, para a navegação mostrar Clientes; o servidor volta a verificar em cada função.

## Alternativas rejeitadas

- Apagar clientes: perde histórico, auditoria e métricas; o PRD pede soft-delete com recuperação (R-09).
- Copiar a configuração dos agentes já ativa: punha a voz e as regras de um cliente a gerar guiões noutro.
- Apagar a linha de `workspace_access` ao remover: perdia-se quem teve acesso e quando.

## Pendentes

Delegar criar/arquivar e atribuir staff ao admin da agência (precisa de grants de âmbito organização). Convidar com envio de email. Transferência formal de posse do cliente. Exportar e eliminar dados de um cliente (E2E-15). Resto das definições do cliente (M15: logótipo, branding, regras).

## Rollback

Bloco no fim de `20261029100534_w1_clients_team.sql`. `tmp_import` não volta (não era usada).
