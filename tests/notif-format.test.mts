import { fmtInTz, groupBy, muteUntil, personalLock, suppressedLine } from "../src/lib/notif-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };

const g = groupBy([{ group: "guioes" as const, k: 1 }, { group: "tarefas" as const, k: 2 }, { group: "tarefas" as const, k: 3 }]);
eq("grupos pela ordem fixa", g.map((x) => x.group).join(","), "tarefas,guioes");
eq("grupo vazio não aparece", g.length, 2);
eq("sem supressões: linha vazia", suppressedLine([], "task_done"), "");
eq("sem supressões (nulo)", suppressedLine(null, "task_done"), "");
eq("supressões somadas e explicadas", suppressedLine([{ kind: "task_done", reason: "org_off", n: 2 }, { kind: "task_done", reason: "muted", n: 1 }, { kind: "x", reason: "muted", n: 9 }], "task_done"),
  "3 não criadas nos últimos 30 dias (2 desligadas pelo cliente, 1 com o cliente silenciado)");
eq("singular", suppressedLine([{ kind: "a", reason: "user_off", n: 1 }], "a"), "1 não criada nos últimos 30 dias (1 desligadas pela pessoa)");
eq("obrigatório: motivo do catálogo", personalLock({ allowed: true, locked: true }, "Atribuições não se desligam."), "Atribuições não se desligam.");
eq("obrigatório pelo cliente", personalLock({ allowed: true, locked: true }, null), "Este cliente tornou esta notificação obrigatória.");
eq("desligado pelo cliente", personalLock({ allowed: false, locked: false }, null), "Desligada neste cliente por quem gere as definições.");
eq("livre", personalLock({ allowed: true, locked: false }, null), null);
const now = new Date("2026-10-30T10:00:00Z");
eq("silenciar 8 h em UTC", muteUntil("8h", now), "2026-10-30T18:00:00.000Z");
eq("silenciar sem fim", muteUntil("forever", now), null);
let threw = false; try { muteUntil("zzz", now); } catch { threw = true; }
eq("opção desconhecida falha", threw, true);
eq("hora mostrada no fuso do cliente", fmtInTz("2026-10-30T18:00:00Z", "Asia/Dubai").includes("22:00"), true);
eq("fuso inválido cai para UTC e diz", fmtInTz("2026-10-30T18:00:00Z", "Nao/Existe").endsWith("UTC"), true);
console.log(`notif-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
