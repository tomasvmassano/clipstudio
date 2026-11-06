/** Anotações desenhadas no vídeo (W10-15, FR-05-03; ADR-0067): geometria e validação puras, sem React nem rede.
 *  Coordenadas normalizadas 0..1 em relação ao fotograma visível do vídeo (não à caixa do player), por isso o desenho cai no
 *  mesmo sítio em qualquer ecrã. Os limites são iguais aos de public._review_annotation (o servidor é quem decide). */

export type ShapeType = "pen" | "arrow" | "rect" | "ellipse";
export type Point = [number, number];
export type Shape = { type: ShapeType; color: string; width: number; points: Point[] };
export type Annotation = { v: 1; shapes: Shape[] };
export type Rect = { x: number; y: number; w: number; h: number };

export const LIMITS = { shapes: 50, penPoints: 500, totalPoints: 2000, minWidth: 0.002, maxWidth: 0.05 } as const;
export const SHAPE_TYPES: ShapeType[] = ["pen", "arrow", "rect", "ellipse"];
/** Cores com bom contraste sobre vídeo; o nome vai para o aria-label. */
export const COLORS: { v: string; l: string }[] = [
  { v: "#ff3b30", l: "Vermelho" }, { v: "#ffd60a", l: "Amarelo" }, { v: "#34c759", l: "Verde" }, { v: "#0a84ff", l: "Azul" }, { v: "#ffffff", l: "Branco" },
];
export const DEFAULT_WIDTH = 0.008;
/** Janela à volta do momento do comentário em que o desenho aparece por cima do vídeo (±0,5 s). */
export const SHOW_WINDOW_MS = 500;

const clamp01 = (n: number) => (n < 0 ? 0 : n > 1 ? 1 : n);
const r4 = (n: number) => Math.round(n * 10000) / 10000;

/** Retângulo do fotograma dentro da caixa do <video> (object-fit: contain). Sem dimensões do vídeo, a caixa toda. */
export function contentRect(boxW: number, boxH: number, videoW: number, videoH: number): Rect {
  if (!(boxW > 0 && boxH > 0)) return { x: 0, y: 0, w: 0, h: 0 };
  if (!(videoW > 0 && videoH > 0)) return { x: 0, y: 0, w: boxW, h: boxH };
  const s = Math.min(boxW / videoW, boxH / videoH);
  const w = videoW * s; const h = videoH * s;
  return { x: (boxW - w) / 2, y: (boxH - h) / 2, w, h };
}

/** Ponto do ecrã (relativo à caixa do player) → coordenada normalizada no fotograma, presa a 0..1 e a 4 casas. */
export function toNormalized(px: number, py: number, r: Rect): Point {
  if (!(r.w > 0 && r.h > 0)) return [0, 0];
  return [r4(clamp01((px - r.x) / r.w)), r4(clamp01((py - r.y) / r.h))];
}

/** Coordenada normalizada → pixels no fotograma (origem no canto do fotograma). */
export const toPixels = (p: Point, r: Rect): Point => [p[0] * r.w, p[1] * r.h];

/** Junta um ponto ao traço da caneta se se afastou o suficiente do último (menos pontos, mesmo desenho) e se cabe no limite. */
export function addPenPoint(points: Point[], p: Point, minDist = 0.004): Point[] {
  if (points.length >= LIMITS.penPoints) return points;
  const last = points[points.length - 1];
  if (last && Math.hypot(p[0] - last[0], p[1] - last[1]) < minDist) return points;
  return [...points, p];
}

/** Uma forma de dois pontos (seta, retângulo, círculo) só conta se não for um clique sem arrastar. */
export function isMeaningful(s: Shape, minSize = 0.01): boolean {
  if (s.type === "pen") return s.points.length >= 1;
  const [a, b] = s.points;
  return !!a && !!b && Math.hypot(b[0] - a[0], b[1] - a[1]) >= minSize;
}

export const totalPoints = (shapes: Shape[]) => shapes.reduce((n, s) => n + s.points.length, 0);
/** Ainda se pode juntar uma forma com `n` pontos? */
export const canAdd = (shapes: Shape[], n = 2) => shapes.length < LIMITS.shapes && totalPoints(shapes) + n <= LIMITS.totalPoints;

/** Pontas da seta (em pixels): duas linhas a partir da ponta, com tamanho proporcional à espessura. */
export function arrowHead(a: Point, b: Point, strokePx: number): [Point, Point] {
  const ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
  const len = Math.max(10, strokePx * 4);
  const spread = Math.PI / 7;
  return [
    [b[0] - len * Math.cos(ang - spread), b[1] - len * Math.sin(ang - spread)],
    [b[0] - len * Math.cos(ang + spread), b[1] - len * Math.sin(ang + spread)],
  ];
}

/** Caixa normalizada de dois pontos (para retângulo e elipse), qualquer que seja a direção do arrasto. */
export function box(a: Point, b: Point): Rect {
  return { x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: Math.abs(b[0] - a[0]), h: Math.abs(b[1] - a[1]) };
}

