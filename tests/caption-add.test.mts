import assert from "node:assert/strict";
import { test } from "node:test";
import { addCaption, wordsInRange, wordsOut } from "../src/lib/edit-doc.ts";

const doc = {
  schema: 1, fps: 30, size: [1080, 1920], style: "S15", hook: { text: "" }, cameras: [], overlays: [],
  segments: [{ id: "a", in: 10, out: 14, section: "body" }, { id: "b", in: 30, out: 35, section: "body" }],
  captions: { words: [{ id: "w1", w: "olá", s: 10.2, e: 10.5 }, { id: "w2", w: "mundo", s: 31, e: 31.4 }] },
  audio: { music: null, sfx: [], gains: [] },
} as never;
const words = (d: unknown) => (d as { captions: { words: { id: string; w: string; s: number; e: number }[] } }).captions.words;

test("legenda nova no cursor: palavras no tempo da fonte, por ordem (W10-43)", () => {
  const r = addCaption(doc, "  Isto  é novo ", 1, 1.5, "n1");
  assert.deepEqual(r.ids, ["n1-0", "n1-1", "n1-2"]);
  const ws = words(r.doc);
  assert.deepEqual(ws.map((w) => w.w), ["olá", "Isto", "é", "novo", "mundo"]);
  const n = ws.filter((w) => w.id.startsWith("n1"));
  assert.equal(n[0].s, 11);
  assert.equal(n.at(-1)!.e, 12.5);
  assert.ok(n.every((w, i) => i === 0 || w.s === n[i - 1].e), "seguidas, sem buracos");
  assert.ok(n[0].e - n[0].s > n[1].e - n[1].s, "palavra maior dura mais");
});

test("não passa o fim do corte e aparece na saída", () => {
  const r = addCaption(doc, "fim do corte", 3.5, 5, "n2");
  assert.equal(words(r.doc).filter((w) => w.id.startsWith("n2")).at(-1)!.e, 14);
  assert.ok(wordsOut(r.doc).some((w) => w.w === "fim"));
});

test("no segundo corte usa o tempo desse corte; substituir tira as que lá estavam", () => {
  assert.equal(wordsInRange(doc, 4.5, 1), 1);
  const r = addCaption(doc, "planeta", 4.5, 1, "n3", true);
  assert.deepEqual(words(r.doc).map((w) => w.w), ["olá", "planeta"]);
  assert.equal(words(r.doc)[1].s, 30.5);
});

test("texto vazio ou cursor fora: não muda nada", () => {
  assert.equal(addCaption(doc, "   ", 1, 1, "x").doc, doc);
  assert.equal(addCaption(doc, "a", 99, 1, "x").doc, doc);
});
