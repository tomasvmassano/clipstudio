"use client";

import { useCallback, useEffect, useState, type ReactNode } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { isForbidden } from "@/lib/perf";
import { fmtIdx, idxTone } from "@/lib/perf-format";
import { cn } from "@/lib/utils";

/** Carrega dados de uma RPC com estado de erro e "tentar de novo". `key` muda quando os parâmetros mudam. */
export function useLoad<T>(load: () => Promise<T>, key: string) {
  const [state, setState] = useState<{ key: string; data: T | null; error: unknown }>({ key: "", data: null, error: null });
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let alive = true;
    load().then((data) => { if (alive) setState({ key, data, error: null }); })
      .catch((error: unknown) => { if (alive) setState({ key, data: null, error }); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, attempt]);
  const reload = useCallback(() => { setState((s) => ({ ...s, key: "" })); setAttempt((n) => n + 1); }, []);
  const fresh = state.key === key;
  return { data: fresh ? state.data : null, error: fresh ? state.error : null, loading: !fresh, reload, setData: (d: T) => setState({ key, data: d, error: null }) };
}

export function LoadState({ loading, error, reload, label, children }: {
  loading: boolean; error: unknown; reload: () => void; label: string; children: ReactNode;
}) {
  if (error) {
    if (isForbidden(error)) {
      return <Alert><AlertDescription>Não tens acesso ao desempenho deste cliente.</AlertDescription></Alert>;
    }
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
        <Skeleton className="h-10 w-full" /><Skeleton className="h-24 w-full" /><Skeleton className="h-24 w-full" />
      </div>
    );
  }
  return <>{children}</>;
}

/** Índice com cor de apoio; sem valor mostra a razão (nunca zero). */
export function Idx({ value, reason, className }: { value: number | null | undefined; reason?: string; className?: string }) {
  const tone = idxTone(value);
  if (tone === "none") return <span className={cn("text-xs text-muted-foreground", className)}>{reason ?? "Sem índice"}</span>;
  return (
    <span className={cn("font-medium tabular-nums",
      tone === "strong" && "text-emerald-600 dark:text-emerald-400", tone === "weak" && "text-amber-700 dark:text-amber-400", className)}>
      {fmtIdx(value)}
    </span>
  );
}

export function OriginBadge({ origin, mode }: { origin: "sistema" | "externo"; mode?: "gravada" | "inferida" }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <Badge variant={origin === "sistema" ? "default" : "secondary"}>{origin === "sistema" ? "Sistema" : "Externo"}</Badge>
      {mode && <Badge variant="outline">{mode === "gravada" ? "Linhagem gravada" : "Linhagem inferida"}</Badge>}
    </span>
  );
}

export function Field({ id, label, children }: { id: string; label: string; children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <label htmlFor={id} className="text-xs font-medium text-muted-foreground">{label}</label>
      {children}
    </div>
  );
}

export const selectClass =
  "h-8 min-w-0 rounded-md border border-input bg-background px-2 text-sm text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring";
