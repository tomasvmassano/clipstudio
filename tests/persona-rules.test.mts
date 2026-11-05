import { personaProblem, newPersonaId } from "../src/lib/persona-rules.ts";
const ok = [{ id: "p01", text: "o homem mais rico de Portugal" }];
const cases: [string, unknown, unknown][] = [
  ["lista válida", personaProblem(ok), null],
  ["vazia é válida", personaProblem([]), null],
  ["curta", personaProblem([{ id: "p01", text: "ab" }])?.includes("entre 3 e 160"), true],
  ["repetida sem maiúsculas", personaProblem([...ok, { id: "p02", text: "O homem mais rico de Portugal " }])?.startsWith("Frase repetida"), true],
  ["id repetido", personaProblem([...ok, { id: "p01", text: "outra frase" }])?.startsWith("Identificador repetido"), true],
  ["outra pessoa sem consentimento", personaProblem([{ id: "p01", text: "o marido mais caro", involves: { name: "Ana", consent_by: "", consent_at: "" } }])?.includes("consentimento"), true],
  ["outra pessoa sem nome", personaProblem([{ id: "p01", text: "o marido mais caro", involves: { name: "", consent_by: "Ana", consent_at: "2026-11-05" } }])?.includes("quem é"), true],
  ["consentimento completo", personaProblem([{ id: "p01", text: "o marido mais caro", involves: { name: "Ana", consent_by: "Ana", consent_at: "2026-11-05" } }]), null],
  ["mais de 100", personaProblem(Array.from({ length: 101 }, (_, i) => ({ id: `p${i}`, text: `frase ${i}` }))), "No máximo 100 frases."],
  ["novo id", newPersonaId([{ id: "p01" }, { id: "p03" }]), "p02"],
  ["novo id vazio", newPersonaId([]), "p01"],
];
let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`persona-rules: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
