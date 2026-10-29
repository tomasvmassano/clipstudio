# Registo de workflows e eventos

> **Estado (W2-01, 2026-10-29):** editorial e produção (gravado/por gravar) implementados em `content_transition` e `content_production`; versões imutáveis em `content_versions`; transições em `content_transitions`; eventos na outbox `domain_events` (ainda sem consumidores, W4). Conflitos de edição devolvem `PT409` (HTTP 409). Ver ADR-0002.

Fonte: PRD v2.1 §4 (estados), §20 (teleprompter), §23 (eventos), AGENTS §6. Cada transição guarda ator, timestamp, versão, estado anterior e novo, motivo e correlation id. Estados editorial, produção, revisão de media e publicação são **independentes**.

## Clientes e membros (W1-06)

Cliente: `active → archived → active`. Arquivar exige motivo, corta logo o acesso de toda a equipa (`authorize` só aceita clientes ativos), cancela execuções em fila e pede cancelamento das que estão a correr; recuperar devolve tudo como estava. Nada é apagado.
Membro (`workspace_access.status`): `active ⇄ suspended`, `active|suspended → removed`. Removido perde o acesso já, fica no histórico e as tarefas abertas passam para quem for escolhido (ou ficam sem responsável), com evento `reassigned` e notificação. Um convite novo aceite reativa o acesso com o papel do convite. Tudo com antes e depois em `audit_events`.

## Convites (aceitação, W1-11; envio, W1-14)

`pendente → aceite` (email confirmado igual ao do convite) ou `pendente → cancelado` (revogado por quem convidou, ou bloqueado por cliente único: a pessoa já está ativa na equipa de outro cliente; fica `invitation.blocked` no histórico do cliente que convidou).
Envio (W1-14, ADR-0023): `invitation_issue_link` gera um token novo (só o hash fica na base; o link anterior deixa de valer), renova a validade para 14 dias e conta o envio (máximo 5, um por minuto). `pendente → recusado` pelo link (`invitation_decline`, sem conta). `pendente → expirado` com o tempo; `expirado → pendente` ao reenviar. Recusado não se reenvia: convida-se de novo. Eventos: `invitation.sent`, `invitation.declined`.

## Comentários de revisão (W2-06)

`aberto → resolvido → aberto` (resolver/reabrir, `content_comment_resolve`). Cada comentário guarda a versão do guião em que foi feito; depois de uma versão nova aparece como "numa versão anterior". Respostas num nível, herdam o bloco. Eventos: `script.commented`, `script.comment_resolved`, `script.comment_reopened`; notificações `script_mention` e `script_comment`.

## Segurança da conta (W1-15)

Verificação em dois passos: `desligada → a configurar` (`mfa.enroll`, fator por verificar, não bloqueia nada) `→ ligada` (código certo; evento `security.mfa_enabled`) `→ desligada` (`mfa.unenroll` numa sessão aal2; `security.mfa_disabled`). Com ela ligada, cada entrada é `aal1 → aal2` depois do código; em aal1 o servidor recusa tudo. Palavra-passe: mudar (com a atual) ou recuperar pelo link (`security.password_changed`). `security.signed_out_everywhere` antes de terminar todas as sessões.

## Staff da agência (`agency_memberships`, W1-13)

`convidado → ativo` (aceita o convite com o email confirmado; entra sem clientes) · `ativo ⇄ suspenso` (`agency_member_update`, só o dono; suspenso perde logo o acesso a todos os clientes) · papel na agência muda entre membro, gestor e admin; o dono não muda aqui. Atribuir a um cliente (`agency_staff_assign`) e tirar (`member_remove`, tarefas abertas ficam sem responsável ou passam a quem escolheres). Eventos: `agency.invitation.create`, `agency.invitation.revoked`, `agency.member.updated`, `member.assigned`, `member.removed`.

## Layout do Início (`dashboard_layouts`, W1-10)

`por omissão → personalizado` (`dashboard_layout_set`, com `dashboard.configure`) e `personalizado → por omissão` (`dashboard_layout_reset`). Um layout por cliente e função; cada mudança fica no histórico com antes e depois (`dashboard.layout_set`, `dashboard.layout_reset`). Widgets desconhecidos ou repetidos são recusados (22023).

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

