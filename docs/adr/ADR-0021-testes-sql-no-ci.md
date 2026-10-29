# ADR-0021 · Testes SQL no CI numa base descartável

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** QA-02, QA-03, QA-05, QA-11, QA-13; AGENTS §10

## Contexto
Os testes de RLS e RPCs (`supabase/tests`) só corriam à mão contra produção. Isso tinha três problemas: ninguém os corria em cada PR; dependiam dos dados vivos (datas, contagens), e quatro já falhavam por desatualização sem ninguém saber; e correr testes contra produção é um risco, mesmo com rollback.

## Decisão
Job `db` no workflow Qualidade: um Postgres 17 descartável, `scripts/db/bootstrap.sql` com o mínimo da plataforma Supabase (papéis anon/authenticated/service_role, `auth.users` e `auth.uid()`, `storage`, `realtime.messages/send/topic`, um `cron.*` equivalente e a publicação `supabase_realtime`), todas as migrações por ordem, dados sintéticos (`supabase/tests/fixtures/seed.sql`) e todos os `w*.sql`. Falha o PR se uma migração não aplicar numa base limpa ou se um teste tiver `fail>0`. O script recusa endereços do Supabase.

Os testes passam a não depender do dia: o fixture põe os guiões em hoje (Dubai) e cada teste ajusta as datas de que precisa.

## Alternativas rejeitadas
- **Supabase CLI (`supabase start`) no CI:** mais fiel (GoTrue, PostgREST, Storage reais), mas ~2 min de imagens por corrida e não reproduzível no ambiente de desenvolvimento sem Docker. Fica para os E2E, que precisam da API.
- **Branches do Supabase:** custo por branch e dependência de rede/segredos no CI de um repo público.

## Consequências
Também prova que as migrações do repo reconstroem a base do zero (antes não havia garantia). O bootstrap é uma imitação: diferenças de comportamento da plataforma real (GoTrue, Storage API) não são apanhadas aqui. Rollback: remover o job.
