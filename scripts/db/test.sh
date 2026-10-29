#!/usr/bin/env bash
# Aplica todas as migrações numa base limpa e corre os testes SQL (supabase/tests).
# Uso: DATABASE_URL=postgres://postgres@localhost:5432/postgres scripts/db/test.sh [teste.sql ...]
# A base tem de ser descartável: o script recusa hosts *.supabase.co / pooler.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${DATABASE_URL:?define DATABASE_URL para uma base descartável}"
case "$DATABASE_URL" in *supabase.co*|*supabase.com*|*pooler*) echo "::error::Recuso correr contra um projeto Supabase real."; exit 2;; esac
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -f scripts/db/bootstrap.sql >/dev/null
for m in supabase/migrations/*.sql; do
  # pg_cron é da plataforma: o bootstrap fornece um cron.* equivalente.
  if ! sed -E 's/^\s*create extension if not exists pg_cron[^;]*;//I' "$m" | "${PSQL[@]}" >/dev/null 2>/tmp/mig.err; then
    echo "::error file=$m::migração falhou"; cat /tmp/mig.err; exit 1
  fi
done
echo "Migrações aplicadas: $(ls supabase/migrations/*.sql | wc -l)"
"${PSQL[@]}" -f supabase/tests/fixtures/seed.sql >/dev/null

tests=("$@"); [ ${#tests[@]} -eq 0 ] && tests=(supabase/tests/w*.sql)
fail=0; total_ok=0
for t in "${tests[@]}"; do
  out=$(psql "$DATABASE_URL" -X -q -f "$t" 2>&1 || true)
  res=$(printf '%s\n' "$out" | grep -oE 'RESULT ok=[0-9]+ fail=[0-9]+.*' | head -1 || true)
  if [[ "$res" =~ ok=([0-9]+)\ fail=0 ]]; then
    total_ok=$((total_ok + BASH_REMATCH[1])); echo "ok   $(basename "$t") ${res#RESULT }"
  else
    fail=1; echo "::error file=$t::${res:-sem RESULT}"; printf '%s\n' "$out" | grep -E 'ERROR|FAIL' | head -5
  fi
done
echo "Testes SQL: $total_ok casos, $([ $fail -eq 0 ] && echo 'todos passaram' || echo 'há falhas')."
exit $fail
