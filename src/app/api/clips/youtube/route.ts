import type { NextRequest } from "next/server";
import { serverSupabase } from "@/lib/server/supabase";
import { fail, ok } from "@/lib/server/media";
import { youtubeId } from "@/lib/clips-format";

/**
 * GET /api/clips/youtube?url= · título e canal de um vídeo do YouTube pelo oEmbed público (W10-45, CHG-012, CLIP-01: o link
 * serve para metadados; nada se descarrega). Só para sessões individuais; só aceita links do YouTube (não é um proxy aberto).
 */
export async function GET(req: NextRequest) {
  const id = youtubeId(req.nextUrl.searchParams.get("url") ?? "");
  if (!id) return fail({ code: "22023", message: "link_invalido", details: "O link tem de ser de um vídeo do YouTube." });
  const sb = await serverSupabase();
  const { data: u } = await sb.auth.getUser();
  if (!u?.user) return fail({ code: "28000", message: "nao_autenticado", details: "Entra na tua conta." });
  try {
    const r = await fetch(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${id}`)}`,
      { cache: "no-store", signal: AbortSignal.timeout(6000) });
    if (r.status === 401 || r.status === 403 || r.status === 404) {
      return ok({ id, title: null, author: null, thumbnail: null, note: "O vídeo é privado ou não existe: escolhe o ficheiro à mão." });
    }
    if (!r.ok) return ok({ id, title: null, author: null, thumbnail: null, note: "O YouTube não respondeu: escolhe o ficheiro à mão." });
    const b = (await r.json()) as { title?: string; author_name?: string; thumbnail_url?: string };
    return ok({ id, title: b.title?.slice(0, 300) ?? null, author: b.author_name?.slice(0, 120) ?? null, thumbnail: b.thumbnail_url ?? null, note: null });
  } catch {
    return ok({ id, title: null, author: null, thumbnail: null, note: "O YouTube não respondeu: escolhe o ficheiro à mão." });
  }
}
