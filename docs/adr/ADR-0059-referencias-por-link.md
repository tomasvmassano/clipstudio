# ADR-0059 — Referências por link: colar, dissecar e 3 guiões em via rápida (W10-04)

**Data:** 2026-11-06 · **Estado:** proposto (pode ser renumerado no merge) · **Requisitos:** PRD §45 REF-01, REF-02, REF-03, REF-04 (CHG-005), R-20, R-17, FR-07-01, FR-07-04; AGENTS §7, §8, §15.

## Decisão

1. **Identidade do vídeo, não do link.** `reel_ref_key(url)` dá `instagram:<shortcode>` (reel, reels, p, tv, com ou sem utilizador; o shortcode distingue maiúsculas) ou `tiktok:<id>` (video, photo, /v/, embed). `reference_items.ref_key` tem índice único parcial por cliente. As linhas antigas são preenchidas da mais antiga para a mais recente e um repetido que já existisse fica com `ref_key` nulo (nada se apaga; o índice nunca rebenta). O `ref_key` só se calcula ao criar. Links curtos do TikTok (vm./vt.) só se resolvem com rede: entram sem `ref_key` e repetem pelo link normalizado.
2. **Colar não falha por repetido.** `reference_paste` devolve `{created, duplicate, reference}`: o mesmo vídeo noutro formato de link abre o que já existe (também no arquivo). Só aceita Reel ou TikTok (`link_nao_suportado`); "Adicionar por link" continua para outros links. Se o scraper já recolheu esse reel para o cliente, a referência fica ligada a ele (métricas com data de recolha). `reference_create` passa a detetar repetidos também pelo `ref_key`.
3. **Dois tipos de execução novos** em `agent_jobs`: `reference_analysis` e `reference_scripts`. Não se reutilizou `analysis` porque esse tipo é um lote sobre os reels dos criadores seguidos (`reels_needing_analysis`) e precisa do ficheiro base do cliente; estes têm contrato por referência, gravação própria e só precisam da configuração da app. O worker em produção pede os tipos pelo nome, por isso não os apanha até ser atualizado: os pedidos ficam em fila, visíveis, e a UI diz "o motor ainda não aceita este tipo de pedido" (`worker_ready`, a partir de `agent_workers.kinds`). Uma execução ativa por referência e tipo (pedir outra vez devolve a mesma); orçamento diário e configuração ativa como nas outras execuções (`_agent_enqueue`).
4. **Recolha (R-20).** O motor usa o mesmo mecanismo do Scout (Apify) para a transcrição, legenda e métricas públicas, como decidido em CHG-005. Ordem: transcrição colada à mão > reel já recolhido pelo scraper > recolha agora. Sem token do fornecedor, ou sem transcrição na recolha (TikTok), a execução falha sem repetir, com uma mensagem PT-PT que manda colar a transcrição; o caminho manual (`reference_analyze(p_transcript)`) funciona sempre. Métricas são "quando disponíveis": falhar a recolha de números não impede a dissecção com transcrição.
5. **Dissecção versionada e imutável.** `reference_analyses` (uma versão por execução, trigger recusa update/delete) guarda transcrição e origem (scraper/manual), métricas, dissecção, número de afirmações sobre terceiros, modelo, versão dos prompts (`ref-2026-11-06.1`) e do agente (`ref_dissector@1`) e tokens (AGENTS §7). O servidor limpa o payload (só chaves conhecidas, máquina numa das 5 + "outra", estrutura 1..30 partes) e **calcula o índice** face à mediana das views do autor nos reels recolhidos para o cliente (mínimo 5), ignorando o que o motor mande. A classificação vazia da referência (hook, duração, criador, idioma) é completada, nunca sobrescrita.
6. **3 guiões, 3 hooks cada (REF-03).** O motor escreve na voz do cliente com a configuração ativa, frases-persona (R-17, via `worker_claim.persona`), 5 guiões aprovados recentes e os 3 vídeos próprios que mais renderam. Semelhança medida em código (fração dos 5-gramas do guião presentes na transcrição; limite [pressuposto] 0,12 configurável) e frases de 8 palavras copiadas bloqueadas, com até 2 revisões só dos que faltam; o servidor recusa acima de 0,25 e sem medida (segunda linha). Afirmações sem fonte vão para as notas como "por verificar".
7. **Via rápida (REF-04, parcial).** Os guiões entram em revisão (nunca aprovados), no dia de hoje do cliente, `origem = 'via_rapida'`, etiqueta "via rápida", notas com a referência e a versão da dissecção, ligados em `reference_links` (added_kind engine) e `reference_script_outputs` (linhagem referência → dissecção → guião, R-18/REF-09). Badge "via rápida" no cartão do guião. Topo da fila do teleprompter e modo rápido pelo telemóvel ficam por fazer.
8. **Capacidades e flag.** `references.analyze` e `references.adapt` (risco M, gastam orçamento de IA; owner, admin e manager do cliente). Colar usa `references.manage`. Flag `references.link` na fase "equipa da agência" (CAP-09): com a flag desligada as RPCs recusam com `funcionalidade_desligada` (55000) mesmo com a capacidade. Código de equipa: nada disto.

## Alternativas rejeitadas

- Guardar a dissecção em colunas de `reference_items`: perdia versões e a proveniência por execução.
- Reaproveitar `script_analysis`: é por reel recolhido e não guarda transcrição, modelo nem versão do prompt.
- Gravar os guiões com `worker_save_script`: usa o dia alvo do pipeline diário, não aceita a marcação nem a ligação à referência; alterá-lo mexia no contrato do worker atual.
- Colunas novas em `guioes` para a via rápida: `origem` (texto livre, sem uso em regras) e a etiqueta chegam, sem mexer nos snapshots de versões.
- Resolver links curtos do TikTok na base (precisa de rede) ou no browser (CORS, e o browser não é autoridade).

## Consequências

- Para funcionar em produção é preciso: aplicar a migração, fazer deploy do worker atualizado (numeiro-engine, `apify-client` nas dependências do worker) e configurar `APIFY_TOKEN` no alojamento do worker (não verificado). Sem o token, só o caminho manual.
- O espaço da agência ainda não tem biblioteca de referências/estilos (REF-07 depende de VAR-02/EDL-01); o campo de colar existe só no espaço do cliente (Referências).

## Rollback

Bloco no fim de `20261106060744_w10_referencias_link.sql` (compatível primeiro; contract das tabelas, coluna e índice depois). O worker antigo ignora os tipos novos; o novo sem a migração não encontra execuções desses tipos e continua a correr as outras.
