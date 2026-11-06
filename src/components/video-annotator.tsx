"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowUpRightIcon, CheckIcon, CircleIcon, PencilIcon, SquareIcon, Trash2Icon, Undo2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import {
  COLORS, DEFAULT_WIDTH, LIMITS, addPenPoint, arrowHead, box, canAdd, isMeaningful, penPath, toNormalized, toPixels, timelineMarkers,
  type Point, type Rect, type Shape, type ShapeType,
} from "@/lib/annotation";
import { fmtMoment } from "@/lib/media-time";

/** Anotações desenhadas no vídeo (W10-15, FR-05-03, ADR-0067): camada que mostra os desenhos, superfície de desenho (rato, caneta
 *  e toque no iPad, por Pointer Events), barra de ferramentas e marcas dos comentários na linha do tempo (QA-07). */

export const TOOLS: { v: ShapeType; l: string; icon: React.ReactNode }[] = [
  { v: "pen", l: "Caneta", icon: <PencilIcon /> }, { v: "arrow", l: "Seta", icon: <ArrowUpRightIcon /> },
  { v: "rect", l: "Retângulo", icon: <SquareIcon /> }, { v: "ellipse", l: "Círculo", icon: <CircleIcon /> },
];

function ShapeSvg({ s, r }: { s: Shape; r: Rect }) {
  const sw = Math.max(1.5, s.width * r.w);
  const common = { stroke: s.color, strokeWidth: sw, fill: "none", strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  if (s.type === "pen") return <path d={penPath(s.points, r)} {...common} />;
  const [a, b] = s.points.map((p) => toPixels(p, r));
  if (s.type === "arrow") {
    const [h1, h2] = arrowHead(a, b, sw);
    return <g {...common}><line x1={a[0]} y1={a[1]} x2={b[0]} y2={b[1]} /><polyline points={`${h1[0]},${h1[1]} ${b[0]},${b[1]} ${h2[0]},${h2[1]}`} /></g>;
  }
  const bx = box(s.points[0], s.points[1]);
  if (s.type === "rect") return <rect x={bx.x * r.w} y={bx.y * r.h} width={bx.w * r.w} height={bx.h * r.h} {...common} />;
  return <ellipse cx={(bx.x + bx.w / 2) * r.w} cy={(bx.y + bx.h / 2) * r.h} rx={(bx.w / 2) * r.w} ry={(bx.h / 2) * r.h} {...common} />;
}

/** Desenhos por cima do fotograma (só mostra; não apanha cliques, os controlos do vídeo continuam a funcionar). */
export function AnnotationLayer({ shapes, rect, label }: { shapes: Shape[]; rect: Rect; label: string }) {
  if (!shapes.length || !(rect.w > 0)) return null;
  return (
    <svg role="img" aria-label={label} data-testid="annotation-layer" width={rect.w} height={rect.h} viewBox={`0 0 ${rect.w} ${rect.h}`}
      className="pointer-events-none absolute" style={{ left: rect.x, top: rect.y, filter: "drop-shadow(0 0 1px rgb(0 0 0 / 0.8))" }}>
      {shapes.map((s, i) => <ShapeSvg key={i} s={s} r={rect} />)}
    </svg>
  );
}

/** Superfície de desenho sobre o fotograma pausado. Arrastar desenha a ferramenta escolhida; Ctrl+Z desfaz; Esc termina. */
export function DrawSurface({ rect, tool, color, shapes, onShapes, onDone }: {
  rect: Rect; tool: ShapeType; color: string; shapes: Shape[]; onShapes: (s: Shape[]) => void; onDone: () => void;
}) {
  const [cur, setCur] = useState<Shape | null>(null);
  const ref = useRef<HTMLDivElement | null>(null);
  useEffect(() => { ref.current?.focus(); }, []); // ao abrir, o foco vai para a área (Ctrl+Z e Esc funcionam logo)
  const at = (e: React.PointerEvent): Point => {
    const b = ref.current!.getBoundingClientRect();
    return toNormalized(e.clientX - b.left, e.clientY - b.top, { x: 0, y: 0, w: rect.w, h: rect.h });
  };
  const full = !canAdd(shapes, tool === "pen" ? 1 : 2);
  return (
    <div ref={ref} role="application" tabIndex={0} data-testid="draw-surface"
      aria-label={`Área de desenho sobre o fotograma, ${TOOLS.find((t) => t.v === tool)?.l.toLowerCase()}. Arrasta para desenhar. Ctrl+Z desfaz, Esc termina.`}
      className="absolute cursor-crosshair touch-none outline-2 outline-offset-2 outline-amber-400 focus-visible:outline-ring"
      style={{ left: rect.x, top: rect.y, width: rect.w, height: rect.h }}
      onKeyDown={(e) => {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") { e.preventDefault(); onShapes(shapes.slice(0, -1)); }
        else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); onDone(); }
      }}
      onPointerDown={(e) => {
        if (full || (e.pointerType === "mouse" && e.button !== 0)) return;
        e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId);
        const p = at(e);
        setCur({ type: tool, color, width: DEFAULT_WIDTH, points: tool === "pen" ? [p] : [p, p] });
      }}
      onPointerMove={(e) => {
        if (!cur) return;
        const p = at(e);
        setCur(cur.type === "pen" ? { ...cur, points: addPenPoint(cur.points, p) } : { ...cur, points: [cur.points[0], p] });
      }}
      onPointerUp={() => {
        if (cur && isMeaningful(cur) && canAdd(shapes, cur.points.length)) onShapes([...shapes, cur]);
        setCur(null);
      }}
      onPointerCancel={() => setCur(null)}>
      <AnnotationLayer shapes={cur ? [...shapes, cur] : shapes} rect={{ x: 0, y: 0, w: rect.w, h: rect.h }} label="Desenho em curso" />
    </div>
  );
}

