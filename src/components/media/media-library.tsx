"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { HardDriveIcon, Link2Icon, Loader2Icon, RotateCwIcon, SearchIcon, ShieldAlertIcon, SlidersHorizontalIcon, Trash2Icon, UploadIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { WidgetBoundary } from "@/components/widget-boundary";
import { useLoad } from "@/components/perf/perf-shared";
import { ConfirmDialog, KindIcon, fmtDateTime, selectCls } from "@/components/media/media-shared";
import { MediaAssetSheet } from "@/components/media/media-asset-sheet";
import { MediaPolicySheet } from "@/components/media/media-policy";
import type { Access } from "@/lib/access";
import {
  abandonUpload, addLink, errCode, fetchLibrary, purge, resumeUpload, uploadFile,
  type MediaAsset, type MediaFilters, type MediaLibrary, type MediaView, type UploadProgress,
} from "@/lib/media";
import { FORMATS, KIND_LABEL, STATUS_LABEL, bytes, kindForMime, mimeOf, pctOf, precheck, splitTags, type MediaKind } from "@/lib/media-format";

type QueueItem = {
  key: string; file: File; progress: UploadProgress; error?: string; controller: AbortController;
  assetId?: string | null; versionId?: string; fields?: Record<string, unknown>;
};

const PHASE: Record<UploadProgress["phase"], string> = {
  checksum: "a calcular o SHA-256", a_registar: "a registar", a_enviar: "a enviar", a_esperar: "à espera para tentar de novo",
  a_confirmar: "a confirmar no servidor", pronta: "pronto", falhou: "falhou", cancelado: "cancelado",
};

