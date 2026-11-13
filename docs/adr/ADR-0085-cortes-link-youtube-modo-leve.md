# ADR-0085 · Cortes a partir do link do YouTube, tipos de momento e modo leve

**Estado:** aceite (2026-11-13) · **Requisitos:** CLIP-01, CLIP-03, CLIP-05, CLIP-06 (CHG-012) · **Mudança:** W10-45, numeiro-engine #20

## Contexto
O Tomás quer colar o link do YouTube de cada vídeo acabado e receber todas as oportunidades de corte (10-15+), com pouca edição (só legendas): conversas, reflexões, opiniões sobre factos, momentos engraçados. O Clip Miner da app (W10-12) existia, mas o motor nunca tinha entrado no main (PR #20 aberto): os pedidos ficavam na fila.

## Decisão
- O link do YouTube é a entrada; o vídeo vem sempre do ficheiro do cliente no R2. Título e canal pelo oEmbed público (rota `/api/clips/youtube`, só sessões individuais, só links do YouTube); a app escolhe o ficheiro da Biblioteca com o título mais parecido (Jaccard das palavras ≥ 0,34) ou carrega-se ali.
- `clips_request2` (nova, aditiva): número 3-20 ou automático (~1 por 4 min, 5-20), modo `leve`/`completo`, link validado (`_youtube_id`). `clips_request` fica até ao contract.
- Motor: tipos de momento no prompt `clip-miner-2` e nos metadados; modo leve = sem reordenação, sem título por cima nem CTA, 20-90 s; idioma detetado (PT/EN) e títulos no idioma do vídeo; limites por máquina e tema relaxam até ao número pedido.

## Alternativas recusadas
Descarregar do YouTube com um serviço externo: proibido pelos termos do YouTube e pelo CLIP-01; o Tomás aceitou outra fonte. YouTube Data API: não dá o ficheiro.

## Consequências
Sem master, o cliente descarrega o vídeo no YouTube Studio (720p) e carrega-o. O enquadramento continua ao centro (CLIP-07 por fazer). Rollback: pedir em modo completo repõe o comportamento anterior; reverter os PRs.
