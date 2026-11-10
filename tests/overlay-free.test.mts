import assert from "node:assert/strict";
import { test } from "node:test";
import { moveOverlayOut, fitBox, clampBox, scaleBox, niceImageTitle } from "../src/lib/edit-doc.ts";

const doc = {
  schema: 1, fps: 30, size: [1080, 1920], style: "S17", captions: { words: [] }, cameras: [], hook: { text: "" },
  segments: [{ id: "a", in: 10, out: 14, section: "body" }, { id: "b", in: 30, out: 35, section: "body" }],
  overlays: [{ id: "o", kind: "graphic", label: "x", asset: "A", s: 11, e: 13 }], audio: { music: null, sfx: [], gains: [] },
} as never;
const ov = (d: unknown) => (d as { overlays: { s: number; e: number }[] }).overlays[0];

test("mover no tempo do vídeo final atravessa o corte para o trecho seguinte (W10-39)", () => {
  const d = moveOverlayOut(doc, "o", 5);              // saída 5 = fonte 31 (segundo corte)
  assert.deepEqual([ov(d).s, ov(d).e], [31, 33]);
  const end = moveOverlayOut(doc, "o", 8.5);          // perto do fim: encurta até ao fim do corte
  assert.deepEqual([ov(end).s, ov(end).e], [34.5, 35]);
  assert.equal(moveOverlayOut(doc, "o", 99), doc);    // fora do vídeo
});

test("caixa da imagem: inteira ao centro, dentro do ecrã, escala à volta do centro", () => {
  assert.deepEqual(fitBox(16 / 9, [90, 1120, 900, 760]), [90, 1247, 900, 506]);
  assert.deepEqual(fitBox(0.5, [0, 0, 1000, 1000]), [250, 0, 500, 1000]);
  assert.deepEqual(clampBox([-5000, 9000, 10, 10]), [-20, 1900, 40, 40]);
  assert.deepEqual(scaleBox([100, 100, 200, 100], 2), [0, 50, 400, 200]);
});

test("nomes legíveis para ficheiros com código", () => {
  assert.equal(niceImageTitle("d3fcce3e5468a815cfcbf2d22f5622d1.jpg", 3), "Imagem 3");
  assert.equal(niceImageTitle("IMG_4821.JPG", 1), "Imagem 1");
  assert.equal(niceImageTitle("Lamborghini preto.png", 2), "Lamborghini preto");
});

test("rótulos com código mostram-se como Imagem", async () => {
  const { shownLabel } = await import("../src/lib/edit-doc.ts");
  assert.equal(shownLabel("d3fcce3e5468a815cfcbf2d22f5622d1"), "Imagem");
  assert.equal(shownLabel("Lamborghini"), "Lamborghini");
});