## Produção (por conteúdo, W3-02)

`not_started → scheduled → recorded → editing → ready → published` (publicação no W6), `cancelled` a partir de qualquer estado menos publicado. `recording` fica reservado para a sessão aberta.

| De → para | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| not_started ↔ scheduled | `calendar.schedule` | não para rejeitados/arquivados | `production.scheduled` / `production.not_started` |
| not_started/scheduled → recorded | `recording.confirm` | **só com confirmação explícita**; ler 80% gera só a telemetria `recording.viewed_80` (PRD §20); exige aprovado se o cliente o pedir | `recording.confirmed` |
| recorded → not_started | `recording.confirm` | desfazer (take falhado) | `recording.undone` |
| recorded/ready → editing, editing → recorded | `production.update` | — | `production.editing` / `production.recorded` |
| editing → ready | `production.update` | — | `production.ready` |
| * → cancelled, cancelled → not_started | `calendar.schedule` | não publicado | `production.cancelled` / `production.not_started` |
| mudar de dia | `calendar.schedule` | não para o passado (fuso do cliente), até +400 dias, `lock_version` (PT409), não arquivado/cancelado/publicado; `n` passa a ser o seguinte no dia novo | `script.rescheduled` |

`gravado` (legado) = recorded, editing, ready ou published. O teleprompter só transita para o dia seguinte o que está por gravar ou agendado. Por defeito conteúdos `rejected` não entram na fila do teleprompter; o workspace pode exigir `approved` para gravar.

## Sessão de gravação e takes (W2-05)

Sessão (`recording_sessions`): `aberta → fechada`, uma aberta por cliente e dia, partilhada entre dispositivos. Fila (`recording_session_items`): elegíveis do dia + transitados por gravar; ordem, saltar conteúdo e saltar bloco persistem.

| Ação | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| abrir / entrar | `recording.use` | idempotente por cliente e dia; acrescenta novos elegíveis no fim | `recording.session_opened` |
| reordenar / saltar | `recording.use` | só itens da sessão; blocos `hook_N`, `body`, `cta` | auditoria `recording.queue_set` |
| progresso | `recording.use` | retoma; ≥80% uma vez por conteúdo e sessão | `recording.viewed_80` (telemetria, não marca gravado) |
| marcar take | `recording.confirm` | numerado por bloco, ligado à versão lida; idempotente por `client_ref`; não muda estados | `take.recorded` |
| marca de tempo | `recording.use` | abrir, rolar, parar, mudar de bloco, take, "Gravaste?", sair; lote até 200; idempotente por `client_ref`; hora do dispositivo e do servidor; só acrescenta; não muda estados (W5-01, ING-03) | — (linha do tempo em `recording_timeline`) |
| escolher / descartar take | `recording.confirm` | um escolhido por bloco; descartado fica guardado | `take.selected` |
| fechar sessão | `recording.use` | não aceita mais takes; reabrir o dia cria sessão nova | `recording.session_closed` |

## Tarefas (`tasks`, W3-01)

`todo → doing → done`, `* → blocked` (motivo obrigatório) `→ todo/doing`, `* → cancelled` (só `tasks.manage`). Concluir exige dependências fechadas. Tarefas não se apagam; histórico em `task_events` (append-only).

| Ação | Capacidade | Regra | Evento / notificação |
| --- | --- | --- | --- |
| criar | `tasks.manage` | responsável tem de ter `tasks.work` no cliente; idempotente por `client_ref` | `task.created`; notifica o responsável |
| mudar estado / bloquear | `tasks.work` (só o responsável) ou `tasks.manage` | `lock_version` (PT409) | `task.<estado>`; bloqueio e conclusão avisam quem criou |
| reatribuir, prazo, prioridade | `tasks.manage` | idem | notifica o novo e o anterior responsável |
| dependências | `tasks.manage` | mesmo cliente, sem ciclos | histórico |
| comentar / mencionar | `tasks.work` | mencionados têm de ter acesso atual | notifica mencionados e o responsável |

