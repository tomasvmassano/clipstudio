"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import {
  ArrowLeftIcon, ArrowRightIcon, ExternalLinkIcon, Loader2Icon, PauseIcon, PlayIcon, Redo2Icon, RotateCwIcon, ScissorsIcon, SaveIcon, Trash2Icon, Undo2Icon,
} from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { WorkspaceGate } from "@/components/workspace-gate";
import { FlagGate } from "@/components/flag-gate";
import type { Access } from "@/lib/access";
import { SOURCE_LABEL, fetchEdit, saveEdit, type EditState } from "@/lib/edit";
import {
  captionAt, deleteSegment, editWord, fmtT, historyOf, hookEnd, layout, moveSegment, outToSrc, problem, push, redo, setHook, spanOut,
  splitSegment, trimSegment, undo, wordsOut, type EditDoc, type History,
} from "@/lib/edit-doc";
import { variantLabel } from "@/lib/media-review";
import { clientPath } from "@/lib/ws-path";
import { cn } from "@/lib/utils";

type Sel = { kind: "seg" | "word"; id: string } | null;
const TRACK_H = 34;

export default function EditorPage() {
  return (
    <Suspense fallback={<Skeleton className="h-96 w-full" />}>
      <WorkspaceGate need="media.read">{(access) => (
        <FlagGate flag="edit.studio" ws={access.ws}><EditorLoader access={access} /></FlagGate>
      )}</WorkspaceGate>
    </Suspense>
  );
}

function EditorLoader({ access }: { access: Access }) {
  const sp = useSearchParams();
  const asset = sp.get("asset");
  const [st, setSt] = useState<EditState | null>(null);
  const [err, setErr] = useState("");
  const load = useCallback(async (version?: string | null) => {
    if (!asset) return;
    try { setSt(await fetchEdit(access, asset, version)); setErr(""); } catch (e) { setErr((e as Error).message); }
  }, [access, asset]);
  useEffect(() => { const id = setTimeout(() => void load(), 0); return () => clearTimeout(id); }, [load]);

  if (!asset) return <Alert><AlertDescription>Abre o editor a partir de um vídeo na Revisão.</AlertDescription></Alert>;
  if (err) return (
    <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{err}
      <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
  );
  if (!st) return <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar"><Skeleton className="h-10 w-80" /><Skeleton className="h-96 w-full" /></div>;
  if (!st.version) return (
    <Alert><AlertDescription className="flex flex-wrap items-center justify-between gap-2">
      Este vídeo ainda não tem documento de edição: foi registado sem o plano do render. Só os vídeos gerados pela IA abrem no editor.
      <Button size="sm" variant="outline" render={<Link href={clientPath(access.ws, `/revisao?ver=videos&asset=${asset}`)} />} nativeButton={false}>Voltar à revisão</Button>
    </AlertDescription></Alert>
  );
  return <Editor key={st.version.id} access={access} st={st} onReload={load} />;
}

