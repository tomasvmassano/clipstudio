# ADR-0087 · Edição do episódio completo (POD-01..06, CHG-013)

**Estado:** aceite · **Data:** 2026-11-18 · **Pedido:** Tomás ("pelo menos um podcast editado hoje")

## Contexto
O PRD só tinha cortes de vídeos longos (CLIP); a edição do episódio completo de um podcast não existia (CHG-013, §48.2). O editor, a pré-visualização e a revisão são verticais (1080x1920).

## Decisão
1. **Job `episode` no worker de media** (numeiro-engine `engine/episode.py`, `engine/episode_io.py`): transcrição com tempos por palavra, cortes por regra em código (pausas acima do máximo do perfil, hesitações, gaguez, repetições, ar morto) e pelo modelo só por IDs de frase (falsos arranques, frases repetidas, conversa antes/depois); câmara do orador ativo pela energia do som de cada câmara; render pelo mesmo `render_doc` dos curtos com tela e loudness por documento (`doc.size`, `doc.audio.lufs`); os curtos ficam iguais.
2. **Resultado:** o master entra na Biblioteca como vídeo novo (etiqueta `episodio`); áudio, .srt, capítulos, notas e lista de cortes ficam no R2 no destino do pedido e descarregam-se por link de 2 min (`episode_file_access`, auditado).
3. **O documento de edição do episódio é gerado e guardado no R2, mas ainda não abre no editor** (vertical). POD-01 fica parcial até o editor suportar paisagem.
4. Limite de 380 segmentos no motor (a app aceita 400): repõem-se primeiro os cortes mais curtos, com aviso.

## Alternativas rejeitadas
- Cortar o episódio no Clip Miner: produz cortes, não o episódio limpo.
- Remotion para o master: segundo motor de render, quebra "pré-visualização igual ao export" (EDL-08).
- Guardar o .srt e os outros ficheiros como versões na Biblioteca: a Biblioteca é de média; ficheiros de texto por link curto chegam.

## Consequências
- Sem versão leve para o master (paisagem): a revisão faz-se descarregando.
- Separação de oradores continua por escolher (CLIP-02); com uma câmara só alterna plano normal e aproximado.

## Rollback
Desligar a flag `edit.episode`; reverter `media_worker_finish` para a de `20261106065110_w10_clip_miner.sql`. Jobs feitos ficam como histórico.
