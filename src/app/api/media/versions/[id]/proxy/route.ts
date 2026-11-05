import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage } from "@/lib/storage";

/**
 * GET /api/media/versions/:id/proxy?ws= · link assinado (1 h) para a versão leve de um vídeo no R2 (EDL-08, ADR-0047).
 * media_proxy_access verifica media.read, o cliente e que o proxy está pronto; o servidor só assina o caminho devolvido.
 */
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const ws = req.nextUrl.searchParams.get("ws") ?? "";
  if (!UUID.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ bucket: string; path: string; mime: string; ttl_seconds: number }>(sb, "media_proxy_access", { p_ws: ws, p_version: id });
  if (r.error) return fail(r.error);
  try {
    const url = await mediaStorage(sb, r.data.bucket).createSignedUrl(r.data.bucket, r.data.path, { expiresIn: r.data.ttl_seconds });
    return ok({ url, mime: r.data.mime, expires_at: new Date(Date.now() + r.data.ttl_seconds * 1000).toISOString() });
  } catch (e) {
    return fail(e as Error);
  }
}
