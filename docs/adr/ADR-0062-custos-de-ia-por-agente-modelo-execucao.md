# ADR-0062 — Custos de IA por agente, modelo, execução e cliente (W10-10)

**Data:** 2026-11-06 · **Estado:** aceite (com decisão de produto pendente, ver fim) · **Requisitos:** PRD M10 FR-10-01; FR-10-06 (só rótulo); §2 (espaço da agência), §3 (custos globais vs do próprio cliente), CAP-04, BIZ-04; AGENTS §9, §15.

## Decisão

1. **Uma RPC, dois espaços.** `costs_ai_usage(p_ws, p_days, p_from, p_to, p_token)`. Com `p_ws` é a vista do cliente (`/c/<cliente>/custos`, aba Consumo de IA): `costs.read` nesse cliente e a flag `costs.content`. Com `p_ws` nulo é a vista da agência (`/custos`): `costs.read_agency` na organização (por defeito só o dono da agência, PRD §3) e a flag nova `costs.agency`; a resposta só leva os clientes ativos em que a pessoa também tem `costs.read`, por isso uma negação explícita num cliente tira-o da vista. A equipa do cliente e o código de equipa nunca entram na vista da agência (R-13); o código de equipa nunca lê custos (`legacy_can` não inclui `costs.*`).
2. **Fontes reais, sem misturar.** Custo e contagem por execução vêm de `agent_jobs` terminadas no período (custo nulo = desconhecido, contado à parte, nunca zero; execuções em curso não entram). Por agente e por modelo vêm das chamadas em `agent_log` (sem ensaios `simulated`, só linhas com custo ou tokens). As duas somas podem diferir (pesquisas web contam na execução; o motor antigo registava chamadas sem execução na fila) e a UI diz isso ao lado da tabela.
3. **Período e tendência.** 7, 30 ou 90 dias até hoje, ou personalizado (até 366 dias), em dias do fuso do cliente (vista do cliente) ou do perfil da pessoa (vista da agência, um só fuso para somar clientes). O período anterior tem o mesmo tamanho. Sem atividade no anterior não se mostra percentagem.
4. **Estimado, rotulado.** O motor calcula o custo pelos tokens e pela tabela de preços pública (`agent_models`, `agent_tool_prices`), em EUR ao câmbio guardado com o preço. Não há custo confirmado por fatura nem câmbio guardado por execução: a resposta traz `basis.kind = estimated`, `confirmed_available = false`, a nota e os preços usados. FR-10-06 continua por fazer.
5. **Moeda.** Valores em EUR; AED só com a taxa EUR→AED mais recente da agência (`fx_rates`, BIZ-05), com taxa e data à vista; sem taxa fica em EUR e a UI diz porquê.
6. **Exportar com capacidade própria.** `costs.export` (nova, ws, risco M; CAP-04 separa ler de exportar), dada aos mesmos papéis que já têm `costs.read` (workspace_owner, workspace_admin), que já exportavam por `content_costs_export`: não alarga ninguém. `costs_ai_usage_export(p_table, …)` devolve o mesmo relatório para o browser montar o CSV da tabela visível e audita `costs.ai_exported` (tabela, período, número de clientes e de linhas). Na vista da agência exige `costs.export` em **todos** os clientes da resposta; falta um, recusa inteira (fail closed).
7. **Sem dados pessoais nas execuções.** As execuções saem sem `requested_label` (pode ser o email de alguém da agência).

## Alternativas rejeitadas

- Juntar agência e cliente numa só capacidade: o PRD §3 separa custos globais da agência (Owner; Admin se delegado) dos custos do próprio cliente ("se autorizado").
- Somar o `agent_log` como total: perde as ferramentas pagas por uso e as execuções sem chamadas registadas; o total oficial é o das execuções.
- Exportar só os clientes com `costs.export` na vista da agência: o CSV deixava de ser a tabela visível sem o dizer.
- Converter para AED com uma taxa fixa no código: inventava um valor; só a taxa registada pela agência, com data.
- Gráfico diário: fica para FR-10-05/BIZ; a tendência é número contra o período anterior, por cliente, agente e modelo.

## Decisão de produto pendente

O `workspace_admin` e o `workspace_owner` de um cliente (equipa do cliente, `client_staff`) têm `costs.read` por defeito desde W1 e veem o cartão "Custo dos agentes" no Início e, com a flag `costs.content`, esta página. O PRD §3 permite ("Consultar custos do próprio workspace: Client Admin, se autorizado"), mas AGENTS §9 pede para evitar mostrar dados de custo confidenciais à equipa do cliente. Este trabalho **não muda grants**. Proposta para o owner: retirar `costs.read` e `costs.export` dos papéis `workspace_owner`/`workspace_admin` quando a pessoa é `client_staff` (ou retirar dos papéis e deixar só por exceção individual na consola), por uma migração própria com teste de que a equipa do cliente deixa de ver custos e a da agência continua a ver.

## Rollback

Bloco no fim de `20261106064815_w10_custos.sql` (funções, índice, flag `costs.agency`, capacidade `costs.export` e o texto anterior da flag `costs.content`). A app sem as funções mostra o erro com "Tentar de novo" na aba; a aba "Por guião e publicação" continua igual.
