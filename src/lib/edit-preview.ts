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
