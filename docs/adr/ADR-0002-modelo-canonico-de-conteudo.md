# ADR-0002 — Modelo canónico de conteúdo (W2-01)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD §4, §7, §23, FR-02-01..06, FR-17-04, FR-03-06; AGENTS §2.5, §2.6, §6.

## Contexto

`guioes` guardava o texto e três booleanos (`validado`, `gravado`, `status`) com um `history` em JSON. O PRD pede uma entidade canónica com estados editorial e de produção independentes, versões imutáveis e aprovações presas a uma versão exata. O motor e os dashboards (`hoje_resumo`, `desempenho`) leem as colunas antigas.

## Decisão

1. **Evoluir `guioes` em vez de criar `content_items` paralelo** (PRD §23: "reutilizar tabelas atuais por migração com mapping"). O nome muda no W4, junto com `client_id → workspace_id` (ADR-0001).
2. `guioes` é a **cópia de trabalho** (o que se edita, com `lock_version` para conflitos). `content_versions` são **fotografias imutáveis** criadas na criação, na submissão, na aprovação e na migração. Editar não cria versão a cada tecla; a versão nasce quando alguém decide sobre ela.
3. `approved_version_id` aponta para a versão aprovada. Editar um guião aprovado volta a `draft` e a aprovação continua na versão antiga.
4. `content_transitions` (append-only) guarda ator, versão, estado anterior e novo, motivo e correlation id. Cada transição escreve também `domain_events` (outbox) e `audit_events`.
5. As colunas antigas continuam sincronizadas nos dois sentidos: as RPCs mudam ambas; o trigger `guioes_legacy_sync` cobre escritas diretas do motor ou de scripts.
6. Sem eliminação definitiva nesta fase: "eliminar" é arquivar (recuperável). Versões e transições não se apagam.
7. Conflito de edição usa `PT409` (HTTP 409). `40001` deixava o PostgREST pendurado.
8. `clients.require_approval_to_record` (por defeito `false`, preset Numeiro): quando `true`, só se grava o aprovado.

## Alternativas rejeitadas

- **Tabela `content_items` nova com cópia dos dados**: duas fontes de verdade durante a transição e o motor teria de mudar já.
- **Versão a cada autosave**: centenas de versões por guião sem valor de auditoria; a aprovação precisa de uma fotografia, não de cada tecla.
- **Apagar fisicamente**: contraria AGENTS §6 (preservar versões rejeitadas e motivos).

## Consequências

- O motor continua a inserir em `guioes`; o trigger cria a versão 1 com `actor_kind = 'engine'`.
- O código de equipa ganhou `scripts.submit` (para reaprovar depois de editar).
- Falta: consumidores da outbox (W4), estados de produção além de gravado (W3), briefs e fontes ligadas (W2-02/03), diff visual entre versões.

## Rollback

Bloco comentado no fim de `supabase/migrations/20261028195656_w2_content_core.sql`; exportar `content_versions`/`content_transitions` antes.
