# ADR-0066 — Tentativas recusadas em audit_events por um segundo pedido (W10-16)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD R-05, FR-13-05, CAP-05, CAP-07, OPS-08; AGENTS §2, §5, §10.

## Contexto

As RPCs recusam com `raise exception … errcode '42501'`. O RAISE desfaz a transação, por isso um `insert into audit_events` feito antes, no mesmo pedido, perde-se. Desde W1 (`w1_denials_to_db_log`) as recusas ficavam só como `raise log 'audit_denied …'` nos logs do Postgres: não aparecem no histórico, não se filtram, e os logs do Supabase têm retenção curta.

## Opções avaliadas

| Opção | Sobrevive ao rollback | Disponível neste stack | Notas |
|---|---|---|---|
| `dblink` / `pg_background` (transação autónoma) | sim | **não** (Supabase não oferece `pg_background`; `dblink` exigiria credenciais da base dentro de SQL) | rejeitada |
| `pg_notify` + ouvinte | **não** | **não**: NOTIFY é transacional e é descartado no rollback; Vercel não mantém ouvintes | rejeitada |
| Devolver erro "suave" (sem RAISE) e gravar | sim | sim | obrigaria a reescrever ~36 funções e o contrato de erro de todas as chamadas; rejeitada por agora |
| Logs do Postgres (RAISE LOG) lidos por um job | sim | parcial (API de logs do Supabase, retenção curta, sem SLA) | mantém-se como segunda via |
| **Segundo pedido, com a mesma sessão, a uma RPC de registo** | **sim** (transação própria) | **sim** | escolhida |

## Decisão

1. **`audit_denied_record(p_ws, p_action, p_entity, p_code, p_capability, p_via, p_correlation)`** (SECURITY DEFINER, só `authenticated`): grava `action = 'access.denied'`, `result = 'denied'`, `actor_kind = 'user'`, com `actor_user_id = auth.uid()` (a assinatura não tem ator: nunca se confia em identidade vinda do browser). Guarda a tentativa (`rpc:<função>`), a capacidade (só se existir no registo; com confirmação `verified` de que a pessoa de facto não a tem), a afiliação no momento, a via (`browser`/`api`), o id de correlação, se havia pré-visualização ativa e pseudónimos do dia do IP e do user-agent (sha256 truncado a 16 hex com o dia UTC; lidos de `request.headers` do PostgREST, nunca em claro). Id do recurso limpo a `[A-Za-z0-9_.:/-]{0,120}`; tokens nunca são enviados.
2. **Limite**: 30 por pessoa por minuto, serializado com `pg_advisory_xact_lock` por pessoa; acima disso devolve `recorded=false` e só fica o RAISE LOG.
3. **Âmbito (decisão de isolamento)**: se a pessoa tem acesso ativo ao cliente (ou é dona da agência), a linha vai para o histórico desse cliente. Se não tem (tentativa a outro cliente, staff da agência sem atribuição, cliente inexistente), vai para `workspace_id = null` com `organization_id` do cliente-alvo e `after.target_ws`; só quem tem `audit.read` da organização (dono/admin da agência) a vê. Assim o admin do cliente B nunca fica a saber o email de uma pessoa do cliente A, e ninguém de fora escreve no histórico de B. A resposta é igual nos três casos (não revela se o cliente existe).
4. **Quem chama**: o `fetch` do cliente Supabase é embrulhado em `src/lib/denials.ts` (`withDenialAudit`) no browser (`src/lib/supabase.ts`) e nas rotas `/api` (`src/lib/server/supabase.ts`). Assim cobre todas as RPCs, incluindo os ~35 módulos com o seu próprio `rpc()`, sem tocar em cada um. Só reage a respostas 401/403 de `/rest/v1/rpc/*` com `code = 42501`, só com sessão individual (JWT), nunca à própria função de registo, e não repete a mesma recusa em 60 s. No servidor espera pelo registo (máx. 1,5 s) antes de responder, porque a função serverless pode parar a seguir; no browser não bloqueia.
5. **Ver**: `audit_denials_list(p_ws, p_before, p_limit)` e o separador "Tentativas recusadas" em `/c/[ws]/historico` (quem, o quê, quando, afiliação, capacidade, "fora deste cliente"). Sem IP nem user-agent na lista.
6. O RAISE LOG existente fica em todas as funções.

## Consequências e riscos

- É uma **declaração** da sessão recusada: a pessoa pode registar recusas que não aconteceram, mas só em seu próprio nome e limitada a 30/min; `verified` mostra quando a capacidade declarada afinal existe. Uma pessoa pode **não** registar (cliente alterado, rede caída): o RAISE LOG continua a ser a fonte completa.
- Código de equipa (anónimo) não é registado (sem identidade individual); fica só no RAISE LOG.
- Recusas feitas nas rotas `/api` levam o IP do servidor (Vercel) no pseudónimo, não o do browser.
- Cabeçalhos que o Supabase passa em `request.headers` (`cf-connecting-ip`, `x-real-ip`, `x-forwarded-for`): **UNVERIFIED** em produção; sem eles os pseudónimos ficam vazios.
- O pseudónimo do IP com o dia é reversível por força bruta para IPv4; é agrupamento, não anonimização.
- Pedidos via `.from()` (tabelas com RLS) não dão 42501 por linha (o RLS filtra), por isso não geram registo; as escritas sensíveis passam por RPC.

## Rollback

Bloco no topo de `PENDING_w10_auditoria_negacoes.sql` (drop das duas funções e dos três índices). As linhas já gravadas ficam (append-only). Sem a função, o wrapper recebe 404 no segundo pedido e ignora (melhor-esforço).
