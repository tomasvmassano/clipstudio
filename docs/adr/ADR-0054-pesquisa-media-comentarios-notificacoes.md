# ADR-0054 — Pesquisa global: media, comentários dos vídeos e notificações próprias (W10-02)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD FR-16-01, FR-16-05, MIG-08; R-01, R-02, R-11; CAP-05, CAP-09; AGENTS §5, §15. Estende ADR-0035.

## Decisão

1. **Três tipos novos no mesmo `search_global`**, com o formato de resposta de sempre (`groups[] {kind, label, more, items[]}`): `media` (Biblioteca de media), `comment` (Comentários nos vídeos) e `notification` (As minhas notificações). Os grupos antigos não mudam; o browser antigo ignora tipos que não conhece.
2. **Cada grupo usa a regra da funcionalidade dona, sem capacidades nem flags novas** (CAP-09: a flag não dá acesso; a capacidade não liga a funcionalidade):
   - `media`: `media.read` + flag `media.library` no cliente (como `media_library`). Só ativos (`lifecycle = 'ativo'`): o lixo e os eliminados ficam de fora da pesquisa, mesmo para quem os pode ver na vista "Lixo". Procura no título, nas etiquetas, no nome original do ficheiro de qualquer versão e no ID. Entra também na pesquisa por `#etiqueta`.
   - `comment`: sessão individual + `media.read` + flag `media.library` (como `media_review_list`) **e** `scripts.read`, porque a página `/revisao`, para onde o resultado leva, exige `scripts.read` e mostra o guião. Só comentários que a revisão mostra: ativo, ligado a um guião não eliminado, versão atual elegível para revisão e versão do comentário pronta.
   - `notification`: só `user_id = auth.uid()`, nos clientes onde a pessoa recebe notificações (`tasks.read`, a regra da caixa) e onde tem acesso ativo. Ficam de fora as notificações de um guião eliminado.
3. **Código de equipa**: só o que `legacy_can` permite; nenhum dos três (não tem `media.read` e não tem identidade para notificações).
4. **Destinos**: media abre `/c/<ws>/biblioteca?asset=<id>` (a biblioteca passou a abrir o ativo pelo URL e a guardá-lo lá); comentário abre `/c/<ws>/revisao?ver=videos&asset=<asset>`; notificação usa o mesmo destino da caixa (`notifPath`, repetido em `search-format.ts` e testado contra o original).
5. **Índices**: trigram no corpo dos comentários (`_search_fold(body)`) e `notifications(user_id, workspace_id)`. A media filtra primeiro pelo cliente (índice existente); sem índice trigram porque o nome do ficheiro vive noutra tabela.

## Alternativas rejeitadas

- **Mostrar media do lixo na pesquisa** a quem tem `media.read`: a pesquisa é para encontrar trabalho vivo; o lixo tem a sua vista e a sua recuperação. Pode voltar como filtro explícito se for pedido.
- **Comentários só com `media.read`** (exatamente `media_review_list`): o resultado levaria a uma página que recusa a pessoa (gate `scripts.read`) e revelaria o contexto do guião a quem não o pode ler.
- **Pesquisar todas as notificações do cliente** (vista de quem gere notificações): as notificações são pessoais; a vista de gestão (`team.read`) só mostra contagens.
- **Uma RPC por tipo**: três pedidos por tecla, três sítios para errar a autorização; manter tudo em `search_global` mantém um só ponto de decisão por cliente (FR-16-05).

## Consequência

Uma pessoa com acesso suspenso ou removido deixa de encontrar também as suas notificações antigas desse cliente (R-11). Um revisor sem `media.read` não vê media nem comentários, mas continua a ver as suas notificações.

## Rollback

Bloco no fim de `supabase/migrations/20261106060240_w10_pesquisa.sql`: repor `search_global` de `20261105202033_w9_guioes_eliminar.sql` e apagar o índice e `_sdoc_media`. Compatível com o código: o browser deixa de receber os tipos novos.
