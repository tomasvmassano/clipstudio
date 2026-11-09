import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { fail, rpc, WS } from "@/lib/server/media";
import { allowedVideoUrl, downloadName } from "@/lib/reacts-format";

/**
 * GET /api/reacts/:id/video?ws=&dl=1 · vídeo original de um candidato a react (REACT-04).
 * react_video_access verifica reacts.read, a flag e que o candidato é deste cliente; o servidor busca o vídeo ao CDN da
 * plataforma (só hosts conhecidos) e devolve-o em stream, com Range para o leitor e "attachment" para descarregar.
 */
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const ws = req.nextUrl.searchParams.get("ws") ?? "";
  const dl = req.nextUrl.searchParams.get("dl") === "1";
  if (!/^\d{1,18}$/.test(id) || !WS.test(ws)) return fail({ code: "22023", message: "pedido_invalido", details: "Pedido inválido." });
  const sb = await serverSupabase();
  const r = await rpc<{ url: string; author: string | null; ref_key: string }>(sb, "react_video_access", { p_ws: ws, p_id: Number(id) });
  if (r.error) return fail(r.error);
  if (!allowedVideoUrl(r.data.url)) return fail({ code: "22023", message: "origem_invalida", details: "Origem do vídeo não permitida." });
  const range = req.headers.get("range");
  let upstream: Response;
  try {
    upstream = await fetch(r.data.url, { headers: range && !dl ? { Range: range } : {}, redirect: "follow", cache: "no-store" });
  } catch {
    return fail({ code: "55000", message: "video_indisponivel", details: "Não foi possível ir buscar o vídeo. Tenta de novo ou abre o original." });
  }
  if (!upstream.ok && upstream.status !== 206) {
    return fail({ code: "55000", message: "video_expirado", details: "O link do vídeo expirou. O agente renova-o na próxima corrida; entretanto abre o original." });
  }
  const headers = new Headers({ "Content-Type": upstream.headers.get("content-type") || "video/mp4", "Cache-Control": "private, no-store" });
  for (const h of ["content-length", "content-range", "accept-ranges"]) { const v = upstream.headers.get(h); if (v) headers.set(h, v); }
  headers.set("Content-Disposition", `${dl ? "attachment" : "inline"}; filename="${downloadName(r.data.author, r.data.ref_key)}"`);
  return new Response(upstream.body, { status: upstream.status, headers });
}
