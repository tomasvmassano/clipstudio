# Inventário Supabase (W0-01, MIG-01)

Projeto `dcvrhgirmijtocprfwqd` (eu-central-1). Inspecionado a 28/10/2026 via SQL sobre `pg_catalog`, `information_schema` e advisors. Tudo aqui é **VERIFICADO** salvo indicação.

## Resumo

O esquema serve um único cliente (`numeiro`) com isolamento por convenção (`client_id`), não por autorização. Não há utilizadores no Supabase Auth (`auth.users` = 0), nem buckets de storage. A escrita da app passa por RPCs `security definer` protegidas por um código de equipa partilhado. O motor Python liga-se diretamente como owner (`DATABASE_URL`) e por isso ignora RLS.

## Tabelas

| Tabela | Linhas | Tenancy | RLS | Leitura anon/auth | Escrita |
| --- | --- | --- | --- | --- | --- |
| clients | 1 | é o tenant | sim | pública (`using true`) | só owner |
| accounts | 7 | `client_id` (null nas 7 referências... 6 referências + 1 cliente) | sim | pública | só owner |
| guioes | 30 | `client_id`, `account_id` | sim | pública | RPC `guiao_update` (código) |
| publicacoes | 0 | via `account_id` | sim | pública | só owner |
| ideas | 14 | **nenhuma** | sim | pública | só owner (motor) |
| agent_log | 27 | `client_id` | sim, sem políticas | não (só via vista) | RPC `agent_simulate`, motor |
| studio_tokens | 1 | `client_id` | sim, sem grants | não | só owner |
| reels | 388 | `account_id` (referências partilhadas) | sim, sem políticas | não | motor |
| script_analysis, comment_analysis, themes, reel_themes, quotes, generated, daily_reports, meta | vários | **nenhuma** | sim, sem políticas | não | motor |

Vistas: `agent_feed` (security definer, só leitura de campos seguros, pública); `v_guioes_hoje`, `v_top_reels`, `v_temas`, `v_guioes_virais`, `v_formatos`, `v_ideias_abertas` (security invoker, fechadas à API desde SEC-HOTFIX-001, usadas só pelo motor).

## Funções expostas na API

| Função | Definer | anon | O que confia do browser |
| --- | --- | --- | --- |
| `guiao_update(p_id, p_patch, p_token)` | sim | sim | token partilhado; deriva o cliente do token (bom) |
| `studio_whoami(p_token)` | sim | sim | token |
| `agent_simulate(p_token, p_events)` | sim | sim | token; limita 60 eventos |
| `desempenho(p_client, p_account)` | sim | sim | **`p_client` e `p_account` sem verificação** |
| `hoje_resumo(p_client)` | sim | sim | **`p_client` sem verificação** |
| `agent_log_broadcast()` | sim | não (revogado) | trigger |
| `tmp_import(token, kind, payload)` | sim | não | legado da importação de 19/10 |

Triggers: `agent_log_broadcast` (after insert em `agent_log`) envia para o canal Realtime público `agents:<client_id>`.

Realtime: a publicação `supabase_realtime` está **vazia**. A subscrição `postgres_changes` em `guioes` que a app faz nunca dispara (a atualização ao vivo de Guiões não funciona).

## Corrigido nesta inspeção

**SEC-HOTFIX-001** (migração `20261028184227`). O Supabase dá por defeito INSERT/UPDATE/DELETE/TRUNCATE a `anon` e `authenticated`. A vista `agent_feed` (security definer) deixava qualquer pessoa com a chave pública apagar ou alterar `agent_log` (provado com `DELETE ... id=-1` → 200). Revogada toda a escrita direta em tabelas e vistas, fechadas as vistas `v_*` à API, removido o EXECUTE da função de trigger e mudados os privilégios por defeito para tabelas futuras. Reteste: DELETE → 401, leituras e RPCs da app → 200.

**Migrações versionadas.** As 14 migrações aplicadas foram exportadas para `supabase/migrations/` (segredos tapados: o repo é público). Dois patches feitos por SQL direto (`hoje_resumo`, `desempenho`) foram registados como `20261028190000_drift_hoje_resumo_desempenho`.

## Em aberto (bloqueia release segundo AGENTS.md §10)

| # | Problema | Regra violada | Resolve em |
| --- | --- | --- | --- |
| 1 | Leituras públicas sem âmbito: qualquer pessoa lê guiões, ideias, contas e publicações de todos os clientes | R-01, R-02, AGENTS §2.1 | W1 (RLS por membership) |
| 2 | `desempenho` e `hoje_resumo` aceitam `p_client` do browser | AGENTS §2.2 | W1 (derivar do JWT) |
| 3 | Escrita autorizada por código partilhado, sem identidade individual nem auditoria | R-05, MIG-04 | W1 |
| 4 | `ideas` sem `client_id`/`workspace_id` | MIG-06 | W1 |
| 5 | Canal Realtime `agents:<client>` público; publicação `guioes` vazia | R-02 (realtime) | W1 |
| 6 | Editar guião validado não cria versão nem invalida validação | R-06, AGENTS §2.6 | W2 (content_versions) |
| 7 | Motor escreve como owner, sem papel de worker por workspace | AGENTS §7, R-01 | W4 |
| 8 | `tmp_import` e o seu token continuam na base (não executável pela API) | MIG-10 | remover com aprovação |
| 9 | Tabelas do motor (`reels`, `themes`, `quotes`...) sem tenancy; referências partilhadas entre clientes | R-02 | decisão: biblioteca partilhada da agência vs por workspace (ADR-0001) |
