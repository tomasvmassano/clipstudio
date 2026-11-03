#!/usr/bin/env bash
# scripts/backup/drill.sh: ensaio reprodutível de backup e restauro (PRD QA-15, ADR-0042).
# Numa instância Postgres descartável: aplica bootstrap + migrações + seed, gera atividade em 2 clientes, faz backup
# (pg_dump custom), restaura para uma base nova e verifica integridade (contagens e checksum por tabela, catálogo:
# funções, políticas, triggers, RLS, índices, restrições, sequências, privilégios, publicação realtime, cron) e que as
# RPCs continuam a funcionar e isoladas. Depois faz o export e restauro de um só cliente (bk_a) e prova que não leva
# dados de outro cliente. Mede tempos (RTO do ensaio) e escreve um relatório Markdown com o JSON do resultado.
#
# Uso: DATABASE_URL=postgres://postgres@localhost:5432/postgres scripts/backup/drill.sh
#   DATABASE_URL  ligação de administração a uma instância descartável (precisa de CREATEDB). Recusa *.supabase.co / pooler.
#   DRILL_DB      prefixo das bases criadas (omissão: backup_drill → backup_drill, _restore, _parcial). São apagadas e recriadas.
#   DRILL_ROWS    guiões por cliente na atividade de amostra (omissão: 40; fontes e tarefas = metade).
#   DRILL_BULK    linhas extra de auditoria sintética (omissão: 0), só para medir tempos com mais volume.
#   REPORT        caminho do relatório (omissão: docs/qa/backup-drill-<data UTC>.md). REPORT=- não escreve relatório.
#   WORK          pasta para os ficheiros de backup (omissão: pasta temporária, apagada no fim salvo KEEP=1).
#   KEEP=1        mantém as bases e a pasta de trabalho no fim.
#   DRILL_SABOTAGE=1  prova que o ensaio apanha falhas: depois do restauro apaga uma linha, abre uma tabela a anon e
#                 põe uma marca de B no export de A. O ensaio TEM de terminar com falhas (não escreve relatório).
# Sai com 0 só se todas as verificações passarem.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${DATABASE_URL:?define DATABASE_URL para uma instância descartável}"
case "$DATABASE_URL" in *supabase.co*|*supabase.com*|*pooler*) echo "::error::Recuso correr contra um projeto Supabase real."; exit 2;; esac
export PGTZ=UTC PGOPTIONS="-c client_min_messages=error"
DRILL_DB=${DRILL_DB:-backup_drill}
DRILL_ROWS=${DRILL_ROWS:-40}
DRILL_BULK=${DRILL_BULK:-0}
REPORT=${REPORT:-docs/qa/backup-drill-$(date -u +%F).md}
KEEP=${KEEP:-0}
WS=bk_a                                   # cliente do restauro parcial
LEAK='bk_b|zebraquantica|bk-cli-b@|numeiro' # marcas de outros clientes que não podem aparecer no export de bk_a
if [ -z "${WORK:-}" ]; then WORK=$(mktemp -d); CLEAN_WORK=1; else mkdir -p "$WORK"; CLEAN_WORK=0; fi

url() { printf '%s' "$DATABASE_URL" | sed -E "s#^([a-z]+://[^/]*/)[^?]*#\1$1#"; }
SRC=$(url "$DRILL_DB"); DST=$(url "${DRILL_DB}_restore"); PART=$(url "${DRILL_DB}_parcial")
q() { psql "$1" -X -q -v ON_ERROR_STOP=1 "${@:2}"; }
now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }
fail=0; problems=()
problem() { fail=1; problems+=("$1"); echo "::error::$1"; }
step() { echo "── $*"; }
recreate() { q "$DATABASE_URL" -c "drop database if exists \"$1\" with (force)" -c "create database \"$1\""; }
cleanup() {
  if [ "$KEEP" != 1 ]; then
    for d in "$DRILL_DB" "${DRILL_DB}_restore" "${DRILL_DB}_parcial"; do q "$DATABASE_URL" -c "drop database if exists \"$d\" with (force)" >/dev/null 2>&1 || true; done
    [ "$CLEAN_WORK" = 1 ] && rm -rf "$WORK"
  fi
}
trap cleanup EXIT

# pg_dump mais antigo do que o servidor recusa-se a correr: falhar já com uma mensagem clara
srv_major=$(q "$DATABASE_URL" -Atc "show server_version_num" | cut -c1-2)
dump_major=$(pg_dump --version | grep -oE '[0-9]+' | head -1)
if [ "$dump_major" -lt "$srv_major" ]; then echo "::error::pg_dump $dump_major é mais antigo do que o servidor $srv_major (instala postgresql-client-$srv_major)."; exit 2; fi

