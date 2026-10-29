# ADR-0025 · Revisão de guiões com comentários contextuais e caixa de revisão

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** FR-05-01, FR-05-02, FR-02-02

## Contexto
A equipa do Numeiro revia guiões por mensagens fora da app: a frase criticada perdia-se, não se sabia que versão tinha sido comentada e não havia uma lista de "o que está à espera de mim". Já havia aprovação versionada (`content_transitions`) e tarefas com responsável, prioridade e prazo, mas nada que ligasse as duas coisas.

## Decisão
- `content_comments`: cada comentário pertence a um guião e a um bloco (Hook N, Corpo, CTA, Notas, Geral), pode citar a frase exata e guarda a versão em que foi feito (`version_id`). Respostas num nível. Não se apagam nem se reescrevem (trigger); resolvem-se e reabrem-se. Lê quem tem `scripts.read`; comenta quem tem `review.comment` (já existia na matriz: contributor, reviewer, manager, admins; o código de equipa do Numeiro também); resolve quem escreveu ou quem edita/aprova.
- Menções e respostas criam notificações (`script_mention`, `script_comment`); cada ação vai para a outbox (`script.commented`, `script.comment_resolved`, `script.comment_reopened`).
- `review_inbox`: guiões por estado editorial com o responsável, a prioridade e o prazo da tarefa em aberto ligada a cada guião (preferindo `kind = review`); filtros por estado, responsável (eu / ninguém / pessoa), prioridade, prazo (atrasados, hoje, 7 dias) e texto. Ordem: por rever, depois urgência, depois prazo.
- UI: `/c/[ws]/revisao` no menu (sai de "Em breve") e "Comentários" em cada cartão de guião. Carregar numa frase escolhe-a para comentar.

## Alternativas rejeitadas
- Comentários como tarefas: misturava conversa com trabalho atribuído e enchia a caixa de entrada.
- Âncoras por posição de carácter: partiam-se a cada edição; bloco + frase citada + versão sobrevivem às mudanças e mostram "numa versão anterior".
- Prioridade e responsável no próprio guião: duplicava o que as tarefas já têm.

## Consequências
Revisão de vídeo (FR-05-03) usa o mesmo desenho por timestamp quando houver media. Menções na UI ficam para depois (a API já aceita). Rollback no fim da migração.
