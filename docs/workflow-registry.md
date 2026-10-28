# Registo de workflows e eventos

> **Estado (W2-01, 2026-10-29):** editorial e produção (gravado/por gravar) implementados em `content_transition` e `content_production`; versões imutáveis em `content_versions`; transições em `content_transitions`; eventos na outbox `domain_events` (ainda sem consumidores, W4). Conflitos de edição devolvem `PT409` (HTTP 409). Ver ADR-0002.

Fonte: PRD v2.1 §4 (estados), §20 (teleprompter), §23 (eventos), AGENTS §6. Cada transição guarda ator, timestamp, versão, estado anterior e novo, motivo e correlation id. Estados editorial, produção, revisão de media e publicação são **independentes**.

## Editorial (por `content_version`)

```
draft → in_review → changes_requested → in_review → approved
                                      ↘ rejected
approved | rejected → archived   (regras)
```

| De → para | Capacidade | Obrigatório | Evento |
| --- | --- | --- | --- |
| draft → in_review | `scripts.submit` | — | `script.submitted` |
| in_review → changes_requested | `scripts.reject` | motivo | `review.changes_requested` |
| in_review → approved | `scripts.approve` | versão exata | `script.approved` |
| in_review → rejected | `scripts.reject` | motivo | `script.rejected` |
| approved → (editar) | `scripts.edit` | volta a `draft`; a aprovação anterior fica ligada à versão antiga (R-06); a versão nova nasce na próxima submissão/aprovação | `script.reopened` |
| draft / changes_requested → approved | `scripts.approve` + `scripts.submit` | regista `in_review` e `approved` na mesma operação, com a versão exata | `script.submitted`, `script.approved` |
| rejected → in_review | `scripts.approve` | recuperar | `script.reopened` |
| approved → in_review | `scripts.approve` | retirar aprovação | `script.unapproved` |
| * → archived, archived → (estado anterior) | `scripts.delete` | sem eliminação definitiva | `script.archived`, `script.restored` |

## Produção (por conteúdo)

`not_started → scheduled → recording → recorded → editing → ready → published` ou `cancelled`.

| De → para | Capacidade | Regra |
| --- | --- | --- |
| scheduled → recording | `recording.use` | abrir o teleprompter numa sessão |
| recording → recorded | `recording.confirm` | **só com confirmação explícita**; ler 80% gera só a telemetria `viewed_80_percent` (PRD §20) |
| recorded → recording | `recording.confirm` | desmarcar (take falhado) |

Por defeito conteúdos `rejected` não entram na fila do teleprompter; o workspace pode exigir `approved` para gravar.

## Revisão de media e publicação

Media: `not_submitted → pending → changes_requested | approved | rejected`.
Publicação (por destino/conta): `draft → scheduled → processing → published` ou `failed | cancelled`; idempotência por `(content_variant_id, social_account_id)`.

## Eventos de domínio (PRD §23)

`source.approved`, `script.submitted`, `script.approved`, `script.rejected`, `script.version_created`, `recording.confirmed`, `asset.uploaded`, `variant.ready`, `review.changes_requested`, `review.approved`, `publication.scheduled`, `publication.published`, `publication.failed`, `metrics.synced`, `run.started`, `run.step`, `run.failed`, `run.completed`. Publicados por outbox transacional; consumidores idempotentes.

## Mapeamento de hoje (`guioes`)

| Campo atual | Estado PRD |
| --- | --- |
| `status='aprovado'`, `validado=false` | editorial `in_review` (o motor aprovou; falta o Creator) |
| `validado=true` | editorial `approved` |
| `status='rejeitado'` + `motivo_rejeicao` | editorial `rejected` |
| `gravado=true` | produção `recorded` |
| `history` (10 versões de hooks/corpo) | precursor de `content_versions` |
