import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage } from "@/lib/storage";

/**
 * GET /api/media/versions/:id/url?ws=&purpose=preview|download · link assinado curto (FR-08-03). media_access verifica
 * a capacidade (media.read / media.download), audita e cria a autorização de 60 s sem a qual o storage não assina.
 */
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const ws = req.nextUrl.searchParams.get("ws") ?? "";
  const purpose = req.nextUrl.searchParams.get("purpose") === "download" ? "download" : "preview";
  if (!UUID.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ bucket: string; path: string; filename: string; mime: string; ttl_seconds: number }>(
    sb, "media_access", { p_ws: ws, p_version: id, p_purpose: purpose });
  if (r.error) return fail(r.error);
  try {
    const url = await mediaStorage(sb).createSignedUrl(r.data.bucket, r.data.path,
      { expiresIn: r.data.ttl_seconds, downloadName: purpose === "download" ? r.data.filename : undefined });
    return ok({ url, mime: r.data.mime, filename: r.data.filename, expires_at: new Date(Date.now() + r.data.ttl_seconds * 1000).toISOString() });
  } catch (e) {
    return fail(e as Error);
  }
}
