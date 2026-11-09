# ADR-0077 · O som do palco dá o tempo ao editor

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-08 · **Mudança:** W10-29

## Contexto

Com a imagem a funcionar (W10-28), o Tomás ouviu o primeiro pacote no editor: o som "dava solavancos" a toda a hora. O palco tinha um relógio próprio (requestAnimationFrame) e os `<video>` seguiam-no, reposicionando sempre que se afastavam mais de 0,25 s. Depois de cada reposicionamento o vídeo pára a carregar do R2, o relógio continua, o desvio volta a passar 0,25 s e o vídeo é reposicionado outra vez: um ciclo de saltos audíveis. Além disso cada corte entre palavras era um salto no mesmo elemento, com um buraco no som.

## Decisão

- A tocar, o som manda: o tempo do editor passa a vir do elemento de áudio (`onTime`), e não o contrário. O relógio da página só corre quando não há imagem.
- O som vem de dois `<audio>` da câmara do som (versão leve), que se revezam. `audioRuns` (puro, testado) dá os trechos em que o som corre seguido: só há salto onde o corte o exige (segmentos seguidos na fonte e na mesma janela colam num trecho). O trecho seguinte fica posicionado e carregado no outro elemento; no fim do trecho um começa e o outro pára.
- Os `<video>` ficam todos sem som e seguem o áudio; são reposicionados só no corte ou quando se afastam mais de 0,3 s e não estão a meio de outro reposicionamento.
- Um salto do cursor a tocar (clicar na linha de tempo) é reconhecido por não ser um tempo que o próprio motor deu, para um React atrasado não parecer um salto.

## Alternativas rejeitadas

- Subir a tolerância de desvio: reduz o ciclo mas não o elimina e deixa a imagem e as legendas fora de tempo.
- Descodificar o áudio com Web Audio: daria cortes perfeitos à amostra, mas obriga a descarregar e descodificar o áudio da sessão inteira (dezenas de MB) antes de tocar.
- Gerar um áudio por documento no motor: mais um job e mais uma espera a cada edição.

## Consequências

Os cortes ouvem-se como na exportação, com uma tolerância de um fotograma (~16 ms) no fim de cada trecho. A imagem pode ficar parada um instante depois de um corte para outra parte da gravação, enquanto carrega, sem afetar o som. A exportação (ffmpeg no motor) não muda.
