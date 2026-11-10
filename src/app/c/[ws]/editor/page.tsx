"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import {
  ArrowLeftIcon, ArrowRightIcon, ExternalLinkIcon, ImagePlusIcon, Loader2Icon, PauseIcon, PlayIcon, Redo2Icon, RotateCwIcon, ScissorsIcon, SaveIcon, Trash2Icon, Undo2Icon,
} from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { WorkspaceGate } from "@/components/workspace-gate";
import { FlagGate } from "@/components/flag-gate";
import type { Access } from "@/lib/access";
import { SOURCE_LABEL, fetchBoard, fetchEdit, saveEdit, variantShort, type BoardVariant, type EditState } from "@/lib/edit";
import { applyBodyToSiblings, bodySummary, flashBody, takeBodyFlash } from "@/lib/body-share-client";
import { applyFramingToVideos, framingSummary, videosWithFile } from "@/lib/framing-client";
import { ImagePicker } from "@/components/edit/image-picker";
import { mediaUrl } from "@/lib/edit-media";
import { captionStates } from "@/lib/caption-plan";
import { VariantTabs } from "@/components/edit/variant-tabs";
import { fetchLibrary, type MediaAsset } from "@/lib/media";
import { useSession } from "@/components/session-provider";
import {
  addNote, addOverlay, clearGain, deleteSegment, editWord, fmtT, historyOf, layout, moveSegment, notesOut, problem, push, redo,
  removeNote, removeOverlay, resizeOverlay, setGain, setHook, setMusic, setMusicDb, shiftOverlay, shiftWord, spanOut, splitSegment, toggleNote, trimSegment, undo,
  camAt, setCam, splitCamAt, frameAllCam, outToSrc, srcToOut, CAM_ANCHOR, ZOOM_LIMITS,
  wordsOut, BOX_PRESETS, boxPreset, setOverlayBox, type EditDoc, type History,
} from "@/lib/edit-doc";
import { useFlags } from "@/lib/flags";
import { AiVisualsPanel } from "@/components/edit/ai-visuals";
import { ClipOrderView } from "@/components/edit/clip-order-view";
import { WidgetBoundary } from "@/components/widget-boundary";
import { variantLabel } from "@/lib/media-review";
import { clientPath } from "@/lib/ws-path";
import { cn } from "@/lib/utils";
import { EditorStage, type StageGuides } from "@/components/edit/editor-stage";
import { ExportPanel } from "@/components/editor/export-panel";
import { PreviewVideo } from "@/components/editor/preview-video";
import { GuidedEditor } from "@/components/edit/guided-editor";
import { LookPanel, SavedStylesPanel } from "@/components/edit/style-tools";

type Sel = { kind: "seg" | "word" | "ov" | "note" | "cam"; id: string } | null;
type DragKind = "seg-in" | "seg-out" | "word" | "ov" | "ov-s" | "ov-e";
type Drag = { kind: DragKind; id: string; x0: number; base: EditDoc; doc: EditDoc };
const EDITABLE_KINDS = new Set(["video", "imagem", "thumbnail", "link_externo"]);
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
  // modo guiado (EDL-10): quem só tem edit.guided; quem tem a linha do tempo pode abrir a vista guiada com ?modo=guiado
  if (!st.can.timeline || sp.get("modo") === "guiado") return <GuidedEditor key={st.version.id} access={access} st={st} onReload={load} />;
  return <Editor key={st.version.id} access={access} st={st} onReload={load} />;
}