export function MediaLibraryView({ access }: { access: Access }) {
  const [view, setView] = useState<MediaView>("ativos");
  const [q, setQ] = useState("");
  const [qApplied, setQApplied] = useState("");
  const [filters, setFilters] = useState<MediaFilters>({});
  const key = JSON.stringify({ ws: access.ws, view, q: qApplied, filters });
  const lib = useLoad(() => fetchLibrary(access, { ...filters, view, q: qApplied }), key);
  const [opened, setOpened] = useState<string | null>(null);
  const [upOpen, setUpOpen] = useState(false);
  const [linkOpen, setLinkOpen] = useState(false);
  const [policyOpen, setPolicyOpen] = useState(false);
  const [queue, setQueue] = useState<QueueItem[]>([]);
  const d = lib.data;

  useEffect(() => { const t = setTimeout(() => setQApplied(q.trim()), 300); return () => clearTimeout(t); }, [q]);

  const patch = (k: string, p: Partial<QueueItem>) => setQueue((xs) => xs.map((x) => (x.key === k ? { ...x, ...p } : x)));
  const run = async (item: QueueItem, resume?: { versionId: string; assetId: string }) => {
    const onProgress = (p: UploadProgress) => patch(item.key, { progress: p, versionId: p.versionId ?? item.versionId, assetId: p.assetId ?? item.assetId });
    try {
      if (resume) await resumeUpload(access, resume.versionId, resume.assetId, item.file, onProgress, item.controller.signal);
      else await uploadFile(access, item.file, { assetId: item.assetId ?? null, fields: item.fields }, onProgress, item.controller.signal);
      lib.reload();
    } catch (e) {
      const aborted = (e as Error).name === "AbortError";
      patch(item.key, { error: aborted ? "Cancelado. O upload fica por concluir até desistires ou retomares." : (e as Error).message,
        progress: { ...item.progress, phase: aborted ? "cancelado" : "falhou" } });
    }
  };
  const enqueue = (files: File[], opts: { assetId?: string | null; fields?: Record<string, unknown> }) => {
    const items = files.map((file): QueueItem => ({
      key: `${file.name}-${file.size}-${Date.now()}-${Math.random()}`, file, controller: new AbortController(), assetId: opts.assetId ?? null, fields: opts.fields,
      progress: { phase: "checksum", loaded: 0, total: file.size, attempt: 0 },
    }));
    setQueue((xs) => [...items, ...xs]);
    // dois envios em paralelo no máximo
    void (async () => {
      const pending = [...items];
      const worker = async () => { for (let it = pending.shift(); it; it = pending.shift()) await run(it); };
      await Promise.all([worker(), worker()]);
    })();
  };
  const retry = (item: QueueItem) => {
    const fresh = { ...item, controller: new AbortController(), error: undefined, progress: { ...item.progress, phase: "a_registar" as const, attempt: 0 } };
    patch(item.key, fresh);
    void run(fresh, item.versionId && item.assetId ? { versionId: item.versionId, assetId: item.assetId } : undefined);
  };
  const giveUp = async (item: QueueItem) => {
    if (item.versionId) {
      try { await abandonUpload(access, item.versionId, "desisti no ecrã de envio"); }
      catch (e) { patch(item.key, { error: (e as Error).message }); return; }
    }
    setQueue((xs) => xs.filter((x) => x.key !== item.key));
    lib.reload();
  };

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Biblioteca</h1>
          <p className="text-sm text-muted-foreground">Finais, miniaturas, legendas, áudio, imagens e documentos deste cliente. O bruto das sessões fica no Google Drive: regista-o como link.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="outline" onClick={lib.reload} aria-label="Atualizar"><RotateCwIcon /> Atualizar</Button>
          {d?.can.policy && <Button size="sm" variant="outline" onClick={() => setPolicyOpen(true)}><SlidersHorizontalIcon /> Tipos e quota</Button>}
          {d?.can.upload && <Button size="sm" variant="outline" onClick={() => setLinkOpen(true)}><Link2Icon /> Registar link</Button>}
          {d?.can.upload && <Button size="sm" onClick={() => setUpOpen(true)}><UploadIcon /> Carregar ficheiros</Button>}
        </div>
      </div>

      {lib.error ? <LibraryError error={lib.error} reload={lib.reload} /> : !d ? (
        <div className="flex flex-col gap-2" aria-busy="true" aria-label="A carregar a biblioteca"><Skeleton className="h-24 w-full" /><Skeleton className="h-64 w-full" /></div>
      ) : (
        <>
          <WidgetBoundary label="Uso do armazenamento"><UsageCard d={d} /></WidgetBoundary>
          {queue.length > 0 && (
            <WidgetBoundary label="Envios">
              <UploadQueue items={queue} onRetry={retry} onCancel={(i) => i.controller.abort()} onGiveUp={(i) => void giveUp(i)}
                onClear={() => setQueue((xs) => xs.filter((x) => x.progress.phase !== "pronta"))} />
            </WidgetBoundary>
          )}
          <div className="flex flex-wrap items-center gap-2" role="tablist" aria-label="Vista">
            {(["ativos", "lixo", ...(d.can.manage ? ["orfaos"] : [])] as MediaView[]).map((v) => (
              <Button key={v} role="tab" aria-selected={view === v} size="sm" variant={view === v ? "secondary" : "ghost"} onClick={() => setView(v)}>
                {v === "ativos" ? "Ativos" : v === "lixo" ? "Lixo" : "Órfãos"}
                <span className="tabular-nums text-muted-foreground">{v === "ativos" ? d.counts.ativos : v === "lixo" ? d.counts.lixo : d.counts.orfaos ?? 0}</span>
              </Button>
            ))}
          </div>
          {view !== "orfaos" && <Filters d={d} q={q} setQ={setQ} filters={filters} setFilters={setFilters} />}
          {view === "orfaos" ? <Orphans access={access} d={d} onDone={lib.reload} /> : (
            <AssetGrid d={d} view={view} onOpen={setOpened} access={access} onChanged={lib.reload}
              onResume={(a, file) => {
                const item: QueueItem = { key: `${a.id}-${Date.now()}`, file, controller: new AbortController(), assetId: a.id, versionId: a.pending!.id,
                  progress: { phase: "a_registar", loaded: 0, total: file.size, attempt: 0 } };
                setQueue((xs) => [item, ...xs]);
                void run(item, { versionId: a.pending!.id, assetId: a.id });
              }} />
          )}
        </>
      )}
      {d && upOpen && <UploadDialog d={d} onClose={() => setUpOpen(false)} onStart={(files, fields) => { setUpOpen(false); enqueue(files, { fields }); }} />}
      {d && linkOpen && <LinkDialog access={access} d={d} onClose={() => setLinkOpen(false)} onDone={() => { setLinkOpen(false); lib.reload(); }} />}
      {d && policyOpen && <MediaPolicySheet access={access} d={d} onClose={() => setPolicyOpen(false)} onChanged={lib.reload} />}
      {(d ?? lib.last) && opened && (
        <MediaAssetSheet access={access} lib={(d ?? lib.last)!} id={opened} onClose={() => setOpened(null)} onChanged={lib.reload}
          onReplace={(assetId, file) => enqueue([file], { assetId })} />
      )}
    </div>
  );
}

