"use client";

import { WsLink } from "@/components/ws-link";
import { useEffect, useState } from "react";
import { RotateCwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { Access } from "@/lib/access";
import { fetchGuioes } from "@/lib/data";
import { fetchTasks, fmtDue, STATUS_LABEL, type Task, type TaskScope } from "@/lib/tasks";
import { EDITORIAL_LABEL, type Guiao } from "@/lib/types";
import { useSession } from "@/components/session-provider";

/** O guião completo (hooks, corpo, CTA, notas) e as tarefas ligadas, para o detalhe do calendário. */
export function ContentDetails({ access, id, date }: { access: Access; id: string; date: string }) {
  const { can, ws } = useSession();
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [g, setG] = useState<Guiao | null>(null);
  const [tasks, setTasks] = useState<Task[] | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchGuioes(access, date, 0)
      .then((x) => { if (!alive) return; const f = x.find((y) => y.id === id) ?? null; setG(f); setErr(f ? "" : "Não encontrei este guião. Recarrega o calendário."); })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    if (can("tasks.read")) {
      fetchTasks(access, "all" as TaskScope, id).then((x) => { if (alive) setTasks(x); }).catch(() => { if (alive) setTasks([]); });
    }
    return () => { alive = false; };
  }, [access, id, date, rev, can]);

  if (err) return <p className="text-sm text-destructive">{err} <Button size="sm" variant="ghost" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></p>;
  if (!g) return <Skeleton className="h-40" />;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-2">
        <Badge variant="secondary">{EDITORIAL_LABEL[g.editorial_status]}</Badge>
        {g.formato && <Badge variant="outline">{g.formato}</Badge>}
      </div>
      <section className="flex flex-col gap-2" aria-label="Guião">
        {g.hooks.filter((h) => h.text?.trim()).map((h, i) => (
          <div key={i}>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Hook {i + 1}{h.mecanismo ? ` · ${h.mecanismo}` : ""}</p>
            <p className="font-medium">{h.text}</p>
          </div>
        ))}
        {g.corpo?.trim() && (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Corpo</p>
            <p className="max-h-72 overflow-y-auto whitespace-pre-wrap rounded-md border bg-muted/30 p-2">{g.corpo}</p>
          </div>
        )}
        {g.cta?.trim() && (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">CTA</p>
            <p>{g.cta}</p>
          </div>
        )}
        {g.notas?.trim() && (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Notas</p>
            <p className="whitespace-pre-wrap text-muted-foreground">{g.notas}</p>
          </div>
        )}
      </section>
      {tasks && (
        <section className="flex flex-col gap-1" aria-label="Tarefas do guião">
          <h3 className="font-semibold">Tarefas {tasks.length > 0 && <span className="font-normal text-muted-foreground">({tasks.filter((t) => t.status === "done").length}/{tasks.length} feitas)</span>}</h3>
          {tasks.length === 0 && <p className="text-muted-foreground">Sem tarefas ligadas.</p>}
          {tasks.map((t) => (
            <WsLink key={t.id} href={`/tarefas?task=${t.id}`} className="flex flex-wrap items-center gap-2 rounded-md px-1 py-0.5 hover:bg-muted">
              <span className={t.status === "done" || t.status === "cancelled" ? "text-muted-foreground line-through" : ""}>{t.title}</span>
              <Badge variant={t.status === "blocked" ? "destructive" : "outline"}>{STATUS_LABEL[t.status]}</Badge>
              <span className="text-xs text-muted-foreground">{t.assignee_email ?? "sem responsável"}{t.due_at ? ` · ${fmtDue(t.due_at, tz)}` : ""}</span>
            </WsLink>
          ))}
        </section>
      )}
    </div>
  );
}
