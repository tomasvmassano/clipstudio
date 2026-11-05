/** Sessões e dispositivos (W10-08, FR-14-03): funções puras, sem rede, testadas em tests/session-format.test.mts. */

export type DeviceKind = "desktop" | "mobile" | "tablet" | "unknown";
export type Device = { browser: string | null; os: string | null; kind: DeviceKind; label: string };

const BROWSERS: [RegExp, string][] = [
  [/\bEdg(?:e|A|iOS)?\//, "Edge"],
  [/\b(?:OPR|Opera)\//, "Opera"],
  [/\bSamsungBrowser\//, "Samsung Internet"],
  [/\bFirefox\/|\bFxiOS\//, "Firefox"],
  [/\bCriOS\/|\bChrome\/|\bChromium\//, "Chrome"],
  [/\bVersion\/[\d.]+.*\bSafari\/|\b(?:iPhone|iPad).*AppleWebKit(?!.*(?:CriOS|FxiOS|EdgiOS))/, "Safari"],
  [/\bcurl\//i, "curl"],
  [/\bnode(?:-fetch)?\b|\bundici\b/i, "Node.js"],
  [/\bsupabase-js\b|\bgotrue-js\b/i, "App"],
];

/** Lê o user agent guardado pelo Supabase Auth e devolve um nome de dispositivo em PT-PT. Nunca falha. */
export function parseDevice(ua: string | null | undefined): Device {
  const s = (ua ?? "").trim();
  if (!s) return { browser: null, os: null, kind: "unknown", label: "Dispositivo desconhecido" };
  let os: string | null = null; let kind: DeviceKind = "unknown";
  if (/\biPad\b/.test(s)) { os = "iPadOS"; kind = "tablet"; }
  else if (/\biPhone\b|\biPod\b/.test(s)) { os = "iOS"; kind = "mobile"; }
  else if (/\bAndroid\b/.test(s)) { os = "Android"; kind = /\bMobile\b/.test(s) ? "mobile" : "tablet"; }
  else if (/\bWindows\b/.test(s)) { os = "Windows"; kind = "desktop"; }
  else if (/\bCrOS\b/.test(s)) { os = "ChromeOS"; kind = "desktop"; }
  else if (/\bMac OS X\b|\bMacintosh\b/.test(s)) { os = "macOS"; kind = "desktop"; }
  else if (/\bLinux\b|\bX11\b/.test(s)) { os = "Linux"; kind = "desktop"; }
  const browser = BROWSERS.find(([re]) => re.test(s))?.[1] ?? null;
  const label = browser && os ? `${browser} em ${os}` : browser ?? os ?? "Dispositivo desconhecido";
  return { browser, os, kind, label };
}

export type SessionRow = {
  id: string; user_agent: string | null; ip: string | null; created_at: string; last_active_at: string | null;
  aal: string | null; not_after: string | null; current: boolean;
};

/** "agora mesmo", "há 5 min", "há 3 h", "há 2 dias"; datas no futuro (relógio adiantado) contam como agora. */
export function agoLabel(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return "sem registo";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "sem registo";
  const min = Math.floor(Math.max(0, now - t) / 60000);
  if (min < 2) return "agora mesmo";
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.floor(h / 24);
  return d === 1 ? "há 1 dia" : `há ${d} dias`;
}

/** A atual primeiro, depois a mais recente. Não altera a lista recebida. */
export function sortSessions(rows: SessionRow[]): SessionRow[] {
  const ts = (r: SessionRow) => Date.parse(r.last_active_at ?? r.created_at) || 0;
  return [...rows].sort((a, b) => Number(b.current) - Number(a.current) || ts(b) - ts(a));
}
