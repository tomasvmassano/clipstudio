# ADR-0078 · Legendas do palco iguais às da exportação

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-08, EDL-13 · **Mudança:** W10-30

## Contexto

O Tomás viu as legendas do palco "aos solavancos, a repetir-se". O palco mostrava todas as palavras numa janela deslizante de ±0,6 s à volta do cursor: as palavras entravam e saíam uma a uma e as linhas reorganizavam-se a cada fotograma. Além disso uma palavra que atravessava dois cortes seguidos era partida e aparecia duas vezes. A exportação (engine/render_doc.py) faz outra coisa: blocos (S15 até 6 palavras, fechados no fim de frase, numa pausa > 0,45 s ou numa vírgula; S14 uma palavra), cada palavra uma vez, no corte onde começa.

O editor também não deixava mudar o estilo das legendas de um vídeo: só no pedido do pacote.

## Decisão

- `src/lib/caption-plan.ts` é o espelho de `words_out`, `chunks_of` e `caption_plan` do motor; o palco mostra o estado desse plano no instante t. Verificado contra o motor em 200 documentos aleatórios, sem diferenças; testes em `tests/caption-plan.test.mts`.
- O palco desenha o bloco como o render: S15 alinhado à esquerda na caixa do estilo, o que já se disse em caixa vermelha (ou a palavra dita na cor de destaque do aspeto); S14 a palavra ao centro.
- "Estilo das legendas" (S15 ou S14) no painel Aspeto do editor; entra no histórico e na versão gravada, e a exportação usa-o.

## Alternativas rejeitadas

- Pedir ao motor um plano de legendas por documento: uma ida ao servidor a cada edição.
- Afinar a janela deslizante: continua a não ser o que se exporta.

## Consequências

O que se vê no palco é o que sai no vídeo, no texto e no tempo. A letra é a serifada do sistema (a Instrument Serif do render não está carregada na app), por isso as quebras de linha podem diferir ligeiramente. Os estilos S13 e S16 do catálogo continuam sem desenho no motor e não aparecem como opção.
