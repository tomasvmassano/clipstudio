# ADR-0010 — Agentes: catálogo, configuração versionada e execuções duráveis (W4-01)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M06, FR-06 (parcial), NFR de durabilidade; AGENTS §2.8, §7.

## Decisão

1. **Catálogo global, configuração por cliente.** `agent_definitions` descreve os 13 agentes do motor (etapa, modelo por defeito, ferramentas, o que lê e escreve) e `agent_models` os modelos permitidos. Tudo o que é do cliente (voz, léxico, regras, formatos, pipeline, modelos, agenda, limite de custo, notícias, leituras) vive em `agent_config_versions`. Os 30 guiões, 8 hooks e 18:00 Dubai são só a versão 1 do cliente Numeiro, carregada por SQL e não pela migração (o repositório é público e a voz é dado privado do cliente).
2. **Versões imutáveis.** Guardar cria sempre uma versão nova, validada por `agent_config_validate` (chaves conhecidas, soma de proporções, limites numéricos, modelos do catálogo). Um trigger impede alterar conteúdo ou apagar. Uma ativa por cliente (índice único parcial); ativar retira a anterior. Ativar uma antiga é o rollback. Versões com erros não se ativam.
3. **Execuções na base, não no pedido HTTP.** `agent_jobs` é a fila: chave de idempotência única por cliente e tipo (por defeito o dia local), lease com heartbeat, tentativas com espera `min(60, 2^n)` min, `dead` com notificação `automation_error`, cancelamento cooperativo, Repetir. Cada execução fica presa à versão de configuração ativa no momento em que entrou na fila. O limite de custo diário bloqueia novas execuções.
4. **Worker com credencial de servidor.** `worker_claim` (`for update skip locked`), `worker_heartbeat`, `worker_finish` e `agent_schedule_tick` só têm grant a `service_role`. A app nunca marca uma execução como concluída.
5. **Custos escondidos por defeito.** `agent_jobs` não tem select direto; `agents_overview` omite custo, tokens, gasto e limite sem `costs.read`.

## Alternativas rejeitadas

- Fila externa (Redis, SQS, Inngest): mais uma peça a operar para um volume de poucas execuções por dia; a fila em Postgres dá transação com os guiões e RLS.
- Editar a configuração no lugar com histórico à parte: perde-se a ligação exata execução ↔ configuração e o rollback fica manual.
- Configuração em YAML no motor: não é por cliente, não tem permissões nem auditoria.

## Pendentes

W4-02: o motor passa a ler a versão da execução, a reclamar jobs e a reportar progresso, custo e erros; hospedagem e chave da API por decidir (UNVERIFIED). `agent_schedule_tick` precisa de um cron (pg_cron ou o worker). Sem worker ligado, as execuções ficam em fila e a página diz isso.

## Rollback

Bloco no fim de `20261029084441_w4_agents_config_jobs.sql`. A página `/agentes/configuracao` sai com o revert do PR.
