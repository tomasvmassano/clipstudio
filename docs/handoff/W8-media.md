# Handoff W8 · media (biblioteca de media)

Ramo `w8-media` (a partir de `w7-vaga2`). ADR-0038. Nada em produção, sem push.

## IDs e estado proposto
| ID | Estado proposto | O que falta |
|---|---|---|
| FR-08-01 | parcial | E2E corrido pelo coordenador (stack local com storage real) e verificação com sessão real (R-15); ficheiros > 100 MB precisam de hash incremental e multipart (R2) |
| FR-08-02 | parcial | verificação com sessão real; "pastas" são filtros (campanha, formato, estado, tipo, etiqueta) e pesquisa, sem pastas físicas |
| FR-08-03 | parcial | verificação com sessão real; partilha só da versão atual |
| FR-08-04 | parcial | verificação com sessão real; take só selecionável quando o guião tem takes |
| FR-08-05 | parcial | **sem antivírus** (decisão em aberto); retenção automática (job) não existe; limite real por ficheiro depende do plano Supabase (verificar) |
| FR-08-06 | parcial | eliminação automática no fim do prazo e limpeza agendada de órfãos (job futuro); custo em euros indisponível (sem preço por GB) |
| ING-01 | parcial (de "por começar") | finais em Supabase Storage atrás de adaptador (R2 por fazer); bruto no Drive só como link externo; retenção de proxies/variantes rejeitadas (7-14 dias) não aplicável ainda (não há proxies) |

## Evidência
- SQL: `supabase/tests/w8_media.sql` **117/117**. Suite completa na base `t_media` (recriada): **todas as suites passam, 1472 casos** (as antigas sem mudanças).
  - Flag desligada 55000 (staff); fase owner: o dono da agência vê.
  - Negativos: cliente B 42501 em A (ler, editar, pedir acesso, revogar link), cliente inexistente 42501, staff sem atribuição 42501, staff de A em B 42501, código de equipa 42501, troca de cliente com id de A → P0002, removido 42501, leitor não carrega nem descarrega, colaborador não partilha nem vê órfãos, admin do cliente e staff não mudam a quota.
  - Storage (políticas reais em `storage.objects`): só quem registou escreve no seu caminho pendente; caminho escolhido pelo browser recusado; upload expirado não escreve; A não escreve no pendente de B; sem autorização curta a versão pronta não se lê; a autorização é da pessoa (outro utilizador não a usa); expirada deixa de valer; B não vê objetos de A; anónimo só lê o objeto do link aberto e deixa de ler ao revogar; sem `media.manage` não apaga; com `media.manage` só apaga órfãos e ativos com eliminação pedida.
  - Fluxo: caminho `<ws>/<asset>/<versão>/<nome-sanitizado>` (`../../Vídeo Final (1).MP4` → `video-final-1.mp4`), registo idempotente, tipo/MIME/tamanho/SHA-256/quota (com reservas)/tipos da política, confirmação sem objeto P0002 (fica pendente), tamanho diferente e checksum diferente → falhou (persistido), sem checksum do servidor → pronta "declarado", versão 4 passa a atual, histórico, versões e ativos imutáveis/sem delete, `asset.uploaded` por versão pronta, etiquetas normalizadas, PT409, ligações a guião/take de outro cliente/guião recusadas, filtros e pesquisa, link externo (https, versão 2, sem URL assinado), partilha (validade, token só na resposta, hash, revogar, expirar, adulterado), lixo com prazo da política, revoga links, não se edita, recuperar, órfãos listados, `APAGAR` obrigatório, purge em 2 fases (nada fica eliminado enquanto o objeto existir), lápide, auditoria das 10 ações e da partilha.
- Unitários: `tests/media-format.test.mts` 17/17 (no `npm run test`; os outros passam). `npx tsc --noEmit` limpo; `eslint` limpo nos ficheiros tocados; `scripts/ci/check-runtime-guards.sh` OK. 34 funções novas, todas com `search_path`.
- E2E: `e2e/w8-media.spec.ts` escrito, **não corrido** (stack partilhado, sem build). Usa o storage real: flag desligada (UI e 55000), cliente A carrega PNG pela UI com a primeira tentativa de envio abortada (tem de repetir sozinho) e confere caminho, `pronta`, SHA-256 conferido e tamanho no `storage.objects`; pesquisa por etiqueta e pré-visualização com URL `/object/sign/` e auditoria; API: A não assina sem `media_access`, B não assina, caminho forjado recusado, B 42501/P0002; cliente B na página e nas rotas (403/404); staff cria link, abre sem sessão (302 → 200), revoga (404); lixo → recuperar → apagar com APAGAR (objeto desaparece do storage); órfão abandonado limpo pela UI. Deixa linhas de teste no stack local (ativos não se apagam), com títulos `e2e<n>`.

