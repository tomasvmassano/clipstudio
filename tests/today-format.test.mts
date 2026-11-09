import { formatMix, liveToday } from "../src/lib/today-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
const L = { lista: "Lista", mito: "Mito" };
const day = [
  { formato: "lista", status: "aprovado", editorial_status: "approved" },
  { formato: "lista", status: "aprovado", editorial_status: "archived" },
  { formato: "mito", status: "aprovado", editorial_status: "in_review" },
  { formato: "mito", status: "aprovado", editorial_status: "draft", deleted_at: "2026-11-09T10:00:00Z" },
  { formato: "mito", status: "rejeitado", editorial_status: "rejected" },
];
eq("arquivados e eliminados fora dos guiões do dia", liveToday(day).length, 3);
eq("formatos de hoje: arquivado, eliminado e rejeitado não contam", formatMix(day, L),
  { total: 2, mix: [{ key: "lista", label: "Lista", share: 50 }, { key: "mito", label: "Mito", share: 50 }] });
eq("só arquivados: vazio", formatMix([{ formato: "lista", editorial_status: "archived" }], L), { total: 0, mix: [] });
eq("mais de 4 formatos juntam-se em outros", formatMix(["a", "b", "c", "d", "e", "e"].map((f) => ({ formato: f })), {}).mix.map((x) => x.key), ["e", "a", "b", "c", "outros"]);
eq("sem formato conta como outros", formatMix([{ formato: null }], {}).mix, [{ key: "outros", label: "outros", share: 100 }]);
console.log(`today-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
