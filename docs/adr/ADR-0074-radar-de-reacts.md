# ADR-0074 · Radar de reacts

**Estado:** aceite · **Data:** 2026-11-09 · **Requisitos:** REACT-01..07 (PRD §47, CHG-009)

## Contexto
Reacts a takes polémicos rendem cerca de 5 vezes mais comentários do que os talking heads do Numeiro. O Tomás quer os takes dentro da app, para ver, descarregar e gravar, com avaliação da IA e decisão humana que ensina o sistema, e um agente que encontre contas novas para não ficar preso à lista inicial.

## Decisão
1. Duas tabelas por cliente, fechadas à API: `react_sources` (contas vigiadas e propostas, com origem) e `react_candidates` (vídeos com identidade única por cliente, métricas, tipo, transcrição, avaliação versionada em `ai`, estado e decisão). Leitura e decisões só por RPCs `security definer` com `ws_can` + flag `reacts.radar`.
2. O agente (tarefa agendada diária com o mecanismo de recolha de R-20) escreve só por `worker_react_source_upsert` e `worker_react_candidate_upsert` (role `engine_worker`), idempotentes pela identidade do vídeo, e nunca altera estado nem decisões humanas. `worker_react_context` dá-lhe as decisões recentes (aprendizagem) e os links a renovar.
3. Vídeo: o link do CDN não sai na lista. A rota `/api/reacts/:id/video` chama `react_video_access` com a sessão e faz stream do vídeo (Range para o leitor, `attachment` para descarregar), só de hosts dos CDNs das plataformas (sem proxy aberto). Links expirados mostram mensagem e o caminho para o original.
4. Gravar cria o guião por `content_create` (mesmas permissões, auditoria e fluxo editorial); idempotente.

## Alternativas rejeitadas
- Ficheiro semanal na pasta do Tomás: rejeitado pelo Tomás (tudo na app).
- Copiar o vídeo para o R2 na recolha: custo e retenção de vídeos de terceiros sem decisão; fica para quando um take é guardado ou gravado, se o link do CDN se mostrar curto demais (REACT-07).
- Lições automáticas a partir das decisões: as lições exigem origem `engine` com job (LRN); nesta fase o agente lê as decisões pelo contexto e as lições continuam a passar pelo fluxo LRN.

## Consequências
- O link do CDN expira em poucos dias; o agente renova-o enquanto o take está aberto ou guardado.
- Mostrar só um excerto curto e creditado do original no vídeo final (REACT-05).
- Rollback no fim da migração `20261109095944_w10_reacts.sql` (flag off primeiro; tabelas só se apagam depois de exportar as decisões).
