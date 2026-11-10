# ADR-0083 · Estilo S17 (caixa branca com imagens) e imagens no editor

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-08, EDL-09, EDL-13, VAR-02 · **Mudança:** W10-37 (motor: numeiro-engine `estilo-s17`)

## Contexto

O Tomás pediu o estilo da referência instagram.com/reel/DeiO5-mNeVh, com uma forma fácil de escolher a imagem e a duração na linha do tempo, e as imagens sempre por baixo das letras. Medido fotograma a fotograma: hook em caixa branca arredondada em cima; legenda numa linha dentro de uma caixa branca a ~2/3 da altura, o que já se disse a preto e o que vem a cinzento; imagens inteiras num cartão na metade de baixo, com a legenda por cima.

## Decisão

- Motor: `S17` em `STYLES` (`draw_box_line`; blocos de 4; `graphic_box` [90,1120,900,760] para as imagens sem posição própria; legendas e hook por cima dos visuais, como sempre).
- App: o mesmo estilo no plano das legendas (`CAP_STYLES`, `GRAPHIC_BOXES`, igual ao motor em 200 documentos) e no palco; o palco passa a desenhar os visuais por baixo do hook e das legendas (antes o hook ficava por baixo), a imagem verdadeira da Biblioteca e o hook como o render (caixa branca, letra serifada preta).
- Editor: "Imagem no cursor" abre uma grelha de miniaturas com procura; a imagem entra no cursor até ao fim da frase da legenda; no painel: miniatura, trocar imagem, duração em segundos e "até ao fim da frase". O S17 aparece nos estilos do pacote e do editor.

## Consequências

Sem migração. As imagens têm de estar na Biblioteca do cliente (kind imagem). Os links das imagens no editor são curtos e renovam-se sozinhos. O hook do palco muda de aspeto em todos os estilos para ficar igual ao export.

## Adenda (W10-38, 2026-11-10)

Imagens do computador: arrastar para o palco ou para a linha do tempo, ou carregar no seletor. Cada ficheiro passa pelo carregamento normal da Biblioteca (SHA-256, R2, verificação pelo worker) e o visual entra logo no documento com o ativo novo; o palco mostra o ficheiro local (object URL) até haver link do armazenamento. Só JPG, PNG, WebP e GIF (a política da Biblioteca).
