# Handoff W8 · portal do cliente (ramo `w8-portal`)

## IDs e estado proposto
| ID | Estado proposto | O que falta | Evidência |
|---|---|---|---|
| SCALE-08 | parcial | revisão de media/vídeos pelo cliente (M08 não existe); relatórios para enviar (PDF/agendados); notificações ao cliente de itens à espera; escolher outro mês nas entregas; verificação com conta real (R-15) | portal_home/portal_block + `/c/<cliente>/portal` (W8, ADR-0041); supabase/tests/w8_portal.sql 46/46; e2e/w8-portal.spec.ts (por correr) |

Tocados sem mudar o estado (o portal só reutiliza): R-13, R-14, TEAM-10, PUB-06, FR-17-01, BIZ-01. Para PUB-06 pode acrescentar-se à evidência "aprovação também no portal do cliente (W8)".

## Evidência
- `DATABASE_URL=…/t_portal npm run -s test:db` numa base recriada: 1401 casos, todos passaram (w8_portal.sql: 46).
- `npm run -s test`: todas as suites, incluindo `tests/portal-format.test.mts` 15/15 (acrescentado ao script `test` em package.json).
- `npx tsc --noEmit -p .` limpo; `npx eslint` nos ficheiros novos/alterados limpo; `scripts/ci/check-runtime-guards.sh` OK.
- E2E **não corrido** (regra da vaga): `e2e/w8-portal.spec.ts` (clientA, staff, clientB, API). Mexe nas flags `client.portal` (numeiro e e2e-b), `pub.planning` e `perf.center` (numeiro, põe a nulo) e aprova 1 guião em revisão do numeiro, devolvendo-o a revisão no `afterAll` com `content_transition`. Pedidos criados ficam `descartada` no fim.

## Capacidades e flags
- Capacidades novas: **nenhuma** (decisão ADR-0041: `portal.view` seria redundante). Usa `scripts.read` (entrar), `scripts.approve`/`scripts.reject`, `calendar.read`, `publishing.approve`/`publishing.republish.approve` (via pub_approve), `analytics.read`, `requests.create`, `sources.read`.
- Flag nova: `client.portal` (Portal do cliente, módulo Cliente, âmbito ws, fase `owner`). Para a equipa do cliente ver, pôr a fase `all` no cliente. Os blocos de publicações e desempenho continuam a depender de `pub.planning` e `perf.center`.

## Entradas para os registos
- **feature-registry:** Portal do cliente · espaço cliente · `/c/<cliente>/portal` · flag `client.portal` · RPCs `portal_home(ws, token)`, `portal_block(ws, bloco, token)` (leitura) · ações reutilizadas: `content_transition`, `content_transition_reasoned`, `pub_approve`, `talent_request_create` · SCALE-08 · ADR-0041.
- **access-matrix:** Portal (entrar) = `scripts.read` (todos os papéis do cliente, staff atribuído, dono da agência, código de equipa com flag `all`); staff da agência sem atribuição e outro cliente: 42501. Blocos: guiões = `scripts.approve` (rejeitar `scripts.reject`); publicações = `calendar.read` + flag `pub.planning` (aprovar pela política TEAM-10; código de equipa só lê); entregas = `scripts.read` (sem valores); desempenho = `analytics.read` + flag `perf.center`; pedidos = ver `requests.create` ou `sources.read`, criar `requests.create`. Nunca a cliente: valores/moeda/pagamento/renovação/notas do contrato, custos, margens, notas internas de saúde, notas de triagem, flags, permissões, outros clientes.
- **workflow-registry:** sem estados nem transições novas. O portal dispara as transições existentes: editorial `in_review → approved | changes_requested | rejected` (content_transition[_reasoned]) e publicação `planeada → aprovada` (pub_approve), e cria `ideas(kind=talent_request, status=nova)` (evento `request.created`).

## CHANGELOG (linha sugerida)
- W8 portal do cliente (SCALE-08, ADR-0041): `/c/<cliente>/portal` atrás da flag `client.portal` com guiões e publicações à espera do cliente (aprovação pelas RPCs existentes), entregas do mês contra o contratado sem valores, resumo de desempenho e pedidos de conteúdo; cada bloco verifica a sua capacidade e vem indisponível com motivo; staff da agência vê "como o cliente vê". Migração `20261030160100_w8_portal.sql` (só funções e 1 flag).

## Migrações
- `supabase/migrations/20261030160100_w8_portal.sql` — aditiva: flag `client.portal`, funções `_portal_off`, `_portal_require`, `_portal_scripts`, `_portal_publications`, `_portal_deliveries`, `_portal_reports`, `_portal_requests` (fechadas), `portal_block`, `portal_home` (anon/authenticated). Nenhuma função existente muda. Rollback comentado no fim.

## Ficheiros
- UI: `src/app/c/[ws]/portal/page.tsx`, `src/components/portal/{portal-shared,portal-approvals,portal-status}.tsx`, item "Portal" em `src/components/app-shared.tsx`, aviso no Início `src/app/c/[ws]/page.tsx`.
- Lib: `src/lib/portal.ts`, `src/lib/portal-format.ts`; teste `tests/portal-format.test.mts`.
- Testes: `supabase/tests/w8_portal.sql`, `e2e/w8-portal.spec.ts`. ADR: `docs/adr/ADR-0041-portal-do-cliente.md`.

## Decisões em aberto para o Tomás
1. **Sem `portal.view`:** entrar no portal = ter acesso ao cliente (`scripts.read`). Se quiseres poder esconder o portal a um papel específico (p.ex. leitor), é preciso a capacidade.
2. **Pedidos visíveis a toda a equipa do cliente:** cada pessoa do cliente vê os pedidos de todos do mesmo cliente (marcados "teu" os próprios). Alternativa: só os próprios.
3. **Motivo de "Não avança":** o `status_reason` da triagem da agência é mostrado ao cliente quando o pedido é descartado; as `notas` não. Confirmar que a agência escreve esse motivo a pensar no cliente.
4. **Atrasos por culpa do cliente/agência** (BIZ-01 `late_client`/`late_agency`) ficaram fora do portal: são um pressuposto interno. Decidir se o cliente deve ver.
5. **Data de renovação e início do contrato** ficaram fora (comerciais). Se "prazos" deve incluir a renovação, é uma linha.

## Limitações
- Entregas só do mês atual; números herdam os pressupostos de BIZ-01 (mostrados na página).
- Desempenho por scraping (sem alcance/retenção), igual ao centro.
- Revisão de vídeos e relatórios exportáveis não existem (fora do que há no código).
- Não verificado com sessão real no browser (R-15): precisa do E2E e de uma passagem manual com cliente-a, staff e cliente-b.
