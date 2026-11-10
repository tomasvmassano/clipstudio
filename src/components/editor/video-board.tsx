"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { CheckIcon, Loader2Icon, RotateCwIcon, SearchIcon, TriangleAlertIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import type { Access } from "@/lib/access";
import { fetchBoard, variantShort, type BoardGuiao, type BoardVariant } from "@/lib/edit";
import { fetchPreviewSources, proxyUrl, requestExport } from "@/lib/edit-media";
import { virtualToSession } from "@/lib/edit-preview";
import { clientPath } from "@/lib/ws-path";

/**
 * Vídeos por guião (EDL-15, CHG-011, ADR-0081): cada guião com os seus hooks lado a lado, uma imagem do início de cada vídeo,
 * o texto do hook, a duração, a versão e o estado da exportação; abrir no editor e exportar. Mostra se o corpo é igual (EDL-14).
 */
export function VideoBoard({ access }: { access: Access }) {
  const [data, setData] = useState<BoardGuiao[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const load = useCallback(async () => {
    try { setData(await fetchBoard(access)); setErr(null); } catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => { const id = setTimeout(() => void load(), 0); return () => clearTimeout(id); }, [load]);

  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!data || !s) return data ?? [];
    return data.filter((g) => [`guião ${g.guiao?.n ?? ""}`, g.guiao?.tema ?? "", ...g.variants.flatMap((v) => [v.hook_text ?? "", v.hook_spoken ?? ""])]
      .some((x) => x.toLowerCase().includes(s)));
  }, [data, q]);

  return (
    <section className="flex flex-col gap-3" aria-labelledby="vb-title">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 id="vb-title" className="text-lg font-semibold">Vídeos por guião</h2>
          <p className="text-sm text-muted-foreground">Cada guião com os seus hooks. Editar o corpo num hook aplica-o aos outros.</p>
        </div>
        <label className="relative w-full sm:w-64">
          <SearchIcon className="pointer-events-none absolute left-2 top-2.5 size-4 text-muted-foreground" aria-hidden />
          <Input className="w-full pl-8" placeholder="Procurar guião, tema ou hook" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Procurar vídeos" />
        </label>
      </div>
      {err && (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">Não consegui carregar os vídeos: {err}
          <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      )}
      {!data && !err && <div className="grid gap-3 md:grid-cols-2"><Skeleton className="h-56" /><Skeleton className="h-56" /></div>}
      {data && shown.length === 0 && <p className="text-sm text-muted-foreground">{q ? "Nenhum guião com esse texto." : "Ainda não há vídeos com documento de edição."}</p>}
      <div className="flex flex-col gap-4">
        {shown.map((g) => <GuiaoCard key={g.content_id} access={access} g={g} onChanged={load} />)}
      </div>
    </section>
  );
}

function GuiaoCard({ access, g, onChanged }: { access: Access; g: BoardGuiao; onChanged: () => void }) {
  const sigs = new Set(g.variants.map((v) => v.body_sig));
  return (
    <article className="flex flex-col gap-3 rounded-lg border p-3" aria-label={`Guião ${g.guiao?.n ?? ""}`}>
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="font-medium">
          Guião {g.guiao?.n ?? "?"}{g.guiao?.date ? ` · ${new Date(g.guiao.date).toLocaleDateString("pt-PT", { day: "2-digit", month: "2-digit" })}` : ""}
          {g.guiao?.tema ? <span className="text-muted-foreground"> · {g.guiao.tema}</span> : null}
        </h3>
        {g.variants.length > 1 && (sigs.size === 1 ? (
          <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><CheckIcon className="size-3" aria-hidden /> Corpo igual nos {g.variants.length} hooks</span>
        ) : (
          <span className="inline-flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400"><TriangleAlertIcon className="size-3" aria-hidden /> Corpos diferentes</span>
        ))}
      </header>
      <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {g.variants.map((v) => <VariantTile key={v.asset_id} access={access} v={v} onChanged={onChanged} />)}
      </ul>
    </article>
  );
}

const fmtDur = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

function exportBadge(v: BoardVariant): { text: string; tone: "ok" | "warn" | "muted" | "err" } {
  const x = v.export;
  if (!x) return { text: "Por exportar", tone: "muted" };
  if (x.status === "queued" || x.status === "running") return { text: "A exportar", tone: "muted" };
  if (x.status === "done") return x.current ? { text: `Exportado v${v.version_no}`, tone: "ok" } : { text: "Exportado (versão anterior)", tone: "warn" };
  if (x.status === "cancelled") return { text: "Exportação cancelada", tone: "muted" };
  return { text: "Exportação falhou", tone: "err" };
}

