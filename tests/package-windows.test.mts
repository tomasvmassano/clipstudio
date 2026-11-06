import { clockText, clipTime, itemText, packageWindows, windowReason, windowRows } from "../src/lib/package-windows.ts";

const result = {
  documents: [],
  windows: {
    clock: { ok: true, method: "transcricao+hora_do_ficheiro", anchors: 3, support: 3, session: "s1" },
    items: {
      g1: { source: "marks", reason: null, windows: [[14, 95.5], [3600, 3625]], passes: 2, takes: 2, agree: true, hooks: ["hook_1", "hook_2"] },
      g2: { source: "transcript", reason: "sem_marcas", windows: [[200, 320]], passes: 0, takes: 0, agree: null, hooks: [] },
      g3: { source: "marks", reason: null, windows: [[400, 470]], passes: 1, takes: 0, agree: false, hooks: [] },
      g4: { source: "transcript", reason: "fora_do_ficheiro", windows: [], passes: 0, takes: 0, agree: null, hooks: [] },
    },
  },
};
const w = packageWindows(result)!;
const rows = windowRows(w, [{ id: "g1", n: 1, tema: "Casas" }, { id: "g2", n: 2, tema: null }, { id: "g3", n: 3, tema: "Ouro" }, { id: "g4", n: 4, tema: "x" }, { id: "g9", n: 9, tema: "não reportado" }]);
const cases: [string, unknown, unknown][] = [
  ["sem resultado", packageWindows(null), null],
  ["worker antigo (sem windows)", packageWindows({ documents: [] }), null],
  ["mal formado", packageWindows({ windows: { clock: null, items: {} } }), null],
  ["relógio acertado", clockText(w.clock), "Marcas do teleprompter acertadas com a câmara pela transcrição, confirmado pela hora da câmara (3 de 3 guiões a concordar)."],
  ["relógio não usado", clockText({ ok: false, reason: "marcas_inconsistentes" }), "Marcas do teleprompter não usadas: as marcas não batem certo com a transcrição. Janelas só pela transcrição."],
  ["pedido sem marcas", clockText({ ok: false, reason: "pedido_sem_marcas" }), "Marcas do teleprompter não usadas: o pedido não trouxe marcas do teleprompter. Janelas só pela transcrição."],
  ["motivo desconhecido", windowReason("xpto"), "motivo desconhecido"],
  ["sem motivo", windowReason(null), null],
  ["tempo", clipTime(95.5), "1:36"],
  ["tempo com horas", clipTime(3625), "1:00:25"],
  ["linhas pela ordem e só as reportadas", rows.map((r) => r.id).join(","), "g1,g2,g3,g4"],
  ["marcas com passagens, hooks e takes", JSON.stringify(itemText(w.items.g1)),
    JSON.stringify({ source: "marcas do teleprompter", detail: "2 passagens · hooks 1, 2 · 2 takes marcados", windows: "0:14-1:36, 1:00:00-1:00:25", warn: false })],
  ["transcrição com motivo", rows[1].detail, "o teleprompter não registou leituras deste guião"],
  ["transcrição não confirma: aviso", rows[2].warn && rows[2].detail === "a transcrição não confirma", true],
  ["sem janela: aviso", rows[3].warn && rows[3].windows === "não encontrado na gravação", true],
];
let fail = 0;
for (const [name, got, want] of cases) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { fail++; console.error(`FAIL ${name}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`); }
}
console.log(`package-windows: ${cases.length - fail}/${cases.length}`);
if (fail) process.exit(1);
