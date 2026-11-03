# Runbook: backup e restauro (QA-15)

**Dono:** Tomás (produto/engenharia) · **Decisão:** [ADR-0042](../adr/ADR-0042-backup-e-restauro.md) · **Ensaio:** `scripts/backup/drill.sh` (último relatório em `docs/qa/backup-drill-*.md`)

Metas do PRD (§10, "Recuperação"): **RPO 24 h e RTO 8 h**, "a validar com infraestrutura real". Este runbook separa o que foi
**verificado** num ensaio local do que depende do projeto Supabase de produção e está **UNVERIFIED** (nunca acedi ao painel
nem ao plano de produção, e nada aqui foi testado contra produção).

Projeto de produção: `dcvrhgirmijtocprfwqd`, região `eu-central-1` (de `docs/inventory/supabase.md`, verificado a 28/10/2026).

## 1. O que foi verificado (ensaio local)

Numa instância Postgres descartável com o mínimo da plataforma (`scripts/db/bootstrap.sql`), todas as migrações, o seed e
atividade em dois clientes feita pelas RPCs, o procedimento da secção 4 (caminho B) restaura para uma base nova com:

- contagem e checksum iguais em todas as tabelas de `public`, `auth`, `storage`, `cron` e `realtime`;
- catálogo igual: funções (definição, `security definer`, `search_path`, privilégios), tabelas e privilégios, RLS ligada nas
  mesmas tabelas, políticas (também as de `storage.objects` e `realtime.messages`), triggers, índices, restrições, sequências,
  privilégios por omissão, extensões, publicação `supabase_realtime` e trabalhos do cron;
- a app a funcionar e isolada depois do restauro (cliente A não vê nem escreve em B, pesquisa sem fugas, escrita nova sem
  colisão de ids, fluxo editorial).

O ensaio encontrou três coisas que um restauro "ingénuo" (`pg_dump -n public` + `pg_restore`) estragaria sem dar erro e que
o procedimento abaixo já trata:

1. **Privilégios abertos à API.** Numa base nova do Supabase, o esquema `public` tem privilégios por omissão que dão tudo a
   `anon`/`authenticated`. O `pg_dump` não os revoga, por isso cada tabela fechada e cada função interna (`_authorize`, etc.)
   ficava acessível pela API. Correção: `scripts/backup/pre_restore.sql` antes do restauro; confirmar com a impressão digital.
2. **Extensões fora de `public`.** `pg_trgm`, `pgcrypto` e `citext` vivem no esquema `extensions`; sem elas o restauro falha
   nos índices de pesquisa.
3. **Objetos das migrações fora de `public`.** As políticas de `storage.objects` e `realtime.messages`, a pertença de
   `guioes` à publicação `supabase_realtime`, os buckets e os trabalhos do cron não vêm no `pg_dump -n public`.

## 2. RPO: o que depende do plano do Supabase (UNVERIFIED)

O RPO real é o intervalo entre o último ponto recuperável e o incidente. Depende do que o projeto tem ativo, e **não sei o que
está ativo**:

| Situação no painel | RPO esperado | Nota |
|---|---|---|
| Backups diários automáticos do Supabase | até 24 h (cumpre a meta à justa) | restaura o projeto inteiro para o ponto do backup |
| Point-in-Time Recovery (PITR) ativo | minutos | é um extra pago; a retenção depende do que foi contratado |
| Sem backups automáticos acessíveis | o último `pg_dump` feito por nós | então a meta de 24 h exige um dump agendado fora do Supabase |

**O Tomás tem de confirmar no painel** (Project Settings / Database / Backups, e a página de faturação):

- [ ] Plano da organização e do projeto, e se inclui backups diários automáticos.
- [ ] Retenção dos backups diários (quantos dias) e data/hora do último backup com sucesso.
- [ ] Se o PITR está ativo e com que retenção.
- [ ] Se o painel permite restaurar para um **projeto novo** (sem apagar o atual) ou só no próprio projeto.
- [ ] Se os backups do Supabase incluem os ficheiros do Storage. A documentação do Supabase diz que os backups da base não
      incluem os objetos guardados pela API de Storage (só os metadados em `storage.objects`); confirmar na documentação atual.
- [ ] Versão major do Postgres do projeto (o `pg_dump` tem de ser dessa versão ou mais recente; o CI usa 17).
- [ ] Quem na organização tem permissão para restaurar (só donos/admins).
- [ ] Se existe alguma cópia fora do Supabase (hoje não há nenhum dump agendado no repo).

Enquanto isto não estiver confirmado, **QA-15 não pode passar a `feito`**: o ensaio mede integridade e tempos do procedimento,
não o RPO de produção.

## 3. O que não está na base (e por isso nunca está num backup da base)

