"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { DownloadIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { EXPORT_STATUS, downloadUrl, fetchExportsFeed, type ExportItem, type ExportsFeed } from "@/lib/edit-media";
import { dayLabel, durText, exportDay, exportName, sizeText } from "@/lib/exports-format";
import { clientPath } from "@/lib/ws-path";

/*
 * Exportados (W10-44, EDL-11): todos os vídeos exportados do cliente num só sítio, por dia, para a equipa descarregar e
 * publicar logo. Ver: media.read com a biblioteca ligada. Descarregar: media.download (link de 2 min, auditado).
 * Os que ainda estão a exportar aparecem com o progresso; os que falharam com o motivo e o caminho para o editor.
 */

export default function ExportadosPage() {
  return (
    <Suspense fallback={null}>
      <WorkspaceGate need="media.read">
        {(access) => <FlagGate flag="media.library" ws={access.ws}><Exportados access={access} /></FlagGate>}
      </WorkspaceGate>
    </Suspense>
  );
}

const FAILED = new Set(["failed", "dead"]);
const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));

function Exportados({ access }: { access: Access }) {
  const [feed, setFeed] = useState<ExportsFeed | null>(null);
  const [err, setErr] = useState("");
  const [days, setDays] = useState(14);
  const [onlyLatest, setOnlyLatest] = useState(true);
  const [q, setQ] = useState("");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);

  const load = useCallback(async () => {
    try { setFeed(await fetchExportsFeed(access, days)); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access, days]);
  useEffect(() => {
    let alive = true;
    fetchExportsFeed(access, days).then((f) => { if (alive) { setFeed(f); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, days]);
  // enquanto houver vídeos a exportar, atualiza a cada 15 s
  const active = !!feed?.items.some((i) => i.status === "queued" || i.status === "running");
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => { void load(); }, 15000);
    return () => clearInterval(id);
  }, [active, load]);

  const tz = feed?.timezone ?? null;
  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return (feed?.items ?? []).filter((i) => (i.status !== "done" || !onlyLatest || i.latest)
      && (!s || [exportName(i), i.title, i.content?.tema ?? ""].some((x) => x.toLowerCase().includes(s))));
  }, [feed, onlyLatest, q]);
  const groups = useMemo(() => {
    const m = new Map<string, ExportItem[]>();
    for (const i of shown) { const d = exportDay(i, tz); m.set(d, [...(m.get(d) ?? []), i]); }
    return [...m.entries()];
  }, [shown, tz]);
  const today = exportDay({ title: "", tags: [], content: null, style: null, version_no: null, finished_at: new Date().toISOString(), created_at: "" }, tz);
  const ready = shown.filter((i) => i.status === "done" && i.version_id);

  const download = async (i: ExportItem) => {
    if (!i.version_id) return;
    const url = await downloadUrl(access, i.version_id, exportName(i));
    const a = document.createElement("a");
    a.href = url; a.rel = "noopener"; a.download = "";
    document.body.appendChild(a); a.click(); a.remove();
  };
  const one = async (i: ExportItem) => {
    setBusy(i.job_id); setMsg(null);
    try { await download(i); } catch (e) { setMsg({ kind: "err", text: (e as Error).message }); } finally { setBusy(null); }
  };
  const many = async () => {
    const list = ready.filter((i) => picked.has(i.job_id));
    setBusy("many"); setMsg(null);
    let done = 0;
    try {
      for (const i of list) { await download(i); done += 1; await pause(800); }
      setMsg({ kind: "ok", text: `${done} vídeo${done === 1 ? "" : "s"} a descarregar. Se o browser perguntar, permite vários downloads deste site.` });
      setPicked(new Set());
    } catch (e) {
      setMsg({ kind: "err", text: `Descarreguei ${done} de ${list.length}. ${(e as Error).message}` });
    } finally { setBusy(null); }
  };
  const toggle = (id: string) => setPicked((p) => { const n = new Set(p); if (n.has(id)) n.delete(id); else n.add(id); return n; });

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Exportados</h1>
          <p className="text-sm text-muted-foreground">Os vídeos exportados deste cliente, por dia, prontos a descarregar e publicar. Os que ainda estão a exportar aparecem aqui com o progresso.</p>
        </div>
        <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Atualizar</Button>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Input className="h-8 w-56" placeholder="Procurar (guião, tema, hook)" aria-label="Procurar exportados" value={q} onChange={(e) => setQ(e.target.value)} />
        <label className="flex items-center gap-1.5"><input type="checkbox" checked={onlyLatest} onChange={(e) => setOnlyLatest(e.target.checked)} /> Só a versão mais recente de cada vídeo</label>
        <select aria-label="Período" className="h-8 rounded-md border bg-background px-2 text-xs" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          {[7, 14, 30, 90].map((d) => <option key={d} value={d}>Últimos {d} dias</option>)}
        </select>
        {feed?.can_download && ready.length > 0 && (
          <span className="flex flex-wrap items-center gap-2">
            <Button size="sm" variant="ghost" onClick={() => setPicked(new Set(picked.size === ready.length ? [] : ready.map((i) => i.job_id)))}>
              {picked.size === ready.length ? "Tirar a seleção" : `Selecionar todos (${ready.length})`}
            </Button>
            <Button size="sm" disabled={!picked.size || !!busy} onClick={() => void many()}>
              {busy === "many" ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Descarregar {picked.size || ""} selecionado{picked.size === 1 ? "" : "s"}
            </Button>
          </span>
        )}
      </div>

      {feed && !feed.can_download && <Alert><AlertDescription>Podes ver os exportados, mas descarregar precisa da permissão de descarregar da Biblioteca. Pede a quem gere a equipa.</AlertDescription></Alert>}
      {msg && <Alert variant={msg.kind === "err" ? "destructive" : "default"}><AlertDescription>{msg.text}</AlertDescription></Alert>}
      {err && <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">{err}<Button size="sm" variant="outline" onClick={() => void load()}>Tentar de novo</Button></AlertDescription></Alert>}
      {!feed && !err && <div className="flex flex-col gap-2" aria-busy="true"><Skeleton className="h-16" /><Skeleton className="h-16" /><Skeleton className="h-16" /></div>}
      {feed && groups.length === 0 && (
        <p className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">
          {q ? "Nenhum exportado com esse nome." : `Nenhum vídeo exportado nos últimos ${feed.days} dias. Exporta no editor ou em "Exportar todos" na Edição automática.`}
        </p>
      )}

      {groups.map(([day, items]) => (
        <section key={day} aria-label={dayLabel(day, today, tz)} className="flex flex-col gap-2">
          <h2 className="text-sm font-medium text-muted-foreground">{dayLabel(day, today, tz)} · {items.length}</h2>
          <ul className="flex flex-col gap-1.5">
            {items.map((i) => {
              const name = exportName(i);
              const isDone = i.status === "done" && !!i.version_id;
              return (
                <li key={i.job_id} data-export={i.job_id} className="flex flex-wrap items-center gap-3 rounded-lg border px-3 py-2">
                  {feed?.can_download && isDone && (
                    <input type="checkbox" aria-label={`Selecionar ${name}`} checked={picked.has(i.job_id)} onChange={() => toggle(i.job_id)} />
                  )}
                  <div className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate font-medium">{name}</span>
                    <span className="truncate text-xs text-muted-foreground">
                      {[i.content?.tema, durText(i.duration), sizeText(i.size_bytes),
                        i.finished_at ? new Intl.DateTimeFormat("pt-PT", { timeZone: tz || "Asia/Dubai", hour: "2-digit", minute: "2-digit" }).format(new Date(i.finished_at)) : null,
                        i.created_label].filter(Boolean).join(" · ")}
                    </span>
                    {FAILED.has(i.status) && <span className="text-xs text-destructive">Falhou: {i.last_error ?? "sem motivo registado"}. Abre no editor e exporta outra vez.</span>}
                  </div>
                  {!isDone && !FAILED.has(i.status) && (
                    <Badge variant="secondary" className="gap-1"><Loader2Icon className="size-3 animate-spin" />{EXPORT_STATUS[i.status]}{i.progress?.pct != null ? ` ${Math.round(i.progress.pct)}%` : ""}</Badge>
                  )}
                  {isDone && !i.latest && <Badge variant="outline">versão anterior</Badge>}
                  <Button size="sm" variant="ghost" render={<Link href={clientPath(access.ws, `/editor?asset=${i.asset_id}`)} />} nativeButton={false}>Editor</Button>
                  {isDone && <Button size="sm" variant="ghost" render={<Link href={clientPath(access.ws, `/revisao?ver=videos&asset=${i.asset_id}`)} />} nativeButton={false}>Revisão</Button>}
                  {isDone && feed?.can_download && (
                    <Button size="sm" disabled={!!busy} onClick={() => void one(i)}>
                      {busy === i.job_id ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Descarregar
                    </Button>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}
