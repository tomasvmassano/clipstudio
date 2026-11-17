# ADR-0086 · Pacote de edição com uma câmara só

**Estado:** aceite (2026-11-17) · **Requisitos:** EDL-01 · **Mudança:** W10-47, numeiro-engine #35

## Contexto
O pacote automático (W5-09, ADR-0048) sempre exigiu duas gravações da sessão (câmara da frente e do lado). A EVOLVE gravou os kits K1 a K8 de 17/11 com uma câmara (C8128, 10,8 GB) e não havia forma de fazer o pacote.

## Decisão
- `edit_package_request` aceita `p_side` vazio: a gravação da frente dá o som, a imagem e o tempo; `input.single = true`, `input.side` = a mesma gravação (para a lista e o "Tentar de novo" continuarem a funcionar) e `audio = front`. A mesma gravação nas duas câmaras continua recusada (22023). Com duas câmaras nada muda: assinatura, chave de idempotência e validações iguais.
- Motor: com `single` (ou sem lado) não sincroniza, `source.cams = {front}` e o corpo alterna plano normal e plano aproximado (zoom 1,2) no mesmo ritmo em que alternava câmaras; o hook fica no plano normal. É o formato de documento de câmara única que os cortes (CLIP) já usam, por isso o editor e a exportação não mudam.
- UI: "Gravei com uma câmara só" no Novo pacote (lembrado por dispositivo; ligado sozinho quando só há uma gravação pronta).

## Alternativas recusadas
Escolher a mesma gravação nas duas câmaras: obrigava o motor a sincronizar o ficheiro com ele próprio e a exportação a abrir duas vezes um ficheiro de 10 GB. Uma RPC nova: mais superfície para o mesmo pedido.

## Consequências
Sem segunda câmara o ritmo visual vem só do zoom; a deteção de cara para o enquadramento continua por fazer (EDL-01). Rollback: reaplicar a função de `20261109171200_w10_som_da_lapela.sql` e reverter os PRs; os jobs de uma câmara já feitos continuam legíveis.
