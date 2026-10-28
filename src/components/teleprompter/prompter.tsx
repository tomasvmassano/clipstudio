"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { blockLabel, blocksOf, type BlockKey, type SessionItem, type TakeRow, type TpAction, type TpPrefs } from "@/lib/recording";
import { keyMap } from "@/components/teleprompter/use-prefs";
import { cn } from "@/lib/utils";

/*
 * Ecrã de leitura (FR-03-02/03/04/07). Preto e branco de propósito.
 * Ler até 80% NÃO marca gravado (AGENTS §6, PRD §20): fica como telemetria; marcar gravado pede confirmação.
 * Marcar takes não mexe no estado editorial nem no de produção (FR-03-06).
 */

type Props = {
  items: SessionItem[];
  start: { index: number; pct?: number; block?: BlockKey | null };
  prefs: TpPrefs;
  update: (p: Partial<TpPrefs> | ((p: TpPrefs) => Partial<TpPrefs>)) => void;
  keysFor: (a: TpAction) => string[];
  canTake: boolean;
  takesFor: (contentId: string) => TakeRow[];
  online: boolean;
  pendingCount: number;
  onTake: (contentId: string, block: BlockKey) => Promise<TakeRow>;
  onTakeUpdate: (take: TakeRow, patch: { selected?: boolean; status?: "ok" | "discarded"; notes?: string }) => Promise<void>;
  onRecorded: (contentId: string, recorded: boolean) => Promise<void>;
  onProgress: (contentId: string, block: BlockKey | null, pct: number) => void;
  onSettings: () => void;
  onExit: () => void;
};

function Btn({ on, label, onClick, aria, disabled }: { on?: boolean; label: string; onClick: () => void; aria?: string; disabled?: boolean }) {
  return (
    <button type="button" aria-label={aria ?? label} aria-pressed={on} onClick={onClick} disabled={disabled}
      className={cn("min-h-11 min-w-11 rounded-xl border border-neutral-700 bg-neutral-900 px-3 font-semibold text-white disabled:opacity-40",
        on && "border-amber-400 bg-amber-400 text-black")}>
      {label}
    </button>
  );
}

type Confirm = { id: string; n: number; takes: number; then: "next" | "exit" };
type WakeState = "off" | "on" | "unsupported" | "failed";

const fsEnabled = () => typeof document !== "undefined" && !!(document.fullscreenEnabled || (document as unknown as { webkitFullscreenEnabled?: boolean }).webkitFullscreenEnabled);

