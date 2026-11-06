# ADR-0070 — Pacote de edição por guião, disparado quando chegam as gravações (W10-20)

**Data:** 2026-11-06 · **Estado:** proposto (PR por aprovar) · **Requisitos:** PRD STU-03; contrato para STU-02; EDL-01, EDL-02, ING-03; ADR-0048 (pacote da sessão), ADR-0052 (exportar todos), ADR-0065 (marcas, W10-17), ADR-0068 (visuais da IA, W10-18); AGENTS §2.1, §2.8, §5, §7.

## Contexto

O pacote de hoje (`edit_package_request`, job `package`, `numeiro-engine` `do_package`) recebe a gravação longa da frente e do lado da sessão inteira e N guiões, transcreve o ficheiro do lado todo e só depois escreve as versões 1. Numa sessão de 30 guiões tudo espera pelo fim, e os exports (3-4 min cada, worker com 512 MB e `FFMPEG_THREADS=1`) só começam depois. STU-03 pede o pacote de um guião de cada vez, disparado pelo envio do corte desse guião (frente + lado), com as mesmas saídas, para haver vídeos para rever poucos minutos depois de cada "Sim". O agente de estúdio (STU-02) ainda não existe: por agora quem envia é a app.

## Decisão

1. **Ligação gravação → guião + câmara** (`recording_clips`, fechada): um ficheiro da Biblioteca é a gravação da câmara `front` ou `side` de um guião, com a sessão do teleprompter quando se sabe e a origem (`upload`, `biblioteca`; `agente` reservado). Uma gravação atual por guião e câmara; ligar outra substitui (auditado). RPCs `media_clip_link` / `media_clip_unlink` (capacidade `media.upload`, a mesma de mudar os dados do ativo) e `media_clip_get` (`media.read`). Na app: no envio da Biblioteca (guião + câmara por ficheiro, liga logo que o ativo existe) e na ficha do ficheiro; e um formulário na Edição automática.
2. **Pedido por guião** (`edit_package_script_request`): mesmas regras do pacote da sessão (`edit.timeline`, flag `edit.studio`, R2) e mais a flag `edit.package_script`. O job é o mesmo `package` com o mesmo input (um só guião) e mais `mode = 'script'`, `guiao_id`, `origin` e `marks` vazio. Idempotente por (guião, versões das duas gravações, estilo, versão do estilo[, visuais da IA]) com chave própria `package_script:`. Pacote falhado: pedir de novo cria um job novo.
3. **Worker** (`numeiro-engine` `stu03-pacote-por-guiao`): com `mode = 'script'` transcreve só o corte (o som do lado tirado uma vez serve também para a sincronização quando o corte tem até 10 min) e a janela do guião é o ficheiro todo (`clip_windows`); escolha dos takes, documento v1 por hook, estilo guardado e alternativas iguais. Sem `mode` tudo fica como antes. Um worker antigo processa o job por guião pelo caminho da sessão (a janela sai da transcrição do corte): funciona, só sem a garantia do ficheiro todo.
4. **Automático** (definição por cliente, `package_script_settings`, `package_script_settings_set` com `styles.manage`; ligar o exportar automático exige também `edit.export`): quando as duas gravações de um guião ficam prontas (trigger em `media_assets.current_version_id`, depois do `ingest` do worker) ou quando se liga a segunda, o pacote do guião é enfileirado. O exportar automático corre quando um pacote por guião acaba (`media_jobs` → `done`): um export por vídeo, que entra na revisão em lote. O automático corre **em nome de quem gravou as definições** (`enabled_by`) e volta a verificar a cada disparo, por `_authorize(…, enabled_by)` e `_flag_on_for`, que essa pessoa ainda tem as capacidades e as flags (removida, suspensa ou sem flag = não corre e fica o motivo em `package_script_status`). Nunca falha a transação que dispara (verificação do upload, fim do pacote).
5. **Concorrência:** locks de transação por ativo e por guião, tomados antes de ver se as duas gravações estão prontas, para que "ligar" e "ficar pronta" (ou frente e lado a acabar ao mesmo tempo) não se percam uma à outra.
6. **Câmaras pelo nome:** o editor e a exportação encontram as câmaras pelo nome do ficheiro (`_edit_resolve_cams`). O pedido recusa (e o automático não corre, com o motivo) se houver outro ficheiro pronto ou a caminho com o mesmo nome noutro ativo; o exportar automático confirma que as câmaras encontradas são as versões do pacote.
7. **Contrato do agente de estúdio (STU-02):** o agente envia cada corte pelo mesmo caminho da Biblioteca (`/api/media/uploads` → `media_upload_begin` com `content_id`, envio, `media_upload_complete`) e liga-o com `media_clip_link(ws, asset, guião, câmara, sessão, 'agente')` quando tiver identidade própria (`studio.capture`, planeada no CHG-008); o resto (automático, worker, exportar) já fica igual. Nome do ficheiro único por cliente (ex.: `<data>_g07_frente.mp4`).
8. `edit_package_list` deixa de listar os pacotes por guião (com 30 por sessão empurravam o pacote da sessão para fora dos últimos 20); têm a lista própria `edit_package_script_list`.

## Alternativas rejeitadas

- **Reescrever `edit_package_request`** para aceitar um guião: W10-17 e W10-18 mexem nessa função ao mesmo tempo; a montagem do job foi copiada (`_package_script_enqueue`, usa `_edit_package_fill` de W10-18 só se existir) para não haver conflito.
- **Chamar `edit_package_request` / `edit_export_request` "como" quem ligou o automático** (pôr o `sub` no JWT da transação): obrigava a forjar `aal2` para quem tem MFA e a contornar a verificação da sessão (W10-08). Em vez disso a autorização é avaliada explicitamente para essa pessoa e o job é montado por funções internas (cópia do export em `_package_script_export`, sem reescrever `edit_export_request`).
- **Capacidade nova** para ligar gravações ou para as definições: as ações cabem em capacidades que já existem (`media.upload`, `edit.timeline`, `styles.manage` que já governa o preset do pacote, `edit.export`). Pergunta em aberto para o dono do produto.
- **Marcas do teleprompter no corte:** as marcas são da gravação longa; o corte já é só deste guião. O job leva `marks` vazio para o trigger de W10-17 não as juntar.

## Limitações

- Notificação "Pacote de edição pronto" por guião (30 numa sessão) para quem pediu ou ligou o automático.
- A exportação à mão continua a encontrar as câmaras pelo nome: um ficheiro com o mesmo nome carregado depois do pacote troca a câmara (como hoje no pacote da sessão).
- Sem verificação com o worker real e uma sessão real (precisa de deploy do motor e da migração).
- O corte por guião a partir das marcas e da gravação contínua (recuperação descrita no STU-03) fica para o agente de estúdio.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_pacote_por_guiao.sql`. Desligar sem rollback: flag `edit.package_script` a `off`. Jobs por guião já criados continuam válidos com o worker antigo.
