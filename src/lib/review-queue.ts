/** Utilitários puros da revisão em lote (W5-12, EDL-02): fila "seguinte" e valores do QC. */
/** Valor de um check do QC em texto curto (números com 1 casa, listas de troços como "0:03 (1.2 s)"). */
export function qcValue(v: unknown): string {
  if (v == null) return "—";
  if (typeof v === "number") return String(Math.round(v * 10) / 10);
  if (Array.isArray(v)) {
    if (v.length === 0) return "nenhum";
    return v.slice(0, 4).map((x) => (Array.isArray(x) && x.length === 2 ? `${Math.floor(Number(x[0]) / 60)}:${String(Math.floor(Number(x[0]) % 60)).padStart(2, "0")} (${x[1]} s)` : String(x))).join(", ")
      + (v.length > 4 ? ` +${v.length - 4}` : "");
  }
  return String(v);
}

/** Próximo vídeo a rever na fila (depois do atual, pela ordem da lista; volta ao início). null se não houver mais. */
export function nextInQueue(items: { asset_id: string; status: string }[], current: string): string | null {
  const i = items.findIndex((x) => x.asset_id === current);
  const order = [...items.slice(i + 1), ...items.slice(0, Math.max(i, 0))];
  return order.find((x) => x.asset_id !== current && (x.status === "in_review" || x.status === "changes_requested"))?.asset_id ?? null;
}
