# ADR-0042 · Backup e restauro: ensaio reprodutível, export por cliente e runbook

**Estado:** aceite (ensaio e runbook); RPO de produção por confirmar · **Data:** 2026-10-30 · **Requisitos:** QA-15 (parcial), NFR "Recuperação" (§10: RPO 24 h, RTO 8 h), MIG-01 (backup documentado), release gate "missing migration rollback/backup for destructive change" (AGENTS §10), ADR-0004

## Contexto
O PRD pede "backup e restauro de amostra: integridade e RPO/RTO medidos" (QA-15) e bloqueia o release sem backup antes de uma
migração destrutiva. Não havia nada no repo: nenhum dump, nenhum ensaio, nenhum procedimento. Não há acesso a produção nem ao
plano do Supabase, por isso o RPO real não pode ser medido aqui.

## Decisão
- **Ensaio reprodutível `scripts/backup/drill.sh`** numa instância descartável (recusa `*.supabase.co`/pooler, como
  `scripts/db/test.sh`): bootstrap + migrações + seed, atividade em dois clientes feita **pelas RPCs** como cada pessoa
  (`scripts/backup/activity.sql`), backup em `pg_dump` custom em duas partes (`public` completo; `auth`/`storage`/`cron`/
  `realtime` de onde só se restauram dados e políticas) mais `extensions.sql` e `publication.sql`, restauro para uma base nova
  e verificação: contagem + md5 das linhas ordenadas de cada tabela, impressão digital do catálogo
  (`scripts/backup/fingerprint.sql`: funções, tabelas, RLS, políticas, triggers, índices, restrições, sequências, privilégios,
  privilégios por omissão, extensões, publicação, cron) e RPCs depois do restauro (`scripts/backup/verify_rpc.sql`: isolamento
  A/B, pesquisa sem fugas, escrita sem colisão de ids, fluxo editorial, tabelas fechadas a anon). Mede tempos e escreve o
  relatório `docs/qa/backup-drill-<data>.md` (Markdown + JSON). `DRILL_SABOTAGE=1` prova que o ensaio falha quando deve.
- **Privilégios por omissão neutralizados antes do restauro (`scripts/backup/pre_restore.sql`).** O ensaio mostrou que, numa
  base com os privilégios por omissão do Supabase em `public`, o `pg_restore` deixa todas as tabelas e funções internas abertas
  a `anon`/`authenticated` sem dar erro (84 tabelas e 238 funções com privilégios diferentes da origem). Revogar esses
  privilégios por omissão do papel que restaura faz o dump repor exatamente os privilégios da origem.
- **Restauro de um cliente por export filtrado (`scripts/backup/scope.sql`).** Cada tabela de `public` com `workspace_id`/
  `client_id` filtra por cliente; `clients`/`organizations` pelo próprio; catálogos globais inteiros; dados da agência pela
  organização; dados por pessoa só das pessoas ligadas ao cliente (membros, equipa da agência e quem aparece em FKs para
  `auth.users` nas linhas exportadas); `storage.objects` pela primeira pasta do caminho. **Falha fechada:** uma tabela nova sem
  coluna de cliente nem regra faz o export parar. O ensaio restaura o export numa base nova com as FKs ligadas (prova que é
  referencialmente completo), compara checksums e procura marcas de outros clientes no export.
- **Job `backup` no CI** (Qualidade), Postgres 17 e cliente 17, em paralelo com os outros jobs; o relatório fica como artefacto.
- **Runbook `docs/runbooks/restauro.md`** com o que o Tomás tem de confirmar no painel (plano, backups diários, PITR,
  retenção, Storage), os três caminhos de restauro, Storage e segredos que não estão na base.

## Alternativas rejeitadas
- **Confiar só nos backups do Supabase:** não dá para ensaiar no CI, não cobre ficheiros do Storage (segundo a documentação,
  por confirmar) e não permite restaurar um só cliente.
- **`pg_dump` da base inteira (todos os esquemas):** num projeto Supabase os esquemas `auth`/`storage` são da plataforma; o
  destino já os tem. Restaurar a estrutura deles colide; só os dados e as políticas criadas pelas migrações são nossos.
- **Checksum com `ORDER BY` da chave primária:** equivalente; ordenar pelo texto da linha em colação `C` funciona para
  qualquer tabela e não depende da colação da base.
- **Restauro parcial direto em produção (merge):** tabelas append-only com triggers, chaves únicas e ids de sequência
  partilhados tornam o merge automático arriscado; fica manual e documentado.
- **Supabase CLI (`supabase db dump`) no ensaio:** precisa do stack Docker (como os E2E, ADR-0021) e não muda o que se verifica.

## Consequências
- QA-15 fica **parcial**: integridade e tempos do procedimento estão medidos e repetidos em cada PR; o RPO e o RTO de produção
  dependem do plano do Supabase e do processo (deteção, Storage, segredos, deploy) e estão **UNVERIFIED**.
- Uma tabela nova em `public` sem coluna de cliente obriga a decidir a regra de export em `scope.sql` (o job falha).
- Uma migração que crie objetos noutros esquemas (políticas em `storage`, publicação, cron, extensões) é coberta pela
  impressão digital; se o ensaio não a restaurar, o job falha.
- Rollback: remover o job `backup` do workflow e a pasta `scripts/backup/`. Não há migrações.

## O que falta (decisões em aberto)
1. Confirmar no painel o plano, os backups diários, o PITR e a retenção (checklist no runbook) e registar o RPO real.
2. Cópia fora do Supabase: dump agendado (onde, cifrado como, retenção) e cópia dos ficheiros do Storage. Hoje não existe.
3. Modo de manutenção na app para parar a escrita durante um restauro (não existe).
4. Ensaio de restauro num projeto Supabase real de staging (o bootstrap imita a plataforma; o papel `postgres` a escrever em
   `auth.users`/`storage.objects` num projeto real está por confirmar).
5. Merge de um cliente restaurado de volta para produção: manual por agora.
6. O export por cliente inclui a equipa da agência e dados da organização: serve para restauro, não para entregar ao cliente
   (exportação para o cliente é outra funcionalidade, com outras regras).
