import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Chave pública (só leitura; a escrita passa por RPC com código de equipa).
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://dcvrhgirmijtocprfwqd.supabase.co";
const KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY ?? "sb_publishable_fk4vSB9lDQZt2ddBdbaHmQ_LvnsIpK_";

let client: SupabaseClient | null = null;
export function supabase(): SupabaseClient {
  if (!client) client = createClient(URL, KEY, { auth: { persistSession: false } });
  return client;
}

export const DEFAULT_CLIENT = "numeiro";
