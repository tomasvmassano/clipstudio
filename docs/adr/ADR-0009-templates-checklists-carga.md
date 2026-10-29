# ADR-0009 — Templates de produção, checklists e carga (W3-03)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD FR-11-04, FR-17-08, FR-17-09, TEAM-08; AGENTS §1, §6.

## Decisão

1. **Templates por cliente** (`task_templates`) com itens em JSON validado no servidor: título, tipo, prioridade, dia relativo ao dia do guião, hora no fuso do cliente, responsável opcional (tem de ter `tasks.work`) e dependências só para itens anteriores, o que impede ciclos. A checklist vai no mesmo template. Não há templates globais: o preset Numeiro é só mais um template desse cliente.
2. **Aplicar** (`template_apply`, `tasks.manage`) cria tarefas normais com `dedup_key = tpl:template:guião:índice` e a checklist com unicidade por guião e texto, por isso repetir é seguro. As tarefas ficam ligadas ao guião, entram nas automações, na caixa de entrada e no calendário.
3. **Clonar** (`template_clone`) exige `tasks.manage` na origem e no destino; nunca copia responsáveis, aplicações nem ligações ao original (FR-17-09: o clone pertence só ao destino).
4. **Checklist** (`content_checklist`) separada das tarefas: itens pequenos que não precisam de dono nem prazo. Marcar e acrescentar com `production.update`; não se apagam; guarda quem marcou e quando.
5. **Carga** (`workload`) calculada a partir das tarefas do cliente, por pessoa. `clients.wip_limit` opcional só sinaliza (FR-17-08: alerta não bloqueia sem política explícita). Só quem gere tarefas vê a carga da equipa.

## Alternativas rejeitadas

- Tabela de itens de template normalizada: o template é editado como um todo e não é consultado por item; JSON validado basta.
- Checklist como tarefas: inundava a caixa de entrada e a carga com micro-itens.

## Pendentes

Estimativas e disponibilidade por pessoa, equipas funcionais (TEAM-08), redistribuição em lote (FR-17-07), templates de campanha/série.

## Rollback

Bloco no fim de `20261029081024_w3_templates_checklists_workload.sql`.
