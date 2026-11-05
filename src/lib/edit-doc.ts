/*
 * Documento de edição (EDL-07, ADR-0046): funções puras, sem rede, testadas em tests/edit-doc.test.mts.
 * Tudo está em tempo da FONTE (a gravação sincronizada das câmaras); o tempo de saída deriva dos segmentos, por ordem.
 * Assim aparar, apagar ou reordenar um corte reflui sozinho as legendas, as câmaras e os visuais desse trecho.
 */

export type Section = "hook" | "body";
export type Seg = { id: string; in: number; out: number; section: Section };
export type Word = { id: string; w: string; s: number; e: number };
export type Cam = { s: number; e: number; cam: string; zoom: number; intro?: boolean };
export type Overlay = { id: string; kind: "broll" | "graphic" | "text"; label: string; asset?: string | null; s: number; e: number };
export type Gain = { s: number; e: number; db: number };
/** Nota num momento (tempo da fonte), para quem edita ou para o agente (EDL-12). Fica na versão. */
export type Note = { id: string; s: number; text: string; by: string | null; done: boolean };
/** Aspeto das legendas e do hook (EDL-13): cores #RRGGBB, tamanho e centro vertical em px de 1080×1920 (dentro do retângulo seguro). */
export type TextLook = { color?: string; highlight?: string | null; background?: string | null; size?: number; y?: number; upper?: boolean };
export type Look = { captions?: TextLook | null; hook?: TextLook | null; from?: { key: string; version: number } | null };
export type EditDoc = {
  schema: 1; fps: number; size: [number, number]; style: string;
  segments: Seg[];
  captions: { words: Word[] };
  cameras: Cam[];
  hook: { text: string };
  overlays: Overlay[];
  audio: { music: { label: string; asset?: string | null; db: number } | null; sfx: { id: string; label: string; s: number }[]; gains: Gain[] };
  notes?: Note[];
  look?: Look | null;
};
export type Placed = Seg & { at: number; dur: number };

export const MIN_SEG = 0.1;
const r3 = (x: number) => Math.round(x * 1000) / 1000;

/** Segmentos com a posição na saída (at) e a duração. */
export function layout(doc: EditDoc): { segs: Placed[]; duration: number } {
  let at = 0;
  const segs = doc.segments.map((s) => { const p = { ...s, at: r3(at), dur: r3(s.out - s.in) }; at += s.out - s.in; return p; });
  return { segs, duration: r3(at) };
}

/** Tempo da fonte → saída. Um instante pode aparecer em mais de um segmento (repetido): devolve o primeiro. null = cortado. */
export function srcToOut(doc: EditDoc, t: number): number | null {
  for (const s of layout(doc).segs) if (t >= s.in && t < s.out) return r3(s.at + (t - s.in));
  return null;
}

/** Saída → fonte (e o segmento). */
export function outToSrc(doc: EditDoc, t: number): { seg: Placed; src: number } | null {
  const { segs } = layout(doc);
  const seg = segs.find((s) => t >= s.at && t < s.at + s.dur) ?? (t >= 0 && segs.length && Math.abs(t - (segs.at(-1)!.at + segs.at(-1)!.dur)) < 1e-6 ? segs.at(-1)! : null);
  return seg ? { seg, src: r3(seg.in + (t - seg.at)) } : null;
}

/** Um intervalo da fonte projetado na saída: um pedaço por segmento onde aparece (cortado = nenhum). */
export function spanOut(doc: EditDoc, s: number, e: number): { at: number; end: number }[] {
  const out: { at: number; end: number }[] = [];
  for (const g of layout(doc).segs) {
    const a = Math.max(s, g.in), b = Math.min(e, g.out);
    if (b > a) out.push({ at: r3(g.at + a - g.in), end: r3(g.at + b - g.in) });
  }
  return out;
}

