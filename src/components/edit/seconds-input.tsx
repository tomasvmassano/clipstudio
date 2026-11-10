"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { parseSeconds } from "@/lib/edit-doc";

/**
 * Campo de segundos que se pode apagar e reescrever (W10-40): grava ao carregar Enter ou ao sair do campo, aceita vírgula e,
 * se o valor não servir, volta ao anterior. Um passo de anular por alteração, não um por tecla.
 */
export function SecondsInput({ value, onCommit, min = 0.1, max = 60, disabled, label }: {
  value: number; onCommit: (v: number) => void; min?: number; max?: number; disabled?: boolean; label: string;
}) {
  const shown = String(Math.round(value * 10) / 10).replace(".", ",");
  const [draft, setDraft] = useState<string | null>(null);
  const commit = () => {
    if (draft == null) return;
    const v = parseSeconds(draft);
    setDraft(null);
    if (v != null) onCommit(Math.min(max, Math.max(min, v)));
  };
  return (
    <Input type="text" inputMode="decimal" className="h-8 w-20" disabled={disabled} aria-label={label}
      value={draft ?? shown}
      onFocus={(e) => e.currentTarget.select()}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") { e.preventDefault(); commit(); }
        else if (e.key === "Escape") { e.preventDefault(); setDraft(null); }
        e.stopPropagation();   // as teclas do editor (espaço, setas, Delete) não disparam enquanto se escreve
      }} />
  );
}
