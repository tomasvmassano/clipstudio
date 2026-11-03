import { cleanElements, countsAsNew, moveToDay, parseHashtags, variantDiff } from "../src/lib/pub-rules.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => {
  n++; const g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g !== e) { bad++; console.log("FAIL", name, g, "esperado", e); }
};
// VAR-01 (mesmas regras de _pub_variant_diff no servidor)
eq("original igual a si próprio", variantDiff({}, {}), 0);
eq("só título: 1", variantDiff({ title_thesis: "Tese" }, {}), 1);
eq("ativo de contexto sem tese conta zero", variantDiff({ context_asset: "foto" }, {}), 0);
eq("ativo de contexto com tese conta 2", variantDiff({ context_asset: "foto", title_thesis: "Tese" }, {}), 2);
eq("maiúsculas e espaços não contam", variantDiff({ segment: "Min 1  a 2" }, { segment: "min 1 a 2" }), 0);
eq("vazio é igual ao original", variantDiff({ segment: "  " }, {}), 0);
eq("irmãs com 1 diferença", variantDiff({ segment: "a", narration: "x" }, { segment: "a", narration: "y" }), 1);
eq("irmãs com 3 diferenças", variantDiff({ segment: "a", narration: "x", structure: "top 3" }, { segment: "b", narration: "y" }), 3);
eq("conta como nova com 2", countsAsNew({ segment: "a", narration: "b" }), true);
eq("não conta com 1", countsAsNew({ structure: "top 3" }), false);
eq("limpa vazios", cleanElements({ segment: " a ", narration: "" }), { segment: "a" });
// hashtags
eq("hashtags normalizadas", parseHashtags("dinheiro #dinheiro, #dubai").tags, ["#dinheiro", "#dubai"]);
eq("hashtag inválida", parseHashtags("##x ok").invalid, ["##x"]);
// arrastar para outro dia mantém a hora local
eq("mover dia", moveToDay("2026-11-02T18:30", "2026-11-05"), "2026-11-05T18:30");
console.log(`pub-rules ${n - bad}/${n}`);
if (bad) process.exit(1);
