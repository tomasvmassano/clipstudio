# ADR-0003 — Fontes, briefs e pedidos do talento (W2-03)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M04 FR-04-01/02/04/06, FR-17-02/03, §20, §23; AGENTS §2.5, §6, §15.

## Contexto

As fontes vivem em `ideas`, escritas pelo motor (Repórter, Curioso, Filósofo), que lê `status='nova'` e marca `usada`. A página `/ideias` só lia, e lia campos que não existem (`take_numeiro` e `expires_at` estão em `data` e `expira_em`). O PRD pede curadoria com estados, dedup, proveniência, ligação N:N a guiões, brief estruturado e pedidos do talento.

## Decisão

1. `ideas` passa a ser a entidade canónica de fontes (PRD §23: reutilizar), com `kind` (`source` | `talent_request`). Os pedidos do talento entram na mesma caixa, não numa tabela paralela.
2. Estados `nova, triagem, selecionada, usada, descartada`; `rejeitada` continua aceite por compatibilidade com o motor e conta como descartada. Descartar exige motivo.
3. Dedup por URL normalizado (sem protocolo, `www`, query, fragmento, barra final) e por workspace, com índice único. Pela app, repetido = `PT409 duplicado:<id>`. Pelo motor, o repetido não falha: entra `descartada` com "duplicado de #id", para o motor nunca perder um lote.
4. `content_sources` (N:N, mesmo workspace por trigger). Ligar marca a fonte como `usada`. Desligar apaga a linha e fica auditado: a ligação não é uma decisão editorial.
5. `content_briefs` append-only; `guioes.brief_id` = brief em vigor; `content_versions.brief_id` = brief da versão. Uma aprovação aponta para a versão, logo para o brief em vigor quando foi aprovada. Mudar o brief não anula a aprovação; fica visível.
6. Capacidade nova `requests.create` (registo, papéis, código de equipa). `/ideias` redireciona para `/fontes`.

## Alternativas rejeitadas

- Tabela `sources` nova: duas fontes de verdade e o motor teria de mudar já.
- Brief como colunas em `guioes`: perdia o histórico e a ligação brief ↔ aprovação.
- Recusar duplicados do motor: um URL repetido derrubava a corrida diária.

## Consequências e pendentes

- O motor ainda não dá prioridade a `selecionada` nem lê pedidos do talento (W4, contrato motor ↔ app).
- Sem RSS nem integrações (FR-04-02 parcial), sem resumo por IA (FR-04-05), sem favoritos/feed personalizado (FR-04-07).
- Referências (M07) são o próximo incremento.

## Rollback

Bloco comentado no fim de `supabase/migrations/20261028202656_w2_sources_briefs_requests.sql`.
