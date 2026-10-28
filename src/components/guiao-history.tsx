"use client";

import { useEffect, useState } from "react";
import { Loader2Icon, RotateCcwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { EDITORIAL_LABEL, type ContentHistory, type EditorialStatus, type Guiao } from "@/lib/types";
import type { ScriptActions } from "@/components/use-guioes";

const fmt = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Dubai" });
const KIND: Record<string, string> = { user: "", legacy_code: "código de equipa", engine: "motor", migration: "migração" };
const PROD: Record<string, string> = { recorded: "gravado", not_started: "por gravar" };
const label = (kind: string, s: string | null) => (s == null ? "início" : kind === "production" ? PROD[s] ?? s : EDITORIAL_LABEL[s as EditorialStatus] ?? s);

/** Versões imutáveis e transições de um guião (FR-02-06). Restaurar nunca apaga: cria revisão nova. */
export function HistorySheet({ g, open, onOpenChange, actions, canRestore, onError }: {
  g: Guiao; open: boolean; onOpenChange: (v: boolean) => void; actions: ScriptActions; canRestore: boolean; onError: (m: string) => void;
}) {
  const [h, setH] = useState<ContentHistory | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [rev, setRev] = useState(0);

  useEffect(() => {
    if (!open) return;
    let alive = true;
    actions.history(g.id).then((x) => { if (alive) { setH(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [open, g.id, g.lock_version, actions, rev]);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>Histórico do guião {g.n}</SheetTitle>
          <SheetDescription>Cada versão fica guardada tal como estava. Uma aprovação fica sempre presa à versão aprovada.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-4 pb-6">
          {err && (
            <p className="text-sm text-destructive">
              {err} <Button size="sm" variant="link" onClick={() => setRev((n) => n + 1)}>Tentar de novo</Button>
            </p>
          )}
          {!h && !err && <Skeleton className="h-48 w-full" />}
          {h && (
            <>
              <section className="flex flex-col gap-3">
                <h3 className="text-sm font-medium">Versões ({h.versions.length})</h3>
                {h.versions.map((v) => (
                  <article key={v.id} className="rounded-lg border p-3 text-sm">
                    <header className="mb-2 flex flex-wrap items-center gap-1.5 text-xs">
                      <b className="font-mono">v{v.version_no}</b>
                      {v.is_approved && <Badge className="bg-primary text-primary-foreground">aprovada</Badge>}
                      {v.is_current && <Badge variant="outline">em vigor</Badge>}
                      <span className="text-muted-foreground">{fmt(v.created_at)} · {[v.author, KIND[v.created_kind]].filter(Boolean).join(" · ")}</span>
                    </header>
                    <ol className="mb-1 list-inside list-decimal text-[13px] font-medium">
                      {v.hooks.map((x, i) => <li key={i}>{x.text}</li>)}
                    </ol>
                    <p className="line-clamp-4 whitespace-pre-line text-muted-foreground">{v.corpo}</p>
                    {v.cta && <p className="mt-1 text-xs">CTA: {v.cta}</p>}
                    {canRestore && !v.is_current && (
                      <Button
                        size="sm" variant="outline" className="mt-2" disabled={busy === v.id}
                        onClick={async () => {
                          setBusy(v.id);
                          try { await actions.restore(g.id, v.id, g.lock_version); setRev((n) => n + 1); }
                          catch (e) { onError((e as Error).message); }
                          finally { setBusy(null); }
                        }}
                      >
                        {busy === v.id ? <Loader2Icon className="animate-spin" /> : <RotateCcwIcon />} Usar este texto
                      </Button>
                    )}
                  </article>
                ))}
              </section>
              <section className="flex flex-col gap-2">
                <h3 className="text-sm font-medium">O que aconteceu</h3>
                <ol className="flex flex-col gap-2 border-l pl-4 text-sm">
                  {h.transitions.map((t, i) => (
                    <li key={i}>
                      <span className="font-medium">{label(t.kind, t.from)} → {label(t.kind, t.to)}</span>
                      {t.version_no != null && <span className="text-muted-foreground"> · v{t.version_no}</span>}
                      <div className="text-xs text-muted-foreground">{fmt(t.at)} · {t.actor}</div>
                      {t.reason && <div className="text-xs">“{t.reason}”</div>}
                    </li>
                  ))}
                </ol>
              </section>
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