export function Prompter(p: Props) {
  const { items, prefs, update, canTake, takesFor } = p;
  // segue o guião pelo id: se outro dispositivo reordenar a fila, não salta para outro guião
  const [curId, setCurId] = useState<string | null>(items[Math.min(p.start.index, Math.max(0, items.length - 1))]?.content_id ?? null);
  const found = items.findIndex((i) => i.content_id === curId);
  const idx = found >= 0 ? found : 0;
  const [playing, setPlaying] = useState(false);
  const [barVisible, setBarVisible] = useState(true);
  const [progress, setProgress] = useState(0);
  const [block, setBlock] = useState<BlockKey | null>(null);
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  const [toast, setToast] = useState<{ text: string; error?: boolean } | null>(null);
  const [showTakes, setShowTakes] = useState(false);
  const [wake, setWake] = useState<WakeState>("off");
  const [isFs, setIsFs] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const blockRefs = useRef<Map<BlockKey, HTMLElement>>(new Map());
  const acc = useRef(0);
  const last = useRef(0);
  const shownAt = useRef(0);
  const hideT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const toastT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lock = useRef<WakeLockSentinel | null>(null);
  const pendingStart = useRef<{ pct?: number; block?: BlockKey | null } | null>({ pct: p.start.pct, block: p.start.block });

  const cur = items[idx];
  const blocks = useMemo(() => (cur ? blocksOf(cur.content).filter((b) => !cur.skipped_blocks.includes(b.key)) : []), [cur]);
  const takes = useMemo(() => (cur ? takesFor(cur.content_id) : []), [cur, takesFor]);
  const recorded = cur?.content.production_status === "recorded";

  const flash = useCallback((text: string, error = false) => {
    setToast({ text, error });
    if (toastT.current) clearTimeout(toastT.current);
    toastT.current = setTimeout(() => setToast(null), error ? 6000 : 2500);
  }, []);

  const readLine = () => (scrollRef.current?.clientHeight ?? 0) * 0.34;
  const pct = () => { const el = scrollRef.current; if (!el) return 1; const max = el.scrollHeight - el.clientHeight; return max > 0 ? el.scrollTop / max : 1; };
  const currentBlock = useCallback((): BlockKey | null => {
    const el = scrollRef.current;
    if (!el) return null;
    const y = el.scrollTop + readLine();
    let found: BlockKey | null = blocks[0]?.key ?? null;
    for (const b of blocks) { const n = blockRefs.current.get(b.key); if (n && n.offsetTop <= y + 4) found = b.key; }
    return found;
  }, [blocks]);

  const cbRef = useRef(currentBlock);
  useEffect(() => { cbRef.current = currentBlock; }, [currentBlock]);
  const curKey = cur?.content_id;

  // ao mudar de guião: posição inicial (retoma) ou topo
  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const ps = pendingStart.current;
    pendingStart.current = null;
    acc.current = 0;
    shownAt.current = performance.now();
    if (ps?.block && blockRefs.current.get(ps.block)) el.scrollTop = Math.max(0, blockRefs.current.get(ps.block)!.offsetTop - readLine());
    else if (ps?.pct) el.scrollTop = ps.pct * Math.max(0, el.scrollHeight - el.clientHeight);
    else el.scrollTop = 0;
    queueMicrotask(() => { setProgress(pct()); setBlock(cbRef.current()); });
  }, [curKey]);

  // wake lock: pedido com gesto (Rolar) e de novo quando o separador volta a ficar visível
  const requestWake = useCallback(async () => {
    if (!("wakeLock" in navigator)) { setWake("unsupported"); return; }
    try {
      lock.current = await navigator.wakeLock.request("screen");
      setWake("on");
      lock.current.addEventListener("release", () => setWake((w) => (w === "on" ? "off" : w)));
    } catch { setWake("failed"); }
  }, []);
  useEffect(() => {
    const onVis = () => { if (document.visibilityState === "visible" && playing) requestWake(); };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [playing, requestWake]);
  useEffect(() => () => { lock.current?.release().catch(() => {}); }, []);

  useEffect(() => {
    const onFs = () => setIsFs(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onFs);
    return () => { document.removeEventListener("fullscreenchange", onFs); if (document.fullscreenElement) document.exitFullscreen().catch(() => {}); };
  }, []);
  const toggleFs = useCallback(() => {
    if (!fsEnabled()) { flash("Este browser não deixa usar ecrã inteiro aqui. No iPhone/iPad: Partilhar → Adicionar ao ecrã principal.", true); return; }
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    else document.documentElement.requestFullscreen().catch(() => flash("O ecrã inteiro foi recusado pelo browser.", true));
  }, [flash]);

  const togglePlay = useCallback(() => {
    setPlaying((x) => { if (!x && wake !== "on") requestWake(); return !x; });
  }, [requestWake, wake]);

  // auto-scroll
  useEffect(() => {
    let raf = 0;
    const loop = (t: number) => {
      const el = scrollRef.current;
      if (playing && el) {
        const dt = last.current ? Math.min((t - last.current) / 1000, 0.1) : 0;
        acc.current += dt * prefs.speed * prefs.font * 0.09;
        if (acc.current >= 1) { const px = Math.floor(acc.current); el.scrollTop += px; acc.current -= px; }
      }
      last.current = t;
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [playing, prefs.speed, prefs.font]);

  // progresso para retoma (o pai faz throttle e guarda no servidor)
  const report = p.onProgress;
  useEffect(() => { if (cur) report(cur.content_id, block, progress); }, [cur, block, progress, report]);

  const shouldAsk = useCallback(() => {
    if (!cur || recorded || !canTake || !prefs.confirm_on_advance) return null;
    const el = scrollRef.current;
    const read = pct() >= 0.8 || (!!el && el.scrollHeight <= el.clientHeight && performance.now() - shownAt.current > 5000);
    return read || takes.length > 0 ? cur : null;
  }, [cur, recorded, canTake, prefs.confirm_on_advance, takes.length]);

  const step = useCallback((k: number) => {
    const j = idx + k;
    if (j < 0 || j >= items.length) return;
    setCurId(items[j].content_id);
  }, [idx, items]);

  const go = useCallback((k: number) => {
    if (k > 0) {
      const g = shouldAsk();
      if (g) { setPlaying(false); setConfirm({ id: g.content_id, n: g.content.n, takes: takes.filter((t) => t.status === "ok").length, then: "next" }); return; }
    }
    step(k);
  }, [shouldAsk, step, takes]);

  const jumpBlock = useCallback((k: number) => {
    const el = scrollRef.current;
    if (!el || !blocks.length) return;
    const i = Math.max(0, blocks.findIndex((b) => b.key === currentBlock()));
    const j = i + k;
    if (j < 0) { el.scrollTop = 0; return; }
    if (j >= blocks.length) { go(1); return; }
    const n = blockRefs.current.get(blocks[j].key);
    if (n) el.scrollTop = Math.max(0, n.offsetTop - readLine());
  }, [blocks, currentBlock, go]);

  const exit = useCallback(() => {
    const g = shouldAsk();
    if (g) { setPlaying(false); setConfirm({ id: g.content_id, n: g.content.n, takes: takes.filter((t) => t.status === "ok").length, then: "exit" }); return; }
    p.onExit();
  }, [shouldAsk, takes, p]);

  const answer = useCallback(async (yes: boolean) => {
    const c = confirm;
    if (!c) return;
    setConfirm(null);
    if (yes) { try { await p.onRecorded(c.id, true); flash(`Guião ${c.n} marcado como gravado.`); } catch (e) { flash(`Não ficou marcado: ${(e as Error).message}`, true); } }
    if (c.then === "exit") p.onExit();
    else step(1);
  }, [confirm, p, step, flash]);

  const markTake = useCallback(async () => {
    if (!cur || !canTake) return;
    const b = currentBlock() ?? blocks[0]?.key;
    if (!b) return;
    try {
      const t = await p.onTake(cur.content_id, b);
      flash(t.pending ? `${blockLabel(b)} · take ${t.take_number || "novo"} guardado no dispositivo (sem ligação, envio depois)` : `${blockLabel(b)} · take ${t.take_number} marcado`);
    } catch (e) { flash(`Take não marcado: ${(e as Error).message}`, true); }
  }, [cur, canTake, currentBlock, blocks, p, flash]);

  const showBar = useCallback(() => {
    setBarVisible(true);
    if (hideT.current) clearTimeout(hideT.current);
    hideT.current = setTimeout(() => setBarVisible(false), 3500);
  }, []);
  useEffect(() => {
    hideT.current = setTimeout(() => setBarVisible(false), 3500);
    return () => { if (hideT.current) clearTimeout(hideT.current); if (toastT.current) clearTimeout(toastT.current); };
  }, []);

  const map = useMemo(() => keyMap(p.keysFor), [p.keysFor]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tgt = e.target as HTMLElement | null;
      if (tgt && (tgt.tagName === "INPUT" || tgt.tagName === "TEXTAREA" || tgt.tagName === "SELECT" || tgt.isContentEditable)) return;
      if (confirm) {
        if (e.key === "Enter" || e.key === "s" || e.key === "S") { e.preventDefault(); answer(true); }
        else if (e.key === "Escape" || e.key === "n" || e.key === "N") { e.preventDefault(); answer(false); }
        return;
      }
      const a = map.get(e.key);
      if (!a) return;
      e.preventDefault();
      showBar();
      switch (a) {
        case "play": togglePlay(); break;
        case "faster": update((x) => ({ speed: x.speed + 1 })); break;
        case "slower": update((x) => ({ speed: x.speed - 1 })); break;
        case "next": go(1); break;
        case "prev": go(-1); break;
        case "next_block": jumpBlock(1); break;
        case "prev_block": jumpBlock(-1); break;
        case "take": markTake(); break;
        case "mirror": update((x) => ({ mirror_h: !x.mirror_h })); break;
        case "font_up": update((x) => ({ font: x.font + 4 })); break;
        case "font_down": update((x) => ({ font: x.font - 4 })); break;
        case "fullscreen": toggleFs(); break;
        case "exit": exit(); break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [map, confirm, answer, showBar, togglePlay, update, go, jumpBlock, markTake, toggleFs, exit]);

  const textColor = prefs.contrast === "ambar" ? "text-amber-300" : "text-white";
  const labelColor = prefs.contrast === "alto" ? "text-white" : "text-neutral-500";
  const takeCount = (k: BlockKey) => takes.filter((t) => t.block_key === k && t.status === "ok").length;
  const chosen = (k: BlockKey) => takes.find((t) => t.block_key === k && t.selected);

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-black text-white" onPointerMove={showBar} onPointerDown={showBar}>
      <div className="fixed left-0 top-0 z-10 h-[3px] bg-amber-400 transition-[width]" style={{ width: items.length ? `${((idx + Math.min(progress, 1)) / items.length) * 100}%` : 0 }} />
      <div className="fixed inset-x-3 top-2 z-10 flex items-center justify-between gap-3 text-sm tabular-nums text-neutral-500">
        <span className="flex items-center gap-3">
          {!p.online && <span role="status" className="rounded-md bg-red-900/80 px-2 py-0.5 text-red-100">Sem ligação{p.pendingCount ? ` · ${p.pendingCount} takes por enviar` : ""}</span>}
          {p.online && p.pendingCount > 0 && <span role="status" className="rounded-md bg-amber-900/70 px-2 py-0.5 text-amber-100">{p.pendingCount} takes por enviar</span>}
          {(wake === "unsupported" || wake === "failed") && <span className="text-amber-500">o ecrã pode apagar-se: este browser não o deixa manter ligado</span>}
        </span>
        <span>{cur ? `guião ${idx + 1} de ${items.length}${block ? ` · ${blockLabel(block)}` : ""}${recorded ? " · gravado" : ""}` : ""}</span>
      </div>

      <div className="relative flex-1 overflow-hidden" style={{ transform: `scale(${prefs.mirror_h ? -1 : 1}, ${prefs.mirror_v ? -1 : 1})` }}
        onDoubleClick={toggleFs}>
        <div ref={scrollRef} className="relative h-full overflow-y-auto [scrollbar-width:none]" style={{ paddingInline: `${prefs.margin}vw` }}
          onScroll={() => { setProgress(pct()); setBlock(currentBlock()); }}>
          <div className={cn("mx-auto max-w-[1100px] py-[34vh] pb-[70vh] font-bold", textColor, prefs.contrast === "alto" && "font-black")}
            style={{ fontSize: prefs.font, lineHeight: prefs.line_height }}>
            {!cur ? (
              <p>Não há guiões nesta fila.</p>
            ) : (
              <>
                <div className={cn("mb-[.8em] text-[.45em] font-normal", labelColor)}>{cur.content.n}{cur.content.tema ? ` · ${cur.content.tema}` : ""}</div>
                {blocks.map((b) => (
                  <section key={b.key} data-block={b.key} ref={(n) => { if (n) blockRefs.current.set(b.key, n); else blockRefs.current.delete(b.key); }}
                    className={cn("mb-[1.2em]", b.key === "body" && "border-t-[3px] border-neutral-700 pt-[.6em]")}>
                    <div className={cn("mb-[.3em] text-[.3em] font-semibold uppercase tracking-widest", labelColor)}>
                      {b.label}
                      {takeCount(b.key) > 0 && <span className="ml-3 normal-case tracking-normal">· {takeCount(b.key)} take{takeCount(b.key) > 1 ? "s" : ""}{chosen(b.key) ? ` · escolhido #${chosen(b.key)!.take_number}` : ""}</span>}
                    </div>
                    {b.text.split("\n").filter(Boolean).map((l, i) => <p key={i} className={cn("mb-[.6em]", b.key === "cta" && prefs.contrast !== "ambar" && "text-amber-300")}>{l}</p>)}
                  </section>
                ))}
              </>
            )}
          </div>
        </div>
        <div aria-hidden className="pointer-events-none absolute left-0 right-0 top-[34%]"><div className="absolute left-[1.5vw] -top-[9px] border-[9px] border-transparent border-l-[14px] border-l-amber-400" /></div>
      </div>

      {toast && (
        <div role={toast.error ? "alert" : "status"} className={cn("fixed inset-x-0 top-10 z-20 mx-auto flex w-[min(92vw,36rem)] items-center gap-3 rounded-xl border px-4 py-3 text-sm",
          toast.error ? "border-red-500/50 bg-red-950/95" : "border-neutral-700 bg-neutral-900/95")}>
          <span className="flex-1">{toast.text}</span>
          <button type="button" className="rounded-md border border-neutral-600 px-3 py-1" onClick={() => setToast(null)}>Fechar</button>
        </div>
      )}

      {confirm && (
        <div role="dialog" aria-label="Confirmar gravação" className="fixed inset-x-0 bottom-28 z-20 mx-auto flex w-[min(92vw,34rem)] flex-wrap items-center justify-center gap-3 rounded-2xl border border-neutral-700 bg-neutral-950/95 p-4 text-center">
          <p className="w-full text-lg font-semibold">Gravaste o guião {confirm.n}?</p>
          {confirm.takes > 0 && <p className="w-full text-sm text-neutral-400">{confirm.takes} take{confirm.takes > 1 ? "s" : ""} marcado{confirm.takes > 1 ? "s" : ""} neste guião.</p>}
          <Btn label="Sim, marcar gravado" on onClick={() => answer(true)} />
          <Btn label="Ainda não" onClick={() => answer(false)} />
          <p className="w-full text-xs text-neutral-500">Enter = sim · Esc = não</p>
        </div>
      )}

      {showTakes && cur && (
        <TakesPanel takes={takes} blocks={blocks.map((b) => b.key)} canEdit={canTake} onUpdate={async (t, patch) => {
          try { await p.onTakeUpdate(t, patch); } catch (e) { flash((e as Error).message, true); }
        }} onClose={() => setShowTakes(false)} />
      )}

      <div data-bar className={cn("fixed inset-x-0 bottom-0 z-10 flex flex-wrap items-center justify-center gap-2 bg-gradient-to-t from-black/95 via-black/80 to-transparent px-4 pb-[calc(12px+env(safe-area-inset-bottom,0px))] pt-6 transition-opacity",
        !barVisible && !confirm && "pointer-events-none opacity-0")}>
        <Btn label="‹" aria="Guião anterior" onClick={() => go(-1)} disabled={idx === 0} />
        <Btn label="⤒" aria="Bloco anterior" onClick={() => jumpBlock(-1)} />
        <Btn label={playing ? "Parar" : "Rolar"} on={playing} onClick={togglePlay} />
        <Btn label="⤓" aria="Bloco seguinte" onClick={() => jumpBlock(1)} />
        <Btn label="›" aria="Guião seguinte" onClick={() => go(1)} disabled={idx >= items.length - 1} />
        <Btn label="−" aria="Mais devagar" onClick={() => update((x) => ({ speed: x.speed - 1 }))} />
        <span className="min-w-[3.5rem] text-center text-sm tabular-nums text-neutral-400">vel. {prefs.speed}</span>
        <Btn label="+" aria="Mais depressa" onClick={() => update((x) => ({ speed: x.speed + 1 }))} />
        <Btn label="A−" aria="Letra mais pequena" onClick={() => update((x) => ({ font: x.font - 4 }))} />
        <Btn label="A+" aria="Letra maior" onClick={() => update((x) => ({ font: x.font + 4 }))} />
        <Btn label="↔" aria="Espelho horizontal" on={prefs.mirror_h} onClick={() => update((x) => ({ mirror_h: !x.mirror_h }))} />
        <Btn label="↕" aria="Espelho vertical" on={prefs.mirror_v} onClick={() => update((x) => ({ mirror_v: !x.mirror_v }))} />
        {canTake && cur && <Btn label={`Take${block ? ` ${blockLabel(block)}` : ""}`} aria="Marcar take do bloco atual" onClick={markTake} />}
        {cur && <Btn label={`Takes (${takes.filter((t) => t.status === "ok").length})`} aria="Ver takes" on={showTakes} onClick={() => setShowTakes((x) => !x)} />}
        {canTake && cur && <Btn label="Gravado" on={recorded} onClick={() => p.onRecorded(cur.content_id, !recorded).catch((e: Error) => flash(`Não ficou marcado: ${e.message}`, true))} />}
        <Btn label={isFs ? "Sair do ecrã inteiro" : "Ecrã inteiro"} onClick={toggleFs} />
        <Btn label="Definições" onClick={() => { setPlaying(false); p.onSettings(); }} />
        <Btn label="Fila" aria="Voltar à fila" onClick={exit} />
      </div>
    </div>
  );
}

function TakesPanel({ takes, blocks, canEdit, onUpdate, onClose }: {
  takes: TakeRow[]; blocks: BlockKey[]; canEdit: boolean;
  onUpdate: (t: TakeRow, patch: { selected?: boolean; status?: "ok" | "discarded"; notes?: string }) => Promise<void>; onClose: () => void;
}) {
  const [notes, setNotes] = useState<Record<string, string>>({});
  const keys = Array.from(new Set([...blocks, ...takes.map((t) => t.block_key)]));
  return (
    <div role="dialog" aria-label="Takes deste guião" className="fixed inset-y-0 left-0 z-30 flex w-[min(100vw,24rem)] flex-col border-r border-neutral-800 bg-neutral-950 text-white">
      <div className="flex items-center justify-between border-b border-neutral-800 px-4 py-3">
        <h2 className="text-base font-semibold">Takes</h2>
        <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-neutral-700 px-4 text-sm">Fechar</button>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 text-sm">
        <p className="pb-3 text-xs text-neutral-500">Escolhe o melhor take de cada bloco. Descartados ficam guardados. Isto não muda o estado do guião.</p>
        {keys.map((k) => {
          const list = takes.filter((t) => t.block_key === k);
          return (
            <div key={k} className="mb-4">
              <h3 className="mb-1 font-semibold">{blockLabel(k)}</h3>
              {list.length === 0 && <p className="text-neutral-500">Ainda sem takes.</p>}
              {list.map((t) => (
                <div key={t.id} className={cn("mb-2 rounded-lg border border-neutral-800 p-2", t.status === "discarded" && "opacity-50")}>
                  <div className="flex items-center justify-between gap-2">
                    <span>
                      Take {t.pending ? "(por enviar)" : t.take_number}
                      {t.selected && <b className="ml-2 text-amber-400">escolhido</b>}
                      {t.status === "discarded" && <span className="ml-2 text-neutral-400">descartado</span>}
                    </span>
                    {canEdit && !t.pending && (
                      <span className="flex gap-1">
                        {t.status === "ok" && !t.selected && <button type="button" className="min-h-9 rounded-md border border-neutral-700 px-2 text-xs" onClick={() => onUpdate(t, { selected: true })}>Escolher</button>}
                        {t.status === "ok"
                          ? <button type="button" className="min-h-9 rounded-md border border-neutral-700 px-2 text-xs" onClick={() => onUpdate(t, { status: "discarded" })}>Descartar</button>
                          : <button type="button" className="min-h-9 rounded-md border border-neutral-700 px-2 text-xs" onClick={() => onUpdate(t, { status: "ok" })}>Recuperar</button>}
                      </span>
                    )}
                  </div>
                  {canEdit && !t.pending ? (
                    <textarea aria-label={`Notas do take ${t.take_number}`} rows={2} maxLength={2000}
                      className="mt-2 w-full rounded-md border border-neutral-800 bg-neutral-900 p-2 text-xs"
                      placeholder="Notas (ex.: tropecei no fim, boa energia)"
                      value={notes[t.id] ?? t.notes ?? ""}
                      onChange={(e) => setNotes((n) => ({ ...n, [t.id]: e.target.value }))}
                      onBlur={() => { const v = notes[t.id]; if (v !== undefined && v !== (t.notes ?? "")) onUpdate(t, { notes: v }); }} />
                  ) : t.notes ? <p className="mt-1 text-xs text-neutral-400">{t.notes}</p> : null}
                </div>
              ))}
            </div>
          );
        })}
      </div>
    </div>
  );
}
