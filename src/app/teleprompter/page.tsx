"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useGuioes } from "@/components/use-guioes";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { todayDubai, tpQueue } from "@/lib/data";
import { cn } from "@/lib/utils";

/*
 * Teleprompter: sempre preto e branco, de propósito. Só número, 3 hooks, separador e corpo.
 * Teclas: Espaço rola/para · ↑↓ velocidade · ←→ ou PageUp/PageDown guião · M espelho · +/- letra · Esc sai.
 * Ler até 80% NÃO marca gravado (AGENTS.md §6, PRD §20): ao avançar pergunta "Gravaste?" e só marca com confirmação.
 */
const store = {
  get<T>(k: string, d: T): T { try { const v = localStorage.getItem(k); return v == null ? d : (JSON.parse(v) as T); } catch { return d; } },
  set(k: string, v: unknown) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};

function Btn({ on, label, onClick, aria }: { on?: boolean; label: string; onClick: () => void; aria?: string }) {
  return (
    <button
      type="button"
      aria-label={aria ?? label}
      onClick={onClick}
      className={cn("min-h-11 min-w-11 rounded-xl border border-neutral-700 bg-neutral-900 px-3 font-semibold text-white", on && "border-amber-400 bg-amber-400 text-black")}
    >
      {label}
    </button>
  );
}

type Confirm = { id: string; n: number; then: "next" | "exit" };

