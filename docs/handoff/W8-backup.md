# Handoff W8 · backup (ramo `w8-backup`)

## IDs e estado proposto
| ID | Estado proposto | Falta |
|---|---|---|
| QA-15 | **parcial** | RPO/RTO de **produção** UNVERIFIED: confirmar no painel do Supabase o plano, os backups diários, o PITR e a retenção (checklist em `docs/runbooks/restauro.md` §2); ensaio num projeto Supabase real de staging; cópia fora do Supabase (dump agendado + ficheiros do Storage) |
| MIG-01 | continua **parcial** | a parte "backup não documentado" fica resolvida (runbook §5 + ensaio); "sem staging" mantém-se |

Evidência para `docs/status.md` (QA-15): `scripts/backup/drill.sh`, `docs/qa/backup-drill-2026-10-30.md`, job `backup` no CI.

## O que foi feito
- `scripts/backup/drill.sh`: numa instância descartável (recusa `*.supabase.co`/pooler, sai com 2) cria `<DRILL_DB>`,
  `_restore` e `_parcial`; aplica o bootstrap, as 84 migrações, o seed e `scripts/backup/activity.sql` (clientes `bk_a`/`bk_b`,
  dono, staff só de A, cliente A, cliente B; guiões, transições, fontes, tarefas e comentários feitos **pelas RPCs** como cada
  pessoa; metadados de objetos do Storage; volume opcional `DRILL_BULK`). Backup `pg_dump -Fc` (public + plataforma) +
  `extensions.sql` + `publication.sql`; restauro para base nova; verificação de checksums por tabela, impressão digital do
  catálogo e RPCs; restauro de um só cliente; relatório Markdown + JSON.
- `scripts/backup/fingerprint.sql`, `scope.sql`, `verify_rpc.sql`, `pre_restore.sql`, `report.py`.
- Restauro parcial (pergunta 2): **viável**. `scope.sql` filtra cada tabela pelo cliente (falha fechada para tabelas novas sem
  regra), o restauro numa base nova recria todas as FKs sem erro (export referencialmente completo), checksums iguais e
  nenhuma marca de B nem do `numeiro` no export de A. O que **não** está feito: voltar a juntar o cliente a uma produção viva
  (append-only, chaves únicas, sequências partilhadas) — manual, decisão em aberto.
- `docs/runbooks/restauro.md`: o que foi verificado, RPO por plano (UNVERIFIED), checklist do painel, o que não está na base
  (Storage, variáveis da Vercel, `DATABASE_URL` e chave do motor, configuração do Auth e chaves), três caminhos de restauro
  passo a passo, Storage, backup antes de migração destrutiva, como verificar.
- `docs/adr/ADR-0042-backup-e-restauro.md`.
- Job `backup` em `.github/workflows/quality.yml` (Postgres 17 + `postgresql-client-17` do PGDG, relatório como artefacto).

## Descobertas do ensaio (importantes)
1. **Restauro ingénuo abre a base à API.** Com os privilégios por omissão do Supabase em `public` (o bootstrap imita-os), o
   `pg_restore` deixou 84 tabelas e 238 funções (incluindo `_authorize`) com privilégios para `anon`/`authenticated`, sem
   erro. Corrigido com `scripts/backup/pre_restore.sql`; a impressão digital apanha-o.
2. `pg_dump -n public` não leva extensões (`pg_trgm` no esquema `extensions`: o restauro falhava nos índices de pesquisa),
   nem as 10 políticas de `storage.objects`/`realtime.messages`, nem a publicação `supabase_realtime`, nem buckets/cron.
3. Diferença cosmética: o Postgres reescreve `(a AND b) AND c` em restrições CHECK; a impressão digital ignora parênteses.

## Testes e resultados
- Ensaio com volume (relatório committed): 200 guiões/cliente + 1 000 000 linhas de auditoria, base de 413 MB,
  90 tabelas / 1 006 237 linhas iguais, 1424 objetos de catálogo sem diferenças, RPCs `ok=18 fail=0`;
  RTO do ensaio 33,8 s (dump 8,1 + restauro 13,3 + verificação 12,4); parcial `bk_a` 89 tabelas / 502 830 linhas iguais,
  sem fugas, RPCs parciais `ok=17 fail=0`.
- Ensaio por omissão (o do CI, 40 guiões/cliente): 2157 linhas, tudo igual, RTO 2,3–4,4 s; 18–36 s no total local.
- `DRILL_SABOTAGE=1` (apaga uma linha, abre uma tabela a anon, põe marca de B no export de A): sai com 1 e acusa as três.
- URL `*.supabase.co`: recusado (exit 2).
- `npm run -s test:db` em `t_backup`: 1355 casos, todos passaram (não há migrações novas).
- Não corri o job no GitHub (sem push). Estimativa do job `backup`: ~1–2 min (instalar o cliente 17 ~30–60 s + ensaio
  ~20–40 s), em paralelo com `quality`/`db`/`e2e`, por isso não alonga o CI. **Confirmar na primeira corrida.**

## Capacidades, flags, registos
- Sem capacidades novas, sem flags, sem migrações, sem UI nem E2E (não há funcionalidade para o utilizador).
- feature-registry: nenhuma entrada (é ferramenta de operação). access-matrix: nenhuma. workflow-registry: opcional, entrada
  "Restauro de backup" a apontar para `docs/runbooks/restauro.md` (parar escrita → restaurar → verificar → Storage → segredos →
  religar), se o coordenador quiser registar processos operacionais.
- CHANGELOG: `QA-15 (parcial): ensaio de backup e restauro reprodutível (scripts/backup/drill.sh, job backup no CI) com checksums por tabela, impressão digital do catálogo, isolamento A/B depois do restauro e restauro de um só cliente; runbook de restauro em produção (RPO de produção por confirmar). ADR-0042.`

## Decisões em aberto para o Tomás
1. Confirmar no painel: plano, backups diários (retenção, último com sucesso), PITR, se restaura para projeto novo, se inclui
   Storage, versão do Postgres (runbook §2). Sem isto o RPO fica UNVERIFIED.
2. Cópia fora do Supabase: dump agendado (onde, cifrado, retenção, quem tem acesso) e cópia dos buckets. Hoje não há.
3. Modo de manutenção para parar a escrita durante um restauro (não existe na app).
4. Ensaio num projeto Supabase de staging (o `postgres` consegue escrever em `auth.users`/`storage.objects`?).
5. Junção de um cliente restaurado de volta a produção: manter manual ou automatizar?

## Limitações
- O bootstrap imita a plataforma; GoTrue/Storage reais não entram no ensaio.
- Os tempos são de uma instância local partilhada; não são o RTO de produção (que inclui deteção, Storage, segredos e deploy).
- `realtime.messages` fica fora do export por cliente (mensagens efémeras com tópicos de vários clientes).
- A geração de atividade pelas RPCs cresce mais do que linearmente (2000 guiões/cliente não terminou em 10 min); para volume
  usar `DRILL_BULK`.
