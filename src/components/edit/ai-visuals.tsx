"use client";

import { RefreshCwIcon, SparklesIcon, Trash2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  AI_RECIPE_LABEL, AI_SLOT_LABEL, aiVisuals, fmtT, pickState, removeOverlays, replaceOverlays, setMusic, spanOut,
  type AiPick, type EditDoc,
} from "@/lib/edit-doc";
import type { MediaAsset } from "@/lib/media";

const STATE_LABEL = { em_uso: "em uso", trocada: "trocada por ti", tirada: "tirada" } as const;

/**
 * O que a IA pôs na versão 1 (imagem, frase-persona, vídeo de atenção, música) e porquê, e o que ficou vazio e porquê
 * (ADR-0068). Com `onChange` (linha do tempo) dá para trocar ou tirar; sem ele (modo guiado) só mostra. As trocas usam a
 * biblioteca do cliente e, para a frase, só a lista aprovada que a IA recebeu (R-17). Sem doc.ai.visuals não mostra nada.
 */
export function AiVisualsPanel({ doc, lib, onChange, onSeek }: {
  doc: EditDoc; lib: MediaAsset[] | null; onChange?: (d: EditDoc) => void; onSeek?: (t: number) => void;
}) {
  const v = aiVisuals(doc);
  if (!v) return null;
  const options = (p: AiPick): { value: string; label: string }[] => {
    if (p.slot === "frase") return (v.phrase_options ?? []).map((x) => ({ value: x, label: x }));
    const kinds = p.slot === "imagem" ? ["imagem", "thumbnail"] : p.slot === "atencao" ? ["video"] : p.slot === "musica" ? ["audio"] : [];
    const tag = p.slot === "imagem" ? "ia-imagem" : p.slot === "atencao" ? "ia-atencao" : "ia-musica";
    return (lib ?? []).filter((a) => kinds.includes(a.kind))
      .sort((a, b) => Number(b.tags.includes(tag)) - Number(a.tags.includes(tag)))
      .map((a) => ({ value: a.id, label: `${a.title}${a.tags.includes(tag) ? ` (${tag})` : ""}` }));
  };
  const replace = (p: AiPick, value: string) => {
    if (!onChange || !value) return;
    if (p.slot === "frase") return onChange(replaceOverlays(doc, p.overlays, { label: value }));
    const a = (lib ?? []).find((x) => x.id === value);
    if (!a) return;
    if (p.slot === "musica") return onChange(setMusic(doc, { label: a.title, asset: a.id }));
    onChange(replaceOverlays(doc, p.overlays, { asset: a.id, label: a.title }));
  };
  const remove = (p: AiPick) => {
    if (!onChange) return;
    onChange(p.slot === "musica" ? setMusic(doc, null) : removeOverlays(doc, p.overlays));
  };
  const firstAt = (p: AiPick) => {
    const o = doc.overlays.find((x) => p.overlays.includes(x.id));
    return o ? spanOut(doc, o.s, o.e)[0]?.at ?? null : null;
  };

  return (
    <section className="flex flex-col gap-2" aria-label="Escolhas da IA">
      <div className="flex flex-wrap items-center gap-2">
        <SparklesIcon className="size-4 text-muted-foreground" aria-hidden />
        <span className="font-medium">Escolhas da IA na versão 1</span>
        <Badge variant="outline">{AI_RECIPE_LABEL[v.recipe] ?? v.recipe}</Badge>
      </div>
      {v.picks.length === 0 && v.empty.length === 0 && <p className="text-xs text-muted-foreground">A IA não pôs visuais nem música neste vídeo.</p>}
      <ul className="flex flex-col gap-2">
        {v.picks.map((p, i) => {
          const state = pickState(doc, p);
          const at = p.slot === "musica" ? null : firstAt(p);
          const opts = onChange ? options(p) : [];
          return (
            <li key={`${p.slot}-${i}`} className="flex flex-col gap-1 rounded-md border p-2">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{AI_SLOT_LABEL[p.slot] ?? p.slot}</span>
                <span className="min-w-0 break-words">{p.label}</span>
                <Badge variant={state === "em_uso" ? "secondary" : "outline"}>{STATE_LABEL[state]}</Badge>
              </div>
              <p className="text-xs text-muted-foreground">Porquê: {p.why}</p>
              {onChange && state !== "tirada" && (
                <div className="flex flex-wrap items-center gap-2">
                  {at != null && onSeek && <Button size="sm" variant="ghost" onClick={() => onSeek(at)}>Ver aos {fmtT(at)}</Button>}
                  <select aria-label={`Trocar ${AI_SLOT_LABEL[p.slot] ?? p.slot}`} className="h-8 max-w-56 rounded-md border bg-background px-2 text-xs" value=""
                    disabled={!opts.length} onChange={(e) => replace(p, e.target.value)}>
                    <option value="">{lib == null && p.slot !== "frase" ? "A carregar a biblioteca…" : opts.length ? "Trocar por…" : p.slot === "frase" ? "Sem outras frases aprovadas" : "Nada na biblioteca para trocar"}</option>
                    {opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                  <Button size="sm" variant="outline" onClick={() => remove(p)}><Trash2Icon /> Tirar</Button>
                </div>
              )}
              {onChange && state === "tirada" && p.slot !== "musica" && (
                <span className="flex items-center gap-1 text-xs text-muted-foreground"><RefreshCwIcon className="size-3" aria-hidden /> Para repor, usa Desfazer ou abre a versão 1.</span>
              )}
            </li>
          );
        })}
        {v.empty.map((e, i) => (
          <li key={`vazio-${i}`} className="flex flex-col gap-1 rounded-md border border-dashed p-2">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-medium">{AI_SLOT_LABEL[e.slot] ?? e.slot}</span>
              <Badge variant="outline">vazio</Badge>
            </div>
            <p className="text-xs text-muted-foreground">Porquê: {e.why}</p>
          </li>
        ))}
      </ul>
      {!onChange && <p className="text-xs text-muted-foreground">No modo guiado a música troca-se em baixo; para trocar ou tirar um visual, deixa uma nota no momento.</p>}
    </section>
  );
}
