import { tokenize, diffWords, diffVersions, diffStats, recordedVersionNo, changed, type DiffOp } from "../src/lib/version-diff.ts";

const side = (ops: DiffOp[], keep: "del" | "add") => ops.filter((o) => o.op === "eq" || o.op === keep).map((o) => o.text).join("");
const show = (ops: DiffOp[]) => ops.map((o) => (o.op === "eq" ? o.text : o.op === "add" ? `[+${o.text}]` : `[-${o.text}]`)).join("");

const a1 = "O Numeiro ganhou 3 milhões, não foi sorte.";
const b1 = "O Numeiro perdeu 3 milhões, e não foi azar!";
const d1 = diffWords(a1, b1);
const long = Array.from({ length: 2500 }, (_, i) => `palavra${i}`).join(" ");
const longB = long.replace("palavra1200", "trocada");
const dl = diffWords(long, longB);

const v = (o: Partial<{ hooks: string[]; corpo: string; cta: string | null; formato: string | null; tema: string | null }>) => ({
  hooks: (o.hooks ?? ["Hook um", "Hook dois"]).map((text) => ({ text })), corpo: o.corpo ?? "Corpo.", cta: o.cta ?? null,
  formato: o.formato ?? "lista", tema: o.tema ?? "Tema",
});
const fv = diffVersions(v({}), v({ hooks: ["Hook um", "Hook 2", "Hook três"], cta: "Segue", formato: "tabu" }), { formato: (x) => x?.toUpperCase() ?? "" });

const cases: [string, unknown, unknown][] = [
  ["tokens com acentos e pontuação", tokenize("Olá, ação-relâmpago d'água!"), ["Olá", ",", " ", "ação-relâmpago", " ", "d'água", "!"]],
  ["tokens com números e espaços", tokenize("3,5 milhões\n\nfim"), ["3", ",", "5", " ", "milhões", "\n\n", "fim"]],
  ["juntar tokens devolve o texto", tokenize(a1).join(""), a1],
  ["vazio", tokenize(""), []],
  ["iguais: só eq", diffWords(a1, a1), [{ op: "eq", text: a1 }]],
  ["reconstrói o antes", side(d1, "del"), a1],
  ["reconstrói o depois", side(d1, "add"), b1],
  ["palavras trocadas e pontuação", show(d1), "O Numeiro [-ganhou][+perdeu] 3 milhões, [+e ]não foi [-sorte.][+azar!]"],
  ["só acrescentar", diffWords("", "novo texto"), [{ op: "add", text: "novo texto" }]],
  ["só remover", diffWords("velho", ""), [{ op: "del", text: "velho" }]],
  ["palavras vizinhas agrupadas", show(diffWords("a b c d", "a x y d")), "a [-b c][+x y] d"],
  ["maiúsculas contam", changed(diffWords("Olá", "olá")), true],
  ["texto longo: reconstrói", side(dl, "add") === longB && side(dl, "del") === long, true],
  ["texto longo: só a palavra trocada", dl.filter((o) => o.op !== "eq").map((o) => o.text), ["palavra1200", "trocada"]],
  ["hooks por posição + hook novo", fv.filter((f) => f.key.startsWith("hook")).map((f) => [f.label, f.status]), [["Hook 1", "same"], ["Hook 2", "changed"], ["Hook 3", "added"]]],
  ["cta acrescentado", fv.find((f) => f.key === "cta")?.status, "added"],
  ["formato com rótulo", show(fv.find((f) => f.key === "formato")!.ops), "[-LISTA][+TABU]"],
  ["tema igual", fv.find((f) => f.key === "tema")?.changed, false],
  ["hook removido", diffVersions(v({ hooks: ["a", "b"] }), v({ hooks: ["a"] }))[1].status, "removed"],
  ["estatística", diffStats(fv), { added: 5, removed: 2, fields: 4 }],
  ["versão gravada: última marcação (não a volta da edição)", recordedVersionNo([
    { kind: "production", from: "editing", to: "recorded", version_no: 5 },
    { kind: "editorial", from: "in_review", to: "approved", version_no: 4 },
    { kind: "production", from: "not_started", to: "recorded", version_no: 3 },
    { kind: "production", from: null, to: "recorded", version_no: 1 },
  ]), 3],
  ["versão gravada: nenhuma", recordedVersionNo([{ kind: "editorial", from: null, to: "draft", version_no: 1 }]), null],
];
let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`version-diff: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