## Capacidades e flags
- Novas: `media.read` (B; workspace_owner, workspace_admin, manager, contributor, reviewer, viewer), `media.manage` (A; workspace_owner, workspace_admin), `media.policy.manage` (A, org; agency_owner).
- Passam de W5 a `ativo` (papéis que já tinham): `media.upload` (owner, admin, manager, contributor), `media.download` (+ reviewer), `media.share` (owner, admin, manager).
- Código de equipa: nenhuma (não está em `legacy_can`).
- Flag nova: `media.library` (Biblioteca, ws, `default_stage 'owner'`). Menu: "Biblioteca" em Dia a dia (`cap: media.read`, `flag: media.library`); o "Em breve · Biblioteca" some com a flag.

## Entradas para os registos
- **feature-registry:** "Biblioteca de media (`/c/[ws]/biblioteca`, flag `media.library`, ADR-0038): ativos por cliente com versões imutáveis, envio com progresso e retentativa (`/api/media/uploads`, `media_upload_begin/target/complete/abandon`), links externos (`media_link_add`), filtros e pesquisa (`media_library`, `media_asset`, `media_asset_save`), pré-visualizar/descarregar por URL assinado curto (`/api/media/versions/:id/url`, `media_access`), partilha (`media_share_create/revoke`, `/api/media/share/:token`, `media_share_open`), lixo (`media_trash/restore`), órfãos e eliminação definitiva (`/api/media/purge`, `media_purge_begin/finish`), política por cliente (`media_policy_save`). Capacidades `media.read|upload|download|share|manage`, `media.policy.manage`."
- **access-matrix:** Biblioteca — ver e pré-visualizar: `media.read` (todos os papéis do cliente); carregar, versão nova, editar, lixo/recuperar, links externos: `media.upload`; descarregar: `media.download`; partilhar/revogar: `media.share`; órfãos e eliminação definitiva: `media.manage`; tipos/tamanho/quota/lixo do cliente: `media.policy.manage` (só dono da agência); código de equipa: nada; link de partilha: quem tiver o token, só aquela versão, até expirar ou ser revogado. Storage: as políticas do bucket `media` repetem a decisão (inserir só no caminho pendente próprio; ler só com autorização de 60 s criada pelas RPCs; apagar só órfãos/eliminação pedida com `media.manage`).
- **workflow-registry:** "Versão de media (W8, ADR-0038): `pendente` (registada, 24 h) → `pronta` (objeto com tamanho e MIME declarados; SHA-256 conferido no servidor ou declarado) | `falhou` (diferença, desistência) ; `pendente` expirada e `falhou` = órfãs → `apagada` (objeto removido pela API, com `APAGAR`). Ativo: `ativo` ↔ `no_lixo` (prazo da política) → `eliminado` (lápide; só com `media.manage` e `APAGAR`, quando já não há objetos). Eventos: `asset.uploaded`, `asset.linked`, `asset.trashed`, `asset.restored`, `asset.purged`."
- **CHANGELOG:** "**W8 Biblioteca de media** (FR-08-01..06, ING-01 parcial; ADR-0038). Nova página Biblioteca por cliente: carregar vídeo, áudio, imagens, miniaturas, legendas e documentos com progresso e retentativa automática, caminho gerado no servidor e SHA-256 conferido; versões imutáveis com histórico e substituição; ligação a guião, take, publicação e campanha; filtros e pesquisa; pré-visualização e descarga por links curtos; links de partilha com validade, revogação e auditoria; lixo recuperável, órfãos e eliminação definitiva com confirmação; tipos, tamanho e quota por cliente (dono da agência). Bruto do Drive como link externo. Supabase Storage (bucket privado `media`) atrás de um adaptador para R2. Sem antivírus (indicado na página). Atrás de `media.library`. Testes: SQL w8_media 117, unitários media-format 17."

