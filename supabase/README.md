# Supabase

`migrations/` tem todas as migrações aplicadas ao projeto `dcvrhgirmijtocprfwqd`, pela ordem de versão, exportadas do próprio Supabase. Segredos estão tapados (`<TEAM_CODE_REDACTED>`, `<IMPORT_TOKEN_REDACTED>`): o repo é público.

`tests/` tem os testes de base de dados (RLS, RPCs, isolamento entre clientes). Cada ficheiro é um bloco `DO` que cria dados de teste (workspaces `ws_test_b`, utilizadores `@test.invalid`), verifica e termina sempre com `RAISE EXCEPTION 'RESULT ok=N fail=M ...'`, o que desfaz tudo; passar = `fail=0`.

Correm no CI (job `db` do workflow Qualidade) em cada PR, numa base Postgres descartável: `scripts/db/bootstrap.sql` cria o mínimo da plataforma Supabase (papéis, `auth`, `storage`, `realtime`, `cron`), aplicam-se todas as migrações por ordem e depois `tests/fixtures/seed.sql` (dados sintéticos com a forma do workspace numeiro, datas relativas a hoje). Localmente: `DATABASE_URL=postgres://postgres@localhost:5432/teste scripts/db/test.sh [ficheiro.sql ...]`. O script recusa endereços do Supabase: não se correm testes contra produção. Teste novo = ficheiro novo `w<N>_<tema>.sql` aqui; entra no CI sozinho.

| Teste | Cobre |
| --- | --- |
| `w1_isolation.sql` | authorize(): agency A/B, cliente só A, grant, deny explícito, suspenso, expirado, anónimo, personificação, teto de convites, convite só com email confirmado, audit append-only (38 casos) |
| `w1_data_access.sql` | RLS e RPCs com login e com código: cliente A não lê nem escreve B (tabela, id, desempenho, hoje, agentes), viewer não edita, contributor não valida mas grava, owner vê A e B, código de A não chega a B (25 casos) |
