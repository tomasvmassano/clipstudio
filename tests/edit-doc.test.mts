import { addNote, addOverlay, captionAt, notesOut, resizeOverlay, setGain, setMusic, shiftOverlay, shiftWord, deleteSegment, editWord, historyOf, hookEnd, layout, moveSegment, outToSrc, problem, push, redo, splitSegment, srcToOut, trimSegment, undo, wordsOut, spanOut, type EditDoc } from "../src/lib/edit-doc.ts";

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
const o1 = addOverlay(doc, { id: "o1", kind: "broll", label: "praia", asset: "a1" }, 3, 2);
eq("visual no cursor fica no tempo da fonte", o1.overlays[0], { id: "o1", kind: "broll", label: "praia", asset: "a1", s: 21, e: 23 });
eq("visual não passa o fim do corte", addOverlay(doc, { id: "o2", kind: "graphic", label: "x" }, 6.5, 5).overlays[0].e, 25);
eq("visual segue o corte quando se apara", spanOut(trimSegment(o1, "b1", "in", 21), 21, 23), [{ at: 2, end: 4 }]);
eq("mover visual", shiftOverlay(o1, "o1", 0.5).overlays[0].s, 21.5);
eq("visual nunca fica com menos de 0,1 s", resizeOverlay(o1, "o1", "e", 10).overlays[0].e, 21.1);
const m = setMusic(doc, { label: "Beat", asset: "m1" });
eq("trocar música guarda o volume", m.audio.music, { label: "Beat", asset: "m1", db: -18 });
const g = setGain(setGain(m, 20, 22, -30), 21, 23, -6);
eq("volume por trecho substitui o que se sobrepõe", g.audio.gains, [{ s: 21, e: 23, db: -6 }]);
eq("tirar a música tira os volumes", setMusic(g, null).audio.gains.length, 0);
const nn = addNote(doc, 3, "  corta aqui ", "Tomás", "n1");
eq("nota no momento", notesOut(nn).map((x) => [x.text, x.at]), [["corta aqui", 3]]);
eq("nota num trecho cortado fica sem posição", notesOut(deleteSegment(nn, "b1"))[0].at, null);
eq("nota vazia não entra", (addNote(doc, 3, "  ", null, "x").notes ?? []).length, 0);
eq("mover palavra", shiftWord(doc, "w2", 0.2).captions.words[1].s, 21.2);
console.log(`edit-doc: ${n - bad}/${n}`);
if (bad) process.exit(1);
