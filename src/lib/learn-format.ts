/* Aprendizagem e custos (W7, ADR-0037): formatação sem dependências, para testar em node. */

const csvCell = (v: unknown) => {
  if (v === null || v === undefined) return "";
  const s = String(v);
  // evita fórmulas ao abrir numa folha de cálculo (injeção CSV)
  const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s;
  return /[";\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
};
/** CSV com ponto e vírgula (Excel PT) e números com vírgula decimal. */
export function toCsv(header: string[], rows: unknown[][]): string {
  const num = (v: unknown) => (typeof v === "number" ? String(v).replace(".", ",") : v);
  return [header, ...rows].map((r) => r.map((c) => csvCell(num(c))).join(";")).join("\r\n");
}
export const eur = (v: number | null | undefined, digits = 2) =>
  v === null || v === undefined ? "sem custo conhecido"
    : new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR", minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v);
export const pct = (v: number | null | undefined) => (v === null || v === undefined ? "sem decisões" : `${Math.round(v * 100)}%`);
const dec = (v: number) => String(v).replace(".", ",");
export const hours = (v: number | null | undefined) =>
  v === null || v === undefined ? "sem dados" : v < 48 ? `${dec(v)} h` : `${dec(Math.round(v / 2.4) / 10)} dias`;
export const monthLabel = (m: string) => new Intl.DateTimeFormat("pt-PT", { month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(m + "-01T12:00:00Z"));
