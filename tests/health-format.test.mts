import { ago, heartbeatState, jobPath, kindLabel, overallTone, redactSecrets } from "../src/lib/health-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
const ok = (name: string, cond: boolean) => eq(name, cond, true);
const now = Date.parse("2026-11-06T12:00:00Z");

eq("nunca", ago(null, now), "nunca");
eq("segundos", ago("2026-11-06T11:59:30Z", now), "há menos de 1 min");
eq("minutos", ago("2026-11-06T11:45:00Z", now), "há 15 min");
eq("horas", ago("2026-11-06T09:00:00Z", now), "há 3 h");
eq("dias", ago("2026-11-03T12:00:00Z", now), "há 3 dias");
eq("futuro", ago("2026-11-06T12:01:00Z", now), "agora");
eq("data inválida", ago("x", now), "nunca");

eq("lease expirada ganha", heartbeatState({ heartbeat_at: "2026-11-06T11:59:50Z", lease_expired: true }, now), "parado");
eq("heartbeat recente", heartbeatState({ heartbeat_at: "2026-11-06T11:59:00Z", lease_expired: false }, now), "ok");
eq("heartbeat atrasado", heartbeatState({ heartbeat_at: "2026-11-06T11:50:00Z", lease_expired: false }, now), "atrasado");
eq("sem heartbeat", heartbeatState({ heartbeat_at: null, lease_expired: false }, now), "atrasado");

eq("agentes", jobPath("agent", "daily_pipeline", null), "/agentes/configuracao");
eq("export com ativo", jobPath("media", "export", "a b"), "/editor?asset=a%20b");
eq("export sem ativo", jobPath("media", "export", null), "/biblioteca");
eq("pacote", jobPath("media", "package", "x"), "/edicao-automatica");
eq("ingest", jobPath("media", "ingest", "x"), "/biblioteca");
eq("tipo conhecido", kindLabel("ingest"), "Verificar envio");
eq("tipo desconhecido tal como vem", kindLabel("novo"), "novo");

const r = redactSecrets("HTTP 401 Bearer abc.def token=s3cr3t https://u:pa55@h.pt/x sk-ant-abcdefghijklmnop eyJhbGciOiJ.eyJzdWIiOiIx.sig ana@exemplo.pt sha 9f86d081");
ok("bearer removido", !r.includes("abc.def"));
ok("token removido", !r.includes("s3cr3t"));
ok("palavra-passe do URL removida", !r.includes("pa55") && r.includes("https://[removido]@h.pt"));
ok("chave removida", !r.includes("sk-ant-abcdef"));
ok("JWT removido", !r.includes("eyJhbGci"));
ok("email removido", !r.includes("ana@exemplo.pt"));
ok("o resto fica", r.includes("HTTP 401") && r.includes("sha 9f86d081"));
eq("vazio", redactSecrets(null), "");

eq("fila sem worker: crítico", overallTone([{ uncovered: 1, stalled: 0 }], 0), "bad");
eq("dead nas 24 h: aviso", overallTone([{ uncovered: 0, stalled: 0 }], 2), "warn");
eq("tudo bem", overallTone([{ uncovered: 0, stalled: 0 }], 0), "good");

console.log(`health-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
