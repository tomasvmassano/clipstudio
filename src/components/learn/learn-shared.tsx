"use client";

import type { ReactNode } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { isFlagOff, isForbidden } from "@/lib/learn";

export { useLoad } from "@/components/perf/perf-shared";

/** Estados de uma leitura: a carregar, sem acesso, desligado, erro com "tentar de novo". */
export function LearnState({ loading, error, reload, label, forbidden, children }: {
  loading: boolean; error: unknown; reload: () => void; label: string; forbidden: string; children: ReactNode;
}) {
  if (error) {
    if (isForbidden(error)) return <Alert><AlertDescription>{forbidden}</AlertDescription></Alert>;
    if (isFlagOff(error)) return <Alert><AlertDescription>{(error as Error).message}</AlertDescription></Alert>;
    return (
      <Alert variant="destructive" role="alert">
        <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
          <span>Não consegui carregar {label}: {(error as Error).message}</span>
          <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
        </AlertDescription>
      </Alert>
    );
  }
  if (loading) {
    return (
      <div className="flex flex-col gap-2" aria-busy="true" aria-label={`A carregar ${label}`}>
        <Skeleton className="h-20 w-full" /><Skeleton className="h-40 w-full" />
      </div>
    );
  }
  return <>{children}</>;
}

export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1 rounded-lg border p-3">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="text-xl font-semibold tabular-nums">{value}</span>
      {hint && <span className="text-xs text-muted-foreground">{hint}</span>}
    </div>
  );
}

/** Barra horizontal simples (proporção do máximo); o número vai sempre ao lado, a cor não carrega significado sozinha. */
export function Bar({ value, max, label, text }: { value: number; max: number; label: string; text?: string }) {
  const w = max > 0 ? Math.max(2, Math.round((value / max) * 100)) : 0;
  return (
    <div className="flex items-center gap-2" aria-label={label}>
      <div className="h-2 flex-1 rounded-full bg-muted"><div className="h-2 rounded-full bg-primary" style={{ width: `${w}%` }} /></div>
      {text !== "" && <span className="w-8 text-right text-xs tabular-nums">{text ?? value}</span>}
    </div>
  );
}

export const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";
