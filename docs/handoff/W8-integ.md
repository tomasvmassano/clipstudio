# Handoff W8 · integ (centro de integrações)

Ramo `w8-integ`. ADR: `docs/adr/ADR-0039-centro-de-integracoes.md`.

## IDs tocados e estado proposto
| ID | Estado proposto | O que falta | Evidência |
|---|---|---|---|
| FR-17-16 | parcial | OAuth real (estado de ligação, reconexão e âmbitos concedidos só depois de PLAT-01..03); Drive/R2/Resend por ligar | centro em /c/[ws]/definicoes/integracoes e /integracoes; w8_integ 58/58; e2e/w8-integ.spec.ts (por correr pelo coordenador) |
| FR-15-03 | parcial | conectar e renovar indisponíveis (sem OAuth); testar só scraping e worker | revogar real e idempotente, testar real com histórico; w8_integ 58/58 |
| FR-21-01 | parcial (sem mudança de estado) | idem W7; acrescenta revogar e validade visível | w8_integ: token nunca exposto, conta não muda de cliente |
| CAP-04 | parcial | `integrations.*` deixa de estar "sem uso"; restam clipping, media, review | capacidades `integrations.read/manage/agency.read` ativas |
| PLAT-01..03, ING-01, FR-13-01 | sem mudança | aparecem no centro como "por ligar" com o motivo | — |

## Evidência
- `DATABASE_URL=... npm run -s test:db`: 35 suites, **1413 casos, todos passaram** (w8_integ.sql 58/58).
- `npm run -s test`: todos passam (novo `tests/integ-format.test.mts` 14/14).
- `npx tsc --noEmit -p .` e `npx eslint` dos ficheiros novos/alterados: limpos.
- E2E não corrido (regra da vaga): `e2e/w8-integ.spec.ts`, 11 testes (flag desligada API/menu; admin do cliente vê por ligar e ligar/renovar indisponíveis; testar scraping grava teste; revogar com motivo; gestor lê mas não testa/revoga; API gestor 42501, B em A 42501/P0002, B não vê contas de A; B pelo endereço; dono vê vista da agência; staff não vê vista da agência). O teste de revogar põe a conta `ligada` por SQL (imita o futuro serviço de OAuth) e repõe no fim.

## Capacidades
| Chave | Âmbito | Papéis | Estado |
|---|---|---|---|
| `integrations.read` (nova) | ws | workspace_owner, workspace_admin, manager | ativo |
| `integrations.manage` (existia, W6) | ws | workspace_owner, workspace_admin (já estavam) | passa a ativo; testar e revogar |
| `integrations.agency.read` (nova) | org | agency_owner | ativo |
Colaborador, revisor, leitor e código de equipa: sem acesso. Dono da agência: tudo (acesso global).

## Flag
`integrations.center` (scope ws, default `owner`). A vista da agência verifica `_flag_on('integrations.center', null)`; o item do menu da agência não tem `flag:` (o registo de flags org só devolve flags de âmbito org), a página mostra a mensagem de desligada.

## feature-registry
- Centro de integrações · `integrations.center` · rotas `/c/[ws]/definicoes/integracoes`, `/integracoes` · RPCs `integrations_overview`, `integrations_agency`, `integrations_test`, `integrations_social_revoke` · capacidades acima · ADR-0039.

## access-matrix (linhas novas)
| Ação | Dono agência | Staff agência (gestor no cliente) | Staff sem atribuição | Dono/admin cliente | Colaborador/revisor/leitor | Código de equipa |
|---|---|---|---|---|---|---|
| Ver integrações do cliente | sim | sim (manager) | não | sim | não | não |
| Testar (scraping, worker) | sim | não | não | sim | não | não |
| Revogar conta social | sim | não | não | sim | não | não |
| Vista da agência | sim | não | não | não | não | não |

## workflow-registry
- Conta social: `por_ligar` → (serviço de OAuth futuro) `ligada` → `expirada` (validade passou, derivado) → `revogada` (RPC `integrations_social_revoke`, motivo obrigatório, auditoria `integrations.social_revoked`, evento `integration.social_revoked`, pedido de purga do segredo). `revogada` não volta a `ligada` sem nova ligação OAuth (futuro).
- Teste de integração: pedido → `integration_checks` (ok/aviso/falhou/sem_dados), auditoria `integrations.tested`, dedupe 30 s.

## CHANGELOG
- W8 integ: centro de integrações por cliente (contas sociais por ligar com âmbitos e validade, revogar real com motivo e purga do segredo, recolha de métricas e motor de agentes lidos da base com testar) e vista da agência para o dono (Drive, R2 e Resend por ligar, limites das APIs, workers, estado por cliente). Registo de tipos como dados; capacidades `integrations.read`, `integrations.agency.read`, `integrations.manage` ativa; flag `integrations.center` (ADR-0039).

## Migrações
- `supabase/migrations/20261030140100_w8_integ.sql` (aditiva; rollback comentado no fim). Tabelas: `integration_types`, `integration_checks`, `integration_secret_purges` (fechadas à API). Não substitui nenhuma função existente.

## Decisões em aberto para o Tomás
1. Limiares [pressuposto]: scraping atrasado depois de 48 h, worker ativo com contacto em 30 min, conta "a expirar" a 7 dias. Estão no registo (`stale_after`) e mudam-se por migração.
2. Revogar usa `integrations.manage` (não `social_accounts.manage`); hoje os papéis são os mesmos. Confirmar.
3. Gestor (manager) lê integrações; se a agência preferir só dono/admin, retirar `('ws','manager','integrations.read')`.
4. Uma só flag para cliente e agência (pedido): no menu da agência o item aparece ao dono mesmo com a flag desligada na agência. Alternativa: flag org separada (`integrations.agency`).
5. A purga do segredo no Vault fica pendente enquanto não houver serviço de OAuth (em produção, se `vault.secrets` existir, a RPC apaga já; **UNVERIFIED** em produção: a função é `security definer` do dono das migrações, que tem de poder apagar em `vault.secrets`).

## Limitações
- Nada liga contas: sem OAuth (PLAT-01..03). "Ligar"/"renovar" sempre indisponíveis com o motivo.
- "Última sincronização" do scraping assume que só o motor escreve em `reels.updated_at` (hoje é assim).
- A vista da agência usa a primeira organização ativa do dono (como `_flag_on`/`flags_admin`).
- Sem notificações de integrações (FR-16-04) nem histórico de testes na UI além do último.
- Sem verificação em sessão real nem E2E corrido (cabe ao coordenador).