function VariantTile({ access, v, onChanged }: { access: Access; v: BoardVariant; onChanged: () => void }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const b = exportBadge(v);
  const exportNow = async () => {
    setBusy(true); setMsg(null);
    try { await requestExport(access, v.asset_id, v.version_id); onChanged(); } catch (e) { setMsg((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <li className="flex min-w-0 gap-3 rounded-md border p-2">
      <Link href={clientPath(access.ws, `/editor?asset=${v.asset_id}`)} className="shrink-0" aria-label={`Abrir ${variantShort(v.variant)} no editor`}>
        <Thumb access={access} v={v} />
      </Link>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <div className="flex flex-wrap items-center gap-1">
          <span className="text-sm font-medium">{variantShort(v.variant)}</span>
          {v.style && <Badge variant="outline">{v.style}</Badge>}
          <span className="text-xs text-muted-foreground tabular-nums">{fmtDur(v.duration)} · v{v.version_no}</span>
        </div>
        {v.hook_spoken ? <p className="line-clamp-3 text-sm" title="O que se diz no hook">“{v.hook_spoken}”</p> : null}
        <p className={v.hook_spoken ? "line-clamp-1 text-xs text-muted-foreground" : "line-clamp-3 text-sm"} title="Texto no ecrã">
          {v.hook_text || <span className="text-muted-foreground">sem texto de hook</span>}</p>
        <span className={b.tone === "ok" ? "text-xs text-emerald-600 dark:text-emerald-400" : b.tone === "warn" ? "text-xs text-amber-600 dark:text-amber-400"
          : b.tone === "err" ? "text-xs text-destructive" : "text-xs text-muted-foreground"}>{b.text}</span>
        <div className="mt-auto flex flex-wrap gap-2 pt-1">
          <Button size="xs" render={<Link href={clientPath(access.ws, `/editor?asset=${v.asset_id}`)} />} nativeButton={false}>Abrir</Button>
          {!(v.export?.current && ["done", "queued", "running"].includes(v.export.status)) && (
            <Button size="xs" variant="outline" disabled={busy} onClick={() => void exportNow()}>{busy ? <Loader2Icon className="animate-spin" /> : null} Exportar</Button>
          )}
        </div>
        {msg && <span className="text-xs text-destructive" role="status">{msg}</span>}
      </div>
    </li>
  );
}

/* Imagem do início de cada vídeo: a versão leve da câmara no instante do primeiro corte, só quando o cartão aparece no ecrã. */
const camUrls = new Map<string, Promise<string | null>>();

function camUrl(access: Access, asset: string, cam: string): Promise<string | null> {
  const k = `${access.ws}:${cam}`;
  if (!camUrls.has(k)) {
    camUrls.set(k, (async () => {
      const s = await fetchPreviewSources(access, asset);
      const c = s.cams[cam];
      if (!c || c.state !== "pronta" || !c.version_id) return null;
      return (await proxyUrl(access, c.version_id, true)).url;   // soft: sem armazenamento, sem imagem (sem erro)
    })().catch(() => { camUrls.delete(k); return null; }));
  }
  return camUrls.get(k)!;
}

function Thumb({ access, v }: { access: Access; v: BoardVariant }) {
  const ref = useRef<HTMLDivElement>(null);
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const cams = v.source.cams ? Object.keys(v.source.cams) : [];
  const cam = cams.includes("front") ? "front" : cams[0];
  const camName = cam ? v.source.cams?.[cam] : null;
  useEffect(() => {
    const el = ref.current;
    if (!el || !cam || v.first_in == null || !camName) return;
    let live = true;
    const io = new IntersectionObserver(async (es) => {
      if (!es.some((e) => e.isIntersecting)) return;
      io.disconnect();
      const url = await camUrl(access, v.asset_id, cam);
      if (!live) return;
      if (!url) { setFailed(true); return; }
      const t = Math.max(0, virtualToSession(v.source.windows, (v.first_in ?? 0) + 0.6) + (Number(v.source.offsets?.[cam]) || 0));
      setSrc(`${url}#t=${t.toFixed(2)}`);
    }, { rootMargin: "200px" });
    io.observe(el);
    return () => { live = false; io.disconnect(); };
  }, [access, v.asset_id, v.first_in, v.source.windows, v.source.offsets, cam, camName]);
  return (
    <div ref={ref} className="relative h-36 w-20 overflow-hidden rounded bg-neutral-900">
      {src && !failed ? (
        <video src={src} muted playsInline preload="metadata" className="h-full w-full object-cover" onError={() => setFailed(true)} aria-hidden
          onLoadedMetadata={(e) => { const t = Number(src.split("#t=")[1]); if (Number.isFinite(t)) e.currentTarget.currentTime = t; }} />
      ) : (
        <span className="absolute inset-0 flex items-center justify-center p-1 text-center text-[10px] text-neutral-400">{failed ? "sem imagem" : "…"}</span>
      )}
    </div>
  );
}
