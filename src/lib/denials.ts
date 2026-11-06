/*
 * Tentativas recusadas → audit_events (PRD R-05, ADR-0066).
 *
 * As RPCs recusam com 42501 e o RAISE desfaz a transação, por isso a recusa não pode ficar gravada no mesmo pedido.
 * Este módulo embrulha o fetch do cliente Supabase (browser e rotas /api): quando uma chamada /rest/v1/rpc/<fn> volta
 * com o código 42501, faz um segundo pedido, com os mesmos cabeçalhos de sessão, a audit_denied_record, que grava a
 * recusa numa transação própria. Quem é a pessoa decide o servidor (auth.uid()); daqui só vão o cliente, a função
 * chamada, o id do recurso e um id de correlação. Nunca vão tokens (p_token e afins não são lidos).
 *
 * Sem imports com "@/": é testado com node --experimental-strip-types (tests/denials.test.mts).
 */

export type DenialReport = {
  p_ws: string | null; p_action: string; p_entity: string | null; p_code: "42501";
  p_capability: string | null; p_via: "browser" | "api"; p_correlation: string | null;
};

type Fetch = typeof fetch;
export type DenialOptions = {
  via: "browser" | "api";
  /** Espera pelo registo antes de devolver a resposta (servidor: a função serverless pode parar logo a seguir). */
  awaitReport?: boolean;
  /** Cliente atual quando a RPC não traz p_ws (o browser lê-o do endereço /c/<cliente>/…). */
  currentWs?: () => string | null;
  now?: () => number;
  /** Para testes. */
  onReport?: (r: DenialReport) => void;
};

export const RECORD_FN = "audit_denied_record";
const DEDUP_MS = 60_000;
const TIMEOUT_MS = 1500;
const WS_RE = /^[a-z0-9_-]{1,60}$/;
const ACTION_RE = /^[a-z0-9_]{1,70}$/;
/** Argumentos que identificam o recurso, por ordem de preferência. Tokens nunca entram. */
const ENTITY_KEYS = ["p_id", "p_version", "p_asset", "p_content", "p_content_id", "p_guiao", "p_task", "p_job", "p_user", "p_invitation"];

/** Função chamada, se o pedido for uma RPC do PostgREST. */
export function rpcName(url: string): string | null {
  const m = /\/rest\/v1\/rpc\/([A-Za-z0-9_]+)(?:\?|$)/.exec(url);
  return m ? m[1] : null;
}

/** Cliente do endereço /c/<cliente>/… (só uma pista: o servidor volta a verificar a pertença). */
export function wsFromPath(path: string): string | null {
  const m = /^\/c\/([^/?#]+)/.exec(path);
  if (!m) return null;
  const ws = decodeURIComponent(m[1]);
  return WS_RE.test(ws) ? ws : null;
}

function parseArgs(body: unknown): Record<string, unknown> {
  if (typeof body !== "string" || !body) return {};
  try { const v = JSON.parse(body); return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {}; } catch { return {}; }
}

/** O que se envia a audit_denied_record a partir da RPC recusada. */
export function buildReport(fn: string, body: unknown, via: "browser" | "api", fallbackWs: string | null, correlation: string | null): DenialReport | null {
  if (!ACTION_RE.test(fn) || fn === RECORD_FN) return null;
  const a = parseArgs(body);
  const ws = typeof a.p_ws === "string" && WS_RE.test(a.p_ws) ? a.p_ws : fallbackWs;
  let entity: string | null = null;
  for (const k of ENTITY_KEYS) {
    const v = a[k];
    if (typeof v === "string" && v) { entity = v.slice(0, 120); break; }
    if (typeof v === "number" && Number.isFinite(v)) { entity = String(v); break; }
  }
  return { p_ws: ws, p_action: `rpc:${fn}`, p_entity: entity, p_code: "42501", p_capability: null, p_via: via, p_correlation: correlation };
}

/** Só sessões individuais: sem Authorization, ou com a chave pública no lugar do JWT, não há quem registar. */
export function sessionHeaders(init: RequestInit | undefined): Record<string, string> | null {
  const h = new Headers(init?.headers);
  const auth = h.get("authorization"); const key = h.get("apikey");
  if (!auth || !/^Bearer\s+\S+\.\S+\.\S+$/.test(auth) || (key && auth === `Bearer ${key}`)) return null;
  const out: Record<string, string> = { authorization: auth, "content-type": "application/json" };
  if (key) out.apikey = key;
  return out;
}

const uuid = () => (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function" ? crypto.randomUUID() : null);

/** Embrulha o fetch: a resposta original segue intacta; a recusa é registada num pedido à parte (sem repetir em 60 s). */
export function withDenialAudit(base: Fetch, opts: DenialOptions): Fetch {
  const seen = new Map<string, number>();
  const now = opts.now ?? Date.now;
  const wrapped = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const res = await base(input, init);
    if (res.status !== 401 && res.status !== 403) return res;
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const fn = rpcName(url);
    if (!fn || fn === RECORD_FN) return res;
    const job = (async () => {
      let code: unknown;
      try { code = ((await res.clone().json()) as { code?: unknown })?.code; } catch { return; }
      if (code !== "42501") return;
      const headers = sessionHeaders(init);
      if (!headers) return;
      const report = buildReport(fn, init?.body, opts.via, opts.currentWs?.() ?? null, uuid());
      if (!report) return;
      const key = `${report.p_action}|${report.p_ws ?? ""}|${report.p_entity ?? ""}`;
      const t = now(); const last = seen.get(key);
      if (last !== undefined && t - last < DEDUP_MS) return;
      if (seen.size > 200) seen.clear();
      seen.set(key, t);
      opts.onReport?.(report);
      const target = url.replace(/\/rpc\/[A-Za-z0-9_]+.*$/, `/rpc/${RECORD_FN}`);
      const ctl = typeof AbortController !== "undefined" ? new AbortController() : null;
      const timer = ctl ? setTimeout(() => ctl.abort(), TIMEOUT_MS) : null;
      try { await base(target, { method: "POST", headers, body: JSON.stringify(report), signal: ctl?.signal }); }
      catch { /* o registo é melhor-esforço: o RAISE LOG da base continua a existir; nunca estraga a resposta original */ }
      finally { if (timer) clearTimeout(timer); }
    })();
    if (opts.awaitReport) await job;
    else void job;
    return res;
  };
  return wrapped as Fetch;
}
