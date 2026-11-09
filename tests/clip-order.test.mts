import { clipInfo, clipOrder, masterTime, type ClipOrder } from "../src/lib/clip-order.ts";
import { deleteSegment, moveSegment, type EditDoc } from "../src/lib/edit-doc.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; const g = JSON.stringify(got), e = JSON.stringify(exp); if (g !== e) { bad++; console.log("FAIL", name, g, "esperado", e); } };

// Documento como o do Clip Miner (engine/clips.py build_doc): gancho f0003 passado para o início, depois f0001-f0002 e f0004.
const w = (id: string, word: string, s: number, e: number) => ({ id, w: word, s, e });
const base = (): EditDoc => ({
  schema: 1, fps: 30, size: [1080, 1920], style: "S15",
  segments: [
    { id: "s01", in: 42, out: 46, section: "hook" },   // f0003
    { id: "s02", in: 30, out: 42, section: "body" },   // f0001 + f0002
    { id: "s03", in: 46, out: 55, section: "body" },   // f0004
  ],
  captions: { words: [
    w("w1", "Primeira", 30.2, 35), w("w2", "frase.", 35, 37), w("w3", "Segunda", 37.5, 41.8),
    w("w4", "Gancho!", 42.1, 45.9), w("w5", "Quarta", 46.2, 50), w("w6", "frase", 50, 54.8),
  ] },
  cameras: [], hook: { text: "Título" }, overlays: [], audio: { music: null, sfx: [], gains: [] },
  ai: { clip: { original: [["f0001", "f0004"]], parts: [["f0003"], ["f0001", "f0002"], ["f0004"]], reordered: true, prompt_version: "clip-miner-1" } },
});
const ok = (d: EditDoc) => clipOrder(d) as ClipOrder;

// sem ai.clip: nada (o editor não mostra a vista)
eq("sem ai", clipOrder({ ...base(), ai: null }), null);
eq("ai sem clip", clipOrder({ ...base(), ai: { visuals: null } }), null);
eq("clip lixo", clipInfo({ ai: { clip: "x" } }), null);
eq("clipInfo", clipInfo(base()), { original: [["f0001", "f0004"]], parts: [["f0003"], ["f0001", "f0002"], ["f0004"]], reordered: true });
eq("clipInfo campos maus", clipInfo({ ai: { clip: { original: 3, parts: [["a", 1]], reordered: "sim" } } }), { original: [], parts: [["a"]], reordered: false });

// proposta da IA: só o gancho aparece como movido (não os trechos que ele empurrou)
const a = ok(base());
eq("cut ordem", a.cut.map((c) => [c.id, c.rank, c.outIndex, c.moved]), [["s01", 2, 1, true], ["s02", 1, 2, false], ["s03", 3, 3, false]]);
eq("cut mudança", a.cut.map((c) => c.change), ["movido de 2.º para 1.º", "na ordem original", "na ordem original"]);
eq("original pela ordem do master", a.original.map((x) => x.kind === "seg" ? x.id : "cut"), ["s02", "s01", "s03"]);
eq("posição na saída", a.cut.map((c) => [c.at, c.dur]), [[0, 4], [4, 12], [16, 9]]);
eq("span das palavras/segmentos", a.span, { in: 30, out: 55 });
eq("contagens", [a.moved, a.removed, a.unchanged], [1, 0, false]);
eq("texto do trecho", a.cut[0].text, "Gancho!");

// tirar um trecho no editor: aparece como cortado, com os tempos do master e a fala
const del = ok(deleteSegment(base(), "s03"));
eq("cortado", del.original.filter((x) => x.kind === "cut").map((x) => [x.in, x.out, x.change, x.text]), [[46.2, 54.8, "cortado: 0:46-0:54", "Quarta frase"]]);
eq("cortado contagem", del.removed, 1);
eq("cortado no fim da esquerda", del.original.at(-1)!.kind, "cut");

// repor a ordem original: sem mudanças
const back = ok(moveSegment(base(), "s01", 1));
eq("ordem original", [back.moved, back.removed, back.unchanged], [0, 0, true]);
eq("ordem original mudanças", back.cut.map((c) => c.change), ["na ordem original", "na ordem original", "na ordem original"]);

// trecho do meio puxado para trás: [1,3,2] -> só o 3 é movido
const mid: EditDoc = { ...base(), segments: [
  { id: "a", in: 30, out: 42, section: "hook" }, { id: "c", in: 46, out: 55, section: "body" }, { id: "b", in: 42, out: 46, section: "body" }] };
eq("[1,3,2]", ok(mid).cut.map((c) => c.change), ["na ordem original", "movido de 3.º para 2.º", "na ordem original"]);

// pausa sem fala entre trechos não conta como corte; fala curta abaixo do mínimo também não
const pause: EditDoc = { ...base(), segments: [{ id: "x", in: 30, out: 41.9, section: "hook" }, { id: "y", in: 42.0, out: 55, section: "body" }] };
eq("pausa não é corte", ok(pause).removed, 0);
const trimmed: EditDoc = { ...base(), segments: [{ id: "x", in: 30, out: 37.2, section: "hook" }, { id: "y", in: 42, out: 55, section: "body" }] };
eq("aparar no meio = cortado", ok(trimmed).original.filter((x) => x.kind === "cut").map((x) => x.change), ["cortado: 0:37-0:41"]);

// trecho usado duas vezes
const rep: EditDoc = { ...base(), segments: [...base().segments, { id: "s04", in: 42, out: 46, section: "body" }] };
eq("repetido", ok(rep).cut.at(-1)!.change, "repetido (este trecho já passou antes)");
eq("repetido não está sem mudanças", ok(rep).unchanged, false);

// erros: documento que não dá para comparar
eq("sem segmentos", clipOrder({ ...base(), segments: [] }), "O documento não tem trechos para comparar.");
eq("tempos inválidos", clipOrder({ ...base(), segments: [{ id: "z", in: 5, out: 5, section: "hook" }] }), "Há um trecho com tempos inválidos no documento.");

// tempos do master com horas
eq("masterTime", [masterTime(0), masterTime(42.9), masterTime(3725)], ["0:00", "0:42", "1:02:05"]);

console.log(`clip-order: ${n - bad}/${n} ok`);
if (bad) process.exit(1);
