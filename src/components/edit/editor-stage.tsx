"use client";

import { useMemo, type ReactNode } from "react";
import { hookEnd, layout, outToSrc, type EditDoc, type TextLook } from "@/lib/edit-doc";
import { CAP_STYLES, GRAPHIC_BOXES, captionAtState, captionStates, capStyleOf, wipeFrac } from "@/lib/caption-plan";

/** Vermelho do destaque do S15 (RED em render_doc.py). */
const S15_RED = "#E2002C";
/** A faixa dos gráficos sem posição própria (GRAPHIC_BOX em render_doc.py) e a caixa do hook (title dos estilos S14/S15/S17). */
const GRAPHIC_BOX: [number, number, number, number] = [108, 730, 864, 600];
const TITLE_BOX = { x: 150, y: 215, w: 780, size: 76 };

/** Aspeto por omissão (o mesmo que o palco mostrava antes de haver "look" no documento). Em px de 1080×1920. */
export const DEFAULT_LOOK: { captions: Required<Pick<TextLook, "color" | "size" | "y">>; hook: Required<Pick<TextLook, "color" | "size" | "y">> } = {
  captions: { color: "#FFFFFF", size: 58, y: 1450 },
  hook: { color: "#FFFFFF", size: 52, y: 330 },
};

/**
 * Palco 9:16 do editor (EDL-08/09/10), partilhado pelo modo completo e pelo guiado. Desenha hook, visuais e legendas a partir
 * do documento no instante t da saída. `media` é a camada de imagem por baixo (o <video> do proxy quando houver R2, EDL-08):
 * fica em absolute inset-0 e quem a fornece sincroniza o tempo. Sem `media` mostra a câmara e o corte em texto.
 */
/** Guias do palco (W10-35): só no editor, nunca na exportação. reels = zona segura dos Reels; grid = terços com hook, olhos e legendas. */
export type StageGuides = { reels?: boolean; grid?: boolean };
/** O retângulo seguro do QC (EDL-03, engine/qc.py SAFE): o que fica fora pode ser tapado pela interface dos Reels. */
export const SAFE_RECT = { x0: 60, x1: 960, y0: 210, y1: 1600 };