/** Palavras na saída, pela ordem em que se ouvem. */
export function wordsOut(doc: EditDoc): (Word & { at: number; end: number })[] {
  const res: (Word & { at: number; end: number })[] = [];
  for (const w of doc.captions.words) for (const p of spanOut(doc, w.s, w.e)) res.push({ ...w, ...p });
  return res.sort((a, b) => a.at - b.at);
}

/** Texto da legenda à volta de um instante da saída (as palavras que se ouvem nessa janela). */
export function captionAt(doc: EditDoc, t: number, span = 1.2): string {
  return wordsOut(doc).filter((w) => w.end > t - span / 2 && w.at < t + span / 2).map((w) => w.w).join(" ");
}

export function hookEnd(doc: EditDoc): number {
  const { segs } = layout(doc);
  const hooks = segs.filter((s) => s.section === "hook");
  return hooks.length ? r3(Math.max(...hooks.map((s) => s.at + s.dur))) : 0;
}

const mapSegs = (doc: EditDoc, f: (s: Seg[]) => Seg[]): EditDoc => ({ ...doc, segments: f(doc.segments) });

/** Muda a entrada ou a saída de um corte (tempo da fonte), com pelo menos MIN_SEG de duração. */
export function trimSegment(doc: EditDoc, id: string, edge: "in" | "out", src: number): EditDoc {
  return mapSegs(doc, (ss) => ss.map((s) => {
    if (s.id !== id) return s;
    if (edge === "in") return { ...s, in: r3(Math.min(Math.max(0, src), s.out - MIN_SEG)) };
    return { ...s, out: r3(Math.max(src, s.in + MIN_SEG)) };
  }));
}

/** Divide o corte no instante da saída indicado. Fica igual se cair a menos de MIN_SEG de uma ponta. */
export function splitSegment(doc: EditDoc, id: string, atOut: number, newId: string): EditDoc {
  const p = layout(doc).segs.find((s) => s.id === id);
  if (!p) return doc;
  const src = r3(p.in + (atOut - p.at));
  if (src - p.in < MIN_SEG || p.out - src < MIN_SEG) return doc;
  return mapSegs(doc, (ss) => ss.flatMap((s) => (s.id === id ? [{ ...s, out: src }, { ...s, id: newId, in: src }] : [s])));
}

export function deleteSegment(doc: EditDoc, id: string): EditDoc {
  if (doc.segments.length <= 1) return doc;   // um vídeo tem pelo menos um corte
  return mapSegs(doc, (ss) => ss.filter((s) => s.id !== id));
}

export function moveSegment(doc: EditDoc, id: string, dir: -1 | 1): EditDoc {
  const i = doc.segments.findIndex((s) => s.id === id), j = i + dir;
  if (i < 0 || j < 0 || j >= doc.segments.length) return doc;
  const ss = [...doc.segments]; [ss[i], ss[j]] = [ss[j], ss[i]];
  return { ...doc, segments: ss };
}

export function editWord(doc: EditDoc, id: string, patch: Partial<Pick<Word, "w" | "s" | "e">>): EditDoc {
  return { ...doc, captions: { words: doc.captions.words.map((w) => {
    if (w.id !== id) return w;
    const n = { ...w, ...patch };
    if (typeof n.w === "string") n.w = n.w.replace(/\s+/g, " ").trim().slice(0, 60);
    if (n.e < n.s) n.e = n.s;
    return { ...n, s: r3(n.s), e: r3(n.e) };
  }).filter((w) => w.w !== "") } };
}

export const setHook = (doc: EditDoc, text: string): EditDoc => ({ ...doc, hook: { text: text.slice(0, 200) } });
export const setMusicDb = (doc: EditDoc, db: number): EditDoc =>
  ({ ...doc, audio: { ...doc.audio, music: doc.audio.music ? { ...doc.audio.music, db: Math.max(-40, Math.min(6, Math.round(db))) } : null } });
export const removeOverlay = (doc: EditDoc, id: string): EditDoc => ({ ...doc, overlays: doc.overlays.filter((o) => o.id !== id) });

