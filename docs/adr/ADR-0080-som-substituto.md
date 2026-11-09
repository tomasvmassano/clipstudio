# ADR-0080 · Som substituto de uma gravação

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-08, FR-08-01 · **Mudança:** W10-32 (motor: numeiro-engine #32)

## Contexto

O Tomás tratou fora da app o som da lapela do C7870 (WAV com a mesma duração, 1615,2 s) e quer que os vídeos usem esse som, exatamente no mesmo tempo. O original tem 29 GB e SHA-256 conferido: as versões são imutáveis e voltar a carregá-lo com outro som custaria horas.

## Decisão

- `media_versions.audio_version_id`: a gravação aponta para uma versão de áudio da Biblioteca (mesmo cliente, prontas no R2, durações a menos de 1 s). `media_audio_replace` liga ou tira (capacidade `media.upload`, auditado); `media_audio_links` diz à Biblioteca o que está ligado.
- `_edit_resolve_cams` junta `audio_key` e `audio_version_id`: a exportação usa esse áudio no lugar do som do vídeo, no mesmo tempo (deslocamento 0); o palco toca-o (link assinado curto, renovado quando expira).
- A chave do export leva o som: trocar o som e exportar outra vez dá um export novo, não o antigo.
- Biblioteca: "Som desta gravação" no cartão de cada gravação de vídeo no R2.

## Alternativas rejeitadas

- Remisturar o original com o som novo: nova versão de 29 GB, outra versão para os pacotes e marcações.
- Música do documento com a voz a zero: a música não segue os cortes da gravação.

## Consequências

Os vídeos exportados antes da troca ficam com o som antigo até serem exportados de novo. A transcrição dos pacotes continua a usar o som da câmara. Rollback: repor as funções anteriores (o código antigo ignora os campos novos); a coluna sai numa migração posterior.
