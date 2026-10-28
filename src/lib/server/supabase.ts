import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/supabase";

/** Cliente Supabase para Route Handlers: lê e escreve os cookies da sessão. */
export async function serverSupabase() {
  const jar = await cookies();
  return createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll: () => jar.getAll(),
      setAll: (list) => { for (const { name, value, options } of list) jar.set(name, value, options); },
    },
  });
}

/** Só aceita caminhos internos como destino (evita open redirect). */
export function safeNext(next: string | null | undefined): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return "/";
  return next;
}
