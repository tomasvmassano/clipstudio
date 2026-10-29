# ADR-0011 — Worker do motor ligado à fila (W4-02)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD FR-06-03, FR-06-05 (parcial), FR-06-06 (parcial); AGENTS §2.7, §2.8, §7, §9.

## Decisão

1. **O motor é um worker, não um script manual.** `python run.py worker` (repositório privado `numeiro-engine`) pede trabalho com `worker_claim`, mantém a lease com `worker_heartbeat` a cada 30 s e depois de cada guião, e fecha com `worker_finish`. A configuração usada é a versão fixada na execução; `clients/<cliente>.yaml` só completa o que a app ainda não guarda (fontes de scraping, cenários, handle).
2. **Guiões entram pela base, em revisão.** `worker_save_script` valida o que o motor manda (hooks, corpo, tamanhos), cria o guião no workspace da execução, no dia alvo (`pipeline.target_day_offset`: 0 o próprio dia, 1 o seguinte, por defeito 1 porque o preset Numeiro corre às 18:00 para amanhã) e com o número a seguir ao último desse dia. Fica `in_review` com versão 1, transição e evento `script.created` criados pelos triggers existentes, por isso as automações de tarefas funcionam igual. Nunca fica aprovado nem gravado sozinho.
3. **Idempotência por (execução, slot)** em `agent_job_outputs`. O worker numera os guiões gravados por ordem; numa nova tentativa continua a partir de `progress.guardados` e, se um slot já existir (caiu antes do heartbeat), salta para o seguinte sem sobrescrever.
4. **Utilizador próprio na base (`engine_worker`)**, criado sem login: o dono define a password no Supabase. Pode chamar as quatro funções do worker e ler/escrever só as tabelas de pesquisa do motor (reels, temas, citações, ideias, generated, agent_log, meta, relatórios). Não lê guiões, membros, a fila nem configurações.
5. **Agenda no Supabase** (`pg_cron`, a cada 5 min: `agent_schedule_tick`). A corrida diária entra na fila mesmo com o worker a reiniciar.
6. **Custos.** Os preços ficam em `agent_models` (EUR por milhão de tokens, vazios por defeito). O worker conta tokens por chamada (`agent_log.tokens_in/out`, `cost_eur`) e por execução. Sem preço, o custo fica desconhecido (vazio, nunca 0). Com limite diário e modelos sem preço, a execução recusa correr (falha definitiva com mensagem), porque não conseguiria respeitar o limite. Ao atingir o limite a meio, pára entre guiões e fecha como concluída parcial. Custos e tokens nunca vão no progresso, que é visível a quem só tem `agents.read`.
7. **Paragens.** Cancelar na app pára entre guiões (fecha como cancelada). SIGTERM do alojamento devolve a execução à fila. Lease perdida: o worker pára sem reportar. Chave ou pedido inválido não repete; rede, API e base repetem com espera crescente.

## Alternativas rejeitadas

- Worker por HTTPS com a chave `service_role`: a chave dá acesso total; um utilizador Postgres com o mínimo limita o estrago se a credencial vazar.
- Motor a escrever direto em `guioes`: saltava a validação e a numeração, e o worker teria de poder ler guiões de todos os clientes.
- Agendar no worker: se o worker estiver em baixo à hora, a corrida perde-se sem rasto.
- Preços fixos no código: mudam e não são nossos para inventar; ficam como dado editável.

## Limitações conhecidas

As tabelas de pesquisa do motor não têm `client_id` (reels, temas, citações, generated, meta). Enquanto não tiverem, o worker só aceita clientes com ficheiro base (hoje só o Numeiro) e falha de vez para os outros. Isolar estas tabelas é obrigatório antes do segundo cliente (tarefa própria, com migração expand/contract). Preços dos modelos por preencher. Alojamento e credenciais por configurar: integração real worker ↔ Postgres **UNVERIFIED** até ao primeiro deploy (aqui testada por SQL como `engine_worker` e em mock).

## Rollback

Blocos no fim de `20261029092137_w4_engine_worker.sql`, `20261029093332_w4_worker_finish_cost_unknown.sql` e `20261029093455_w4_worker_search_path.sql`. Parar o worker basta para voltar ao estado de W4-01.
