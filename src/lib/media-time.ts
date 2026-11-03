/** Utilitários puros da revisão de vídeo (W5-04, CHG-006): momentos mm:ss e links da Google Drive. */

/** "0:23", "1:02:03", "23" ou "23s" → milissegundos; null se não for um momento válido. */
export function parseMoment(s: string): number | null {
  const v = s.trim().replace(/s$/i, "");
  if (!v) return null;
  if (/^\d+(\.\d+)?$/.test(v)) return Math.round(Number(v) * 1000);
  const m = /^(?:(\d+):)?([0-5]?\d):([0-5]\d)$/.exec(v);
  if (!m) return null;
  return ((Number(m[1] ?? 0) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000;
}

/** milissegundos → "0:23" ou "1:02:03". */
export function fmtMoment(ms: number): string {
  const t = Math.max(0, Math.floor(ms / 1000)); const h = Math.floor(t / 3600); const m = Math.floor((t % 3600) / 60); const s = t % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

/** ID do ficheiro a partir de um link da Drive (…/file/d/ID/…, …?id=ID) ou do próprio ID. Igual a public._drive_file_id. */
export function driveFileId(s: string): string | null {
  const v = s.trim();
  const a = /^https:\/\/(?:drive|docs)\.google\.com\/(?:.*\/)?file\/d\/([A-Za-z0-9_-]{10,200})/.exec(v) ?? /^https:\/\/drive\.google\.com\/.*[?&]id=([A-Za-z0-9_-]{10,200})/.exec(v);
  if (a) return a[1];
  return /^[A-Za-z0-9_-]{10,200}$/.test(v) ? v : null;
}

/** Player embutido e "Abrir na Drive" (opcionalmente num momento). */
export function driveLinks(id: string, tMs?: number | null) {
  const t = tMs != null ? `?t=${Math.floor(tMs / 1000)}` : "";
  return { preview: `https://drive.google.com/file/d/${id}/preview`, view: `https://drive.google.com/file/d/${id}/view${t}` };
}