Handoffs (`task_rules`, por cliente): `on_event` cria uma tarefa com `dedup_key = regra:entidade:versão` (repetir não duplica) e `complete_on` fecha-a como `system`. Eventos aceites: `script.created`, `script.submitted`, `script.approved`, `script.rejected`, `review.changes_requested`, `recording.confirmed`, `production.editing`, `production.ready` (W3-02), `request.created`, `source.approved`. Se o responsável da regra perdeu acesso, a tarefa nasce sem responsável e aparece em "Sem responsável".

Caixa de entrada: notificações, tarefas minhas, guiões `in_review` onde posso aprovar e tarefas sem dono; tudo filtrado pelo acesso atual (quem perde acesso deixa de ver). Marcar lido não altera nada.

## Templates e checklist (W3-03)

Template (`task_templates`, por cliente) = até 30 tarefas (título com `{n}`/`{tema}`, tipo, prioridade, dia relativo ao guião, hora no fuso do cliente, responsável opcional, dependências só de itens anteriores) + até 50 itens de checklist. Aplicar a um guião (`tasks.manage`) cria as tarefas com `dedup_key = tpl:template:guião:índice` e a checklist (sem repetidos por guião): repetir não duplica. Responsável que perdeu acesso fica vazio. Clonar para outro cliente exige gerir os dois e nunca leva responsáveis.

Checklist do guião (`content_checklist`): marcar/acrescentar com `production.update`, ler com `scripts.read`; itens não se apagam; fica quem marcou e quando. Carga (`workload`, `tasks.manage`): abertas, em curso, bloqueadas, atrasadas, próximos 7 dias e feitas em 7 dias por pessoa; o limite de WIP (`clients.wip_limit`) só avisa.

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

## Execuções dos agentes (`agent_jobs`, W4-01)

`queued → running → succeeded`; `running → queued` (falha temporária, nova tentativa em `min(60, 2^tentativas)` min, ou lease expirado sem heartbeat); `running → failed` (falha definitiva) ou `dead` (esgotou tentativas, notificação `automation_error` a quem pode correr); `queued|running → cancelled` (em fila cancela já; a correr marca `cancel_requested` e o worker termina); `failed|dead|cancelled → queued` com Repetir (`agent_job_retry`, tentativas a zero).
Uma execução por cliente, tipo e chave de idempotência (por defeito o dia no fuso do cliente). Cada execução fica presa à versão de configuração ativa quando entrou na fila. Não corre sem configuração ativa nem com o limite diário esgotado. Cada tentativa fica em `agent_job_attempts`.

Worker (W4-02): cada guião aprovado pelo Crítico entra em `guioes` como `in_review` (versão 1, `created_kind = engine`, evento `script.created`) no dia alvo da execução; repetir o mesmo slot devolve o mesmo guião. Cancelar pára entre guiões; reinício do alojamento devolve a execução à fila; limite de custo atingido fecha como concluída parcial (`result.parcial`, `result.motivo`). A corrida diária é enfileirada pelo `pg_cron` a cada 5 min (`agent_schedule_tick`).

Dados de pesquisa (W4-03): cada execução lê e escreve só os reels, temas, citações, análises, hooks usados e relatórios do seu cliente (ADR-0016). Dois clientes podem acompanhar o mesmo criador, cada um com a sua cópia, depois da migração contract.

## Configuração dos agentes (`agent_config_versions`, W4-01)

`draft → active → retired`. Versões nunca mudam nem se apagam; guardar cria sempre uma versão nova validada no servidor. Só uma ativa por cliente; ativar uma antiga é o rollback. Versões com erros não se ativam. Evento `agent.config_activated`.

## Revisão de media e publicação

Media: `not_submitted → pending → changes_requested | approved | rejected`.
Publicação (por destino/conta): `draft → scheduled → processing → published` ou `failed | cancelled`; idempotência por `(content_variant_id, social_account_id)`.

## Eventos de domínio (PRD §23)

`source.approved`, `script.submitted`, `script.approved`, `script.rejected`, `script.version_created`, `recording.confirmed`, `recording.session_opened`, `recording.viewed_80`, `take.recorded`, `take.selected`, `task.created`, `task.todo`, `task.doing`, `task.blocked`, `task.done`, `task.cancelled`, `asset.uploaded`, `variant.ready`, `review.changes_requested`, `review.approved`, `publication.scheduled`, `publication.published`, `publication.failed`, `metrics.synced`, `run.started`, `run.step`, `run.failed`, `run.completed`. Publicados por outbox transacional; consumidores idempotentes.

