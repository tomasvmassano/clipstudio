"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { PlayIcon, RotateCcwIcon, RadioIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { TeamCode } from "@/components/team-code";
import { useSession } from "@/components/session-provider";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { fetchGuioes, todayDubai } from "@/lib/data";
import { AGENTS, agentById, buildSimulation, fetchRun, fetchRuns, simulateRun, subscribeAgents, type AgentEvent, type RunRow } from "@/lib/agents";
import { cn } from "@/lib/utils";

const STEP_MS = 1500; // ritmo da reprodução: os eventos chegam em rajada, a sala mostra-os um a um

type Live = { speaking: string | null; to: string | null; bubble: Record<string, { text: string; status: string; at: number }>; done: Set<string> };
const empty = (): Live => ({ speaking: null, to: null, bubble: {}, done: new Set() });

export default function AgentesPage() {
  return <WorkspaceGate need="agents.read">{(access) => <Sala access={access} />}</WorkspaceGate>;
}

function Sala({ access }: { access: Access }) {
  const { can, mode } = useSession();
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [log, setLog] = useState<AgentEvent[]>([]);
  const [live, setLive] = useState<Live>(empty);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const queue = useRef<AgentEvent[]>([]);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const logEnd = useRef<HTMLDivElement>(null);

  const play = useCallback((e: AgentEvent) => {
    setLog((l) => [...l.slice(-199), e]);
    setLive((s) => {
      const done = new Set(s.done);
      if (e.status === "done") done.add(e.agent);
      return {
        speaking: e.agent,
        to: e.to_agent,
        bubble: { ...s.bubble, [e.agent]: { text: e.message ?? "", status: e.status, at: Date.now() } },
        done,
      };
    });
  }, []);

  // um evento a cada STEP_MS
  useEffect(() => {
    timer.current = setInterval(() => {
      const e = queue.current.shift();
      if (e) play(e);
      else setLive((s) => (s.speaking ? { ...s, speaking: null, to: null } : s));
    }, STEP_MS);
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [play]);

  const loadRuns = useCallback(async () => {
    try { const r = await fetchRuns(access); setRuns(r); return r; } catch (e) { setMsg((e as Error).message); return [] as RunRow[]; }
  }, [access]);
  useEffect(() => {
    let alive = true;
    fetchRuns(access).then((r) => { if (alive) setRuns(r); }).catch((e: Error) => { if (alive) setMsg(e.message); });
    return () => { alive = false; };
  }, [access]);

  // tempo real (só com login; no modo código a sala mostra a corrida ao terminar)
  const live_ = mode === "user";
  useEffect(() => {
    const unsub = subscribeAgents(access, (e) => {
      queue.current.push(e);
      queue.current.sort((x, y) => x.id - y.id);
      if (e.status === "done" && e.agent === "aprendiz") setTimeout(loadRuns, 1000);
    });
    return () => { unsub?.(); };
  }, [access, loadRuns]);

  useEffect(() => { logEnd.current?.scrollIntoView({ block: "nearest" }); }, [log]);

  const replay = async (runId: string) => {
    queue.current = [];
    setLog([]);
    setLive(empty());
    try { queue.current = await fetchRun(access, runId); } catch (e) { setMsg((e as Error).message); }
  };

  const simulate = async () => {
    setBusy(true); setMsg("");
    try {
      const gs = await fetchGuioes(access, todayDubai(), 0);
      setLog([]); setLive(empty()); queue.current = [];
      await simulateRun(access, buildSimulation(gs));
      if (!live_) {
        const r = await loadRuns();
        if (r[0]) queue.current = await fetchRun(access, r[0].run_id);
      }
    } catch (e) { setMsg((e as Error).message); }
    finally { setBusy(false); }
  };

  const sp = agentById(live.speaking);
  const to = agentById(live.to);

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Sala dos agentes</h1>
          <p className="text-sm text-muted-foreground">Cada passo do motor aparece aqui em tempo real. O ensaio testa a sala sem inventar resultados e fica marcado como ensaio.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <TeamCode />
          {can("agents.rehearse") && <Button size="sm" disabled={busy} onClick={simulate}><PlayIcon /> Ensaiar a sala</Button>}
        </div>
      </div>

      {msg && <Alert variant="destructive"><AlertDescription>{msg}</AlertDescription></Alert>}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
        {/* a sala */}
        <Card className="overflow-hidden dark:bg-transparent">
          <CardContent className="p-0">
            <div className="relative aspect-[16/9] w-full min-h-[420px] bg-[radial-gradient(circle_at_1px_1px,var(--border)_1px,transparent_0)] [background-size:22px_22px]">
              <svg className="pointer-events-none absolute inset-0 size-full" viewBox="0 0 100 100" preserveAspectRatio="none">
                {sp && to && (
                  <line key={`${sp.id}-${to.id}-${log.length}`} x1={sp.x} y1={sp.y} x2={to.x} y2={to.y}
                    stroke={sp.cor} strokeWidth={0.5} strokeDasharray="1.5 1.5" vectorEffect="non-scaling-stroke"
                    className="animate-[dash_1s_linear_infinite]" style={{ strokeWidth: 2 }} />
                )}
              </svg>
              {AGENTS.map((a) => {
                const on = live.speaking === a.id;
                const target = live.to === a.id;
                const b = live.bubble[a.id];
                return (
                  <div key={a.id} className="absolute flex w-[9.5rem] -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1 text-center" style={{ left: `${a.x}%`, top: `${a.y}%` }}>
                    {on && b?.text && (
                      <div className="absolute bottom-[calc(100%+4px)] z-10 w-56 rounded-xl border bg-popover px-3 py-2 text-left text-xs leading-snug text-popover-foreground shadow-lg">
                        {b.status === "think" && <span className="mr-1 text-muted-foreground">a pensar…</span>}
                        {b.text}
                      </div>
                    )}
                    <div
                      className={cn(
                        "relative grid size-14 place-items-center rounded-2xl border-2 bg-card text-lg font-bold transition-transform duration-300",
                        on && "scale-110",
                        target && "scale-105",
                      )}
                      style={{ borderColor: on || target ? a.cor : "var(--border)", color: a.cor, boxShadow: on ? `0 0 24px ${a.cor}66` : undefined }}
                    >
                      {a.nome.slice(0, 2)}
                      {on && b?.status === "think" && <span className="absolute -right-1 -top-1 size-3 animate-ping rounded-full" style={{ background: a.cor }} />}
                      {live.done.has(a.id) && !on && <span className="absolute -bottom-1 -right-1 grid size-4 place-items-center rounded-full bg-emerald-600 text-[9px] text-white">✓</span>}
                    </div>
                    <div className="text-xs font-semibold">{a.nome}</div>
                    <div className="text-[10px] leading-tight text-muted-foreground">{a.papel}</div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* registo */}
        <div className="flex flex-col gap-4">
          <Card className="dark:bg-transparent">
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-base"><RadioIcon className="size-4 text-emerald-500" /> Conversa</CardTitle>
              <CardDescription>{log.length ? `${log.length} mensagens` : "À espera da próxima corrida."}</CardDescription>
            </CardHeader>
            <CardContent className="max-h-[420px] overflow-y-auto pr-2">
              <ol className="flex flex-col gap-2 text-xs">
                {log.map((e) => {
                  const a = agentById(e.agent); const t = agentById(e.to_agent);
                  return (
                    <li key={e.id} className="leading-snug">
                      <span className="font-semibold" style={{ color: a?.cor }}>{a?.nome ?? e.agent}</span>
                      {t && <span className="text-muted-foreground"> → {t.nome}</span>}
                      {e.slot != null && <span className="ml-1 text-muted-foreground">#{e.slot}</span>}
                      <div className={cn("text-muted-foreground", e.status === "error" && "text-destructive", e.status === "done" && "text-emerald-600 dark:text-emerald-400")}>{e.message}</div>
                    </li>
                  );
                })}
                <div ref={logEnd} />
              </ol>
            </CardContent>
          </Card>

          <Card className="dark:bg-transparent">
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Corridas</CardTitle>
              <CardDescription>Carrega para rever uma corrida passada.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-1.5">
              {runs.length === 0 && <p className="text-xs text-muted-foreground">Ainda não houve corridas. O motor real escreve aqui quando correr com a chave.</p>}
              {runs.map((r) => (
                <button key={r.run_id} onClick={() => replay(r.run_id)} className="flex items-center justify-between gap-2 rounded-md border px-2.5 py-1.5 text-left text-xs hover:bg-muted">
                  <span className="tabular-nums">{new Date(r.created_at).toLocaleString("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Dubai" })}</span>
                  <span className="flex items-center gap-1.5">
                    {r.simulated && <Badge variant="outline" className="text-[10px]">ensaio</Badge>}
                    <span className="text-muted-foreground">{r.n} passos</span>
                    <RotateCcwIcon className="size-3 text-muted-foreground" />
                  </span>
                </button>
              ))}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
