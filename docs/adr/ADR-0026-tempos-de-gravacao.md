# ADR-0026 · Tempos de gravação do teleprompter como base do corte automático

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** ING-03 (parcial), EDL-01 (preparação)

## Contexto
A edição vai ser feita pela IA ou por código, sem passo manual (decisão do Tomás, 29/10). O FX3 grava um ficheiro longo por sessão; para o cortar por guião e por bloco (ING-03) é preciso saber quando cada guião e cada bloco foi lido. O teleprompter só guardava a posição para retomar (`recording_progress`, sobrescrita a cada 4 s) e os takes, sem hora de início nem de fim de leitura.

## Decisão
- `recording_marks`, só de acrescentar: cada marca tem tipo (`open`, `play`, `pause`, `block`, `take`, `recorded`, `not_recorded`, `exit`), guião, bloco, hora do dispositivo (`client_at`), hora do servidor (`server_at`), dispositivo e um `client_ref` gerado no dispositivo, único por cliente. A diferença entre as duas horas permite corrigir o relógio do dispositivo quando se alinhar com a câmara.
- `recording_marks_add` recebe lotes de até 200, exige `recording.use` (o código de equipa também) e é idempotente pelo `client_ref`. Recusa horas fora da janela da sessão (desde a véspera até 10 minutos no futuro) e guiões fora da fila da sessão.
- `recording_timeline` devolve, por guião, as janelas de leitura de cada bloco (de "rolar" ou "mudança de bloco" até à marca seguinte do mesmo dispositivo), os segundos lidos, os takes e a última decisão "Gravaste?". Lê quem tem `recording.use` ou `scripts.read`.
- No teleprompter as marcas ficam primeiro no dispositivo (`tp.marks.<cliente>`) e são enviadas a cada 10 s, ao parar, ao confirmar e ao sair. Sem rede, ficam guardadas e seguem quando a ligação voltar. A fila mostra "Tempos da sessão".
- As marcas `take` e `recorded` são só telemetria: o take e o estado de produção continuam nas suas RPCs com `recording.confirm`.

## Alternativas rejeitadas
- Derivar os tempos de `recording_progress`: só guarda o último ponto, perde a história.
- Uma marca por linha de texto ou por segundo: volume grande sem ganho; o alinhamento fino vem da transcrição com tempos por palavra (ING-03, segunda metade).
- Publicação assistida manual (PUB-03) como passo intermédio: recusada pelo Tomás (29/10), espera pela API.

## Consequências
O motor de edição (W5) lê `recording_timeline` para propor cortes; falta a ingestão do ficheiro da câmara, a transcrição e a sincronização pelo áudio. Rollback no fim da migração (funções primeiro; a tabela sai num contract posterior).
