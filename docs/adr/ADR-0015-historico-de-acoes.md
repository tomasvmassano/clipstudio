# ADR-0015 — Histórico de ações por cliente (W1-09)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD R-05, CAP-07 (parcial), FR-15-06 (parcial).

## Decisão

1. **Leitura por função, tabela fechada.** `audit_list` exige `audit.read` no cliente e devolve só linhas desse cliente, com quem (email, ou Sistema/Código de equipa), o quê, sobre quê e o antes e depois. `audit_events` continua sem acesso direto à API e append-only.
2. **Paginação por cursor** (`id` descendente, até 200 por pedido, 50 por defeito) com índice `(workspace_id, id desc)`, para não degradar com o volume.
3. **Filtros validados no servidor:** ação exata ou prefixo (`script` apanha `script.*`), pessoa, período. O período é calculado no fuso do cliente pela app.
4. **Tentativas recusadas ficam no registo da base** (`RAISE LOG audit_denied`), como decidido no W1: gravá-las em `audit_events` seria desfeito pelo rollback da própria recusa.

## Pendentes

Vista de agência (todos os clientes de uma vez, para o dono e o admin com âmbito), exportação do histórico, retenção configurável (FR-15-06/07), e trazer as recusas para uma tabela própria escrita fora da transação recusada.

## Rollback

Comentário no topo de `20261029110013_w1_audit_list.sql`.
