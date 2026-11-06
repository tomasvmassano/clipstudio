# ADR-0054 — Registo da publicação manual (W10-03)

**Data:** 2026-11-06 · **Estado:** proposta (aguarda aprovação do owner: "ainda não, mas deixa na fila") · **Requisitos:** PRD FR-12-02, FR-21-02, FR-21-04, R-16, R-18, PERF-02, PUB-04, PUB-06; AGENTS §2.6, §2.7, §6, §8.

> Número provisório: outras tarefas da mesma noite podem ocupar o 0054; renumerar ao fazer merge se for preciso.

## Contexto

Sem OAuth (PLAT-01..03 bloqueados) a equipa publica à mão na app de cada plataforma. Até aqui a publicação planeada parava em `aprovada` e a linhagem só era gravada "pelo publicador futuro", por isso as métricas desses posts ficavam como `externo` e com linhagem inferida (PERF-02 parcial). FR-12-02 pede a publicação manual com registo de URL e timestamp.

## Decisão

1. **Registar, não publicar.** `pub_record_published(p_ws, p_id, {url, published_at, media_version_id, revision}, p_reason)` regista que uma publicação **aprovada** saiu. A app não chama nenhuma API das plataformas.
2. **Verifica outra vez no momento do registo (FR-21-02, AGENTS §2.7):** publicação `aprovada` com a política cumprida para a revisão atual; versão do guião ainda a aprovada; o vídeo é a versão **atual** de um ativo do mesmo guião e está `approved` em `media_reviews`; hora não no futuro nem anterior à aprovação (5 min de folga); `revision` vista igual à atual (40001).
3. **URL pela plataforma da conta** (`_pub_post_url`, igual a `src/lib/pub-url.ts`): Instagram `reel|reels|p|tv/<shortcode>`, TikTok `@conta/video/<id>`, YouTube `shorts/<id>`, `watch?v=<id>`, `youtu.be/<id>`. Guarda o link canónico e o ID do post. Se o link trouxer a conta (TikTok, Instagram com utilizador) tem de ser a da publicação. Links curtos (vm.tiktok.com) são recusados: resolver exigiria pedir à rede a partir da base de dados.
4. **Idempotência (R-08):** índice único `(account_id, published_external_id)`; o mesmo registo outra vez devolve `replayed` sem auditoria nem eventos novos; o mesmo post noutra publicação é recusado (`url_ja_registada`). Mudar o registo de uma publicada exige **correção explícita com motivo** (3 a 500), auditada com antes/depois, contador `published_corrections`.
5. **Linhagem no momento (R-18, PERF-02, FR-21-04):** chama `_perf_record_lineage` com `correlation_id = pub:<id>`, hook pela etiqueta `hook_N` do ativo, estilo pela variante ou pela etiqueta `Sxx`, `asset_ref = media_version:<id>`, duração do ficheiro, e depois `_pub_link_lineage`. Uma linhagem inferida do mesmo post (motor) dá lugar à gravada, por isso as métricas do scraper ficam nesta publicação e contam como `sistema` (R-16: "publicada à mão a partir de um render nosso").
6. **Estado novo `publicada`**, só pela RPC (guarda com `pub.recording`). Depois de publicada nada do que foi aprovado muda nem se cancela.
7. **Correção da linhagem gravada:** `perf_lineage_guard` passa a aceitar, só dentro da correção (`pub.correcting` = id da linha), mudar post, URL, hora, hora local, ativo, duração, hook e estilo. Conteúdo, versão do guião, conta, correlation_id e modo continuam imutáveis. Uma linhagem inferida do post novo é apagada (como já fazia `_perf_record_lineage`).
8. **Capacidade:** `publishing.publish` (já registada como planeada, W6, com owner/admin) passa a `ativo` e o `manager` recebe-a, porque é quem já planeia e aprova. Revisor, colaborador e leitor não a têm (grant individual possível). Sessão individual obrigatória; o código de equipa é recusado. Flag `pub.planning`.
9. **Notificação** `publication_published` (catálogo W8) a quem planeou ou mudou, a quem aprovou a revisão e ao responsável do guião; falhar o aviso nunca desfaz o registo. Evento `publication.published` / `publication.published_corrected`; auditoria `pub.published_recorded` / `pub.published_corrected` e `perf.lineage_recorded`.

## Alternativas rejeitadas

- **Capacidade nova `publishing.record`:** separava "registar" de "publicar", mas na prática quem publica à mão é quem tem o grant de publicar, e `perf_record_lineage` já exige `publishing.publish`. Uma segunda chave duplicava a matriz sem ganho.
- **Linha de linhagem nova a cada correção** (e a antiga marcada `externo`): deixava linhas gravadas órfãs com o mesmo correlation_id e obrigava a mudar `lineage_id`, que o publicador trata como fixo.
- **Aceitar links curtos do TikTok** resolvendo o redirecionamento: chamada de rede dentro da transação e dependência de um serviço externo não oficial.
- **Guardar o ativo em `media_assets.publication_id`:** um vídeo pode sair em várias contas (AGENTS §6); a ligação fica na publicação (`published_media_version_id`).

## Pressupostos (UNVERIFIED)

- O ID que o scraper/motor (Python) usa em `reels.id` é o shortcode no Instagram (confirmado pelo fallback `instagram.com/reel/<id>/` da app e pelos dados de teste) e, no TikTok e no YouTube, o ID do vídeo. Se o motor usar outro formato nessas duas plataformas, a linhagem grava-se na mesma mas as métricas não se juntam até alinhar o ID.
- `origin_source` fica `publicador` (valor que `_perf_record_lineage` grava); `recorded_kind = user` e o ator distinguem o registo manual.

## Rollback

Bloco no fim de `20261106061032_w10_publicacao_manual.sql`: repor as funções substituídas, apagar as novas, o tipo de notificação, o índice e as checks; a capacidade volta a W6. Compatível enquanto nenhuma publicação estiver `publicada`; se houver, exportar primeiro e decidir com o owner. As colunas saem num contract posterior.
