# ADR-0072 — Notificação agrupada dos pacotes por guião (W10-23)

**Data:** 2026-11-09 · **Estado:** proposto (PR por aprovar) · **Requisitos:** PRD STU-03; FR-15-05 (notificações por evento); ADR-0070 (pacote por guião), ADR-0040 (preferências de notificações), ADR-0048 (pacote da sessão); AGENTS §2.8, §5, §6.

## Contexto

Com o pacote por guião (ADR-0070, flag `edit.package_script` ligada no Numeiro) uma sessão de ~30 guiões gera até 30 jobs `package`. O trigger `_media_package_done` (W5-09) cria uma notificação "Pacote de edição pronto: N vídeos para rever" por job: 30 notificações por sessão na caixa de quem pediu (ou de quem ligou o automático). Decisão do responsável de produto, 2026-11-09: no pacote por guião as notificações são **agrupadas**, não uma por guião.

## Decisão

1. **Lote** (`package_script_batches`, fechada): uma linha por cliente, pessoa a notificar e lote de gravação. O lote é a sessão do teleprompter das gravações ligadas ao guião (`recording_clips.session_id`, preferindo a câmara do lado) quando se sabe (`session:<uuid>`); senão o dia local do cliente (fuso de `clients.timezone`) em que o job foi pedido (`day:AAAA-MM-DD`).
2. **Itens por guião, não por job** (`package_script_batch_items`, fechada; `job_id` único): o job de pacote por guião entra no lote quando é criado (trigger AFTER INSERT em `media_jobs`). Voltar a pedir um guião (falhou, ou estilo novo) substitui o item desse guião e volta a pô-lo "a preparar": o total não cresce e o job antigo deixa de contar.
3. **Contagem idempotente:** trigger AFTER UPDATE OF status. `done` = pronto; `failed`/`dead` = falhou; `cancelled` sai das contas. O item só muda se o resultado mudar (`outcome is distinct from`): repetições do mesmo estado, retries e o job antigo de um guião pedido de novo não contam duas vezes. Advisory lock de transação por lote (e por pessoa + chave na criação) para jobs que acabam ao mesmo tempo.
4. **Uma notificação por lote** (`dedup_key = 'package_script_batch:<id>'`, `kind = 'video_decision'` como hoje, `entity_type = 'package_script_batch'`): criada quando o primeiro job acaba (nunca "0 de 12"), atualizada a cada mudança de contagem: título "Pacotes por guião prontos: 7 de 12" (", 1 falhou" se já houver falhas), de novo **por ler** e de volta ao topo da caixa (`created_at = now()`; a caixa ordena por essa coluna). Estado final quando todos acabaram: "Pacotes por guião prontos: 12 de 12" ou "Pacotes por guião terminados: 9 de 12 prontos, 3 falharam", com os guiões falhados nomeados no corpo ("Falharam: guião 4, guião 7, guião 9"). A mesma contagem não volta a pôr por ler.
5. **Destinatários iguais aos de hoje:** quem pediu o job (`created_by`; no automático é quem ligou as definições). A criação passa por `_notify` (acesso atual com `tasks.read`, preferências do cliente e da pessoa, silêncio, nunca a própria pessoa que age); a atualização aplica a mesma regra antes de mexer na linha. Sem `created_by` não há lote nem notificação, como hoje.
6. **Eventos:** `domain_events` `package_script.batch_progress` a cada mudança de contagem; `audit_events` `edit.package_script_batch_done` no estado final.
7. `_media_package_done` (corpo atual de `20261105192728_w5_edit_package.sql`) passa a ignorar os jobs com `mode = 'script'`. Pacote da sessão: exatamente como hoje.
8. **App:** a caixa mostra título e corpo tal como vêm; `notifPath('package_script_batch')` leva a `/edicao-automatica`.

Os triggers nunca falham a transação do worker ou do pedido (exceção registada com `raise log`).

## Alternativas rejeitadas

- **Resumo por tempo (digest às N horas):** atrasa o aviso dos primeiros vídeos prontos, que é o objetivo do STU-03 (rever minutos depois de cada "Sim").
- **Notificação nova a cada mudança, apagando a anterior:** perde o estado de lido/por ler e cria ruído nos ids; atualizar a mesma linha é mais simples e idempotente.
- **Coluna `updated_at` em `notifications` e ordenar a caixa por ela:** obrigava a reescrever `inbox()` e a fila de operações; mexer em `created_at` desta linha dá o mesmo efeito sem mudar contratos. Contrapartida: `created_at` desta notificação é "última atualização", não "criação" (a criação fica em `package_script_batches.created_at`).
- **Lote por job do agente ou por pedido "Criar pacote" manual:** o pedido manual é um guião de cada vez; só a sessão (ou o dia) agrupa o que a equipa sente como "a gravação de hoje".
- **Contar por job:** voltar a pedir um guião falhado faria "13 de 12".

## Consequências

- Uma notificação por sessão em vez de ~30. A fila de operações (`ops_queue`) ainda leva estas notificações (e as `media_job` de hoje) ao início; fica como lacuna conhecida.
- Jobs por guião criados antes desta migração não têm item: se acabarem depois, não notificam (nem pelo caminho antigo). Janela curta; aceitável.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_notif_agrupada.sql`: tirar os dois triggers, repor `_media_package_done` de 20261105192728, apagar as funções; contract posterior apaga as duas tabelas. As notificações já criadas ficam na caixa.
