"use client";

import { useCallback, useEffect, useState } from "react";
import { CalendarClockIcon, CheckIcon, ClockIcon, EyeIcon, Loader2Icon, PlayIcon, UserRoundPlusIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Textarea } from "@/components/ui/textarea";
import { actOnItem, CATEGORY_LABEL, delegateTask, fetchMyQueue, fmtWhen, REASON_LABEL, snoozeOptions, type Queue, type QueueItem } from "@/lib/ops";
import { fetchAssignees, updateTask, PRIORITY_LABEL, type Assignee } from "@/lib/tasks";
import { cn } from "@/lib/utils";

export const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";

/** Fila pessoal do servidor; `rev` força nova leitura. Erros ficam visíveis com nova tentativa (nunca spinner infinito). */
export function useQueue(ws: string | null, enabled = true) {
  const [data, setData] = useState<Queue | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    fetchMyQueue(ws).then((q) => { if (alive) { setData(q); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [ws, enabled, rev]);
  const reload = useCallback(() => setRev((n) => n + 1), []);
  return { data, err, reload };
}

const PRIORITY_VARIANT: Record<string, "destructive" | "secondary" | "outline"> = { urgent: "destructive", high: "secondary", normal: "outline", low: "outline" };

/** Uma linha da fila: abre o objeto; ações ver, adiar, passar, começar e concluir conforme o servidor deixa. */
export function QueueRow({ item, tz, showWorkspace, compact, onOpen, onChanged, onError, onDelegate }: {
  item: QueueItem; tz: string; showWorkspace: boolean; compact?: boolean;
  onOpen: (i: QueueItem) => void; onChanged: () => void; onError: (m: string) => void; onDelegate?: (i: QueueItem) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const run = async (what: string, fn: () => Promise<unknown>) => {
    setBusy(what); onError("");
    try { await fn(); onChanged(); } catch (e) { onError((e as Error).message); } finally { setBusy(null); }
  };
  const access = { ws: item.workspace_id, token: null };
  const reasons = item.reasons.filter((r) => REASON_LABEL[r]).map((r) => REASON_LABEL[r]);
  const when = item.due_at ? fmtWhen(item.due_at, tz) : item.day ? `${item.day.slice(8, 10)}/${item.day.slice(5, 7)}` : "";
  return (
    <li data-queue-item={item.key} className={cn("flex flex-col gap-2 rounded-md border p-2 sm:flex-row sm:items-center", !item.seen && "border-primary/40 bg-muted/40")}>
      <button type="button" className="min-w-0 flex-1 rounded-sm text-left outline-none focus-visible:ring-2 focus-visible:ring-ring" onClick={() => onOpen(item)}>
        <span className="flex flex-wrap items-center gap-1.5">
          {!item.seen && <span className="size-2 shrink-0 rounded-full bg-primary" aria-label="Novo" />}
          <span className={cn("text-sm", !item.seen && "font-medium")}>{item.title}</span>
          {item.categories.map((c) => <Badge key={c} variant={c === "alert" ? "destructive" : "outline"} className="text-[11px]">{CATEGORY_LABEL[c]}</Badge>)}
          {item.priority !== "normal" && <Badge variant={PRIORITY_VARIANT[item.priority]} className="text-[11px]">{PRIORITY_LABEL[item.priority]}</Badge>}
          {item.unread > 1 && <Badge variant="secondary" className="text-[11px]">{item.unread} por ler</Badge>}
        </span>
        <span className="mt-0.5 block truncate text-xs text-muted-foreground">
          {[showWorkspace ? item.workspace : null, reasons.join(", "), item.detail].filter(Boolean).join(" · ")}
        </span>
        {(when || item.snoozed_until) && (
          <span className={cn("mt-0.5 inline-flex items-center gap-1 text-xs", item.overdue ? "text-destructive" : "text-muted-foreground")}>
            <CalendarClockIcon className="size-3.5" aria-hidden />
            {item.snoozed_until ? `Adiado até ${fmtWhen(item.snoozed_until, tz)}` : `${item.overdue ? "Atrasado desde" : item.due_at ? "Prazo" : "Dia"} ${when}`}
          </span>
        )}
      </button>
      {!compact && item.enabled && (
        <div className="flex flex-wrap items-center gap-1">
          {item.can.start && (
            <Button size="sm" variant="outline" disabled={!!busy} onClick={() => run("start", () => updateTask(access, item.task!.id, { status: "doing" }, item.task!.lock_version))}>
              {busy === "start" ? <Loader2Icon className="animate-spin" /> : <PlayIcon />} Começar
            </Button>
          )}
          {item.can.complete && (
            <Button size="sm" variant="outline" disabled={!!busy} onClick={() => run("done", () => updateTask(access, item.task!.id, { status: "done" }, item.task!.lock_version))}>
              {busy === "done" ? <Loader2Icon className="animate-spin" /> : <CheckIcon />} Concluir
            </Button>
          )}
          {item.can.ack && !item.seen && (
            <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => run("ack", () => actOnItem(item.key, "ack"))} aria-label={`Marcar como visto: ${item.title}`}>
              {busy === "ack" ? <Loader2Icon className="animate-spin" /> : <EyeIcon />} Visto
            </Button>
          )}
          {item.can.snooze && (item.snoozed_until ? (
            <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => run("unsnooze", () => actOnItem(item.key, "unsnooze"))}>
              {busy === "unsnooze" ? <Loader2Icon className="animate-spin" /> : <ClockIcon />} Mostrar já
            </Button>
          ) : (
            <DropdownMenu>
              <DropdownMenuTrigger render={<Button size="sm" variant="ghost" disabled={!!busy} aria-label={`Adiar: ${item.title}`} />}>
                {busy === "snooze" ? <Loader2Icon className="animate-spin" /> : <ClockIcon />} Adiar
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuLabel>Voltar a mostrar</DropdownMenuLabel>
                {snoozeOptions(tz).map((o) => (
                  <DropdownMenuItem key={o.label} onClick={() => run("snooze", () => actOnItem(item.key, "snooze", o.until))}>{o.label}</DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          ))}
          {item.can.delegate && onDelegate && (
            <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => onDelegate(item)}>
              <UserRoundPlusIcon /> {item.task?.mine ? "Passar" : "Atribuir"}
            </Button>
          )}
        </div>
      )}
    </li>
  );
}

/** Passar uma tarefa: só aparecem pessoas que podem trabalhar tarefas neste cliente (o servidor volta a verificar). */
export function DelegateDialog({ item, onClose, onDone }: { item: QueueItem; onClose: () => void; onDone: () => void }) {
  const [people, setPeople] = useState<Assignee[] | null>(null);
  const [loadErr, setLoadErr] = useState("");
  const [to, setTo] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let alive = true;
    fetchAssignees({ ws: item.workspace_id, token: null })
      .then((p) => { if (alive) { setPeople(p); setLoadErr(""); } })
      .catch((e: Error) => { if (alive) setLoadErr(e.message); });
    return () => { alive = false; };
  }, [item.workspace_id, tick]);
  const submit = async () => {
    if (!to || !item.task) return;
    setBusy(true); setErr("");
    try { await delegateTask(item.task.id, to, note.trim() || null, item.task.lock_version); onDone(); }
    catch (e) { setErr((e as Error).message); setBusy(false); }
  };
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{item.task?.mine ? "Passar a tarefa" : "Atribuir a tarefa"}</DialogTitle>
          <DialogDescription>{item.title} · {item.workspace}. Quem recebe é avisado na caixa de entrada.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          {loadErr ? (
            <p role="alert" className="flex flex-wrap items-center gap-2 text-sm text-destructive">{loadErr}
              <Button size="sm" variant="outline" onClick={() => setTick((n) => n + 1)}>Tentar de novo</Button></p>
          ) : (
            <label className="flex flex-col gap-1 text-sm">Para quem
              <select className={selectCls} value={to} disabled={!people} onChange={(e) => setTo(e.target.value)}>
                <option value="">{people ? "Escolhe a pessoa" : "A carregar..."}</option>
                {people?.map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
              </select>
            </label>
          )}
          <label className="flex flex-col gap-1 text-sm">Nota (opcional)
            <Textarea rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Ex.: falta só a legenda final" />
          </label>
          {item.task?.status === "doing" && <p className="text-xs text-muted-foreground">A tarefa volta a &quot;Por fazer&quot;: quem recebe ainda não começou.</p>}
          {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={submit} disabled={busy || !to}>{busy && <Loader2Icon className="animate-spin" />} Confirmar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
