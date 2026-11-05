import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { r2Storage } from "@/lib/storage";

/**
 * POST /api/media/uploads/:id/multipart · envio por partes para o R2 (ADR-0047). {ws, upload_id, action: "urls", parts: [n]}
 * devolve URLs novos para essas partes (expiraram ou falharam); {action: "complete", parts: [{n, etag}]} junta as partes.
 * Antes de tudo media_upload_target confirma que a versão é de quem pede, está pendente e não expirou.
 */
export const maxDuration = 60;

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const b = await body(req);
  const ws = String(b.ws ?? ""), uploadId = String(b.upload_id ?? "");
  if (!UUID.test(id) || !WS.test(ws) || !uploadId || uploadId.length > 1024) {
    return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  }
  const sb = await serverSupabase();
  const t = await rpc<{ bucket: string; path: string; size_bytes: number }>(sb, "media_upload_target", { p_ws: ws, p_version: id });
  if (t.error) return fail(t.error);
  if (t.data.bucket !== "r2") return fail({ code: "22023", message: "pedido_invalido", details: "Este upload não é por partes." });
  try {
    const st = r2Storage();
    if (b.action === "urls") {
      const ns = Array.isArray(b.parts) ? b.parts.map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 1000) : [];
      return ok(st.partUrls(t.data.path, uploadId, t.data.size_bytes, ns));
    }
    if (b.action === "complete") {
      const parts = Array.isArray(b.parts) ? (b.parts as { n?: unknown; etag?: unknown }[])
        .map((p) => ({ n: Number(p.n), etag: String(p.etag ?? "") })).filter((p) => Number.isInteger(p.n) && p.n > 0 && p.etag) : [];
      if (parts.length === 0 || parts.length > 10000) return fail({ code: "22023", message: "pedido_invalido", details: "Faltam as partes." });
      await st.completeMultipart(t.data.path, uploadId, parts);
      return ok({ completed: true });
    }
    if (b.action === "abort") { await st.abortMultipart(t.data.path, uploadId); return ok({ aborted: true }); }
    return fail({ code: "22023", message: "pedido_invalido", details: "Ação desconhecida." });
  } catch (e) {
    return fail(e as Error);
  }
}
