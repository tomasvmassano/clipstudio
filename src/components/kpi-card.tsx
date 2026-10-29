"use client";

import { useState } from "react";
import { InfoIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Delta, DeltaIcon, DeltaValue } from "@/components/delta";
import { LOWER_IS_BETTER, deltaPct, fmtKpi, fmtRange, type Kpi, type Period, type Widget } from "@/lib/dashboard";

/** Um KPI com comparação ao período anterior e a explicação da métrica (abre ao tocar: funciona em iPad). */
export function KpiCard({ w, k, period, extra }: { w: Pick<Widget, "key" | "label" | "description" | "snapshot">; k: Kpi | null; period: Period; extra?: string }) {
  const [open, setOpen] = useState(false);
  const d = deltaPct(k, w.snapshot);
  const lower = LOWER_IS_BETTER.has(w.key);
  return (
    <Card className="shadow-none dark:ring-0" data-widget={w.key}>
      <CardHeader className="flex flex-row items-start justify-between gap-2">
        <CardTitle className="font-normal text-muted-foreground text-xs">{w.label}</CardTitle>
        <button type="button" aria-label={`O que é: ${w.label}`} aria-expanded={open} onClick={() => setOpen(!open)}
          className="-m-2 rounded p-2 text-muted-foreground hover:text-foreground focus-visible:outline-2 focus-visible:outline-ring">
          <InfoIcon className="size-3.5" />
        </button>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        <p className="font-semibold text-2xl tabular-nums">{fmtKpi(w.key, k?.value ?? null)}</p>
        <div className="flex flex-wrap items-center gap-1 text-xs">
          {d != null && (
            <Delta value={lower ? -d : d}>
              <DeltaIcon />
              <DeltaValue />
            </Delta>
          )}
          <span className="text-muted-foreground">
            {w.snapshot ? "agora" : k?.prev == null ? "sem comparação" : `vs ${fmtKpi(w.key, k.prev)} em ${fmtRange(period.prev_from, period.prev_to)}`}
          </span>
        </div>
        {extra && <p className="text-muted-foreground text-xs">{extra}</p>}
        {open && <p className="border-t pt-2 text-muted-foreground text-xs">{w.description}</p>}
      </CardContent>
    </Card>
  );
}