/** Põe um visual (B-roll, gráfico ou texto) a começar no instante da saída indicado; fica preso ao trecho da fonte. */
export function addOverlay(doc: EditDoc, o: Omit<Overlay, "s" | "e">, atOut: number, dur = 2): EditDoc {
  const p = outToSrc(doc, atOut);
  if (!p) return doc;
  const s = p.src, e = Math.min(p.seg.out, s + dur);
  if (e - s < MIN_SEG) return doc;
  return { ...doc, overlays: [...doc.overlays, { ...o, s: r3(s), e: r3(e) }] };
}
/** Desloca um visual ou uma palavra no tempo da fonte (dentro do mesmo corte, para não ir parar a um trecho cortado). */
export function shiftOverlay(doc: EditDoc, id: string, dt: number): EditDoc {
  return { ...doc, overlays: doc.overlays.map((o) => (o.id === id ? { ...o, s: r3(Math.max(0, o.s + dt)), e: r3(Math.max(0, o.e + dt)) } : o)) };
}
export function resizeOverlay(doc: EditDoc, id: string, edge: "s" | "e", src: number): EditDoc {
  return { ...doc, overlays: doc.overlays.map((o) => {
    if (o.id !== id) return o;
    return edge === "s" ? { ...o, s: r3(Math.min(Math.max(0, src), o.e - MIN_SEG)) } : { ...o, e: r3(Math.max(src, o.s + MIN_SEG)) };
  }) };
}
export const setMusic = (doc: EditDoc, m: { label: string; asset: string | null } | null): EditDoc =>
  ({ ...doc, audio: { ...doc.audio, music: m ? { label: m.label.slice(0, 120), asset: m.asset, db: doc.audio.music?.db ?? -18 } : null, gains: m ? doc.audio.gains : [] } });
/** Volume da música num trecho da fonte (substitui o que já houver nesse trecho). */
export function setGain(doc: EditDoc, s: number, e: number, db: number): EditDoc {
  const g = { s: r3(s), e: r3(e), db: Math.max(-40, Math.min(6, Math.round(db))) };
  return { ...doc, audio: { ...doc.audio, gains: [...doc.audio.gains.filter((x) => x.e <= s || x.s >= e), g].sort((a, b) => a.s - b.s) } };
}
export const clearGain = (doc: EditDoc, s: number): EditDoc => ({ ...doc, audio: { ...doc.audio, gains: doc.audio.gains.filter((g) => g.s !== s) } });

export function addNote(doc: EditDoc, atOut: number, text: string, by: string | null, id: string): EditDoc {
  const p = outToSrc(doc, atOut);
  const clean = text.trim().slice(0, 500);
  if (!p || !clean) return doc;
  return { ...doc, notes: [...(doc.notes ?? []), { id, s: p.src, text: clean, by, done: false }] };
}
export const toggleNote = (doc: EditDoc, id: string): EditDoc => ({ ...doc, notes: (doc.notes ?? []).map((n) => (n.id === id ? { ...n, done: !n.done } : n)) });
export const removeNote = (doc: EditDoc, id: string): EditDoc => ({ ...doc, notes: (doc.notes ?? []).filter((n) => n.id !== id) });
/** Notas na saída, por ordem (as de trechos cortados ficam com at = null, para não se perderem). */
export function notesOut(doc: EditDoc): (Note & { at: number | null })[] {
  return (doc.notes ?? []).map((n) => ({ ...n, at: srcToOut(doc, n.s) })).sort((a, b) => (a.at ?? 1e9) - (b.at ?? 1e9));
}
/** Desloca uma palavra (as duas pontas). */
export const shiftWord = (doc: EditDoc, id: string, dt: number): EditDoc => {
  const w = doc.captions.words.find((x) => x.id === id);
  return w ? editWord(doc, id, { s: Math.max(0, w.s + dt), e: Math.max(0, w.e + dt) }) : doc;
};

