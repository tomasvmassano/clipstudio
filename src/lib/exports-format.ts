/* Formatação da página Exportados (W10-44). Puro e testado. */

type Item = {
  title: string; tags: string[]; content: { n: number; date: string; tema: string | null } | null; style: string | null;
  version_no: number | null; finished_at: string | null; created_at: string;
};

const hookOf = (tags: string[]) => tags.find((t) => /^hook_\d+$/.test(t))?.replace("hook_", "Hook ") ?? null;

/** Nome do vídeo para mostrar e para o ficheiro: "Guião 03 · Hook 1 · S17 · v2" (sem guião, o título). */
export function exportName(i: Item): string {
  const parts = i.content ? [`Guião ${String(i.content.n).padStart(2, "0")}`] : [i.title];
  const hook = hookOf(i.tags);
  if (hook) parts.push(hook);
  if (i.style) parts.push(i.style);
  if (i.version_no) parts.push(`v${i.version_no}`);
  return parts.join(" · ");
}

/** Dia (no fuso do cliente) em que ficou pronto, para agrupar: "2026-11-10". */
export function exportDay(i: Item, tz: string | null): string {
  const d = new Date(i.finished_at ?? i.created_at);
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz || "Asia/Dubai", year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
}

/** "Hoje", "Ontem" ou "seg., 9 nov." */
export function dayLabel(day: string, today: string, tz: string | null): string {
  if (day === today) return "Hoje";
  const y = new Date(`${today}T12:00:00Z`); y.setUTCDate(y.getUTCDate() - 1);
  if (day === y.toISOString().slice(0, 10)) return "Ontem";
  return new Intl.DateTimeFormat("pt-PT", { timeZone: tz || "Asia/Dubai", weekday: "short", day: "numeric", month: "short" }).format(new Date(`${day}T12:00:00Z`));
}

export function sizeText(b: number | null): string {
  if (b == null) return "";
  return b >= 1e9 ? `${(b / 1e9).toFixed(1).replace(".", ",")} GB` : `${Math.max(1, Math.round(b / 1e6))} MB`;
}

export function durText(s: number | null): string {
  if (s == null || !Number.isFinite(s)) return "";
  const m = Math.floor(s / 60), r = Math.round(s % 60);
  return m ? `${m}:${String(r).padStart(2, "0")}` : `${r} s`;
}
