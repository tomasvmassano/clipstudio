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

## Sessão de gravação e takes (W2-05)

Sessão (`recording_sessions`): `aberta → fechada`, uma aberta por cliente e dia, partilhada entre dispositivos. Fila (`recording_session_items`): elegíveis do dia + transitados por gravar; ordem, saltar conteúdo e saltar bloco persistem.

| Ação | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| abrir / entrar | `recording.use` | idempotente por cliente e dia; acrescenta novos elegíveis no fim | `recording.session_opened` |
| reordenar / saltar | `recording.use` | só itens da sessão; blocos `hook_N`, `body`, `cta` | auditoria `recording.queue_set` |
| progresso | `recording.use` | retoma; ≥80% uma vez por conteúdo e sessão | `recording.viewed_80` (telemetria, não marca gravado) |
| marcar take | `recording.confirm` | numerado por bloco, ligado à versão lida; idempotente por `client_ref`; não muda estados | `take.recorded` |
| escolher / descartar take | `recording.confirm` | um escolhido por bloco; descartado fica guardado | `take.selected` |
| fechar sessão | `recording.use` | não aceita mais takes; reabrir o dia cria sessão nova | `recording.session_closed` |

## Fontes e pedidos do talento (`ideas`, W2-03)

`nova → triagem → selecionada → usada`, ou `descartada` (motivo obrigatório). `kind = source | talent_request`.

| De → para | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| (criar) | `sources.create` | dedup por URL normalizado por workspace; repetido = PT409 `duplicado:<id>`; motor nunca falha, o repetido entra `descartada` com "duplicado de #id" | `source.created` |
| (pedido) | `requests.create` | texto 3–2000 caracteres; entra `nova`, nada é gerado sem aprovação | `request.created` |
| nova → triagem / selecionada | `sources.triage` | — | `source.status_changed` / `source.approved` |
| * → descartada | `sources.triage` | motivo | `source.discarded` |
| ligar a um guião | `scripts.edit` | mesmo workspace; fonte passa a `usada` | auditoria `content.source_linked` |
| fonte → guião | `scripts.create` | rascunho com tema, hooks e take da fonte; ligação automática | `script.created` |

O motor continua a consumir só `status='nova'`; `selecionada` ainda não tem prioridade no motor (contrato a fechar no W4).

## Brief (`content_briefs`, W2-03)

Cada gravação cria uma versão nova (append-only). `guioes.brief_id` aponta para a versão em vigor e `content_versions.brief_id` guarda o brief de cada versão, por isso a aprovação fica com o brief que estava em vigor (FR-17-03). Mudar o brief depois de aprovar não anula a aprovação; a app mostra "mudou depois da aprovação". Evento `brief.updated`.

## Revisão de media e publicação

Media: `not_submitted → pending → changes_requested | approved | rejected`.
Publicação (por destino/conta): `draft → scheduled → processing → published` ou `failed | cancelled`; idempotência por `(content_variant_id, social_account_id)`.

## Eventos de domínio (PRD §23)

`source.approved`, `script.submitted`, `script.approved`, `script.rejected`, `script.version_created`, `recording.confirmed`, `recording.session_opened`, `recording.viewed_80`, `take.recorded`, `take.selected`, `asset.uploaded`, `variant.ready`, `review.changes_requested`, `review.approved`, `publication.scheduled`, `publication.published`, `publication.failed`, `metrics.synced`, `run.started`, `run.step`, `run.failed`, `run.completed`. Publicados por outbox transacional; consumidores idempotentes.

## Mapeamento de hoje (`guioes`)

| Campo atual | Estado PRD |
| --- | --- |
| `status='aprovado'`, `validado=false` | editorial `in_review` (o motor aprovou; falta o Creator) |
| `validado=true` | editorial `approved` |
| `status='rejeitado'` + `motivo_rejeicao` | editorial `rejected` |
| `gravado=true` | produção `recorded` |
| `history` (10 versões de hooks/corpo) | precursor de `content_versions` |
