"use client";

import { useState } from "react";
import { CaptionsIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { fmtT, parseSeconds, wordsInRange, type EditDoc } from "@/lib/edit-doc";

/**
 * Legenda nova no cursor (W10-43): escrever o texto e a duração; as palavras entram no cursor, repartidas pela duração, e
 * passam a ser legendas como as outras (editar, mover, tirar). Pode substituir as palavras que já estão nesse intervalo.
 */
export function CaptionAdder({ doc, t, disabled, onAdd }: {
  doc: EditDoc; t: number; disabled: boolean; onAdd: (text: string, dur: number, replace: boolean) => boolean;
}) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [dur, setDur] = useState("2");
  const [replace, setReplace] = useState(false);
  const d = parseSeconds(dur);
  const valid = !!text.trim() && d != null && d >= 0.2 && d <= 30;
  const there = d != null ? wordsInRange(doc, t, d) : 0;
  const submit = () => {
    if (!valid || !onAdd(text, d!, replace)) return;
    setText(""); setReplace(false); setOpen(false);
  };
  if (!open) return <Button size="sm" variant="outline" disabled={disabled} onClick={() => setOpen(true)}><CaptionsIcon /> Legenda no cursor</Button>;
  return (
    <form className="flex w-full flex-wrap items-center gap-2 rounded-md border bg-muted/30 p-2" aria-label="Legenda nova"
      onSubmit={(e) => { e.preventDefault(); submit(); }}
      onKeyDown={(e) => { e.stopPropagation(); if (e.key === "Escape") setOpen(false); }}>
      <span className="text-xs text-muted-foreground">Aos {fmtT(t)}</span>
      <Input autoFocus className="h-8 min-w-48 flex-1" maxLength={300} placeholder="Texto da legenda" aria-label="Texto da legenda nova" value={text} onChange={(e) => setText(e.target.value)} />
      <label className="flex items-center gap-1 text-xs text-muted-foreground">durante
        <Input className="h-8 w-16" inputMode="decimal" aria-label="Duração da legenda em segundos" value={dur} onChange={(e) => setDur(e.target.value)} /> s</label>
      {there > 0 && (
        <label className="flex items-center gap-1.5 text-xs">
          <input type="checkbox" checked={replace} onChange={(e) => setReplace(e.target.checked)} />
          Substituir as {there} palavra{there === 1 ? "" : "s"} que já lá estão
        </label>
      )}
      <Button size="sm" type="submit" disabled={!valid}>Adicionar</Button>
      <Button size="sm" type="button" variant="ghost" onClick={() => setOpen(false)}>Cancelar</Button>
      {d == null || d < 0.2 || d > 30 ? <span className="w-full text-xs text-destructive">Duração entre 0,2 e 30 segundos.</span> : null}
      <span className="w-full text-xs text-muted-foreground">Fica no corte onde está o cursor (acaba no fim desse corte, no máximo). Depois corriges cada palavra na faixa Legendas.</span>
    </form>
  );
}
