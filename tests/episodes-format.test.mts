import { camsPayload, camsProblem, durText, parseProfile, reasonRows, summaryLine } from "../src/lib/episodes-format.ts";

const r = (name: string, version: string) => ({ name, version });
const cases: [string, unknown, unknown][] = [
  ["sem vídeo", camsProblem([r("frente", "")], "", ""), "Escolhe pelo menos um vídeo."],
  ["uma câmara ok", camsProblem([r("frente", "a")], "frente", ""), null],
  ["duas câmaras e largo ok", camsProblem([r("frente", "a"), r("largo", "b")], "frente", "largo"), null],
  ["nome inválido", camsProblem([r("Frente Cam", "a")], "", "")?.toString().startsWith("Nomes"), true],
  ["nomes repetidos", camsProblem([r("cam", "a"), r("cam", "b")], "", ""), "Duas câmaras com o mesmo nome."],
  ["mesmo vídeo duas vezes", camsProblem([r("a", "x"), r("b", "x")], "", ""), "O mesmo vídeo em duas câmaras."],
  ["som fora", camsProblem([r("frente", "a")], "largo", ""), "A câmara do som tem de ser uma das escolhidas."],
  ["largo com uma câmara", camsProblem([r("frente", "a")], "frente", "frente"), "Com uma câmara só não há plano largo à parte."],
  ["5 câmaras", camsProblem(["a", "b", "c", "d", "e"].map((n) => r(n, n)), "", ""), "No máximo 4 câmaras."],
  ["payload ignora vazias", camsPayload([r("frente", "a"), r("largo", "")]), { frente: "a" }],
  ["perfil vazio", parseProfile("  "), { profile: null, error: null }],
  ["perfil do style-extract", parseProfile('{"profile": {"audio": {"lufs": -16}}, "fields": {}}').profile, { audio: { lufs: -16 } }],
  ["perfil direto", parseProfile('{"pacing": {"max_pause_s": 0.6}}').profile, { pacing: { max_pause_s: 0.6 } }],
  ["perfil inválido", parseProfile("{x").error, "O perfil não é JSON válido."],
  ["perfil lista", parseProfile("[1]").error, "O perfil tem de ser um objeto JSON."],
  ["duração", durText(3725), "1:02:05"],
  ["duração curta", durText(65), "1:05"],
  ["resumo", summaryLine({ before_s: 3130, after_s: 2643, cuts: 312, removed_pct: 15.6 }), "52:10 → 44:03 · 312 cortes · 15,6% removido"],
  ["resumo vazio", summaryLine(null), null],
  ["motivos ordenados", reasonRows({ by_reason: { "hesitação": 20, "pausa acima do máximo": 190 } }), [["pausa acima do máximo", "3:10"], ["hesitação", "0:20"]]],
];
let bad = 0;
for (const [n, got, exp] of cases) {
  if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
}
console.log(`episodes-format ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
