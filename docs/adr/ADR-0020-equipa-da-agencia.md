# ADR-0020 — Equipa da agência (W1-13)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD §2 (espaço da agência, R-13), §3, R-12, R-14, M13 (parcial).

## Decisão

1. **Página no espaço da agência** (`/equipa-agencia`): cada pessoa do staff com papel na agência, estado, último acesso, clientes onde trabalha (com o papel em cada um) e tarefas abertas.
2. **Permissões (registo existente):** ver com `team.read` de agência (dono e admin); convidar com `team.invite`; mudar papel, suspender, reativar e atribuir ou tirar de clientes com `team.manage` (dono). Ninguém muda a si próprio; o dono da agência não se altera aqui; não se convida nem promove a dono.
3. **Sem fugas entre clientes:** cada pessoa mostra só os clientes (e a carga) que quem vê também pode ver. Um admin da agência atribuído só ao cliente A não fica a saber que existe o cliente B.
4. **Convite para a agência** (`agency_invite`): sem cliente; a pessoa entra na agência sem acesso a clientes e o dono atribui-os. Recusado para quem já é staff, para quem já tem convite pendente e para quem é da equipa de um cliente (R-14).
5. **Suspender** corta logo o acesso a todos os clientes (já garantido por `_authorize`); reativar devolve-o. Tudo auditado no histórico da agência.
6. **Erro ao aceitar convites** deixa de ser silencioso: quem entra sem clientes vê o motivo.

## Pendentes

Envio do email de convite (próxima tarefa); papel em cada cliente continua a mudar-se dentro do cliente; presença/disponibilidade (§31) fica para depois.

## Rollback

Comentário no fim de `20261029130512_w1_agency_team.sql`; reverter o PR.
