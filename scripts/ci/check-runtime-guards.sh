#!/usr/bin/env bash
# Guardas de execução (ADR-0019, PRD §25 R-15). Falha o CI se:
#  1. alguém abrir um canal de tempo real fora do gestor partilhado (src/lib/realtime*.ts / realtime.listen);
#  2. faltar um limite de erro da app, do espaço do cliente ou o global.
set -euo pipefail
FAIL=0
while IFS= read -r f; do
  case "$f" in src/lib/realtime-hub.ts|src/lib/realtime.ts) continue ;; esac
  if ! grep -q "realtime.listen(" "$f"; then
    echo "::error file=$f::abre um canal de tempo real (.channel) sem passar por realtime.listen (src/lib/realtime.ts)"
    FAIL=1
  fi
done < <(grep -rlE "\.channel\(" src --include=*.ts --include=*.tsx || true)
for f in src/app/error.tsx "src/app/c/[ws]/error.tsx" src/app/global-error.tsx; do
  [ -f "$f" ] || { echo "::error::falta o limite de erro $f"; FAIL=1; }
done
[ "$FAIL" -eq 0 ] && echo "Guardas de execução: OK."
exit "$FAIL"
