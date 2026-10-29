"use client";

import { useEffect, useState } from "react";
import { Loader2Icon, RotateCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { addChecklist, applyTemplate, fetchChecklist, fetchTemplates, fmtDue, toggleChecklist, type ChecklistItem, type Template } from "@/lib/tasks";

/** Checklist de produção de um guião e "Aplicar template" (FR-11-04). */
export function ContentChecklist({ access, contentId, onApplied }: { access: Access; contentId: string; onApplied?: () => void }) {
  const { can } = useSession();
  const canTick = can("production.update");
  const canApply = can("tasks.manage");
  const [items, setItems] = useState<ChecklistItem[] | null>(null);
  const [tpls, setTpls] = useState<Template[]>([]);
  const [pick, setPick] = useState("");
  const [label, setLabel] = useState("");
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchChecklist(access, contentId).then((x) => { if (alive) { setItems(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, contentId, rev]);
  useEffect(() => {
    if (!canApply) return;
    let alive = true;
    fetchTemplates(access).then((x) => { if (alive) setTpls(x.filter((t) => t.active)); }).catch(() => {});
    return () => { alive = false; };
  }, [access, canApply]);

  const run = async (f: () => Promise<ChecklistItem[]>) => {
    setBusy(true); setMsg("");
    try { setItems(await f()); } catch (e) { setMsg((e as Error).message); } finally { setBusy(false); }
  };

  if (err) return <p className="text-sm text-destructive">{err} <Button size="sm" variant="ghost" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></p>;
  if (!items) return <Skeleton className="h-16" />;
  const done = items.filter((i) => i.done).length;

  return (
    <section className="flex flex-col gap-2" aria-label="Checklist de produção">
      <h3 className="font-semibold">Checklist {items.length > 0 && <span className="font-normal text-muted-foreground">({done}/{items.length})</span>}</h3>
      {items.length === 0 && <p className="text-muted-foreground">Sem itens.{canApply && tpls.length > 0 ? " Aplica um template ou acrescenta à mão." : ""}</p>}
      <ul className="flex flex-col gap-1">
        {items.map((i) => (
          <li key={i.id}>
            <label className="flex items-start gap-2">
              <input type="checkbox" className="mt-0.5" checked={i.done} disabled={!canTick || busy} onChange={(e) => run(() => toggleChecklist(access, i.id, e.target.checked))} />
              <span className={i.done ? "text-muted-foreground line-through" : ""}>{i.label}
                {i.done && i.done_label && <span className="ml-1 text-xs no-underline">· {i.done_label}, {fmtDue(i.done_at)}</span>}
              </span>
            </label>
          </li>
        ))}
      </ul>
      {canTick && (
        <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); const l = label.trim(); if (l) { setLabel(""); run(() => addChecklist(access, contentId, l)); } }}>
          <Input aria-label="Novo item da checklist" value={label} maxLength={200} onChange={(e) => setLabel(e.target.value)} placeholder="Acrescentar item" />
          <Button size="sm" variant="outline" type="submit" disabled={busy || !label.trim()}>Acrescentar</Button>
        </form>
      )}
      {canApply && tpls.length > 0 && (
        <div className="flex gap-2">
          <select aria-label="Template a aplicar" className="h-9 min-w-0 flex-1 rounded-md border bg-background px-2 text-sm" value={pick} onChange={(e) => setPick(e.target.value)}>
            <option value="">Aplicar template…</option>
            {tpls.map((t) => <option key={t.id} value={t.id}>{t.name} ({t.items.length} tarefas)</option>)}
          </select>
          <Button size="sm" disabled={!pick || busy} onClick={async () => {
            setBusy(true); setMsg("");
            try {
              const r = await applyTemplate(access, pick, contentId);
              setItems(r.checklist); setPick("");
              setMsg(r.tasks_created ? `Criadas ${r.tasks_created} tarefas.` : "Este template já estava aplicado: nada duplicado.");
              onApplied?.();
            } catch (e) { setMsg((e as Error).message); } finally { setBusy(false); }
          }}>{busy && <Loader2Icon className="animate-spin" />} Aplicar</Button>
        </div>
      )}
      {msg && <p role="status" className="text-sm text-muted-foreground">{msg}</p>}
    </section>
  );
}
