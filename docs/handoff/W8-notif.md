# Handoff W8 · notif (notificações por evento com canais e preferências)

Ramo `w8-notif` (a partir de `w7-vaga2`). ADR-0040. Nada em produção, sem push.

## IDs e estado proposto
| ID | Estado proposto | O que falta |
|---|---|---|
| FR-15-05 | parcial | envio de email e resumo diário (dependem de domínio/envio e FR-13-01, adiado); verificação com conta real (R-15) e E2E corrido pelo coordenador |
| FR-14-02 | parcial | idioma continua só PT-PT; email/resumo pessoais guardados mas sem envio; verificação com conta real |
| FR-16-03 | parcial (mantém) | passa a ter preferências (cliente e pessoais); falta página `/notificacoes` própria e deep links confirmados para todos os tipos |
| FR-17-01, FR-17-05, TEAM-12 | sem mudança de estado | `_notify` mantém dedup, idempotência e "só quem tem acesso recebe"; obrigatórios (atribuições, erros de automação) nunca suprimidos |
| FR-13-01 | adiado (mantém) | o canal email fica indisponível com o motivo até haver domínio e envio |

## Evidência
- SQL: `supabase/tests/w8_notif.sql` **72/72**. Suite completa na base `t_notif`: **35 suites, 1427 casos, todas passam** (as 34 antigas sem mudanças: prova de que sem flag/sem preferências nada muda).
  - Catálogo cobre todos os valores de `notifications_kind_check` (lido do constraint); 5 obrigatórios; só `in_app` disponível, email e resumo com motivo.
  - Flag desligada: preferências do cliente, pessoais e silêncio gravados diretamente são ignorados (3/3 notificações criadas, 0 supressões); dedup, "quem age não se notifica" e "acesso removido não recebe" iguais; fase `owner` só afeta o dono da agência; RPCs dizem desligada / recusam com 55000.
  - Flag ligada: cliente desliga → não cria e conta 1 (repetição não conta); obrigatório do catálogo e do cliente nunca suprimido (também com silêncio); pessoa não liga o que o cliente desligou nem desliga obrigatório (22023); silêncio com fim inválido (passado, >90 dias) recusado; silêncio expirado deixa de valer; fluxo real `task_create` + `task_comment` (atribuição chega, comentário suprimido por preferência pessoal); voltar à predefinição apaga a linha; desligar a flag outra vez deixa de aplicar as preferências guardadas.
  - Negativos: cliente B não vê nem muda A (42501) e não herda o que A desligou; staff da agência sem atribuição 42501; staff atribuído a A não abre B; viewer sem `team.read` não abre as definições mas tem as pessoais; manager vê sem mudar e sem contagens da equipa; acesso removido 42501; código de equipa/anon sem execução; tabelas fechadas; `_notify`/auxiliares não executáveis pela API; todas as funções novas com `search_path`.
  - Auditoria: mudança do cliente com antes/depois (sem duplicar se repetida), preferência pessoal e silêncio auditados; nenhuma supressão gera `audit_events`.
- Unitários: `tests/notif-format.test.mts` 15/15 (adicionado ao `npm run test`; todos os outros passam). `npx tsc --noEmit` limpo; `eslint` limpo nos ficheiros tocados; `check-runtime-guards.sh` OK.
- E2E: `e2e/w8-notif.spec.ts` escrito (não corrido: stack partilhado). Cobre flag desligada (UI e API 55000), cliente-a desliga um evento e persiste/audita, obrigatórias travadas, email indisponível, staff (manager) só lê no cliente e muda as suas no perfil + silenciar/voltar a ligar, API 42501/22023, cliente-b sem acesso a A e sem cartão no perfil. Limpa as tabelas novas e a flag antes e depois.

## Capacidades e flags
- **Capacidades novas: nenhuma.** Gerir: `settings.manage` (workspace_owner, workspace_admin; dono da agência por via org). Ver as do cliente: `team.read`. Pessoais: quem tem `tasks.read` no cliente (mesma regra de quem recebe em `_notify`), só conta própria.
- **Flag nova:** `notifications.prefs` (Definições, ws, `default_stage 'owner'`). Avaliada para quem recebe em `_notify` (`_flag_on_for`) e para quem chama nas RPCs.

