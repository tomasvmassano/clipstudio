/**
 * Só aceita destinos internos depois de entrar (evita open redirect).
 * O parser de URL do browser remove tabs/newlines, por isso "/\t/evil.com" viraria "//evil.com":
 * recusamos caracteres de controlo e confirmamos que a origem resolvida é a nossa.
 */
export function safeNext(next: string | null | undefined, origin = "http://local.invalid"): string {
  if (!next || !next.startsWith("/") || /[\u0000-\u001f\u007f\\]/.test(next)) return "/";
  try {
    const u = new URL(next, origin);
    if (u.origin !== new URL(origin).origin) return "/";
    return u.pathname + u.search + u.hash;
  } catch {
    return "/";
  }
}