function Editor({ access, st, onReload }: { access: Access; st: EditState; onReload: (v?: string | null) => Promise<void> }) {
  const v = st.version!;
  const isCurrent = v.id === st.document?.current_version_id;
  const canEdit = (st.can.timeline || st.can.guided) && isCurrent;
  const [h, setH] = useState<History>(() => historyOf(v.doc));
  const doc = h.present;
  const dirty = h.past.length > 0;
  const { segs, duration } = useMemo(() => layout(doc), [doc]);
  const words = useMemo(() => wordsOut(doc), [doc]);
  const hEnd = useMemo(() => hookEnd(doc), [doc]);
  const [tRaw, setT] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [sel, setSel] = useState<Sel>(null);
  const [pps, setPps] = useState(40);
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const idSeq = useRef(0);
  const apply = useCallback((d: EditDoc) => { if (canEdit) setH((x) => push(x, d)); }, [canEdit]);

  // relógio da pré-visualização (sem imagem até haver proxies: legendas, hook e cortes no tempo certo)
  useEffect(() => {
    if (!playing) return;
    let raf = 0; let last = performance.now();
    const tick = (now: number) => {
      setT((x) => { const n = x + (now - last) / 1000; if (n >= duration) { setPlaying(false); return duration; } return n; });
      last = now; raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, duration]);
  const t = Math.min(tRaw, duration);   // um corte tirado pode encurtar o vídeo para antes do cursor

  const segAt = useCallback((x: number) => segs.find((s) => x >= s.at && x < s.at + s.dur) ?? segs.at(-1)!, [segs]);
  const split = useCallback(() => {
    const s = sel?.kind === "seg" ? segs.find((x) => x.id === sel.id) : segAt(t);
    if (!s) return;
    idSeq.current += 1;
    apply(splitSegment(doc, s.id, t, `${s.id}-${Date.now().toString(36)}${idSeq.current}`));
  }, [apply, doc, sel, segs, segAt, t]);
  const remove = useCallback(() => {
    if (!sel) return;
    if (sel.kind === "seg") apply(deleteSegment(doc, sel.id)); else apply(editWord(doc, sel.id, { w: "" }));
    setSel(null);
  }, [apply, doc, sel]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.key === " ") { e.preventDefault(); setPlaying((p) => !p); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") { e.preventDefault(); setH((x) => (e.shiftKey ? redo(x) : undo(x))); }
      else if (e.key === "ArrowLeft") setT((x) => Math.max(0, x - (e.shiftKey ? 1 : 0.1)));
      else if (e.key === "ArrowRight") setT((x) => Math.min(duration, x + (e.shiftKey ? 1 : 0.1)));
      else if (e.key.toLowerCase() === "s" && canEdit) split();
      else if ((e.key === "Delete" || e.key === "Backspace") && canEdit) remove();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [canEdit, duration, remove, split]);

  const save = async () => {
    const why = problem(doc);
    if (why) { setMsg({ kind: "err", text: `Não dá para gravar: ${why}.` }); return; }
    setSaving(true); setMsg(null);
    try { await saveEdit(access, st.asset.id, st.document?.current_version_id ?? null, doc, note.trim() || undefined); setNote(""); await onReload(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setSaving(false); }
  };
  const restore = async () => {
    setSaving(true); setMsg(null);
    try { await saveEdit(access, st.asset.id, st.document?.current_version_id ?? null, v.doc, `restaurada a partir da v${v.version_no}`); await onReload(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); setSaving(false); }
  };

  const selSeg = sel?.kind === "seg" ? segs.find((s) => s.id === sel.id) ?? null : null;
  const selWord = sel?.kind === "word" ? doc.captions.words.find((w) => w.id === sel.id) ?? null : null;
  const caption = captionAt(doc, t);
  const width = Math.max(600, Math.ceil(duration * pps) + 40);
  const back = clientPath(access.ws, `/revisao?ver=videos&asset=${st.asset.id}`);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <Link href={back} className="text-xs text-muted-foreground hover:underline">← Revisão</Link>
          <h1 className="truncate text-2xl font-semibold tracking-tight">
            {st.guiao ? `Guião ${st.guiao.n}` : st.asset.title} · {variantLabel(st.asset.variant)}{st.asset.style ? ` · ${st.asset.style}` : ""}
          </h1>
          <p className="text-sm text-muted-foreground">
            Versão {v.version_no} ({SOURCE_LABEL[v.source]}{v.created_label ? `, ${v.created_label}` : ""}){!isCurrent && " · versão antiga, só leitura"}{dirty && " · alterações por gravar"}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Versão" className="h-9 rounded-md border bg-background px-2 text-sm" value={v.id}
            onChange={(e) => { if (!dirty || confirmDiscard()) void onReload(e.target.value); }}>
            {st.versions.map((x) => <option key={x.id} value={x.id}>v{x.version_no} · {SOURCE_LABEL[x.source]}{x.note ? ` · ${x.note}` : ""}</option>)}
          </select>
          <Button size="sm" variant="outline" disabled={!h.past.length} onClick={() => setH(undo)} aria-label="Desfazer"><Undo2Icon /></Button>
          <Button size="sm" variant="outline" disabled={!h.future.length} onClick={() => setH(redo)} aria-label="Refazer"><Redo2Icon /></Button>
          <Button size="sm" disabled title="Exportar precisa do worker alojado e do armazenamento de vídeo (R2). As versões gravadas ficam prontas para exportar.">Exportar</Button>
        </div>
      </div>

      <Alert><AlertDescription>
        Pré-visualização sem imagem até haver armazenamento de vídeo (R2): os cortes, as legendas e o hook aparecem no tempo certo; o vídeo exportado (v{st.asset.media_version_no ?? 1}) abre na Drive.
        {st.asset.drive_file_id && <a className="ml-1 inline-flex items-center gap-1 underline" href={`https://drive.google.com/file/d/${st.asset.drive_file_id}/view`} target="_blank" rel="noreferrer">Abrir na Drive <ExternalLinkIcon className="size-3" /></a>}
      </AlertDescription></Alert>
      {msg && <Alert variant={msg.kind === "err" ? "destructive" : "default"}><AlertDescription>{msg.text}</AlertDescription></Alert>}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,20rem)_1fr]">
        {/* palco 9:16 */}
        <div className="flex flex-col gap-2">
          <div className="relative mx-auto aspect-[9/16] w-full max-w-[20rem] overflow-hidden rounded-lg border bg-neutral-900" aria-label="Pré-visualização">
            <div className="absolute inset-0 flex items-center justify-center text-xs text-neutral-500">
              {(() => { const s = segAt(t); const src = outToSrc(doc, t)?.src; const cam = doc.cameras.find((c) => src != null && src >= c.s && src < c.e);
                return `${cam ? (cam.cam === "front" ? "Câmara frente" : "Câmara lado") : "Câmara"}${cam && cam.zoom !== 1 ? ` · zoom ${cam.zoom}` : ""} · corte ${segs.indexOf(s) + 1}`; })()}
            </div>
            {t < hEnd && doc.hook.text && (
              <div className="absolute inset-x-[8%] top-[11%] text-center text-[15px] font-extrabold leading-tight text-white [text-shadow:0_1px_3px_#000,0_0_2px_#000]">{doc.hook.text}</div>
            )}
            {caption && <div className="absolute inset-x-[6%] bottom-[24%] text-center text-[17px] font-black text-white [text-shadow:0_2px_4px_#000,0_0_3px_#000]">{caption}</div>}
          </div>
          <div className="flex items-center justify-center gap-2">
            <Button size="sm" variant="outline" onClick={() => setT((x) => Math.max(0, x - 1))} aria-label="Recuar 1 s"><ArrowLeftIcon /></Button>
            <Button size="sm" onClick={() => { if (t >= duration) setT(0); setPlaying((p) => !p); }} aria-label={playing ? "Pausa" : "Tocar"}>{playing ? <PauseIcon /> : <PlayIcon />}</Button>
            <Button size="sm" variant="outline" onClick={() => setT((x) => Math.min(duration, x + 1))} aria-label="Avançar 1 s"><ArrowRightIcon /></Button>
            <span className="tabular-nums text-sm text-muted-foreground">{fmtT(t)} / {fmtT(duration)}</span>
          </div>
        </div>

        {/* inspetor */}
        <div className="flex flex-col gap-3 rounded-lg border p-3 text-sm">
          <label className="flex flex-col gap-1">
            <span className="font-medium">Hook no ecrã</span>
            <Input value={doc.hook.text} disabled={!canEdit} maxLength={200} onChange={(e) => apply(setHook(doc, e.target.value))} />
          </label>
          {selSeg && (
            <div className="flex flex-col gap-2" aria-label="Corte selecionado">
              <span className="font-medium">Corte {segs.indexOf(selSeg) + 1} · {selSeg.section === "hook" ? "hook" : "corpo"} · {fmtT(selSeg.dur)}</span>
              <div className="flex flex-wrap items-center gap-2">
                <span className="w-16 text-muted-foreground">Entrada</span>
                {[-0.5, -0.1, 0.1, 0.5].map((d) => <Button key={d} size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(trimSegment(doc, selSeg.id, "in", selSeg.in + d))}>{d > 0 ? `+${d}` : d} s</Button>)}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <span className="w-16 text-muted-foreground">Saída</span>
                {[-0.5, -0.1, 0.1, 0.5].map((d) => <Button key={d} size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(trimSegment(doc, selSeg.id, "out", selSeg.out + d))}>{d > 0 ? `+${d}` : d} s</Button>)}
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(moveSegment(doc, selSeg.id, -1))}>Mover para trás</Button>
                <Button size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(moveSegment(doc, selSeg.id, 1))}>Mover para a frente</Button>
                <Button size="sm" variant="outline" disabled={!canEdit} onClick={split}><ScissorsIcon /> Dividir no cursor</Button>
                <Button size="sm" variant="destructive" disabled={!canEdit || segs.length <= 1} onClick={remove}><Trash2Icon /> Tirar corte</Button>
              </div>
            </div>
          )}
          {selWord && (
            <div className="flex flex-col gap-2" aria-label="Palavra selecionada">
              <span className="font-medium">Legenda</span>
              <Input value={selWord.w} disabled={!canEdit} maxLength={60} onChange={(e) => apply(editWord(doc, selWord.id, { w: e.target.value }))} aria-label="Texto da palavra" />
              <div className="flex flex-wrap items-center gap-2">
                {[-0.1, -0.05, 0.05, 0.1].map((d) => <Button key={d} size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(editWord(doc, selWord.id, { s: selWord.s + d, e: selWord.e + d }))}>{d > 0 ? `+${d}` : d} s</Button>)}
                <Button size="sm" variant="destructive" disabled={!canEdit} onClick={remove}><Trash2Icon /> Tirar palavra</Button>
              </div>
            </div>
          )}
          {!sel && <p className="text-muted-foreground">Clica num corte ou numa palavra na linha do tempo para a ajustar. Atalhos: Espaço tocar, ←/→ 0,1 s (Shift 1 s), S dividir, Delete tirar, Cmd+Z desfazer.</p>}
          <div className="mt-auto flex flex-col gap-2 border-t pt-3">
            {isCurrent ? (
              <>
                <Input placeholder="O que mudou (opcional)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} disabled={!canEdit} aria-label="Nota da versão" />
                <div className="flex gap-2">
                  <Button disabled={!canEdit || !dirty || saving} onClick={() => void save()}>{saving ? <Loader2Icon className="animate-spin" /> : <SaveIcon />} Gravar versão {st.versions.length + 1}</Button>
                  {dirty && <Button variant="ghost" onClick={() => setH(historyOf(v.doc))}>Descartar</Button>}
                </div>
                {!canEdit && <span className="text-xs text-muted-foreground">Não tens permissão para editar vídeos neste cliente.</span>}
              </>
            ) : (
              <Button variant="outline" disabled={saving || !(st.can.timeline || st.can.guided)} onClick={() => void restore()}>Restaurar esta versão como nova</Button>
            )}
          </div>
        </div>
      </div>

      {/* linha do tempo */}
      <div className="flex flex-col gap-2 rounded-lg border p-3">
        <div className="flex flex-wrap items-center gap-3 text-sm">
          <span className="font-medium">Linha do tempo</span>
          <label className="flex items-center gap-2 text-muted-foreground">Zoom
            <input type="range" min={15} max={200} value={pps} onChange={(e) => setPps(Number(e.target.value))} aria-label="Zoom da linha do tempo" />
          </label>
          <span className="text-xs text-muted-foreground">{segs.length} cortes · {words.length} palavras · {fmtT(duration)}</span>
        </div>
        <div className="flex">
          <div className="w-20 shrink-0 text-xs text-muted-foreground">
            {["", "Secções", "Cortes", "Câmara", "Legendas", "Visuais", "Som"].map((l, i) => <div key={i} style={{ height: i === 0 ? 20 : TRACK_H }} className="flex items-center">{l}</div>)}
          </div>
          <div className="overflow-x-auto">
            <div className="relative select-none" style={{ width }}>
              {/* régua */}
              <div className="relative h-5 cursor-pointer border-b" onClick={(e) => { const r = (e.currentTarget as HTMLDivElement).getBoundingClientRect(); setT(Math.min(duration, Math.max(0, (e.clientX - r.left) / pps))); }}>
                {Array.from({ length: Math.floor(duration) + 1 }, (_, s) => s).filter((s) => s % (pps < 30 ? 10 : pps < 80 ? 5 : 1) === 0).map((s) => (
                  <span key={s} className="absolute top-0 text-[10px] text-muted-foreground" style={{ left: s * pps }}>{fmtT(s).replace(/\.0$/, "")}</span>
                ))}
              </div>
              <Track>{segs.map((s) => <Block key={s.id} left={s.at * pps} w={s.dur * pps} className={s.section === "hook" ? "bg-amber-500/30" : "bg-sky-500/20"} label={s.section === "hook" ? "Hook" : "Corpo"} />)}</Track>
              <Track>{segs.map((s, i) => (
                <Block key={s.id} left={s.at * pps} w={s.dur * pps} label={`${i + 1}`} selected={sel?.kind === "seg" && sel.id === s.id}
                  className="bg-violet-500/30" onClick={() => setSel({ kind: "seg", id: s.id })} />
              ))}</Track>
              <Track>{doc.cameras.flatMap((c, i) => spanOut(doc, c.s, c.e).map((p, k) => (
                <Block key={`${i}-${k}`} left={p.at * pps} w={(p.end - p.at) * pps} label={c.cam === "front" ? "frente" : "lado"} className={c.cam === "front" ? "bg-emerald-500/20" : "bg-teal-500/30"} />
              )))}</Track>
              <Track>{words.map((w, i) => (
                <Block key={`${w.id}-${i}`} left={w.at * pps} w={Math.max(4, (w.end - w.at) * pps)} label={pps >= 60 ? w.w : ""} title={w.w}
                  selected={sel?.kind === "word" && sel.id === w.id} className="bg-yellow-400/40" onClick={() => setSel({ kind: "word", id: w.id })} />
              ))}</Track>
              <Track>{doc.overlays.length === 0 && <span className="px-2 text-xs text-muted-foreground">Sem visuais nesta versão</span>}</Track>
              <Track>{doc.audio.music ? <Block left={0} w={duration * pps} label={doc.audio.music.label} className="bg-pink-500/20" /> : <span className="px-2 text-xs text-muted-foreground">Só a voz (sem música nesta versão)</span>}</Track>
              {/* cursor */}
              <div className="pointer-events-none absolute top-0 bottom-0 w-px bg-red-500" style={{ left: t * pps }} aria-hidden />
            </div>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" disabled={!canEdit} onClick={split}><ScissorsIcon /> Dividir no cursor (S)</Button>
          <Badge variant="outline">{fmtT(t)}</Badge>
        </div>
      </div>
    </div>
  );
}

function confirmDiscard() {
  // sem diálogos do browser: trocar de versão com alterações por gravar descarta-as (o botão Descartar faz o mesmo)
  return true;
}

function Track({ children }: { children: React.ReactNode }) {
  return <div className="relative border-b border-dashed" style={{ height: TRACK_H }}>{children}</div>;
}

function Block({ left, w, label, className, selected, onClick, title }: {
  left: number; w: number; label: string; className?: string; selected?: boolean; onClick?: () => void; title?: string;
}) {
  const Tag = onClick ? "button" : "div";
  return (
    <Tag type={onClick ? "button" : undefined} onClick={onClick} title={title ?? label}
      className={cn("absolute top-1 bottom-1 overflow-hidden rounded-sm border border-white/10 px-1 text-left text-[10px] leading-[24px] whitespace-nowrap", className,
        selected && "ring-2 ring-primary", onClick && "cursor-pointer hover:brightness-125")}
      style={{ left, width: Math.max(2, w - 1) }}>{label}</Tag>
  );
}
