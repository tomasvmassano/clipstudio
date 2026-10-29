# ADR-0014 — Consola de permissões por cliente (W1-08)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD CAP-02, CAP-03, CAP-05, CAP-07 (parcial), R-12; AGENTS §15.

## Decisão

1. **Exceções em `permission_grants`, que já existia** (ADR-0001), em vez de um modelo novo de papéis. Cada exceção permite ou nega uma capacidade de âmbito cliente a uma pessoa, com motivo obrigatório e prazo opcional (até um ano). Uma ativa por pessoa e capacidade; a nova substitui a anterior. Retirar marca `revoked_at`/`revoked_by` (nada se apaga) e `_authorize` passa a ignorar exceções retiradas.
2. **Teto de autoridade (R-12):** só quem tem `permissions.manage`; nunca a si próprio; só a quem está ao seu nível ou abaixo; staff da agência só pelo dono da agência; permitir só o que o próprio tem. Negar é sempre possível dentro do teto, porque tirar acesso não escala privilégios.
3. **"Porque tem acesso?" (CAP-05)** com `_access_explain`, que segue a mesma ordem de `_authorize` (capacidade desconhecida, cliente arquivado, negação, dono da agência, membro, suspenso, expirado, staff suspenso na agência, papel, exceção) e devolve as razões em português. Cada pessoa pode perguntar por si; sobre outros, só quem gere permissões no mesmo cliente.
4. **Nomes legíveis no registo de capacidades** (`capabilities.label`) e uma função só de leitura para os nomes, porque a tabela continua fechada à API.
5. **Matriz papéis × capacidades só de leitura** nesta fase.

## Alternativas rejeitadas

- Papéis personalizados já: exigem versões de papéis, migração dos membros e testes de precedência formais (§30.1). As exceções cobrem os casos imediatos (férias, um editor que também aprova) sem esse custo.
- Apagar exceções ao retirar: perde-se quem tinha o quê e quando.

## Pendentes

Papéis personalizados versionados (CAP-03), aprovação por segunda pessoa para mudanças sensíveis e pré-visualização do impacto (CAP-07), revisões periódicas de acessos (CAP-06), simulador "ver como" (CAP-05), exceções de âmbito agência (delegar criar clientes ao admin da agência).

## Rollback

Blocos no fim das duas migrações.
