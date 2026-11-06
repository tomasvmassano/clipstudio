import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/supabase";
import { withDenialAudit } from "@/lib/denials";

/**
 * Cliente Supabase para Route Handlers: lê e escreve os cookies da sessão.
 * Uma RPC recusada (42501) numa rota /api é registada em audit_events antes de a rota responder (ADR-0066).
 */
export async function serverSupabase() {
  const jar = await cookies();
  return createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    global: { fetch: withDenialAudit((...a) => fetch(...a), { via: "api", awaitReport: true }) },
    cookies: {
      getAll: () => jar.getAll(),
      setAll: (list) => { for (const { name, value, options } of list) jar.set(name, value, options); },
    },
  });
}

export { safeNext } from "@/lib/safe-next";
