"use client";

import { useEffect, useState } from "react";
import { BotIcon, Loader2Icon, PlusIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import type { Access } from "@/lib/access";
import { EVENT_LABEL, fetchRules, KIND_LABEL, PRIORITY_LABEL, saveRule, type Assignee, type TaskKind, type TaskPriority, type TaskRule } from "@/lib/tasks";

const sel = "h-9 w-full rounded-md border bg-background px-2 text-sm";
type Draft = { id?: string; on_event: string; complete_on: string[]; kind: TaskKind; title: string; assignee_id: string; priority: TaskPriority; due_hours: string; active: boolean };
const EMPTY: Draft = { on_event: "script.submitted", complete_on: ["script.approved", "script.rejected"], kind: "review", title: "Rever guião {n}", assignee_id: "", priority: "normal", due_hours: "24", active: true };

/** Automações de handoff deste cliente (FR-17-05). Só aqui: não mudam outros clientes. */
export function RulesPanel({ access, people }: { access: Access; people: Assignee[] }) {
  const [rules, setRules] = useState<TaskRule[] | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let alive = true;
    fetchRules(access).then((x) => { if (alive) { setRules(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, rev]);

  const save = async (d: Draft) => {
    if (d.title.trim().length < 2) { setMsg("Escreve o título da tarefa."); return; }
    setBusy(true); setMsg("");
    try {
      await saveRule(access, { ...(d.id ? { id: d.id } : {}), on_event: d.on_event, complete_on: d.complete_on, kind: d.kind, title: d.title,
        assignee_id: d.assignee_id || null, priority: d.priority, due_hours: d.due_hours ? Number(d.due_hours) : null, active: d.active });
      setDraft(null); setRev((n) => n + 1);
    } catch (e) { setMsg((e as Error).message); }
    finally { setBusy(false); }
  };
  const toggle = async (r: TaskRule) => {
    setBusy(true); setMsg("");
    try { await saveRule(access, { id: r.id, active: !r.active }); setRev((n) => n + 1); }
    catch (e) { setMsg((e as Error).message); }
    finally { setBusy(false); }
  };

  if (err) return (
    <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
      <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
  );
  if (!rules) return <Skeleton className="h-32" />;

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-muted-foreground">
        Quando acontece um evento, cria uma tarefa para alguém; outro evento fecha-a. Repetir o mesmo evento na mesma versão não cria tarefas duplicadas.
        Usa <code>{"{n}"}</code>, <code>{"{tema}"}</code> e <code>{"{data}"}</code> no título.
      </p>
      {msg && <Alert variant="destructive"><AlertDescription>{msg}</AlertDescription></Alert>}
      {rules.length === 0 && !draft && <Alert><AlertDescription>Ainda não há automações neste cliente.</AlertDescription></Alert>}
      {rules.map((r) => (
        <Card key={r.id} data-rule={r.id} className={r.active ? "" : "opacity-60"}>
          <CardContent className="flex flex-wrap items-center gap-x-3 gap-y-1 py-3 text-sm">
            <BotIcon className="size-4 text-muted-foreground" />
            <span className="min-w-0 flex-1">
              <b>{EVENT_LABEL[r.on_event] ?? r.on_event}</b> → {KIND_LABEL[r.kind].toLowerCase()} “{r.title}” para {r.assignee_email ?? "ninguém"}
              {r.due_hours ? `, prazo ${r.due_hours} h` : ""}
              {r.complete_on.length > 0 && <span className="text-muted-foreground"> · fecha com: {r.complete_on.map((e) => EVENT_LABEL[e] ?? e).join(", ")}</span>}
            </span>
            {r.assignee_has_access === false && <Badge variant="destructive">responsável sem acesso</Badge>}
            {r.tasks_open > 0 && <Badge variant="outline">{r.tasks_open} abertas</Badge>}
            <Button size="sm" variant="outline" disabled={busy} onClick={() => setDraft({ id: r.id, on_event: r.on_event, complete_on: r.complete_on, kind: r.kind, title: r.title,
              assignee_id: r.assignee_id ?? "", priority: r.priority, due_hours: r.due_hours ? String(r.due_hours) : "", active: r.active })}>Editar</Button>
            <Button size="sm" variant="ghost" disabled={busy} onClick={() => toggle(r)}>{r.active ? "Desligar" : "Ligar"}</Button>
          </CardContent>
        </Card>
      ))}
      {draft ? (
        <Card>
          <CardContent className="flex flex-col gap-3 py-4 text-sm">
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="flex flex-col gap-1">Quando
                <select className={sel} value={draft.on_event} onChange={(e) => setDraft({ ...draft, on_event: e.target.value })}>
                  {Object.entries(EVENT_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1">Criar
                <select className={sel} value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value as TaskKind })}>
                  {Object.entries(KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1 sm:col-span-2">Título da tarefa
                <Input value={draft.title} maxLength={200} onChange={(e) => setDraft({ ...draft, title: e.target.value })} />
              </label>
              <label className="flex flex-col gap-1">Para
                <select className={sel} value={draft.assignee_id} onChange={(e) => setDraft({ ...draft, assignee_id: e.target.value })}>
                  <option value="">Sem responsável (fica em “Sem responsável”)</option>
                  {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1">Prazo (horas depois do evento)
                <Input type="number" min={1} max={2160} value={draft.due_hours} onChange={(e) => setDraft({ ...draft, due_hours: e.target.value })} />
              </label>
              <label className="flex flex-col gap-1">Prioridade
                <select className={sel} value={draft.priority} onChange={(e) => setDraft({ ...draft, priority: e.target.value as TaskPriority })}>
                  {Object.entries(PRIORITY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </label>
            </div>
            <fieldset className="flex flex-col gap-1">
              <legend className="mb-1">Fecha automaticamente quando</legend>
              <div className="flex flex-wrap gap-x-4 gap-y-1">
                {Object.entries(EVENT_LABEL).filter(([k]) => k !== draft.on_event).map(([k, v]) => (
                  <label key={k} className="inline-flex items-center gap-1.5">
                    <input type="checkbox" checked={draft.complete_on.includes(k)}
                      onChange={(e) => setDraft({ ...draft, complete_on: e.target.checked ? [...draft.complete_on, k] : draft.complete_on.filter((x) => x !== k) })} />
                    {v}
                  </label>
                ))}
              </div>
            </fieldset>
            <div className="flex gap-2">
              <Button size="sm" disabled={busy} onClick={() => save(draft)}>{busy && <Loader2Icon className="animate-spin" />} Guardar automação</Button>
              <Button size="sm" variant="ghost" onClick={() => setDraft(null)}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div><Button size="sm" variant="outline" onClick={() => setDraft(EMPTY)}><PlusIcon /> Nova automação</Button></div>
      )}
    </div>
  );
}
