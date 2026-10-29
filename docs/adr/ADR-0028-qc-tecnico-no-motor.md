# ADR-0028 · QC técnico dos vídeos em código, no motor

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** EDL-03 (parcial)

## Contexto
O PRD pede QC técnico em código antes de qualquer revisão por IA (EDL-03). A edição vai ser automática e corre no worker do motor (`numeiro-engine`), onde vai estar o ffmpeg do render.

## Decisão
- Módulo `engine/qc.py` no motor (PR numeiro-engine #7), só com ffprobe/ffmpeg, sem API nem rede: formato 1080×1920, fps constante e no intervalo, duração, faixa de áudio, loudness integrada e pico (ebur128), troços pretos (blackdetect) e congelados (freezedetect), texto do layout dentro do retângulo seguro (mesma regra que a app valida ao gravar estilos, ADR-0027) e distinção visual por pHash (DCT 32×32, 64 bits, média de 5 amostras) face à fonte e às irmãs.
- Limites por cliente em `qc:`; os valores atuais (−14 LUFS ± 2, pico ≤ −1 dBTP, 5-180 s, preto ≤ 0,5 s, congelado ≤ 2 s, pHash ≥ 10 bits) são pressupostos até ao piloto (EDL-06).
- Ficheiro ilegível é erro (`QCError`, sair 2), não chumbo: o job repete ou vai para dead-letter em vez de marcar a variante como má.
- O pHash é condição necessária, não suficiente: quem decide se uma variante é nova continua a ser a receita VAR-01.
- O texto queimado no vídeo é verificado pelo layout do estilo usado no render, não por OCR.

## Alternativas rejeitadas
- QC na app (Vercel): sem ffmpeg e com limites de tempo curtos para vídeo.
- OCR para encontrar texto: lento e falível; o render conhece as caixas de texto do layout.

## Consequências
Falta ligar o QC ao job do pacote (EDL-01) e guardar o relatório por variante para a revisão em lote (EDL-02).