## Migrações
- `supabase/migrations/20261030130100_w8_media_p1.sql` — capacidades, flag, bucket `media` (privado, 50 MiB, lista de MIME), `media_assets`, `media_versions`, `media_policies`, `media_shares`, `media_access_grants` (RLS ligada, `revoke all`), guardas, auxiliares, `_media_object_can` e 3 políticas novas em `storage.objects` (só `bucket_id = 'media'`).
- `supabase/migrations/20261030130200_w8_media_p2.sql` — leitura, metadados, links, upload, acesso, lixo.
- `supabase/migrations/20261030130300_w8_media_p3.sql` — partilha, purge, política.
- Só aditivas; não substituem nenhuma função existente. Aplicar por ordem. Rollback comentado no fim de cada uma (o bucket só sai depois de esvaziado pela API).
- `scripts/db/bootstrap.sql`: **sem mudanças** (o `storage` mínimo chegou).

## Ficheiros
- Página: `src/app/c/[ws]/biblioteca/page.tsx`; componentes `src/components/media/{media-library,media-asset-sheet,media-policy,media-shared}.tsx`; menu em `src/components/app-shared.tsx`.
- Rotas: `src/app/api/media/uploads/route.ts`, `uploads/[id]/target/route.ts`, `uploads/[id]/complete/route.ts`, `versions/[id]/url/route.ts`, `purge/route.ts`, `share/[token]/route.ts`; `src/proxy.ts` (só acrescenta `/api/media/share/` às rotas públicas).
- Adaptador: `src/lib/storage/{types,supabase,index}.ts`. Servidor: `src/lib/server/media.ts`. Cliente: `src/lib/media.ts`, `src/lib/media-format.ts` (+ `tests/media-format.test.mts`, `package.json`).
- Docs: `docs/adr/ADR-0038-biblioteca-de-media.md`, este handoff. Testes: `supabase/tests/w8_media.sql`, `e2e/w8-media.spec.ts`.

## Decisões em aberto (para o Tomás)
1. **Limite por ficheiro / plano Supabase.** O bucket ficou com 50 MiB (limite do plano gratuito) e é o teto de todos os clientes (lido de `storage.buckets.file_size_limit`). Verificar o plano de produção e o limite global do projeto (Storage → Settings); para subir, mudar o plano e o `file_size_limit` do bucket `media` — a app adapta-se sozinha. Também `MEDIA_VERIFY_MAX_BYTES` (100 MiB por defeito; a rota de confirmação tem `maxDuration = 60`).
2. **Antivírus.** Não há serviço; a página diz "Sem antivírus". Opções: ClamAV num worker, serviço do fornecedor de storage (R2 não tem nativo), ou aceitar o risco para ficheiros internos. Até decidir, FR-08-05 fica parcial.
3. **Quota e lixo por defeito** [pressupostos]: 5 GiB por cliente, 30 dias no lixo, 24 h para concluir um upload. Confirmar ou ajustar por cliente na página (dono da agência).
4. **Quem muda a quota:** pus só o dono da agência (é custo da agência). Alternativa: dar `media.policy.manage` também a quem gere a agência.
5. **Eliminação automática** no fim do prazo do lixo e limpeza agendada de órfãos: não existe; precisa de um job com credenciais de serviço (o Supabase não apaga objetos por SQL). Até lá, manual com `APAGAR`.
6. **Checksum "conferido":** a rota relê o objeto com a sessão de quem carregou; quem carrega podia chamar a RPC de confirmação diretamente com o hash que declarou. Serve contra corrupção, não contra o próprio autor. Um worker com credenciais (R2) deve recalcular. Aceitar por agora?
7. **Preço por GB** para mostrar custo em euros (FR-08-06 "custos"): hoje só bytes; o custo aparece como indisponível.
8. **Migração para R2:** implementar `R2MediaStorage` (PUT pré-assinado, URLs assinados, `GetObject`, `DeleteObjects`), mover objetos e mudar `storage_bucket`/políticas; os caminhos mantêm-se.

## Limitações
- Sem verificação com sessão real (R-15) nem E2E corridos neste worktree.
- SHA-256 no browser lê o ficheiro inteiro para memória (até ao teto atual, ok).
- Sem miniaturas geradas, transcodificação nem proxies (jobs separados, AGENTS §8); pré-visualização é o próprio ficheiro.
- Partilha só da versão atual no momento de criar; o link continua a abrir essa versão mesmo depois de uma versão nova.
- O link de partilha abre num URL do storage (domínio do Supabase), com 5 min.
