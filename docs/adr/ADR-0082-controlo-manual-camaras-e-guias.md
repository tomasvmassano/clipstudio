# ADR-0082 · Câmaras à mão, guias do palco e corpo sempre igual

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-07, EDL-08, EDL-09, EDL-14 · **Mudança:** W10-35 (motor: numeiro-engine `enquadramento-por-trecho`)

## Contexto

O Tomás pediu mais controlo manual: trocar o ângulo da câmara, fazer zoom e puxar a câmara da frente para cima, e ligar e desligar guias de layout (zona segura dos Reels, hook/olhos/legendas). Pediu também a garantia de que o corpo fica igual nos hooks.

## Decisão

- Trechos de câmara (`doc.cameras`) editáveis: clicar na faixa abre ângulo (os das gravações do documento), zoom (1 a 3×), posição vertical e horizontal (0 a 1), dividir no cursor, aplicar o enquadramento a toda a câmara e repor; tecla C troca a câmara no cursor. `x`/`y` entram no trecho; o render corta a partir desse ponto (`cam_anchor`, `geo`) e o palco escala com `transform-origin` no mesmo ponto, por isso a pré-visualização é igual ao export. A posição só muda o enquadramento com zoom acima de 1×.
- Guias no palco, só no editor (lembradas no dispositivo): zona segura dos Reels = fora do retângulo seguro do QC (x 60-960, y 210-1600) sombreado; grelha de terços com as faixas do hook, dos olhos e das legendas.
- Corpo sempre igual (EDL-14): sem caixa para desligar; o modo guiado também aplica (o servidor aplica as regras do modo guiado a cada hook); "Igualar corpos a este" no aviso de corpo diferente. O resultado aparece depois de recarregar o editor.

## Alternativas rejeitadas

- Enquadramento global por câmara num campo à parte: o trecho já tem câmara e zoom; "aplicar a toda a câmara" escreve o mesmo valor em todos os trechos e continua editável trecho a trecho.
- Guias no vídeo exportado: só servem a quem edita.

## Consequências

Sem migração (a validação do documento não restringe as câmaras). Os documentos antigos sem x/y ficam como estavam.
