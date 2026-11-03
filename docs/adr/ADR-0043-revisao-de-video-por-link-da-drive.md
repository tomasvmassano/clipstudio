# ADR-0043 · Revisão de vídeo por link da Google Drive, sobre a biblioteca de media

**Estado:** aceite · **Data:** 2026-11-03 · **Requisitos:** FR-05-03, FR-05-04 (parcial), ING-01 (fase atual) · **Mudança:** CHG-006 · **Depende de:** ADR-0038 (biblioteca de media)

## Contexto
O Tomás quer rever os 69 vídeos editados do Numeiro na plataforma. O object storage de ING-01 ainda não existe e o plano gratuito do Supabase não chega (1 GB, 50 MB por ficheiro; os vídeos somam ~2,4 GB). Decisão de produto (CHG-006): o ficheiro fica na Google Drive da agência e a app guarda o link. A biblioteca de media (W8, ADR-0038) já guarda ativos com versões, incluindo versões por link externo ligadas a um guião, e deixa a revisão de media para mais tarde ("o estado da biblioteca não é aprovação").

## Decisão
- **Um só modelo de media.** O vídeo a rever é um ativo da biblioteca (`media_assets`) ligado ao guião (`content_id`), com a versão atual (`media_versions`, `source = 'link'`) num link da Drive. A variante e o estilo vêm das etiquetas do ativo (`hook_1`…`hook_20`, `s14`, `s15`). Registar e trocar ficheiros é o `media_link_add` da biblioteca; uma versão nova no mesmo ativo volta a "por rever".
- **A revisão é por versão:** `media_reviews` (estado de cada versão; sem linha = por rever), `media_comments` (momento opcional em ms, respostas num nível que herdam o momento, resolver/reabrir; não se apagam nem se reescrevem), `media_decisions` (aprovar, pedir alterações, rejeitar; motivo obrigatório nos dois últimos; não se alteram). Só a versão atual se decide; aprovado é final (o gatilho também o garante). Decisões auditadas (`media.review.decided`) e eventos `media.commented`, `media.decided`.
- **Permissões:** ler com `media.read` e a biblioteca ligada (`media.library`), como a própria biblioteca; comentar `review.comment`; decidir `review.approve`. Sessão individual: o código de equipa não chega à revisão de vídeo, como não chega à biblioteca. Cada RPC recebe o cliente e só encontra ativos e versões desse cliente (outro cliente: 42501 na lista, P0002 por ID).
- **Só links da Drive:** a lista mostra ativos ativos ligados a um guião cuja versão atual é um link da Drive (`_drive_file_id`, o mesmo padrão no browser e no servidor).
- **UI:** separador "Vídeos" em `/c/[ws]/revisao?ver=videos`. Player da Drive embutido (`/preview`) e "Abrir na Drive". O player da Drive não expõe o tempo, por isso o momento escreve-se (0:23) e o momento de cada comentário abre a Drive nesse ponto (`?t=`).

## Alternativas rejeitadas
- **Tabela própria de vídeos de revisão** (`content_media`, primeira versão deste PR): duplicava a biblioteca e partia a identidade única do conteúdo (AGENTS §2.5). Abandonada quando o PR das vagas 6-8 (#44) entrou na análise.
- **Supabase Storage para os 69 finais:** não cabe no plano gratuito.
- **Ler o tempo do player:** a Drive não oferece API de player num iframe; um player próprio exigiria servir o ficheiro.
- **Credenciais da Drive na app** para listar ou partilhar ficheiros: a partilha fica na Drive, gerida pela agência.

## Consequências
Quem revê precisa de acesso ao ficheiro na Drive e da biblioteca ligada no cliente. Sem notificações de decisão nesta fase. Quando houver R2, a versão passa a `upload` e a revisão continua igual (falta só o player próprio). Rollback no fim da migração.
