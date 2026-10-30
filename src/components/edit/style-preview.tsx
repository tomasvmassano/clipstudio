"use client";

import { Inter, Instrument_Serif } from "next/font/google";
import { SAFE, LAYER_LABEL, type Layer, type StyleSpec } from "@/lib/edit-styles";
import { cn } from "@/lib/utils";

/*
 * Pré-visualização de um estilo como o vídeo vai sair (VAR-02): 1080×1920 em unidades reais, com o tipo de letra,
 * o tamanho, a caixa, as cores e o destaque de cada camada tal como o motor de render os usa. O texto é de exemplo;
 * a imagem e o vídeo são marcadores (não há media real no catálogo). `boxes` mostra as caixas e o retângulo seguro.
 */

const serif = Instrument_Serif({ subsets: ["latin"], weight: "400", display: "swap" });
const inter = Inter({ subsets: ["latin"], display: "swap" });

const SAMPLE_TITLE = "Dividir a conta no primeiro encontro";
const SAMPLE_WORDS = "Tu podes ter tido a melhor conversa da tua vida".split(" ");
const BOX_FILL: Record<string, string> = {
  video: "#3b82f6", image: "#8b5cf6", attention_video: "#14b8a6", title: "#facc15", captions: "#f97316", band: "#ef4444",
};

/** Família CSS para o nome de letra do spec; fonte desconhecida cai na letra da app (e o nome fica no aria-label). */
function family(name: string | undefined, kind: Layer["kind"]) {
  const n = (name ?? "").toLowerCase();
  if (n.includes("instrument")) return serif.style.fontFamily;
  if (n.includes("inter")) return inter.style.fontFamily;
  return kind === "title" ? inter.style.fontFamily : "var(--font-sans-app), sans-serif";
}

const num = (v: unknown, d: number) => (typeof v === "number" && Number.isFinite(v) ? v : d);
const str = (v: unknown) => (typeof v === "string" ? v : undefined);

function Person() {
  // marcador neutro para dar a escala da cara e do tronco no enquadramento vertical
  return (
    <g fill="#ffffff" fillOpacity={0.08}>
      <ellipse cx={540} cy={860} rx={210} ry={260} />
      <path d="M140 1920 C160 1420 330 1230 540 1230 C750 1230 920 1420 940 1920 Z" />
    </g>
  );
}

function TextLayer({ l, children, align }: { l: Layer; children: React.ReactNode; align: "left" | "center" }) {
  const [x, y, w, h] = l.box;
  return (
    <foreignObject x={x} y={y} width={w} height={h} style={{ overflow: "visible" }}>
      <div style={{ width: w, height: h, display: "flex", flexDirection: "column", alignItems: align === "left" ? "flex-start" : "center", justifyContent: "flex-start" }}>
        {children}
      </div>
    </foreignObject>
  );
}

function Title({ l }: { l: Layer }) {
  const size = num(l.size, 64);
  const bg = str(l.background);
  const text = str(l.text) ?? SAMPLE_TITLE;
  return (
    <TextLayer l={l} align="center">
      <div style={{
        fontFamily: family(str(l.font), "title"), fontSize: size, lineHeight: 1.05, color: str(l.color) ?? "#ffffff",
        fontWeight: l.weight === "bold" ? 800 : 400, textAlign: "center", maxWidth: l.box[2],
        background: bg, borderRadius: bg ? num(l.radius, 22) : 0, padding: bg ? "22px 34px" : 0,
        boxShadow: bg ? "0 6px 20px rgba(0,0,0,.35)" : undefined,
        WebkitTextStroke: l.stroke ? `${Math.max(2, size / 22)}px ${l.stroke}` : undefined, paintOrder: "stroke fill",
      }}>{text}</div>
    </TextLayer>
  );
}

function Captions({ l }: { l: Layer }) {
  const size = num(l.size, 72);
  const max = Math.max(1, Math.min(num(l.max_words, 6), SAMPLE_WORDS.length));
  const words = max === 1 ? ["conversa"] : SAMPLE_WORDS.slice(0, max);
  const left = l.align === "left";
  const hl = str(l.highlight);
  const said = Math.ceil(words.length * 0.55);   // parte já dita, para mostrar o destaque
  const shadow = l.shadow ? "0 3px 10px rgba(0,0,0,.75)" : hl ? "2px 3px 0 rgba(0,0,0,.45)" : "0 2px 8px rgba(0,0,0,.6)";
  return (
    <TextLayer l={l} align={left ? "left" : "center"}>
      <div style={{
        fontFamily: family(str(l.font), "captions"), fontSize: size, lineHeight: 1.12, color: str(l.color) ?? "#ffffff",
        fontWeight: (str(l.font) ?? "").toLowerCase().includes("bold") ? 800 : 400, textAlign: left ? "left" : "center",
        textShadow: shadow, maxWidth: l.box[2], WebkitTextStroke: l.stroke ? `1px ${l.stroke}` : undefined,
      }}>
        {hl ? (
          <>
            <span style={{ background: hl, boxDecorationBreak: "clone", WebkitBoxDecorationBreak: "clone", padding: "0 8px", marginLeft: -8 }}>
              {words.slice(0, said).join(" ")}
            </span>{" "}{words.slice(said).join(" ")}
          </>
        ) : words.join(" ")}
      </div>
    </TextLayer>
  );
}

