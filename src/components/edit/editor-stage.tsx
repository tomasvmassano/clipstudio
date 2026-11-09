"use client";

import { useMemo, type ReactNode } from "react";
import { hookEnd, layout, outToSrc, type EditDoc, type TextLook } from "@/lib/edit-doc";
import { CAP_STYLES, captionAtState, captionStates, capStyleOf, wipeFrac } from "@/lib/caption-plan";

/** Vermelho do destaque do S15 (RED em render_doc.py). */
const S15_RED = "#E2002C";

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
export function EditorStage({ doc, t, media, className }: { doc: EditDoc; t: number; media?: ReactNode; className?: string }) {
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
  const hl = { ...DEFAULT_LOOK.hook, ...(doc.look?.hook ?? {}) };
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
      {t < hEnd && doc.hook.text && (
        <div className="absolute inset-x-[8%] -translate-y-1/2 text-center font-extrabold leading-tight [text-shadow:0_1px_3px_#000,0_0_2px_#000]"
          style={{ top: top(hl.y), fontSize: px(hl.size), color: hl.color }}>
          <span className="box-decoration-clone px-[0.2em]" style={hl.background ? { background: hl.background } : undefined}>{text(doc.hook.text, hl.upper)}</span>
        </div>
      )}
      {ovNow.map((o) => o.box ? (
        // posição própria (ADR-0068): a caixa onde o render desenha o visual, à escala do palco
        <div key={o.id} className="absolute flex items-center justify-center overflow-hidden rounded border border-white/30 bg-black/50 px-2 py-1 text-center text-[11px] text-white"
          style={{ left: `${(o.box[0] / 1080) * 100}%`, top: top(o.box[1]), width: `${(o.box[2] / 1080) * 100}%`, height: `${(o.box[3] / 1920) * 100}%` }}>
          {o.kind === "text" ? o.label : `${o.kind === "broll" ? "B-roll" : "Gráfico"}: ${o.label}`}
        </div>
      ) : (
        <div key={o.id} className="absolute inset-x-[10%] top-[38%] rounded border border-white/30 bg-black/50 px-2 py-1 text-center text-[11px] text-white">
          {o.kind === "broll" ? "B-roll" : o.kind === "graphic" ? "Gráfico" : "Texto"}: {o.label}
        </div>
      ))}
      {capNow && (capStyle === "S14" ? (
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
    </div>
  );
}
