import assert from "node:assert/strict";
import { test } from "node:test";
import { camAt, setCam, splitCamAt, frameAllCam, CAM_ANCHOR } from "../src/lib/edit-doc.ts";

const doc = {
  schema: 1, fps: 30, size: [1080, 1920], style: "S15", segments: [{ id: "s1", in: 0, out: 10, section: "body" }], captions: { words: [] },
  cameras: [{ s: 0, e: 4, cam: "front", zoom: 1, intro: true }, { s: 4, e: 10, cam: "side", zoom: 1 }],
  hook: { text: "" }, overlays: [], audio: { music: null, sfx: [], gains: [] },
} as never;
const cams = (d: unknown) => (d as { cameras: { s: number; e: number; cam: string; zoom: number; x?: number; y?: number; intro?: boolean }[] }).cameras;

test("trocar o ângulo e o zoom de um trecho, com limites (W10-35)", () => {
  const d = setCam(doc, 1, { cam: "front", zoom: 9, y: -1 });
  assert.deepEqual([cams(d)[1].cam, cams(d)[1].zoom, cams(d)[1].y], ["front", 3, 0]);
  assert.equal(cams(d)[0].cam, "front");
  assert.equal(setCam(doc, 7, { cam: "side" }), doc);
});

test("dividir no cursor e trocar só a segunda parte", () => {
  const d = splitCamAt(doc, 6);
  assert.deepEqual(cams(d).map((c) => [c.s, c.e, c.cam]), [[0, 4, "front"], [4, 6, "side"], [6, 10, "side"]]);
  const d2 = setCam(d, camAt(d, 7), { cam: "front" });
  assert.deepEqual(cams(d2).map((c) => c.cam), ["front", "side", "front"]);
  assert.equal(splitCamAt(doc, 4.05), doc);               // perto da borda: não parte
  assert.equal(cams(splitCamAt(doc, 2))[1].intro, false); // o zoom de entrada fica só no início
});

test("enquadrar a câmara da frente inteira", () => {
  const d = frameAllCam(splitCamAt(doc, 6), "side", { zoom: 1.4, y: 0.2 });
  assert.deepEqual(cams(d).filter((c) => c.cam === "side").map((c) => [c.zoom, c.x, c.y]), [[1.4, CAM_ANCHOR.x, 0.2], [1.4, CAM_ANCHOR.x, 0.2]]);
  assert.equal(cams(d)[0].zoom, 1);
});
