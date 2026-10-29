"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangleIcon, CheckCircle2Icon, ChevronLeftIcon, ChevronRightIcon, Loader2Icon, PlusIcon, RotateCwIcon, Settings2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import type { Access } from "@/lib/access";
import { dayTitle, monthTitle, rangeFor, shift, type CalView } from "@/lib/calendar";
import { approveBatch, fetchPubCalendar, savePublication, type Publication, type PubCalendar as PubCalendarData } from "@/lib/pub";
import { moveToDay, PLATFORM_LABEL, PLATFORM_SHORT, PLATFORMS, PUBLISH_UNAVAILABLE, STATUS_LABEL, type Platform } from "@/lib/pub-rules";
import { fromLocalInput, toLocalInput } from "@/lib/tasks";
import { cn } from "@/lib/utils";
import { PubSheet } from "@/components/pub/pub-sheet";
import { PubRulesSheet } from "@/components/pub/pub-rules";

/*
 * Calendário de publicações (PRD PUB-04, ADR-0036): publicações planeadas por conta e plataforma. Arrastar muda o dia
 * (mantém a hora); conflitos e limites das APIs vêm do servidor. Nada aqui publica: aprovar autoriza o publicador futuro.
 */

const STATUS_CLASS: Record<string, string> = {
  planeada: "border-amber-500/60 bg-amber-500/10",
  aprovada: "border-emerald-500/60 bg-emerald-500/15",
  cancelada: "border-border bg-muted text-muted-foreground line-through",
};
const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";

type Props = { access: Access; view: CalView; anchor: string; today: string; onNav: (v: CalView, d: string) => void };

