# ADR-0079 · Barra vermelha contínua no S15

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-08, EDL-13 · **Mudança:** W10-31 (motor: numeiro-engine `s15-barra-continua`)

## Contexto

O Tomás comparou o S15 com a referência (instagram.com/p/DenrdHBRDpo): lá a barra vermelha avança de forma contínua, a meio da palavra, linha a linha. A spec S15 v2 já dizia "contínuo por frame", mas o render e o palco avançavam palavra a palavra.

## Decisão

- Motor: cada estado de palavra do S15 é partido em fotogramas (1/30 s) com a fração dita da palavra ativa; a barra cobre as palavras já ditas e essa fração. Imagens iguais reaproveitadas e gravadas em paralelo.
- Palco: `wipeFrac` dá a mesma fração; a palavra ativa leva um gradiente com o corte nessa fração, as anteriores a caixa inteira.
- S14 e o aspeto com destaque próprio (cor da palavra dita) não mudam.

## Consequências

Um PNG por fotograma de fala na exportação (~1300 para 60 s), uns segundos a mais por vídeo com 8 vCPU. A fração é linear no tempo da palavra da transcrição: uma palavra com tempos errados (ex.: "custa" com 7 s) enche devagar.
