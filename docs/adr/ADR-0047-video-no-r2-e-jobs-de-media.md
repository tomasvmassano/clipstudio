# ADR-0047 — Vídeo no Cloudflare R2, verificação e proxy pelo worker, exportar (W5-07)

**Data:** 2026-11-05 · **Estado:** aceite · **Requisitos:** PRD ING-01, FR-08-01, EDL-08, EDL-11; ADR-0038 (biblioteca), ADR-0046 (documento de edição), ADR-0011 (worker); AGENTS §2.8, §8.

## Contexto

O Tomás escolheu o Cloudflare R2 (2026-11-05) para os vídeos: as gravações brutas por sessão passam muito o limite de 50 MiB do Supabase gratuito, e o tráfego de saída do R2 é grátis. O worker do motor fica no Railway. O editor precisava de imagem (proxies) e de exportar.

## Decisão

1. **R2 por cliente, não por pessoa.** Flag `media.r2` (só a fase `all` conta): com ela ligada, uploads novos do cliente vão para o R2 (bucket lógico `r2` na base; real em `R2_BUCKET`). Cada versão guarda `storage_provider`, por isso as versões antigas no Supabase continuam a abrir. Teto por ficheiro 50 GiB e quota por defeito 500 GiB no R2 [pressupostos; a política do cliente pode baixar].
2. **Envio direto do browser ao R2**, com URLs pré-assinados (SigV4, `src/lib/storage/sigv4.ts`, conferido com o exemplo oficial da AWS) só para o caminho que `media_upload_begin` gerou. Acima de 256 MiB, envio por partes de 64 MiB, 3 em paralelo, cada parte repete sozinha e URLs expirados renovam-se só para essa parte (`/api/media/uploads/:id/multipart`). O SHA-256 no browser é incremental por fatias de 16 MiB para ficheiros grandes (`src/lib/sha256-incremental.ts`, ~95 MiB/s) e Web Crypto para os pequenos.
3. **A base não vê o R2, por isso não confia no browser.** "Concluir" num upload R2 só marca "chegou" e põe um job `ingest` na fila (idempotente por versão). O worker (com as chaves R2 no alojamento) lê o objeto, confere tamanho e SHA-256 com o declarado, e só então a versão passa a pronta (`checksum_verified`). Diferença marca `falhou` com o motivo. A rota confere já com HEAD que o objeto chegou inteiro, para dar resposta rápida.
4. **Jobs de media** (`media_jobs`, fechada à API): `ingest` (verificar + versão leve) e `export` (render do documento). Lease de 15 min com heartbeat a cada 30 s, cancelamento, repetição com espera crescente (30 s × 2ⁿ, até 1 h) e `dead` ao fim de `max_attempts`. Funções `media_worker_claim/heartbeat/finish` só para `engine_worker`; o browser recebe 42501. Tudo auditado (`media.upload_sent`, `media.version_ready`, `media.job_error`, `edit.export_requested`, `edit.exported`).
5. **Versão leve (proxy)** com o mesmo tempo do original (sem cortar): 540 px no lado curto, H.264 com chave a cada 1 s para procurar depressa. Fica em `<caminho da versão>/proxy.mp4`; `media_proxy_access` dá o caminho só com `media.read` e proxy pronto; link assinado de 1 h.
6. **Imagem no editor (EDL-08).** As câmaras do documento (`source.cams`: nome do ficheiro da gravação) resolvem-se para o vídeo R2 pronto mais recente do cliente com esse nome (`_edit_resolve_cams`, `edit_preview_sources`). O palco tem um `<video>` por câmara, todos no mesmo tempo da sessão (janelas → gravação, `src/lib/edit-preview.ts`); vê-se a câmara no ar e ouve-se a câmara do som. O relógio é o do editor: o vídeo só volta a posicionar quando se afasta mais de 0,25 s.
7. **Exportar (EDL-11).** `edit_export_request` (com `edit.export`, R2 ligado e todas as gravações carregadas; senão diz quais faltam) cria um job idempotente por versão do documento; repetir depois de falhar cria outro. O worker faz o render (`engine/render_doc.py`: cortes × câmaras × janelas, zoom, legendas S14/S15 e hook, volume por intervalo, música, −14 LUFS), carrega o MP4 e a versão leve, e `media_worker_finish` cria a versão nova do vídeo (pronta, checksum conferido pelo worker), passa-a a atual e avisa quem pediu. O caminho de saída é fixo por versão do documento, por isso uma repetição reescreve o mesmo objeto.

## Alternativas rejeitadas

- **Proxies no Supabase Storage** (~450 MB): cabia no gratuito mas não resolve as gravações brutas; o Tomás escolheu R2.
- **Confiar no HEAD feito pela rota** para marcar pronta: a RPC é chamável pelo browser diretamente, por isso o resultado não seria verificável. Fica no worker.
- **Chave de serviço do Supabase no Vercel**: evitada; a app continua só com a sessão de quem pede.

## Limitações

- Visuais (b-roll) ainda não entram no render: o resultado diz `skipped: ["overlays"]` e a UI avisa.
- Sem worker ligado, uploads R2 ficam "a verificar" e exports "na fila"; a UI diz que o worker não está ligado.
- Uploads interrompidos por partes retomam com um envio por partes novo (o id do envio não é guardado na base).

## Rollback

Bloco no fim de `supabase/migrations/20261105175803_w5_media_r2_jobs.sql`. Primeiro `flag_set('media.r2', <ws>, 'off')`: uploads novos voltam ao Supabase; as versões R2 já prontas continuam a abrir enquanto as chaves estiverem no servidor.