## Mapeamento de hoje (`guioes`)

| Campo atual | Estado PRD |
| --- | --- |
| `status='aprovado'`, `validado=false` | editorial `in_review` (o motor aprovou; falta o Creator) |
| `validado=true` | editorial `approved` |
| `status='rejeitado'` + `motivo_rejeicao` | editorial `rejected` |
| `gravado=true` | produção `recorded` |
| `history` (10 versões de hooks/corpo) | precursor de `content_versions` |


## Estilos de edição e preset (W5-02, VAR-02, EDL-01)

Estilo (`edit_styles`): `rascunho → ativo → rascunho`, qualquer um `→ arquivado → rascunho`. Cada gravação cria uma versão nova em `edit_style_versions` (imutáveis).

| Transição | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| gravar estilo | `styles.manage` | versão esperada tem de ser a atual (40001); layout 1080×1920, texto no retângulo seguro x 60-960, y 210-1600; arquivado não se edita | auditoria `edit.style_saved` (antes/depois) |
| ativar | `styles.manage` | layout com pelo menos uma camada e sem problemas | `edit.style_status` |
| rascunho / arquivar | `styles.manage` | recusado se o preset atual usa o estilo | `edit.style_status` |
| gravar preset | `styles.manage` | 1 a 12 saídas (`master`, `split_image_persona`, `split_attention`, `style`); estilos têm de estar ativos; fixa a versão de cada estilo; versão esperada (40001) | `edit.preset_saved` |


## Metadados do guião e campanhas (W2-07, FR-02-03, FR-03-01)

Campanha (`projects`): `ativa ↔ arquivada`. Arquivar não tira os guiões; só deixa de se poder escolher.

| Ação | Capacidade | Regra | Evento |
| --- | --- | --- | --- |
| criar / mudar campanha | `projects.manage` | nome único no cliente; fim ≥ início | auditoria `project.created` / `project.updated` |
| campanha, responsável, plataformas, etiquetas do guião | `scripts.edit` | campanha ativa do mesmo cliente; responsável com `scripts.edit`; não cria versão | `script.meta_changed`; notificação `script_assigned` |


## Contrato do cliente e custos (W6, BIZ-05/06)

Cada gravação de um contrato cria uma versão nova (v1, v2, …) com "em vigor desde"; as versões não se alteram nem apagam. Estado ativo ou terminado; pagamento em dia, pendente ou vencido. Gravar sobre uma versão antiga: 40001, recarregar. Câmbio EUR→AED escrito à mão, com data e fonte visíveis. Custos: lançado, depois anulado com motivo (uma vez, sem apagar). Auditoria `biz.contract_saved`, `biz.fx_saved`, `biz.cost_saved`, `biz.cost_voided`.

## Desempenho (W6, PERF-03, R-16, R-18)

Leitura do scraper → `perf_capture` (de hora a hora, idempotente) → fotografia por idade (1 h, 24 h, 72 h, 7 d, 30 d; leitura dentro de ±25% da idade, nunca interpolada) → índice pela mediana da mesma conta na mesma idade nos 30 dias anteriores. Publicação importada: origem `externo`, linhagem inferida e marcada; correção manual de origem com motivo e auditoria. Publicador: `perf_record_lineage` (gravada no momento, imutável, idempotente por conta e id externo).

## Caixa e presença (W6, OPS-02/03/04/10, FR-17-01)

Item da fila (um por objeto, notificações juntas): novo → visto (não aprova) → adiado (1 min a 30 dias) → volta a mostrar (hora, "mostrar já" ou notificação nova). Versão nova do guião ou tarefa que volta torna-o novo. Tarefa passada: `task.delegated` com antes/depois, "em curso" volta a "por fazer", notificação `task_delegated` uma vez. Presença: online (sinal ≤ 120 s), ativo (≤ 5 min, só com consentimento), a trabalhar (tarefa iniciada pela pessoa), estado manual com fim opcional. Sem horas nem histórico.
