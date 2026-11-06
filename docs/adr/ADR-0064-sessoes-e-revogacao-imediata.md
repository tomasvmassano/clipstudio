# ADR-0064 · Sessões e dispositivos, e revogação imediata no servidor

**Estado:** proposto · **Data:** 2026-11-06 · **Requisitos:** FR-14-03, R-11, CAP-06, FL-07, QA-03, QA-13 (parte de MIG-04)

## Contexto
O perfil (ADR-0024) só tinha "terminar sessão em todos os dispositivos". Não se viam as sessões abertas, não se terminava uma só, e uma sessão terminada (ou de alguém removido) continuava a passar nas RPCs até o JWT expirar (1 hora por omissão), porque o PostgREST só valida a assinatura e o prazo do token. R-11 pede que desativar, retirar atribuição ou reduzir permissões revogue o acesso a novos pedidos imediatamente.

O que o Supabase permite por SQL (verificado na imagem `supabase/postgres:17.11` da stack local): `auth.sessions` e `auth.refresh_tokens` são do `supabase_auth_admin`, mas o `postgres` (dono das funções das migrações, sem superuser) tem `select` e `delete` nelas; `refresh_tokens.session_id` tem `on delete cascade`. O JWT do Supabase Auth traz a claim `session_id`. Apagar uma linha de `auth.sessions` faz o Auth recusar o refresh dessa sessão. **Produção: UNVERIFIED** até aplicar; a migração começa por verificar estes privilégios e falha inteira se faltarem, em vez de deixar RPCs a falhar.

## Decisão
- **Sessão viva verificada a cada pedido.** `_session_alive()`: se o JWT tem `session_id`, essa sessão tem de existir em `auth.sessions`, ser da própria pessoa e não ter passado o `not_after`. `_mfa_ok` passa a exigi-lo (mesmo nome, por já ser chamado por `_authorize_base`, `_org_can`, `my_context` e `profile_update`), por isso uma sessão terminada perde tudo no pedido seguinte, incluindo RLS e storage que usam `_authorize`. JWT sem `session_id` (testes, service role) comporta-se como antes. `my_context` de uma sessão terminada responde `sessao_terminada` (42501) e a app faz `signOut` local e pede para entrar outra vez, em vez de pedir o código MFA.
- **As minhas sessões:** `my_sessions()` (só `auth.uid()`, até 100, com agente, IP, criação e última atividade = maior de `created_at`, `updated_at`, `refreshed_at`; a atual marcada pela claim). `session_terminate(id)` apaga uma sessão da própria pessoa (de outra pessoa dá P0002, como se não existisse). `sessions_terminate_others()` apaga todas menos a atual. Ambas auditadas (`security.session_terminated`, `security.sessions_terminated_others`) e visíveis no histórico de segurança.
- **"Terminar esta sessão"** usa `supabase.auth.signOut({ scope: "local" })`, que apaga a sessão no servidor e deixa as outras abertas; antes regista `security.signed_out_here` (com o `session_id`). Apagar a própria sessão pela RPC deixava o pedido de logout do browser a dar 403.
- **Offboarding (FL-07):** trigger em `workspace_access` e `agency_memberships`: quando um acesso ativo deixa de o ser (removido, suspenso ou apagado) e a pessoa fica sem nenhum acesso ativo (membro ativo da agência, ou equipa ativa de um cliente ativo e por expirar), todas as suas sessões são apagadas e fica `security.sessions_revoked` com quem fez a mudança como ator. Staff da agência retirado de um cliente mas ativo noutro não é desligado: perde só esse cliente, porque a pertença é verificada a cada pedido (testado com o mesmo JWT: 42501). Mudar o papel não termina sessões; a nova autorização vale no pedido seguinte (QA-13).
- Nome do dispositivo: função pura `parseDevice` (`src/lib/session-format.ts`), com testes; nunca falha (agente vazio ou estranho = "Dispositivo desconhecido").

## Alternativas rejeitadas
- **Só `signOut({ scope: "others" })` no browser:** não deixa terminar uma sessão escolhida, não lista nada e não corta os JWTs já emitidos; ficaria sem auditoria no servidor.
- **Encurtar o prazo do JWT:** reduz a janela mas não a fecha, e aumenta os refreshes de todos.
- **Lista de JWTs revogados:** duplicaria o que `auth.sessions` já é.
- **Terminar sessões em qualquer remoção de cliente:** desligaria staff da agência de todos os outros clientes por causa de um.
- **Bloquear a conta no Auth (`banned_until`) ao suspender:** é uma decisão de conta, não de pertença a um cliente; fica para quando houver desativação de conta (não existe hoje).

## Consequências e limites
- Mais uma leitura por chave primária em `auth.sessions` por cada `_mfa_ok` da própria pessoa (`my_context` chama-o por capacidade e cliente). Medido localmente sem diferença visível; observar em produção.
- Realtime: os canais privados autorizam pelas políticas no momento de entrar; um canal já aberto pode continuar a receber até o Realtime voltar a verificar ou o token expirar. URLs assinados já emitidos valem até ao fim do prazo (R-11: precisa de proxy ou rotação; fora deste ADR).
- O proxy da app (`getClaims`) valida o JWT localmente e não vê sessões terminadas; a barreira é a base de dados, e a app sai no primeiro `my_context` recusado ou no refresh falhado.
- O código de equipa partilhado (MIG-04) não usa sessões do Auth; continua com as suas regras até ser retirado.
- A migração vai como `20261106064909_w10_sessoes.sql`: o `supabase` CLI só a aplica (e o E2E `e2e/sessions.spec.ts` só corre) depois de ganhar o nome com data. Rollback no fim da migração (testado na stack local).
