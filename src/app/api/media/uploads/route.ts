import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { body, fail, ok, rpc, WS } from "@/lib/server/media";
import { mediaStorage, MULTIPART_FROM, r2Storage } from "@/lib/storage";

/**
 * POST /api/media/uploads · regista uma versão pendente (media_upload_begin: capacidade, tipo, tamanho, quota, caminho
 * gerado no servidor) e devolve o alvo de envio (URL assinado de uso único). FR-08-01, ADR-0038.
 */
export async function POST(req: NextRequest) {
  const b = await body(req);
  const ws = String(b.ws ?? "");
  if (!WS.test(ws)) return fail({ code: "22023", message: "cliente_invalido", details: "Cliente inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ asset_id: string; version_id: string; version_no: number; bucket: string; path: string; expires_at: string; reused: boolean }>(
    sb, "media_upload_begin", { p_ws: ws, p_asset_id: b.asset_id ?? null, p_fields: b.fields ?? {}, p_file: b.file ?? {} });
  if (r.error) return fail(r.error);
  try {
    const mime = String((b.file as { mime?: string } | undefined)?.mime ?? "").toLowerCase();
    const size = Number((b.file as { size?: number } | undefined)?.size ?? 0);
    // R2 e ficheiro grande: envio por partes (retoma por parte; o PUT simples do R2 vai só até 5 GiB)
    if (r.data.bucket === "r2" && size >= MULTIPART_FROM) {
      return ok({ ...r.data, upload: { kind: "multipart", ...(await r2Storage().createMultipart(r.data.path, mime, size)) } });
    }
    const upload = await mediaStorage(sb, r.data.bucket).createUploadTarget(r.data.bucket, r.data.path, mime);
    return ok({ ...r.data, upload: { kind: "single", ...upload } });
  } catch (e) {
    return fail(e as Error);
  }
}