/** O mesmo que o servidor recusa (_edit_doc_problem), para avisar antes de gravar. null = válido. */
export function problem(d: EditDoc): string | null {
  if (!d || d.schema !== 1) return "versão do formato desconhecida";
  if (!Array.isArray(d.segments) || d.segments.length === 0) return "sem segmentos";
  if (d.segments.length > 400) return "segmentos a mais";
  for (const s of d.segments) if (!(s.in >= 0) || !(s.out - s.in >= MIN_SEG - 1e-9)) return "segmento com menos de 0,1 s";
  for (const w of d.captions?.words ?? []) if (!(w.e >= w.s) || w.w.length > 60) return "palavra de legenda inválida";
  if ((d.hook?.text ?? "").length > 200) return "hook demasiado longo";
  for (const o of d.overlays ?? []) if (!(o.e - o.s >= MIN_SEG - 1e-9)) return "visual com menos de 0,1 s";
  return lookProblem(d.look);
}

export const LOOK_LIMITS = { size: [30, 140], y: [260, 1550] } as const;
const HEX = /^#[0-9A-Fa-f]{6}$/;
/** O mesmo que _edit_look_problem. */
export function lookProblem(l: Look | null | undefined): string | null {
  if (l == null) return null;
  for (const part of [l.captions, l.hook]) {
    if (part == null) continue;
    for (const c of [part.color, part.highlight, part.background]) if (c != null && !HEX.test(c)) return "cor inválida no aspeto";
    if (part.size != null && !(part.size >= LOOK_LIMITS.size[0] && part.size <= LOOK_LIMITS.size[1])) return "tamanho do texto entre 30 e 140";
    if (part.y != null && !(part.y >= LOOK_LIMITS.y[0] && part.y <= LOOK_LIMITS.y[1])) return "texto fora do retângulo seguro (y 260-1550)";
  }
  return null;
}

/* ---------- modo guiado (EDL-10) ---------- */

/** Um corte que já existiu numa versão anterior deste documento e não está nesta (vem do servidor: cut_pool). */
export type PoolSeg = { seg: Seg; after: string | null; version_no: number };

/** Repõe um corte: a seguir ao corte que o precedia, se ainda estiver; senão pela ordem da fonte. Não repete ids. */
export function restoreSegment(doc: EditDoc, seg: Seg, after: string | null): EditDoc {
  if (doc.segments.some((s) => s.id === seg.id)) return doc;
  const ss = [...doc.segments];
  let i: number;
  if (after == null) i = 0;
  else {
    const j = ss.findIndex((s) => s.id === after);
    i = j >= 0 ? j + 1 : (() => { const k = ss.findIndex((s) => s.in > seg.in); return k < 0 ? ss.length : k; })();
  }
  ss.splice(i, 0, seg);
  return { ...doc, segments: ss };
}

/** Cortes que dá para repor: os do servidor e os da versão base que se tiraram agora (ainda por gravar). */
export function restorable(doc: EditDoc, base: EditDoc, pool: PoolSeg[]): PoolSeg[] {
  const have = new Set(doc.segments.map((s) => s.id));
  const out = new Map<string, PoolSeg>();
  base.segments.forEach((s, i) => { if (!have.has(s.id)) out.set(s.id, { seg: s, after: i ? base.segments[i - 1].id : null, version_no: 0 }); });
  for (const p of pool) if (!have.has(p.seg.id) && !out.has(p.seg.id)) out.set(p.seg.id, p);
  return [...out.values()];
}

/** Palavras de cada corte, pela ordem da saída (para corrigir as legendas sem a linha do tempo). */
export function wordsBySegment(doc: EditDoc): { seg: Placed; words: (Word & { at: number; end: number })[] }[] {
  const ws = wordsOut(doc);
  return layout(doc).segs.map((seg) => ({ seg, words: ws.filter((w) => w.at >= seg.at - 1e-6 && w.at < seg.at + seg.dur - 1e-6) }));
}

