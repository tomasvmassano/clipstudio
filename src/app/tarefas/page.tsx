"use client";

import Link from "next/link";
import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { AlertTriangleIcon, BarChart3Icon, BotIcon, LayersIcon, CalendarClockIcon, Link2Icon, MessageSquareIcon, PlusIcon, RotateCwIcon, UserXIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { NewTaskDialog, TaskSheet } from "@/components/tasks/task-sheet";
import { RulesPanel } from "@/components/tasks/rules-panel";
import { TemplatesPanel } from "@/components/tasks/templates-panel";
import { WorkloadPanel } from "@/components/tasks/workload-panel";
import type { Access } from "@/lib/access";
import { fetchAssignees, fetchTasks, fmtDue, KIND_LABEL, PRIORITY_LABEL, STATUS_LABEL, type Assignee, type Task, type TaskScope } from "@/lib/tasks";
import { cn } from "@/lib/utils";

type Tab = TaskScope | "regras" | "templates" | "carga";

export default function TarefasPage() {
  return (
    <Suspense fallback={<Skeleton className="h-40 w-full" />}>
      <WorkspaceGate need="tasks.read">{(access) => <Tarefas access={access} />}</WorkspaceGate>
    </Suspense>
  );
}

function Tarefas({ access }: { access: Access }) {
  const { can, mode, ws } = useSession();
  const params = useSearchParams();
  const router = useRouter();
  const manage = can("tasks.manage");
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [tab, setTab] = useState<Tab>(() => (mode === "user" && can("tasks.work") ? "mine" : "open"));
  const [list, setList] = useState<Task[] | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [people, setPeople] = useState<Assignee[]>([]);
  const [creating, setCreating] = useState(false);
  const openId = params.get("task");

  useEffect(() => {
    if (tab === "regras" || tab === "templates" || tab === "carga") return;
    let alive = true;
    fetchTasks(access, tab)
      .then((x) => { if (alive) { setList(x); setErr(""); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, tab, rev]);
  useEffect(() => {
    let alive = true;
    fetchAssignees(access).then((x) => { if (alive) setPeople(x); }).catch(() => {});
    return () => { alive = false; };
  }, [access]);

  const reload = useCallback(() => setRev((n) => n + 1), []);
  const open = (id: string | null) => router.replace(id ? `/tarefas?task=${id}` : "/tarefas", { scroll: false });
  const counts = useMemo(() => ({
    blocked: (list ?? []).filter((t) => t.status === "blocked").length,
    overdue: (list ?? []).filter((t) => t.overdue).length,
  }), [list]);

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Tarefas</h1>
          <p className="text-sm text-muted-foreground">Quem faz o quê e até quando, ligado ao guião. As automações criam tarefas quando um guião muda de estado.</p>
        </div>
        {manage && <Button size="sm" onClick={() => setCreating(true)}><PlusIcon /> Nova tarefa</Button>}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <ToggleGroup value={[tab]} onValueChange={(v) => { const t = (v as string[])[0] as Tab | undefined; if (t) { setList(null); setTab(t); } }} variant="outline" size="sm">
          {mode === "user" && can("tasks.work") && <ToggleGroupItem value="mine">As minhas</ToggleGroupItem>}
          <ToggleGroupItem value="open">Abertas</ToggleGroupItem>
          {manage && <ToggleGroupItem value="unassigned"><UserXIcon /> Sem responsável</ToggleGroupItem>}
          <ToggleGroupItem value="done">Feitas</ToggleGroupItem>
          {manage && mode === "user" && <ToggleGroupItem value="regras"><BotIcon /> Automações</ToggleGroupItem>}
          {manage && mode === "user" && <ToggleGroupItem value="templates"><LayersIcon /> Templates</ToggleGroupItem>}
          {manage && <ToggleGroupItem value="carga"><BarChart3Icon /> Carga</ToggleGroupItem>}
        </ToggleGroup>
        {tab !== "regras" && tab !== "templates" && tab !== "carga" && list && (counts.overdue > 0 || counts.blocked > 0) && (
          <span className="text-sm text-muted-foreground">
            {counts.overdue > 0 && <span className="text-destructive">{counts.overdue} atrasada{counts.overdue > 1 ? "s" : ""}</span>}
            {counts.overdue > 0 && counts.blocked > 0 && " · "}
            {counts.blocked > 0 && <span>{counts.blocked} bloqueada{counts.blocked > 1 ? "s" : ""}</span>}
          </span>
        )}
      </div>

      {mode === "code" && (
        <Alert><AlertDescription>Com o código de equipa vês as tarefas mas não as alteras. Para teres tarefas tuas, pede um convite com o teu email.</AlertDescription></Alert>
      )}

      {tab === "regras" ? (
        <RulesPanel access={access} people={people} />
      ) : tab === "templates" ? (
        <TemplatesPanel access={access} people={people} />
      ) : tab === "carga" ? (
        <WorkloadPanel access={access} />
      ) : err ? (
        <Alert variant="destructive">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>{err}</span>
            <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
          </AlertDescription>
        </Alert>
      ) : !list ? (
        <div className="flex flex-col gap-2">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-16" />)}</div>
      ) : list.length === 0 ? (
        <Alert><AlertDescription>{emptyText(tab, manage)}</AlertDescription></Alert>
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Lista de tarefas">
          {list.map((t) => <TaskRow key={t.id} t={t} tz={tz} onOpen={() => open(t.id)} />)}
        </ul>
      )}

      {creating && (
        <NewTaskDialog access={access} people={people} tz={tz} onClose={() => setCreating(false)}
          onDone={(t) => { setCreating(false); reload(); open(t.id); }} />
      )}
      {openId && <TaskSheet access={access} id={openId} people={people} tz={tz} onClose={() => open(null)} onChange={reload} />}
    </div>
  );
}

function emptyText(tab: Tab, manage: boolean) {
  if (tab === "mine") return "Não tens tarefas abertas neste cliente.";
  if (tab === "unassigned") return "Todas as tarefas abertas têm responsável com acesso.";
  if (tab === "done") return "Nenhuma tarefa fechada nos últimos 60 dias.";
  return manage ? "Ainda não há tarefas abertas. Cria uma ou liga uma automação." : "Não há tarefas abertas.";
}

const PRIO_CLASS: Record<string, string> = { urgent: "bg-destructive text-white", high: "bg-amber-500/15 text-amber-700 dark:text-amber-300", normal: "", low: "text-muted-foreground" };

function TaskRow({ t, tz, onOpen }: { t: Task; tz: string; onOpen: () => void }) {
  return (
    <li data-task={t.id}>
      <Card className={cn("transition-colors hover:bg-muted/40", t.overdue && "border-destructive/50")}>
        <CardContent className="flex flex-wrap items-center gap-x-3 gap-y-1 py-3">
          <button type="button" onClick={onOpen} className="min-w-0 flex-1 text-left">
            <span className={cn("font-medium", (t.status === "done" || t.status === "cancelled") && "text-muted-foreground line-through")}>{t.title}</span>
            <span className="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
              <span>{KIND_LABEL[t.kind]}</span>
              {t.content && <span className="inline-flex items-center gap-1"><Link2Icon className="size-3" /> Guião {t.content.n} · {t.content.date.slice(8, 10)}/{t.content.date.slice(5, 7)}</span>}
              {t.rule_id && <span className="inline-flex items-center gap-1"><BotIcon className="size-3" /> automática</span>}
              {t.comments > 0 && <span className="inline-flex items-center gap-1"><MessageSquareIcon className="size-3" /> {t.comments}</span>}
              {t.open_deps > 0 && <span>à espera de {t.open_deps}</span>}
            </span>
          </button>
          {t.priority !== "normal" && <Badge variant="secondary" className={PRIO_CLASS[t.priority]}>{PRIORITY_LABEL[t.priority]}</Badge>}
          <Badge variant={t.status === "blocked" ? "destructive" : "outline"}>{STATUS_LABEL[t.status]}</Badge>
          {t.due_at && (
            <span className={cn("inline-flex items-center gap-1 text-xs tabular-nums", t.overdue ? "font-medium text-destructive" : "text-muted-foreground")}>
              <CalendarClockIcon className="size-3.5" /> {fmtDue(t.due_at, tz)}
            </span>
          )}
          <span className="inline-flex min-w-0 max-w-[14rem] items-center gap-1 truncate text-xs text-muted-foreground">
            {t.assignee_id && t.assignee_has_access === false && <AlertTriangleIcon className="size-3.5 text-amber-600" aria-label="Sem acesso" />}
            {t.assignee_email ?? "Sem responsável"}
          </span>
          {t.content && <Link className="text-xs underline-offset-2 hover:underline" href={`/guioes?date=${t.content.date}`}>Abrir guião</Link>}
        </CardContent>
      </Card>
    </li>
  );
}
