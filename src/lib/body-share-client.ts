/*
 * Aplicar o corpo às outras variantes do guião (EDL-14, ADR-0081): lê a versão atual de cada uma, junta o corpo (applyBody) e grava
 * uma versão nova com edit_doc_save, com a versão base para não sobrescrever o que outra pessoa gravou entretanto.
 */
import type { Access } from "@/lib/access";
import { applyBody, sameBody } from "@/lib/body-share";
import { fetchEdit, saveEdit, variantShort, type BoardVariant } from "@/lib/edit";
import type { EditDoc } from "@/lib/edit-doc";

export type BodyResult = { asset: string; label: string; outcome: "aplicado" | "igual" | "falhou"; error?: string };

export async function applyBodyToSiblings(a: Access, srcAsset: string, srcLabel: string, srcDoc: EditDoc, siblings: BoardVariant[]): Promise<BodyResult[]> {
  const out: BodyResult[] = [];
  for (const s of siblings) {
    if (s.asset_id === srcAsset) continue;
    const label = variantShort(s.variant);
    try {
      const st = await fetchEdit(a, s.asset_id);
      if (!st.version || !st.document) { out.push({ asset: s.asset_id, label, outcome: "falhou", error: "sem documento de edição" }); continue; }
      if (sameBody(srcDoc, st.version.doc)) { out.push({ asset: s.asset_id, label, outcome: "igual" }); continue; }
      const merged = applyBody(srcDoc, st.version.doc);
      await saveEdit(a, s.asset_id, st.document.current_version_id, merged, `corpo aplicado de ${srcLabel}`);
      out.push({ asset: s.asset_id, label, outcome: "aplicado" });
    } catch (e) {
      out.push({ asset: s.asset_id, label, outcome: "falhou", error: (e as Error).message });
    }
  }
  return out;
}

/** Frase para o editor: o que foi aplicado e o que falhou. */
export function bodySummary(rs: BodyResult[]): { kind: "ok" | "err"; text: string } | null {
  if (!rs.length) return null;
  const ap = rs.filter((r) => r.outcome === "aplicado").map((r) => r.label);
  const eq = rs.filter((r) => r.outcome === "igual").map((r) => r.label);
  const fl = rs.filter((r) => r.outcome === "falhou");
  const parts = [ap.length ? `Corpo aplicado a ${ap.join(", ")}` : "", eq.length ? `${eq.join(", ")} já tinha${eq.length > 1 ? "m" : ""} o mesmo corpo` : "",
    fl.length ? `Falhou em ${fl.map((r) => `${r.label} (${r.error})`).join("; ")}` : ""].filter(Boolean);
  return { kind: fl.length ? "err" : "ok", text: parts.join(". ") + "." };
}

/* A mensagem sobrevive ao recarregar o editor (que remonta com a versão nova): fica na sessão do separador até ser mostrada. */
const FLASH = "edit.bodyFlash";
export function flashBody(m: { kind: "ok" | "err"; text: string } | null) {
  try { if (m) sessionStorage.setItem(FLASH, JSON.stringify(m)); } catch { /* sem armazenamento: não se mostra */ }
}
export function takeBodyFlash(): { kind: "ok" | "err"; text: string } | null {
  try { const v = sessionStorage.getItem(FLASH); sessionStorage.removeItem(FLASH); return v ? JSON.parse(v) : null; } catch { return null; }
}