const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
const omit = <T extends object>(o: T | null | undefined, ks: string[]) => Object.fromEntries(Object.entries(o ?? {}).filter(([k]) => !ks.includes(k)).sort(([a], [b]) => a.localeCompare(b)));

/**
 * Espelho de _edit_guided_problem (o servidor decide; isto avisa antes de gravar). null = permitido no modo guiado.
 * pool: cortes de versões anteriores; label: o nome de quem grava. A música só se verifica no servidor (biblioteca).
 */
export function guidedProblem(base: EditDoc, next: EditDoc, pool: Seg[], label: string | null): string | null {
  const free = ["segments", "captions", "hook", "audio", "notes"];
  if (!same(omit(next, free), omit(base, free))) return "no modo guiado só mudam as legendas, o hook, os cortes, a música e as notas";
  if (!same(omit(next.hook, ["text"]), omit(base.hook, ["text"]))) return "no modo guiado só muda o texto do hook";
  const nw = next.captions.words, bw = base.captions.words;
  if (!same(omit(next.captions, ["words"]), omit(base.captions, ["words"])) || nw.length !== bw.length) return "no modo guiado as palavras das legendas corrigem-se, não se tiram nem se juntam";
  if (nw.some((w, i) => !same(omit(w, ["w"]), omit(bw[i], ["w"])) || !w.w.trim())) return "no modo guiado só se corrige o texto das palavras (os tempos ficam)";
  if (!same(omit(next.audio, ["music", "gains"]), omit(base.audio, ["music", "gains"]))) return "no modo guiado o som só muda na música";
  if (!same(next.audio.gains, base.audio.gains) && !(next.audio.music == null && next.audio.gains.length === 0)) return "no modo guiado o volume por trecho não muda";
  const ids = next.segments.map((s) => s.id);
  if (new Set(ids).size !== ids.length) return "cortes repetidos";
  const known = [...base.segments, ...pool].map((s) => JSON.stringify(omit(s, [])));
  if (next.segments.some((s) => !known.includes(JSON.stringify(omit(s, []))))) return "no modo guiado só se tiram cortes ou se repõem cortes de versões anteriores (sem aparar nem criar cortes)";
  const order = next.segments.map((s) => base.segments.findIndex((b) => b.id === s.id)).filter((i) => i >= 0);
  if (order.some((x, i) => i > 0 && x < order[i - 1])) return "no modo guiado a ordem dos cortes não muda";
  const bn = base.notes ?? [], nn = next.notes ?? [];
  if (bn.some((o) => !nn.some((x) => x.id === o.id && same(omit(x, ["done"]), omit(o, ["done"]))))) return "no modo guiado as notas não se apagam nem se reescrevem (só se marcam como feitas)";
  if (nn.some((x) => !bn.some((o) => o.id === x.id) && (x.done || !x.text.trim() || x.text.length > 500 || x.s < 0 || (x.by != null && x.by !== label))))
    return "nota nova inválida (momento, texto ou autor)";
  return null;
}

/** Desfazer/refazer: pilha simples de documentos. */
export type History = { past: EditDoc[]; present: EditDoc; future: EditDoc[] };
export const historyOf = (d: EditDoc): History => ({ past: [], present: d, future: [] });
export function push(h: History, d: EditDoc): History {
  if (d === h.present) return h;
  return { past: [...h.past, h.present].slice(-200), present: d, future: [] };
}
export const undo = (h: History): History => (h.past.length ? { past: h.past.slice(0, -1), present: h.past.at(-1)!, future: [h.present, ...h.future] } : h);
export const redo = (h: History): History => (h.future.length ? { past: [...h.past, h.present], present: h.future[0], future: h.future.slice(1) } : h);

/** mm:ss.d para a UI. */
export function fmtT(t: number): string {
  const s = Math.max(0, t), m = Math.floor(s / 60), r = s - m * 60;
  return `${m}:${r.toFixed(1).padStart(4, "0")}`;
}
