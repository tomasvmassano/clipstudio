"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { ArrowLeftIcon, ArrowRightIcon, Loader2Icon, PauseIcon, PlayIcon, Redo2Icon, SaveIcon, Undo2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useSession } from "@/components/session-provider";
import { EditorStage } from "@/components/edit/editor-stage";
import { SavedStylesPanel } from "@/components/edit/style-tools";
import type { Access } from "@/lib/access";
import { SOURCE_LABEL, saveEdit, type EditState } from "@/lib/edit";
import {
  addNote, deleteSegment, editWord, fmtT, guidedProblem, historyOf, layout, notesOut, problem, push, redo, restorable, restoreSegment, setHook, setMusic,
  toggleNote, undo, wordsBySegment, type EditDoc, type History,
} from "@/lib/edit-doc";
import { fetchLibrary, type MediaAsset } from "@/lib/media";
import { variantLabel } from "@/lib/media-review";
import { clientPath } from "@/lib/ws-path";
import { cn } from "@/lib/utils";

/*
 * Modo guiado (EDL-10, ADR-0047): a mesma edição, sem linha do tempo. Passos Estilo → Corte → Hook → Visual e música →
 * Legendas → Exportar, cada um com a escolha da IA, as alternativas que existem e uma nota no momento.
 * Só produz mudanças que o servidor aceita no modo guiado (_edit_guided_problem); guidedProblem avisa antes de gravar.
 */
type Step = "estilo" | "corte" | "hook" | "visual" | "legendas" | "exportar";
const STEPS: { key: Step; label: string }[] = [
  { key: "estilo", label: "Estilo" }, { key: "corte", label: "Corte" }, { key: "hook", label: "Hook" },
  { key: "visual", label: "Visual e música" }, { key: "legendas", label: "Legendas" }, { key: "exportar", label: "Exportar" },
];

