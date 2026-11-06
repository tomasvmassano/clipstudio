import { altSections, hookTexts, optionInDoc, guidedProblem, restoreSegment, restorable, wordsBySegment, lookProblem, setLook, toggleNote, setHook, addNote, addOverlay, captionAt, notesOut, resizeOverlay, setGain, setMusic, shiftOverlay, shiftWord, deleteSegment, editWord, historyOf, hookEnd, layout, moveSegment, outToSrc, problem, push, redo, splitSegment, srcToOut, trimSegment, undo, wordsOut, spanOut, aiVisuals, pickState, removeOverlays, replaceOverlays, setOverlayBox, boxPreset, type EditDoc } from "../src/lib/edit-doc.ts";

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

// modo guiado (EDL-10): espelho do servidor
const gb: EditDoc = { ...doc, notes: [{ id: "n0", s: 21, text: "antiga", by: "Ana", done: false }] };
const noB1 = deleteSegment(gb, "b1");
eq("guiado: tirar um corte é permitido", guidedProblem(gb, noB1, [], "Rui"), null);
eq("guiado: repor um corte tirado volta ao mesmo sítio", restoreSegment(noB1, gb.segments[1], "h").segments.map((s) => s.id), ["h", "b1", "b2"]);
eq("guiado: repor sem o anterior vai pela ordem da fonte", restoreSegment(deleteSegment(noB1, "h"), gb.segments[0], "zz").segments.map((s) => s.id), ["h", "b2"]);
eq("guiado: repor não repete", restoreSegment(gb, gb.segments[0], null).segments.length, 3);
eq("guiado: cortes por repor incluem os tirados agora", restorable(noB1, gb, [{ seg: { id: "old", in: 1, out: 2, section: "body" }, after: null, version_no: 1 }]).map((p) => [p.seg.id, p.after]), [["b1", "h"], ["old", null]]);
eq("guiado: repor um corte de versão anterior", guidedProblem(gb, restoreSegment(gb, { id: "old", in: 1, out: 2, section: "body" }, null), [{ id: "old", in: 1, out: 2, section: "body" }], null), null);
eq("guiado: aparar recusado", guidedProblem(gb, trimSegment(gb, "b1", "in", 21), [], null), "no modo guiado só se tiram cortes ou se repõem cortes de versões anteriores (sem aparar nem criar cortes)");
eq("guiado: dividir recusado", guidedProblem(gb, sp, [], null) !== null, true);
eq("guiado: reordenar recusado", guidedProblem(gb, moveSegment(gb, "b2", -1), [], null), "no modo guiado a ordem dos cortes não muda");
eq("guiado: corrigir palavra e hook", guidedProblem(gb, setHook(editWord(gb, "w2", { w: "corpinho" }), "Novo"), [], null), null);
eq("guiado: tempo da palavra recusado", guidedProblem(gb, shiftWord(gb, "w2", 0.2), [], null), "no modo guiado só se corrige o texto das palavras (os tempos ficam)");
eq("guiado: tirar palavra recusado", guidedProblem(gb, editWord(gb, "w2", { w: "" }), [], null) !== null, true);
eq("guiado: visual recusado", guidedProblem(gb, o1, [], null) !== null, true);
eq("guiado: volume por trecho recusado", guidedProblem({ ...gb, audio: m.audio }, setGain({ ...gb, audio: m.audio }, 20, 22, -30), [], null), "no modo guiado o volume por trecho não muda");
eq("guiado: trocar música permitido (biblioteca verificada no servidor)", guidedProblem(gb, setMusic(gb, { label: "Beat", asset: "m1" }), [], null), null);
eq("guiado: aspeto recusado", guidedProblem(gb, { ...gb, look: { captions: { color: "#FF0000" } } }, [], null) !== null, true);
eq("guiado: nota nova com o próprio nome", guidedProblem(gb, addNote(gb, 3, "aqui", "Rui", "n1"), [], "Rui"), null);
eq("guiado: nota em nome de outro recusada", guidedProblem(gb, addNote(gb, 3, "aqui", "Ana", "n1"), [], "Rui"), "nota nova inválida (momento, texto ou autor)");
eq("guiado: marcar nota feita", guidedProblem(gb, toggleNote(gb, "n0"), [], "Rui"), null);
eq("guiado: apagar nota recusado", guidedProblem(gb, { ...gb, notes: [] }, [], "Rui") !== null, true);
eq("palavras por corte", wordsBySegment(doc).map((x) => x.words.map((w) => w.w)), [["Olá"], ["corpo"], ["fim"]]);
eq("aspeto: cor inválida", lookProblem({ captions: { color: "red" } }), "cor inválida no aspeto");
eq("aspeto: fora do retângulo seguro", lookProblem({ hook: { y: 100 } }), "texto fora do retângulo seguro (y 260-1550)");
eq("aspeto válido", problem({ ...doc, look: { captions: { color: "#FFFFFF", highlight: "#FFD400", size: 64, y: 1300 }, hook: { color: "#FFD400", background: null } } }), null);
const lk = setLook({ ...doc, look: { captions: { color: "#FFFFFF" }, hook: null, from: { key: "E01", version: 1 } } }, "captions", { highlight: "#FFD400" });
eq("aspeto: retoque mantém o resto e tira a origem do estilo", lk.look, { captions: { color: "#FFFFFF", highlight: "#FFD400" }, hook: null });
eq("aspeto: sem fundo", setLook(doc, "hook", { background: null }).look?.hook, { background: null });
const alts = { hook_texts: ["Outro hook", "Hook", "  ", "Outro hook"], sections: {
  cta: { replaces: ["b2"], options: [{ id: "alt_cta_1", segments: [{ id: "alt_cta_1_s01", in: 40, out: 42, section: "body" as const }], words: [], text: "x", duration: 2, confidence: null, note: "" }] },
  hook: { replaces: ["h"], options: [{ id: "alt_hook_1", segments: [{ id: "alt_hook_1_s01", in: 50, out: 52, section: "hook" as const }], words: [], text: "y", duration: 2, confidence: 0.6, note: "" },
                                     { id: "vazia", segments: [], words: [], text: "", duration: 0, confidence: null, note: "" }] },
  body: { replaces: [], options: [] } } };
