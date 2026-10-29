# ADR-0017 — Início por cliente e painel da agência (W1-10)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD FR-01-01, FR-01-02, FR-01-06 (parcial), R-04, AGENTS §15.

## Decisão

1. **Registo de widgets na base** (`dashboard_widgets`): chave estável, tipo (número, gráfico, painel), nome, explicação da métrica e as capacidades de que precisa. A app desenha o que o servidor manda; nenhum widget aparece sem as capacidades dele, mesmo que esteja no layout.
2. **Layout por cliente e por função** (`dashboard_layouts`), com valores por omissão por função no código da base (`_dashboard_default`). Muda-se com a capacidade nova `dashboard.configure` (dono e admin do cliente), com validação no servidor e auditoria (`dashboard.layout_set`, `dashboard.layout_reset`). O dono da agência sem papel no cliente vê o layout de dono; o código de equipa antigo, o de colaborador.
3. **KPIs por período** (`dashboard_get`): fontes, guiões criados, à espera de aprovação (fotografia de agora, sem comparação), aprovados, gravados, publicados, views, engagement, custo dos agentes e tarefas concluídas. Cada um comparado com o período anterior do mesmo tamanho, no fuso do cliente. Período até um ano. Sem base comparável não se mostra variação.
4. **Painel da agência** (`agency_dashboard`, capacidade nova `dashboard.agency` para a equipa da agência): só clientes ativos a que a pessoa tem acesso (o dono vê todos). Cada número de cada cliente exige a capacidade nesse cliente; os totais dizem quantos clientes ficaram de fora de cada número. Engagement total é ponderado pelas views. A equipa de um cliente nunca o vê.
5. **Meta do dia** sai da configuração ativa dos agentes (`pipeline.scripts_per_day`), não do código (antes estava fixa em 30, preset do Numeiro).
6. O período escolhido fica guardado no browser de cada pessoa (conveniência; se falhar, volta aos 30 dias).

## Alternativas rejeitadas

- **Layout por pessoa:** pedido no PRD é por função e por cliente; por pessoa fica para depois (FR-01-06 fala em filtros persistentes por utilizador, já cobertos pelo período).
- **Widgets só no código da app:** perdia-se a verificação no servidor e o registo de capacidades (AGENTS §15).

## Pendentes

Publicados conta só o que for marcado como publicado até haver publicação ligada (W6). Custos por cliente na agência só com `costs.read` em cada cliente. Exportar o painel, alertas e gráficos por período (os gráficos continuam em janelas fixas: 60 dias, 10 dias, semanas).

## Rollback

Comentário no fim de `20261029114823_w1_dashboard.sql`.
