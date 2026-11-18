import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage } from "@/lib/storage";
import { EPISODE_FILES } from "@/lib/episodes-format";

/**
 * GET /api/episodes/:id/files/:name?ws= · link assinado curto para um ficheiro do episódio editado (POD-05, CHG-013).
 * episode_file_access verifica edit.episode (flag) e media.download, audita e cria a autorização de 60 s sem a qual o
 * storage não assina; o caminho vem sempre do servidor (resultado do job), nunca do pedido.
 */
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string; name: string }> }) {
  const { id, name } = await ctx.params;
  const ws = req.nextUrl.searchParams.get("ws") ?? "";
  if (!UUID.test(id) || !WS.test(ws) || !(EPISODE_FILES as readonly string[]).includes(name)) {
    return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  }
  const sb = await serverSupabase();
  const r = await rpc<{ bucket: string; path: string; filename: string; mime: string; ttl_seconds: number }>(
    sb, "episode_file_access", { p_ws: ws, p_job: id, p_name: name });
  if (r.error) return fail(r.error);
  try {
    const url = await mediaStorage(sb, r.data.bucket).createSignedUrl(r.data.bucket, r.data.path,
      { expiresIn: r.data.ttl_seconds, downloadName: r.data.filename });
    return ok({ url, mime: r.data.mime, filename: r.data.filename, expires_at: new Date(Date.now() + r.data.ttl_seconds * 1000).toISOString() });
  } catch (e) {
    return fail(e as Error);
  }
}