eq("alternativas: secções com opções, pela ordem hook, corpo, CTA", altSections(alts).map((s) => [s.key, s.options.map((o) => o.id)]), [["hook", ["alt_hook_1"]], ["cta", ["alt_cta_1"]]]);
eq("alternativas: sem dados", altSections(null), []);
eq("alternativas: textos do hook sem o atual, vazios ou repetidos", hookTexts(alts, "Hook"), ["Outro hook"]);
const opt = alts.sections.hook.options[0];
eq("alternativa ainda não usada", optionInDoc(doc, opt), false);
eq("alternativa em uso (cortes iguais)", optionInDoc({ ...doc, segments: [...opt.segments, ...doc.segments.slice(1)] }, opt), true);
eq("alternativa aparada já não conta como em uso", optionInDoc({ ...doc, segments: [{ ...opt.segments[0], out: 51.5 }] }, opt), false);
eq("opção sem cortes nunca está em uso", optionInDoc(doc, { segments: [] }), false);
// visuais e música da IA (ADR-0068)
const IMG = "11111111-1111-4111-8111-111111111111";
const vdoc: EditDoc = { ...doc, audio: { music: { label: "Batida", asset: "m1", db: -18 }, sfx: [], gains: [] },
  overlays: [{ id: "ai_img", kind: "graphic", label: "Ferrari", asset: IMG, s: 20, e: 23, box: [108, 500, 864, 560] },
             { id: "ai_frase", kind: "text", label: "O rei do Dubai", asset: null, s: 20, e: 23, box: [120, 230, 840, 220] }],
  ai: { visuals: { version: 1, recipe: "imagem_frase", empty: [{ slot: "musica", why: "x" }], phrase_options: ["O rei do Dubai", "Outra"],
    picks: [{ slot: "imagem", overlays: ["ai_img"], asset: IMG, label: "Ferrari", why: "ferrari" },
            { slot: "frase", overlays: ["ai_frase"], asset: null, label: "O rei do Dubai", why: "lista v3" },
            { slot: "musica", overlays: [], asset: "m1", label: "Batida", why: "ia-musica" }] } } };
const vp = aiVisuals(vdoc)!.picks;
eq("documento antigo sem visuais da IA", aiVisuals(doc), null);
eq("escolhas em uso", vp.map((p) => pickState(vdoc, p)), ["em_uso", "em_uso", "em_uso"]);
eq("trocar a imagem mantém tempo e posição", replaceOverlays(vdoc, ["ai_img"], { asset: "other", label: "Praia" }).overlays[0], { id: "ai_img", kind: "graphic", label: "Praia", asset: "other", s: 20, e: 23, box: [108, 500, 864, 560] });
eq("imagem trocada", pickState(replaceOverlays(vdoc, ["ai_img"], { asset: "other", label: "Praia" }), vp[0]), "trocada");
eq("frase trocada só muda o texto", pickState(replaceOverlays(vdoc, ["ai_frase"], { label: "Outra" }), vp[1]), "trocada");
eq("tirar", pickState(removeOverlays(vdoc, ["ai_img"]), vp[0]), "tirada");
eq("música tirada", pickState(setMusic(vdoc, null), vp[2]), "tirada");
eq("posição pronta reconhecida", boxPreset(vdoc.overlays[0]), "middle");
eq("caixa de sempre tira a chave box", "box" in setOverlayBox(vdoc, "ai_img", null).overlays[0], false);
eq("posição própria", boxPreset({ ...vdoc.overlays[0], box: [1, 2, 300, 300] }), "custom");
eq("documento com visuais da IA é válido", problem(vdoc), null);
console.log(`edit-doc: ${n - bad}/${n}`);
if (bad) process.exit(1);
