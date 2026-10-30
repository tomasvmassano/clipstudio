/* Portal do cliente (W8, ADR-0041): formatação sem dependências, para testar em node. Nada aqui decide acesso. */

export type RequestStatus = "nova" | "triagem" | "selecionada" | "usada" | "descartada";
/** O que o cliente vê de cada estado de um pedido (os estados internos de triagem não aparecem pelo nome técnico). */
export const REQUEST_STATUS_LABEL: Record<RequestStatus, string> = {
  nova: "Recebido", triagem: "Em análise", selecionada: "Aceite", usada: "Em produção", descartada: "Não avança",
};
export const requestStatusLabel = (s: string) => REQUEST_STATUS_LABEL[s as RequestStatus] ?? s;

export const EDITORIAL_LABEL: Record<string, string> = {
  draft: "Rascunho", in_review: "Em revisão", changes_requested: "Alterações pedidas", approved: "Aprovado", rejected: "Rejeitado", archived: "Arquivado",
};

/** "12 de 30" quando há volume contratado; só o número quando não há (nunca inventa um alvo). */
export function ofContracted(done: number | null | undefined, contracted: number | null | undefined): string {
  const d = done ?? 0;
  return contracted === null || contracted === undefined ? String(d) : `${d} de ${contracted}`;
}

/** Percentagem para a barra (0 a 100), ou null sem volume contratado. */
export function progressPct(done: number | null | undefined, contracted: number | null | undefined): number | null {
  if (!contracted || contracted <= 0) return null;
  return Math.max(0, Math.min(100, Math.round(((done ?? 0) / contracted) * 100)));
}

/** Índice normalizado (1 = igual à mediana da própria conta) em texto PT. */
export function indexLabel(v: number | null | undefined): string {
  if (v === null || v === undefined) return "sem amostra";
  return `${String(Math.round(v * 100) / 100).replace(".", ",")}×`;
}

export const monthTitle = (iso: string) =>
  new Intl.DateTimeFormat("pt-PT", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(iso.slice(0, 10) + "T12:00:00Z"));

/** Texto de um pedido: entre 3 e 2000 caracteres (a mesma regra de talent_request_create). */
export function requestTextError(t: string): string | null {
  const s = t.trim();
  if (s.length < 3) return "Escreve pelo menos 3 caracteres.";
  if (s.length > 2000) return "No máximo 2000 caracteres.";
  return null;
}
