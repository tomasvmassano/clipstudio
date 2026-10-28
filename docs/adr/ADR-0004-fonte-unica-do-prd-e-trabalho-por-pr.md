# ADR-0004 — PRD com fonte única e trabalho por PR (CHG-000)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD §28, §29.1, §33; AGENTS §10, §11, §15.

## Contexto

O PRD existia em três sítios editáveis (este repo, a pasta de referência do Tomás e um Doc no Claude) e nada impedia uma sessão de implementação de o alterar dentro de um commit de código. As sessões faziam push direto para `main`, com deploy automático em produção no Vercel, sem check obrigatório nem preview.

## Decisão

1. O PRD só é escrito neste repo. A pasta de referência passa a cópia só de leitura (sincronizada a partir do `main`) e o Doc no Claude fica arquivado.
2. O PRD só muda em alterações só de documentação que tragam `docs/changes/CHG-NNN.md`. O workflow `PRD guard` (`scripts/ci/check-prd-change.sh`) chumba o resto.
3. `main` protegido: merge só por PR, com checks obrigatórios (`prd-guard` e Vercel), sem aprovação humana obrigatória. A sessão faz merge quando está verde e o preview foi verificado.
4. Migrações Supabase em expandir/contrair: o que é aplicado antes do merge é compatível com o código no `main`; passos destrutivos vão numa migração posterior.
5. Ideias novas são captadas fora do repo e só entram por pacote CHG, para não contaminar tarefas em curso.

## Alternativas rejeitadas

- Push direto para `main` com o guard só a avisar: a violação já estaria em produção quando o aviso chegasse.
- PR com aprovação humana obrigatória: o Tomás seria o gargalo de cada tarefa e o GitHub não deixa aprovar os próprios PRs.
- Regra só no CLAUDE.md, sem CI: depende de a sessão a ler e cumprir; não há verificação.

## Consequências

- Cada tarefa demora alguns minutos a mais (PR, checks, preview). Hotfixes também.
- A base em produção pode estar à frente do código enquanto um PR espera; a regra expandir/contrair mantém isso seguro.
- O guard só bloqueia de facto depois de ligada a proteção do `main` no GitHub.

## Rollback

Desligar a regra de proteção do `main`; apagar `.github/workflows/prd-guard.yml` e `scripts/ci/check-prd-change.sh`; reverter a secção "Change workflow" do `CLAUDE.md`.
