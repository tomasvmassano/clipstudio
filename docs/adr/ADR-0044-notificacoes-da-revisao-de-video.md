# ADR-0044 — Notificações da revisão de vídeo (W5-05)

**Data:** 2026-11-03 · **Estado:** aceite · **Requisitos:** PRD FR-05-04 (notificações), FR-15-05; AGENTS §6 (eventos idempotentes), §9.

## Contexto

A revisão de vídeo (W5-04, ADR-0043) grava decisões e comentários, mas ninguém era avisado: quem editou o vídeo só sabia que o cliente pediu alterações se abrisse a Revisão. Com os 69 vídeos do Numeiro a entrar em revisão, o editor precisa de saber o que voltou e porquê.

## Decisão

1. **Dois tipos novos**, `video_decision` e `video_comment`, no catálogo de preferências (W8, ADR-0040), no grupo Guiões, não obrigatórios, só "na app" por omissão. O cliente e a pessoa podem desligá-los; a supressão fica registada como as outras.
2. **Triggers depois de inserir** em `media_decisions` e `media_comments` chamam `_notify`. As RPCs de W5-04 não mudam. Um erro ao avisar fica no log da base e nunca desfaz a decisão ou o comentário.
3. **Quem recebe.** Decisão: quem registou o ativo, quem registou a versão e o responsável do guião. Comentário: quem registou o ativo e a versão; numa resposta, também quem escreveu o comentário respondido ("Resposta ao teu comentário…"). Quem age não se avisa; quem já não tem acesso ao cliente não recebe (regras de `_notify`).
4. **Idempotência.** A chave é `video_decision:<id da decisão>` / `video_comment:<id do comentário>` por pessoa: repetir o evento não duplica, e repetir uma decisão igual já não cria decisão (W5-04).
5. **Para onde leva.** O item da caixa (`_ops_queue`) e a lista de notificações abrem `/revisao?ver=videos&asset=<id>`, que abre o vídeo. O vídeo aberto fica no URL, para o link se poder partilhar. Comentários de vídeo contam como menção na caixa.

## Alternativas rejeitadas

- **Redefinir `media_review_decide`/`media_review_comment`:** duplicava as RPCs inteiras numa migração e arriscava divergir de W5-04; o trigger cobre qualquer caminho de escrita.
- **Grupo "Revisão" novo nas preferências:** a UI no `main` só conhece três grupos; um grupo novo antes do merge escondia os tipos. Fica no grupo Guiões (o vídeo é sempre de um guião).
- **Avisar o responsável do guião em cada comentário:** ruído; recebe as decisões.

## Rollback

Bloco no fim de `supabase/migrations/20261103171148_w5_media_review_notif_body.sql`: tirar os triggers e as funções, repor `_ops_category`/`_ops_queue` de `20261030075315_w6_ops_p1.sql`, apagar notificações, preferências e definições dos dois tipos e repor a restrição de `notifications.kind`.

Nota: `20261103171023_w5_media_review_notif` foi aplicada em produção por engano só com um comentário (sem efeito); fica no repositório para o histórico bater com produção. A migração real é `20261103171148_w5_media_review_notif_body`.
