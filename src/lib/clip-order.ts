/*
 * Original vs. cortado (CLIP-06, ADR-0073): funções puras, sem rede, testadas em tests/clip-order.test.mts.
 * Compara a ordem dos trechos no master (tempo da fonte) com a ordem em que se ouvem no corte (a versão aberta).
 * ai.clip (numeiro-engine engine/clips.py) só guarda IDs de frase (original, parts, reordered), sem tempos: os tempos vêm
 * dos próprios campos do documento. Os segmentos dão a ordem e os tempos; as palavras das legendas ficam no documento
 * mesmo quando se tira um segmento, por isso marcam o trecho original inteiro e o que ficou de fora com fala.
 */
import type { EditDoc } from "./edit-doc.ts";

export type ClipInfo = { original: string[][]; parts: string[][]; reordered: boolean };

/** Trecho que está no corte. rank = lugar na ordem do master (1 = o mais cedo); outIndex = lugar no corte (1 = abre o vídeo). */
export type ClipPiece = {
  kind: "seg"; id: string; in: number; out: number; at: number; dur: number; rank: number; outIndex: number;
  moved: boolean; repeated: boolean; text: string; change: string;
};
/** Trecho do master com fala que ficou fora do corte (nunca tem posição na saída). */
export type ClipGap = { kind: "cut"; in: number; out: number; text: string; change: string };
export type ClipOrder = {
  info: ClipInfo; span: { in: number; out: number };
  /** Esquerda: tudo pela ordem do master. Direita: os trechos pela ordem do corte. */
  original: (ClipPiece | ClipGap)[]; cut: ClipPiece[];
  moved: number; removed: number; unchanged: boolean;
};

const r3 = (x: number) => Math.round(x * 1000) / 1000;
const fin = (x: unknown): x is number => typeof x === "number" && Number.isFinite(x);
const ids = (x: unknown): string[][] =>
  Array.isArray(x) ? x.filter(Array.isArray).map((p) => (p as unknown[]).filter((s): s is string => typeof s === "string")) : [];

