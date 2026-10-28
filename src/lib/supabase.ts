import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

// Chave publishable: só identifica o projeto. Quem pode ler ou escrever o quê decide o RLS e as RPCs (authorize()).
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://dcvrhgirmijtocprfwqd.supabase.co";
export const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY ?? "sb_publishable_fk4vSB9lDQZt2ddBdbaHmQ_LvnsIpK_";

let client: SupabaseClient | null = null;
/** Cliente do browser. A sessão vive em cookies para o proxy (src/proxy.ts) a poder ver. */
export function supabase(): SupabaseClient {
  if (!client) client = createBrowserClient(SUPABASE_URL, SUPABASE_KEY);
  return client;
}
