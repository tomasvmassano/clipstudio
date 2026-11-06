import { checkForHook, parseVerification, summary, worst, type VerifierResult } from "../src/lib/verifier-format.ts";

const r: VerifierResult = {
  versao: "2026-11-06.1", marca: "bloqueado", llm: "ok",
  hooks: [
    { i: 0, texto: "Sou o homem mais rico do mundo.", marca: "bloqueado", afirmacoes: [{ tipo: "persona", trecho: "o homem mais rico", marca: "bloqueado" }] },
    { i: 1, texto: "Gastei 40 mil € num voo.", marca: "rever", afirmacoes: [{ tipo: "facto", trecho: "40 mil €", marca: "rever" }] },
    { i: 2, texto: "Acho que estudar não chega.", marca: "ok", afirmacoes: [] },
  ],
};
const cases: [string, unknown, unknown][] = [
  ["pior marca", worst(["ok", "juridico", "atencao"]), "juridico"],
  ["sem marcas é ok", worst([]), "ok"],
  ["hook igual encontra (maiúsculas e pontuação não contam)", checkForHook(r, "sou o homem mais rico do mundo")?.hook?.marca, "bloqueado"],
  ["hook editado fica desatualizado", checkForHook(r, "Sou o homem mais pobre do mundo.").stale, true],
  ["sem verificação não está desatualizado", checkForHook(null, "x").stale, false],
  ["resumo conta e nunca diz verificado", summary(r), "Hooks: 1 fora da regra, 1 para rever. Quem revê decide; nenhum facto fica dado como verificado."],
  ["resumo parcial quando o modelo falhou", summary({ ...r, llm: "falhou" }).includes("Só regras"), true],
  ["resumo de erro", summary({ ...r, erro: "x" }), "A verificação falhou neste guião: rever à mão."],
  ["resumo sem nada", summary({ ...r, hooks: [] }).startsWith("Nenhum hook marcado."), true],
  ["parse recusa marca desconhecida", parseVerification({ marca: "verificado", result: r }), null],
  ["parse tira afirmações desconhecidas", parseVerification({ marca: "rever", result: { ...r, hooks: [{ ...r.hooks[1], afirmacoes: [{ tipo: "boato", marca: "ok" }] }] } })?.result.hooks[0].afirmacoes.length, 0],
  ["parse lixo", parseVerification("x"), null],
];
let fail = 0;
for (const [name, got, want] of cases) {
  if (JSON.stringify(got) !== JSON.stringify(want)) { fail++; console.error(`FAIL ${name}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`); }
}
console.log(`verifier-format: ${cases.length - fail}/${cases.length}`);
if (fail) process.exit(1);
