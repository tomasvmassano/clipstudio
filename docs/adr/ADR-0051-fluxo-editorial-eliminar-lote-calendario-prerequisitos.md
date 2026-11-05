# ADR-0051 — Fluxo editorial: eliminar guiões, aprovar gravados em lote, calendário completo, pré-requisitos nas transições (W9)

**Data:** 2026-11-05 · **Estado:** aceite · **Requisitos:** PRD FR-02-01, FR-02-05, FR-11-02, FR-17-05, FR-15-02, R-09; AGENTS §2.6, §5, §6.

## Decisão

1. **Eliminar guiões arquivados (W9-01, FR-02-01).** Eliminar é uma lápide (R-09): o guião sai de listas, pesquisa, calendário, exportações e ações; versões e transições ficam (prova das aprovações) mas deixam de ser legíveis. Só arquivados, sem tarefas abertas, publicações nem ativos na biblioteca, com confirmação explícita (o ID) e sessão individual. Capacidade nova `scripts.purge` (dono do cliente e dono da agência). Recuperável durante 30 dias [pressuposto].
2. **Aprovar gravados em lote (W9-02, FR-02-05).** Os guiões gravados antes do fluxo novo (status legado `aprovado`, editorial `in_review`) aparecem todos numa lista própria; `content_bulk` ganha `recorded_only` na ação `approve` e aprova exatamente a versão que estava em vigor quando o guião foi marcado gravado (se o texto mudou depois, recusa esse guião com o motivo). É uma ação da equipa, não uma correção de dados.
3. **Calendário (W9-03, FR-11-02).** `calendar_range` junta revisões de vídeo (no dia do prazo da tarefa de revisão/edição, senão no dia do guião) e publicações planeadas/aprovadas, com as mesmas regras de acesso das vistas próprias; a UI só mostra as camadas a que a pessoa tem acesso.
4. **Pré-requisitos nas transições (W9-04, FR-17-05).** Por cliente e por transição de produção (agendar, gravado, edição, pronto): guião aprovado, sem tarefas bloqueadas, vídeo aprovado. `content_production` verifica no servidor e recusa com `pre_requisito_em_falta` e a causa em PT. A regra antiga "só se gravam guiões aprovados" é a célula gravado × guião aprovado (continua em `clients.require_approval_to_record`). Configurar com `settings.manage` em Definições. Voltar atrás nunca é bloqueado.

## Rollback

Bloco no fim de cada migração `*_w9_*.sql`. Sem linhas em `workflow_prerequisites` o comportamento é o de antes.