export function GuidedEditor({ access, st, onReload }: { access: Access; st: EditState; onReload: (v?: string | null) => Promise<void> }) {
  const v = st.version!;
  const base = v.doc;
  const isCurrent = v.id === st.document?.current_version_id;
  const canEdit = (st.can.guided || st.can.timeline) && isCurrent;
  const { label: me } = useSession();
  const [h, setH] = useState<History>(() => historyOf(base));
  const doc = h.present;
  const dirty = h.past.length > 0;
  const [step, setStep] = useState<Step>("corte");
  const [lib, setLib] = useState<MediaAsset[] | null>(null);
  const [libErr, setLibErr] = useState(false);
  const [tRaw, setT] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [word, setWord] = useState<string | null>(null);
  const [newNote, setNewNote] = useState("");
  const [vnote, setVnote] = useState("");
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const idSeq = useRef(0);
  const { segs, duration } = useMemo(() => layout(doc), [doc]);
  const t = Math.min(tRaw, duration);
  const pool = useMemo(() => st.cut_pool ?? [], [st.cut_pool]);
  const poolSegs = useMemo(() => pool.map((p) => p.seg), [pool]);
  // quem tem a linha do tempo pode gravar tudo; para os outros o servidor só aceita o modo guiado
  const guidedWhy = useMemo(() => (st.can.timeline ? null : guidedProblem(base, doc, poolSegs, me)), [st.can.timeline, base, doc, poolSegs, me]);
  const apply = useCallback((d: EditDoc) => {
    if (!canEdit) return;
    if (!st.can.timeline) { const why = guidedProblem(base, d, poolSegs, me); if (why) { setMsg({ kind: "err", text: `No modo guiado não dá: ${why}.` }); return; } }
    setMsg(null); setH((x) => push(x, d));
  }, [canEdit, st.can.timeline, base, poolSegs, me]);

  useEffect(() => {
    let off = false;
    const id = setTimeout(() => {
      fetchLibrary(access, { view: "ativos", limit: 200 }).then((l) => { if (!off) setLib(l.assets); }).catch(() => { if (!off) { setLib([]); setLibErr(true); } });
    }, 0);
    return () => { off = true; clearTimeout(id); };
  }, [access]);

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

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.key === " ") { e.preventDefault(); setPlaying((p) => !p); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") { e.preventDefault(); setH((x) => (e.shiftKey ? redo(x) : undo(x))); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const save = async () => {
    const why = problem(doc) ?? guidedWhy;
    if (why) { setMsg({ kind: "err", text: `Não dá para gravar: ${why}.` }); return; }
    setSaving(true); setMsg(null);
    try { await saveEdit(access, st.asset.id, st.document?.current_version_id ?? null, doc, vnote.trim() || undefined); setVnote(""); await onReload(); }
    catch (e) { setMsg({ kind: "err", text: (e as Error).message }); setSaving(false); }
  };
  const seek = (x: number) => { setPlaying(false); setT(Math.max(0, Math.min(duration, x))); };
  const nextId = (p: string) => { idSeq.current += 1; return `${p}${Date.now().toString(36)}${idSeq.current}`; };

  const notes = notesOut(doc);
  const tracks = (lib ?? []).filter((a) => a.kind === "audio");
  const ai = st.ai_choice ?? null;
  const back = clientPath(access.ws, `/revisao?ver=videos&asset=${st.asset.id}`);
  const canRestore = restorable(doc, base, pool);
  const selWord = word ? doc.captions.words.find((w) => w.id === word) ?? null : null;
  const hookAlts = [...new Set([ai?.hook ?? "", ...(st.guiao?.hooks ?? [])].map((x) => x.trim()).filter((x) => x && x !== doc.hook.text))].slice(0, 4);
  const aiSegsOk = ai && JSON.stringify(ai.segments) !== JSON.stringify(doc.segments) && (st.can.timeline || !guidedProblem(base, { ...doc, segments: ai.segments }, poolSegs, me));

  const noteBox = (
    <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); apply(addNote(doc, t, newNote, me, nextId("n"))); setNewNote(""); }}>
      <Input placeholder={`Nota aos ${fmtT(t)}: o que queres mudar aqui?`} value={newNote} maxLength={500} disabled={!canEdit}
        onChange={(e) => setNewNote(e.target.value)} aria-label="Nota neste momento" />
      <Button size="sm" type="submit" disabled={!canEdit || !newNote.trim()}>Juntar nota</Button>
    </form>
  );

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <Link href={back} className="text-xs text-muted-foreground hover:underline">← Revisão</Link>
          <h1 className="truncate text-2xl font-semibold tracking-tight">
            {st.guiao ? `Guião ${st.guiao.n}` : st.asset.title} · {variantLabel(st.asset.variant)}{st.asset.style ? ` · ${st.asset.style}` : ""}
          </h1>
          <p className="text-sm text-muted-foreground">
            Modo guiado · versão {v.version_no} ({SOURCE_LABEL[v.source]}{v.created_label ? `, ${v.created_label}` : ""}){!isCurrent && " · versão antiga, só leitura"}{dirty && " · alterações por gravar"}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Versão" className="h-9 rounded-md border bg-background px-2 text-sm" value={v.id} onChange={(e) => void onReload(e.target.value)}>
            {st.versions.map((x) => <option key={x.id} value={x.id}>v{x.version_no} · {SOURCE_LABEL[x.source]}{x.note ? ` · ${x.note}` : ""}</option>)}
          </select>
          <Button size="sm" variant="outline" disabled={!h.past.length} onClick={() => setH(undo)} aria-label="Desfazer"><Undo2Icon /></Button>
          <Button size="sm" variant="outline" disabled={!h.future.length} onClick={() => setH(redo)} aria-label="Refazer"><Redo2Icon /></Button>
          {st.can.timeline && (
            <Button size="sm" variant="outline" render={<Link href={clientPath(access.ws, `/editor?asset=${st.asset.id}`)} />} nativeButton={false}>Linha do tempo</Button>
          )}
        </div>
      </div>
      {msg && <Alert variant={msg.kind === "err" ? "destructive" : "default"}><AlertDescription>{msg.text}</AlertDescription></Alert>}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,20rem)_1fr]">
        <div className="flex flex-col gap-2">
          <EditorStage doc={doc} t={t} />
          <div className="flex items-center justify-center gap-2">
            <Button size="sm" variant="outline" onClick={() => seek(t - 1)} aria-label="Recuar 1 s"><ArrowLeftIcon /></Button>
            <Button size="sm" onClick={() => { if (t >= duration) setT(0); setPlaying((p) => !p); }} aria-label={playing ? "Pausa" : "Tocar"}>{playing ? <PauseIcon /> : <PlayIcon />}</Button>
            <Button size="sm" variant="outline" onClick={() => seek(t + 1)} aria-label="Avançar 1 s"><ArrowRightIcon /></Button>
            <span className="tabular-nums text-sm text-muted-foreground">{fmtT(t)} / {fmtT(duration)}</span>
          </div>
          <input type="range" min={0} max={Math.max(0.1, duration)} step={0.1} value={t} onChange={(e) => seek(Number(e.target.value))} aria-label="Posição no vídeo" />
          <p className="text-xs text-muted-foreground">Pré-visualização sem imagem até haver armazenamento de vídeo: o hook e as legendas aparecem no tempo certo.</p>
        </div>

        <div className="flex min-w-0 flex-col gap-3 rounded-lg border p-3 text-sm">
          <Tabs value={step} onValueChange={(x) => setStep(String(x) as Step)}>
            <TabsList className="flex h-auto w-full flex-wrap justify-start">
              {STEPS.map((s, i) => <TabsTrigger key={s.key} value={s.key}>{i + 1}. {s.label}</TabsTrigger>)}
            </TabsList>

            <TabsContent value="estilo" className="flex flex-col gap-3 pt-2">
              <p>Estilo deste vídeo: <Badge variant="outline">{doc.style || "sem estilo"}</Badge>{doc.look?.from ? <> · aspeto do estilo guardado <Badge variant="outline">{doc.look.from.key} v{doc.look.from.version}</Badge></> : null}</p>
              <SavedStylesPanel access={access} st={st} dirty={dirty} canSave={!!st.can.styles} onApplied={() => onReload()} />
              <p className="text-muted-foreground">Queres outro aspeto? Deixa uma nota e a equipa trata disso.</p>
              {noteBox}
            </TabsContent>

            <TabsContent value="corte" className="flex flex-col gap-3 pt-2">
              {ai && <p className="text-muted-foreground">Escolha da IA (v{ai.version_no}): {ai.segments.length} cortes.
                {aiSegsOk && <Button size="sm" variant="link" disabled={!canEdit} onClick={() => apply({ ...doc, segments: ai.segments })}>Voltar aos cortes da IA</Button>}</p>}
              <ol className="flex flex-col gap-1" aria-label="Cortes">
                {wordsBySegment(doc).map(({ seg, words }, i) => (
                  <li key={seg.id} className={cn("flex items-start gap-2 rounded border px-2 py-1", t >= seg.at && t < seg.at + seg.dur && "border-primary")}>
                    <button type="button" className="font-mono text-xs tabular-nums underline" onClick={() => seek(seg.at)}>{fmtT(seg.at)}</button>
                    <span className="min-w-0 flex-1"><span className="text-xs text-muted-foreground">{i + 1} · {seg.section === "hook" ? "hook" : "corpo"} · {fmtT(seg.dur)} · </span>
                      {words.map((w) => w.w).join(" ") || <span className="text-muted-foreground">sem fala</span>}</span>
                    <Button size="sm" variant="outline" disabled={!canEdit || segs.length <= 1} onClick={() => apply(deleteSegment(doc, seg.id))}>Tirar</Button>
                  </li>
                ))}
              </ol>
              {canRestore.length > 0 && (
                <div className="flex flex-col gap-1" aria-label="Cortes tirados">
                  <span className="font-medium">Cortes tirados</span>
                  {canRestore.map((p) => (
                    <div key={p.seg.id} className="flex items-center gap-2 rounded border border-dashed px-2 py-1">
                      <span className="min-w-0 flex-1 text-muted-foreground">{p.seg.section === "hook" ? "hook" : "corpo"} · {fmtT(p.seg.out - p.seg.in)}{p.version_no ? ` · da v${p.version_no}` : " · tirado agora"}</span>
                      <Button size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(restoreSegment(doc, p.seg, p.after))}>Repor</Button>
                    </div>
                  ))}
                </div>
              )}
              <p className="text-muted-foreground">Para aparar ou mudar a ordem, deixa uma nota no momento.</p>
              {noteBox}
            </TabsContent>

            <TabsContent value="hook" className="flex flex-col gap-3 pt-2">
              <label className="flex flex-col gap-1"><span className="font-medium">Hook no ecrã</span>
                <Input value={doc.hook.text} disabled={!canEdit} maxLength={200} onChange={(e) => apply(setHook(doc, e.target.value))} />
              </label>
              {hookAlts.length > 0 && (
                <div className="flex flex-col gap-1" aria-label="Alternativas do hook">
                  <span className="text-muted-foreground">Alternativas</span>
                  {hookAlts.map((x) => (
                    <div key={x} className="flex items-center gap-2 rounded border px-2 py-1">
                      <span className="min-w-0 flex-1">{x}{x === ai?.hook?.trim() && <Badge variant="outline" className="ml-2">escolha da IA</Badge>}</span>
                      <Button size="sm" variant="outline" disabled={!canEdit} onClick={() => apply(setHook(doc, x))}>Usar</Button>
                    </div>
                  ))}
                </div>
              )}
              {noteBox}
            </TabsContent>

            <TabsContent value="visual" className="flex flex-col gap-3 pt-2">
              <div className="flex flex-col gap-1">
                <span className="font-medium">Visuais</span>
                {doc.overlays.length === 0 ? <span className="text-muted-foreground">Sem visuais nesta versão.</span> : doc.overlays.map((o) => (
                  <span key={o.id}>{o.kind === "broll" ? "B-roll" : o.kind === "graphic" ? "Gráfico" : "Texto"}: {o.label}</span>
                ))}
                <span className="text-xs text-muted-foreground">Para trocar ou juntar um visual, deixa uma nota no momento.</span>
              </div>
              <label className="flex flex-col gap-1"><span className="font-medium">Música</span>
                <select aria-label="Música" className="h-9 rounded-md border bg-background px-2" disabled={!canEdit || !lib}
                  value={doc.audio.music?.asset ?? ""} onChange={(e) => { const a = tracks.find((x) => x.id === e.target.value); apply(setMusic(doc, a ? { label: a.title, asset: a.id } : null)); }}>
                  <option value="">{lib == null ? "A carregar a biblioteca…" : "Sem música"}</option>
                  {doc.audio.music && !tracks.some((a) => a.id === doc.audio.music?.asset) && <option value={doc.audio.music.asset ?? ""} disabled>{doc.audio.music.label}</option>}
                  {tracks.map((a) => <option key={a.id} value={a.id}>{a.title}{a.id === ai?.music?.asset ? " (escolha da IA)" : ""}</option>)}
                </select>
              </label>
              {libErr && <span className="text-xs text-destructive">Não consegui abrir a biblioteca de media. Recarrega a página para tentar de novo.</span>}
              {lib && tracks.length === 0 && !libErr && <span className="text-xs text-muted-foreground">Não há áudio na biblioteca deste cliente.</span>}
              {noteBox}
            </TabsContent>

            <TabsContent value="legendas" className="flex flex-col gap-3 pt-2">
              {selWord ? (
                <div className="flex items-center gap-2" aria-label="Palavra selecionada">
                  <Input value={selWord.w} disabled={!canEdit} maxLength={60} autoFocus aria-label="Texto da palavra"
                    onChange={(e) => { if (e.target.value.trim()) apply(editWord(doc, selWord.id, { w: e.target.value })); }} />
                  <Button size="sm" variant="ghost" onClick={() => setWord(null)}>Fechar</Button>
                </div>
              ) : <p className="text-muted-foreground">Clica numa palavra para a corrigir. Os tempos das legendas ficam iguais.</p>}
              <div className="flex max-h-80 flex-col gap-2 overflow-y-auto" aria-label="Legendas">
                {wordsBySegment(doc).map(({ seg, words }, i) => (
                  <p key={seg.id} className="leading-7"><span className="mr-1 text-xs text-muted-foreground">{i + 1}.</span>
                    {words.map((w, k) => (
                      <button key={`${w.id}-${k}`} type="button" onClick={() => { setWord(w.id); seek(w.at); }}
                        className={cn("mr-1 rounded px-0.5 hover:bg-muted", word === w.id && "bg-primary/20 ring-1 ring-primary", t >= w.at && t < w.end && "underline")}>{w.w}</button>
                    ))}
                  </p>
                ))}
              </div>
              {noteBox}
            </TabsContent>

            <TabsContent value="exportar" className="flex flex-col gap-3 pt-2">
              <p>{dirty ? `${h.past.length} alteração(ões) por gravar.` : "Sem alterações por gravar."} Grava a versão abaixo; a exportação do vídeo faz-se a partir da versão gravada{st.can.export ? " (na linha do tempo)" : " por quem gere o cliente"}.</p>
              {noteBox}
            </TabsContent>
          </Tabs>

          <div className="flex flex-col gap-2 border-t pt-3" aria-label="Notas">
            <span className="font-medium">Notas {notes.length > 0 && <span className="text-muted-foreground">({notes.filter((n) => !n.done).length} por tratar)</span>}</span>
            {notes.length === 0 ? <span className="text-muted-foreground">Sem notas nesta versão.</span> : (
              <ul className="flex max-h-40 flex-col gap-1 overflow-y-auto">
                {notes.map((n) => (
                  <li key={n.id} className="flex items-start gap-2 px-1 py-0.5">
                    <button type="button" className="font-mono text-xs tabular-nums underline" disabled={n.at == null} onClick={() => { if (n.at != null) seek(n.at); }}>
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
                <Input placeholder="O que mudou (opcional)" value={vnote} maxLength={500} onChange={(e) => setVnote(e.target.value)} disabled={!canEdit} aria-label="Nota da versão" />
                <div className="flex flex-wrap items-center gap-2">
                  <Button disabled={!canEdit || !dirty || saving} onClick={() => void save()}>{saving ? <Loader2Icon className="animate-spin" /> : <SaveIcon />} Gravar versão {st.versions.length + 1}</Button>
                  {dirty && <Button variant="ghost" onClick={() => { setH(historyOf(base)); setMsg(null); }}>Descartar</Button>}
                  {guidedWhy && <span className="text-xs text-destructive">{guidedWhy}</span>}
                </div>
                {!canEdit && <span className="text-xs text-muted-foreground">Não tens permissão para editar vídeos neste cliente.</span>}
              </>
            ) : <span className="text-xs text-muted-foreground">Versão antiga: escolhe a versão atual para ajustar.</span>}
          </div>
        </div>
      </div>
    </div>
  );
}
