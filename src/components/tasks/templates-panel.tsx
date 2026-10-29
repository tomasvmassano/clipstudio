"use client";

import { useEffect, useState } from "react";
import { CopyIcon, Loader2Icon, PlusIcon, RotateCwIcon, Trash2Icon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import {
  cloneTemplate, fetchTemplates, KIND_LABEL, saveTemplate, type Assignee, type TaskKind, type Template, type TemplateItem,
} from "@/lib/tasks";

const sel = "h-9 rounded-md border bg-background px-2 text-sm";
type Draft = { id?: string; name: string; description: string; items: TemplateItem[]; checklist: string; active: boolean };
const newItem = (): TemplateItem => ({ title: "", kind: "task", priority: "normal", offset_days: 0, hour: 10, assignee_id: null, depends_on: [] });

/** Templates de produção deste cliente (FR-11-04, FR-17-09). Aplicam-se a um guião no calendário. */
export function TemplatesPanel({ access, people }: { access: Access; people: Assignee[] }) {
  const { workspaces } = useSession();
  const targets = workspaces.filter((w) => w.id !== access.ws && w.capabilities.includes("tasks.manage"));
  const [list, setList] = useState<Template[] | null>(null);
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState<{ text: string; ok: boolean } | null>(null);
  const [rev, setRev] = useState(0);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    fetchTemplates(access).then((x) => { if (alive) { setList(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, rev]);

  const run = async (f: () => Promise<unknown>, ok?: string) => {
    setBusy(true); setMsg(null);
    try { await f(); if (ok) setMsg({ text: ok, ok: true }); setRev((n) => n + 1); return true; }
    catch (e) { setMsg({ text: (e as Error).message, ok: false }); return false; }
    finally { setBusy(false); }
  };
  const save = async (d: Draft) => {
    const items = d.items.filter((i) => i.title.trim()).map((i) => ({ title: i.title, kind: i.kind, priority: i.priority, offset_days: i.offset_days, hour: i.hour, assignee_id: i.assignee_id, depends_on: i.depends_on }));
    const ok = await run(() => saveTemplate(access, {
      ...(d.id ? { id: d.id } : {}), name: d.name, description: d.description || null, active: d.active,
      items, checklist: d.checklist.split("\n").map((x) => x.trim()).filter(Boolean),
    }), "Template guardado.");
    if (ok) setDraft(null);
  };
  const setItem = (i: number, patch: Partial<TemplateItem>) => draft && setDraft({ ...draft, items: draft.items.map((x, j) => (j === i ? { ...x, ...patch } : x)) });

  if (err) return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
    <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  if (!list) return <Skeleton className="h-32" />;

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-muted-foreground">
        Um template é a lista de tarefas e a checklist de cada guião. Aplica-se no calendário, no detalhe do guião. O prazo conta a partir do dia do guião. Aplicar duas vezes não duplica nada.
      </p>
      {msg && <Alert variant={msg.ok ? "default" : "destructive"}><AlertDescription>{msg.text}</AlertDescription></Alert>}
      {list.length === 0 && !draft && <Alert><AlertDescription>Ainda não há templates neste cliente.</AlertDescription></Alert>}
      {list.map((t) => (
        <Card key={t.id} data-template={t.id} className={t.active ? "" : "opacity-60"}>
          <CardContent className="flex flex-col gap-2 py-3 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <b className="min-w-0 flex-1">{t.name}</b>
              <Badge variant="outline">{t.items.length} tarefa{t.items.length === 1 ? "" : "s"} · {t.checklist.length} na checklist</Badge>
              {t.applied > 0 && <Badge variant="secondary">usado em {t.applied}</Badge>}
              <Button size="sm" variant="outline" disabled={busy} onClick={() => setDraft({ id: t.id, name: t.name, description: t.description ?? "", items: t.items, checklist: t.checklist.join("\n"), active: t.active })}>Editar</Button>
              <Button size="sm" variant="ghost" disabled={busy} onClick={() => run(() => saveTemplate(access, { id: t.id, active: !t.active }))}>{t.active ? "Desligar" : "Ligar"}</Button>
              {targets.length > 0 && (
                <select aria-label={`Copiar ${t.name} para outro cliente`} className={sel} value="" disabled={busy}
                  onChange={(e) => { const w = e.target.value; if (w) run(() => cloneTemplate(t.id, w), `Copiado para ${targets.find((x) => x.id === w)?.name}, sem responsáveis.`); }}>
                  <option value="">Copiar para…</option>
                  {targets.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select>
              )}
            </div>
            <ol className="ml-4 list-decimal text-muted-foreground">
              {t.items.map((i, k) => (
                <li key={k}>{i.title} · {KIND_LABEL[i.kind].toLowerCase()} · dia {i.offset_days >= 0 ? `+${i.offset_days}` : i.offset_days} às {String(i.hour).padStart(2, "0")}h
                  {i.assignee_email ? ` · ${i.assignee_email}` : ""}{i.assignee_has_access === false ? " (sem acesso)" : ""}{i.depends_on.length ? ` · depois de ${i.depends_on.map((d) => d + 1).join(", ")}` : ""}</li>
              ))}
            </ol>
          </CardContent>
        </Card>
      ))}
      {draft ? (
        <Card>
          <CardContent className="flex flex-col gap-3 py-4 text-sm">
            <label className="flex flex-col gap-1">Nome<Input value={draft.name} maxLength={120} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="Ex.: Reel com edição" /></label>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1 font-medium">Tarefas (use {"{n}"} e {"{tema}"} no título)</legend>
              {draft.items.map((it, i) => (
                <div key={i} className="grid gap-2 rounded-md border p-2 sm:grid-cols-[1fr_8rem_5rem_5rem_12rem_auto]" data-template-item={i}>
                  <Input aria-label={`Título da tarefa ${i + 1}`} value={it.title} maxLength={200} onChange={(e) => setItem(i, { title: e.target.value })} placeholder={`Tarefa ${i + 1}`} />
                  <select aria-label="Tipo" className={sel} value={it.kind} onChange={(e) => setItem(i, { kind: e.target.value as TaskKind })}>
                    {Object.entries(KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                  <Input aria-label="Dias depois do guião" type="number" min={-60} max={60} value={it.offset_days} onChange={(e) => setItem(i, { offset_days: Number(e.target.value) })} />
                  <Input aria-label="Hora" type="number" min={0} max={23} value={it.hour} onChange={(e) => setItem(i, { hour: Number(e.target.value) })} />
                  <select aria-label="Responsável" className={sel} value={it.assignee_id ?? ""} onChange={(e) => setItem(i, { assignee_id: e.target.value || null })}>
                    <option value="">Sem responsável</option>
                    {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.email}</option>)}
                  </select>
                  <span className="flex items-center gap-2">
                    {i > 0 && (
                      <label className="inline-flex items-center gap-1 whitespace-nowrap text-xs">
                        <input type="checkbox" checked={it.depends_on.includes(i - 1)} onChange={(e) => setItem(i, { depends_on: e.target.checked ? [i - 1] : [] })} /> depois da anterior
                      </label>
                    )}
                    <Button size="icon-sm" variant="ghost" aria-label={`Remover tarefa ${i + 1}`}
                      onClick={() => setDraft({ ...draft, items: draft.items.filter((_, j) => j !== i).map((x) => ({ ...x, depends_on: x.depends_on.filter((d) => d !== i).map((d) => (d > i ? d - 1 : d)) })) })}>
                      <Trash2Icon />
                    </Button>
                  </span>
                </div>
              ))}
              <div className="flex flex-wrap items-center gap-2">
                <Button size="sm" variant="outline" disabled={draft.items.length >= 30} onClick={() => setDraft({ ...draft, items: [...draft.items, newItem()] })}><PlusIcon /> Tarefa</Button>
                <span className="text-xs text-muted-foreground">Dias: 0 = dia do guião, 1 = dia seguinte, -1 = véspera.</span>
              </div>
            </fieldset>
            <label className="flex flex-col gap-1">Checklist (um item por linha)
              <Textarea rows={4} value={draft.checklist} onChange={(e) => setDraft({ ...draft, checklist: e.target.value })} placeholder={"Luz ok\nMicrofone ligado\nCapa escolhida"} />
            </label>
            <div className="flex gap-2">
              <Button size="sm" disabled={busy} onClick={() => save(draft)}>{busy && <Loader2Icon className="animate-spin" />} Guardar template</Button>
              <Button size="sm" variant="ghost" onClick={() => setDraft(null)}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div><Button size="sm" variant="outline" onClick={() => setDraft({ name: "", description: "", items: [newItem()], checklist: "", active: true })}><CopyIcon /> Novo template</Button></div>
      )}
    </div>
  );
}
