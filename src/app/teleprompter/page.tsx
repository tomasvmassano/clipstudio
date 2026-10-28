"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { Prompter } from "@/components/teleprompter/prompter";
import { TpSettings } from "@/components/teleprompter/settings";
import { useTpPrefs } from "@/components/teleprompter/use-prefs";
import type { Access } from "@/lib/access";
import { addDays, dayLabel, setProduction, subscribeGuioes, todayDubai } from "@/lib/data";
import {
  blockLabel, blocksOf, closeSession, createTake, openSession, permanentError, readOutbox, saveProgress, setQueue, updateTake, writeOutbox,
  type BlockKey, type PendingTake, type RecordingSession, type SessionItem, type TakeRow,
} from "@/lib/recording";
import { cn } from "@/lib/utils";

/*
 * Teleprompter (PRD M03): fila de gravação do dia partilhada entre dispositivos, blocos Hook/Body/CTA, takes,
 * preferências por utilizador e dispositivo, retoma segura e takes offline com reenvio idempotente.
 */

const subscribeOnline = (cb: () => void) => {
  window.addEventListener("online", cb); window.addEventListener("offline", cb);
  return () => { window.removeEventListener("online", cb); window.removeEventListener("offline", cb); };
};

function Btn({ label, onClick, on, disabled, aria, className }: { label: string; onClick: () => void; on?: boolean; disabled?: boolean; aria?: string; className?: string }) {
  return (
    <button type="button" aria-label={aria ?? label} onClick={onClick} disabled={disabled}
      className={cn("min-h-11 rounded-xl border border-neutral-700 bg-neutral-900 px-3 text-sm font-semibold text-white disabled:opacity-40", on && "border-amber-400 bg-amber-400 text-black", className)}>
      {label}
    </button>
  );
}

