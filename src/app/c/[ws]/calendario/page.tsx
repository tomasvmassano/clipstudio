"use client";

import { wsPath } from "@/lib/ws-path";
import { WsLink } from "@/components/ws-link";
import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ChevronLeftIcon, ChevronRightIcon, ClapperboardIcon, ListTodoIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WorkspaceGate } from "@/components/workspace-gate";
import { ContentChecklist } from "@/components/tasks/content-checklist";
import { ContentDetails } from "@/components/content-details";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import {
  dayInTz, dayTitle, fetchCalendar, monthTitle, nextProduction, PRODUCTION_LABEL, rangeFor, reschedule, setProductionStatus, shift,
  type CalContent, type CalendarData, type CalTask, type CalView,
} from "@/lib/calendar";
import { todayDubai } from "@/lib/data";
import { fromLocalInput, toLocalInput, updateTask } from "@/lib/tasks";
import { cn } from "@/lib/utils";
import { useFlags } from "@/lib/flags";
import { PubCalendar } from "@/components/pub/pub-calendar";

/*
 * Calendário (PRD M11 FR-11-01/02): guiões por dia com o estado de produção, tarefas pelo prazo e sessões de gravação.
 * Arrastar muda o dia (validado no servidor: nada para o passado, conflitos de edição recusados). Sem rato: "Mover para".
 */

const PROD_CLASS: Record<string, string> = {
  not_started: "border-border bg-background",
  scheduled: "border-sky-500/50 bg-sky-500/10",
  recording: "border-amber-500/50 bg-amber-500/10",
  recorded: "border-emerald-500/50 bg-emerald-500/10",
  editing: "border-violet-500/50 bg-violet-500/10",
  ready: "border-emerald-600 bg-emerald-600/20",
  published: "border-emerald-700 bg-emerald-700/20",
  cancelled: "border-border bg-muted text-muted-foreground line-through",
};

export default function CalendarioPage() {
  return (
    <Suspense fallback={<Skeleton className="h-96 w-full" />}>
      <WorkspaceGate need="calendar.read">{(access) => <CalendarLayers access={access} />}</WorkspaceGate>
    </Suspense>
  );
}

type Drag = { kind: "content"; item: CalContent } | { kind: "task"; item: CalTask };

/*
 * Camada de publicações (PUB-04, ADR-0036) atrás da flag pub.planning. Com a flag desligada (ou enquanto carrega) o
 * calendário é exatamente o de sempre.
 */
function CalendarLayers({ access }: { access: Access }) {
  const { mode } = useSession();
  const flags = useFlags(access.ws, access.token, mode !== "loading");
  const params = useSearchParams();
  const router = useRouter();
  if (!flags?.has("pub.planning")) return <Calendario access={access} />;
  const layer = params.get("l") === "pub" ? "pub" : "prod";
  const view = (["month", "week", "day"].includes(params.get("v") ?? "") ? params.get("v") : "week") as CalView;
  const anchor = /^\d{4}-\d{2}-\d{2}$/.test(params.get("d") ?? "") ? params.get("d")! : todayDubai();
  const go = (l: "pub" | "prod", v: CalView, d: string) => router.replace(wsPath(`/calendario?v=${v}&d=${d}${l === "pub" ? "&l=pub" : ""}`), { scroll: false });
  return (
    <div className="flex flex-col gap-4">
      <div role="tablist" aria-label="Camadas do calendário" className="inline-flex w-fit gap-1 rounded-lg border p-1">
        {([["prod", "Produção"], ["pub", "Publicações"]] as const).map(([k, label]) => (
          <button key={k} type="button" role="tab" aria-selected={layer === k}
            className={cn("rounded-md px-3 py-1 text-sm", layer === k ? "bg-primary text-primary-foreground" : "hover:bg-muted")}
            onClick={() => go(k, view, anchor)}>{label}</button>
        ))}
      </div>
      {layer === "pub"
        ? <PubCalendar access={access} view={view} anchor={anchor} today={todayDubai()} onNav={(v, d) => go("pub", v, d)} />
        : <Calendario access={access} />}
    </div>
  );
}

