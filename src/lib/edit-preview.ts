/*
 * Pré-visualização do editor com imagem (EDL-08, ADR-0047). Funções puras: tempo de saída → tempo da fonte (documento) →
 * tempo da gravação (janelas extraídas da sessão) e qual câmara está no ar. O palco usa os proxies (versões leves) no R2.
 */
import type { EditDoc } from "./edit-doc";

/** Saída → fonte (o mesmo que outToSrc em edit-doc; repetido aqui para este ficheiro ficar sem dependências e testável). */
function outToSrc(doc: EditDoc, t: number): { seg: { at: number; dur: number }; src: number } | null {
  let at = 0;
  for (const s of doc.segments) {
    const dur = s.out - s.in;
    if (t >= at && t < at + dur) return { seg: { at, dur }, src: Math.round((s.in + (t - at)) * 1000) / 1000 };
    at += dur;
  }
  return null;
}

export type Windows = [number, number][];

/** Tempo virtual (janelas coladas) → tempo da gravação. Sem janelas, o tempo virtual já é o da gravação. */
export function virtualToSession(windows: Windows | null | undefined, v: number): number {
  if (!windows?.length) return v;
  let acc = 0;
  for (const [a, b] of windows) {
    const len = b - a;
    if (v < acc + len - 1e-6) return a + Math.max(0, v - acc);
    acc += len;
  }
  const [, last] = windows[windows.length - 1];
  return last;
}

export type Shot = { cam: string; zoom: number; session: number; src: number; segEndOut: number };

/** O que se vê no instante t de saída: câmara, zoom, tempo na gravação; null fora do vídeo. */
export function shotAt(doc: EditDoc, t: number): Shot | null {
  const p = outToSrc(doc, t);
  if (!p) return null;
  const c = doc.cameras.find((k) => p.src >= k.s && p.src < k.e) ?? doc.cameras.find((k) => Math.abs(p.src - k.e) < 1e-3);
  const windows = (doc as EditDoc & { source?: { windows?: Windows } }).source?.windows;
  return { cam: c?.cam ?? "front", zoom: c?.zoom ?? 1, src: p.src, session: virtualToSession(windows, p.src), segEndOut: p.seg.at + p.seg.dur };
}

/** Câmara de onde vem o som (por defeito a primeira). */
export function audioCam(doc: EditDoc): string {
  const s = (doc as EditDoc & { source?: { audio?: string; cams?: Record<string, string> } }).source;
  return s?.audio ?? Object.keys(s?.cams ?? { front: "" })[0];
}

/** Desvio tolerado entre o vídeo e o relógio do editor antes de voltar a posicionar (s). */
export const DRIFT_S = 0.25;

/** Trecho de áudio contínuo: de outStart a outEnd (saída) o som corre seguido a partir de sess (tempo da gravação). */
export type Run = { outStart: number; outEnd: number; sess: number };

/**
 * Os trechos que o palco toca sem saltar (W10-29): cada segmento partido nas janelas da sessão, e segmentos seguidos na
 * fonte e na gravação colados num só. Só há salto no áudio onde o corte o exige; o resto toca de seguida.
 */
export function audioRuns(doc: EditDoc, windows?: Windows | null): Run[] {
  const runs: Run[] = [];
  const wins = windows ?? (doc as EditDoc & { source?: { windows?: Windows } }).source?.windows ?? null;
  const bounds: number[] = [];                       // fronteiras do tempo virtual onde a gravação salta
  if (wins?.length) { let acc = 0; for (const [a, b] of wins) { acc += b - a; bounds.push(acc); } }
  let at = 0;
  for (const s of doc.segments) {
    const cuts = [s.in, ...bounds.filter((x) => x > s.in + 1e-6 && x < s.out - 1e-6), s.out];
    for (let i = 0; i < cuts.length - 1; i++) {
      const a = cuts[i], b = cuts[i + 1], len = b - a;
      if (len <= 1e-6) continue;
      const sess = virtualToSession(wins, a);
      const prev = runs[runs.length - 1];
      if (prev && Math.abs(prev.outEnd - at) < 1e-6 && Math.abs(prev.sess + (prev.outEnd - prev.outStart) - sess) < 0.02) prev.outEnd = at + len;
      else runs.push({ outStart: at, outEnd: at + len, sess });
      at += len;
    }
  }
  return runs.map((r) => ({ outStart: Math.round(r.outStart * 1000) / 1000, outEnd: Math.round(r.outEnd * 1000) / 1000, sess: Math.round(r.sess * 1000) / 1000 }));
}

/** Índice do trecho que contém o instante t de saída (o último se t passou o fim); -1 sem trechos. */
export function runAt(runs: Run[], t: number): number {
  if (!runs.length) return -1;
  const i = runs.findIndex((r) => t >= r.outStart - 1e-6 && t < r.outEnd - 1e-6);
  return i >= 0 ? i : runs.length - 1;
}
