"use client";

import { clientPath } from "@/lib/ws-path";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { BellIcon, CalendarClockIcon, CheckCheckIcon, ClipboardCheckIcon, ListTodoIcon, RotateCwIcon, UserXIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { fetchInbox, fmtDue, markRead, STATUS_LABEL, type Inbox } from "@/lib/tasks";
import { cn } from "@/lib/utils";

/*
 * Caixa de entrada pessoal (FR-17-01): notificações, as minhas tarefas, aprovações pendentes e tarefas sem dono,
 * de todos os clientes a que tenho acesso agora. Marcar lido não aprova nem fecha nada.
 */

const FILTER_KEY = "inbox.ws";

export default function CaixaPage() {
  const { mode, wsRequested } = useSession();
  // na agência (/caixa) não há cliente aberto: a caixa junta todos; dentro de um cliente passa pela porta do cliente
  if (!wsRequested && mode === "user") return <Caixa />;
  return <WorkspaceGate>{() => <Caixa />}</WorkspaceGate>;
}

function Caixa() {
  const { mode, workspaces, wsRequested } = useSession();
  const router = useRouter();
  const [data, setData] = useState<Inbox | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  // dentro de um cliente a caixa mostra só esse cliente; na agência, todos (ou o filtro guardado)
  const [saved, setSaved] = useState<string>(() => { try { return localStorage.getItem(FILTER_KEY) ?? ""; } catch { return ""; } });
  const wsFilter = wsRequested ?? saved;

  useEffect(() => {
    if (mode !== "user") return;
    let alive = true;
    fetchInbox().then((x) => { if (alive) { setData(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [mode, rev]);

  const pick = (v: string) => { setSaved(v); try { localStorage.setItem(FILTER_KEY, v); } catch {} };
  const go = useCallback((ws: string, path: string) => { router.push(clientPath(ws, path)); }, [router]);
  const f = useMemo(() => {
    if (!data) return null;
    const ok = (w: string) => !wsFilter || w === wsFilter;
    return {
      notifications: data.notifications.filter((n) => ok(n.workspace_id)),
      tasks: data.tasks.filter((t) => ok(t.workspace_id)),
      approvals: data.approvals.filter((a) => ok(a.workspace_id)),
      unassigned: data.unassigned.filter((u) => ok(u.workspace_id)),
    };
  }, [data, wsFilter]);
  const unread = f?.notifications.filter((n) => !n.read_at) ?? [];

  if (mode === "code") {
    return <Alert><AlertDescription>A caixa de entrada é pessoal: precisa de uma conta com o teu email. Com o código de equipa usa as páginas de Guiões e Tarefas.</AlertDescription></Alert>;
  }

  const read = async (ids: string[] | null) => {
    try { await markRead(ids); setRev((n) => n + 1); } catch (e) { setErr((e as Error).message); }
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Caixa de entrada</h1>
          <p className="text-sm text-muted-foreground">{wsRequested ? "O que precisa de ti neste cliente." : "O que precisa de ti, em todos os clientes a que tens acesso."}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {!wsRequested && workspaces.length > 1 && (
            <select aria-label="Filtrar por cliente" className="h-8 rounded-md border bg-background px-2 text-sm" value={wsFilter} onChange={(e) => pick(e.target.value)}>
              <option value="">Todos os clientes</option>
              {workspaces.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          )}
          <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)} aria-label="Atualizar"><RotateCwIcon /></Button>
        </div>
      </div>

      {err && (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      )}
      {!f ? (
        !err && <div className="grid gap-3 lg:grid-cols-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-40" />)}</div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          <Section icon={<BellIcon />} title="Notificações" count={unread.length} has={f.notifications.length > 0}
            action={unread.length > 0 ? <Button size="sm" variant="ghost" onClick={() => read(unread.map((n) => n.id))}><CheckCheckIcon /> Marcar tudo lido</Button> : null}
            empty="Nada de novo.">
            {f.notifications.map((n) => (
              <li key={n.id} data-notification={n.id} className={cn("flex items-start gap-2 rounded-md p-2", !n.read_at && "bg-muted/60")}>
                <button type="button" className="min-w-0 flex-1 text-left" onClick={() => { if (!n.read_at) void markRead([n.id]); go(n.workspace_id, n.entity_type === "task" ? `/tarefas?task=${n.entity_id}` : "/"); }}>
                  <span className={cn("block text-sm", !n.read_at && "font-medium")}>{n.title}</span>
                  <span className="block text-xs text-muted-foreground">{n.workspace} · {fmtDue(n.created_at)}{n.body ? ` · ${n.body}` : ""}</span>
                </button>
                {!n.read_at && <Button size="sm" variant="ghost" onClick={() => read([n.id])}>Lido</Button>}
              </li>
            ))}
          </Section>

          <Section icon={<ListTodoIcon />} title="As minhas tarefas" count={f.tasks.length} has={f.tasks.length > 0} empty="Não tens tarefas abertas.">
            {f.tasks.map((t) => (
              <li key={t.id}>
                <button type="button" className="flex w-full flex-wrap items-center gap-2 rounded-md p-2 text-left hover:bg-muted/60" onClick={() => go(t.workspace_id, `/tarefas?task=${t.id}`)}>
                  <span className="min-w-0 flex-1 text-sm">{t.title}<span className="block text-xs text-muted-foreground">{t.workspace}</span></span>
                  <Badge variant={t.status === "blocked" ? "destructive" : "outline"}>{STATUS_LABEL[t.status]}</Badge>
                  {t.due_at && <span className={cn("inline-flex items-center gap-1 text-xs", t.overdue ? "text-destructive" : "text-muted-foreground")}><CalendarClockIcon className="size-3.5" />{fmtDue(t.due_at)}</span>}
                </button>
              </li>
            ))}
          </Section>

          <Section icon={<ClipboardCheckIcon />} title="Guiões à espera de aprovação" count={f.approvals.length} has={f.approvals.length > 0} empty="Nenhum guião à tua espera.">
            {f.approvals.slice(0, 30).map((a) => (
              <li key={a.id}>
                <button type="button" className="w-full rounded-md p-2 text-left text-sm hover:bg-muted/60" onClick={() => go(a.workspace_id, `/guioes?date=${a.date}`)}>
                  Guião {a.n} · {a.date.slice(8, 10)}/{a.date.slice(5, 7)}{a.tema ? ` · ${a.tema}` : ""}
                  <span className="block truncate text-xs text-muted-foreground">{a.workspace}{a.hook ? ` · ${a.hook}` : ""}</span>
                </button>
              </li>
            ))}
            {f.approvals.length > 30 && <li className="p-2 text-xs text-muted-foreground">E mais {f.approvals.length - 30}. Abre Guiões para ver todos.</li>}
          </Section>

          {(data?.unassigned.length ?? 0) > 0 && (
            <Section icon={<UserXIcon />} title="Tarefas sem responsável" count={f.unassigned.length} has={f.unassigned.length > 0} empty="Todas têm responsável.">
              {f.unassigned.map((u) => (
                <li key={u.id}>
                  <button type="button" className="w-full rounded-md p-2 text-left text-sm hover:bg-muted/60" onClick={() => go(u.workspace_id, `/tarefas?task=${u.id}`)}>
                    {u.title}<span className="block text-xs text-muted-foreground">{u.workspace}</span>
                  </button>
                </li>
              ))}
            </Section>
          )}
        </div>
      )}
    </div>
  );
}

function Section({ icon, title, count, has, action, empty, children }: {
  icon: React.ReactNode; title: string; count: number; has: boolean; action?: React.ReactNode; empty: string; children: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-2">
        <CardTitle className="flex items-center gap-2 text-base [&_svg]:size-4">{icon} {title} {count > 0 && <Badge variant="secondary">{count}</Badge>}</CardTitle>
        {action}
      </CardHeader>
      <CardContent>
        {!has ? <p className="text-sm text-muted-foreground">{empty}</p> : <ul className="flex flex-col gap-1">{children}</ul>}
      </CardContent>
    </Card>
  );
}