function Editor({ access, st, onReload }: { access: Access; st: EditState; onReload: (v?: string | null) => Promise<void> }) {
  const v = st.version!;
  const isCurrent = v.id === st.document?.current_version_id;
  const canEdit = st.can.timeline && isCurrent;   // sem edit.timeline abre o modo guiado (GuidedEditor)
  const [h, setH] = useState<History>(() => historyOf(v.doc));
  const [drag, setDrag] = useState<Drag | null>(null);
  const doc = drag?.doc ?? h.present;      // enquanto se arrasta mostra o resultado; ao largar entra no histórico
  const { label: me } = useSession();
  const flags = useFlags(access.ws, access.token);
  const canPlace = !!flags?.has("edit.ai_visuals");   // posição por visual (ADR-0068), atrás da flag
  const [lib, setLib] = useState<MediaAsset[] | null>(null);
  const [newNote, setNewNote] = useState("");
  const noteRef = useRef<HTMLInputElement>(null);
  const dirty = h.past.length > 0;
  // hooks do mesmo guião (EDL-14/15): separadores e corpo partilhado
  const [siblings, setSiblings] = useState<BoardVariant[]>([]);
  useEffect(() => {
    if (!st.asset.content_id) return;
    let live = true;
    fetchBoard(access, st.asset.content_id, 1).then((g) => { if (live) setSiblings(g[0]?.variants ?? []); }).catch(() => { /* sem separadores: o editor continua */ });
    return () => { live = false; };
  }, [access, st.asset.content_id, st.document?.current_version_id]);
  const { segs, duration } = useMemo(() => layout(doc), [doc]);
  const words = useMemo(() => wordsOut(doc), [doc]);
  const [tRaw, setT] = useState(0);
  const [playing, setPlaying] = useState(false);
  const soundDriving = useRef(false);   // a tocar com imagem, é o som do palco que dá o tempo (W10-29)
  const [sel, setSel] = useState<Sel>(null);
  const [pps, setPps] = useState(40);
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(takeBodyFlash);   // o resultado do corpo partilhado, depois de recarregar
  const idSeq = useRef(0);
  const apply = useCallback((d: EditDoc) => { if (canEdit) setH((x) => push(x, d)); }, [canEdit]);
  const nextId = (p: string) => { idSeq.current += 1; return `${p}${Date.now().toString(36)}${idSeq.current}`; };
  // imagens da Biblioteca no palco e no seletor (W10-37): links curtos, pedidos quando fazem falta e renovados a cada 4 min
  const [assetUrls, setAssetUrls] = useState<Record<string, string>>({});
  const urlsRef = useRef<Record<string, string>>({});
  const pendingUrls = useRef(new Set<string>());
  useEffect(() => { urlsRef.current = assetUrls; }, [assetUrls]);
  const ensureUrls = useCallback((ids: string[]) => {
    for (const id of ids) {
      if (urlsRef.current[id] || pendingUrls.current.has(id)) continue;
      const vid = (lib ?? []).find((x) => x.id === id)?.current?.id;
      if (!vid) continue;
      pendingUrls.current.add(id);
      mediaUrl(access, vid).then((r) => setAssetUrls((u) => ({ ...u, [id]: r.url }))).catch(() => { /* sem imagem: fica o nome */ })
        .finally(() => pendingUrls.current.delete(id));
    }
  }, [access, lib]);
  useEffect(() => { const id = setInterval(() => setAssetUrls({}), 240_000); return () => clearInterval(id); }, []);
  const [picker, setPicker] = useState<null | { mode: "add" } | { mode: "replace"; id: string }>(null);
  const graphicIds = useMemo(() => Array.from(new Set(doc.overlays.filter((o) => o.kind === "graphic" && o.asset).map((o) => o.asset!))), [doc.overlays]);
  useEffect(() => { ensureUrls(graphicIds); }, [graphicIds, ensureUrls, assetUrls]);
  const images = useMemo(() => (lib ?? []).filter((a) => a.kind === "imagem" || a.kind === "thumbnail"), [lib]);
  const capStates = useMemo(() => captionStates(doc, duration), [doc, duration]);
  /** Segundos do instante x da saída até ao fim da frase da legenda (entre 0,5 e 8 s; fora de uma frase, 2,5 s). */
  const toPhraseEnd = useCallback((x: number) => {
    let i = -1;
    for (let k = 0; k < capStates.length; k++) if (capStates[k][0] <= x + 1e-6) i = k;
    const cur = i >= 0 ? capStates[i][1] : null;
    if (!cur) return 2.5;
    const nxt = capStates.slice(i + 1).find((st) => st[1]?.chunk !== cur.chunk);
    return Math.min(8, Math.max(0.5, (nxt ? nxt[0] : duration) - x));
  }, [capStates, duration]);

  // ficheiros da biblioteca do cliente para visuais e música (só os que dão para usar)
  useEffect(() => {
    let off = false;
    const id = setTimeout(() => {
      fetchLibrary(access, { view: "ativos", limit: 200 }).then((l) => { if (!off) setLib(l.assets); }).catch(() => { if (!off) setLib([]); });
    }, 0);
    return () => { off = true; clearTimeout(id); };
  }, [access]);

  // arrastar na linha do tempo: pontas dos cortes e dos visuais, palavras e visuais inteiros
  const startDrag = (kind: DragKind, id: string) => (e: React.PointerEvent) => {
    if (!canEdit) return;
    e.preventDefault(); e.stopPropagation();
    setDrag({ kind, id, x0: e.clientX, base: h.present, doc: h.present });
  };
  useEffect(() => {
    if (!drag) return;
    const move = (e: PointerEvent) => {
      const dx = (e.clientX - drag.x0) / pps;
      const b = drag.base;
      let d = b;
      if (drag.kind === "seg-in" || drag.kind === "seg-out") {
        const s = b.segments.find((x) => x.id === drag.id)!;
        d = drag.kind === "seg-in" ? trimSegment(b, s.id, "in", s.in + dx) : trimSegment(b, s.id, "out", s.out + dx);
      } else if (drag.kind === "word") d = shiftWord(b, drag.id, dx);
      else if (drag.kind === "ov") d = shiftOverlay(b, drag.id, dx);
      else {
        const o = b.overlays.find((x) => x.id === drag.id)!;
        d = drag.kind === "ov-s" ? resizeOverlay(b, o.id, "s", o.s + dx) : resizeOverlay(b, o.id, "e", o.e + dx);
      }
      setDrag((x) => (x ? { ...x, doc: d } : x));
    };
    const up = () => { setH((x) => (drag.doc === drag.base ? x : push(x, drag.doc))); setDrag(null); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up, { once: true });
    return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
  }, [drag, pps]);

  // relógio da pré-visualização (sem imagem até haver proxies: legendas, hook e cortes no tempo certo)
  useEffect(() => {
    if (!playing) return;
    let raf = 0; let last = performance.now();
    const tick = (now: number) => {
      if (!soundDriving.current) setT((x) => { const n = x + (now - last) / 1000; if (n >= duration) { setPlaying(false); return duration; } return n; });
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
    if (sel.kind === "seg") apply(deleteSegment(doc, sel.id));
    else if (sel.kind === "word") apply(editWord(doc, sel.id, { w: "" }));
    else if (sel.kind === "ov") apply(removeOverlay(doc, sel.id));
    else if (sel.kind === "cam") return;   // um trecho de câmara não se tira: troca-se o ângulo
    else apply(removeNote(doc, sel.id));
    setSel(null);
  }, [apply, doc, sel]);
  // câmaras à mão (W10-35): ângulos que há nas gravações deste documento
  const camNames = useMemo(() => {
    const ks = Object.keys((doc as EditDoc & { source?: { cams?: Record<string, string> } }).source?.cams ?? {});
    return ks.length ? ks : Array.from(new Set(doc.cameras.map((c) => c.cam)));
  }, [doc]);
  const camLabel = (c: string) => (c === "front" ? "Frente" : c === "side" ? "Lado" : c);
  const toggleCamAtCursor = useCallback(() => {
    const src = outToSrc(doc, t)?.src;
    if (src == null) return;
    const i = camAt(doc, src);
    if (i < 0) return;
    const next = camNames[(camNames.indexOf(doc.cameras[i].cam) + 1) % camNames.length] ?? doc.cameras[i].cam;
    apply(setCam(doc, i, { cam: next }));
    setSel({ kind: "cam", id: String(i) });
  }, [apply, camNames, doc, t]);
  const [guides, setGuides] = useState<StageGuides>(() => { try { return JSON.parse(localStorage.getItem("edit.guides") || "{}"); } catch { return {}; } });
  const toggleGuide = (k: keyof StageGuides) => setGuides((g) => {
    const n = { ...g, [k]: !g[k] };
    try { localStorage.setItem("edit.guides", JSON.stringify(n)); } catch { /* só neste dispositivo */ }
    return n;
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.key === " ") { e.preventDefault(); setPlaying((p) => !p); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") { e.preventDefault(); setH((x) => (e.shiftKey ? redo(x) : undo(x))); }
      else if (e.key === "ArrowLeft") setT((x) => Math.max(0, x - (e.shiftKey ? 1 : 0.1)));
      else if (e.key === "ArrowRight") setT((x) => Math.min(duration, x + (e.shiftKey ? 1 : 0.1)));
      else if (e.key.toLowerCase() === "s" && canEdit) split();
      else if (e.key.toLowerCase() === "c" && canEdit) toggleCamAtCursor();
      else if (e.key.toLowerCase() === "n" && canEdit) { e.preventDefault(); setPlaying(false); noteRef.current?.focus(); }
      else if ((e.key === "Delete" || e.key === "Backspace") && canEdit) remove();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [canEdit, duration, remove, split, toggleCamAtCursor]);

  const save = async () => {
    const why = problem(doc);
    if (why) { setMsg({ kind: "err", text: `Não dá para gravar: ${why}.` }); return; }
    setSaving(true); setMsg(null);
    try {
      await saveEdit(access, st.asset.id, st.document?.current_version_id ?? null, doc, note.trim() || undefined); setNote("");
      // corpo partilhado (EDL-14): o mesmo corpo nos outros hooks do guião, cada um com o seu hook
      const others = siblings.filter((x) => x.asset_id !== st.asset.id);
      if (others.length) {
        const rs = await applyBodyToSiblings(access, st.asset.id, `${variantShort(st.asset.variant)} v${st.versions.length + 1}`, doc, others);
        flashBody(bodySummary(rs));
      }
      await onReload();
    }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setSaving(false); }
  };
  const [framing, setFraming] = useState(false);
  const camFile = (cam: string) => (doc as EditDoc & { source?: { cams?: Record<string, string> } }).source?.cams?.[cam] ?? null;
  // enquadramento da gravação inteira (W10-36): este vídeo fica com o enquadramento já (por gravar) e os outros com a mesma
  // gravação recebem uma versão nova
  const frameEverywhere = async (cam: string, f: { zoom: number; x?: number; y?: number }) => {
    const file = camFile(cam);
    if (!file) return;
    setFraming(true); setMsg(null);
    try {
      const vids = await videosWithFile(access, cam, file, st.asset.id);
      if (vids.length && !window.confirm(`Pôr este zoom e posição da câmara ${camLabel(cam).toLowerCase()} em mais ${vids.length} vídeo${vids.length === 1 ? "" : "s"} com ${file}? Cada um fica com uma versão nova.`)) return;
      apply(frameAllCam(doc, cam, f));
      const rs = vids.length ? await applyFramingToVideos(access, cam, f, vids, `enquadramento de ${file} igual ao de ${variantShort(st.asset.variant)}`) : [];
      const sm = rs.length ? framingSummary(rs) : null;
      setMsg({ kind: sm?.kind ?? "ok", text: `${sm ? sm.text + " " : ""}Grava este vídeo para ficar também com este enquadramento.` });
    } catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setFraming(false); }
  };
  const [syncing, setSyncing] = useState(false);
  // Igualar corpos (EDL-14): o corpo da versão gravada deste hook vai para os outros
  const syncBodies = async () => {
    const others = siblings.filter((x) => x.asset_id !== st.asset.id);
    if (!others.length || dirty) return;
    setSyncing(true); setMsg(null);
    try { flashBody(bodySummary(await applyBodyToSiblings(access, st.asset.id, `${variantShort(st.asset.variant)} v${v.version_no}`, v.doc, others))); await onReload(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setSyncing(false); }
  };
  const restore = async () => {
    setSaving(true); setMsg(null);
    try { await saveEdit(access, st.asset.id, st.document?.current_version_id ?? null, v.doc, `restaurada a partir da v${v.version_no}`); await onReload(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); setSaving(false); }
  };

  const selSeg = sel?.kind === "seg" ? segs.find((s) => s.id === sel.id) ?? null : null;
  const selWord = sel?.kind === "word" ? doc.captions.words.find((w) => w.id === sel.id) ?? null : null;
  const selOv = sel?.kind === "ov" ? doc.overlays.find((o) => o.id === sel.id) ?? null : null;
  const selCamIdx = sel?.kind === "cam" ? Number(sel.id) : -1;
  const selCam = selCamIdx >= 0 ? doc.cameras[selCamIdx] ?? null : null;
  const notes = notesOut(doc);
  const visuals = (lib ?? []).filter((a) => EDITABLE_KINDS.has(a.kind));
  const tracks = (lib ?? []).filter((a) => a.kind === "audio");
  const width = Math.max(600, Math.ceil(duration * pps) + 40);
  const back = clientPath(access.ws, `/revisao?ver=videos&asset=${st.asset.id}`);

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <Link href={back} className="text-xs text-muted-foreground hover:underline">← Revisão</Link>
          <h1 className="truncate text-2xl font-semibold tracking-tight">
            {st.guiao ? `Guião ${st.guiao.n}` : st.asset.title} · {variantLabel(st.asset.variant)}{st.asset.style ? ` · ${st.asset.style}` : ""}
          </h1>
          <p className="text-sm text-muted-foreground">
            Versão {v.version_no} ({SOURCE_LABEL[v.source]}{v.created_label ? `, ${v.created_label}` : ""}){!isCurrent && " · versão antiga, só leitura"}{dirty && " · alterações por gravar"}
          </p>
          <div className="mt-2"><VariantTabs access={access} current={st.asset.id} variants={siblings} dirty={dirty} syncing={syncing}
            onSync={canEdit ? () => void syncBodies() : undefined} /></div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Versão" className="h-9 rounded-md border bg-background px-2 text-sm" value={v.id}
            onChange={(e) => { if (!dirty || confirmDiscard()) void onReload(e.target.value); }}>
            {st.versions.map((x) => <option key={x.id} value={x.id}>v{x.version_no} · {SOURCE_LABEL[x.source]}{x.note ? ` · ${x.note}` : ""}</option>)}
          </select>
          <Button size="sm" variant="outline" disabled={!h.past.length} onClick={() => setH(undo)} aria-label="Desfazer"><Undo2Icon /></Button>
          <Button size="sm" variant="outline" disabled={!h.future.length} onClick={() => setH(redo)} aria-label="Refazer"><Redo2Icon /></Button>
          <Button size="sm" variant="outline" render={<Link href={clientPath(access.ws, `/editor?asset=${st.asset.id}&modo=guiado`)} />} nativeButton={false}>Modo guiado</Button>
        </div>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <ExportPanel access={access} ws={access.ws} asset={st.asset.id} versionId={isCurrent ? v.id : null} versionNo={v.version_no} dirty={dirty} canExport={st.can.export} />
        {st.asset.drive_file_id && <a className="inline-flex items-center gap-1 text-sm underline" href={`https://drive.google.com/file/d/${st.asset.drive_file_id}/view`} target="_blank" rel="noreferrer">Vídeo anterior na Drive <ExternalLinkIcon className="size-3" /></a>}
      </div>
      {msg && <Alert variant={msg.kind === "err" ? "destructive" : "default"}><AlertDescription>{msg.text}</AlertDescription></Alert>}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,20rem)_1fr]">
        {/* palco 9:16 */}
        <div className="flex flex-col gap-2">
          <EditorStage doc={doc} t={t} guides={guides} assetUrls={assetUrls} media={<PreviewVideo access={access} asset={st.asset.id} versionId={v.id} doc={doc} t={t} playing={playing}
            onTime={setT} onEnd={() => setPlaying(false)} onDriving={(on) => { soundDriving.current = on; }} />} />
          <div className="flex items-center justify-center gap-2">
            <Button size="sm" variant="outline" onClick={() => setT((x) => Math.max(0, x - 1))} aria-label="Recuar 1 s"><ArrowLeftIcon /></Button>
            <Button size="sm" onClick={() => { if (t >= duration) setT(0); setPlaying((p) => !p); }} aria-label={playing ? "Pausa" : "Tocar"}>{playing ? <PauseIcon /> : <PlayIcon />}</Button>
            <Button size="sm" variant="outline" onClick={() => setT((x) => Math.min(duration, x + 1))} aria-label="Avançar 1 s"><ArrowRightIcon /></Button>
            <span className="tabular-nums text-sm text-muted-foreground">{fmtT(t)} / {fmtT(duration)}</span>
          </div>
          <div className="flex flex-wrap items-center justify-center gap-2" aria-label="Guias do palco">
            <span className="text-xs text-muted-foreground">Guias:</span>
            <Button size="xs" variant={guides.reels ? "default" : "outline"} aria-pressed={!!guides.reels} onClick={() => toggleGuide("reels")}>Zona segura Reels</Button>
            <Button size="xs" variant={guides.grid ? "default" : "outline"} aria-pressed={!!guides.grid} onClick={() => toggleGuide("grid")}>Hook · olhos · legendas</Button>
          </div>
        </div>

        {/* inspetor */}
        <div className="flex flex-col gap-3 rounded-lg border p-3 text-sm">
          <label className="flex flex-col gap-1">
            <span className="font-medium">Hook no ecrã</span>
            <Input value={doc.hook.text} disabled={!canEdit} maxLength={200} onChange={(e) => apply(setHook(doc, e.target.value))} />
          </label>
          <AiVisualsPanel doc={doc} lib={lib} onChange={canEdit ? apply : undefined} onSeek={(x) => setT(x)} />
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
          {selCam && (
            <div className="flex flex-col gap-2" aria-label="Câmara selecionada">
              <span className="font-medium">Câmara · trecho {selCamIdx + 1} de {doc.cameras.length}</span>
              <div className="flex flex-wrap items-center gap-2">
                <span className="w-16 text-muted-foreground">Ângulo</span>
                {camNames.map((c) => (
                  <Button key={c} size="sm" variant={selCam.cam === c ? "default" : "outline"} aria-pressed={selCam.cam === c} disabled={!canEdit}
                    onClick={() => apply(setCam(doc, selCamIdx, { cam: c }))}>{camLabel(c)}</Button>
                ))}
                <Button size="sm" variant="outline" disabled={!canEdit} title="Parte este trecho no cursor, para trocar só uma parte"
                  onClick={() => { const src = outToSrc(doc, t)?.src; if (src != null) apply(splitCamAt(doc, src)); }}><ScissorsIcon /> Dividir no cursor</Button>
              </div>
              <label className="flex items-center gap-2 text-xs text-muted-foreground">Zoom {selCam.zoom.toFixed(2)}×
                <input type="range" min={ZOOM_LIMITS[0]} max={ZOOM_LIMITS[1]} step={0.05} value={selCam.zoom} disabled={!canEdit} className="flex-1"
                  onChange={(e) => apply(setCam(doc, selCamIdx, { zoom: Number(e.target.value) }))} aria-label="Zoom da câmara" />
              </label>
              <label className="flex items-center gap-2 text-xs text-muted-foreground">Vertical
                <input type="range" min={0} max={1} step={0.01} value={selCam.y ?? CAM_ANCHOR.y} disabled={!canEdit || selCam.zoom <= 1.001} className="flex-1"
                  onChange={(e) => apply(setCam(doc, selCamIdx, { y: Number(e.target.value) }))} aria-label="Posição vertical" />
              </label>
              <label className="flex items-center gap-2 text-xs text-muted-foreground">Horizontal
                <input type="range" min={0} max={1} step={0.01} value={selCam.x ?? CAM_ANCHOR.x} disabled={!canEdit || selCam.zoom <= 1.001} className="flex-1"
                  onChange={(e) => apply(setCam(doc, selCamIdx, { x: Number(e.target.value) }))} aria-label="Posição horizontal" />
              </label>
              {selCam.zoom <= 1.001 && <span className="text-xs text-muted-foreground">A posição muda o enquadramento quando há zoom acima de 1×.</span>}
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" disabled={!canEdit}
                  onClick={() => apply(frameAllCam(doc, selCam.cam, { zoom: selCam.zoom, x: selCam.x, y: selCam.y }))}>
                  Aplicar a toda a câmara {camLabel(selCam.cam).toLowerCase()}</Button>
                <Button size="sm" variant="outline" disabled={!canEdit || framing || !camFile(selCam.cam)} title="O mesmo zoom e posição em todos os vídeos que usam esta gravação"
                  onClick={() => void frameEverywhere(selCam.cam, { zoom: selCam.zoom, x: selCam.x, y: selCam.y })}>
                  {framing ? <Loader2Icon className="animate-spin" /> : null} Aplicar a todos os vídeos com {camFile(selCam.cam) ?? "esta gravação"}</Button>
                <Button size="sm" variant="ghost" disabled={!canEdit}
                  onClick={() => apply(setCam(doc, selCamIdx, { zoom: 1, x: CAM_ANCHOR.x, y: CAM_ANCHOR.y }))}>Repor</Button>
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
          {selOv && (
            <div className="flex flex-col gap-2" aria-label="Visual selecionado">
              <span className="font-medium">{selOv.kind === "broll" ? "B-roll" : selOv.kind === "graphic" ? "Imagem" : "Texto"} · {selOv.label}</span>
              {selOv.kind === "graphic" && (
                <div className="flex items-center gap-3">
                  <span className="flex h-20 w-20 items-center justify-center overflow-hidden rounded border bg-muted">
                    {selOv.asset && assetUrls[selOv.asset] ? (
                      // eslint-disable-next-line @next/next/no-img-element -- link assinado curto do R2
                      <img src={assetUrls[selOv.asset]} alt="" className="max-h-full max-w-full object-contain" />
                    ) : <span className="text-[10px] text-muted-foreground">…</span>}
                  </span>
                  <Button size="sm" variant="outline" disabled={!canEdit || !images.length} onClick={() => setPicker({ mode: "replace", id: selOv.id })}>Trocar imagem</Button>
                </div>
              )}
              <div className="flex flex-wrap items-center gap-2">
                <label className="flex items-center gap-2"><span className="text-muted-foreground">Duração</span>
                  <Input type="number" min={0.1} max={30} step={0.1} className="h-8 w-20" disabled={!canEdit} aria-label="Duração do visual em segundos"
                    value={Math.round((selOv.e - selOv.s) * 10) / 10}
                    onChange={(e) => { const v = Number(e.target.value); if (Number.isFinite(v) && v >= 0.1) apply(resizeOverlay(doc, selOv.id, "e", selOv.s + v)); }} /> s</label>
                <Button size="sm" variant="outline" disabled={!canEdit} title="Estica ou encurta até ao fim da frase da legenda"
                  onClick={() => { const o = srcToOut(doc, selOv.s); if (o != null) apply(resizeOverlay(doc, selOv.id, "e", selOv.s + toPhraseEnd(o))); }}>Até ao fim da frase</Button>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                {[-0.5, 0.5].map((d) => <Button key={d} size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(shiftOverlay(doc, selOv.id, d))}>Mover {d > 0 ? `+${d}` : d} s</Button>)}
                {[-0.5, 0.5].map((d) => <Button key={`e${d}`} size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(resizeOverlay(doc, selOv.id, "e", selOv.e + d))}>Duração {d > 0 ? `+${d}` : d} s</Button>)}
                <Button size="sm" variant="destructive" disabled={!canEdit} onClick={remove}><Trash2Icon /> Tirar visual</Button>
              </div>
              {(canPlace || selOv.box) && (
                <label className="flex flex-wrap items-center gap-2">
                  <span className="text-muted-foreground">Posição</span>
                  <select aria-label="Posição do visual" className="h-8 rounded-md border bg-background px-2 text-xs" disabled={!canEdit} value={boxPreset(selOv)}
                    onChange={(e) => { const p = BOX_PRESETS.find((x) => x.key === e.target.value); if (p) apply(setOverlayBox(doc, selOv.id, p.box)); }}>
                    {boxPreset(selOv) === "custom" && <option value="custom" disabled>Posição própria</option>}
                    {BOX_PRESETS.map((p) => <option key={p.key} value={p.key}>{p.label}{p.key === "default" && selOv.kind === "broll" ? " (ecrã inteiro)" : ""}</option>)}
                  </select>
                </label>
              )}
            </div>
          )}
          {!sel && <p className="text-muted-foreground">Clica num corte ou numa palavra na linha do tempo para a ajustar. Arrasta as pontas de um corte ou de um visual para aparar e uma palavra ou um visual para o mover. Clica na faixa das câmaras para trocar o ângulo, o zoom e a posição. Atalhos: Espaço tocar, ←/→ 0,1 s (Shift 1 s), S dividir, C trocar a câmara no cursor, N nota, Delete tirar, Cmd+Z desfazer.</p>}
          <details className="border-t pt-3">
            <summary className="cursor-pointer font-medium">Aspeto e estilos guardados</summary>
            <div className="mt-2 flex flex-col gap-3">
              <LookPanel doc={doc} disabled={!canEdit} onChange={apply} />
              <SavedStylesPanel access={access} st={st} dirty={dirty} canSave={!!st.can.styles} onApplied={() => onReload()} />
            </div>
          </details>
          <div className="flex flex-col gap-2 border-t pt-3" aria-label="Notas">
            <span className="font-medium">Notas {notes.length > 0 && <span className="text-muted-foreground">({notes.filter((n) => !n.done).length} por tratar)</span>}</span>
            <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); apply(addNote(doc, t, newNote, me, nextId("n"))); setNewNote(""); }}>
              <Input ref={noteRef} placeholder={`O que muda aos ${fmtT(t)}? (N)`} value={newNote} maxLength={500} disabled={!canEdit} onChange={(e) => setNewNote(e.target.value)} aria-label="Nova nota no cursor" />
              <Button size="sm" type="submit" disabled={!canEdit || !newNote.trim()}>Juntar</Button>
            </form>
            {notes.length > 0 && (
              <ul className="flex max-h-40 flex-col gap-1 overflow-y-auto">
                {notes.map((n) => (
                  <li key={n.id} className={cn("flex items-start gap-2 rounded px-1 py-0.5", sel?.kind === "note" && sel.id === n.id && "bg-muted")}>
                    <button type="button" className="font-mono text-xs tabular-nums underline" disabled={n.at == null} onClick={() => { if (n.at != null) setT(n.at); setSel({ kind: "note", id: n.id }); }}>
                      {n.at == null ? "cortado" : fmtT(n.at)}
                    </button>
                    <span className={cn("min-w-0 flex-1", n.done && "text-muted-foreground line-through")}>{n.text}{n.by ? <span className="text-xs text-muted-foreground"> · {n.by}</span> : null}</span>
                    <Button size="sm" variant="ghost" disabled={!canEdit} onClick={() => apply(toggleNote(doc, n.id))}>{n.done ? "Reabrir" : "Feita"}</Button>
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div className="mt-auto flex flex-col gap-2 border-t pt-3">
            {isCurrent ? (
              <>
                <Input placeholder="O que mudou (opcional)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} disabled={!canEdit} aria-label="Nota da versão" />
                <div className="flex gap-2">
                  <Button disabled={!canEdit || !dirty || saving} onClick={() => void save()}>{saving ? <Loader2Icon className="animate-spin" /> : <SaveIcon />} Gravar versão {st.versions.length + 1}</Button>
                  {dirty && <Button variant="ghost" onClick={() => setH(historyOf(v.doc))}>Descartar</Button>}
                </div>
                {siblings.length > 1 && (
                  <span className="text-xs text-muted-foreground">
                    O corpo vai também para {siblings.filter((x) => x.asset_id !== st.asset.id).map((x) => variantShort(x.variant)).join(", ")} (cada um com o seu hook).
                  </span>
                )}
                {!canEdit && <span className="text-xs text-muted-foreground">Não tens permissão para editar vídeos neste cliente.</span>}
              </>
            ) : (
              <Button variant="outline" disabled={saving || !st.can.timeline} onClick={() => void restore()}>Restaurar esta versão como nova</Button>
            )}
          </div>
        </div>
      </div>

      {/* original vs. cortado (CLIP-06): só com doc.ai.clip */}
      <ImagePicker open={!!picker} onOpenChange={(o) => { if (!o) setPicker(null); }} images={images} urls={assetUrls} ensure={ensureUrls}
        title={picker?.mode === "replace" ? "Trocar imagem" : "Imagem no cursor"}
        onPick={(a) => {
          if (!picker) return;
          if (picker.mode === "replace") {
            const id = picker.id;
            apply({ ...doc, overlays: doc.overlays.map((o) => (o.id === id ? { ...o, asset: a.id, label: a.title } : o)) });
          } else {
            const oid = nextId("o");
            const next = addOverlay(doc, { id: oid, kind: "graphic", label: a.title, asset: a.id }, t, toPhraseEnd(t));
            apply(next);
            if (next !== doc) setSel({ kind: "ov", id: oid });
          }
        }} />
      <WidgetBoundary label="Original vs. cortado"><ClipOrderView doc={doc} t={t} onSeek={(x) => { setPlaying(false); setT(x); }} /></WidgetBoundary>

      {/* linha do tempo (min-w-0: a faixa larga rola dentro, sem alargar a página) */}
      <div className="flex min-w-0 flex-col gap-2 rounded-lg border p-3">
        <div className="flex flex-wrap items-center gap-3 text-sm">
          <span className="font-medium">Linha do tempo</span>
          <label className="flex items-center gap-2 text-muted-foreground">Zoom
            <input type="range" min={15} max={200} value={pps} onChange={(e) => setPps(Number(e.target.value))} aria-label="Zoom da linha do tempo" />
          </label>
          <span className="text-xs text-muted-foreground">{segs.length} cortes · {words.length} palavras · {doc.overlays.length} visuais · {fmtT(duration)}</span>
          <Button size="sm" variant="outline" disabled={!canEdit || !lib} onClick={() => setPicker({ mode: "add" })}><ImagePlusIcon /> Imagem no cursor</Button>
          <select aria-label="Juntar visual no cursor" className="h-8 max-w-56 rounded-md border bg-background px-2 text-xs" value="" disabled={!canEdit || !lib}
            onChange={(e) => { const a = visuals.find((x) => x.id === e.target.value); if (a) apply(addOverlay(doc, { id: nextId("o"), kind: a.kind === "video" || a.kind === "link_externo" ? "broll" : "graphic", label: a.title, asset: a.id }, t, 2)); }}>
            <option value="">{lib == null ? "A carregar a biblioteca…" : visuals.length ? "＋ Visual da biblioteca no cursor" : "Sem imagens nem vídeos na biblioteca"}</option>
            {visuals.map((a) => <option key={a.id} value={a.id}>{a.title}</option>)}
          </select>
          <select aria-label="Música" className="h-8 max-w-56 rounded-md border bg-background px-2 text-xs" disabled={!canEdit || !lib}
            value={doc.audio.music?.asset ?? ""} onChange={(e) => { const a = tracks.find((x) => x.id === e.target.value); apply(setMusic(doc, a ? { label: a.title, asset: a.id } : null)); }}>
            <option value="">{tracks.length ? "Sem música" : "Sem áudio na biblioteca"}</option>
            {tracks.map((a) => <option key={a.id} value={a.id}>{a.title}</option>)}
          </select>
          {doc.audio.music && (
            <label className="flex items-center gap-2 text-xs text-muted-foreground">Volume {doc.audio.music.db} dB
              <input type="range" min={-40} max={6} value={doc.audio.music.db} disabled={!canEdit} onChange={(e) => apply(setMusicDb(doc, Number(e.target.value)))} aria-label="Volume da música" />
            </label>
          )}
          {doc.audio.music && selSeg && (
            <Button size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(setGain(doc, selSeg.in, selSeg.out, -30))}>Baixar música no corte {segs.indexOf(selSeg) + 1}</Button>
          )}
        </div>
        <div className="flex">
          <div className="w-20 shrink-0 text-xs text-muted-foreground">
            {["", "Secções", "Cortes", "Câmara", "Legendas", "Visuais", "Som", "Notas"].map((l, i) => <div key={i} style={{ height: i === 0 ? 20 : TRACK_H }} className="flex items-center">{l}</div>)}
          </div>
          <div className="min-w-0 flex-1 overflow-x-auto">
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
                  className="bg-violet-500/30" onClick={() => setSel({ kind: "seg", id: s.id })}
                  onEdge={canEdit ? (edge) => startDrag(edge === "start" ? "seg-in" : "seg-out", s.id) : undefined} />
              ))}</Track>
              <Track>{doc.cameras.flatMap((c, i) => spanOut(doc, c.s, c.e).map((p, k) => (
                <Block key={`${i}-${k}`} left={p.at * pps} w={(p.end - p.at) * pps} label={`${c.cam === "front" ? "frente" : "lado"}${c.zoom > 1.001 ? ` ${c.zoom.toFixed(1)}×` : ""}`}
                  className={c.cam === "front" ? "bg-emerald-500/20" : "bg-teal-500/30"} selected={sel?.kind === "cam" && sel.id === String(i)}
                  onClick={() => setSel({ kind: "cam", id: String(i) })} />
              )))}</Track>
              <Track>{words.map((w, i) => (
                <Block key={`${w.id}-${i}`} left={w.at * pps} w={Math.max(4, (w.end - w.at) * pps)} label={pps >= 60 ? w.w : ""} title={w.w}
                  selected={sel?.kind === "word" && sel.id === w.id} className="bg-yellow-400/40" onClick={() => setSel({ kind: "word", id: w.id })}
                  onBody={canEdit ? startDrag("word", w.id) : undefined} />
              ))}</Track>
              <Track>
                {doc.overlays.length === 0 && <span className="px-2 text-xs text-muted-foreground">Sem visuais nesta versão: junta um da biblioteca no cursor</span>}
                {doc.overlays.flatMap((o) => spanOut(doc, o.s, o.e).map((p, k) => (
                  <Block key={`${o.id}-${k}`} left={p.at * pps} w={(p.end - p.at) * pps} label={o.label} selected={sel?.kind === "ov" && sel.id === o.id}
                    className={o.kind === "broll" ? "bg-orange-500/30" : "bg-fuchsia-500/30"} onClick={() => setSel({ kind: "ov", id: o.id })}
                    onBody={canEdit ? startDrag("ov", o.id) : undefined} onEdge={canEdit ? (edge) => startDrag(edge === "start" ? "ov-s" : "ov-e", o.id) : undefined} />
                )))}
              </Track>
              <Track>
                {doc.audio.music ? <Block left={0} w={duration * pps} label={`${doc.audio.music.label} · ${doc.audio.music.db} dB`} className="bg-pink-500/20" />
                  : <span className="px-2 text-xs text-muted-foreground">Só a voz (sem música nesta versão)</span>}
                {doc.audio.music && doc.audio.gains.flatMap((g) => spanOut(doc, g.s, g.e).map((p, k) => (
                  <Block key={`${g.s}-${k}`} left={p.at * pps} w={(p.end - p.at) * pps} label={`${g.db} dB`} title="Clica para tirar" className="top-4 bg-pink-700/60"
                    onClick={canEdit ? () => apply(clearGain(doc, g.s)) : undefined} />
                )))}
              </Track>
              <Track>{notes.filter((n) => n.at != null).map((n) => (
                <button key={n.id} type="button" title={n.text} onClick={() => { setT(n.at!); setSel({ kind: "note", id: n.id }); }}
                  className={cn("absolute top-1 bottom-1 w-2 -translate-x-1 rounded-sm", n.done ? "bg-muted-foreground/40" : "bg-red-500")} style={{ left: n.at! * pps }} aria-label={`Nota aos ${fmtT(n.at!)}`} />
              ))}</Track>
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

function Block({ left, w, label, className, selected, onClick, title, onBody, onEdge }: {
  left: number; w: number; label: string; className?: string; selected?: boolean; onClick?: () => void; title?: string;
  onBody?: (e: React.PointerEvent) => void; onEdge?: (edge: "start" | "end") => (e: React.PointerEvent) => void;
}) {
  return (
    <div title={title ?? label} role={onClick ? "button" : undefined} tabIndex={onClick ? 0 : undefined}
      onClick={onClick} onKeyDown={onClick ? (e) => { if (e.key === "Enter") onClick(); } : undefined}
      onPointerDown={(e) => { onClick?.(); onBody?.(e); }}
      className={cn("absolute top-1 bottom-1 overflow-hidden rounded-sm border border-white/10 px-1 text-left text-[10px] leading-[24px] whitespace-nowrap", className,
        selected && "ring-2 ring-primary", onClick && "cursor-pointer hover:brightness-125", onBody && "cursor-grab")}
      style={{ left, width: Math.max(2, w - 1) }}>
      {label}
      {onEdge && w > 12 && <>
        <span aria-hidden onPointerDown={(e) => { onClick?.(); onEdge("start")(e); }} className="absolute inset-y-0 left-0 w-1.5 cursor-ew-resize bg-white/40" />
        <span aria-hidden onPointerDown={(e) => { onClick?.(); onEdge("end")(e); }} className="absolute inset-y-0 right-0 w-1.5 cursor-ew-resize bg-white/40" />
      </>}
    </div>
  );
}
