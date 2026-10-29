"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { MessagesSquareIcon, RotateCwIcon, SearchIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { GuiaoCard } from "@/components/guiao-card";
import { useScriptActions, useScriptCaps } from "@/components/use-guioes";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { subscribeGuioes } from "@/lib/data";
import { fetchReviewInbox, type ReviewFilters, type ReviewInbox } from "@/lib/comments";
import type { Guiao } from "@/lib/types";

const STATUS: { v: string; l: string }[] = [
  { v: "in_review", l: "Por rever" }, { v: "changes_requested", l: "Alterações pedidas" }, { v: "draft", l: "Rascunho" },
  { v: "approved", l: "Aprovados" }, { v: "rejected", l: "Rejeitados" },
];
const PRIORITY: Record<string, string> = { urgent: "Urgente", high: "Alta", normal: "Normal", low: "Baixa" };
const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";
const day = (iso: string) => new Date(iso.length === 10 ? `${iso}T12:00:00` : iso).toLocaleDateString("pt-PT", { day: "numeric", month: "short" });

/** Caixa de revisão (FR-05-01): o que está à espera de revisão, com filtros por estado, responsável, prioridade e prazo. */
function RevisaoInner({ access }: { access: Access }) {
  const caps = useScriptCaps();
  const [f, setF] = useState<ReviewFilters>({ status: ["in_review", "changes_requested"] });
  const [q, setQ] = useState("");
  const [inbox, setInbox] = useState<ReviewInbox | null>(null);
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");

  const reload = useCallback(async () => {
    try { setInbox(await fetchReviewInbox(access, { ...f, q: q.trim() || undefined })); setErr(""); }
    catch (e) { setErr((e as Error).message); }
  }, [access, f, q]);
  useEffect(() => {
    const id = setTimeout(() => void reload(), q ? 300 : 0);   // a pesquisa espera um pouco pela escrita
    return () => clearTimeout(id);
  }, [reload, q]);
  useEffect(() => subscribeGuioes(access, () => void reload()), [access, reload]);

  const put = useCallback((g: Guiao) => {
    setInbox((p) => (p ? { ...p, items: p.items.map((it) => (it.guiao.id === g.id ? { ...it, guiao: g } : it)) } : p));
    void reload();
    return g;
  }, [reload]);
  const actions = useScriptActions(access, put, reload);
  const assignees = useMemo(() => inbox?.assignees ?? [], [inbox]);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Revisão</h1>
          <p className="text-sm text-muted-foreground">Guiões à espera de decisão. Abre os comentários para comentar uma frase; aprova ou pede alterações no próprio cartão.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => void reload()}><RotateCwIcon /> Atualizar</Button>
      </div>

      <div className="flex flex-col gap-3 rounded-lg border p-3">
        <ToggleGroup multiple value={f.status ?? []} onValueChange={(v) => setF((p) => ({ ...p, status: v as string[] }))} variant="outline" size="sm" className="flex-wrap">
          {STATUS.map((s) => (
            <ToggleGroupItem key={s.v} value={s.v} aria-label={s.l}>
              {s.l}{inbox?.counts?.[s.v] != null && <span className="ml-1 tabular-nums text-muted-foreground">{inbox.counts[s.v]}</span>}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
        <div className="flex flex-wrap items-center gap-2">
          <label className="relative min-w-56 flex-1">
            <SearchIcon className="pointer-events-none absolute top-2 left-2 size-4 text-muted-foreground" />
            <Input aria-label="Pesquisar nos guiões" className="h-8 pl-8" placeholder="Pesquisar tema, hooks ou corpo" value={q} maxLength={100} onChange={(e) => setQ(e.target.value)} />
          </label>
          <select aria-label="Responsável" className={selectCls} value={f.assignee ?? ""} onChange={(e) => setF((p) => ({ ...p, assignee: e.target.value || undefined }))}>
            <option value="">Qualquer responsável</option>
            <option value="me">Atribuídos a mim</option>
            <option value="none">Sem responsável</option>
            {assignees.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
          </select>
          <select aria-label="Prioridade" className={selectCls} value={f.priority ?? ""} onChange={(e) => setF((p) => ({ ...p, priority: e.target.value || undefined }))}>
            <option value="">Qualquer prioridade</option>
            {Object.entries(PRIORITY).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
          <select aria-label="Prazo" className={selectCls} value={f.due ?? ""} onChange={(e) => setF((p) => ({ ...p, due: e.target.value || undefined }))}>
            <option value="">Qualquer prazo</option>
            <option value="overdue">Atrasados</option>
            <option value="today">Hoje</option>
            <option value="week">Próximos 7 dias</option>
          </select>
          {(f.assignee || f.priority || f.due || q) && (
            <Button size="sm" variant="ghost" onClick={() => { setF((p) => ({ status: p.status })); setQ(""); }}>Limpar filtros</Button>
          )}
        </div>
      </div>

      {(err || msg) && <Alert variant="destructive"><AlertDescription>{err || msg} {err && <Button size="sm" variant="link" onClick={() => void reload()}>Tentar de novo</Button>}</AlertDescription></Alert>}
      {!inbox && !err && <div className="flex flex-col gap-3">{[1, 2].map((i) => <Skeleton key={i} className="h-40 w-full" />)}</div>}
      {inbox && inbox.items.length === 0 && (
        <Alert><AlertDescription>{(f.status?.length ?? 0) === 0 ? "Escolhe pelo menos um estado." : "Nada à espera de revisão com estes filtros."}</AlertDescription></Alert>
      )}
      {inbox && inbox.items.length > 0 && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted-foreground">{inbox.items.length} {inbox.items.length === 1 ? "guião" : "guiões"}</p>
          {inbox.items.map((it) => {
            const due = it.task?.due_at ?? it.guiao.date;
            const late = (it.task?.due_at ? it.task.due_at.slice(0, 10) : it.guiao.date) < inbox.today;
            return (
              <div key={it.guiao.id} className="flex flex-col gap-1.5">
                <div className="flex flex-wrap items-center gap-2 px-1 text-xs text-muted-foreground">
                  <span className={late ? "font-medium text-destructive" : ""}>{it.task?.due_at ? "prazo" : "dia"} {day(due)}{late ? " · atrasado" : ""}</span>
                  {it.task && <Badge variant={it.task.priority === "urgent" || it.task.priority === "high" ? "destructive" : "outline"}>{PRIORITY[it.task.priority] ?? it.task.priority}</Badge>}
                  <span>{it.task?.assignee ? `responsável: ${it.task.assignee}` : "sem responsável"}</span>
                  {it.version_no != null && <span>v{it.version_no}</span>}
                  <span className="inline-flex items-center gap-1"><MessagesSquareIcon className="size-3" /> {it.open_comments} por resolver{it.all_comments > it.open_comments ? ` de ${it.all_comments}` : ""}</span>
                </div>
                <GuiaoCard g={it.guiao} caps={caps} actions={actions} onError={setMsg} openComments={it.open_comments} />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function RevisaoPage() {
  return (
    <Suspense fallback={<Skeleton className="h-40 w-full" />}>
      <WorkspaceGate need="scripts.read">{(access) => <RevisaoInner access={access} />}</WorkspaceGate>
    </Suspense>
  );
}
