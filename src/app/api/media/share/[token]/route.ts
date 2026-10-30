import { createClient } from "@supabase/supabase-js";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/supabase";
import { mediaStorage } from "@/lib/storage";

/**
 * GET /api/media/share/:token · link de partilha público (FR-08-03). Sem sessão de propósito: media_share_open valida o
 * token (hash), a validade, a revogação e a flag, audita e cria uma autorização de 60 s só para esse objeto; depois o
 * storage assina um URL de no máximo 5 min e redirecionamos para ele. Qualquer falha dá a mesma página (não revela nada).
 */
const gone = () => new NextResponse(
  `<!doctype html><html lang="pt-PT"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Link indisponível</title>
<body style="font-family:system-ui;background:#0a0a0a;color:#f5f5f5;display:grid;place-items:center;min-height:100vh;margin:0;padding:16px">
<main><h1 style="font-size:1.25rem">Link indisponível</h1><p>Este link expirou, foi revogado ou não existe. Pede um link novo a quem to enviou.</p></main></body></html>`,
  { status: 404, headers: { "content-type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });

export async function GET(_req: NextRequest, ctx: { params: Promise<{ token: string }> }) {
  const { token } = await ctx.params;
  if (!/^[0-9a-f]{48}$/.test(token)) return gone();
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await sb.rpc("media_share_open", { p_share_token: token });
  if (error || !data) return gone();
  const d = data as { bucket: string; path: string; ttl_seconds: number };
  try {
    const url = await mediaStorage(sb).createSignedUrl(d.bucket, d.path, { expiresIn: d.ttl_seconds });
    return NextResponse.redirect(url, { status: 302, headers: { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });
  } catch {
    return gone();
  }
}