function LibraryError({ error, reload }: { error: unknown; reload: () => void }) {
  const code = errCode(error);
  if (code === "42501") return <Alert><AlertDescription>Não tens acesso à biblioteca deste cliente.</AlertDescription></Alert>;
  if (code === "55000") return <Alert><AlertDescription>{(error as Error).message}</AlertDescription></Alert>;
  return (
    <Alert variant="destructive" role="alert">
      <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
        <span>Não consegui carregar a biblioteca: {(error as Error).message}</span>
        <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
      </AlertDescription>
    </Alert>
  );
}

function UsageCard({ d }: { d: MediaLibrary }) {
  const u = d.usage; const p = d.policy;
  const used = u.stored_bytes + u.reserved_bytes;
  const pct = pctOf(used, p.quota_bytes);
  return (
    <section className="flex flex-col gap-3 rounded-lg border p-3" aria-labelledby="media-usage">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 id="media-usage" className="flex items-center gap-2 text-sm font-semibold"><HardDriveIcon className="size-4" aria-hidden /> Armazenamento deste cliente</h2>
        <Badge variant="outline" className="gap-1" data-antivirus="off"><ShieldAlertIcon className="size-3" aria-hidden /> Sem antivírus</Badge>
      </div>
      <Progress value={pct} aria-label={`Uso da quota: ${pct}%`} />
      <p className="text-sm tabular-nums" data-usage>{bytes(used)} de {bytes(p.quota_bytes)} ({pct}%)</p>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-muted-foreground sm:grid-cols-4">
        <div><dt className="inline">Ativos: </dt><dd className="inline tabular-nums">{bytes(u.active_bytes)}</dd></div>
        <div><dt className="inline">No lixo: </dt><dd className="inline tabular-nums">{bytes(u.trash_bytes)}</dd></div>
        <div><dt className="inline">Órfãos: </dt><dd className="inline tabular-nums">{bytes(u.orphan_bytes)}</dd></div>
        <div><dt className="inline">Por concluir: </dt><dd className="inline tabular-nums">{bytes(u.pending_bytes)}</dd></div>
      </dl>
      <p className="text-xs text-muted-foreground">
        Máximo por ficheiro: {bytes(p.max_file_bytes)} (limite do armazenamento: {bytes(p.ceiling_bytes)}). Lixo recuperável durante {p.trash_days} dias.
        {" "}{d.antivirus.reason} {d.cost.reason}
      </p>
    </section>
  );
}

