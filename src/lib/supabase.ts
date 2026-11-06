import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { withDenialAudit, wsFromPath } from "@/lib/denials";

// Chave publishable: só identifica o projeto. Quem pode ler ou escrever o quê decide o RLS e as RPCs (authorize()).
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://dcvrhgirmijtocprfwqd.supabase.co";
export const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY ?? "sb_publishable_fk4vSB9lDQZt2ddBdbaHmQ_LvnsIpK_";

let client: SupabaseClient | null = null;
/**
 * Cliente do browser. A sessão vive em cookies para o proxy (src/proxy.ts) a poder ver.
 * Toda a RPC recusada (42501) é registada em audit_events por um segundo pedido (src/lib/denials.ts, ADR-0066).
 */
export function supabase(): SupabaseClient {
  if (!client) client = createBrowserClient(SUPABASE_URL, SUPABASE_KEY, {
    global: { fetch: withDenialAudit((...a) => fetch(...a), { via: "browser", currentWs: () => (typeof window === "undefined" ? null : wsFromPath(window.location.pathname)) }) },
  });
  return client;
}
