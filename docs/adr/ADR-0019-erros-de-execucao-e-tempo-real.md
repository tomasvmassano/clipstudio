# ADR-0019 — Erros de execução contidos e canais de tempo real partilhados (W1-12)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD R-07, §25 (R-15 novo, CHG-002), AGENTS §4 e §10.

## Incidente

Ao abrir `/c/numeiro` com conta, a página inteira caiu no ecrã genérico do browser ("This page couldn't load"). Causa: o Início tem dois widgets com os guiões de hoje; cada um abria o canal de tempo real `guioes-numeiro`. O cliente Supabase devolve o mesmo canal para o mesmo nome e lança quando se juntam ouvintes depois de `subscribe()`. Não havia limite de erro, por isso um erro num efeito deitou a app abaixo. Os testes E2E correram só com o código de equipa, que não usa tempo real (usa sondagem), e não apanharam o caso.

## Decisão

1. **Gestor único de canais** (`src/lib/realtime-hub.ts`, `src/lib/realtime.ts`): um canal por nome, partilhado, com contagem de ouvintes; fecha quando sai o último; um erro ao abrir o canal ou num ouvinte não chega à página. Ninguém chama `.channel()` fora de `realtime.listen` (verificado no CI).
2. **Limites de erro em todos os níveis:** `app/error.tsx` (agência e restantes), `app/c/[ws]/error.tsx` (volta ao Início do cliente), `app/global-error.tsx` (último recurso), e um por widget no Início (`WidgetBoundary`, com `catchError` do Next). Mensagem em português, "Tentar de novo" e caminho de volta; sem detalhes técnicos; erro na consola com a referência.
3. **CI de qualidade** em cada PR: guardas de execução (canais e limites de erro), lint, tipos, testes unitários e build. Antes só corria o PRD guard e a build da Vercel.
4. **Teste do gestor** com um cliente falso que reproduz o comportamento do Supabase (o mesmo erro do incidente).

## Pendente (decisão do Tomás)

E2E com uma conta real de teste (agência e cliente) no CI: precisa de uma conta de teste e da password guardada como segredo do GitHub por ti. Sem isso, os caminhos só de quem tem conta (tempo real, painel da agência) são verificados no teu browser depois do deploy.

## Rollback

Reverter o PR. Sem migrações.
