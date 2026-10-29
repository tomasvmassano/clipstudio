"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronDownIcon, InboxIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Skeleton } from "@/components/ui/skeleton";
import { DelegateDialog, QueueRow, selectCls, useQueue } from "@/components/ops/queue-parts";
import { CATEGORY_PLURAL, type QueueCategory, type QueueItem } from "@/lib/ops";
import { clientPath } from "@/lib/ws-path";

/*
 * Minha área de trabalho (OPS-03, FR-17-01): uma fila única com tudo o que precisa de mim, um item por objeto
 * (a tarefa, as notificações e a aprovação do mesmo guião juntam-se). Ver não aprova nem fecha; adiar volta a mostrar
 * à hora escolhida ou quando chega algo novo; passar exige que a pessoa possa trabalhar tarefas nesse cliente.
 */

type Filters = { ws: string; type: "" | QueueCategory; priority: "" | "urgent_high" | "normal_low"; due: "" | "overdue" | "today" | "week" | "none" };
const KEY = "ops.inbox.filters";
const EMPTY: Filters = { ws: "", type: "", priority: "", due: "" };
const TYPES: QueueCategory[] = ["task", "approval", "recording", "decision", "mention", "alert", "info"];

function loadFilters(): Filters {
  try { return { ...EMPTY, ...(JSON.parse(localStorage.getItem(KEY) ?? "{}") as Partial<Filters>) }; } catch { return EMPTY; }
}

function matchDue(i: QueueItem, due: Filters["due"], tz: string) {
  if (!due) return true;
  const d = i.due_at ? new Date(i.due_at) : i.day ? new Date(i.day + "T23:59:59Z") : null;
  if (due === "none") return !d;
  if (due === "overdue") return i.overdue;
  if (!d) return false;
  const day = (x: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(x);
  if (due === "today") return i.overdue || day(d) <= day(new Date());
  return d.getTime() <= Date.now() + 7 * 86400000;
}

export function WorkInbox({ ws, workspaces, tz }: { ws: string | null; workspaces: { id: string; name: string }[]; tz: string }) {
  const router = useRouter();
  const { data, err, reload } = useQueue(ws);
  const [f, setF] = useState<Filters>(loadFilters);
  const [actionErr, setActionErr] = useState("");
  const [delegating, setDelegating] = useState<QueueItem | null>(null);
  const set = (p: Partial<Filters>) => { const n = { ...f, ...p }; setF(n); try { localStorage.setItem(KEY, JSON.stringify(n)); } catch {} };
  const wsFilter = ws ?? f.ws;

  const ok = useMemo(() => (i: QueueItem) =>
    (!wsFilter || i.workspace_id === wsFilter)
    && (!f.type || i.categories.includes(f.type))
    && (!f.priority || (f.priority === "urgent_high" ? ["urgent", "high"].includes(i.priority) : ["normal", "low"].includes(i.priority)))
    && matchDue(i, f.due, tz), [wsFilter, f, tz]);
  const items = data?.items.filter(ok) ?? [];
  const snoozed = data?.snoozed.filter(ok) ?? [];
  const filtered = !!(f.type || f.priority || f.due || (!ws && f.ws));
  const open = (i: QueueItem) => router.push(clientPath(i.workspace_id, i.href));
  const disabledSome = data ? data.items.some((i) => !i.enabled) : false;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Minha área de trabalho</h1>
          <p className="text-sm text-muted-foreground">
            {ws ? "O que precisa de ti neste cliente." : "O que precisa de ti, em todos os clientes a que tens acesso."}
            {data ? ` ${data.counts.all} ite${data.counts.all === 1 ? "m" : "ns"}, ${data.counts.new} por ver.` : ""}
          </p>
        </div>
        <Button size="sm" variant="outline" onClick={reload} aria-label="Atualizar"><RotateCwIcon /></Button>
      </div>

      <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filtros">
        {!ws && workspaces.length > 1 && (
          <select aria-label="Cliente" className={selectCls} value={f.ws} onChange={(e) => set({ ws: e.target.value })}>
            <option value="">Todos os clientes</option>
            {workspaces.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        )}
        <select aria-label="Tipo" className={selectCls} value={f.type} onChange={(e) => set({ type: e.target.value as Filters["type"] })}>
          <option value="">Todos os tipos</option>
          {TYPES.map((t) => <option key={t} value={t}>{CATEGORY_PLURAL[t]}{data ? ` (${data.counts[t]})` : ""}</option>)}
        </select>
        <select aria-label="Prioridade" className={selectCls} value={f.priority} onChange={(e) => set({ priority: e.target.value as Filters["priority"] })}>
          <option value="">Qualquer prioridade</option>
          <option value="urgent_high">Urgente e alta</option>
          <option value="normal_low">Normal e baixa</option>
        </select>
        <select aria-label="Prazo" className={selectCls} value={f.due} onChange={(e) => set({ due: e.target.value as Filters["due"] })}>
          <option value="">Qualquer prazo</option>
          <option value="overdue">Atrasados</option>
          <option value="today">Até hoje</option>
          <option value="week">Próximos 7 dias</option>
          <option value="none">Sem prazo</option>
        </select>
        {filtered && <Button size="sm" variant="ghost" onClick={() => set(EMPTY)}>Limpar filtros</Button>}
      </div>

      {(err || actionErr) && (
        <Alert variant="destructive">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>{err ? `Não consegui carregar a tua caixa: ${err}` : actionErr}</span>
            <Button size="sm" variant="outline" onClick={() => { setActionErr(""); reload(); }}><RotateCwIcon /> Tentar de novo</Button>
          </AlertDescription>
        </Alert>
      )}
      {disabledSome && (
        <p className="text-xs text-muted-foreground">Em alguns clientes a área de trabalho ainda está em teste: os itens aparecem, mas sem ver, adiar nem passar.</p>
      )}

      {!data ? (
        !err && <div className="flex flex-col gap-2" aria-busy="true" aria-label="A carregar">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-16" />)}</div>
      ) : (
        <>
          {items.length === 0 ? (
            <Card><CardContent className="flex items-center gap-3 py-6 text-sm text-muted-foreground">
              <InboxIcon className="size-5" aria-hidden />
              {filtered ? "Nada com estes filtros." : "Está tudo tratado. Quando algo precisar de ti, aparece aqui."}
            </CardContent></Card>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Itens por tratar">
              {items.map((i) => (
                <QueueRow key={i.key} item={i} tz={tz} showWorkspace={!ws} onOpen={open} onChanged={reload} onError={setActionErr} onDelegate={setDelegating} />
              ))}
            </ul>
          )}
          {snoozed.length > 0 && (
            <Collapsible>
              <CollapsibleTrigger render={<Button size="sm" variant="ghost" className="self-start" />}>
                <ChevronDownIcon /> Adiados <Badge variant="secondary">{snoozed.length}</Badge>
              </CollapsibleTrigger>
              <CollapsibleContent>
                <ul className="mt-2 flex flex-col gap-2" aria-label="Itens adiados">
                  {snoozed.map((i) => (
                    <QueueRow key={i.key} item={i} tz={tz} showWorkspace={!ws} onOpen={open} onChanged={reload} onError={setActionErr} onDelegate={setDelegating} />
                  ))}
                </ul>
              </CollapsibleContent>
            </Collapsible>
          )}
        </>
      )}

      {delegating && (
        <DelegateDialog item={delegating} onClose={() => setDelegating(null)} onDone={() => { setDelegating(null); reload(); }} />
      )}
    </div>
  );
}
