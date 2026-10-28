#!/usr/bin/env bash
# PRD guard (CHG-000). O PRD só pode mudar numa alteração só de documentação
# que traga o pacote docs/changes/CHG-NNN.md correspondente.
# Uso: check-prd-change.sh <base> <head>
set -euo pipefail
BASE="$1"; HEAD="${2:-HEAD}"
CHANGED=$(git diff --name-status "$BASE" "$HEAD")
PRD=$(printf '%s\n' "$CHANGED" | awk '{print $NF}' | grep -E '^docs/ClipStudio_PRD_.*\.md$' || true)
if [ -z "$PRD" ]; then echo "PRD guard: PRD não mudou. OK."; exit 0; fi

FAIL=0
PACK=$(printf '%s\n' "$CHANGED" | grep -E '^[AM][[:space:]]+docs/changes/CHG-[0-9]{3}[^/]*\.md$' || true)
if [ -z "$PACK" ]; then
  echo "::error::O PRD mudou sem pacote. Junta docs/changes/CHG-NNN.md nesta alteração (ver PRD §33, AGENTS §15)."
  FAIL=1
fi
OUTSIDE=$(printf '%s\n' "$CHANGED" | awk '{print $NF}' | grep -vE '^(docs/|AGENTS\.md$|CLAUDE\.md$|README\.md$)' || true)
if [ -n "$OUTSIDE" ]; then
  echo "::error::O PRD só muda em alterações só de documentação. Ficheiros fora de docs/:"
  printf '  %s\n' $OUTSIDE
  FAIL=1
fi
[ "$FAIL" -eq 0 ] && echo "PRD guard: alteração ao PRD com pacote e só documentação. OK."
exit "$FAIL"