/** Ferramentas, cores, desfazer, limpar e concluir. Tudo por teclado (Tab e Enter/Espaço). */
export function AnnotationToolbar({ tool, onTool, color, onColor, shapes, onShapes, onDone }: {
  tool: ShapeType; onTool: (t: ShapeType) => void; color: string; onColor: (c: string) => void;
  shapes: Shape[]; onShapes: (s: Shape[]) => void; onDone: () => void;
}) {
  const full = !canAdd(shapes, 1);
  return (
    <div role="toolbar" aria-label="Ferramentas de desenho" className="flex w-full max-w-xs flex-col gap-2 rounded-md border p-2">
      <ToggleGroup value={[tool]} onValueChange={(v) => { const t = (v as ShapeType[])[0]; if (t) onTool(t); }} variant="outline" className="flex-wrap">
        {TOOLS.map((t) => <ToggleGroupItem key={t.v} value={t.v} aria-label={t.l} title={t.l} className="min-h-9 min-w-9">{t.icon}</ToggleGroupItem>)}
      </ToggleGroup>
      <div role="radiogroup" aria-label="Cor" className="flex flex-wrap gap-2">
        {COLORS.map((c) => (
          <button key={c.v} type="button" role="radio" aria-checked={color === c.v} aria-label={c.l} title={c.l} onClick={() => onColor(c.v)}
            className={`size-9 rounded-full border-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring ${color === c.v ? "border-foreground" : "border-transparent"}`}
            style={{ backgroundColor: c.v }} />
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Button type="button" size="sm" variant="outline" disabled={!shapes.length} onClick={() => onShapes(shapes.slice(0, -1))}><Undo2Icon /> Desfazer</Button>
        <Button type="button" size="sm" variant="ghost" disabled={!shapes.length} onClick={() => onShapes([])}><Trash2Icon /> Limpar</Button>
        <Button type="button" size="sm" className="ml-auto" onClick={onDone}><CheckIcon /> Concluir</Button>
      </div>
      <p className="text-xs text-muted-foreground" aria-live="polite">
        {shapes.length} {shapes.length === 1 ? "forma" : "formas"}{full ? `. Chegaste ao limite (${LIMITS.shapes} formas ou ${LIMITS.totalPoints} pontos).` : "."}
      </p>
    </div>
  );
}

type MarkerComment = { id: string; t_ms: number | null; parent_id: string | null; body: string; annotation?: unknown; resolved_at?: string | null };

/** Linha do tempo com uma marca por comentário com momento (QA-07). Clicar (ou Enter) leva ao momento e mostra o desenho. */
export function VideoTimeline({ comments, durationMs, nowMs, onSeek }: {
  comments: MarkerComment[]; durationMs: number; nowMs: number; onSeek: (ms: number, id: string) => void;
}) {
  const marks = timelineMarkers(comments, durationMs);
  if (!marks.length) return null;
  const byId = new Map(comments.map((c) => [c.id, c]));
  return (
    <div className="w-full max-w-xs" aria-label="Comentários na linha do tempo" role="group">
      <div className="relative h-6 rounded bg-muted">
        <div aria-hidden className="absolute top-0 bottom-0 w-0.5 bg-foreground/60" style={{ left: `${Math.min(100, (nowMs / durationMs) * 100)}%` }} />
        {marks.map((m) => {
          const first = byId.get(m.ids[0]);
          const label = `${fmtMoment(m.t_ms)}: ${m.ids.length > 1 ? `${m.ids.length} comentários` : first?.body.slice(0, 80) ?? ""}${m.drawn ? " (com desenho)" : ""}`;
          return (
            <button key={m.ids.join()} type="button" aria-label={`Ir a ${label}`} title={label} data-testid="timeline-marker"
              onClick={() => onSeek(m.t_ms, m.ids[0])}
              className="absolute top-0 flex h-6 w-6 -translate-x-1/2 items-center justify-center focus-visible:outline-2 focus-visible:outline-ring"
              style={{ left: `${m.pct}%` }}>
              <span className={`block h-4 w-1.5 rounded-sm ${m.drawn ? "bg-amber-400" : "bg-sky-400"} ${m.open ? "" : "opacity-40"}`} />
            </button>
          );
        })}
      </div>
      <p className="mt-1 text-[11px] text-muted-foreground">Marcas: <span className="text-amber-400">com desenho</span> · <span className="text-sky-400">só texto</span></p>
    </div>
  );
}
