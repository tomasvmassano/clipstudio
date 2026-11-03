import { fmtIdx, idxMissingReason, idxTone, fmtPct } from "../src/lib/perf-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
eq("2 -> 2,0×", fmtIdx(2), "2,0×");
eq("string", fmtIdx("0.667"), "0,67×");
eq("nulo fica vazio, nunca 0", fmtIdx(null), "");
eq("NaN vazio", fmtIdx("x"), "");
eq("forte", idxTone(1.5), "strong");
eq("fraco", idxTone(0.49), "weak");
eq("normal", idxTone(1), "normal");
eq("sem índice", idxTone(null), "none");
eq("percentagem", fmtPct(0.25), "25%");
eq("sem leitura", idxMissingReason(undefined, 5), "Sem leitura nessa idade");
eq("base curta", idxMissingReason({ views: 50, base_n: 2 }, 5), "Amostra insuficiente (2 de 5 na base)");
console.log(`perf-format ${n - bad}/${n}`);
if (bad) process.exit(1);