export function EditorStage({ doc, t, media, className, guides, assetUrls }: {
  doc: EditDoc; t: number; media?: ReactNode; className?: string; guides?: StageGuides;
  /** Links das imagens da Biblioteca (id do ativo → URL): o palco mostra a imagem verdadeira, como o export (W10-37). */
  assetUrls?: Record<string, string>;
}) {
  const { segs } = layout(doc);
  const hEnd = hookEnd(doc);
  const at = outToSrc(doc, t);
  const src = at?.src ?? null;
  const cam = doc.cameras.find((c) => src != null && src >= c.s && src < c.e);
  const ovNow = doc.overlays.filter((o) => src != null && src >= o.s && src < o.e);
  // legendas: o mesmo plano que a exportação (blocos e tempos de render_doc.caption_plan), não uma janela deslizante
  const { duration } = layout(doc);
  const states = useMemo(() => captionStates(doc, duration), [doc, duration]);
  const capNow = captionAtState(states, t);
  const capStyle = capStyleOf(doc);
  const cs = CAP_STYLES[capStyle];
  const lk: TextLook = doc.look?.captions ?? {};
  const hk: TextLook = doc.look?.hook ?? {};
  const styleBox = GRAPHIC_BOXES[capStyle] ?? GRAPHIC_BOX;
  const segNo = at ? segs.findIndex((s) => s.id === at.seg.id) + 1 : segs.length;
  const px = (v: number) => `${(v / 1080) * 100}cqw`;   // px de 1080 → largura do palco
  const top = (y: number) => `${(y / 1920) * 100}%`;
  const text = (s: string, up?: boolean) => (up ? s.toLocaleUpperCase("pt-PT") : s);

  return (
    <div className={className ?? "relative mx-auto aspect-[9/16] w-full max-w-[20rem] overflow-hidden rounded-lg border bg-neutral-900"}
      style={{ containerType: "inline-size" }} aria-label="Pré-visualização">
      {media ? <div className="absolute inset-0">{media}</div> : (
        <div className="absolute inset-0 flex items-center justify-center text-xs text-neutral-500">
          {`${cam ? (cam.cam === "front" ? "Câmara frente" : "Câmara lado") : "Câmara"}${cam && cam.zoom !== 1 ? ` · zoom ${cam.zoom}` : ""} · corte ${segNo}`}
        </div>
      )}
      {/* visuais por baixo de tudo: o render desenha as legendas e o hook por cima */}
      {ovNow.map((o) => {
        const b = o.box ?? (o.kind === "broll" ? null : styleBox);
        const url = o.asset ? assetUrls?.[o.asset] : undefined;
        if (!b) return (
          <div key={o.id} className="absolute inset-0 flex items-center justify-center bg-black/60 text-center text-[11px] text-white">B-roll: {o.label}</div>
        );
        return (
          <div key={o.id} className="absolute flex items-center justify-center overflow-hidden"
            style={{ left: `${(b[0] / 1080) * 100}%`, top: top(b[1]), width: `${(b[2] / 1080) * 100}%`, height: `${(b[3] / 1920) * 100}%` }}>
            {o.kind === "graphic" && url ? (
              // eslint-disable-next-line @next/next/no-img-element -- link assinado curto do R2, sem otimização do Next
              <img src={url} alt={o.label} className="max-h-full max-w-full object-contain" />
            ) : (
              <span className="rounded border border-white/30 bg-black/50 px-2 py-1 text-[11px] text-white">
                {o.kind === "text" ? o.label : `${o.kind === "broll" ? "B-roll" : "Gráfico"}: ${o.label}`}</span>
            )}
          </div>
        );
      })}
      {t < hEnd && doc.hook.text && (
        // o hook como o render (draw_title): caixa branca arredondada, letra serifada preta; o aspeto muda cor, caixa, tamanho e y
        <div className="absolute flex justify-center"
          style={{ left: `${(TITLE_BOX.x / 1080) * 100}%`, width: `${(TITLE_BOX.w / 1080) * 100}%`,
            ...(hk.y != null ? { top: top(hk.y), transform: "translateY(-50%)" } : { top: top(TITLE_BOX.y) }) }}>
          <span className={hk.background === null ? "text-center font-serif leading-[1.05] [text-shadow:0_2px_4px_#000]" : "rounded-[2cqw] px-[3.1cqw] py-[2cqw] text-center font-serif leading-[1.05] shadow-lg"}
            style={{ fontSize: px(hk.size ?? TITLE_BOX.size), color: hk.color ?? "#000000",
              background: hk.background === null ? undefined : hk.background ?? "#FFFFFF" }}>
            {text(doc.hook.text, hk.upper)}</span>
        </div>
      )}
      {capNow && capStyle === "S17" && (
        // S17: uma linha numa caixa branca, ao centro; já dito a preto, o que vem a cinzento (draw_box_line)
        <div className="absolute flex justify-center"
          style={{ left: `${(cs.box[0] / 1080) * 100}%`, width: `${(cs.box[2] / 1080) * 100}%`, top: top(lk.y ?? cs.box[1] + cs.box[3] / 2), transform: "translateY(-50%)" }}>
          <span className="px-[0.28em] py-[0.16em] text-center font-serif leading-[1.12] shadow-md"
            style={{ fontSize: px(lk.size ?? cs.size), background: lk.background === null ? undefined : lk.background ?? "#FFFFFF" }}>
            {capNow.chunk.map((w, j) => (
              <span key={j} style={{ color: j <= capNow.active ? lk.color ?? "#111111" : lk.highlight ?? "#A6A6A6" }}>{j ? " " : ""}{text(w.w, lk.upper)}</span>
            ))}</span>
        </div>
      )}
      {capNow && capStyle !== "S17" && (capStyle === "S14" ? (
        // S14: a palavra que se ouve, ao centro da caixa; com destaque no aspeto leva essa cor
        <div className="absolute -translate-y-1/2 text-center font-serif [text-shadow:0_3px_5px_rgba(0,0,0,.8)]"
          style={{ left: `${(cs.box[0] / 1080) * 100}%`, width: `${(cs.box[2] / 1080) * 100}%`, top: top(lk.y ?? cs.box[1] + cs.size * 0.6),
            fontSize: px(lk.size ?? cs.size), color: lk.highlight || lk.color || "#FFFFFF" }}>
          <span className="box-decoration-clone px-[0.2em]" style={lk.background ? { background: lk.background } : undefined}>{text(capNow.chunk[0].w, lk.upper)}</span>
        </div>
      ) : (
        // S15: o bloco inteiro (até 2 linhas), alinhado à esquerda; o que já se disse em caixa vermelha (ou a palavra dita na cor de destaque)
        <div className="absolute font-serif leading-[1.12]"
          style={{ left: `${(cs.box[0] / 1080) * 100}%`, width: `${(cs.box[2] / 1080) * 100}%`, fontSize: px(lk.size ?? cs.size), color: lk.color || "#FFFFFF",
            ...(lk.y != null ? { top: top(lk.y), transform: "translateY(-50%)" } : { top: top(cs.box[1]) }) }}>
          {capNow.chunk.map((w, j) => {
            const redBox = !("highlight" in lk);
            const last = j === capNow.chunk.length - 1;
            const shadow = "box-decoration-clone [text-shadow:2px_3px_0_rgba(0,0,0,.47)]";
            if (redBox) {
              // barra contínua (como o render): as já ditas inteiras com o espaço a seguir, a que se diz até à fração dita
              if (j < capNow.active) return <span key={j} className={shadow} style={{ background: S15_RED }}>{text(w.w, lk.upper)}{last ? "" : " "}</span>;
              const pct = j === capNow.active ? Math.round(wipeFrac(w, t) * 1000) / 10 : 0;
              const bg = pct > 0 ? `linear-gradient(90deg, ${S15_RED} ${pct}%, ${lk.background || "transparent"} ${pct}%)` : lk.background || undefined;
              return <span key={j}><span className={shadow} style={{ background: bg }}>{text(w.w, lk.upper)}</span>{last ? "" : " "}</span>;
            }
            const color = lk.highlight && j === capNow.active ? lk.highlight : undefined;
            return <span key={j} className={shadow} style={{ background: lk.background || undefined, color }}>{text(w.w, lk.upper)}{last ? "" : " "}</span>;
          })}
        </div>
      ))}
      {guides?.reels && <ReelsGuide />}
      {guides?.grid && <GridGuide />}
    </div>
  );
}

