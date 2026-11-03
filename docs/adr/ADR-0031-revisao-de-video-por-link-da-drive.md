# ADR-0031 · Revisão de vídeo por link da Google Drive

**Estado:** aceite · **Data:** 2026-11-03 · **Requisitos:** FR-05-03, FR-05-04 (parcial), FR-08-04 (parcial), ING-01 (fase atual) · **Mudança:** CHG-006

## Contexto
O Tomás quer rever os 69 vídeos editados do Numeiro na plataforma. O object storage de ING-01 ainda não existe e o plano gratuito do Supabase não chega (1 GB, 50 MB por ficheiro; os vídeos somam ~2,4 GB). Decisão de produto (CHG-006): o ficheiro fica na Google Drive da agência e a app guarda o link.

## Decisão
- `content_media`: uma linha por versão de vídeo de uma variante (`variant` = hook N ou geral, `style`, `version`), ligada ao guião. Guarda só o ID do ficheiro da Drive (extraído do link no servidor, `_drive_file_id`). Repetir o mesmo ficheiro não cria versão; um ficheiro novo cria a seguinte. Linhas não se apagam nem mudam, exceto o estado de revisão.
- `media_comments`: comentário com momento opcional em ms (`t_ms`), respostas num nível que herdam o momento, resolver/reabrir. Não se apagam nem se reescrevem.
- `media_decisions`: aprovar, pedir alterações ou rejeitar, com motivo obrigatório nos dois últimos; só a versão mais recente se decide; aprovado é final (para mudar, nova versão). Repetir a mesma decisão não duplica.
- Capacidades já registadas, agora ativas: `media.upload` (registar), `review.comment`, `review.approve`; ler com `scripts.read`. O código de equipa do Numeiro ganha `review.approve` (já aprovava guiões).
- Tudo por RPC (`media_link_add`, `media_review_list`, `media_detail`, `media_comment_add`, `media_comment_resolve`, `media_decide`); tabelas fechadas a leitura direta. Eventos `media.linked`, `media.commented`, `media.decided`.
- UI: separador "Vídeos" em `/c/[ws]/revisao?ver=videos`. Player da Drive embutido (`/preview`) e "Abrir na Drive". O player da Drive não expõe o tempo, por isso o momento escreve-se (0:23) e o momento de cada comentário abre a Drive nesse ponto (`?t=`).

## Alternativas rejeitadas
- Supabase Storage: não cabe no plano gratuito e duplicaria a migração para R2.
- Ler o tempo do player: a Drive não oferece API de player num iframe; um player próprio exigiria servir o ficheiro (storage ou proxy com credenciais da Drive na app), o que o CHG-006 evita.
- Pôr credenciais da Drive na app para listar ou partilhar ficheiros: a partilha fica na Drive, gerida pela agência.

## Consequências
Quem revê precisa de acesso ao ficheiro na Drive; sem ele, o player mostra o pedido de acesso da Google. Sem notificações de decisão nesta fase. Quando houver R2, `source` ganha outro valor e o resto (comentários, decisões, versões) fica igual. Rollback no fim da migração.
