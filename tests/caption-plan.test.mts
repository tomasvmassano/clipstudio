import assert from "node:assert/strict";
import { test } from "node:test";
import { capWordsOut, chunksOf, captionStates, captionAtState } from "../src/lib/caption-plan.ts";

const base = { schema: 1, fps: 30, size: [1080, 1920], cameras: [], hook: { text: "" }, overlays: [], audio: { music: null, sfx: [], gains: [] }, notes: [] };
const w = (id: string, word: string, s: number, e: number) => ({ id, w: word, s, e });
const doc = (style: string, words: ReturnType<typeof w>[], segments = [{ id: "s1", in: 0, out: 10 }]) =>
  ({ ...base, style, segments, captions: { words } }) as never;

test("cada palavra aparece uma vez, no corte onde começa (W10-30)", () => {
  // a palavra atravessa a fronteira de dois cortes seguidos: o palco antigo mostrava-a duas vezes
  const d = doc("S15", [w("a", "custa", 4.5, 6)], [{ id: "s1", in: 0, out: 5 }, { id: "s2", in: 5, out: 8 }]);
  assert.deepEqual(capWordsOut(d), [{ w: "custa", s: 4.5, e: 5 }]);
});

test("blocos: máximo de palavras, fim de frase, pausa e vírgula", () => {
  const ws = ["Tu", "nunca", "vais", "conseguir", "competir", "com", "quem"].map((x, i) => ({ w: x, s: i * 0.3, e: i * 0.3 + 0.25 }));
  assert.deepEqual(chunksOf(ws, 6).map((c) => c.length), [6, 1]);
  const stop = [{ w: "raiva.", s: 0, e: 0.3 }, { w: "Enquanto", s: 0.35, e: 0.6 }];
  assert.deepEqual(chunksOf(stop, 6).map((c) => c.length), [1, 1]);
  const gap = [{ w: "a", s: 0, e: 0.2 }, { w: "b", s: 0.7, e: 0.9 }];
  assert.deepEqual(chunksOf(gap, 6).map((c) => c.length), [1, 1]);
  const comma = ["um", "dois", "três,", "quatro"].map((x, i) => ({ w: x, s: i * 0.3, e: i * 0.3 + 0.25 }));
  assert.deepEqual(chunksOf(comma, 6).map((c) => c.length), [3, 1]);
});

test("estados S15: o bloco fica parado e só a palavra ativa avança", () => {
  const d = doc("S15", [w("1", "Tu", 1, 1.2), w("2", "nunca", 1.2, 1.5), w("3", "vais.", 1.5, 1.9)]);
  const st = captionStates(d, 10);
  assert.equal(captionAtState(st, 0.5), null);
  const a = captionAtState(st, 1.1)!, b = captionAtState(st, 1.6)!;
  assert.deepEqual(a.chunk.map((x) => x.w), ["Tu", "nunca", "vais."]);
  assert.equal(a.chunk, b.chunk);                     // o mesmo bloco: nada salta nem se repete
  assert.deepEqual([a.active, b.active], [0, 2]);
  assert.equal(captionAtState(st, 2.2), null);        // 0,25 s depois da última palavra sai
});

test("estados S14: uma palavra de cada vez, até 0,35 s depois de dita", () => {
  const d = doc("S14", [w("1", "Tu", 1, 1.2), w("2", "nunca", 3, 3.3)]);
  const st = captionStates(d, 10);
  assert.equal(captionAtState(st, 1.1)!.chunk[0].w, "Tu");
  assert.equal(captionAtState(st, 1.5)!.chunk[0].w, "Tu");
  assert.equal(captionAtState(st, 1.6), null);
  assert.equal(captionAtState(st, 3.1)!.chunk[0].w, "nunca");
});

test("barra contínua: fração dita da palavra ativa (W10-31)", async () => {
  const { wipeFrac } = await import("../src/lib/caption-plan.ts");
  const w = { w: "jerKING", s: 2, e: 2.4 };
  assert.equal(wipeFrac(w, 1.9), 0);
  assert.ok(Math.abs(wipeFrac(w, 2.2) - 0.5) < 1e-9);
  assert.equal(wipeFrac(w, 3), 1);
  assert.ok(Math.abs(wipeFrac({ w: "a", s: 1, e: 1 }, 1.025) - 0.5) < 1e-9);   // palavra sem duração: 50 ms, como o motor
});