export function PubCalendar({ access, view, anchor, today: todayGuess, onNav }: Props) {
  const range = useMemo(() => rangeFor(view, anchor), [view, anchor]);
  const [data, setData] = useState<PubCalendarData | null>(null);
  const [err, setErr] = useState("");
  const [forbidden, setForbidden] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);
  const [account, setAccount] = useState("");
  const [platform, setPlatform] = useState<Platform | "">("");
  const [showCancelled, setShowCancelled] = useState(false);
  const [drag, setDrag] = useState<Publication | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const [open, setOpen] = useState<string | "new" | null>(null);
  const [newDay, setNewDay] = useState<string | null>(null);
  const [rules, setRules] = useState(false);
  const [confirmMove, setConfirmMove] = useState<{ p: Publication; day: string } | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());

  useEffect(() => {
    let alive = true;
    fetchPubCalendar(access, range.from, range.to)
      .then((x) => { if (alive) { setData(x); setErr(""); setForbidden(false); } })
      .catch((e: Error & { code?: string }) => { if (alive) { setErr(e.message); setForbidden(e.code === "42501"); } });
    return () => { alive = false; };
  }, [access, range.from, range.to, rev]);

  const tz = data?.timezone ?? "Asia/Dubai";
  const today = data?.today ?? todayGuess;
  const refresh = useCallback(() => setRev((n) => n + 1), []);
  const visible = useMemo(() => (data?.publications ?? []).filter((p) =>
    (!account || p.account_id === account) && (!platform || p.platform === platform) && (showCancelled || p.status !== "cancelada")), [data, account, platform, showCancelled]);
  const byDay = useMemo(() => {
    const m = new Map<string, Publication[]>();
    for (const d of range.days) m.set(d, []);
    for (const p of visible) m.get(p.local_day)?.push(p);
    return m;
  }, [visible, range.days]);
  const pending = visible.filter((p) => p.status === "planeada");
  const approvable = pending.filter((p) => p.can_approve);

  const move = async (p: Publication, day: string) => {
    setBusy(true); setMsg(null);
    try {
      const at = fromLocalInput(moveToDay(toLocalInput(p.scheduled_at, tz), day), tz);
      const r = await savePublication(access, p.id, { scheduled_at: at ?? undefined }, p.lock_version);
      setMsg({ text: `Publicação em @${r.account_handle} passou para ${dayTitle(day)} às ${r.local_time}.${p.status === "aprovada" ? " Precisa de nova aprovação." : ""}`, bad: false });
    } catch (e) {
      const code = (e as { code?: string }).code;
      setMsg({ text: code === "PT409" ? "Alguém mudou esta publicação entretanto. Recarreguei: tenta de novo." : `Não ficou feito: ${(e as Error).message}`, bad: true });
    } finally { setBusy(false); refresh(); }
  };
  const canDrop = (day: string) => !!drag && day >= today;
  const drop = (day: string) => {
    const p = drag; setDrag(null); setOver(null);
    if (!p || !canDrop(day) || p.local_day === day) return;
    if (p.status === "aprovada") setConfirmMove({ p, day }); else move(p, day);
  };
  const runBatch = async () => {
    const items = approvable.filter((p) => picked.has(p.id)).map((p) => ({ id: p.id, revision: p.revision }));
    if (!items.length) return;
    setBusy(true); setMsg(null);
    try {
      const r = await approveBatch(access, items);
      const okN = r.filter((x) => x.ok).length;
      const fails = r.filter((x) => !x.ok).map((x) => x.detail || x.error).filter(Boolean);
      setMsg({ text: `${okN} de ${r.length} aprovadas.${fails.length ? ` Não aprovadas: ${fails.join(" ")}` : ""}`, bad: fails.length > 0 });
      setPicked(new Set());
    } catch (e) { setMsg({ text: `Não ficou feito: ${(e as Error).message}`, bad: true }); }
    finally { setBusy(false); refresh(); }
  };

  const title = view === "month" ? monthTitle(anchor) : view === "week" ? `${dayTitle(range.from)} a ${dayTitle(range.to)}` : dayTitle(anchor);
  const opened = open && open !== "new" ? data?.publications.find((p) => p.id === open) ?? null : null;

  if (err && !data) {
    return forbidden ? (
      <Alert><AlertDescription>{err}</AlertDescription></Alert>
    ) : (
      <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{err}
        <Button size="sm" variant="outline" onClick={refresh}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Publicações</h1>
          <p className="text-sm text-muted-foreground">Publicações planeadas por conta e plataforma, com conflitos e limites das APIs. {data?.can.schedule ? "Arrasta para mudar de dia." : ""}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <ToggleGroup value={[view]} onValueChange={(v) => { const x = (v as string[])[0] as CalView | undefined; if (x) onNav(x, anchor); }} variant="outline" size="sm">
            <ToggleGroupItem value="day">Dia</ToggleGroupItem>
            <ToggleGroupItem value="week">Semana</ToggleGroupItem>
            <ToggleGroupItem value="month">Mês</ToggleGroupItem>
          </ToggleGroup>
          <Button size="sm" variant="outline" aria-label="Anterior" onClick={() => onNav(view, shift(view, anchor, -1))}><ChevronLeftIcon /></Button>
          <Button size="sm" variant="outline" onClick={() => onNav(view, today)}>Hoje</Button>
          <Button size="sm" variant="outline" aria-label="Seguinte" onClick={() => onNav(view, shift(view, anchor, 1))}><ChevronRightIcon /></Button>
        </div>
      </div>

      <Alert>
        <AlertDescription>
          <b>{data?.publish_unavailable_reason ?? PUBLISH_UNAVAILABLE}</b> Aqui planeia-se e aprova-se a versão e o destino de cada publicação; nada é publicado.
        </AlertDescription>
      </Alert>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="font-medium first-letter:uppercase">{title}</span>
        <select aria-label="Conta" className={selectCls} value={account} onChange={(e) => setAccount(e.target.value)}>
          <option value="">Todas as contas</option>
          {data?.accounts.map((a) => <option key={a.id} value={a.id}>@{a.handle} · {PLATFORM_LABEL[a.platform] ?? a.platform}</option>)}
        </select>
        <select aria-label="Plataforma" className={selectCls} value={platform} onChange={(e) => setPlatform(e.target.value as Platform | "")}>
          <option value="">Todas as plataformas</option>
          {PLATFORMS.map((p) => <option key={p} value={p}>{PLATFORM_LABEL[p]}</option>)}
        </select>
        <label className="inline-flex items-center gap-1.5"><input type="checkbox" checked={showCancelled} onChange={(e) => setShowCancelled(e.target.checked)} /> Canceladas</label>
        {busy && <Loader2Icon className="size-4 animate-spin" aria-label="A guardar" />}
        <span className="ml-auto flex flex-wrap gap-2">
          <Button size="sm" variant="outline" onClick={() => setRules(true)} disabled={!data}><Settings2Icon /> Regras e contas</Button>
          {data?.can.schedule && <Button size="sm" onClick={() => { setNewDay(null); setOpen("new"); }}><PlusIcon /> Planear publicação</Button>}
        </span>
      </div>

      {msg && (
        <Alert variant={msg.bad ? "destructive" : "default"}>
          <AlertDescription className="flex items-center justify-between gap-2">{msg.text}<Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button></AlertDescription>
        </Alert>
      )}
      {err && data && (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={refresh}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      )}

      {!data ? <Skeleton className="h-96" /> : (
        <>
          {data.accounts.length === 0 && (
            <Alert><AlertDescription>Este cliente ainda não tem contas de destino. {data.can.accounts ? "Acrescenta-as em Regras e contas." : "Pede a quem gere o cliente para as acrescentar."}</AlertDescription></Alert>
          )}
          <div className={cn("grid gap-px overflow-hidden rounded-lg border bg-border", view === "day" ? "grid-cols-1" : "grid-cols-1 md:grid-cols-7")}
            role="grid" aria-label={`Publicações: ${title}`}>
            {view !== "day" && ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"].map((d) => (
              <div key={d} className="hidden bg-muted px-2 py-1 text-xs font-medium uppercase text-muted-foreground md:block" role="columnheader">{d}</div>
            ))}
            {range.days.map((day) => {
              const list = byDay.get(day) ?? [];
              const outside = view === "month" && day.slice(0, 7) !== anchor.slice(0, 7);
              return (
                <div key={day} role="gridcell" data-pub-day={day} aria-label={dayTitle(day)}
                  className={cn("flex min-h-28 flex-col gap-1 bg-background p-1.5", outside && "bg-muted/40", day === today && "ring-2 ring-inset ring-primary",
                    over === day && (canDrop(day) ? "bg-primary/10" : "bg-destructive/10"), view === "month" && list.length === 0 && "max-md:hidden")}
                  onDragOver={(e) => { if (drag) { e.preventDefault(); setOver(day); } }}
                  onDragLeave={() => setOver((o) => (o === day ? null : o))}
                  onDrop={(e) => { e.preventDefault(); drop(day); }}>
                  <div className="flex items-center justify-between gap-1 text-xs">
                    <button type="button" className={cn("font-medium hover:underline", outside && "text-muted-foreground")} onClick={() => onNav("day", day)}>
                      <span className="md:hidden">{dayTitle(day)}</span><span className="max-md:hidden">{Number(day.slice(8))}</span>
                    </button>
                    {data.can.schedule && day >= today && (
                      <button type="button" className="rounded px-1 text-muted-foreground hover:bg-muted" aria-label={`Planear em ${dayTitle(day)}`}
                        onClick={() => { setNewDay(day); setOpen("new"); }}><PlusIcon className="size-3" /></button>
                    )}
                  </div>
                  {list.map((p) => {
                    const blocks = p.conflicts.some((c) => c.severity === "bloqueia");
                    const warns = p.conflicts.length > 0;
                    return (
                      <button key={p.id} type="button" data-pub={p.id}
                        draggable={data.can.schedule && p.status !== "cancelada"}
                        onDragStart={() => setDrag(p)} onDragEnd={() => { setDrag(null); setOver(null); }}
                        onClick={() => setOpen(p.id)}
                        aria-label={`${p.local_time} ${PLATFORM_LABEL[p.platform]} @${p.account_handle}, guião ${p.content_n}, ${STATUS_LABEL[p.status]}${blocks ? ", com conflito" : ""}`}
                        className={cn("flex w-full items-center gap-1 truncate rounded border px-1.5 py-0.5 text-left text-xs", STATUS_CLASS[p.status], blocks && "border-destructive")}>
                        <span className="tabular-nums">{p.local_time}</span>
                        <span className="font-semibold">{PLATFORM_SHORT[p.platform]}</span>
                        <span className="truncate">@{p.account_handle} · {p.content_n}{p.variant ? ` · ${p.variant.label}` : ""}</span>
                        {p.status === "aprovada" && <CheckCircle2Icon className="ml-auto size-3 shrink-0 text-emerald-500" aria-hidden />}
                        {warns && <AlertTriangleIcon className={cn("ml-auto size-3 shrink-0", blocks ? "text-destructive" : "text-amber-500")} aria-hidden />}
                      </button>
                    );
                  })}
                </div>
              );
            })}
          </div>

          <section aria-labelledby="pub-pending-title" className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 id="pub-pending-title" className="font-semibold">Por aprovar neste período ({pending.length})</h2>
              {approvable.length > 0 && (
                <Button size="sm" disabled={busy || ![...picked].some((id) => approvable.some((p) => p.id === id))} onClick={runBatch}>
                  Aprovar selecionadas
                </Button>
              )}
            </div>
            {pending.length === 0 ? <p className="text-sm text-muted-foreground">Nada à espera de aprovação neste período.</p> : (
              <ul className="flex flex-col divide-y rounded-lg border">
                {pending.map((p) => (
                  <li key={p.id} className="flex flex-wrap items-center gap-2 px-3 py-2 text-sm" data-pending={p.id}>
                    {approvable.length > 0 && (
                      <input type="checkbox" aria-label={`Selecionar ${p.local_day} ${p.local_time} @${p.account_handle}`} disabled={!p.can_approve}
                        checked={picked.has(p.id)} onChange={(e) => setPicked((s) => { const n = new Set(s); if (e.target.checked) n.add(p.id); else n.delete(p.id); return n; })} />
                    )}
                    <button type="button" className="text-left hover:underline" onClick={() => setOpen(p.id)}>
                      {dayTitle(p.local_day)} {p.local_time} · {PLATFORM_LABEL[p.platform]} @{p.account_handle} · guião {p.content_n} v{p.version_no}
                    </button>
                    <span className="ml-auto text-xs text-muted-foreground">
                      {p.missing.length && !p.missing.includes("qualquer") ? `Falta: ${p.missing.join(" e ")}` : ""}
                      {p.conflicts.some((c) => c.severity === "bloqueia") ? " · com conflito" : ""}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}

      {data && open && (
        <PubSheet access={access} data={data} pub={opened} defaultDay={newDay ?? (today > anchor ? today : anchor)}
          onClose={() => setOpen(null)} onChanged={(text) => { if (text) setMsg({ text, bad: false }); refresh(); }} />
      )}
      {data && rules && <PubRulesSheet access={access} data={data} onClose={() => setRules(false)} onChanged={refresh} />}
      {confirmMove && (
        <Dialog open onOpenChange={(v) => { if (!v) setConfirmMove(null); }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Mudar uma publicação aprovada?</DialogTitle>
              <DialogDescription>Passar para {dayTitle(confirmMove.day)} muda o destino aprovado. A aprovação deixa de valer e é precisa uma aprovação nova.</DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button variant="ghost" onClick={() => setConfirmMove(null)}>Cancelar</Button>
              <Button onClick={() => { const c = confirmMove; setConfirmMove(null); move(c.p, c.day); }}>Mudar e pedir nova aprovação</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}
