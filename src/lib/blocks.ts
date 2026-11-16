/* Blocos do corpo de um guião (FR-03-02, W10-46). Puro e testado; recording.ts reexporta. */

/** Uma linha "## Nome" no corpo começa um bloco personalizado (FR-03-02). */
export const MARKER = /^\s*##\s*(\S.*)$/;

/** Um bloco é um CTA quando é o CTA do guião ou um bloco personalizado com nome "CTA…" (ex.: CTA 1, CTA 2), W10-46. */
export const isCtaBlock = (b: { key: string; label: string }) => b.key === "cta" || /^cta\b/i.test(b.label.trim());

/** Corpo do guião partido em blocos para mostrar: o texto antes da primeira marca e cada bloco "## Nome" (sem linhas vazias). */
export function corpoParts(corpo: string): { label: string | null; lines: string[] }[] {
  const out: { label: string | null; lines: string[] }[] = [{ label: null, lines: [] }];
  for (const line of (corpo ?? "").split("\n")) {
    const m = line.match(MARKER);
    if (m) out.push({ label: m[1].trim(), lines: [] });
    else if (line.trim()) out[out.length - 1].lines.push(line.trim());
  }
  return out.filter((p) => p.label !== null || p.lines.length);
}
