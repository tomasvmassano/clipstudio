# ADR-0016 — Dados de pesquisa do motor por cliente (W4-03)

**Data:** 2026-10-29 · **Estado:** aceite (fase expand) · **Requisitos:** PRD R-02, AGENTS §2.2 e §5, SCALE-07 (parcial).

## Contexto

As tabelas de pesquisa do motor (`reels`, `themes`, `reel_themes`, `quotes`, `meta`, `generated`, `script_analysis`, `comment_analysis`, `daily_reports`) eram globais. Funcionava com um só cliente, mas um segundo cliente partilharia temas, citações, análises e o histórico de hooks do Numeiro. O worker (ADR-0011) recusava clientes sem `clients/<id>.yaml` por causa disto.

Decisão de produto (Tomás, 29/10): **tudo por cliente**. Cada cliente tem a sua cópia de reels, análises, temas, citações e guiões gerados, mesmo que dois clientes acompanhem o mesmo criador de referência.

## Decisão

1. **Expand (este PR).** `client_id` nas 9 tabelas, preenchido com os dados atuais (todos do Numeiro: 388 reels, 15 temas, 28 citações, 103 análises), e índices únicos por cliente: `(client_id, id)` nos reels, `(client_id, tema)`, `(client_id, texto_pt)`, `(client_id, k)`, `(client_id, reel_id)` nas análises, `(client_id, reel_id, theme_id)`.
2. **Motor sempre num cliente.** `PgDB` exige o cliente da execução, filtra todas as leituras e escritas por ele, usa os índices por cliente nos `on conflict` e grava o cliente na sessão (`engine.client_id`). O CLI passa `--client`.
3. **Compatibilidade.** Um trigger (`_engine_fill_client`, security definer) preenche o cliente quando o código antigo não o manda: pelo reel, pela conta, ou `numeiro` (o único cliente que esse código servia). Liga também os reels novos à conta do cliente pelo handle e plataforma, que antes ficavam sem `account_id` e fora do Desempenho.
4. **Funções da app.** `_reference_row`, `reference_create`, `references_discover` e o trigger das referências passam a exigir que o reel e a análise sejam do mesmo cliente, além da conta.
5. **Até ao contract**, as chaves globais continuam: o mesmo reel, tema, citação ou chave de meta em dois clientes dá erro (23505) em vez de misturar dados.

## Contract (PR seguinte, depois do motor novo no main)

Chaves passam a `(client_id, …)`, `client_id` obrigatório sem valor por omissão, saem `reels_pkey`, `themes_tema_key`, `quotes_texto_pt_key`, `meta_pkey` e as chaves por `reel_id`; FKs para reels passam a compostas; sai o fallback `numeiro` do trigger; política do `engine_worker` passa de `true` a `client_id = current_setting('engine.client_id')`; saem os grants de leitura antigos de anon/authenticated nestas tabelas (hoje sem efeito: RLS sem política dá 0 linhas). O teste `test_contract_mesmos_ids_em_dois_clientes` do motor já corre o código contra essa forma.

## Alternativas rejeitadas

- **Reels partilhados, análises por cliente:** poupava scraping, mas as métricas e a análise de um criador dependem do ângulo de cada cliente e o produto pediu isolamento total.
- **Schema por cliente:** isolamento forte, mas multiplica migrações e funções por cliente.

## Pendentes

Fontes de scraping (`sources`) e onboarding de um cliente novo ainda vêm de `clients/<id>.yaml`; `accounts.id` é global (`cobraalive-ig`), por isso dois clientes não podem ter a mesma conta de referência até o id da conta ficar por cliente.

## Rollback

Comentários no topo de `20261029111417_w4_engine_client_scope.sql` e seguintes; o motor antigo continua a funcionar com o trigger.
