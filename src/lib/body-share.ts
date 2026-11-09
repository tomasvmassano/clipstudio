/*
 * Corpo partilhado entre hooks (EDL-14, CHG-011, ADR-0081). As variantes do mesmo guião têm o mesmo corpo na mesma gravação
 * (tempo da fonte) e hooks diferentes. Aplicar o corpo de uma variante a outra troca, na outra, tudo o que é corpo e mantém o hook:
 *   - cortes: os de hook da outra, por ordem, seguidos dos de corpo desta;
 *   - legendas, câmaras, visuais e volumes que tocam um trecho de corpo (desta ou da outra), e efeitos que lá começam, vêm desta; o resto fica.
 * Funções puras, sem rede, testadas em tests/body-share.test.mts. Quem grava é o editor, versão a versão (edit_doc_save).
 */
import type { EditDoc, Seg } from "./edit-doc";

type Range = [number, number];

/** Trechos da gravação que são corpo (cortes que não são hook). */
export function bodyRanges(doc: EditDoc): Range[] {
  return doc.segments.filter((s) => s.section !== "hook").map((s) => [s.in, s.out] as Range);
}

const EPS = 1e-3;
const inAny = (t: number, rs: Range[]) => rs.some(([a, b]) => t >= a - EPS && t < b - EPS);
/** O intervalo [s, e) toca algum trecho? (câmaras, visuais, volumes e palavras podem começar antes de um corte aparado) */
const hits = (s: number, e: number, rs: Range[]) => rs.some(([a, b]) => s < b - EPS && Math.max(e, s + EPS) > a + EPS);

/** Ids únicos: um id que já existe nos que ficam leva sufixo. */
function uniqueIds<T extends { id: string }>(keep: T[], add: T[], prefix: string): T[] {
  const used = new Set(keep.map((x) => x.id));
  return add.map((x) => {
    if (!used.has(x.id)) { used.add(x.id); return x; }
    let n = 2, id = `${prefix}${x.id}`;
    while (used.has(id)) id = `${prefix}${x.id}_${n++}`;
    used.add(id);
    return { ...x, id };
  });
}

/** O documento `dst` com o corpo de `src` e o hook de `dst`. */
export function applyBody(src: EditDoc, dst: EditDoc): EditDoc {
  const rs = bodyRanges(src);
  const all = [...rs, ...bodyRanges(dst)];
  const hookSegs = dst.segments.filter((s) => s.section === "hook");
  const bodySegs = uniqueIds<Seg>(hookSegs, src.segments.filter((s) => s.section !== "hook"), "b");
  const keepWords = dst.captions.words.filter((w) => !hits(w.s, w.e, all));
  const words = [...keepWords, ...uniqueIds(keepWords, src.captions.words.filter((w) => hits(w.s, w.e, rs)), "b")].sort((a, b) => a.s - b.s);
  const cameras = [...dst.cameras.filter((c) => !hits(c.s, c.e, all)), ...src.cameras.filter((c) => hits(c.s, c.e, rs))].sort((a, b) => a.s - b.s);
  const keepOv = dst.overlays.filter((o) => !hits(o.s, o.e, all));
  const overlays = [...keepOv, ...uniqueIds(keepOv, src.overlays.filter((o) => hits(o.s, o.e, rs)), "b")].sort((a, b) => a.s - b.s);
  const gains = [...dst.audio.gains.filter((g) => !hits(g.s, g.e, all)), ...src.audio.gains.filter((g) => hits(g.s, g.e, rs))].sort((a, b) => a.s - b.s);
  const keepSfx = dst.audio.sfx.filter((x) => !inAny(x.s, all));
  const sfx = [...keepSfx, ...uniqueIds(keepSfx, src.audio.sfx.filter((x) => inAny(x.s, rs)), "b")].sort((a, b) => a.s - b.s);
  return { ...dst, segments: [...hookSegs, ...bodySegs], captions: { ...dst.captions, words }, cameras, overlays, audio: { ...dst.audio, gains, sfx } };
}

/** Assinatura do corpo (cortes, legendas, câmaras, visuais, volumes e efeitos nos trechos de corpo), para saber se duas variantes têm o mesmo. */
export function bodyKey(doc: EditDoc): string {
  const rs = bodyRanges(doc);
  const r = (x: number) => Math.round(x * 1000) / 1000;
  return JSON.stringify({
    s: doc.segments.filter((s) => s.section !== "hook").map((s) => [r(s.in), r(s.out)]),
    w: doc.captions.words.filter((w) => hits(w.s, w.e, rs)).map((w) => [w.w, r(w.s), r(w.e)]),
    c: doc.cameras.filter((c) => hits(c.s, c.e, rs)).map((c) => [c.cam, r(c.s), r(c.e), c.zoom]),
    o: doc.overlays.filter((o) => hits(o.s, o.e, rs)).map((o) => [o.kind, o.asset ?? o.label, r(o.s), r(o.e), o.box ?? null]),
    g: doc.audio.gains.filter((g) => hits(g.s, g.e, rs)).map((g) => [r(g.s), r(g.e), g.db]),
    x: doc.audio.sfx.filter((x) => inAny(x.s, rs)).map((x) => [x.label, r(x.s)]),
  });
}

/** O corpo de src é igual ao de dst? */
export const sameBody = (a: EditDoc, b: EditDoc) => bodyKey(a) === bodyKey(b);
