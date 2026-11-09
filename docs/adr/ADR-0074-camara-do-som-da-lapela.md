# ADR-0074 · Câmara com o som da lapela escolhida em cada pacote

- **Data:** 2026-11-09
- **Estado:** aceite
- **Requisitos:** EDL-01 (pacote de edição automático), ADR-0048
- **Pedido:** Tomás, 09/11. Na sessão de hoje a lapela estava na câmara da frente (C7870), "mas pode nem sempre ser assim".

## Contexto

O pacote automático (ADR-0048) assumia que o som da lapela estava sempre na câmara do lado. Isso veio da montagem do protótipo e nunca foi confirmado com o dono: a UI chegou a chamar ao campo "Câmara do lado (com o som da lapela)". O motor tirava o som, a transcrição e o tempo do documento sempre do lado. Com a lapela na frente, a transcrição e o som do vídeo ficavam com o microfone da câmara.

## Decisão

- O pedido do pacote diz de que câmara vem o som: `edit_package_request(..., p_audio text default 'side')`, com os valores `front` ou `side`. Fica guardado em `input.audio` e no audit `edit.package_requested`.
- Na UI (Edição automática → Novo pacote), "Som da lapela" é um campo obrigatório, sem valor assumido. Cada dispositivo lembra a última escolha neste cliente (`pkg.audio.<ws>`). Os campos das câmaras ficam só "Câmara da frente" e "Câmara do lado".
- O motor (numeiro-engine `lapela-camara`) tira o som, a transcrição, a duração e a hora do ficheiro da câmara escolhida. A outra câmara é sincronizada pela correlação do som. O documento grava `source.audio` com essa câmara e `source.offsets` com a câmara do som a 0. O render já respeitava `source.audio`.
- A chave de idempotência só muda com o som na frente (sufixo `:af`), por isso os pedidos antigos e os de som no lado continuam iguais.
- O resultado do job mantém `offset.front`, que a app atual lê, e acrescenta `offset.side` e `audio`.

## Alternativas rejeitadas

- **Trocar as câmaras no formulário,** isto é, pôr a frente no campo do lado. Funcionava para o som, mas os cortes ficavam com "frente" e "lado" trocados e a receita de câmaras (o hook na frente) deixava de bater certo.
- **Detetar a lapela automaticamente pelo nível do som.** É frágil (as câmaras também gravam som) e não é auditável. Pode vir mais tarde como sugestão, nunca como escolha silenciosa.

## Limites

- O pacote por guião (STU-03) ainda usa o som da câmara do lado. Seguimento: pôr a mesma escolha nas definições do pacote por guião.
- Um gravador de som à parte (sem ser numa das câmaras) não é suportado.

## Rollback

Correr o bloco de rollback da migração `w10_som_da_lapela` (repõe a função de 6 argumentos) e reverter o PR. O motor sem `input.audio` usa o lado, como antes.
