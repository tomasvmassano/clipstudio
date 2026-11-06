"use client";

import { useEffect, useState } from "react";
import { GitCompareIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EDITORIAL_LABEL, type ContentHistory, type EditorialStatus, type Guiao } from "@/lib/types";
import { recordedVersionNo } from "@/lib/version-diff";
import { VersionCompare } from "@/components/guiao-diff";
import type { ScriptActions } from "@/components/use-guioes";

const fmt = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Dubai" });
const KIND: Record<string, string> = { user: "", legacy_code: "código de equipa", engine: "motor", migration: "migração" };
const PROD: Record<string, string> = { recorded: "gravado", not_started: "por gravar" };
const label = (kind: string, s: string | null) => (s == null ? "início" : kind === "production" ? PROD[s] ?? s : EDITORIAL_LABEL[s as EditorialStatus] ?? s);

/** Versões imutáveis, comparação e transições de um guião (FR-02-06, FR-05-06, FR-05-07). Restaurar nunca apaga. */
export function HistorySheet({ g, open, onOpenChange, actions, canRestore, onError }: {
  g: Guiao; open: boolean; onOpenChange: (v: boolean) => void; actions: ScriptActions; canRestore: boolean; onError: (m: string) => void;
}) {
  const [h, setH] = useState<ContentHistory | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [rev, setRev] = useState(0);
  const [tab, setTab] = useState<"versions" | "compare">("versions");
  const [from, setFrom] = useState<string | null>(null);
  const [done, setDone] = useState("");

  useEffect(() => {
    if (!open) return;
    let alive = true;
    actions.history(g.id).then((x) => { if (alive) { setH(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [open, g.id, g.lock_version, actions, rev]);

  const restore = async (versionId: string) => {
    setBusy(versionId); setDone("");
    try {
      await actions.restore(g.id, versionId, g.lock_version);
      const v = h?.versions.find((x) => x.id === versionId);
      setDone(`O texto de v${v?.version_no ?? "?"} está agora na cópia de trabalho.`);
      setRev((n) => n + 1);
      return true;
    } catch (e) {
      const code = (e as { code?: string }).code;
      onError(code === "PT409" ? "Alguém mudou este guião entretanto. Recarreguei: revê a comparação e tenta de novo." : (e as Error).message);
      setRev((n) => n + 1);
      return false;
    } finally { setBusy(null); }
  };

  const recNo = h ? (h.versions.find((v) => v.is_recorded)?.version_no ?? (h.recorded_version_id === undefined ? recordedVersionNo(h.transitions) : null)) : null;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-2xl lg:max-w-4xl">
        <SheetHeader>
          <SheetTitle>Histórico do guião {g.n}</SheetTitle>
          <SheetDescription>Cada versão fica guardada tal como estava. Uma aprovação fica sempre presa à versão aprovada.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6">
          {err && (
            <p className="text-sm text-destructive" role="alert">
              {err} <Button size="sm" variant="link" onClick={() => setRev((n) => n + 1)}>Tentar de novo</Button>
            </p>
          )}
          {done && <p className="text-sm" role="status">{done}</p>}
          {!h && !err && <Skeleton className="h-48 w-full" />}
          {h && (
            <Tabs value={tab} onValueChange={(x) => setTab(String(x) as "versions" | "compare")}>
              <TabsList>
                <TabsTrigger value="versions">Versões ({h.versions.length})</TabsTrigger>
                <TabsTrigger value="compare">Comparar</TabsTrigger>
              </TabsList>
              <TabsContent value="versions" className="flex flex-col gap-6 pt-2">
                <section className="flex flex-col gap-3" aria-label="Versões">
                  {h.versions.map((v) => {
                    const why = h.transitions.filter((t) => t.version_no === v.version_no);
                    const restored = (h.restores ?? []).filter((r) => r.version_no === v.version_no);
                    return (
                      <article key={v.id} className="rounded-lg border p-3 text-sm" data-version={v.version_no}>
                        <header className="mb-2 flex flex-wrap items-center gap-1.5 text-xs">
                          <b className="font-mono">v{v.version_no}</b>
                          {v.is_approved && <Badge className="bg-primary text-primary-foreground">aprovada</Badge>}
                          {v.version_no === recNo && <Badge variant="secondary">gravada</Badge>}
                          {v.is_current && <Badge variant="outline">em vigor</Badge>}
                          <span className="text-muted-foreground">{fmt(v.created_at)} · {[v.author, KIND[v.created_kind]].filter(Boolean).join(" · ") || "autor desconhecido"}</span>
                        </header>
                        <ol className="mb-1 list-inside list-decimal text-[13px] font-medium">
                          {v.hooks.map((x, i) => <li key={i}>{x.text}</li>)}
                        </ol>
                        <p className="line-clamp-4 whitespace-pre-line text-muted-foreground">{v.corpo}</p>
                        {v.cta && <p className="mt-1 text-xs">CTA: {v.cta}</p>}
                        {(why.length > 0 || restored.length > 0) && (
                          <ul className="mt-2 flex flex-col gap-0.5 border-t pt-2 text-xs text-muted-foreground" aria-label={`O que aconteceu com v${v.version_no}`}>
                            {why.map((t, i) => (
                              <li key={`t${i}`}>
                                {label(t.kind, t.from)} → {label(t.kind, t.to)} · {fmt(t.at)}{t.actor ? ` · ${t.actor}` : ""}
                                {t.reason && <span className="text-foreground"> · “{t.reason}”</span>}
                              </li>
                            ))}
                            {restored.map((r, i) => <li key={`r${i}`}>restaurada · {fmt(r.at)}{r.actor ? ` · ${r.actor}` : ""}</li>)}
                          </ul>
                        )}
                        {h.versions.length > 1 && (
                          <Button size="sm" variant="outline" className="mt-2" onClick={() => { setFrom(v.id); setTab("compare"); }}>
                            <GitCompareIcon /> Comparar
                          </Button>
                        )}
                      </article>
                    );
                  })}
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
              </TabsContent>
              <TabsContent value="compare" className="pt-2">
                <VersionCompare key={from ?? "default"} g={g} h={h} canRestore={canRestore} busy={busy} onRestore={restore} initialFrom={from} />
              </TabsContent>
            </Tabs>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
