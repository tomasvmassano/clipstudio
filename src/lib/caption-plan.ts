/*
 * Legendas como a exportação as desenha (W10-30, ADR-0078). Espelho de engine/render_doc.py (words_out, chunks_of,
 * caption_plan): o palco do editor mostra o mesmo bloco, ao mesmo tempo, que o vídeo exportado. Funções puras e testadas.
 */
import type { EditDoc } from "./edit-doc";

/** Segmentos na saída (o mesmo que layout em edit-doc; repetido para este ficheiro ficar sem dependências e testável). */
function placed(doc: EditDoc): { in: number; out: number; at: number }[] {
  let at = 0;
  return doc.segments.map((s) => { const p = { in: s.in, out: s.out, at: Math.round(at * 1000) / 1000 }; at += s.out - s.in; return p; });
}

export type CapWord = { w: string; s: number; e: number };
/** Caixas e tamanhos dos estilos que o motor desenha (STYLES em render_doc.py), em px de 1080×1920. */
export const CAP_STYLES = {
  S14: { box: [140, 1090, 800, 140] as const, size: 84, maxWords: 1, label: "S14 · uma palavra de cada vez" },
  S15: { box: [150, 1250, 780, 220] as const, size: 72, maxWords: 6, label: "S15 · frases com destaque" },
} as const;
export type CapStyle = keyof typeof CAP_STYLES;
export const capStyleOf = (doc: EditDoc): CapStyle => (doc.style === "S14" || doc.style === "S15" ? doc.style : "S15");

/** Palavras no tempo da saída: cada palavra entra uma vez, no segmento onde começa (como words_out do motor). */
export function capWordsOut(doc: EditDoc): CapWord[] {
  const segs = placed(doc);
  const out: CapWord[] = [];
  for (const w of doc.captions.words) {
    const g = segs.find((x) => x.in - 1e-3 <= w.s && w.s < x.out);
    if (!g) continue;
    const s = g.at + (w.s - g.in);
    const e = g.at + (Math.min(w.e, g.out) - g.in);
    out.push({ w: w.w, s, e: Math.max(s, e) });
  }
  return out.sort((a, b) => a.s - b.s);
}

/** Blocos de legenda: fecha no máximo de palavras, no fim de frase, numa pausa > 0,45 s ou numa vírgula perto do máximo. */
export function chunksOf(words: CapWord[], maxWords: number): CapWord[][] {
  const out: CapWord[][] = [];
  let cur: CapWord[] = [];
  words.forEach((w, i) => {
    cur.push(w);
    const nxt = words[i + 1];
    const end = /[.?!:]$/.test(w.w) || (!!nxt && nxt.s - w.e > 0.45);
    const soft = w.w.endsWith(",") && cur.length >= Math.max(2, maxWords - 3);
    if (cur.length >= maxWords || end || soft || !nxt) { out.push(cur); cur = []; }
  });
  return out;
}

export type CapState = { chunk: CapWord[]; active: number } | null;

/** Sequência de estados [(t, estado)] da legenda, ordenada: o estado vale de t até ao seguinte. */
export function captionStates(doc: EditDoc, duration: number): [number, CapState][] {
  const style = capStyleOf(doc);
  const words = capWordsOut(doc);
  const states: [number, CapState][] = [];
  let t = 0;
  if (style === "S14") {
    words.forEach((w, i) => {
      if (w.s > t + 0.02) states.push([t, null]);
      const nxt = i + 1 < words.length ? words[i + 1].s : duration;
      states.push([w.s, { chunk: [w], active: 0 }]);
      t = Math.min(nxt, w.e + 0.35);
    });
  } else {
    for (const c of chunksOf(words, CAP_STYLES.S15.maxWords)) {
      if (c[0].s > t + 0.02) states.push([t, null]);
      c.forEach((w, j) => states.push([w.s, { chunk: c, active: j }]));
      t = c[c.length - 1].e + 0.25;
    }
  }
  states.push([t, null]);
  return states.map(([a, b]) => [Math.max(0, a), b] as [number, CapState]).sort((x, y) => x[0] - y[0]);
}

/** O estado no instante t (busca binária; antes do primeiro, nada). */
export function captionAtState(states: [number, CapState][], t: number): CapState {
  let lo = 0, hi = states.length - 1, best = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (states[mid][0] <= t + 1e-6) { best = mid; lo = mid + 1; } else hi = mid - 1;
  }
  return best >= 0 ? states[best][1] : null;
}
