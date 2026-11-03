/* Pré-visualização (BIZ-07): funções puras, sem rede; testadas em tests/preview.test.mts. */
export type Preview = {
  workspace_id: string; kind: "role" | "user"; role: string | null; label: string;
  started_at: string; expires_at: string; capabilities: string[];
};

/** Ainda ativa a esta hora (a lista vem do servidor; isto só esconde a faixa quando o prazo passa com a página aberta). */
export const isActive = (p: Preview | null | undefined, now = Date.now()) => !!p && new Date(p.expires_at).getTime() > now;

/** "até 14:32", no fuso do cliente. */
export function untilLabel(iso: string, tz: string): string {
  try { return new Date(iso).toLocaleTimeString("pt-PT", { hour: "2-digit", minute: "2-digit", timeZone: tz }); }
  catch { return new Date(iso).toISOString().slice(11, 16) + " UTC"; }
}
