import { clipMasters, clipTime, polemicText, scoreText } from "../src/lib/clips-format.ts";

const v = (o: Record<string, unknown> = {}) => ({ id: "v", state: "pronta", storage: "r2", mime: "video/mp4", media_info: { duration: 1800 }, ...o });
const assets = [
  { id: "longo", tags: [], current: v() },
  { id: "curto", tags: [], current: v({ media_info: { duration: 40 } }) },
  { id: "sem-duracao", tags: [], current: v({ media_info: null }) },
  { id: "supabase", tags: [], current: v({ storage: "supabase" }) },
  { id: "a-verificar", tags: [], current: v({ state: "pendente" }) },
  { id: "audio", tags: [], current: v({ mime: "audio/mpeg" }) },
  { id: "corte", tags: ["corte"], current: v() },
  { id: "pacote", tags: ["pacote"], current: v() },
  { id: "sem-versao", tags: [], current: null },
  { id: "5h", tags: [], current: v({ media_info: { duration: 5 * 3600 } }) },
];
const cases: [string, unknown, unknown][] = [
  ["tempo curto", clipTime(65.4), "1:05"],
  ["tempo com horas", clipTime(3725), "1:02:05"],
  ["tempo nulo", clipTime(null), "—"],
  ["polémica", polemicText(["tensao", "xpto", "numero"]), "tensão, número"],
  ["não polémico", polemicText([]), "não polémico"],
  ["pontuação", scoreText(82.4), "82/100"],
  ["pontuação nula", scoreText(undefined), "—"],
  ["fontes de cortes", clipMasters(assets).map((a) => a.id).join(","), "longo,sem-duracao"],
];
let bad = 0;
for (const [name, got, want] of cases) {
  if (got !== want) { bad++; console.error(`FAIL ${name}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`); }
}
console.log(`clips-format: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