function Calendario({ access }: { access: Access }) {
  const { ws } = useSession();
  const tz = ws?.timezone ?? "Asia/Dubai";
  const params = useSearchParams();
  const router = useRouter();
  const view = (["month", "week", "day"].includes(params.get("v") ?? "") ? params.get("v") : "week") as CalView;
  const anchor = /^\d{4}-\d{2}-\d{2}$/.test(params.get("d") ?? "") ? params.get("d")! : todayDubai();
  const [show, setShow] = useState({ contents: true, tasks: true });
  const [data, setData] = useState<CalendarData | null>(null);
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const range = useMemo(() => rangeFor(view, anchor), [view, anchor]);

  useEffect(() => {
    let alive = true;
    fetchCalendar(access, range.from, range.to)
      .then((x) => { if (alive) { setData(x); setErr(""); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, range.from, range.to, rev]);

  const nav = (v: CalView, d: string) => router.replace(wsPath(`/calendario?v=${v}&d=${d}`), { scroll: false });
  const today = data?.today ?? todayDubai();
  const byDay = useMemo(() => {
    const m = new Map<string, { contents: CalContent[]; tasks: CalTask[]; takes: number; session: boolean }>();
    for (const d of range.days) m.set(d, { contents: [], tasks: [], takes: 0, session: false });
    for (const c of data?.contents ?? []) m.get(c.date)?.contents.push(c);
    for (const t of data?.tasks ?? []) m.get(dayInTz(t.due_at, tz))?.tasks.push(t);
    for (const s of data?.sessions ?? []) { const x = m.get(s.date); if (x) { x.takes += s.takes; x.session = true; } }
    return m;
  }, [data, range.days, tz]);

  const act = useCallback(async (f: () => Promise<unknown>, ok?: string) => {
    setBusy(true); setMsg("");
    try { await f(); if (ok) setMsg(ok); setRev((n) => n + 1); }
    catch (e) {
      const code = (e as { code?: string }).code;
      setMsg(code === "PT409" ? "Alguém mudou isto entretanto. Recarreguei o calendário: tenta de novo." : `Não ficou feito: ${(e as Error).message}`);
      setRev((n) => n + 1);
    }
    finally { setBusy(false); }
  }, []);

  const moveContent = (c: CalContent, day: string) => act(() => reschedule(access, c.id, day, c.lock_version), `Guião ${c.n} passou para ${dayTitle(day)}.`);
  const moveTask = (t: CalTask, day: string) => {
    const time = toLocalInput(t.due_at, tz).slice(11);
    return act(() => updateTask(access, t.id, { due_at: fromLocalInput(`${day}T${time}`, tz) }, t.lock_version), `Prazo de "${t.title}" passou para ${dayTitle(day)}.`);
  };
  const canDrop = (day: string) => !!drag && day >= today && (drag.kind === "content" ? data?.can.schedule : data?.can.tasks);
  const drop = (day: string) => {
    const d = drag; setDrag(null); setOver(null);
    if (!d || !canDrop(day)) return;
    if (d.kind === "content" && d.item.date !== day) moveContent(d.item, day);
    if (d.kind === "task" && dayInTz(d.item.due_at, tz) !== day) moveTask(d.item, day);
  };

  const opened = data?.contents.find((c) => c.id === open) ?? null;
  const title = view === "month" ? monthTitle(anchor) : view === "week" ? `${dayTitle(range.from)} a ${dayTitle(range.to)}` : dayTitle(anchor);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Calendário</h1>
          <p className="text-sm text-muted-foreground">Guiões por dia com o estado de produção, tarefas pelo prazo e sessões de gravação. {data?.can.schedule ? "Arrasta para mudar de dia." : ""}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <ToggleGroup value={[view]} onValueChange={(v) => { const x = (v as string[])[0] as CalView | undefined; if (x) nav(x, anchor); }} variant="outline" size="sm">
            <ToggleGroupItem value="day">Dia</ToggleGroupItem>
            <ToggleGroupItem value="week">Semana</ToggleGroupItem>
            <ToggleGroupItem value="month">Mês</ToggleGroupItem>
          </ToggleGroup>
          <Button size="sm" variant="outline" aria-label="Anterior" onClick={() => nav(view, shift(view, anchor, -1))}><ChevronLeftIcon /></Button>
          <Button size="sm" variant="outline" onClick={() => nav(view, todayDubai())}>Hoje</Button>
          <Button size="sm" variant="outline" aria-label="Seguinte" onClick={() => nav(view, shift(view, anchor, 1))}><ChevronRightIcon /></Button>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className="font-medium first-letter:uppercase">{title}</span>
        <label className="inline-flex items-center gap-1.5"><input type="checkbox" checked={show.contents} onChange={(e) => setShow({ ...show, contents: e.target.checked })} /> Guiões</label>
        <label className="inline-flex items-center gap-1.5"><input type="checkbox" checked={show.tasks} onChange={(e) => setShow({ ...show, tasks: e.target.checked })} /> Tarefas</label>
        {busy && <Loader2Icon className="size-4 animate-spin" aria-label="A guardar" />}
        <span className="ml-auto flex flex-wrap gap-2 text-xs text-muted-foreground">
          {(["scheduled", "recorded", "editing", "ready"] as const).map((s) => <span key={s} className={cn("rounded border px-1.5", PROD_CLASS[s])}>{PRODUCTION_LABEL[s]}</span>)}
          <span className="rounded border border-destructive px-1.5 text-destructive">Atrasado</span>
        </span>
      </div>

      {msg && (
        <Alert variant={msg.startsWith("Não") || msg.startsWith("Alguém") ? "destructive" : "default"}>
          <AlertDescription className="flex items-center justify-between gap-2">{msg}<Button size="sm" variant="ghost" onClick={() => setMsg("")}>Fechar</Button></AlertDescription>
        </Alert>
      )}
      {err ? (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ) : !data ? (
        <Skeleton className="h-96" />
      ) : (
        <div className={cn("grid gap-px overflow-hidden rounded-lg border bg-border",
          view === "day" ? "grid-cols-1" : "grid-cols-1 md:grid-cols-7")} role="grid" aria-label={`Calendário: ${title}`}>
          {view !== "day" && ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"].map((d) => (
            <div key={d} className="hidden bg-muted px-2 py-1 text-xs font-medium uppercase text-muted-foreground md:block" role="columnheader">{d}</div>
          ))}
          {range.days.map((day) => {
            const x = byDay.get(day)!;
            const outside = view === "month" && day.slice(0, 7) !== anchor.slice(0, 7);
            const empty = (!show.contents || x.contents.length === 0) && (!show.tasks || x.tasks.length === 0);
            return (
              <div key={day} role="gridcell" data-day={day} aria-label={dayTitle(day)}
                className={cn("flex min-h-28 flex-col gap-1 bg-background p-1.5", outside && "bg-muted/40", day === today && "ring-2 ring-inset ring-primary",
                  over === day && (canDrop(day) ? "bg-primary/10" : "bg-destructive/10"), view === "month" && empty && "max-md:hidden")}
                onDragOver={(e) => { if (drag) { e.preventDefault(); setOver(day); } }}
                onDragLeave={() => setOver((o) => (o === day ? null : o))}
                onDrop={(e) => { e.preventDefault(); drop(day); }}>
                <div className="flex items-center justify-between gap-1 text-xs">
                  <button type="button" className={cn("font-medium hover:underline", outside && "text-muted-foreground")} onClick={() => nav("day", day)}>
                    <span className="md:hidden">{dayTitle(day)}</span><span className="max-md:hidden">{Number(day.slice(8))}</span>
                  </button>
                  <span className="flex items-center gap-1 text-muted-foreground">
                    {x.session && <span title="Sessão de gravação" className="inline-flex items-center gap-0.5"><ClapperboardIcon className="size-3" />{x.takes}</span>}
                    {show.contents && x.contents.length > 0 && <span>{x.contents.length}</span>}
                  </span>
                </div>
                {show.contents && (view === "month" ? x.contents.slice(0, 4) : x.contents).map((c) => (
                  <button key={c.id} type="button" data-content={c.id}
                    draggable={!!data.can.schedule && !["published", "cancelled"].includes(c.production_status)}
                    onDragStart={() => setDrag({ kind: "content", item: c })} onDragEnd={() => { setDrag(null); setOver(null); }}
                    onClick={() => setOpen(c.id)}
                    className={cn("w-full truncate rounded border px-1.5 py-0.5 text-left text-xs", PROD_CLASS[c.production_status], c.late && "border-destructive text-destructive",
                      c.editorial_status === "rejected" && "opacity-50")}>
                    <span className="tabular-nums text-muted-foreground">{c.n}</span> {c.hook || c.tema || "Sem hook"}
                  </button>
                ))}
                {show.contents && view === "month" && x.contents.length > 4 && (
                  <button type="button" className="text-left text-xs text-muted-foreground hover:underline" onClick={() => nav("day", day)}>+ {x.contents.length - 4} guiões</button>
                )}
                {show.tasks && x.tasks.map((t) => (
                  <WsLink key={t.id} href={`/tarefas?task=${t.id}`} data-cal-task={t.id}
                    draggable={!!data.can.tasks && t.status !== "done"} onDragStart={() => setDrag({ kind: "task", item: t })} onDragEnd={() => { setDrag(null); setOver(null); }}
                    className={cn("flex items-center gap-1 truncate rounded px-1.5 py-0.5 text-xs hover:bg-muted", t.overdue && "text-destructive", t.status === "done" && "text-muted-foreground line-through")}>
                    <ListTodoIcon className="size-3 shrink-0" />
                    <span className="tabular-nums">{toLocalInput(t.due_at, tz).slice(11)}</span>
                    <span className="truncate">{t.title}</span>
                  </WsLink>
                ))}
              </div>
            );
          })}
        </div>
      )}

      {opened && data && (
        <ContentSheet access={access} onRefresh={() => setRev((n) => n + 1)} c={opened} today={today} data={data} busy={busy} onClose={() => setOpen(null)}
          onMove={(d) => moveContent(opened, d)}
          onProduction={(to) => act(() => setProductionStatus(access, opened.id, to), `Guião ${opened.n}: ${PRODUCTION_LABEL[to].toLowerCase()}.`)} />
      )}
    </div>
  );
}