function Filters({ d, q, setQ, filters, setFilters }: {
  d: MediaLibrary; q: string; setQ: (s: string) => void; filters: MediaFilters; setFilters: (f: MediaFilters) => void;
}) {
  const set = (k: keyof MediaFilters, v: string) => setFilters({ ...filters, [k]: v || undefined });
  const any = Object.values(filters).some(Boolean) || q;
  return (
    <div className="flex flex-wrap items-center gap-2">
      <label className="relative min-w-0 flex-1 basis-48">
        <span className="sr-only">Pesquisar por título ou etiqueta</span>
        <SearchIcon className="pointer-events-none absolute top-1/2 left-2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
        <Input className="pl-8" placeholder="Pesquisar título ou etiqueta" value={q} onChange={(e) => setQ(e.target.value)} />
      </label>
      <select className={selectCls} aria-label="Tipo" value={filters.kind ?? ""} onChange={(e) => set("kind", e.target.value)}>
        <option value="">Todos os tipos</option>
        {(Object.keys(KIND_LABEL) as MediaKind[]).map((k) => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
      </select>
      <select className={selectCls} aria-label="Estado" value={filters.status ?? ""} onChange={(e) => set("status", e.target.value)}>
        <option value="">Todos os estados</option>
        {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
      </select>
      <select className={selectCls} aria-label="Formato" value={filters.format ?? ""} onChange={(e) => set("format", e.target.value)}>
        <option value="">Todos os formatos</option>
        {FORMATS.map((f) => <option key={f} value={f}>{f}</option>)}
      </select>
      <select className={selectCls} aria-label="Campanha" value={filters.project_id ?? ""} onChange={(e) => set("project_id", e.target.value)}>
        <option value="">Todas as campanhas</option>
        {d.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
      {d.tags.length > 0 && (
        <select className={selectCls} aria-label="Etiqueta" value={filters.tag ?? ""} onChange={(e) => set("tag", e.target.value)}>
          <option value="">Todas as etiquetas</option>
          {d.tags.map((t) => <option key={t} value={t}>#{t}</option>)}
        </select>
      )}
      {any && <Button size="sm" variant="ghost" onClick={() => { setFilters({}); setQ(""); }}><XIcon /> Limpar</Button>}
    </div>
  );
}

function AssetGrid({ d, view, onOpen, onResume, access, onChanged }: {
  d: MediaLibrary; view: MediaView; onOpen: (id: string) => void; onResume: (a: MediaAsset, f: File) => void; access: Access; onChanged: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [resumeFor, setResumeFor] = useState<MediaAsset | null>(null);
  const [err, setErr] = useState("");
  if (d.assets.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
        {view === "lixo" ? "O lixo está vazio." : d.total === 0 && d.counts.ativos > 0 ? "Nada corresponde a estes filtros." : "Ainda não há ativos. Carrega ficheiros ou regista um link."}
      </p>
    );
  }
  return (
    <>
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      <input ref={fileRef} type="file" className="hidden" aria-hidden tabIndex={-1} onChange={(e) => {
        const f = e.target.files?.[0]; e.target.value = "";
        if (!f || !resumeFor?.pending) return;
        if (f.size !== resumeFor.pending.size_bytes) { setErr(`Escolhe o mesmo ficheiro (${resumeFor.pending.original_name}, ${bytes(resumeFor.pending.size_bytes)}).`); return; }
        setErr(""); onResume(resumeFor, f); setResumeFor(null);
      }} />
      <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3" aria-label="Ativos">
        {d.assets.map((a) => (
          <li key={a.id} data-asset={a.id} className="flex min-w-0 flex-col gap-2 rounded-lg border p-3">
            <button type="button" className="flex min-w-0 items-start gap-3 text-left" onClick={() => onOpen(a.id)} aria-label={`Abrir ${a.title}`}>
              <span className="mt-0.5 rounded-md bg-muted p-2"><KindIcon kind={a.kind} /></span>
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate font-medium">{a.title}</span>
                <span className="text-xs text-muted-foreground">
                  {KIND_LABEL[a.kind]} · {STATUS_LABEL[a.status]}{a.format ? ` · ${a.format}` : ""}{a.project ? ` · ${a.project.name}` : ""}
                </span>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {a.current ? `v${a.current.version_no} · ${a.current.source === "link" ? "link" : bytes(a.current.size_bytes)} · ${fmtDateTime(a.current.created_at, d.timezone)}` : "sem versão pronta"}
                </span>
              </span>
            </button>
            {a.tags.length > 0 && <div className="flex flex-wrap gap-1">{a.tags.map((t) => <Badge key={t} variant="secondary">#{t}</Badge>)}</div>}
            {a.current && a.current.source === "upload" && (
              <span className="text-xs text-muted-foreground">{a.current.checksum_verified ? "SHA-256 conferido no servidor" : "SHA-256 declarado pelo browser (não conferido)"}</span>
            )}
            {view === "lixo" && <span className="text-xs text-muted-foreground">No lixo desde {fmtDateTime(a.trashed_at, d.timezone)}; recuperável até {fmtDateTime(a.purge_after, d.timezone)}.</span>}
            {!a.current && a.pending && (
              <div className="flex flex-wrap items-center gap-2 text-xs" data-pending={a.pending.id}>
                <Badge variant="outline">{a.pending.expired ? "Upload expirado" : "Upload por concluir"}</Badge>
                {a.pending.mine && !a.pending.expired && d.can.upload && (
                  <>
                    <Button size="xs" variant="outline" onClick={() => { setResumeFor(a); fileRef.current?.click(); }}>Retomar</Button>
                    <Button size="xs" variant="ghost" onClick={async () => {
                      try { await abandonUpload(access, a.pending!.id, "desisti na biblioteca"); onChanged(); } catch (e) { setErr((e as Error).message); }
                    }}>Desistir</Button>
                  </>
                )}
              </div>
            )}
          </li>
        ))}
      </ul>
      {d.total > d.assets.length && <p className="text-xs text-muted-foreground">A mostrar {d.assets.length} de {d.total}. Afina a pesquisa ou os filtros para ver os restantes.</p>}
    </>
  );
}

function UploadQueue({ items, onRetry, onCancel, onGiveUp, onClear }: {
  items: QueueItem[]; onRetry: (i: QueueItem) => void; onCancel: (i: QueueItem) => void; onGiveUp: (i: QueueItem) => void; onClear: () => void;
}) {
  return (
    <section className="flex flex-col gap-2 rounded-lg border p-3" aria-labelledby="media-queue">
      <div className="flex items-center justify-between gap-2">
        <h2 id="media-queue" className="text-sm font-semibold">Envios</h2>
        <Button size="xs" variant="ghost" onClick={onClear}>Limpar concluídos</Button>
      </div>
      <ul className="flex flex-col gap-3">
        {items.map((i) => {
          const p = i.progress;
          const done = p.phase === "pronta"; const failed = p.phase === "falhou" || p.phase === "cancelado";
          const sending = p.phase === "a_enviar";
          const pct = sending ? pctOf(p.loaded, p.total) : done ? 100 : null;
          return (
            <li key={i.key} className="flex flex-col gap-1 text-sm" data-upload={i.file.name} data-phase={p.phase}>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="min-w-0 truncate">{i.file.name} <span className="text-xs text-muted-foreground">({bytes(i.file.size)})</span></span>
                <span className="flex items-center gap-1">
                  {!done && !failed && <Button size="xs" variant="ghost" onClick={() => onCancel(i)}>Cancelar</Button>}
                  {failed && <Button size="xs" variant="outline" onClick={() => onRetry(i)}><RotateCwIcon /> Tentar de novo</Button>}
                  {failed && <Button size="xs" variant="ghost" onClick={() => onGiveUp(i)}>Desistir</Button>}
                </span>
              </div>
              <Progress value={pct} aria-label={`Envio de ${i.file.name}`} />
              <span role={failed ? "alert" : "status"} className={`text-xs ${failed ? "text-destructive" : "text-muted-foreground"}`}>
                {PHASE[p.phase]}{sending ? ` · ${pct}% (${bytes(p.loaded)} de ${bytes(p.total)})` : ""}{p.attempt > 1 ? ` · tentativa ${p.attempt}` : ""}
                {p.message && !failed ? ` · ${p.message}` : ""}{i.error ? ` · ${i.error}` : ""}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function UploadDialog({ d, onClose, onStart }: { d: MediaLibrary; onClose: () => void; onStart: (files: File[], fields: Record<string, unknown>) => void }) {
  const [files, setFiles] = useState<File[]>([]);
  const [kind, setKind] = useState<"" | MediaKind>("");
  const [project, setProject] = useState("");
  const [format, setFormat] = useState("");
  const [tags, setTags] = useState("");
  const checks = useMemo(() => files.reduce<{ errs: (string | null)[]; reserved: number }>((acc, f) => {
    // reserva acumulada: dois ficheiros que cabem sozinhos podem não caber juntos
    const err = precheck(f, d.policy, { stored_bytes: d.usage.stored_bytes, reserved_bytes: acc.reserved }, kind || undefined);
    return { errs: [...acc.errs, err], reserved: err ? acc.reserved : acc.reserved + f.size };
  }, { errs: [], reserved: d.usage.reserved_bytes }).errs, [files, kind, d]);
  const okFiles = files.filter((_, i) => !checks[i]);
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Carregar ficheiros</DialogTitle>
          <DialogDescription>Cada ficheiro vira um ativo. O SHA-256 é calculado aqui e conferido no servidor. Sem antivírus: carrega só ficheiros de confiança.</DialogDescription>
        </DialogHeader>
        <label className="flex flex-col gap-1 text-sm">Ficheiros
          <input type="file" multiple accept={d.policy.allowed_mime.join(",") + ",.srt,.vtt"} aria-label="Ficheiros"
            className="text-sm file:mr-2 file:rounded-md file:border file:bg-background file:px-2 file:py-1"
            onChange={(e) => setFiles(Array.from(e.target.files ?? []))} />
        </label>
        {files.length > 0 && (
          <ul className="flex max-h-40 flex-col gap-1 overflow-auto text-xs">
            {files.map((f, i) => (
              <li key={i} className={checks[i] ? "text-destructive" : "text-muted-foreground"}>
                {f.name} · {bytes(f.size)} · {KIND_LABEL[kind || kindForMime(mimeOf(f.name, f.type))]}{checks[i] ? ` · ${checks[i]}` : ""}
              </li>
            ))}
          </ul>
        )}
        <div className="grid gap-2 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-sm">Tipo
            <select className={selectCls} value={kind} onChange={(e) => setKind(e.target.value as MediaKind | "")}>
              <option value="">Automático (pelo ficheiro)</option>
              {(Object.keys(KIND_LABEL) as MediaKind[]).filter((k) => k !== "link_externo").map((k) => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">Campanha
            <select className={selectCls} value={project} onChange={(e) => setProject(e.target.value)}>
              <option value="">Sem campanha</option>
              {d.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">Formato
            <select className={selectCls} value={format} onChange={(e) => setFormat(e.target.value)}>
              <option value="">Sem formato</option>
              {FORMATS.map((f) => <option key={f} value={f}>{f}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">Etiquetas
            <Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="final dubai" />
          </label>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button disabled={okFiles.length === 0} onClick={() => onStart(okFiles, {
            ...(kind ? { kind } : {}), ...(project ? { project_id: project } : {}), ...(format ? { format } : {}), ...(tags.trim() ? { tags: splitTags(tags) } : {}),
          })}><UploadIcon /> Carregar {okFiles.length || ""}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function LinkDialog({ access, d, onClose, onDone }: { access: Access; d: MediaLibrary; onClose: () => void; onDone: () => void }) {
  const [url, setUrl] = useState("");
  const [title, setTitle] = useState("");
  const [project, setProject] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const save = async () => {
    setBusy(true); setErr("");
    try {
      await addLink(access, null, { url: url.trim(), ...(title.trim() ? { title: title.trim() } : {}), ...(project ? { project_id: project } : {}) });
      onDone();
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Registar link externo</DialogTitle>
          <DialogDescription>Ex.: a pasta ou o ficheiro do bruto no Google Drive. Só fica o link: nada é descarregado nem copiado.</DialogDescription>
        </DialogHeader>
        <label className="flex flex-col gap-1 text-sm">Link (https://)
          <Input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://drive.google.com/..." inputMode="url" />
        </label>
        <label className="flex flex-col gap-1 text-sm">Título
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Bruto da sessão de 28/10" />
        </label>
        <label className="flex flex-col gap-1 text-sm">Campanha
          <select className={selectCls} value={project} onChange={(e) => setProject(e.target.value)}>
            <option value="">Sem campanha</option>
            {d.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button disabled={busy || !/^https:\/\/\S+\.\S+/.test(url.trim())} onClick={() => void save()}>{busy && <Loader2Icon className="animate-spin" />} Registar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Orphans({ access, d, onDone }: { access: Access; d: MediaLibrary; onDone: () => void }) {
  const [sel, setSel] = useState<string[]>([]);
  const [confirm, setConfirm] = useState(false);
  const [msg, setMsg] = useState("");
  if (d.orphans.length === 0) return <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">Sem órfãos: não há uploads falhados nem abandonados.</p>;
  const all = sel.length === d.orphans.length;
  return (
    <section className="flex flex-col gap-2" aria-label="Órfãos">
      <p className="text-sm text-muted-foreground">Uploads que falharam ou expiraram sem confirmação. Ocupam espaço quando o objeto chegou ao armazenamento. Limpar apaga o objeto e marca a versão como apagada (o histórico fica).</p>
      <div className="flex flex-wrap items-center gap-2">
        <label className="inline-flex items-center gap-2 text-sm"><input type="checkbox" checked={all} onChange={() => setSel(all ? [] : d.orphans.map((o) => o.id))} /> Todos</label>
        <Button size="sm" variant="destructive" disabled={sel.length === 0} onClick={() => setConfirm(true)}><Trash2Icon /> Limpar {sel.length || ""}</Button>
      </div>
      {msg && <p role="status" className="text-sm">{msg}</p>}
      <ul className="flex flex-col divide-y rounded-lg border">
        {d.orphans.map((o) => (
          <li key={o.id} className="flex flex-wrap items-center gap-3 p-3 text-sm" data-orphan={o.id}>
            <input type="checkbox" aria-label={`Selecionar ${o.original_name}`} checked={sel.includes(o.id)}
              onChange={() => setSel((s) => (s.includes(o.id) ? s.filter((x) => x !== o.id) : [...s, o.id]))} />
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate">{o.asset_title} · v{o.version_no} · {o.original_name}</span>
              <span className="text-xs text-muted-foreground">
                {o.state === "falhou" ? `falhou: ${o.failed_reason ?? "sem motivo"}` : "expirou sem confirmação"} · {o.uploaded_label ?? "?"} · {fmtDateTime(o.created_at, d.timezone)}
                {" · "}{o.object_exists ? `ocupa ${bytes(o.size_bytes)}` : "sem objeto guardado"}
              </span>
            </span>
          </li>
        ))}
      </ul>
      <ConfirmDialog open={confirm} typed title="Limpar órfãos" confirmLabel="Apagar definitivamente"
        description={`Vais apagar ${sel.length} objeto(s) do armazenamento. Não há volta atrás.`}
        onCancel={() => setConfirm(false)}
        onConfirm={async (typed) => {
          const r = await purge(access, "orfaos", sel, typed);
          setConfirm(false); setSel([]);
          setMsg(`${r.versions_deleted} versão(ões) apagada(s).${r.remaining.length ? ` ${r.remaining.length} ainda no armazenamento: tenta de novo.` : ""}${r.storage_error ? ` Erro do armazenamento: ${r.storage_error}` : ""}`);
          onDone();
        }} />
    </section>
  );
}
