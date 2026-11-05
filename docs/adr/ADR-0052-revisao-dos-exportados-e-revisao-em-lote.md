# ADR-0052 — Revisão dos vídeos exportados e revisão em lote (W5-12)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD EDL-02, EDL-03, EDL-11, FR-05-03; AGENTS §2.6, §2.7, §8.

## Contexto

A revisão de vídeo (W5-04) só listava versões com link da Google Drive. O export do editor (W5-07) cria uma versão nova no R2 e avisava "já está na revisão", mas o vídeo não aparecia lá: o fluxo gravação → pacote → exportar → rever parava no fim. O QC técnico (EDL-03) existia no motor mas não corria sobre os exports.

## Decisão

1. **Elegibilidade única** `_review_eligible(versão)`: pronta e (link da Drive ou ficheiro de vídeo guardado). Usada na lista, nas contagens e no calendário (W9-03). Guiões eliminados ficam de fora.
2. **Player da app** para ficheiros: versão leve assinada (`media_proxy_access`, `media.read`, 1 h); sem versão leve, o original pela rota `url` (preview). Comentários por momento com o tempo do próprio vídeo.
3. **QC no export, informativo.** O worker corre `qc.run_qc` sobre o ficheiro exportado e grava o relatório em `media_info.qc` (versão do QC, checks com rótulo PT). Não bloqueia a versão: chumbos são notas para quem decide (os limites são pressupostos até ao piloto, EDL-06). Ficheiro ilegível fica `passed = null` com o erro, nunca como sucesso.
4. **Exportar o pacote** `edit_package_export`: chama `edit_export_request` por vídeo (mesma permissão `edit.export`, mesma idempotência pela versão do documento); falhas por vídeo voltam na resposta sem travar os outros; auditado.
5. **Fila "seguinte"**: depois de aprovar abre o próximo vídeo por rever pela ordem da lista (≤ 30 s por variante, EDL-02).

## Alternativas rejeitadas

- Exportar automaticamente quando o pacote acaba: gasta render sem um humano ter olhado para a v1 e esconde o custo; fica um clique explícito.
- QC a bloquear a versão: com limites ainda não calibrados, bloquearia vídeos bons (ex.: loudness de fala).
- Versão leve a 720p como o PRD sugere: mantém-se 540p (já gerada pelo worker, suficiente em telemóvel); revisitar no piloto.

## Rollback

Bloco no fim de `*_w5_review_stored.sql` (repor as funções anteriores). Os relatórios do QC em `media_info` ficam inertes.
