import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage } from "@/lib/storage";

/** POST /api/media/uploads/:id/target · retomar: alvo de envio novo para a mesma versão pendente (só quem a registou). */
export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const b = await body(req);
  const ws = String(b.ws ?? "");
  if (!UUID.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ bucket: string; path: string; mime: string; object_exists: boolean; expires_at: string }>(sb, "media_upload_target", { p_ws: ws, p_version: id });
  if (r.error) return fail(r.error);
  if (r.data.object_exists) return ok({ ...r.data, upload: null });
  try {
    return ok({ ...r.data, upload: await mediaStorage(sb).createUploadTarget(r.data.bucket, r.data.path, r.data.mime) });
  } catch (e) {
    return fail(e as Error);
  }
}
