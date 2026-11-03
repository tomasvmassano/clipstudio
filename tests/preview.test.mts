import { isActive, untilLabel } from "../src/lib/preview-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
const p = { workspace_id: "w", kind: "role" as const, role: "viewer", label: "viewer", started_at: "2026-11-04T10:00:00Z", expires_at: "2026-11-04T10:30:00Z", capabilities: [] };
eq("ativa antes do prazo", isActive(p, Date.parse("2026-11-04T10:29:00Z")), true);
eq("inativa depois do prazo", isActive(p, Date.parse("2026-11-04T10:31:00Z")), false);
eq("sem pré-visualização", isActive(null), false);
eq("hora no fuso do cliente", untilLabel("2026-11-04T10:30:00Z", "Asia/Dubai"), "14:30");
eq("fuso inválido cai para UTC", untilLabel("2026-11-04T10:30:00Z", "Nao/Existe"), "10:30 UTC");
console.log(`preview: ${n - bad}/${n}`);
if (bad) process.exit(1);