apply_platform() { q "$1" -f scripts/db/bootstrap.sql >/dev/null; [ -f "$WORK/extensions.sql" ] && q "$1" -f "$WORK/extensions.sql" >/dev/null; return 0; }

# ── 1. base de origem: plataforma mínima, migrações, seed e atividade em 2 clientes ──
step "origem: $DRILL_DB"
t0=$(now)
recreate "$DRILL_DB" >/dev/null
apply_platform "$SRC"
for m in supabase/migrations/*.sql; do
  if ! sed -E 's/^\s*create extension if not exists pg_cron[^;]*;//I' "$m" | q "$SRC" >/dev/null 2>"$WORK/mig.err"; then
    echo "::error file=$m::migração falhou"; cat "$WORK/mig.err"; exit 1
  fi
done
q "$SRC" -f supabase/tests/fixtures/seed.sql >/dev/null
q "$SRC" -v rows="$DRILL_ROWS" -v bulk="$DRILL_BULK" -f scripts/backup/activity.sql >/dev/null
q "$SRC" -c "analyze" >/dev/null
t_prepare=$(secs "$t0" "$(now)")
migrations=$(ls supabase/migrations/*.sql | wc -l)

# checksum por tabela: contagem e md5 das linhas ordenadas (texto da linha, colação C, independente da ordem física)
checksum_sql() { # $1 = ficheiro de âmbito (tbl<TAB>consulta), $2 = "filtered" usa a consulta, "table" lê a tabela inteira
  while IFS=$'\t' read -r tbl sel; do
    [ "$2" = table ] && sel="select * from $tbl"
    printf "select '%s' || '|' || count(*) || '|' || coalesce(md5(string_agg(x::text, E'\\\\n' order by x::text collate \"C\")), '-') from (%s) x;\n" "$tbl" "$sel"
  done < "$1"
}

# ── 2. backup ──
step "backup"
t0=$(now)
pg_dump "$SRC" -Fc -n public -f "$WORK/public.dump"
pg_dump "$SRC" -Fc -n auth -n storage -n cron -n realtime -f "$WORK/platform.dump"
# extensões: vivem fora de public (esquema extensions) e o pg_dump -n public não as cria
q "$SRC" -Atc "select format('create extension if not exists %I with schema %I version %L;', extname, extnamespace::regnamespace, extversion) from pg_extension where extname <> 'plpgsql' order by 1" > "$WORK/extensions.sql"
# a pertença à publicação do realtime é da base, não do esquema: o pg_dump -n não a leva
q "$SRC" -Atc "select format('alter publication %I add table only %I.%I;', pubname, schemaname, tablename) from pg_publication_tables order by 1" > "$WORK/publication.sql"
t_dump=$(secs "$t0" "$(now)")
# manifesto do backup (o que o restauro tem de reproduzir)
t0=$(now)
q "$SRC" -f scripts/backup/scope.sql > "$WORK/scope_full.tsv"
checksum_sql "$WORK/scope_full.tsv" filtered > "$WORK/checksum_full.sql"
q "$SRC" -At -f "$WORK/checksum_full.sql" | sort > "$WORK/src.checksums"
q "$SRC" -f scripts/backup/fingerprint.sql | sort > "$WORK/src.fingerprint"
t_manifest=$(secs "$t0" "$(now)")
db_bytes=$(q "$SRC" -Atc "select pg_database_size(current_database())")

# Entradas do dump da plataforma: dados das tabelas que a app usa (pessoas, MFA, buckets, metadados de objetos, cron,
# realtime) e as políticas que as migrações criam em storage/realtime. A estrutura destas tabelas vem da plataforma
# (bootstrap.sql aqui, o próprio Supabase num projeto novo).
pg_restore -l "$WORK/platform.dump" | grep -E '(TABLE DATA|SEQUENCE SET) (auth|storage|cron|realtime) ' > "$WORK/platform.data.list"
pg_restore -l "$WORK/platform.dump" | grep -E ' POLICY (storage|realtime|auth|cron) ' > "$WORK/platform.policy.list" || true
# o esquema public já existe numa base nova (e num projeto Supabase novo): restaurar tudo o resto
pg_restore -l "$WORK/public.dump" | grep -vE '^[0-9]+; [0-9]+ [0-9]+ SCHEMA - public ' > "$WORK/public.list"

# ── 3. restauro completo para uma base nova ──
step "restauro: ${DRILL_DB}_restore"
t0=$(now)
recreate "${DRILL_DB}_restore" >/dev/null
apply_platform "$DST"
q "$DST" -f scripts/backup/pre_restore.sql >/dev/null
pg_restore -d "$DST" --exit-on-error --single-transaction -L "$WORK/platform.data.list" "$WORK/platform.dump"
pg_restore -d "$DST" --exit-on-error --single-transaction -L "$WORK/public.list" "$WORK/public.dump"
[ -s "$WORK/platform.policy.list" ] && pg_restore -d "$DST" --exit-on-error --single-transaction -L "$WORK/platform.policy.list" "$WORK/platform.dump"
q "$DST" -f "$WORK/publication.sql" >/dev/null
if [ "${DRILL_SABOTAGE:-0}" = 1 ]; then
  REPORT=-
  q "$DST" -c "set session_replication_role = replica" -c "delete from public.tasks where id = (select id from public.tasks order by id limit 1)" -c "grant select on public.workspace_access to anon" >/dev/null
fi
q "$DST" -c "analyze" >/dev/null
t_restore=$(secs "$t0" "$(now)")

# ── 4. verificação ──
step "verificação"
t0=$(now)
q "$DST" -At -f "$WORK/checksum_full.sql" | sort > "$WORK/dst.checksums"
q "$DST" -f scripts/backup/fingerprint.sql | sort > "$WORK/dst.fingerprint"
diff "$WORK/src.checksums" "$WORK/dst.checksums" > "$WORK/checksums.diff" || problem "restauro: $(grep -c '^[<>]' "$WORK/checksums.diff") linhas de checksum diferentes"
diff "$WORK/src.fingerprint" "$WORK/dst.fingerprint" > "$WORK/fingerprint.diff" || problem "restauro: catálogo diferente ($(grep -c '^[<>]' "$WORK/fingerprint.diff") linhas)"
rpc_out=$(psql "$DST" -X -q -v partial=0 -f scripts/backup/verify_rpc.sql 2>&1 || true)
rpc_res=$(printf '%s\n' "$rpc_out" | grep -oE 'RESULT ok=[0-9]+ fail=[0-9]+' | head -1 || true)
printf '%s\n' "$rpc_out" | grep -E '^(PASS|FAIL) ' > "$WORK/rpc.txt" || true
[[ "$rpc_res" =~ fail=0 ]] || problem "restauro: RPCs ${rpc_res:-sem RESULT}"
t_verify=$(secs "$t0" "$(now)")

# ── 5. export e restauro de um só cliente (bk_a) ──
step "restauro parcial: $WS → ${DRILL_DB}_parcial"
t0=$(now)
mkdir -p "$WORK/ws-$WS"
q "$SRC" -v ws="$WS" -f scripts/backup/scope.sql > "$WORK/scope_ws.tsv"
: > "$WORK/ws-$WS/manifest.tsv"
while IFS=$'\t' read -r tbl sel; do
  # colunas geradas não se copiam (são recalculadas na escrita)
  cols=$(q "$SRC" -Atc "select string_agg(quote_ident(attname), ',' order by attnum) from pg_attribute where attrelid = '$tbl'::regclass and attnum > 0 and not attisdropped and attgenerated = ''")
  q "$SRC" -c "copy (select $cols from ($sel) x) to stdout" > "$WORK/ws-$WS/$tbl.copy"
  printf '%s\t%s\n' "$tbl" "$cols" >> "$WORK/ws-$WS/manifest.tsv"
done < "$WORK/scope_ws.tsv"
t_export=$(secs "$t0" "$(now)")
if [ "${DRILL_SABOTAGE:-0}" = 1 ]; then echo "bk_b" > "$WORK/ws-$WS/sabotagem.copy"; fi
# a procura de fugas tem de saber encontrar: as marcas existem na origem
q "$SRC" -c "copy (select * from public.clients) to stdout" | grep -qE "$LEAK" || problem "procura de fugas inválida: as marcas de outros clientes não existem na origem"
ws_bytes=$(du -sb "$WORK/ws-$WS" | cut -f1)
leaks=$(grep -rlE "$LEAK" "$WORK/ws-$WS" --include='*.copy' | xargs -r -n1 basename | sed 's/\.copy$//' | sort | tr '\n' ' ' || true)
[ -z "$leaks" ] || problem "export de $WS contém marcas de outros clientes em: $leaks"
checksum_sql "$WORK/scope_ws.tsv" filtered > "$WORK/checksum_ws_src.sql"
checksum_sql "$WORK/scope_ws.tsv" table > "$WORK/checksum_ws_dst.sql"
q "$SRC" -At -f "$WORK/checksum_ws_src.sql" | sort > "$WORK/src_ws.checksums"

t0=$(now)
recreate "${DRILL_DB}_parcial" >/dev/null
apply_platform "$PART"
q "$PART" -f scripts/backup/pre_restore.sql >/dev/null
pg_restore -d "$PART" --exit-on-error --single-transaction --section=pre-data -L "$WORK/public.list" "$WORK/public.dump"
{
  echo "begin;"
  while IFS=$'\t' read -r tbl cols; do echo "\\copy $tbl ($cols) from '$WORK/ws-$WS/$tbl.copy'"; done < "$WORK/ws-$WS/manifest.tsv"
  echo "commit;"
} > "$WORK/load_ws.sql"
q "$PART" -f "$WORK/load_ws.sql" >/dev/null
# posições das sequências do momento do backup (≥ máximo de qualquer cliente: nunca reutiliza ids)
pg_restore -l "$WORK/public.dump" | grep -E ' SEQUENCE SET ' > "$WORK/seq.list"
pg_restore -d "$PART" --exit-on-error --single-transaction -L "$WORK/seq.list" "$WORK/public.dump"
pg_restore -l "$WORK/platform.dump" | grep -E ' SEQUENCE SET cron ' > "$WORK/seq_cron.list" || true
[ -s "$WORK/seq_cron.list" ] && pg_restore -d "$PART" --exit-on-error -L "$WORK/seq_cron.list" "$WORK/platform.dump"
# índices, chaves, FKs (prova de que o export é referencialmente completo), triggers, políticas e privilégios
part_post_ok=1
if ! pg_restore -d "$PART" --exit-on-error --single-transaction --section=post-data -L "$WORK/public.list" "$WORK/public.dump" 2> "$WORK/part_post.err"; then
  part_post_ok=0; problem "restauro parcial: chaves/índices falharam: $(head -c 300 "$WORK/part_post.err")"
fi
[ -s "$WORK/platform.policy.list" ] && pg_restore -d "$PART" --exit-on-error --single-transaction -L "$WORK/platform.policy.list" "$WORK/platform.dump"
q "$PART" -f "$WORK/publication.sql" >/dev/null
t_part_restore=$(secs "$t0" "$(now)")
q "$PART" -At -f "$WORK/checksum_ws_dst.sql" | sort > "$WORK/part_ws.checksums"
diff "$WORK/src_ws.checksums" "$WORK/part_ws.checksums" > "$WORK/part.diff" || problem "restauro parcial: $(grep -c '^[<>]' "$WORK/part.diff") linhas de checksum diferentes"
q "$PART" -f scripts/backup/fingerprint.sql | grep -vE '^(sequence|cron)\|' | sort > "$WORK/part.fingerprint"
grep -vE '^(sequence|cron)\|' "$WORK/src.fingerprint" | diff - "$WORK/part.fingerprint" > "$WORK/part_fp.diff" || problem "restauro parcial: catálogo diferente ($(grep -c '^[<>]' "$WORK/part_fp.diff") linhas)"
part_rpc_out=$(psql "$PART" -X -q -v partial=1 -f scripts/backup/verify_rpc.sql 2>&1 || true)
part_rpc_res=$(printf '%s\n' "$part_rpc_out" | grep -oE 'RESULT ok=[0-9]+ fail=[0-9]+' | head -1 || true)
printf '%s\n' "$part_rpc_out" | grep -E '^(PASS|FAIL) ' > "$WORK/part_rpc.txt" || true
[[ "$part_rpc_res" =~ fail=0 ]] || problem "restauro parcial: RPCs ${part_rpc_res:-sem RESULT}"

# ── 6. relatório ──
rto=$(awk -v a="$t_dump" -v b="$t_restore" -v c="$t_verify" 'BEGIN { printf "%.2f", a + b + c }')
export WORK DRILL_ROWS DRILL_BULK migrations db_bytes t_prepare t_dump t_manifest t_restore t_verify rto t_export t_part_restore ws_bytes \
       rpc_res part_rpc_res WS fail part_post_ok srv_major dump_major leaks
PROBLEMS=$(printf '%s\n' "${problems[@]+"${problems[@]}"}"); export PROBLEMS
summary=$(python3 scripts/backup/report.py "$REPORT")
echo "$summary"
[ "$fail" = 0 ] && echo "Ensaio de backup: tudo verificado." || echo "Ensaio de backup: HÁ FALHAS."
exit $fail
