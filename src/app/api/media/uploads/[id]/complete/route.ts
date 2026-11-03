import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, sha256Stream, UUID, WS } from "@/lib/server/media";
import { mediaStorage, VERIFY_MAX_BYTES } from "@/lib/storage";

/**
 * POST /api/media/uploads/:id/complete · o servidor relê o objeto, calcula o SHA-256 e confirma (media_upload_complete
 * confere também tamanho e tipo guardados). Acima de MEDIA_VERIFY_MAX_BYTES o checksum fica "declarado pelo browser".
 */
export const maxDuration = 60;

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const b = await body(req);
  const ws = String(b.ws ?? "");
  if (!UUID.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const t = await rpc<{ bucket: string; path: string; size_bytes: number; object_exists: boolean }>(sb, "media_upload_target", { p_ws: ws, p_version: id });
  let sha: string | null = null;
  if (t.error) {
    // já confirmada (repetição) ou expirada: a RPC de confirmação decide e responde com o estado certo
    if (t.error.code !== "22023") return fail(t.error);
  } else {
    if (!t.data.object_exists) return fail({ code: "P0002", message: "objeto_em_falta", details: "O ficheiro ainda não chegou ao armazenamento: tenta enviar outra vez." });
    if (t.data.size_bytes <= VERIFY_MAX_BYTES) {
      const stream = await mediaStorage(sb).read(t.data.bucket, t.data.path);
      // lê no máximo o tamanho declarado + 1: se o objeto for maior, a RPC marca a diferença de tamanho
      const h = stream ? await sha256Stream(stream, t.data.size_bytes) : null;
      sha = h?.sha256 ?? null;
    }
  }
  const r = await rpc<{ state: string; reason?: string }>(sb, "media_upload_complete", { p_ws: ws, p_version: id, p_server_sha256: sha });
  if (r.error) return fail(r.error);
  return ok(r.data);
}
