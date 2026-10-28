# Inventário do motor e da app (W0-02)

Inspecionado a 28/10/2026 lendo o código de `numeiro-engine/` e `clipstudio/src/`. **VERIFICADO** por leitura de código; o motor **não foi executado** com LLM real (falta `ANTHROPIC_API_KEY`), por isso o comportamento em execução fica **UNVERIFIED**.

## Motor (`numeiro-engine`, Python)

**Ligação.** `engine/pgdb.py` liga-se por `DATABASE_URL` (Postgres como owner, via session pooler). Ignora RLS e não tem noção de workspace. Sem `DATABASE_URL` usa SQLite local (`engine/db.py`).

**Configuração por cliente.** `clients/<slug>.yaml` (só `numeiro.yaml`): voz, léxico, ritual, formatos com máquina e intervalo de palavras, `scripts_per_day`, `hooks_per_slot`, limiares do Critic. É o preset Viral Engine do PRD §20, ainda em ficheiro e não na base.

**Pipeline** (`engine/orchestrator.py`): Strategist → HookSmith → Writer → Critic → Editor, com scouts (Repórter, Curioso, Filósofo), Analista diário e Aprendiz. Regras de escrita em `engine/prompts.py` (WRITING_GUIDE) e `engine/agents/rubric.py`.

| Escreve em | O quê | Problema |
| --- | --- | --- |
| `generated` | guiões gerados | **a app não lê esta tabela**; lê `guioes` |
| `agent_log` | passos (run_id, slot, agent, model, input, output, ms) | **sem `client_id`, `status`, `message`**: a sala dos agentes e o Hoje não veem corridas reais |
| `ideas` | ideias dos scouts | sem tenancy |
| `reels`, `comment_analysis`, `script_analysis`, `themes`, `reel_themes`, `quotes`, `meta`, `daily_reports` | dados de análise | globais, sem tenancy |

**Contrato motor → app (em falta).** Hoje os guiões chegam a `guioes` por scripts manuais (`scripts/seed_from_engine.py`, `work/day1_v4.py`). Falta: o orquestrador escrever `guioes` (id, client_id, date, n, formato, maquina, tema, hooks, corpo, fonte, critic_score, origem) e `agent_log` com `client_id`, `status`, `to_agent`, `message`, `cost_eur`, com idempotência por `run_id` + slot (AGENTS §2.8). Execução agendada às 18:00 Dubai (preset) num worker durável, não num handler HTTP (AGENTS §7).

## App (`clipstudio`, Next.js 16.4.3, React 19.3, supabase-js)

| Ficheiro | Acesso | Âmbito |
| --- | --- | --- |
| `lib/supabase.ts` | cliente com chave publishable; `DEFAULT_CLIENT = "numeiro"` | hardcoded (MIG-03) |
| `lib/data.ts` `fetchGuioes` | `from("guioes")` filtrado por `client_id` | filtro só no browser |
| `lib/data.ts` `fetchIdeas` | `from("ideas")` sem filtro | **todos os clientes** |
| `lib/data.ts` `updateGuiao` | RPC `guiao_update` com token | token partilhado |
| `lib/data.ts` `subscribeGuioes` | `postgres_changes` em `guioes` | **não dispara**: publicação vazia |
| `lib/data.ts` `checkToken` | RPC `studio_whoami` | sessão em localStorage |
| `lib/desempenho.ts` | RPC `desempenho(p_client, p_account)` | cliente vindo do browser |
| `lib/hoje.ts` | RPC `hoje_resumo(p_client)` | cliente vindo do browser |
| `lib/agents.ts` | `from("agent_feed")`, broadcast `agents:<client>`, RPC `agent_simulate` | canal público |

**Sem testes** no repo (`package.json` não tem test runner). **Sem middleware/proxy de auth.** Rotas: `/`, `/guioes`, `/teleprompter`, `/ideias`, `/desempenho`, `/agentes`.
