#!/usr/bin/env bash
# Vercel "Ignored Build Step" (ADR-0019 / CHG-002): sai com 0 para SALTAR a build, 1 para construir.
# Salta quando o commit só muda documentação, migrações e testes SQL, testes unitários ou CI: nada disso muda a app servida.
# Na dúvida (sem commit anterior, erro do git), constrói.
set -u
BASE="${VERCEL_GIT_PREVIOUS_SHA:-}"
[ -z "$BASE" ] && BASE="HEAD^"
git cat-file -e "$BASE" 2>/dev/null || git fetch --depth=50 origin >/dev/null 2>&1 || true
git cat-file -e "$BASE" 2>/dev/null || { echo "Sem commit anterior: constrói."; exit 1; }
if git diff --quiet "$BASE" HEAD -- . ':(exclude)docs/**' ':(exclude)supabase/**' ':(exclude)tests/**' \
     ':(exclude)scripts/ci/**' ':(exclude).github/**' ':(exclude)*.md'; then
  echo "Só documentação, testes ou CI: build saltada."; exit 0
fi
echo "A app mudou: constrói."; exit 1
