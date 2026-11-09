import assert from "node:assert/strict";
import { test } from "node:test";
import { applyBody, bodyKey, sameBody } from "../src/lib/body-share.ts";

const base = (hookIn: number, hookOut: number, extra: Record<string, unknown> = {}) => ({
  schema: 1, fps: 30, size: [1080, 1920], style: "S15",
  segments: [{ id: "s01", in: hookIn, out: hookOut, section: "hook" }, { id: "s02", in: 100, out: 110, section: "body" }, { id: "s03", in: 112, out: 120, section: "body" }],
  captions: { words: [{ id: "h1", w: "Hook", s: hookIn + 0.1, e: hookIn + 0.5 }, { id: "w1", w: "corpo", s: 101, e: 101.5 }, { id: "w2", w: "erro", s: 113, e: 113.4 }] },
  cameras: [{ s: hookIn, e: hookOut, cam: "front", zoom: 1, intro: true }, { s: 100, e: 110, cam: "side", zoom: 1 }, { s: 112, e: 120, cam: "front", zoom: 1 }],
  hook: { text: `hook ${hookIn}` }, overlays: [], audio: { music: null, sfx: [], gains: [] }, notes: [], ...extra,
}) as never;

test("o corpo editado passa para o outro hook e o hook dele fica (EDL-14)", () => {
  const h1 = base(10, 13) as ReturnType<typeof base> & Record<string, never>;
  const h2 = base(30, 34);
  // no hook 1: aparou-se o 2.º corte, corrigiu-se uma palavra, trocou-se a câmara e pôs-se um visual no corpo
  const ed = {
    ...(h1 as object),
    segments: [{ id: "s01", in: 10, out: 13, section: "hook" }, { id: "s02", in: 100, out: 110, section: "body" }, { id: "s03", in: 112.5, out: 119, section: "body" }],
    captions: { words: [{ id: "h1", w: "Hook", s: 10.1, e: 10.5 }, { id: "w1", w: "corpo", s: 101, e: 101.5 }, { id: "w2", w: "certo", s: 113, e: 113.4 }] },
    cameras: [{ s: 10, e: 13, cam: "front", zoom: 1, intro: true }, { s: 100, e: 110, cam: "front", zoom: 1.2 }, { s: 112, e: 120, cam: "front", zoom: 1 }],
    overlays: [{ id: "o1", kind: "graphic", label: "gráfico", asset: "a1", s: 104, e: 106 }],
    audio: { music: null, sfx: [], gains: [{ s: 113, e: 114, db: -6 }] },
  } as never;
  const out = applyBody(ed, h2) as unknown as { segments: { id: string; in: number; out: number }[]; captions: { words: { w: string; s: number }[] }; cameras: { cam: string; zoom: number; s: number }[]; overlays: unknown[]; hook: { text: string }; audio: { gains: unknown[] } };
  assert.deepEqual(out.segments.map((s) => [s.in, s.out]), [[30, 34], [100, 110], [112.5, 119]]);
  assert.equal(out.hook.text, "hook 30");                                  // o hook dele
  assert.deepEqual(out.captions.words.map((w) => w.w), ["Hook", "corpo", "certo"]);
  assert.equal(out.captions.words[0].s, 30.1);                              // a palavra do hook dele
  assert.deepEqual(out.cameras.map((c) => [c.s, c.cam, c.zoom]), [[30, "front", 1], [100, "front", 1.2], [112, "front", 1]]);
  assert.equal(out.overlays.length, 1);
  assert.equal(out.audio.gains.length, 1);
  assert.ok(sameBody(ed, out as never));                                    // ficaram com o mesmo corpo
  assert.ok(!sameBody(ed, h2));
});

test("aplicar duas vezes não muda nada e não repete ids", () => {
  const h1 = base(10, 13), h2 = base(30, 34);
  const once = applyBody(h1, h2), twice = applyBody(h1, once);
  assert.deepEqual(twice, once);
  const ids = (once as unknown as { segments: { id: string }[] }).segments.map((s) => s.id);
  assert.equal(new Set(ids).size, ids.length);
});

test("um corte de corpo tirado no editado desaparece no outro, com as suas legendas", () => {
  const h1 = base(10, 13), h2 = base(30, 34);
  const ed = { ...(h1 as object), segments: (h1 as unknown as { segments: unknown[] }).segments.slice(0, 2) } as never;
  const out = applyBody(ed, h2) as unknown as { segments: unknown[]; captions: { words: { w: string }[] }; cameras: unknown[] };
  assert.equal(out.segments.length, 2);
  assert.deepEqual(out.captions.words.map((w) => w.w), ["Hook", "corpo"]);   // "erro" (112-120) saiu com o corte
  assert.equal(out.cameras.length, 2);
});

test("ids repetidos entre o hook que fica e o corpo que entra ganham sufixo", () => {
  const h2 = { ...(base(30, 34) as object), segments: [{ id: "s02", in: 30, out: 34, section: "hook" }] } as never;
  const out = applyBody(base(10, 13), h2) as unknown as { segments: { id: string }[] };
  assert.deepEqual(out.segments.map((s) => s.id), ["s02", "bs02", "s03"]);
});

test("a assinatura ignora o hook", () => {
  assert.equal(bodyKey(base(10, 13)), bodyKey(base(30, 34)));
});
