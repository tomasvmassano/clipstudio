# ADR-0007 — Tarefas, handoffs e caixa de entrada (W3-01)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD TEAM-05, TEAM-06, TEAM-12, TEAM-15, FR-11-02, FR-17-01, FR-17-02, FR-17-05; AGENTS §5, §6, §15.

## Contexto

Não havia forma de dizer quem faz o quê. As transições de guião já escrevem eventos num outbox (`domain_events`) sem consumidores.

## Decisão

1. **`tasks` por cliente**, com tipo, estado (`todo`, `doing`, `blocked`, `done`, `cancelled`), prioridade, prazo (UTC, mostrado no fuso do cliente), responsável, motivo de bloqueio obrigatório, ligação opcional a guião ou fonte do mesmo cliente, `lock_version` e `client_ref` para criação idempotente. Não se apagam.
2. **Histórico e comentários append-only** (`task_events`, `task_comments`). Dependências em `task_dependencies`, no mesmo cliente e sem ciclos; concluir exige dependências fechadas.
3. **Permissões**: `tasks.read` lê; `tasks.manage` cria, atribui e configura; **`tasks.work`** (nova) deixa o responsável mudar o estado das suas tarefas e qualquer membro com ela comentar. O âmbito `own` é verificado no servidor (responsável = utilizador). Só se atribui ou menciona quem tem acesso atual.
4. **Handoffs** (`task_rules`, sempre por cliente): um trigger em `domain_events` cria tarefas para os eventos de uma lista fechada e fecha as abertas quando chega um evento de `complete_on`. Idempotente por `dedup_key = regra:entidade:versão`. Corre na mesma transação do evento, por isso não há tarefas perdidas nem duplicadas; não concede permissões nem publica nada.
5. **Notificações pessoais** (`notifications`), deduplicadas por `(user_id, dedup_key)`, criadas só para quem tem acesso no momento. A leitura volta a filtrar pelo acesso atual, por isso quem é suspenso deixa de as ver (TEAM-12). Quem age não se notifica.
6. **Caixa de entrada** = notificações + tarefas minhas + guiões em revisão onde posso aprovar + tarefas sem dono (para quem gere), em todos os clientes autorizados. As aprovações são calculadas, não notificadas, para não multiplicar avisos.
7. O código de equipa só lê tarefas: não tem identidade para ser responsável nem caixa de entrada.

## Alternativas rejeitadas

- Worker assíncrono a consumir o outbox: mais robusto para efeitos externos, mas para criar linhas na mesma base o trigger dá atomicidade e idempotência sem infraestrutura nova. Fica para o W4 quando houver efeitos externos (email, push).
- Notificar todos os aprovadores a cada submissão: ruído; a caixa calcula a fila de aprovação.
- Regras globais com o preset Numeiro: proibido pelo AGENTS §1; cada cliente configura as suas.

## Pendentes

Lembretes de prazo e escalonamento por SLA (precisam de agendador), templates e checklists (FR-11-04, FR-17-09), carga por pessoa (TEAM-08, FR-17-08), projetos e campanhas, reatribuição pedida ao remover um membro (TEAM-15), email/push.

## Rollback

Bloco no fim de `20261029071504_w3_tasks_handoffs_inbox.sql`. O trigger `domain_events_handoff` sai primeiro; o código em `main` antes deste PR não usa estas tabelas.
