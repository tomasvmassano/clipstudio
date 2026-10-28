import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/supabase";

/**
 * Verificação otimista (Next 16 proxy): manda para /login quem não tem sessão nem código de equipa.
 * Não é a barreira de segurança: RLS e authorize() decidem cada leitura e escrita no servidor.
 * Também renova os cookies da sessão Supabase.
 */
const PUBLIC = [/^\/login/, /^\/auth\//, /^\/legacy\//];

export async function proxy(req: NextRequest) {
  let res = NextResponse.next({ request: req });
  const sb = createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (list) => {
        for (const { name, value } of list) req.cookies.set(name, value);
        res = NextResponse.next({ request: req });
        for (const { name, value, options } of list) res.cookies.set(name, value, options);
      },
    },
  });
  const { data } = await sb.auth.getClaims();
  const path = req.nextUrl.pathname;
  if (PUBLIC.some((r) => r.test(path))) return res;

  const hasUser = !!data?.claims?.sub;
  const hasCode = req.cookies.get("studio_code")?.value === "1" || req.nextUrl.searchParams.has("k");
  if (!hasUser && !hasCode) {
    const to = new URL("/login", req.url);
    if (path !== "/") to.searchParams.set("next", path);
    const r = NextResponse.redirect(to);
    for (const c of res.cookies.getAll()) r.cookies.set(c);
    return r;
  }
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|legacy/|.*\\.(?:png|jpg|jpeg|svg|webp|ico|json|txt|js|css)$).*)"],
};
