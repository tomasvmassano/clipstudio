import { nextInQueue, qcValue } from "../src/lib/review-queue.ts";
const q = [
  { asset_id: "a", status: "approved" }, { asset_id: "b", status: "in_review" }, { asset_id: "c", status: "rejected" },
  { asset_id: "d", status: "changes_requested" }, { asset_id: "e", status: "in_review" },
];
const cases: [string, unknown, unknown][] = [
  ["seguinte salta decididos", nextInQueue(q, "b"), "d"],
  ["seguinte depois do último volta ao início", nextInQueue(q, "e"), "b"],
  ["a partir de um aprovado", nextInQueue(q, "a"), "b"],
  ["fila vazia", nextInQueue([], "x"), null],
  ["só o atual por rever", nextInQueue([{ asset_id: "x", status: "in_review" }, { asset_id: "y", status: "approved" }], "x"), null],
  ["atual fora da lista", nextInQueue(q, "zz"), "b"],
  ["número", qcValue(-20.14), "-20.1"],
  ["nulo", qcValue(null), "—"],
  ["sem troços", qcValue([]), "nenhum"],
  ["troços", qcValue([[3.2, 1.5], [65, 0.8]]), "0:03 (1.5 s), 1:05 (0.8 s)"],
  ["muitos troços", qcValue([[1, 1], [2, 1], [3, 1], [4, 1], [5, 1]]).endsWith("+1"), true],
  ["texto", qcValue("1080x1920"), "1080x1920"],
];
let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`review-queue: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