/* Zona segura dos Reels: sombreia o que fica fora do retângulo seguro (a interface da app tapa) e a coluna dos botões à direita. */
function ReelsGuide() {
  const P = (v: number, total: number) => `${(v / total) * 100}%`;
  const shade = "absolute bg-red-600/30";
  return (
    <div className="pointer-events-none absolute inset-0" aria-hidden>
      <div className={shade} style={{ left: 0, right: 0, top: 0, height: P(SAFE_RECT.y0, 1920) }} />
      <div className={shade} style={{ left: 0, right: 0, top: P(SAFE_RECT.y1, 1920), bottom: 0 }} />
      <div className={shade} style={{ left: 0, width: P(SAFE_RECT.x0, 1080), top: P(SAFE_RECT.y0, 1920), height: P(SAFE_RECT.y1 - SAFE_RECT.y0, 1920) }} />
      <div className={shade} style={{ right: 0, width: P(1080 - SAFE_RECT.x1, 1080), top: P(SAFE_RECT.y0, 1920), height: P(SAFE_RECT.y1 - SAFE_RECT.y0, 1920) }} />
      <div className="absolute border border-dashed border-red-400/80" style={{ left: P(SAFE_RECT.x0, 1080), width: P(SAFE_RECT.x1 - SAFE_RECT.x0, 1080), top: P(SAFE_RECT.y0, 1920), height: P(SAFE_RECT.y1 - SAFE_RECT.y0, 1920) }} />
      <span className="absolute left-1 top-1 rounded bg-black/60 px-1 text-[9px] text-red-200">fora da zona segura dos Reels</span>
    </div>
  );
}

/* Terços com as faixas habituais: hook em cima, olhos na linha de cima dos terços, legendas em baixo. */
function GridGuide() {
  const band = (top: number, h: number, label: string) => (
    <div className="absolute inset-x-[8%] border border-yellow-300/70 bg-yellow-300/15" style={{ top: `${(top / 1920) * 100}%`, height: `${(h / 1920) * 100}%` }}>
      <span className="absolute left-1 top-0.5 text-[9px] font-medium text-yellow-100 [text-shadow:0_1px_2px_#000]">{label}</span>
    </div>
  );
  return (
    <div className="pointer-events-none absolute inset-0" aria-hidden>
      {[1, 2].map((k) => <div key={`h${k}`} className="absolute inset-x-0 border-t border-white/50" style={{ top: `${(k / 3) * 100}%` }} />)}
      {[1, 2].map((k) => <div key={`v${k}`} className="absolute inset-y-0 border-l border-white/50" style={{ left: `${(k / 3) * 100}%` }} />)}
      {band(215, 260, "hook")}
      {band(560, 160, "olhos")}
      {band(1250, 300, "legendas")}
    </div>
  );
}
