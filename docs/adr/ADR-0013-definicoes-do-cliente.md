# ADR-0013 — Definições do cliente e logótipo (W1-07)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M15 FR-15-01, FR-15-02 (parcial), FR-15-08 (parcial); R-02; AGENTS §5, §8.

## Decisão

1. **Uma página `/definicoes` por cliente** com o que é do workspace (geral e regras) e atalhos para o que já tem página própria (agentes, templates, automações, equipa), em vez de duplicar editores. Quem tem `team.read` vê; só quem tem `settings.manage` muda; o limite de tarefas continua em `tasks.manage`.
2. **Logótipo em storage privado** (`branding`, 500 KB, PNG/JPG/WebP, sem SVG por poder levar scripts). Caminho fixo `<cliente>/logo-<aleatório>.<ext>`; as políticas do storage extraem o cliente do caminho e exigem caminho válido (sem isso `authorize(cap, null)` avaliaria capacidades de agência). Ler: quem tem `scripts.read` ou `team.read` no cliente; escrever e apagar: `settings.manage`. A app usa URLs assinados de 1 hora. Cada envio tem nome novo, por isso não há cache velha.
3. **`workspace_update` só aceita um logótipo que já existe no bucket desse cliente** e cor `#rrggbb`; tudo auditado com antes e depois.
4. **Idioma fica fixo em PT-PT** e a página diz isso, em vez de mostrar uma opção sem efeito (AGENTS §4).

## Alternativas rejeitadas

- Bucket público: qualquer pessoa com o link via o logótipo e o caminho revela que o cliente existe (CAP-08).
- Guardar o logótipo em base64 na tabela: pesa em cada `my_context` e não tem limites de tipo e tamanho.

## Pendentes

Integrações (FR-15-03, W6), notificações (FR-15-05), segurança (FR-15-06), dados e exportação (FR-15-07), transferir posse (FR-15-08). Usar a cor da marca nos relatórios e exportações.

## Rollback

Blocos no fim das duas migrações. O bucket só se remove depois de vazio.
