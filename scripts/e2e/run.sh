#!/usr/bin/env bash
# E2E com contas reais numa stack Supabase local: supabase start (migrações + seed), build da app apontada
# para a stack, Playwright. Uso: scripts/e2e/run.sh [args do playwright]. Precisa de Docker.
set -euo pipefail
cd "$(dirname "$0")/../.."
npx supabase status >/dev/null 2>&1 || npx supabase start -x studio,edge-runtime,logflare,vector,supavisor,imgproxy,mailpit,postgres-meta
eval "$(npx supabase status -o env | sed -n 's/^\(API_URL\|DB_URL\|PUBLISHABLE_KEY\|SERVICE_ROLE_KEY\)=/export SB_\1=/p')"
export NEXT_PUBLIC_SUPABASE_URL="$SB_API_URL" NEXT_PUBLIC_SUPABASE_KEY="$SB_PUBLISHABLE_KEY"
export E2E_SUPABASE_URL="$SB_API_URL" E2E_DB_URL="$SB_DB_URL" E2E_SERVICE_KEY="$SB_SERVICE_ROLE_KEY"
if [ "${E2E_SKIP_BUILD:-}" != 1 ]; then npm run build; fi
npx playwright test "$@"