function TeleprompterInner({ access }: { access: Access }) {
  const params = useSearchParams();
  const router = useRouter();
  const date = params.get("date") ?? todayDubai();
  const { mode, can } = useSession();
  const canTake = can("recording.confirm");
  const { prefs, update, keysFor, syncError } = useTpPrefs(mode === "user");
  const online = useSyncExternalStore(subscribeOnline, () => navigator.onLine, () => true);

  const [session, setSession] = useState<RecordingSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [view, setView] = useState<{ kind: "queue" } | { kind: "prompter"; index: number; pct?: number; block?: BlockKey | null }>({ kind: "queue" });
  const [settings, setSettings] = useState(false);
  const [outbox, setOutbox] = useState<PendingTake[]>(() => readOutbox(access.ws));
  const [expanded, setExpanded] = useState<string | null>(null);

  const load = useCallback(async () => {
    try { setSession(await openSession(access, date)); setError(""); }
    catch (e) { setError((e as Error).message); }
    finally { setLoading(false); }
  }, [access, date]);

  useEffect(() => {
    let alive = true;
    openSession(access, date)
      .then((s) => { if (alive) { setSession(s); setError(""); } })
      .catch((e: Error) => { if (alive) setError(e.message); })
      .finally(() => { if (alive) setLoading(false); });
    const unsub = subscribeGuioes(access, load);
    const onFocus = () => { if (document.visibilityState === "visible") load(); };
    document.addEventListener("visibilitychange", onFocus);
    return () => { alive = false; unsub(); document.removeEventListener("visibilitychange", onFocus); };
  }, [access, date, load]);

  // ---------- takes por enviar ----------
  const setBox = useCallback((f: (l: PendingTake[]) => PendingTake[]) => {
    setOutbox((prev) => { const next = f(prev); writeOutbox(access.ws, next); return next; });
  }, [access.ws]);
  const flushing = useRef(false);
  const flush = useCallback(async () => {
    if (flushing.current) return;
    flushing.current = true;
    try {
      for (const t of readOutbox(access.ws)) {
        if (t.error) continue;
        try {
          await createTake(access, t);
          setBox((l) => l.filter((x) => x.client_ref !== t.client_ref));
        } catch (e) {
          const code = (e as { code?: string }).code;
          if (permanentError(code)) setBox((l) => l.map((x) => (x.client_ref === t.client_ref ? { ...x, error: (e as Error).message } : x)));
          else break; // sem rede: tenta mais tarde
        }
      }
    } finally { flushing.current = false; }
    load();
  }, [access, setBox, load]);
  useEffect(() => {
    if (!online || !outbox.some((t) => !t.error)) return;
    const t = setTimeout(flush, 500);
    const iv = setInterval(flush, 15000);
    return () => { clearTimeout(t); clearInterval(iv); };
  }, [online, outbox, flush]);

  const onTake = useCallback(async (contentId: string, block: BlockKey): Promise<TakeRow> => {
    if (!session) throw new Error("Sem sessão.");
    const t: PendingTake = { session: session.id, content: contentId, block, client_ref: crypto.randomUUID(), at: new Date().toISOString() };
    try {
      const row = await createTake(access, t);
      setSession((s) => s && { ...s, items: s.items.map((i) => (i.content_id === contentId ? { ...i, takes: [...i.takes, row] } : i)) });
      return row;
    } catch (e) {
      if (permanentError((e as { code?: string }).code)) throw e;
      setBox((l) => [...l, t]); // sem rede: fica no dispositivo e é reenviado com o mesmo client_ref
      return { id: t.client_ref, block_key: block, take_number: 0, status: "ok", selected: false, notes: null, version_id: null, session_id: t.session, created_label: null, created_at: t.at, pending: true };
    }
  }, [access, session, setBox]);

  const takesFor = useCallback((contentId: string): TakeRow[] => {
    const real = session?.items.find((i) => i.content_id === contentId)?.takes ?? [];
    const pend = outbox.filter((t) => t.content === contentId && t.session === session?.id).map<TakeRow>((t) => ({
      id: t.client_ref, block_key: t.block, take_number: 0, status: "ok", selected: false, notes: t.error ? `Não enviado: ${t.error}` : null,
      version_id: null, session_id: t.session, created_label: null, created_at: t.at, pending: true,
    }));
    return [...real, ...pend];
  }, [session, outbox]);

  const onTakeUpdate = useCallback(async (t: TakeRow, patch: { selected?: boolean; status?: "ok" | "discarded"; notes?: string }) => {
    await updateTake(access, t.id, patch);
    await load();
  }, [access, load]);

  const onRecorded = useCallback(async (contentId: string, recorded: boolean) => {
    await setProduction(access, contentId, recorded ? "recorded" : "not_started");
    await load();
  }, [access, load]);

  // ---------- progresso (retoma segura) ----------
  const prog = useRef<{ content: string; block: BlockKey | null; pct: number; sent: number; dirty: boolean } | null>(null);
  const onProgress = useCallback((content: string, block: BlockKey | null, pct: number) => {
    const prev = prog.current;
    prog.current = { content, block, pct, sent: prev?.sent ?? 0, dirty: true };
    try { localStorage.setItem(`tp.resume.${access.ws}.${date}`, JSON.stringify({ content, block, pct, at: Date.now() })); } catch {}
  }, [access.ws, date]);
  useEffect(() => {
    if (!session || session.closed_at) return;
    const iv = setInterval(() => {
      const p = prog.current;
      if (!p || !p.dirty || !navigator.onLine) return;
      p.dirty = false;
      saveProgress(access, session.id, p.content, p.block, p.pct).catch(() => { if (prog.current) prog.current.dirty = true; });
    }, 4000);
    return () => clearInterval(iv);
  }, [access, session]);

  // ---------- fila ----------
  const items = useMemo(() => session?.items ?? [], [session]);
  const playable = useMemo(() => items.filter((i) => !i.skipped && blocksOf(i.content).some((b) => !i.skipped_blocks.includes(b.key))), [items]);

  const saveQueue = useCallback(async (next: SessionItem[]) => {
    if (!session) return;
    setBusy(true);
    try {
      setSession(await setQueue(access, session.id, next.map((i) => ({ content_id: i.content_id, skipped: i.skipped, skipped_blocks: i.skipped_blocks }))));
      setError("");
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }, [access, session]);
  const move = (i: number, k: number) => {
    const j = i + k;
    if (j < 0 || j >= items.length) return;
    const next = [...items];
    [next[i], next[j]] = [next[j], next[i]];
    saveQueue(next);
  };
  const toggleSkip = (it: SessionItem) => saveQueue(items.map((x) => (x.content_id === it.content_id ? { ...x, skipped: !x.skipped } : x)));
  const toggleBlock = (it: SessionItem, b: BlockKey) =>
    saveQueue(items.map((x) => (x.content_id === it.content_id
      ? { ...x, skipped_blocks: x.skipped_blocks.includes(b) ? x.skipped_blocks.filter((y) => y !== b) : [...x.skipped_blocks, b] } : x)));

  const resume = useMemo(() => {
    if (!session) return null;
    let local: { content: string; block: BlockKey | null; pct: number; at: number } | null = null;
    try { local = JSON.parse(localStorage.getItem(`tp.resume.${access.ws}.${date}`) ?? "null"); } catch {}
    const server = session.last_content_id ? { content: session.last_content_id, block: session.last_block, pct: session.last_pct ?? 0, at: Date.parse(session.last_at ?? "") || 0 } : null;
    const r = local && (!server || local.at > server.at) ? local : server;
    if (!r) return null;
    const index = playable.findIndex((i) => i.content_id === r.content);
    if (index < 0 || playable[index].content.production_status === "recorded") return null;
    return { ...r, index, n: playable[index].content.n };
  }, [session, playable, access.ws, date]);

  const start = (index: number, extra?: { pct?: number; block?: BlockKey | null }) => { setView({ kind: "prompter", index, ...extra }); };
  const firstOpen = Math.max(0, playable.findIndex((i) => i.content.production_status !== "recorded"));

  const endSession = async () => {
    if (!session) return;
    if (!window.confirm("Terminar a sessão de gravação deste dia? Os takes ficam guardados.")) return;
    setBusy(true);
    try { await closeSession(access, session.id); router.push(`/guioes?date=${date}`); }
    catch (e) { setError((e as Error).message); setBusy(false); }
  };

  const settingsPanel = settings && (
    <TpSettings prefs={prefs} update={update} keysFor={keysFor} serverSync={mode === "user"} syncError={syncError} onClose={() => setSettings(false)} />
  );

  if (view.kind === "prompter") {
    return (
      <>
        <Prompter
          items={playable} start={view} prefs={prefs} update={update} keysFor={keysFor} canTake={canTake} takesFor={takesFor}
          online={online} pendingCount={outbox.filter((t) => !t.error).length}
          onTake={onTake} onTakeUpdate={onTakeUpdate} onRecorded={onRecorded} onProgress={onProgress}
          onSettings={() => setSettings(true)} onExit={() => { setView({ kind: "queue" }); load(); }}
        />
        {settingsPanel}
      </>
    );
  }

  const failed = outbox.filter((t) => t.error);
  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-black text-white">
      <div className="mx-auto flex max-w-3xl flex-col gap-4 px-4 pb-16 pt-6">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold">Teleprompter · {dayLabel(date)}</h1>
            <p className="text-sm text-neutral-400">
              {session ? `Sessão aberta por ${session.opened_label ?? "—"} · partilhada com os outros dispositivos deste cliente` : loading ? "A abrir a sessão…" : ""}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Btn label="‹ Dia" aria="Dia anterior" onClick={() => router.replace(`/teleprompter?date=${addDays(date, -1)}`)} />
            <Btn label="Dia ›" aria="Dia seguinte" onClick={() => router.replace(`/teleprompter?date=${addDays(date, 1)}`)} />
            <Btn label="Definições" onClick={() => setSettings(true)} />
            <Btn label="Sair" onClick={() => router.push(`/guioes?date=${date}`)} />
          </div>
        </header>

        {!online && <p role="status" className="rounded-xl border border-red-500/50 bg-red-950/80 px-4 py-3 text-sm">Sem ligação. Podes ler e marcar takes; ficam neste dispositivo e são enviados quando a ligação voltar.</p>}
        {outbox.some((t) => !t.error) && online && <p role="status" className="rounded-xl border border-amber-500/40 bg-amber-950/60 px-4 py-3 text-sm">A enviar {outbox.filter((t) => !t.error).length} takes guardados no dispositivo…</p>}
        {failed.length > 0 && (
          <div role="alert" className="rounded-xl border border-red-500/50 bg-red-950/80 px-4 py-3 text-sm">
            <p>{failed.length} take{failed.length > 1 ? "s" : ""} não {failed.length > 1 ? "foram aceites" : "foi aceite"} pelo servidor: {failed[0].error}</p>
            <button type="button" className="mt-2 rounded-md border border-red-400/50 px-3 py-1" onClick={() => setBox((l) => l.filter((t) => !t.error))}>Descartar estes takes</button>
          </div>
        )}
        {error && (
          <div role="alert" className="flex items-center gap-3 rounded-xl border border-red-500/50 bg-red-950/80 px-4 py-3 text-sm">
            <span className="flex-1">{error}</span>
            <button type="button" className="rounded-md border border-red-400/50 px-3 py-1" onClick={() => { setLoading(true); load(); }}>Tentar de novo</button>
          </div>
        )}
        {session?.require_approval && <p className="text-sm text-neutral-400">Neste cliente só entram na fila guiões aprovados.</p>}

        {loading && !session ? (
          <p className="text-neutral-400" aria-busy="true">A carregar a fila…</p>
        ) : session && items.length === 0 ? (
          <p className="text-neutral-300">Não há guiões para gravar neste dia. Os guiões rejeitados e arquivados não entram na fila.</p>
        ) : session ? (
          <>
            <div className="flex flex-wrap items-center gap-2">
              {resume && <Btn on label={`Retomar no guião ${resume.n}${resume.block ? ` · ${blockLabel(resume.block)}` : ""} (${Math.round(resume.pct * 100)}%)`} onClick={() => start(resume.index, { pct: resume.pct, block: resume.block })} />}
              <Btn on={!resume} label={playable.length ? `Começar no guião ${playable[firstOpen]?.content.n ?? ""}` : "Nada para ler"} disabled={!playable.length} onClick={() => start(firstOpen)} />
              <span className="text-sm text-neutral-400">{playable.length} na fila · {items.filter((i) => i.content.production_status === "recorded").length} gravados{busy ? " · a guardar…" : ""}</span>
            </div>
            <ol className="flex flex-col gap-2" aria-label="Fila de gravação">
              {items.map((it, i) => {
                const bl = blocksOf(it.content);
                const ok = it.takes.filter((t) => t.status === "ok").length;
                const rec = it.content.production_status === "recorded";
                const open = expanded === it.content_id;
                return (
                  <li key={it.content_id} data-item={it.content_id} className={cn("rounded-xl border border-neutral-800 bg-neutral-950 p-3", it.skipped && "opacity-50")}>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="w-8 text-right tabular-nums text-neutral-500">{it.content.n}</span>
                      <button type="button" className="min-w-0 flex-1 truncate text-left font-medium" onClick={() => setExpanded(open ? null : it.content_id)} aria-expanded={open}>
                        {it.content.hooks?.[0]?.text || it.content.tema || "Sem hook"}
                      </button>
                      {it.carried && <span className="rounded bg-neutral-800 px-2 py-0.5 text-xs">de {dayLabel(it.content.date).toLowerCase()}</span>}
                      {rec && <span className="rounded bg-emerald-900 px-2 py-0.5 text-xs text-emerald-100">gravado</span>}
                      {ok > 0 && <span className="rounded bg-neutral-800 px-2 py-0.5 text-xs">{ok} take{ok > 1 ? "s" : ""}</span>}
                      {it.skipped && <span className="rounded bg-neutral-800 px-2 py-0.5 text-xs">saltado</span>}
                      <span className="flex gap-1">
                        <Btn label="↑" aria={`Subir guião ${it.content.n}`} onClick={() => move(i, -1)} disabled={busy || i === 0} className="min-w-11" />
                        <Btn label="↓" aria={`Descer guião ${it.content.n}`} onClick={() => move(i, 1)} disabled={busy || i === items.length - 1} className="min-w-11" />
                        <Btn label={it.skipped ? "Incluir" : "Saltar"} onClick={() => toggleSkip(it)} disabled={busy} />
                        {!it.skipped && <Btn label="Ler" onClick={() => start(Math.max(0, playable.findIndex((x) => x.content_id === it.content_id)))} />}
                      </span>
                    </div>
                    {open && (
                      <div className="mt-3 flex flex-col gap-3 border-t border-neutral-800 pt-3 text-sm">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-neutral-400">Blocos:</span>
                          {bl.map((b) => {
                            const off = it.skipped_blocks.includes(b.key);
                            return (
                              <button key={b.key} type="button" aria-pressed={!off} disabled={busy} onClick={() => toggleBlock(it, b.key)}
                                className={cn("min-h-9 rounded-full border px-3 text-xs", off ? "border-neutral-700 text-neutral-500 line-through" : "border-amber-400/60 text-amber-200")}>
                                {b.label}
                              </button>
                            );
                          })}
                          <span className="text-xs text-neutral-500">(toca para saltar ou incluir)</span>
                        </div>
                        {it.takes.length > 0 && (
                          <p className="text-neutral-400">
                            Takes: {Array.from(new Set(it.takes.map((t) => t.block_key))).map((k) => {
                              const l = it.takes.filter((t) => t.block_key === k && t.status === "ok");
                              const sel = it.takes.find((t) => t.block_key === k && t.selected);
                              return `${blockLabel(k)} ${l.length}${sel ? ` (escolhido #${sel.take_number})` : ""}`;
                            }).join(" · ")}
                          </p>
                        )}
                        {canTake && rec && (
                          <div><Btn label="Desfazer gravado" onClick={() => onRecorded(it.content_id, false).catch((e: Error) => setError(e.message))} /></div>
                        )}
                      </div>
                    )}
                  </li>
                );
              })}
            </ol>
            <div className="flex flex-wrap gap-2 border-t border-neutral-800 pt-4">
              <Btn label="Terminar sessão" onClick={endSession} disabled={busy} />
              <span className="self-center text-xs text-neutral-500">O que não for gravado passa para o dia seguinte com os takes que já tem.</span>
            </div>
          </>
        ) : null}
      </div>
      {settingsPanel}
    </div>
  );
}

export default function TeleprompterPage() {
  return (
    <Suspense fallback={<div className="fixed inset-0 bg-black" />}>
      <WorkspaceGate need="recording.use">{(access) => <TeleprompterInner access={access} />}</WorkspaceGate>
    </Suspense>
  );
}