| O quê | Onde vive | Como se recupera |
|---|---|---|
| Ficheiros dos buckets `avatars` e `branding` (e futuros de media) | Storage do Supabase (objetos); a base só tem `storage.objects` (metadados) | cópia por bucket com a API de Storage ou o endpoint S3 do Supabase (ver 4.D) |
| Variáveis da app na Vercel: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_KEY`, `RESEND_API_KEY`, `INVITE_FROM`, `APP_URL` | Vercel (Project Settings / Environment Variables) | as duas do Supabase mudam se o projeto mudar; as outras mantêm-se |
| `DATABASE_URL` do motor Python (liga-se como owner pelo pooler) e a chave do modelo do motor | ambiente onde corre o motor | muda se o projeto mudar |
| Configuração do Auth: URL do site, URLs de redirecionamento, SMTP, fornecedores, MFA, chaves JWT | painel do Supabase (Authentication) | refazer à mão num projeto novo; num projeto novo as chaves JWT são outras, por isso todas as sessões caem e as pessoas entram de novo (as passwords vêm em `auth.users`) |
| Chaves do endpoint S3 do Storage, chaves de serviço | painel do Supabase | geradas de novo; nunca escritas no repo |
| Segredos do CI (GitHub Actions) | GitHub | não dependem da base |

O código de equipa (`studio_tokens`), as flags, as capacidades e toda a configuração dos clientes **estão** na base.

## 4. Procedimento de restauro em produção

### A. Antes de restaurar (sempre)

1. Abrir um incidente: hora de deteção, o que se perdeu ou corrompeu, quem decide.
2. Parar a escrita: parar o motor Python (worker); desligar os trabalhos do cron
   (`update cron.job set active = false where jobname in ('agent-schedule-tick','perf-tick')`); avisar a equipa.
   Não há modo de manutenção na app (decisão em aberto, ver ADR-0042).
3. Fazer já um dump do estado atual, mesmo estragado (secção 5), e guardá-lo fora do Supabase: é a única forma de recuperar o
   que for escrito entre o ponto de restauro e o incidente.
4. Escolher o caminho: **A** (restauro do Supabase, base inteira), **B** (projeto novo a partir do nosso dump) ou **C** (um só
   cliente).

### B. Caminho A: restauro gerido pelo Supabase (backup diário ou PITR)

1. No painel, escolher o ponto (backup diário ou instante do PITR) imediatamente antes do incidente.
2. Restaurar (UNVERIFIED: se for no próprio projeto, há indisponibilidade e tudo o que foi escrito depois do ponto perde-se;
   o dump do passo A.3 é a cópia disso).
3. Verificar (secção 6). Os ficheiros do Storage não voltam atrás com a base: comparar `storage.objects` com os buckets.
4. Religar o cron e o motor; registar o RPO real (`select max(at) from audit_events`) e o RTO (deteção → serviço reposto).

### C. Caminho B: projeto novo a partir do nosso dump (o procedimento do ensaio)

Pré-requisito: um dump feito como na secção 5. Usar um `pg_dump`/`pg_restore` da versão do Postgres do projeto.

1. Criar o projeto novo na mesma região (`eu-central-1`) e na mesma versão major do Postgres.
2. Extensões: correr o `extensions.sql` do dump (cria `pgcrypto`, `citext`, `pg_trgm` no esquema `extensions`; o
   `pg_cron` ativa-se no painel, como em produção).
3. `psql "$NOVO" -f scripts/backup/pre_restore.sql` (obrigatório: sem isto as tabelas ficam abertas à API).
4. Dados da plataforma: `pg_restore -d "$NOVO" --single-transaction -L platform.data.list platform.dump`
   (pessoas, MFA, buckets, metadados dos objetos, cron). **UNVERIFIED:** no Supabase, `auth` e `storage` pertencem a papéis
   da plataforma; confirmar que o papel `postgres` pode escrever em `auth.users` e `storage.objects` e, se não puder, usar o
   procedimento de migração de projeto da documentação do Supabase para esses dados. Para o cron, preferir voltar a correr
   os `cron.schedule(...)` das migrações (`agent-schedule-tick`, `perf-tick`) a copiar a tabela.
5. Esquema e dados da app: `pg_restore -d "$NOVO" --single-transaction -L public.list public.dump`
   (`public.list` = o índice do dump sem a entrada `SCHEMA - public`).
6. Políticas de `storage`/`realtime`: `pg_restore -d "$NOVO" --single-transaction -L platform.policy.list platform.dump`.
7. Publicação do realtime: `psql "$NOVO" -f publication.sql`.
8. Verificar (secção 6) **antes** de apontar a app.
9. Storage: copiar os ficheiros (4.D).
10. Segredos e configuração (secção 3): Auth (URLs, SMTP, MFA), variáveis da Vercel, `DATABASE_URL` do motor. Fazer deploy.
11. Religar o motor e o cron; teste com sessão real (agência e cliente) nas rotas principais; registar RPO e RTO.

### D. Ficheiros do Storage

Os buckets que as migrações criam são `avatars` (caminho `<user_id>/...`) e `branding` (caminho `<cliente>/...`).

1. Listar no projeto de origem os objetos por bucket e comparar com `storage.objects` (contagem e `metadata->>'size'`).
2. Copiar bucket a bucket com o endpoint S3 do Supabase (por exemplo `rclone` ou `aws s3 sync` com as chaves S3 do painel,
   UNVERIFIED nesta conta) ou com a API de Storage. Os caminhos têm de ficar iguais: as políticas usam a primeira pasta.
3. Voltar a contar no destino. Um objeto com linha em `storage.objects` e sem ficheiro aparece na app como imagem em falta.

Hoje não há nenhuma cópia dos ficheiros do Storage fora do Supabase (decisão em aberto, ADR-0042).

### E. Caminho C: um só cliente

Para recuperar um cliente sem mexer nos outros (por exemplo, apagaram-se dados de um cliente):

1. `psql "$ORIGEM" -v ws=<cliente> -f scripts/backup/scope.sql > scope.tsv` numa **cópia** restaurada do backup (nunca em
   produção diretamente se não for preciso), e exportar cada linha com `COPY (consulta) TO STDOUT` (como o ensaio faz).
2. Restaurar numa base lateral (pré-dados do `public.dump`, carga, sequências, pós-dados). O ensaio prova que isto funciona
   e que o export não leva dados de outro cliente.
3. Copiar de volta para produção **à mão**, tabela a tabela, só o que falta. Não está automatizado: há tabelas
   append-only (auditoria, tarefas, versões aprovadas) com triggers que recusam alterações, chaves únicas e ids de sequência
   partilhados. Decisão em aberto (ADR-0042).

## 5. Fazer um backup nosso (fora do Supabase)

Com a ligação direta (não o pooler em modo transação) e um `pg_dump` da versão do projeto:

```sh
pg_dump "$PROD" -Fc -n public -f public.dump
pg_dump "$PROD" -Fc -n auth -n storage -n cron -n realtime -f platform.dump
psql "$PROD" -Atc "select format('create extension if not exists %I with schema %I version %L;', extname, extnamespace::regnamespace, extversion) from pg_extension where extname <> 'plpgsql'" > extensions.sql
psql "$PROD" -Atc "select format('alter publication %I add table only %I.%I;', pubname, schemaname, tablename) from pg_publication_tables" > publication.sql
psql "$PROD" -f scripts/backup/fingerprint.sql > fingerprint.txt
```

Os scripts do repo recusam endereços `*.supabase.co`/pooler de propósito; estes comandos correm-se à mão, por quem tem acesso,
e o dump fica num sítio cifrado e fora do Supabase. **Nunca** se faz commit de um dump (AGENTS §14).

**Migração destrutiva (bloqueia o release sem isto, AGENTS §10):** antes de aplicar em produção uma migração de contração
(drop, rename, restrição mais apertada; ADR-0004), fazer o backup desta secção, guardar a impressão digital, anotar no PR
onde está o dump e confirmar que o ensaio (`scripts/backup/drill.sh`) passa com a migração.

## 6. Verificar um restauro

1. `psql "$NOVO" -f scripts/backup/fingerprint.sql | sort > novo.txt` e comparar com a impressão digital da origem
   (`diff`): tem de ser vazia (com o caminho A, comparar com a de um dump anterior e esperar só as diferenças das migrações
   aplicadas desde então).
2. Contagens e checksums por tabela: `psql -f scripts/backup/scope.sql` dá as consultas; o ensaio mostra como se calculam.
3. Privilégios: `select relname, relacl from pg_class where relnamespace = 'public'::regnamespace and relacl::text like '%anon=%'`
   tem de devolver exatamente o mesmo na origem e no destino (a impressão digital já o compara; isto é a verificação à mão).
4. Sessão real: dono, staff com um só cliente, cliente A e cliente B; cliente A não vê B (pesquisa, URL direta).
5. Registar no incidente: ponto de restauro, RPO real, RTO real, diferenças encontradas.

## 7. Tempos medidos (ensaio, não produção)

Ver o relatório mais recente em `docs/qa/`. No ensaio de 30/10/2026 (Postgres 16 local, ~413 MB, ~1 milhão de linhas) o
backup + restauro + verificação levou ~34 s. Isto mostra que o procedimento cabe folgadamente nas 8 h para bases desta ordem de
grandeza, mas o RTO de produção inclui também deteção, decisão, Storage, segredos e deploy, e **não foi medido**.
