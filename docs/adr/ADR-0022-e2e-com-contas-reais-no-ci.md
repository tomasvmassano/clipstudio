# ADR-0022 · E2E com contas reais numa stack Supabase local, no CI

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** QA-01, QA-02, QA-16, R-13, R-14, R-15, TEAM-04

## Contexto
Os E2E de W1 a W4 eram scripts soltos fora do repositório, corriam contra produção e só com o código de equipa. Por isso não cobriam o realtime nem os caminhos da agência (foi assim que o erro de /c/numeiro passou), e os números citados no CHANGELOG não tinham nada versionado por trás. Testar com contas reais em produção pedia contas e segredos no CI de um repositório público.

## Decisão
Playwright no repositório (`e2e/`, `playwright.config.ts`) e job `e2e` no workflow Qualidade. `scripts/e2e/run.sh` levanta a stack Supabase local (`supabase start`: Postgres, GoTrue, PostgREST, Realtime, Storage reais) com as migrações e `supabase/tests/fixtures/seed.sql`, faz o build da app apontada para ela e corre os testes. O `global-setup` cria quatro contas só nessa stack (dono da agência, staff com acesso só ao A, equipa do cliente A, equipa do cliente B), um segundo cliente com um guião "secreto" e um código de equipa conhecido, e guarda a sessão de cada conta. As chaves usadas são as de demonstração da stack local, que são públicas; não há segredos no CI.

Cobertura inicial (41 testes):
- isolamento entre clientes pela UI e pela API (REST e RPC com o token da conta A contra o B);
- espaço certo para cada papel;
- cada rota principal aberta por URL e por refresh, sem página de erro e sem erros na consola, com conta de agência e com conta de cliente;
- código de equipa.

`e2e/env.ts` recusa qualquer endereço que não seja local.

## Alternativas rejeitadas
- **Contas reais em produção com segredos no GitHub:** risco num repo público e dados de teste em produção.
- **Mocks do Supabase:** não apanham o RLS, o realtime nem os erros de canal, que foram precisamente os bugs reais.

## Consequências
O job leva cerca de 6 a 8 minutos. Os E2E antigos (teleprompter, escrita de guiões, calendário) passam para aqui por fases. A "verificação com conta real" do R-15 passa a ser automática para o que os E2E cobrem; o que fica de fora continua a pedir verificação manual. Rollback: remover o job.
