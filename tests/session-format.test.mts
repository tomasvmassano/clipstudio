import { agoLabel, parseDevice, sortSessions, type SessionRow } from "../src/lib/session-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };

const UA = {
  macChrome: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
  macSafari: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
  iphone: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  iphoneChrome: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0 Mobile/15E148 Safari/604.1",
  ipad: "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
  android: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36",
  androidTab: "Mozilla/5.0 (Linux; Android 13; SM-X700) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
  winEdge: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 Edg/130.0",
  winFirefox: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0",
  linux: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
  samsung: "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0 Mobile Safari/537.36",
  opera: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 OPR/115.0",
};

eq("Chrome no Mac", parseDevice(UA.macChrome), { browser: "Chrome", os: "macOS", kind: "desktop", label: "Chrome em macOS" });
eq("Safari no Mac", parseDevice(UA.macSafari).label, "Safari em macOS");
eq("Safari no iPhone", parseDevice(UA.iphone), { browser: "Safari", os: "iOS", kind: "mobile", label: "Safari em iOS" });
eq("Chrome no iPhone", parseDevice(UA.iphoneChrome).label, "Chrome em iOS");
eq("iPad é tablet", parseDevice(UA.ipad), { browser: "Safari", os: "iPadOS", kind: "tablet", label: "Safari em iPadOS" });
eq("Android telemóvel", parseDevice(UA.android), { browser: "Chrome", os: "Android", kind: "mobile", label: "Chrome em Android" });
eq("Android tablet", parseDevice(UA.androidTab).kind, "tablet");
eq("Edge antes de Chrome", parseDevice(UA.winEdge).label, "Edge em Windows");
eq("Firefox no Windows", parseDevice(UA.winFirefox).label, "Firefox em Windows");
eq("Chrome no Linux", parseDevice(UA.linux).label, "Chrome em Linux");
eq("Samsung Internet", parseDevice(UA.samsung).label, "Samsung Internet em Android");
eq("Opera", parseDevice(UA.opera).label, "Opera em Windows");
eq("curl", parseDevice("curl/8.5.0"), { browser: "curl", os: null, kind: "unknown", label: "curl" });
eq("vazio", parseDevice(""), { browser: null, os: null, kind: "unknown", label: "Dispositivo desconhecido" });
eq("null", parseDevice(null).label, "Dispositivo desconhecido");
eq("lixo", parseDevice("???").label, "Dispositivo desconhecido");

const now = Date.parse("2026-11-06T12:00:00Z");
eq("agora", agoLabel("2026-11-06T11:59:30Z", now), "agora mesmo");
eq("minutos", agoLabel("2026-11-06T11:45:00Z", now), "há 15 min");
eq("horas", agoLabel("2026-11-06T09:00:00Z", now), "há 3 h");
eq("1 dia", agoLabel("2026-11-05T11:00:00Z", now), "há 1 dia");
eq("dias", agoLabel("2026-11-01T12:00:00Z", now), "há 5 dias");
eq("futuro conta como agora", agoLabel("2026-11-06T12:05:00Z", now), "agora mesmo");
eq("sem data", agoLabel(null, now), "sem registo");
eq("data inválida", agoLabel("x", now), "sem registo");

const row = (id: string, last: string, current = false): SessionRow => ({ id, user_agent: null, ip: null, created_at: "2026-11-01T00:00:00Z", last_active_at: last, aal: "aal1", not_after: null, current });
const input = [row("a", "2026-11-02T00:00:00Z"), row("b", "2026-11-05T00:00:00Z"), row("c", "2026-11-01T00:00:00Z", true)];
eq("atual primeiro, depois mais recente", sortSessions(input).map((r) => r.id), ["c", "b", "a"]);
eq("não altera a lista original", input.map((r) => r.id), ["a", "b", "c"]);

console.log(`session-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
