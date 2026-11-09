# ADR-0076 · Refazer a versão leve de um vídeo já pronto

**Estado:** aceite (2026-11-09) · **Requisitos:** FR-08-01, EDL-08 · **Mudança:** W10-28

## Contexto

A 09/11 o C7870 (29 GB, câmara da frente com o som da lapela) foi conferido e ficou pronto, mas a versão leve falhou por falta de memória no worker de 512 MB. O editor usa só a versão leve no palco (ADR-0047), por isso os 37 vídeos do pacote abriram sem imagem nem som. Não havia forma de a refazer: `media_versions_guard` não deixa uma versão pronta voltar a pendente, e `media_worker_finish` ignora o resultado de um ingest para uma versão que já não está pendente.

## Decisão

- `media_proxy_redo(ws, version)` (capacidade `media.upload`, a mesma do carregamento): só para um vídeo pronto no R2 cuja versão leve não está pronta. Põe `proxy_state = pendente` e cria um job `ingest` com `input.proxy_only = true` (chave `proxy:<versão>:<n>`; com um job na fila devolve esse).
- O motor, nesse modo, não relê o original para o SHA-256 (já conferido), faz a versão leve e grava-a por `media_worker_proxy_save` (só `proxy_path`, `proxy_state`, `proxy_error` e `media_info` se faltar; exige a lease e uma chave ao lado do original). Depois fecha o job pelo `media_worker_finish` de sempre, que para uma versão pronta só o marca como feito.
- Botão "Refazer versão leve" na Biblioteca, no cartão do vídeo, quando a versão leve falhou.

## Alternativas rejeitadas

- Voltar a versão a pendente e repetir o carregamento inteiro: contraria o guard (versões prontas são imutáveis no estado) e relia 29 GB só para o SHA.
- Alterar `media_worker_finish` para aceitar o proxy de uma versão pronta: reescreve uma função central que todos os jobs usam; a função nova é aditiva e só serve este modo.
- Criar uma versão nova do ativo: mudaria o `version_id` que o pacote e as marcações já usam.

## Consequências

Uma versão leve falhada deixa de ser um beco sem saída. O motor antigo, sem o modo, faria um ingest normal (relê e confere o SHA) e o resultado seria ignorado pelo finish: a migração vai depois do motor. Rollback: largar as duas funções; jobs `proxy_only` na fila passam a cancelados.