/** Segundos do master em m:ss (ou h:mm:ss): um master pode ter horas. */
export function masterTime(sec: number): string {
  const s = Math.max(0, Math.floor(sec)), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${r}` : `${m}:${r}`;
}

/** ai.clip do documento, ou null quando o documento não veio do Clip Miner. */
export function clipInfo(doc: Pick<EditDoc, "ai"> | null | undefined): ClipInfo | null {
  const c = doc?.ai && typeof doc.ai === "object" ? (doc.ai as Record<string, unknown>).clip : null;
  if (!c || typeof c !== "object" || Array.isArray(c)) return null;
  const o = c as Record<string, unknown>;
  return { original: ids(o.original), parts: ids(o.parts), reordered: o.reordered === true };
}

/**
 * Índices (na ordem do corte) que ficam no lugar: a maior subsequência crescente dos lugares no master. Em empate guarda a que
 * começa mais tarde, para que seja o trecho puxado para a frente (o gancho) a aparecer como movido, não os que ele empurrou.
 */
function keptInPlace(ranks: number[]): Set<number> {
  const n = ranks.length, best = new Array<number>(n).fill(1);
  for (let i = n - 1; i >= 0; i--) for (let j = i + 1; j < n; j++) if (ranks[j] > ranks[i]) best[i] = Math.max(best[i], best[j] + 1);
  const keep = new Set<number>();
  let need = Math.max(0, ...best), last = -Infinity, from = 0;
  while (need > 0) {
    let pick = -1;
    for (let i = from; i < n; i++) if (best[i] === need && ranks[i] > last) pick = i;   // o último que serve
    if (pick < 0) break;
    keep.add(pick); last = ranks[pick]; from = pick + 1; need--;
  }
  return keep;
}

const textOf = (doc: EditDoc, a: number, b: number, max = 90) => {
  const t = doc.captions.words.filter((w) => { const m = (w.s + w.e) / 2; return m >= a && m < b; })
    .sort((x, y) => x.s - y.s).map((w) => w.w).join(" ");
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t;
};

/**
 * A comparação, ou null sem ai.clip. Erro (string) quando o documento não dá para comparar.
 * minGap: buracos sem fala ou mais curtos do que isto não contam como corte (as pausas que o worker aparou entre frases).
 */
export function clipOrder(doc: EditDoc | null | undefined, minGap = 0.25): ClipOrder | string | null {
  const info = clipInfo(doc);
  if (!doc || !info) return null;
  const segs = Array.isArray(doc.segments) ? doc.segments : [];
  if (!segs.length) return "O documento não tem trechos para comparar.";
  if (segs.some((s) => !fin(s.in) || !fin(s.out) || s.out <= s.in)) return "Há um trecho com tempos inválidos no documento.";
  const words = (doc.captions?.words ?? []).filter((w) => fin(w.s) && fin(w.e));

  // ordem do corte (como se ouve) e lugar de cada trecho no master
  let at = 0;
  const placed = segs.map((s, i) => { const p = { s, i, at: r3(at), dur: r3(s.out - s.in) }; at += s.out - s.in; return p; });
  const bySrc = [...placed].sort((a, b) => a.s.in - b.s.in || a.s.out - b.s.out || a.i - b.i);
  const rankOf = new Map(bySrc.map((p, k) => [p.i, k + 1]));
  const kept = keptInPlace(placed.map((p) => rankOf.get(p.i)!));

  const cut: ClipPiece[] = placed.map((p, k) => {
    const rank = rankOf.get(p.i)!;
    const repeated = placed.slice(0, k).some((q) => Math.min(q.s.out, p.s.out) - Math.max(q.s.in, p.s.in) > 0.1);
    const moved = !kept.has(k) && !repeated;
    return {
      kind: "seg", id: p.s.id, in: r3(p.s.in), out: r3(p.s.out), at: p.at, dur: p.dur, rank, outIndex: k + 1, moved, repeated,
      text: textOf(doc, p.s.in, p.s.out),
      change: repeated ? "repetido (este trecho já passou antes)" : moved ? `movido de ${rank}.º para ${k + 1}.º` : "na ordem original",
    };
  });

  // o trecho original: dos segmentos e das palavras (que ficam no documento mesmo com um segmento tirado)
  const lo = Math.min(...segs.map((s) => s.in), ...words.map((w) => w.s));
  const hi = Math.max(...segs.map((s) => s.out), ...words.map((w) => w.e));

  // partes do trecho original sem nenhum segmento por cima e com fala = cortado
  const cover = [...segs].map((s) => [s.in, s.out] as [number, number]).sort((a, b) => a[0] - b[0]);
  const holes: [number, number][] = [];
  let cur = lo;
  for (const [a, b] of cover) { if (a > cur) holes.push([cur, a]); cur = Math.max(cur, b); }
  if (hi > cur) holes.push([cur, hi]);
  const gaps: ClipGap[] = [];
  for (const [a, b] of holes) {
    const ws = words.filter((w) => { const m = (w.s + w.e) / 2; return m >= a && m < b; });
    if (!ws.length) continue;
    const s = Math.min(...ws.map((w) => w.s)), e = Math.max(...ws.map((w) => w.e));
    if (e - s < minGap) continue;
    gaps.push({ kind: "cut", in: r3(s), out: r3(e), text: textOf(doc, a, b), change: `cortado: ${masterTime(s)}-${masterTime(e)}` });
  }

  const original = [...bySrc.map((p) => cut[p.i]), ...gaps].sort((a, b) => a.in - b.in || (a.kind === "cut" ? 1 : -1));
  const moved = cut.filter((c) => c.moved).length;
  return { info, span: { in: r3(lo), out: r3(hi) }, original, cut, moved, removed: gaps.length, unchanged: moved === 0 && gaps.length === 0 && !cut.some((c) => c.repeated) };
}
