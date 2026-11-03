import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, UUID, WS } from "@/lib/server/media";
import { mediaStorage } from "@/lib/storage";

/**
 * POST /api/media/purge · {ws, scope: orfaos|lixo, ids, confirm: "APAGAR"} · eliminação definitiva com confirmação explícita
 * (FR-08-06). media_purge_begin autoriza (media.manage) e devolve os caminhos; os objetos apagam-se pela API do storage
 * (com a política de delete a voltar a verificar); media_purge_finish só marca o que já não existe.
 */
export async function POST(req: NextRequest) {
  const b = await body(req);
  const ws = String(b.ws ?? "");
  const scope = b.scope === "lixo" ? "lixo" : b.scope === "orfaos" ? "orfaos" : "";
  const ids = Array.isArray(b.ids) ? b.ids.map(String) : [];
  if (!WS.test(ws) || !scope || ids.length === 0 || ids.some((i) => !UUID.test(i))) {
    return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  }
  const sb = await serverSupabase();
  const begin = await rpc<{ objects: { bucket: string; path: string }[] }>(sb, "media_purge_begin",
    { p_ws: ws, p_scope: scope, p_ids: ids, p_confirm: String(b.confirm ?? "") });
  if (begin.error) return fail(begin.error);
  const byBucket = new Map<string, string[]>();
  for (const o of begin.data.objects) byBucket.set(o.bucket, [...(byBucket.get(o.bucket) ?? []), o.path]);
  let storageError: string | undefined;
  try {
    const st = mediaStorage(sb);
    for (const [bucket, paths] of byBucket) {
      const r = await st.remove(bucket, paths);
      if (r.error) storageError = r.error;
    }
  } catch (e) {
    storageError = (e as Error).message;
  }
  const fin = await rpc<{ versions_deleted: number; assets_purged: number; remaining: string[] }>(sb, "media_purge_finish", { p_ws: ws, p_scope: scope, p_ids: ids });
  if (fin.error) return fail(fin.error);
  return ok({ ...fin.data, storage_error: storageError ?? null });
}