function ContentSheet({ access, onRefresh, c, today, data, busy, onClose, onMove, onProduction }: {
  access: Access; onRefresh: () => void; c: CalContent; today: string; data: CalendarData; busy: boolean; onClose: () => void;
  onMove: (d: string) => void; onProduction: (to: CalContent["production_status"]) => void;
}) {
  const [d, setD] = useState(c.date >= today ? c.date : today);
  const moves = nextProduction(c.production_status, data.can);
  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>Guião {c.n}{c.tema ? ` · ${c.tema}` : ""}</SheetTitle>
          <SheetDescription>{dayTitle(c.date)}{c.late ? " · atrasado" : ""}</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6 text-sm">
          <div className="flex flex-wrap gap-2">
            <Badge variant="outline">{PRODUCTION_LABEL[c.production_status]}</Badge>
            {c.open_tasks > 0 && <Badge variant="secondary">{c.open_tasks} tarefa{c.open_tasks > 1 ? "s" : ""} aberta{c.open_tasks > 1 ? "s" : ""}</Badge>}
          </div>
          <ContentDetails access={access} id={c.id} date={c.date} />
          {moves.length > 0 && (
            <div className="flex flex-col gap-2">
              <h3 className="font-semibold">Produção</h3>
              <div className="flex flex-wrap gap-2">
                {moves.map((m) => <Button key={m.to + m.label} size="sm" variant={m.to === "cancelled" ? "ghost" : "outline"} disabled={busy} onClick={() => onProduction(m.to)}>{m.label}</Button>)}
              </div>
            </div>
          )}
          {data.can.schedule && !["published", "cancelled"].includes(c.production_status) && (
            <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); if (d !== c.date) onMove(d); }}>
              <h3 className="font-semibold">Mover para</h3>
              <div className="flex gap-2">
                <Input type="date" aria-label="Novo dia" min={today} value={d} onChange={(e) => setD(e.target.value)} />
                <Button size="sm" type="submit" disabled={busy || d === c.date || d < today}>Mover</Button>
              </div>
            </form>
          )}
          <ContentChecklist access={access} contentId={c.id} onApplied={onRefresh} />
          <div className="flex flex-wrap gap-3">
            <WsLink className="underline underline-offset-2" href={`/guioes?date=${c.date}`}>Abrir no dia dos guiões</WsLink>
            <WsLink className="underline underline-offset-2" href={`/teleprompter?date=${c.date}`}>Teleprompter deste dia</WsLink>
            {c.open_tasks > 0 && <WsLink className="underline underline-offset-2" href="/tarefas">Tarefas</WsLink>}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
