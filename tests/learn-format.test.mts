import { hours, pct, toCsv, eur } from "../src/lib/learn-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
eq("csv: cabeçalho e números com vírgula", toCsv(["a", "b"], [[1.5, "x"]]), "a;b\r\n1,5;x");
eq("csv: aspas e ponto e vírgula", toCsv(["a"], [['di"z; isto']]), 'a\r\n"di""z; isto"');
eq("csv: fórmula neutralizada", toCsv(["a"], [["=SOMA(A1)"]]), "a\r\n'=SOMA(A1)");
eq("csv: nulo vazio, nunca 0", toCsv(["a"], [[null]]), "a\r\n");
eq("pct", pct(0.256), "26%");
eq("pct sem decisões", pct(null), "sem decisões");
eq("horas", hours(5.5), "5,5 h");
eq("dias", hours(72), "3 dias");
eq("sem custo conhecido nunca é zero", eur(null), "sem custo conhecido");
console.log(`learn-format: ${n - bad}/${n}`);
if (bad) process.exit(1);