function MediaBox({ l }: { l: Layer }) {
  const [x, y, w, h] = l.box;
  const full = w >= 1000 && h >= 1800;
  if (full) return null;   // vídeo de ecrã inteiro: o fundo já o representa
  const iw = Math.min(w, h * (4 / 3)); const ix = x + (w - iw) / 2;   // imagens em 4:3 dentro da caixa (fit contain)
  return (
    <g>
      <rect x={l.kind === "image" ? ix : x} y={y} width={l.kind === "image" ? iw : w} height={h} fill="#3f3f46" />
      <path d={`M${(l.kind === "image" ? ix : x) + 40} ${y + h - 40} l${Math.min(w, iw) * 0.3} ${-h * 0.45} l${Math.min(w, iw) * 0.2} ${h * 0.25} l${Math.min(w, iw) * 0.15} ${-h * 0.15} l${Math.min(w, iw) * 0.25} ${h * 0.35} Z`} fill="#71717a" />
      <text x={x + w / 2} y={y + 64} textAnchor="middle" fontSize={44} fill="#d4d4d8">{str(l.role) ?? LAYER_LABEL[l.kind]}</text>
    </g>
  );
}

export function StylePreview({ spec, boxes = false, className }: { spec: StyleSpec | null; boxes?: boolean; className?: string }) {
  const layers = (Array.isArray(spec?.layers) ? spec!.layers : []).filter((l) => Array.isArray(l?.box) && l.box.length === 4);
  const fonts = [...new Set(layers.map((l) => str(l.font)).filter(Boolean))].join(", ");
  const label = layers.length ? `Pré-visualização com ${layers.length} camadas${fonts ? `, letra ${fonts}` : ""}` : "Layout ainda por desenhar";
  const hasVideo = layers.some((l) => l.kind === "video");
  return (
    <svg viewBox="0 0 1080 1920" role="img" aria-label={label} className={cn("h-auto w-full rounded-md border bg-neutral-950", className)}>
      <defs>
        <linearGradient id="sp-bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#3f3f46" /><stop offset="1" stopColor="#18181b" /></linearGradient>
      </defs>
      {hasVideo && <rect width={1080} height={1920} fill="url(#sp-bg)" />}
      {hasVideo && <Person />}
      {layers.map((l, i) => {
        if (l.kind === "video" || l.kind === "image" || l.kind === "attention_video") return <MediaBox key={i} l={l} />;
        if (l.kind === "band") return <rect key={i} x={l.box[0]} y={l.box[1]} width={l.box[2]} height={l.box[3]} fill={l.color ?? BOX_FILL.band} />;
        return null;
      })}
      {layers.map((l, i) => l.kind === "title" ? <Title key={i} l={l} /> : l.kind === "captions" ? <Captions key={i} l={l} /> : null)}
      {boxes && layers.map((l, i) => (
        <g key={`b${i}`}>
          <rect x={l.box[0]} y={l.box[1]} width={l.box[2]} height={l.box[3]} fill="none" stroke={BOX_FILL[l.kind] ?? "#64748b"} strokeWidth={6} />
          <text x={l.box[0] + 16} y={l.box[1] + 48} fontSize={40} fill={BOX_FILL[l.kind] ?? "#cbd5e1"} fontWeight={700}>{LAYER_LABEL[l.kind] ?? l.kind}</text>
        </g>
      ))}
      {boxes && <rect x={SAFE.x0} y={SAFE.y0} width={SAFE.x1 - SAFE.x0} height={SAFE.y1 - SAFE.y0} fill="none" stroke="#e5e7eb" strokeWidth={6} strokeDasharray="30 20" />}
      {!layers.length && <text x={540} y={980} textAnchor="middle" fontSize={64} fill="#9ca3af">Layout por desenhar</text>}
    </svg>
  );
}
