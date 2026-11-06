import { fmtMoment, notificationSub, searchHref, toCsv } from "../src/lib/search-format.ts";
import { notifPath } from "../src/lib/notif-format.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; if (got !== exp) { bad++; console.log("FAIL", name, JSON.stringify(got), "esperado", JSON.stringify(exp)); } };
eq("guião abre no dia e destaca", searchHref({ kind: "script", id: "numeiro-2026-10-30-01", ws: "numeiro", title: "x", date: "2026-10-30" }),
  "/c/numeiro/guioes?date=2026-10-30&open=numeiro-2026-10-30-01");
eq("tarefa", searchHref({ kind: "task", id: "abc", ws: "numeiro", title: "x" }), "/c/numeiro/tarefas?task=abc");
eq("fonte filtra pelo título", searchHref({ kind: "source", id: "1", ws: "a b", title: "Leis & impostos" }), "/c/a%20b/fontes?q=Leis%20%26%20impostos");
eq("campanha", searchHref({ kind: "project", id: "p1", ws: "numeiro", title: "x" }), "/c/numeiro/guioes?campanha=p1");
eq("sem cliente não há destino", searchHref({ kind: "tag", id: "t", title: "#t" }), null);
// W10: media, comentários dos vídeos e notificações próprias
eq("media abre na biblioteca com o ativo", searchHref({ kind: "media", id: "a-1", ws: "numeiro", title: "x" }), "/c/numeiro/biblioteca?asset=a-1");
eq("comentário abre a revisão do vídeo", searchHref({ kind: "comment", id: "c-1", ws: "numeiro", title: "x", asset_id: "a 1" }),
  "/c/numeiro/revisao?ver=videos&asset=a%201");
eq("comentário sem vídeo não tem destino", searchHref({ kind: "comment", id: "c-1", ws: "numeiro", title: "x" }), null);
eq("notificação de tarefa", searchHref({ kind: "notification", id: "n", ws: "numeiro", title: "x", entity_type: "task", entity_id: "t1" }), "/c/numeiro/tarefas?task=t1");
eq("notificação de vídeo", searchHref({ kind: "notification", id: "n", ws: "numeiro", title: "x", entity_type: "media_asset", entity_id: "a1" }),
  "/c/numeiro/revisao?ver=videos&asset=a1");
eq("notificação desconhecida vai para o início do cliente", searchHref({ kind: "notification", id: "n", ws: "numeiro", title: "x", entity_type: "media_job", entity_id: "j" }), "/c/numeiro");
for (const et of ["task", "media_asset", "content", "agent_job", "media_job", "x"]) eq(`destino igual à caixa (${et})`, notificationSub(et, "id 1"), notifPath(et, "id 1"));
eq("momento m:ss", fmtMoment(83_400), "1:23");
eq("momento nulo", fmtMoment(null), null);
const row = { id: "g1", date: "2026-10-30", n: 1, tema: 'Diz "olá"; adeus', formato: null, editorial_status: "approved", production_status: "not_started",
  campanha: null, responsavel: "Rita", tags: ["a", "b"], platforms: [], hooks: ["=SOMA(1)", "h2"], corpo: "linha1\nlinha2", cta: null };
const csv = toCsv([row]);
eq("BOM no início", csv.charCodeAt(0), 0xfeff);
const line = csv.split("\r\n")[1];
eq("aspas e ; escapados", line.includes('"Diz ""olá""; adeus"'), true);
eq("fórmula neutralizada", line.includes("'=SOMA(1)"), true);
eq("quebra de linha entre aspas", line.includes('"linha1\nlinha2"'), true);
eq("etiquetas juntas", line.includes(";a, b;"), true);
console.log(`search-format ${n - bad}/${n}`);
if (bad) process.exit(1);
