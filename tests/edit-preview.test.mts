import assert from "node:assert/strict";
import { test } from "node:test";
import { virtualToSession, shotAt, audioCam } from "../src/lib/edit-preview.ts";

const doc = {
  schema: 1, segments: [{ id: "s1", in: 5, out: 10, section: "hook" }, { id: "s2", in: 25, out: 30, section: "body" }],
  captions: { words: [] }, cameras: [{ s: 5, e: 10, cam: "front", zoom: 1.2 }, { s: 25, e: 28, cam: "side", zoom: 1 }, { s: 28, e: 30, cam: "front", zoom: 1 }],
  hook: { text: "" }, overlays: [], audio: { music: null, sfx: [], gains: [] }, notes: [],
  source: { windows: [[100, 110], [200, 230]], audio: "side", cams: { front: "a.mp4", side: "b.mp4" } },
} as never;

test("tempo virtual → gravação pelas janelas", () => {
  assert.equal(virtualToSession([[100, 110], [200, 230]], 3), 103);
  assert.equal(virtualToSession([[100, 110], [200, 230]], 12), 202);
  assert.equal(virtualToSession(null, 7), 7);
  assert.equal(virtualToSession([[100, 110]], 50), 110);
});

test("plano no ar: câmara, zoom e tempo na gravação", () => {
  const a = shotAt(doc, 1)!;            // saída 1 → fonte 6 → sessão 106
  assert.deepEqual([a.cam, a.zoom, a.src, a.session, a.segEndOut], ["front", 1.2, 6, 106, 5]);
  const b = shotAt(doc, 5.5)!;          // saída 5.5 → fonte 25.5 → sessão 215.5, lado
  assert.deepEqual([b.cam, b.session], ["side", 215.5]);
  assert.equal(shotAt(doc, 9)!.cam, "front");
  assert.equal(shotAt(doc, 99), null);
  assert.equal(audioCam(doc), "side");
});
