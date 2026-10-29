"use client";

import { WsLink } from "@/components/ws-link";
import { useCallback, useEffect, useState } from "react";
import { BotIcon, Loader2Icon, RotateCwIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import type { Access } from "@/lib/access";
import { useSession } from "@/components/session-provider";
import {
  commentTask, createTask, dependTask, fetchTask, fetchTasks, fmtDue, fromLocalInput, HISTORY_LABEL, KIND_LABEL, PRIORITY_LABEL, STATUS_LABEL,
  toLocalInput, updateTask, type Assignee, type Task, type TaskDetail, type TaskKind, type TaskPriority, type TaskStatus,
} from "@/lib/tasks";

const sel = "h-9 w-full rounded-md border bg-background px-2 text-sm";

export function NewTaskDialog({ access, people, tz, onClose, onDone, contentId }: {
  access: Access; people: Assignee[]; tz: string; onClose: () => void; onDone: (t: Task) => void; contentId?: string;
}) {
  const [f, setF] = useState({ title: "", description: "", kind: "task" as TaskKind, priority: "normal" as TaskPriority, assignee_id: "", due: "" });
  const [ref] = useState(() => crypto.randomUUID());
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const submit = async () => {
    if (f.title.trim().length < 2) { setErr("Escreve um título."); return; }
    setBusy(true); setErr("");
    try {
      onDone(await createTask(access, {
        title: f.title, description: f.description || null, kind: f.kind, priority: f.priority, assignee_id: f.assignee_id || null,
        due_at: fromLocalInput(f.due, tz), content_id: contentId ?? null, client_ref: ref,
      }));
    } catch (e) { setErr((e as Error).message); setBusy(false); }
  };
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Nova tarefa</DialogTitle>
          <DialogDescription>O responsável recebe-a na caixa de entrada. Só aparecem pessoas com acesso a tarefas neste cliente.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1 text-sm">Título
            <Input autoFocus value={f.title} maxLength={200} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="Ex.: Gravar B-roll do guião 4" />
          </label>
          <label className="flex flex-col gap-1 text-sm">Descrição
            <Textarea rows={3} maxLength={5000} value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} />
          </label>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="flex flex-col gap-1 text-sm">Tipo
              <select className={sel} value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value as TaskKind })}>
                {Object.entries(KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">Prioridade
              <select className={sel} value={f.priority} onChange={(e) => setF({ ...f, priority: e.target.value as TaskPriority })}>
                {Object.entries(PRIORITY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">Responsável
              <select className={sel} value={f.assignee_id} onChange={(e) => setF({ ...f, assignee_id: e.target.value })}>
                <option value="">Sem responsável</option>
                {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">Prazo
              <Input type="datetime-local" value={f.due} onChange={(e) => setF({ ...f, due: e.target.value })} />
            </label>
          </div>
          {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={submit} disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Criar tarefa</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function TaskSheet({ access, id, people, tz, onClose, onChange }: {
  access: Access; id: string; people: Assignee[]; tz: string; onClose: () => void; onChange: () => void;
}) {
  const canComment = useSession().can("tasks.work");
  const [t, setT] = useState<TaskDetail | null>(null);
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);
  const [blockReason, setBlockReason] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [mentions, setMentions] = useState<string[]>([]);
  const [others, setOthers] = useState<Task[]>([]);
  const [dep, setDep] = useState("");

  useEffect(() => {
    let alive = true;
    fetchTask(access, id).then((x) => { if (alive) { setT(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, id, rev]);
  useEffect(() => {
    if (!t?.can_manage) return;
    let alive = true;
    fetchTasks(access, "open").then((x) => { if (alive) setOthers(x.filter((o) => o.id !== id)); }).catch(() => {});
    return () => { alive = false; };
  }, [access, id, t?.can_manage]);

  const run = useCallback(async (f: () => Promise<unknown>) => {
    setBusy(true); setMsg("");
    try { await f(); setRev((n) => n + 1); onChange(); }
    catch (e) {
      const code = (e as { code?: string }).code;
      setMsg(code === "PT409" ? "Alguém mudou esta tarefa entretanto. Recarreguei: revê e tenta de novo." : (e as Error).message);
      if (code === "PT409") setRev((n) => n + 1);
    }
    finally { setBusy(false); }
  }, [onChange]);
  const patch = (p: Record<string, unknown>) => t && run(() => updateTask(access, t.id, p, t.lock_version));

  return (
    <Sheet open onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader>
          <SheetTitle>{t?.title ?? "Tarefa"}</SheetTitle>
          <SheetDescription>
            {t ? <>Criada por {t.created_kind === "system" ? "automação" : t.created_label ?? "—"} a {fmtDue(t.created_at, tz)}</> : "A carregar…"}
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-4 px-4 pb-6">
          {err ? (
            <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
              <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
          ) : !t ? (
            <Skeleton className="h-48" />
          ) : (
            <>
              {msg && <Alert variant="destructive"><AlertDescription>{msg}</AlertDescription></Alert>}
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant={t.status === "blocked" ? "destructive" : "outline"}>{STATUS_LABEL[t.status]}</Badge>
                <Badge variant="secondary">{KIND_LABEL[t.kind]}</Badge>
                {t.rule_id && <Badge variant="secondary"><BotIcon /> automática</Badge>}
                {t.overdue && <Badge variant="destructive">Atrasada</Badge>}
              </div>
              {t.status === "blocked" && t.blocked_reason && <p className="rounded-md border border-destructive/40 bg-destructive/5 p-2 text-sm">Bloqueada: {t.blocked_reason}</p>}
              {t.assignee_id && t.assignee_has_access === false && (
                <Alert><AlertDescription>{t.assignee_email} já não tem acesso a este cliente. Reatribui a tarefa.</AlertDescription></Alert>
              )}

              {(t.can_work || t.can_manage) && (
                <div className="flex flex-wrap gap-2" aria-label="Mudar estado">
                  {(["todo", "doing", "done"] as TaskStatus[]).filter((s) => s !== t.status).map((s) => (
                    <Button key={s} size="sm" variant={s === "done" ? "default" : "outline"} disabled={busy || (s === "done" && t.open_deps > 0)} onClick={() => patch({ status: s })}>
                      {s === "todo" ? "Voltar a por fazer" : s === "doing" ? "Começar" : "Marcar feita"}
                    </Button>
                  ))}
                  {t.status !== "blocked" && <Button size="sm" variant="outline" disabled={busy} onClick={() => setBlockReason("")}>Bloquear</Button>}
                  {t.can_manage && t.status !== "cancelled" && <Button size="sm" variant="ghost" disabled={busy} onClick={() => patch({ status: "cancelled" })}>Cancelar tarefa</Button>}
                </div>
              )}
              {t.open_deps > 0 && (t.can_work || t.can_manage) && <p className="text-xs text-muted-foreground">Só se pode marcar feita quando as dependências fecharem.</p>}
              {blockReason !== null && (
                <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); if (blockReason.trim()) { patch({ status: "blocked", blocked_reason: blockReason }); setBlockReason(null); } }}>
                  <Input autoFocus aria-label="Motivo do bloqueio" placeholder="O que falta? Ex.: falta o microfone" value={blockReason} maxLength={500} onChange={(e) => setBlockReason(e.target.value)} />
                  <Button size="sm" type="submit" disabled={!blockReason.trim()}>Bloquear</Button>
                  <Button size="sm" type="button" variant="ghost" onClick={() => setBlockReason(null)}>Cancelar</Button>
                </form>
              )}

              <dl className="grid grid-cols-[7rem_1fr] items-center gap-x-3 gap-y-2 text-sm">
                <dt className="text-muted-foreground">Responsável</dt>
                <dd>{t.can_manage ? (
                  <select aria-label="Responsável" className={sel} value={t.assignee_id ?? ""} disabled={busy} onChange={(e) => patch({ assignee_id: e.target.value || null })}>
                    <option value="">Sem responsável</option>
                    {t.assignee_id && !people.some((p) => p.user_id === t.assignee_id) && <option value={t.assignee_id}>{t.assignee_email} (sem acesso)</option>}
                    {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
                  </select>
                ) : t.assignee_email ?? "Sem responsável"}</dd>
                <dt className="text-muted-foreground">Prazo</dt>
                <dd>{t.can_manage ? (
                  <Input type="datetime-local" aria-label="Prazo" defaultValue={toLocalInput(t.due_at, tz)} key={t.lock_version}
                    onBlur={(e) => { const v = fromLocalInput(e.target.value, tz); if (v !== (t.due_at ? new Date(t.due_at).toISOString() : null)) patch({ due_at: v }); }} />
                ) : t.due_at ? fmtDue(t.due_at, tz) : "Sem prazo"}</dd>
                <dt className="text-muted-foreground">Prioridade</dt>
                <dd>{t.can_manage ? (
                  <select aria-label="Prioridade" className={sel} value={t.priority} disabled={busy} onChange={(e) => patch({ priority: e.target.value })}>
                    {Object.entries(PRIORITY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                ) : PRIORITY_LABEL[t.priority]}</dd>
                {t.content && <>
                  <dt className="text-muted-foreground">Guião</dt>
                  <dd><WsLink className="underline underline-offset-2" href={`/guioes?date=${t.content.date}`}>Guião {t.content.n}{t.content.tema ? ` · ${t.content.tema}` : ""}</WsLink></dd>
                </>}
                {t.source && <>
                  <dt className="text-muted-foreground">Fonte</dt>
                  <dd><WsLink className="underline underline-offset-2" href="/fontes">{t.source.titulo}</WsLink></dd>
                </>}
              </dl>
              {t.description && <p className="whitespace-pre-wrap text-sm">{t.description}</p>}

              <section className="flex flex-col gap-2">
                <h3 className="text-sm font-semibold">Depende de</h3>
                {t.deps.length === 0 && <p className="text-sm text-muted-foreground">Nada.</p>}
                {t.deps.map((d) => (
                  <div key={d.id} className="flex items-center gap-2 text-sm">
                    <span className={d.status === "done" || d.status === "cancelled" ? "text-muted-foreground line-through" : ""}>{d.title}</span>
                    <Badge variant="outline">{STATUS_LABEL[d.status]}</Badge>
                    {t.can_manage && <Button size="icon-sm" variant="ghost" aria-label={`Remover dependência ${d.title}`} onClick={() => run(() => dependTask(access, t.id, d.id, false))}><XIcon /></Button>}
                  </div>
                ))}
                {t.can_manage && others.length > 0 && (
                  <div className="flex gap-2">
                    <select aria-label="Escolher tarefa de que depende" className={sel} value={dep} onChange={(e) => setDep(e.target.value)}>
                      <option value="">Escolher tarefa…</option>
                      {others.filter((o) => !t.deps.some((d) => d.id === o.id)).map((o) => <option key={o.id} value={o.id}>{o.title}</option>)}
                    </select>
                    <Button size="sm" variant="outline" disabled={!dep || busy} onClick={() => { const d = dep; setDep(""); run(() => dependTask(access, t.id, d, true)); }}>Adicionar</Button>
                  </div>
                )}
              </section>

              <section className="flex flex-col gap-2">
                <h3 className="text-sm font-semibold">Comentários</h3>
                {t.comments_list.length === 0 && <p className="text-sm text-muted-foreground">Ainda sem comentários.</p>}
                {t.comments_list.map((c) => (
                  <div key={c.id} className="rounded-md border p-2 text-sm">
                    <p className="text-xs text-muted-foreground">{c.author_label} · {fmtDue(c.created_at, tz)}{c.mentions.length ? ` · para ${c.mentions.join(", ")}` : ""}</p>
                    <p className="whitespace-pre-wrap">{c.body}</p>
                  </div>
                ))}
                {canComment && (
                  <form className="flex flex-col gap-2" onSubmit={(e) => {
                    e.preventDefault();
                    if (!comment.trim()) return;
                    const body = comment, m = mentions;
                    run(async () => { await commentTask(access, t.id, body, m); setComment(""); setMentions([]); });
                  }}>
                    <Textarea aria-label="Novo comentário" rows={2} maxLength={4000} value={comment} onChange={(e) => setComment(e.target.value)} placeholder="Escreve um comentário" />
                    <div className="flex flex-wrap items-center gap-2">
                      <select aria-label="Mencionar alguém" className="h-8 rounded-md border bg-background px-2 text-xs" value=""
                        onChange={(e) => { const v = e.target.value; if (v && !mentions.includes(v)) setMentions([...mentions, v]); }}>
                        <option value="">Mencionar…</option>
                        {people.filter((p) => !mentions.includes(p.user_id)).map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
                      </select>
                      {mentions.map((m) => (
                        <Badge key={m} variant="secondary">{people.find((p) => p.user_id === m)?.email}
                          <button type="button" aria-label="Tirar menção" onClick={() => setMentions(mentions.filter((x) => x !== m))}><XIcon className="size-3" /></button>
                        </Badge>
                      ))}
                      <Button size="sm" type="submit" className="ml-auto" disabled={busy || !comment.trim()}>Comentar</Button>
                    </div>
                  </form>
                )}
              </section>

              <section className="flex flex-col gap-1">
                <h3 className="text-sm font-semibold">Histórico</h3>
                <ol className="flex flex-col gap-1 text-xs text-muted-foreground">
                  {t.history.map((h, i) => (
                    <li key={i}>{fmtDue(h.created_at, tz)} · {h.actor_label} {HISTORY_LABEL[h.action] ?? h.action}{describe(h.after, people)}</li>
                  ))}
                </ol>
              </section>
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

function describe(after: Record<string, unknown> | null, people: Assignee[]) {
  if (!after) return "";
  const parts: string[] = [];
  if (typeof after.status === "string") parts.push(`estado: ${STATUS_LABEL[after.status as TaskStatus] ?? after.status}`);
  if ("assignee_id" in after) parts.push(`responsável: ${people.find((p) => p.user_id === after.assignee_id)?.email ?? (after.assignee_id ? "outra pessoa" : "ninguém")}`);
  if ("priority" in after && typeof after.priority === "string") parts.push(`prioridade: ${PRIORITY_LABEL[after.priority as TaskPriority] ?? after.priority}`);
  if ("due_at" in after) parts.push(after.due_at ? "prazo alterado" : "sem prazo");
  if (typeof after.title === "string" && !("status" in after)) parts.push(`"${after.title}"`);
  if (typeof after.event === "string") parts.push(`(${after.event})`);
  return parts.length ? ` (${parts.join(", ")})` : "";
}
