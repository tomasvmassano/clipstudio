"use client";

import { useEffect, useState } from "react";
import { AlertTriangleIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { Access } from "@/lib/access";
import { fetchWorkload, setWipLimit, type Workload } from "@/lib/tasks";
import { cn } from "@/lib/utils";

/** Carga por pessoa neste cliente (TEAM-08, FR-17-08). O limite só avisa; nunca impede atribuir. */
export function WorkloadPanel({ access }: { access: Access }) {
  const [w, setW] = useState<Workload | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [limit, setLimit] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let alive = true;
    fetchWorkload(access).then((x) => { if (alive) { setW(x); setLimit(x.wip_limit ? String(x.wip_limit) : ""); setErr(""); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, rev]);

  if (err) return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
    <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  if (!w) return <Skeleton className="h-32" />;

  const max = Math.max(1, ...w.people.map((p) => p.open), w.wip_limit ?? 0);
  return (
    <div className="flex flex-col gap-3">
      <form className="flex flex-wrap items-end gap-2 text-sm" onSubmit={async (e) => {
        e.preventDefault(); setMsg("");
        try { setW(await setWipLimit(access, limit ? Number(limit) : null)); } catch (x) { setMsg((x as Error).message); }
      }}>
        <label className="flex flex-col gap-1">Limite de tarefas abertas por pessoa
          <Input type="number" min={1} max={100} className="w-28" value={limit} onChange={(e) => setLimit(e.target.value)} placeholder="sem limite" />
        </label>
        <Button size="sm" variant="outline" type="submit">Guardar limite</Button>
        <span className="text-xs text-muted-foreground">Acima do limite aparece um aviso; atribuir continua possível.</span>
      </form>
      {msg && <Alert variant="destructive"><AlertDescription>{msg}</AlertDescription></Alert>}
      {w.unassigned > 0 && <p className="text-sm text-amber-700 dark:text-amber-300">{w.unassigned} tarefa{w.unassigned > 1 ? "s" : ""} aberta{w.unassigned > 1 ? "s" : ""} sem responsável com acesso.</p>}
      {w.people.length === 0 ? (
        <Alert><AlertDescription>Ninguém tem tarefas atribuídas neste cliente.</AlertDescription></Alert>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Pessoa</TableHead><TableHead className="w-1/3">Abertas</TableHead><TableHead>Em curso</TableHead>
              <TableHead>Bloqueadas</TableHead><TableHead>Atrasadas</TableHead><TableHead>Próximos 7 dias</TableHead><TableHead>Feitas (7 dias)</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {w.people.map((p) => (
              <TableRow key={p.user_id} data-person={p.email}>
                <TableCell className="font-medium">
                  <span className="inline-flex items-center gap-1">{p.email}{!p.has_access && <span className="text-xs text-amber-600">(sem acesso)</span>}</span>
                </TableCell>
                <TableCell>
                  <span className="flex items-center gap-2">
                    <span className="h-2 flex-1 overflow-hidden rounded bg-muted">
                      <span className={cn("block h-full rounded", p.over_limit ? "bg-destructive" : "bg-primary")} style={{ width: `${(p.open / max) * 100}%` }} />
                    </span>
                    <span className="tabular-nums">{p.open}</span>
                    {p.over_limit && <AlertTriangleIcon className="size-4 text-destructive" aria-label="Acima do limite" />}
                  </span>
                </TableCell>
                <TableCell className="tabular-nums">{p.doing}</TableCell>
                <TableCell className="tabular-nums">{p.blocked}</TableCell>
                <TableCell className={cn("tabular-nums", p.overdue > 0 && "font-medium text-destructive")}>{p.overdue}</TableCell>
                <TableCell className="tabular-nums">{p.due_7d}</TableCell>
                <TableCell className="tabular-nums text-muted-foreground">{p.done_7d}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
