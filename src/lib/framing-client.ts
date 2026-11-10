/*
 * Enquadramento da gravação inteira (W10-36, ADR-0082): o mesmo zoom e posição de uma câmara em todos os vídeos que usam o mesmo
 * ficheiro dessa câmara (ex.: o C7870 em todos os vídeos do pacote). Para cada vídeo lê a versão atual e grava uma versão nova com
 * edit_doc_save e essa versão como base; quem gravou entretanto fica de fora com aviso.
 */
import type { Access } from "@/lib/access";
import { fetchBoard, fetchEdit, saveEdit, variantShort } from "@/lib/edit";
import { frameAllCam, type EditDoc } from "@/lib/edit-doc";

export type Framing = { zoom: number; x?: number; y?: number };
export type FrameResult = { asset: string; label: string; outcome: "aplicado" | "igual" | "falhou"; error?: string };

/** Os outros vídeos (com documento) que usam o mesmo ficheiro para esta câmara. */
export async function videosWithFile(a: Access, cam: string, file: string, exclude: string): Promise<{ asset: string; label: string }[]> {
  const gs = await fetchBoard(a, null, 100);
  return gs.flatMap((g) => g.variants
    .filter((v) => v.asset_id !== exclude && v.source.cams?.[cam] === file)
    .map((v) => ({ asset: v.asset_id, label: `Guião ${g.guiao?.n ?? "?"} ${variantShort(v.variant)}` })));
}

const sameFrame = (d: EditDoc, cam: string, f: Framing) => JSON.stringify(frameAllCam(d, cam, f).cameras) === JSON.stringify(d.cameras);

export async function applyFramingToVideos(a: Access, cam: string, f: Framing, videos: { asset: string; label: string }[], note: string): Promise<FrameResult[]> {
  const out: FrameResult[] = [];
  for (const v of videos) {
    try {
      const st = await fetchEdit(a, v.asset);
      if (!st.version || !st.document) { out.push({ ...v, outcome: "falhou", error: "sem documento de edição" }); continue; }
      if (sameFrame(st.version.doc, cam, f)) { out.push({ ...v, outcome: "igual" }); continue; }
      await saveEdit(a, v.asset, st.document.current_version_id, frameAllCam(st.version.doc, cam, f), note);
      out.push({ ...v, outcome: "aplicado" });
    } catch (e) {
      out.push({ ...v, outcome: "falhou", error: (e as Error).message });
    }
  }
  return out;
}

export function framingSummary(rs: FrameResult[]): { kind: "ok" | "err"; text: string } {
  const ap = rs.filter((r) => r.outcome === "aplicado").length, eq = rs.filter((r) => r.outcome === "igual").length;
  const fl = rs.filter((r) => r.outcome === "falhou");
  const parts = [`Enquadramento aplicado a ${ap} vídeo${ap === 1 ? "" : "s"}`, eq ? `${eq} já estava${eq === 1 ? "" : "m"} assim` : "",
    fl.length ? `falhou em ${fl.map((r) => `${r.label} (${r.error})`).join("; ")}` : ""].filter(Boolean);
  return { kind: fl.length ? "err" : "ok", text: parts.join(", ") + "." };
}
