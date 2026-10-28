import { NextResponse, type NextRequest } from "next/server";
import { safeNext, serverSupabase } from "@/lib/server/supabase";

/**
 * Volta do email de confirmação e do Google (PKCE): troca o código por sessão e segue.
 * Os convites pendentes são aceites na app (accept_invitations) e só para emails confirmados.
 */
export async function GET(req: NextRequest) {
  const url = req.nextUrl;
  const code = url.searchParams.get("code");
  const next = safeNext(url.searchParams.get("next"), url.origin);
  const errDesc = url.searchParams.get("error_description");
  if (errDesc) return NextResponse.redirect(new URL(`/login?erro=${encodeURIComponent(errDesc)}`, url.origin));
  if (!code) return NextResponse.redirect(new URL("/login?erro=link_invalido", url.origin));
  const sb = await serverSupabase();
  const { error } = await sb.auth.exchangeCodeForSession(code);
  if (error) return NextResponse.redirect(new URL(`/login?erro=${encodeURIComponent(error.message)}`, url.origin));
  return NextResponse.redirect(new URL(next, url.origin));
}
