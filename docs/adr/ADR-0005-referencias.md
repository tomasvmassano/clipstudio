# ADR-0005 — Referências por cliente (W2-04)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M07 FR-07-01/02/03/05/06, §7; ADR-0001 (referências isoladas por cliente).

## Contexto

Cada cliente tem criadores de referência (`accounts.role='reference'`) cujos reels são recolhidos pelo scraper (`reels`, com métricas e `script_analysis`). Isto alimenta o Desempenho, mas não havia biblioteca curada, classificação, coleções nem ligação a guiões e fontes.

## Decisão

1. `reference_items` é a biblioteca curada por cliente. Cada item tem link manual ou aponta para um reel recolhido (`reel_id`). Os reels continuam a ser dados de desempenho e não são copiados.
2. Ao guardar um reel, herdam-se hook, formato, estrutura (narrativa), duração e idioma da análise; tudo editável. Duração 0 do scraper = desconhecida.
3. Métricas só aparecem quando a referência aponta para um reel recolhido, sempre com "scraper · data". Referências por link não mostram números (FR-07-06).
4. Coleções como `colecoes text[]` no item: são grupos nomeados dentro do mesmo cliente, sem ACL própria, por isso dispensam tabela nova. Se precisarem de dono, descrição ou partilha, passam a tabela.
5. `reference_links` liga uma referência a um guião (`scripts.edit`) ou a uma fonte (`references.manage`), sempre no mesmo cliente por trigger. Desligar remove a linha e fica auditado.
6. Dedup por URL normalizado e por reel dentro do cliente; repetido = `PT409 duplicado:<id>`. Arquivar em vez de apagar.
7. O código de equipa lê referências, mas não as gere.

## Alternativas rejeitadas

- Marcar reels diretamente como referência: misturava dados recolhidos com curadoria e não suportava links manuais.
- Referências partilhadas pela agência entre clientes: rejeitado pelo produto (ADR-0001).

## Pendentes

- Upload de ficheiro e captura (FR-07-01), transcrição e análise de links manuais (FR-07-04), gerir a lista de criadores seguidos (mexe no scraper e no custo; W4).
- As métricas vêm de scraping, não da API oficial: fica rotulado na app, e a decisão de manter esta fonte é do produto (PRD §21).

## Rollback

Bloco no fim de `supabase/migrations/20261028205017_w2_references.sql` mais o replace inverso de `20261028205134_w2_references_zero_duration.sql`.
