import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage, MULTIPART_FROM, r2Storage } from "@/lib/storage";

/** POST /api/media/uploads/:id/target · retomar: alvo de envio novo para a mesma versão pendente (só quem a registou). */
export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const b = await body(req);
  const ws = String(b.ws ?? "");
  if (!UUID.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ bucket: string; path: string; mime: string; size_bytes: number; object_exists: boolean | null; expires_at: string }>(
    sb, "media_upload_target", { p_ws: ws, p_version: id });
  if (r.error) return fail(r.error);
  if (r.data.object_exists) return ok({ ...r.data, upload: null });
  try {
    if (r.data.bucket === "r2") {
      // o objeto já lá está com o tamanho certo (resposta perdida): segue para confirmar
      const h = await r2Storage().head(r.data.path);
      if (h && h.size === r.data.size_bytes) return ok({ ...r.data, upload: null });
      if (r.data.size_bytes >= MULTIPART_FROM) {
        return ok({ ...r.data, upload: { kind: "multipart", ...(await r2Storage().createMultipart(r.data.path, r.data.mime, r.data.size_bytes)) } });
      }
    }
    const upload = await mediaStorage(sb, r.data.bucket).createUploadTarget(r.data.bucket, r.data.path, r.data.mime);
    return ok({ ...r.data, upload: { kind: "single", ...upload } });
  } catch (e) {
    return fail(e as Error);
  }
}