function TeleprompterInner({ access }: { access: Access }) {
  const params = useSearchParams();
  const router = useRouter();
  const date = params.get("date") ?? todayDubai();
  const { all, loading, patch, caps } = useGuioes(access, date);
  const canWrite = caps.record;
  const queue = useMemo(() => tpQueue(all, date), [all, date]);

  // null = ainda não escolhido: começa no primeiro por gravar
  const [picked, setPicked] = useState<number | null>(null);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(() => store.get("tp.speed", 4));
  const [font, setFont] = useState(() => store.get("tp.font", 56));
  const [mirror, setMirror] = useState(() => store.get("tp.mirror", false));
  const [barVisible, setBarVisible] = useState(true);
  const [progress, setProgress] = useState(0);
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const acc = useRef(0);
  const last = useRef(0);
  const shownAt = useRef(0);
  const hideT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lock = useRef<WakeLockSentinel | null>(null);

  const firstOpen = useMemo(() => Math.max(0, queue.findIndex((g) => !g.gravado)), [queue]);
  const idx = picked ?? firstOpen;


  const cur = queue[idx];
  useEffect(() => { store.set("tp.speed", speed); }, [speed]);
  useEffect(() => { store.set("tp.font", font); }, [font]);
  useEffect(() => { store.set("tp.mirror", mirror); }, [mirror]);
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = 0;
    acc.current = 0;
    shownAt.current = performance.now();
  }, [idx]);

  // wake lock + ecrã inteiro
  useEffect(() => {
    (async () => { try { lock.current = await navigator.wakeLock?.request("screen"); } catch {} })();
    document.documentElement.requestFullscreen?.().catch(() => {});
    return () => { lock.current?.release().catch(() => {}); if (document.fullscreenElement) document.exitFullscreen().catch(() => {}); };
  }, []);

  // auto-scroll
  useEffect(() => {
    let raf = 0;
    const loop = (t: number) => {
      const el = scrollRef.current;
      if (playing && el) {
        const dt = last.current ? Math.min((t - last.current) / 1000, 0.1) : 0;
        acc.current += dt * speed * font * 0.09;
        if (acc.current >= 1) { const px = Math.floor(acc.current); el.scrollTop += px; acc.current -= px; }
      }
      last.current = t;
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, font]);

  const pct = () => { const el = scrollRef.current; if (!el) return 1; const max = el.scrollHeight - el.clientHeight; return max > 0 ? el.scrollTop / max : 1; };
  /** Se o guião foi lido até 80% e ainda não está gravado, pergunta antes de seguir. */
  const shouldAsk = useCallback(() => {
    const g = queue[idx];
    if (!g || g.gravado || !canWrite) return null;
    const el = scrollRef.current;
    const read = pct() >= 0.8 || (!!el && el.scrollHeight <= el.clientHeight && performance.now() - shownAt.current > 5000);
    return read ? g : null;
  }, [queue, idx, canWrite]);

  const step = useCallback((k: number) => {
    const j = idx + k;
    if (j < 0 || j >= queue.length) return;
    setPicked(j);
  }, [idx, queue.length]);

  const go = useCallback((k: number) => {
    if (k > 0) {
      const g = shouldAsk();
      if (g) { setPlaying(false); setConfirm({ id: g.id, n: g.n, then: "next" }); return; }
    }
    step(k);
  }, [shouldAsk, step]);

  const showBar = useCallback(() => {
    setBarVisible(true);
    if (hideT.current) clearTimeout(hideT.current);
    hideT.current = setTimeout(() => setBarVisible(false), 3000);
  }, []);
  useEffect(() => {
    hideT.current = setTimeout(() => setBarVisible(false), 3000);
    return () => { if (hideT.current) clearTimeout(hideT.current); };
  }, []);

  const exit = useCallback(() => {
    const g = shouldAsk();
    if (g) { setPlaying(false); setConfirm({ id: g.id, n: g.n, then: "exit" }); return; }
    router.push("/guioes");
  }, [shouldAsk, router]);

  const answer = useCallback(async (yes: boolean) => {
    const c = confirm;
    if (!c) return;
    setConfirm(null);
    if (yes) { try { await patch(c.id, { gravado: true }); } catch {} }
    if (c.then === "exit") router.push("/guioes");
    else step(1);
  }, [confirm, patch, router, step]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const k = e.key;
      if (confirm) {
        if (k === "Enter" || k === "s" || k === "S") { e.preventDefault(); answer(true); }
        else if (k === "Escape" || k === "n" || k === "N") { e.preventDefault(); answer(false); }
        return;
      }
      if (k === " ") { e.preventDefault(); setPlaying((p) => !p); showBar(); }
      else if (k === "ArrowUp") { e.preventDefault(); setSpeed((s) => Math.min(10, s + 1)); showBar(); }
      else if (k === "ArrowDown") { e.preventDefault(); setSpeed((s) => Math.max(1, s - 1)); showBar(); }
      else if (k === "ArrowRight" || k === "PageDown") { e.preventDefault(); go(1); }
      else if (k === "ArrowLeft" || k === "PageUp") { e.preventDefault(); go(-1); }
      else if (k === "Escape") { e.preventDefault(); exit(); }
      else if (k === "m" || k === "M") setMirror((m) => !m);
      else if (k === "+" || k === "=") setFont((f) => Math.min(96, f + 4));
      else if (k === "-") setFont((f) => Math.max(32, f - 4));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, exit, showBar, confirm, answer]);

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-black text-white" onPointerMove={showBar} onPointerDown={showBar}>
      <div className="fixed left-0 top-0 h-[3px] bg-amber-400 transition-[width]" style={{ width: queue.length ? `${((idx + Math.min(progress, 1)) / queue.length) * 100}%` : 0 }} />
      <div className="fixed right-4 top-3 text-sm tabular-nums text-neutral-500">{queue.length ? `guião ${idx + 1} de ${queue.length}` : ""}</div>
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-[6vw] [scrollbar-width:none]" onScroll={() => setProgress(pct())}>
        <div className={cn("mx-auto max-w-[1100px] py-[38vh] pb-[70vh] font-bold leading-[1.38]", mirror && "[transform:scaleX(-1)]")} style={{ fontSize: font }}>
          {loading ? (
            <p className="text-neutral-500">A carregar…</p>
          ) : !cur ? (
            <p>Não há guiões para gravar neste dia.</p>
          ) : (
            <>
              <div className="mb-[.8em] text-[.45em] font-normal text-neutral-500">{idx + 1}</div>
              {cur.hooks.map((h, i) => <p key={i} className="mb-[1.5em]">{h.text}</p>)}
              <hr className="mb-[1.3em] mt-[.4em] border-t-[3px] border-neutral-700" />
              {cur.corpo.split("\n").filter(Boolean).map((l, i) => <p key={i} className="mb-[.75em]">{l}</p>)}
            </>
          )}
        </div>
      </div>
      <div className="pointer-events-none fixed left-0 right-0 top-[34vh]"><div className="absolute left-[1.5vw] -top-[9px] border-[9px] border-transparent border-l-[14px] border-l-amber-400" /></div>
      {confirm && (
        <div role="dialog" aria-label="Confirmar gravação" className="fixed inset-x-0 bottom-28 z-10 mx-auto flex w-[min(92vw,34rem)] flex-wrap items-center justify-center gap-3 rounded-2xl border border-neutral-700 bg-neutral-950/95 p-4 text-center">
          <p className="w-full text-lg font-semibold">Gravaste o guião {confirm.n}?</p>
          <Btn label="Sim, marcar gravado" on onClick={() => answer(true)} />
          <Btn label="Ainda não" onClick={() => answer(false)} />
          <p className="w-full text-xs text-neutral-500">Enter = sim · Esc = não</p>
        </div>
      )}
      <div data-bar className={cn("fixed inset-x-0 bottom-0 flex flex-wrap items-center justify-center gap-2 bg-gradient-to-t from-black/95 via-black/80 to-transparent px-4 pb-[calc(12px+env(safe-area-inset-bottom,0px))] pt-6 transition-opacity", !barVisible && "pointer-events-none opacity-0")}>
        <Btn label="‹" aria="Guião anterior" onClick={() => go(-1)} />
        <Btn label={playing ? "Parar" : "Rolar"} on={playing} onClick={() => setPlaying((p) => !p)} />
        <Btn label="›" aria="Guião seguinte" onClick={() => go(1)} />
        <Btn label="−" aria="Mais devagar" onClick={() => setSpeed((s) => Math.max(1, s - 1))} />
        <span className="min-w-[4rem] text-center text-sm tabular-nums text-neutral-400">vel. {speed}</span>
        <Btn label="+" aria="Mais depressa" onClick={() => setSpeed((s) => Math.min(10, s + 1))} />
        <Btn label="A−" aria="Letra mais pequena" onClick={() => setFont((f) => Math.max(32, f - 4))} />
        <span className="min-w-[4rem] text-center text-sm tabular-nums text-neutral-400">{font} px</span>
        <Btn label="A+" aria="Letra maior" onClick={() => setFont((f) => Math.min(96, f + 4))} />
        <Btn label="Espelho" on={mirror} onClick={() => setMirror((m) => !m)} />
        {canWrite && cur && <Btn label="Gravado" on={cur.gravado} onClick={() => patch(cur.id, { gravado: !cur.gravado }).catch(() => {})} />}
        <Btn label="Sair" onClick={exit} />
      </div>
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