/** Caminho SVG de um traço em pixels. */
export function penPath(points: Point[], r: Rect): string {
  if (!points.length) return "";
  const px = points.map((p) => toPixels(p, r));
  if (px.length === 1) return `M${px[0][0].toFixed(1)} ${px[0][1].toFixed(1)}l0.01 0`; // um toque é um ponto visível
  return px.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join("");
}

/** Validação igual à do servidor. Devolve a mensagem do primeiro problema ou null; e `normalize` devolve a forma canónica. */
export function validateAnnotation(a: unknown): string | null {
  if (!a || typeof a !== "object" || Array.isArray(a)) return "Formato desconhecido.";
  const o = a as { v?: unknown; shapes?: unknown };
  if (o.v !== 1 || !Array.isArray(o.shapes)) return "Formato desconhecido.";
  if (o.shapes.length === 0) return "Desenho vazio.";
  if (o.shapes.length > LIMITS.shapes) return `Máximo de ${LIMITS.shapes} formas.`;
  let total = 0;
  for (const s of o.shapes as unknown[]) {
    if (!s || typeof s !== "object" || Array.isArray(s)) return "Forma inválida.";
    const x = s as Partial<Shape>;
    if (!SHAPE_TYPES.includes(x.type as ShapeType)) return "Tipo de forma não permitido.";
    if (typeof x.color !== "string" || !/^#[0-9a-fA-F]{6}$/.test(x.color)) return "Cor inválida.";
    if (typeof x.width !== "number" || !Number.isFinite(x.width)) return "Espessura inválida.";
    if (x.width < LIMITS.minWidth || x.width > LIMITS.maxWidth) return "Espessura fora do intervalo.";
    if (!Array.isArray(x.points)) return "Pontos inválidos.";
    const n = x.points.length;
    if (x.type === "pen" ? n < 1 || n > LIMITS.penPoints : n !== 2) return "Número de pontos inválido.";
    total += n;
    if (total > LIMITS.totalPoints) return `Máximo de ${LIMITS.totalPoints} pontos.`;
    for (const p of x.points as unknown[]) {
      if (!Array.isArray(p) || p.length !== 2 || typeof p[0] !== "number" || typeof p[1] !== "number" || !Number.isFinite(p[0]) || !Number.isFinite(p[1])) return "Ponto inválido.";
      if (p[0] < 0 || p[0] > 1 || p[1] < 0 || p[1] > 1) return "Coordenada fora do fotograma.";
    }
  }
  return null;
}

/** Forma canónica (só chaves conhecidas, cor em minúsculas, 4 casas), como o servidor a guarda. Assume `validateAnnotation` = null. */
export function normalize(a: Annotation): Annotation {
  return { v: 1, shapes: a.shapes.map((s) => ({ type: s.type, color: s.color.toLowerCase(), width: r4(s.width), points: s.points.map((p) => [r4(p[0]), r4(p[1])] as Point) })) };
}

/** A anotação que veio do servidor (ou null/JSON null) → Annotation utilizável, ou null se não for válida. */
export function parseAnnotation(a: unknown): Annotation | null {
  return a != null && validateAnnotation(a) === null ? (a as Annotation) : null;
}

/** Comentários (só os de topo, com momento e desenho) cujo momento está a ±janela do tempo atual do vídeo. */
export function activeAnnotations<C extends { id: string; t_ms: number | null; parent_id: string | null; annotation?: unknown }>(
  comments: C[], currentMs: number, windowMs = SHOW_WINDOW_MS,
): C[] {
  return comments.filter((c) => !c.parent_id && c.t_ms != null && Math.abs(c.t_ms - currentMs) <= windowMs && parseAnnotation(c.annotation) !== null);
}

/** Marcas na linha do tempo (QA-07): posição em % da duração, juntando comentários no mesmo sítio (a menos de `mergePct`). */
export function timelineMarkers<C extends { id: string; t_ms: number | null; parent_id: string | null; annotation?: unknown; resolved_at?: string | null }>(
  comments: C[], durationMs: number, mergePct = 1,
): { pct: number; t_ms: number; ids: string[]; drawn: boolean; open: boolean }[] {
  if (!(durationMs > 0)) return [];
  const roots = comments.filter((c) => !c.parent_id && c.t_ms != null).sort((a, b) => a.t_ms! - b.t_ms!);
  const out: { pct: number; t_ms: number; ids: string[]; drawn: boolean; open: boolean }[] = [];
  for (const c of roots) {
    const pct = Math.min(100, Math.max(0, (c.t_ms! / durationMs) * 100));
    const drawn = parseAnnotation(c.annotation) !== null; const open = !c.resolved_at;
    const last = out[out.length - 1];
    if (last && pct - last.pct < mergePct) { last.ids.push(c.id); last.drawn ||= drawn; last.open ||= open; }
    else out.push({ pct, t_ms: c.t_ms!, ids: [c.id], drawn, open });
  }
  return out;
}