## Entradas para os registos
- **feature-registry** (linha `settings.manage`): acrescentar "notificações por evento (`/definicoes/notificacoes`, flag `notifications.prefs`, `notif_settings`/`notif_settings_set`: ligar/desligar por tipo e canal, obrigatórias; ADR-0040)". Nova linha de funcionalidade "Notificações pessoais no perfil (FR-14-02): `my_notif_workspaces`, `my_notif_prefs`, `my_notif_pref_set`, `my_notif_mute`; flag `notifications.prefs`; sem capacidade própria (de quem recebe)".
- **access-matrix:** Notificações do cliente — ver: quem tem `team.read`; mudar: `settings.manage`; contagens de supressão da equipa: só `settings.manage`; código de equipa: nunca. Preferências pessoais e silêncio: a própria pessoa, só nos clientes a que tem acesso (`tasks.read`); nunca de outra pessoa; obrigatórias (atribuições, erros de automação para quem tem `agents.configure`, e as marcadas pelo cliente) não se desligam.
- **workflow-registry:** "Notificação (W8, ADR-0040): evento → `_notify` → sem acesso/quem age/já existe: nada → obrigatória: cria → desligada no cliente / cliente silenciado / desligada pela pessoa: não cria, soma ao contador diário (`notification_suppressions`) → senão cria. Só a flag para quem recebe ativa as preferências. Email e resumo: preferência guardada, sem envio."
- **CHANGELOG:** "**W8 Notificações por evento** (FR-15-05, FR-14-02; ADR-0040). Catálogo dos 11 tipos com canais (na app; email e resumo diário guardados como preferência mas indisponíveis até haver envio), definições por cliente em Definições → Notificações (ligar/desligar, marcar obrigatórias; atribuições e erros de automação sempre obrigatórios) e preferências pessoais no perfil com silêncio por cliente. Aplicado no servidor em `_notify`, com supressões contadas por dia. Atrás de `notifications.prefs`. Testes: SQL w8_notif 72."

## Migrações
- `supabase/migrations/20261030150100_w8_notif_p1.sql` — flag, catálogo (canais e tipos), `notification_ws_prefs`, `notification_user_prefs`, `notification_mutes`, `notification_suppressions` (RLS ligada, `revoke all`). Rollback no fim.
- `supabase/migrations/20261030150200_w8_notif_p2.sql` — `_flag_on_for`, `_notif_suppress_reason`, **`_notify` substituída** (mesma assinatura/permissões), auxiliares JSON e as 6 RPCs. Rollback no fim (repõe o `_notify` original de W3 antes dos drops).
- Só aditivas (expand). Aplicar p1 antes de p2.

## Ficheiros
- UI: `src/app/c/[ws]/definicoes/notificacoes/page.tsx`, `src/components/notif/ws-notif-settings.tsx`, `src/components/notif/my-notif-card.tsx`; atalho em `src/app/c/[ws]/definicoes/page.tsx` (só com a flag); cartão em `src/components/profile-page.tsx` (só aparece se a flag estiver ligada em algum cliente).
- Lib: `src/lib/notif-prefs.ts` (RPCs), `src/lib/notif-format.ts` (puro) + `tests/notif-format.test.mts`; `package.json` (script `test`).
- Docs: `docs/adr/ADR-0040-notificacoes-por-evento.md`, este handoff. Testes: `supabase/tests/w8_notif.sql`, `e2e/w8-notif.spec.ts`.

## Decisões em aberto (para o Tomás)
1. **Lista de obrigatórios.** Pus como obrigatórios do catálogo: tarefa atribuída, criada automaticamente, delegada, guião atribuído e erro de automação. "Tarefa passou para outra pessoa" (`task_unassigned`) ficou desligável. Confirmar.
2. **Email por omissão.** O email está desligado por omissão e a pessoa só o pode escolher se o cliente o ligar para esse tipo. Alternativa: o cliente "permite" email por omissão e cada pessoa decide. Sem envio, não muda nada hoje.
3. **Flag avaliada para quem recebe.** Na fase `owner`, só o dono da agência sente as preferências do cliente. Ao passar a `agency`/`all`, as preferências que o cliente já gravou passam a valer para a equipa nesse momento. Confirmar que é o esperado.
4. **Retenção de `notification_suppressions`.** Só se mostram 30 dias; não há limpeza automática. Propor um job (ex.: apagar > 90 dias) quando houver agenda de limpeza.
5. **Resumo diário** ficou como canal por tipo (guardado, indisponível). Se o produto o quiser como opção única por pessoa e cliente, muda só a UI e a semântica de `digest`.

## Limitações
- Nenhum envio fora da app (email/resumo) — mostrado como indisponível com o motivo, nunca simulado.
- Sem verificação com sessão real (R-15) nem E2E corridos neste worktree (sem build; stack partilhado).
- `notif_settings` exige `team.read`: o viewer do cliente não vê a página das definições do cliente (tal como Definições), mas tem as suas preferências no perfil.
