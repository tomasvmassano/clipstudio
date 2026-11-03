import { captionAt, deleteSegment, editWord, historyOf, hookEnd, layout, moveSegment, outToSrc, problem, push, redo, splitSegment, srcToOut, trimSegment, undo, wordsOut, type EditDoc } from "../src/lib/edit-doc.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => { n++; const g = JSON.stringify(got), e = JSON.stringify(exp); if (g !== e) { bad++; console.log("FAIL", name, g, "esperado", e); } };

const doc: EditDoc = {
  schema: 1, fps: 30, size: [1080, 1920], style: "S15",
  segments: [{ id: "h", in: 10, out: 12, section: "hook" }, { id: "b1", in: 20, out: 25, section: "body" }, { id: "b2", in: 30, out: 31, section: "body" }],
  captions: { words: [{ id: "w1", w: "Olá", s: 10.2, e: 10.6 }, { id: "w2", w: "corpo", s: 21, e: 21.5 }, { id: "w3", w: "fora", s: 26, e: 26.4 }, { id: "w4", w: "fim", s: 30.2, e: 30.5 }] },
  cameras: [], hook: { text: "Hook" }, overlays: [], audio: { music: { label: "m", db: -18 }, sfx: [], gains: [] },
};

eq("duração = soma dos cortes", layout(doc).duration, 8);
eq("posições na saída", layout(doc).segs.map((s) => s.at), [0, 2, 7]);
eq("fonte → saída", srcToOut(doc, 21), 3);
eq("cortado não aparece", srcToOut(doc, 26), null);
eq("saída → fonte", outToSrc(doc, 7.5)?.src, 30.5);
eq("fim do hook", hookEnd(doc), 2);
eq("palavras na saída sem as cortadas", wordsOut(doc).map((w) => [w.w, w.at]), [["Olá", 0.2], ["corpo", 3], ["fim", 7.2]]);
eq("legenda num instante", captionAt(doc, 3.2), "corpo");

const t1 = trimSegment(doc, "b1", "in", 21);
eq("aparar a entrada reflui as palavras", wordsOut(t1).map((w) => [w.w, w.at]), [["Olá", 0.2], ["corpo", 2], ["fim", 6.2]]);
eq("aparar nunca deixa menos de 0,1 s", trimSegment(doc, "b2", "out", 29).segments[2], { id: "b2", in: 30, out: 30.1, section: "body" });
eq("entrada não fica negativa", trimSegment(doc, "h", "in", -5).segments[0].in, 0);
const sp = splitSegment(doc, "b1", 4, "b1b");
eq("dividir no instante da saída", sp.segments.map((s) => [s.id, s.in, s.out]), [["h", 10, 12], ["b1", 20, 22], ["b1b", 22, 25], ["b2", 30, 31]]);
eq("dividir rente à ponta não faz nada", splitSegment(doc, "b1", 2.05, "x").segments.length, 3);
eq("apagar um corte", layout(deleteSegment(doc, "b1")).duration, 3);
eq("não apaga o último corte", deleteSegment({ ...doc, segments: [doc.segments[0]] }, "h").segments.length, 1);
eq("reordenar", moveSegment(doc, "b2", -1).segments.map((s) => s.id), ["h", "b2", "b1"]);
eq("reordenar no limite fica igual", moveSegment(doc, "h", -1).segments.map((s) => s.id), ["h", "b1", "b2"]);
eq("corrigir uma palavra", editWord(doc, "w2", { w: "  corpo  certo " }).captions.words[1].w, "corpo certo");
eq("palavra vazia sai", editWord(doc, "w2", { w: " " }).captions.words.length, 3);
eq("fim antes do início corrige", editWord(doc, "w1", { e: 9 }).captions.words[0].e, 10.2);
eq("documento válido", problem(doc), null);
eq("sem segmentos", problem({ ...doc, segments: [] }), "sem segmentos");
let h = historyOf(doc); h = push(h, t1); h = push(h, sp);
eq("desfazer", undo(h).present === t1, true);
eq("refazer", redo(undo(h)).present === sp, true);
eq("editar depois de desfazer apaga o refazer", push(undo(h), doc).future.length, 0);
console.log(`edit-doc: ${n - bad}/${n}`);
if (bad) process.exit(1);
