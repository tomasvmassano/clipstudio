/*
 * O cliente aberto vive no endereço: /c/<cliente>/<página> (ADR-0018).
 * O espaço da agência é tudo o que não começa por /c/. O servidor continua a verificar o acesso em cada pedido.
 */
export function wsIdFromPath(path: string | null | undefined): string | null {
  const m = path?.match(/^\/c\/([^/?#]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}
/** Caminho dentro de um cliente; sub "/" ou "" é o Início do cliente. */
export function clientPath(ws: string, sub = ""): string {
  const s = sub === "/" ? "" : sub;
  return `/c/${encodeURIComponent(ws)}${s}`;
}
/** Caminho sem o prefixo do cliente (para saber que página está aberta). */
export function stripWs(path: string): string {
  return path.replace(/^\/c\/[^/]+/, "") || "/";
}
/** Para navegações feitas em código (handlers): usa o cliente do endereço atual. */
export function wsPath(sub: string): string {
  const ws = typeof window === "undefined" ? null : wsIdFromPath(window.location.pathname);
  return ws ? clientPath(ws, sub) : sub;
}
