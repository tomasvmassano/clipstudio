/*
 * Início → widgets do dia (Formatos de hoje, Guiões de hoje). Sem dependências, para testar em node.
 * Contam só os guiões vivos do dia: arquivados (editorial_status = 'archived') e eliminados (deleted_at) ficam de fora;
 * os rejeitados (status 'rejeitado') continuam fora da mistura de formatos, como antes. W10-22 (ADR-0071).
 */
export type TodayScript = { formato?: string | null; status?: string | null; editorial_status?: string | null; deleted_at?: string | null };

/** Guiões do dia que contam no Início: sem arquivados nem eliminados. */
export const liveToday = <T extends TodayScript>(day: T[]): T[] =>
  day.filter((g) => g.editorial_status !== "archived" && !g.deleted_at);

export type FormatSlice = { key: string; label: string; share: number };

/** Mistura de formatos: os 4 mais frequentes e o resto em "outros"; percentagens sobre os guiões contados. */
export function formatMix(day: TodayScript[], labels: Record<string, string>): { total: number; mix: FormatSlice[] } {
  const ok = liveToday(day).filter((g) => g.status !== "rejeitado");
  const count = new Map<string, number>();
  ok.forEach((g) => count.set(g.formato ?? "outros", (count.get(g.formato ?? "outros") ?? 0) + 1));
  const sorted = [...count.entries()].sort((a, b) => b[1] - a[1]);
  const rest = sorted.slice(4).reduce((t, [, n]) => t + n, 0);
  const mix = [...sorted.slice(0, 4), ...(rest ? [["outros", rest] as [string, number]] : [])].map(([k, n]) => ({
    key: k.replace(/[^a-z0-9]/gi, "_"), label: labels[k] ?? k, share: Math.round((n / Math.max(1, ok.length)) * 100),
  }));
  return { total: ok.length, mix };
}
