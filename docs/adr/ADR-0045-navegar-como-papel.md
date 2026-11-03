# ADR-0045 — Navegar a app como papel ou pessoa (W1-17)

**Data:** 2026-11-04 · **Estado:** aceite · **Requisitos:** PRD BIZ-07, CAP-05; AGENTS §2.1, §2.3, §5, §15.

## Contexto

O "Ver como" (W1-16, ADR de `access_simulate`) mostrava uma lista do que um papel ou uma pessoa pode fazer, dentro de Permissões. O BIZ-07 pede mais: navegar a app como o papel X no cliente Y, só leitura, avaliado no servidor, com uma faixa persistente e auditado, sem impersonação.

## Decisão

1. **Uma linha por pessoa e cliente** em `access_previews` (alvo: papel ou pessoa; 30 minutos, máximo 2 h por restrição). Só pelas RPCs `access_preview_start` (exige `permissions.manage`), `access_preview_stop` (a própria pessoa, sempre) e `access_preview_mine`.
2. **O servidor estreita, nunca alarga.** `_authorize` passa a ser um invólucro de `_authorize_base` (a regra de sempre). Quando quem pergunta é a própria sessão e tem pré-visualização ativa nesse cliente, uma capacidade só é dada se for **de leitura** (`*.read` ou `ops.presence`), se a própria pessoa a tem e se o alvo a tem (papel: `role_capabilities`; pessoa: `_authorize_base` dela, com as negações). Tudo o resto, incluindo escrever o que o alvo poderia escrever, é recusado com o 42501 de sempre. O RLS, as RPCs e o realtime usam `_authorize`, por isso os dados que se veem também são os do alvo.
3. **Sem efeito em mais ninguém.** Só se aplica quando `p_uid = auth.uid()`: verificações sobre outras pessoas (por exemplo, quem recebe uma notificação) não mudam, nem o alvo, nem outros clientes da mesma pessoa.
4. **A app** pede `access_preview_mine` ao abrir; com pré-visualização ativa no cliente aberto, `can()` passa a ser o conjunto de capacidades do alvo (menus e botões como ele os vê), mostra uma faixa fixa com quem, até quando e "Sair da pré-visualização", e traduz as recusas por "Estás em pré-visualização: só leitura". Quando o prazo passa com a página aberta, a faixa sai e o contexto é pedido outra vez.
5. **Auditoria** `access.preview_started` / `access.preview_stopped`, com quem começa como ator.

## Alternativas rejeitadas

- **Só esconder na UI** (dados do dono, botões do alvo): mostrava dados que o alvo não vê e não cumpria "avaliado no servidor".
- **Trocar a identidade (JWT do alvo):** é impersonação, fora do âmbito do PRD, e daria escrita.
- **Lista fixa de RPCs de escrita a bloquear:** frágil; estreitar em `_authorize` cobre todas, incluindo as futuras (falha fechada).

## Limitações

Funções que verificam o dono da agência sem passar por `_authorize` (configuração ao nível da agência) não ficam estreitadas; não são do âmbito de um cliente. Páginas cujo acesso pede uma capacidade de escrita (por exemplo o teleprompter, `recording.use`) abrem pelos menus do alvo mas o servidor recusa, com a mensagem de pré-visualização.

## Rollback

Bloco no fim de `supabase/migrations/20261103203930_w1_preview_papel.sql`: repor `_authorize` com o corpo de `_authorize_base`, tirar as funções novas e a tabela. A UI sem linhas em `access_previews` volta ao comportamento de antes.
