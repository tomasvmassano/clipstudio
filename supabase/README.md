# Supabase

`migrations/` tem todas as migrações aplicadas ao projeto `dcvrhgirmijtocprfwqd`, pela ordem de versão, exportadas do próprio Supabase. Segredos estão tapados (`<TEAM_CODE_REDACTED>`, `<IMPORT_TOKEN_REDACTED>`): o repo é público.

`tests/` tem os testes de isolamento. Cada ficheiro é um bloco `DO` que cria dados de teste (workspace `ws_test_b`, utilizadores `@test.invalid`), verifica e termina sempre com `RAISE EXCEPTION 'RESULT ok=N fail=M ...'`, o que desfaz tudo. Correr com `psql "$DATABASE_URL" -f supabase/tests/<ficheiro>.sql` ou pelo SQL editor; passar = `fail=0`.

| Teste | Cobre |
| --- | --- |
| `w1_isolation.sql` | authorize(): agency A/B, cliente só A, grant, deny explícito, suspenso, expirado, anónimo, personificação, teto de convites, convite só com email confirmado, audit append-only (38 casos) |
| `w1_data_access.sql` | RLS e RPCs com login e com código: cliente A não lê nem escreve B (tabela, id, desempenho, hoje, agentes), viewer não edita, contributor não valida mas grava, owner vê A e B, código de A não chega a B (25 casos) |
