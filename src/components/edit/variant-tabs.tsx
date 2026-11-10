"use client";

import Link from "next/link";
import { CheckIcon, TriangleAlertIcon } from "lucide-react";
import type { Access } from "@/lib/access";
import { clientPath } from "@/lib/ws-path";
import { variantShort, type BoardVariant } from "@/lib/edit";

/**
 * Separadores dos hooks do mesmo guião no editor (EDL-15) e o estado do corpo partilhado (EDL-14): igual em todos ou diferente
 * em quais (pelos cortes do corpo da versão gravada). Mudar de separador com alterações por gravar pede confirmação.
 */
export function VariantTabs({ access, current, variants, dirty, mode, onSync, syncing }: {
  access: Access; current: string; variants: BoardVariant[]; dirty: boolean; mode?: string | null;
  /** Igualar corpos: copia o corpo gravado deste hook para os outros (sem alterações por gravar). */
  onSync?: () => void; syncing?: boolean;
}) {
  if (variants.length < 2) return null;
  const me = variants.find((v) => v.asset_id === current);
  const diff = me ? variants.filter((v) => v.asset_id !== current && v.body_sig !== me.body_sig) : [];
  return (
    <div className="flex flex-wrap items-center gap-2" aria-label="Hooks deste guião">
      <nav className="flex flex-wrap gap-1 rounded-lg border p-1">
        {variants.map((v) => {
          const on = v.asset_id === current;
          const href = clientPath(access.ws, `/editor?asset=${v.asset_id}${mode ? `&modo=${mode}` : ""}`);
          return on ? (
            <span key={v.asset_id} aria-current="page" className="rounded-md bg-primary px-3 py-1 text-sm font-medium text-primary-foreground">{variantShort(v.variant)}</span>
          ) : (
            <Link key={v.asset_id} href={href} title={v.hook_text ?? v.title}
              onClick={(e) => { if (dirty && !window.confirm("Tens alterações por gravar neste hook. Sair sem gravar?")) e.preventDefault(); }}
              className="rounded-md px-3 py-1 text-sm hover:bg-muted">{variantShort(v.variant)}</Link>
          );
        })}
      </nav>
      {me && (diff.length === 0 ? (
        <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><CheckIcon className="size-3" aria-hidden /> Corpo igual nos {variants.length} hooks</span>
      ) : (
        <span className="inline-flex flex-wrap items-center gap-2 text-xs text-amber-600 dark:text-amber-400"><TriangleAlertIcon className="size-3" aria-hidden />
          Corpo diferente em {diff.map((v) => variantShort(v.variant)).join(", ")}
          {onSync && (
            <button type="button" disabled={dirty || syncing} onClick={onSync}
              title={dirty ? "Grava ou descarta as alterações primeiro" : `Copia o corpo deste hook para ${diff.map((v) => variantShort(v.variant)).join(", ")}`}
              className="rounded border border-current px-2 py-0.5 font-medium hover:bg-amber-500/10 disabled:opacity-50">
              {syncing ? "A igualar…" : "Igualar corpos a este"}</button>
          )}</span>
      ))}
    </div>
  );
}
