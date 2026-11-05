# ADR-0061 — Notificações de prazos e alterações (W10-14)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD FR-11-04, TEAM-12; FR-15-05, FR-16-03, FR-17-06; AGENTS §5, §6, §10. (Número escolhido acima dos ADR-0054..0060 usados em PRs abertos; renumerar se colidir no merge.)

## Decisão

1. **Um tick SQL de 15 em 15 minutos** (`deadline_notify_tick`, pg_cron `deadline-notify-tick`, o mesmo padrão de `agent-schedule-tick`) trata os avisos que dependem do relógio: tarefa com prazo nas próximas 24 h (`task_due_soon`), tarefa atrasada (`task_overdue`), guião por aprovar com gravação amanhã no fuso do cliente (`script_unapproved_recording`) e revisão de vídeo atrasada (`video_review_overdue`, a regra do calendário W9-03: tarefa de revisão/edição aberta com prazo mais cedo, senão o dia do guião). Não precisa de worker: são consultas pequenas e indexadas, e o pg_cron já está na plataforma.
2. **Uma vez por limiar e por valor do prazo.** A chave inclui o `due_at` (epoch), a data do guião ou o dia do prazo da revisão: mudar o prazo volta a armar o aviso; repetir o tick não. Cada envio fica em `notification_deadline_sent (user_id, dedup_key)` **antes** de chamar `_notify`, incluindo os suprimidos por preferência (`delivered=false`). Sem este registo, `_notify` contaria a mesma supressão de novo cada vez que dois avisos suprimidos da mesma pessoa alternassem (o contador só ignora a última chave). Ticks sobrepostos: lock consultivo.
3. **Mudança de prazo por trigger** (`tasks_due_changed_notify`, depois de mudar `due_at`): apanha todos os caminhos (RPC, calendário, futuros) sem tocar em `task_update`. Avisa o responsável; quem muda não se avisa (`_notify`); se o responsável muda no mesmo passo, o aviso de atribuição já existente basta. Mudança de responsável continua como estava (`task_assigned` ao novo, `task_unassigned` ao antigo em `task_update`, `task_delegate` e remoção de membro).
4. **Quem recebe decide-se no envio**, com capacidades existentes (sem capacidade nova): `tasks.read` sempre (acesso atual, R-11, TEAM-12), mais `scripts.read`/`scripts.approve` nos guiões e `media.read`/`review.approve` + flag `media.library` nas revisões. Membros de `workspace_access` ativos apenas (o mesmo critério de `automation_error`); nunca alguém de outro cliente.
5. **Flag `notifications.deadlines`** (fase owner), verificada para quem recebe (`_flag_on_for`). Nenhum tipo novo é obrigatório; o cliente pode torná-los obrigatórios nas Definições.
6. **Janelas limitadas**: atrasos só até 7 dias para trás, para não despejar avisos antigos ao ligar a flag (o atraso continua visível na caixa pelo motivo `overdue`). Registo limpo ao fim de 45 dias.
7. **Catálogo e UI**: grupo novo "Prazos" nas preferências (check do grupo alargado a partir da definição atual, como o de `notifications.kind`); na caixa os avisos de prazo são "Alerta" e a mudança de prazo é "Tarefa" (`_ops_category` alterada por substituição na definição atual).

## Alternativas rejeitadas

- Worker Node/Python com fila: mais uma peça para operar por consultas que cabem num tick SQL.
- Usar só `_notify` sem registo próprio: idempotente para as notificações criadas, mas inflaciona o contador de supressões.
- Mexer em `task_update` para o aviso de prazo: não cobria outros caminhos de escrita.
- Avisar todos os atrasos históricos: ruído no primeiro tick depois de ligar.

## Riscos

- Outra migração que reescreva `_ops_category` inteira (ex.: W10-01 saúde) apaga a linha dos tipos de prazo se for aplicada depois: o efeito é só a caixa mostrar "Aviso" em vez de "Alerta" nas notificações sem objeto vivo; quem fizer o merge em segundo tem de juntar as duas linhas.
- Staff com acesso global (dono da agência sem linha em `workspace_access`) não recebe avisos de aprovação/revisão, como nos erros de automação.

## Rollback

Bloco no fim de `PENDING_w10_prazos.sql` (unschedule, drop trigger/funções/tabela, apagar tipos e repor os checks a partir da definição atual). A app não depende de nada novo: os tipos desconhecidos caem em "Outras"/"Aviso".
