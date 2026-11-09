# ADR-0075 · Comentários como fonte de ideias (W10-26, REACT-08)

**Estado:** aceite · 2026-11-09 · CHG-010

## Contexto
O PRD §47 REACT-08 pede um separador Comentários na tab Reacts: de 3 em 3 dias, o agente lê os comentários dos Reels do próprio cliente e traz os que dão vídeo novo (discorda, concorda e acrescenta, outro ponto de vista, pergunta), avaliados contra a mensagem do cliente.

## Decisão
- Tabela própria `comment_ideas` (não reutilizar `react_candidates`): a identidade é o comentário (`comment_key`, único por cliente), não o vídeo, e não há link de vídeo a expirar nem fonte vigiada.
- Reutiliza as capacidades `reacts.read` e `reacts.decide` e a flag `reacts.radar` (pela regra do PRD: mesma superfície e os mesmos papéis). Gravar exige também `scripts.create`.
- A mensagem do cliente vem do servidor: `worker_comment_context` devolve a configuração ativa do motor (voz, formatos, guardrails, temas, léxico), a última lista de frases-persona, as contas do cliente, os comentários vistos nos últimos 60 dias e as últimas 200 decisões. O agente não guarda cópia própria da mensagem.
- `comment_record` cria um guião em rascunho (`formato = resposta_comentario`) sem o nome de quem comentou (pessoa privada); o nome só aparece na app para a equipa, com o aviso.
- O agente escreve só por `worker_comment_upsert`, que nunca muda estado nem decisões humanas.

## Alternativas rejeitadas
- Novas capacidades `comments.*`: mais uma linha na consola sem diferença real de quem decide; o PRD pede as mesmas.
- Guardar os comentários em `reels`/métricas: misturava dados de desempenho com fila editorial.
- Ler comentários pela API oficial já: só com OAuth Instagram (R-19); até lá, recolha pública (R-20), como no radar.

## Rollback
Bloco comentado no fim de `20261109132856_w10_comentarios.sql` (só depois de reverter o código; exportar decisões antes).
