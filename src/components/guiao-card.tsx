"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArchiveIcon, CheckIcon, ChevronDownIcon, ChevronUpIcon, CopyIcon, ExternalLinkIcon, HistoryIcon, Loader2Icon, MessageSquareWarningIcon,
  MessagesSquareIcon, MoreHorizontalIcon, NotebookTextIcon, PencilIcon, PlusIcon, SendIcon, Trash2Icon, UndoIcon, VideoIcon, XIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent } from "@/components/ui/card";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { PRODUCTION_LABEL } from "@/lib/calendar";
import { recordable, words } from "@/lib/data";
import { EDITORIAL_LABEL, FORMATO_LABEL, WPS, type EditorialStatus, type Guiao, type Hook } from "@/lib/types";
import type { ScriptActions, ScriptCaps } from "@/components/use-guioes";
import { HistorySheet } from "@/components/guiao-history";
import { CommentsSheet } from "@/components/guiao-comments";
import { BriefSheet } from "@/components/guiao-brief";

const MECH = ["pergunta", "contra", "numero", "ego", "confissao", "segredo"];

const STATUS_STYLE: Record<EditorialStatus, string> = {
  draft: "border-dashed",
  in_review: "border-amber-500/50 text-amber-600 dark:text-amber-400",
  changes_requested: "border-orange-500/60 text-orange-600 dark:text-orange-400",
  approved: "bg-primary text-primary-foreground border-transparent",
  rejected: "bg-destructive text-white border-transparent",
  archived: "text-muted-foreground",
};

type Props = {
  g: Guiao;
  carried?: boolean;
  caps: ScriptCaps;
  actions: ScriptActions;
  onError: (msg: string) => void;
  startInEdit?: boolean;
  /** Comentários por resolver, quando quem mostra o cartão já os sabe (caixa de revisão). */
  openComments?: number;
};

type Draft = { hooks: Hook[]; corpo: string; cta: string; notas: string };
const toDraft = (g: Guiao): Draft => ({ hooks: g.hooks.length ? g.hooks : [{ text: "", mecanismo: "" }], corpo: g.corpo, cta: g.cta ?? "", notas: g.notas ?? "" });
const clean = (d: Draft) => ({
  hooks: d.hooks.filter((h) => h.text.trim()).map((h) => ({ text: h.text.trim(), mecanismo: h.mecanismo })),
  corpo: d.corpo.split("\n").map((l) => l.trim()).filter(Boolean).join("\n"),
  cta: d.cta.trim(),
  notas: d.notas.trim(),
});

export function GuiaoCard({ g, carried, caps, actions, onError, startInEdit, openComments }: Props) {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"view" | "edit" | "changes_requested" | "rejected">(startInEdit ? "edit" : "view");
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState("");
  const [historyOpen, setHistoryOpen] = useState(false);
  const [briefOpen, setBriefOpen] = useState(false);
  const [commentsOpen, setCommentsOpen] = useState(false);
  const [nComments, setNComments] = useState<number | undefined>(openComments);

  const st = g.editorial_status;
  const dead = st === "rejected" || st === "archived";
  const recorded = ["recorded", "editing", "ready", "published"].includes(g.production_status);
  const toggleable = ["not_started", "scheduled", "recorded"].includes(g.production_status);
  const dur = Math.round((words(g.corpo) + words(g.hooks[0]?.text) + words(g.cta)) / WPS);

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      await fn();
      setMode("view");
      setReason("");
    } catch (e) {
      onError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const meta = (
    <div className="flex flex-wrap items-center gap-1.5 text-xs">
      <Badge variant="outline" className={STATUS_STYLE[st]}>{EDITORIAL_LABEL[st]}</Badge>
      {recorded && <Badge className="bg-emerald-600 text-white">{PRODUCTION_LABEL[g.production_status].toLowerCase()}</Badge>}
      {g.production_status === "scheduled" && <Badge variant="outline">agendado</Badge>}
      {g.production_status === "cancelled" && <Badge variant="outline">cancelado</Badge>}
      {g.formato && <Badge variant="outline">{FORMATO_LABEL[g.formato] ?? g.formato}</Badge>}
      {g.tema && <Badge variant="secondary" className="max-w-[18rem] truncate">{g.tema}</Badge>}
      {carried && <Badge variant="outline" className="border-amber-500/50 text-amber-600 dark:text-amber-400">por gravar de {g.date}</Badge>}
      {st === "draft" && g.approved_version_id && <span className="text-muted-foreground">tem uma versão anterior aprovada</span>}
      <span className="text-muted-foreground tabular-nums">~{dur}s</span>
      {g.critic_score != null && <span className="ml-auto font-medium tabular-nums text-muted-foreground">{Number(g.critic_score).toFixed(1)}</span>}
    </div>
  );

  return (
    <Card data-guiao={g.id} className={cn("overflow-hidden", dead && "opacity-60", recorded && "border-emerald-600/40")}>
      <CardContent className="grid grid-cols-[3rem_minmax(0,1fr)] gap-4 p-0">
        <div className={cn("flex items-start justify-center border-r bg-muted/40 pt-4 font-mono text-2xl font-semibold tabular-nums text-muted-foreground", recorded && "text-emerald-600")}>
          {g.n}
        </div>
        <div className="flex min-w-0 flex-col gap-3 py-4 pr-4">
          {meta}

          {mode === "edit" ? (
            <BlockEditor g={g} actions={actions} onError={onError} onClose={() => setMode("view")} />
          ) : (
            <>
              <ol className="flex flex-col gap-1.5" aria-label="Hooks">
                {g.hooks.map((h, i) => (
                  <li key={i} className="grid grid-cols-[3.5rem_minmax(0,1fr)_auto] items-baseline gap-2 text-[15px] font-semibold leading-snug">
                    <span className="font-mono text-[11px] font-normal uppercase text-primary">Hook {i + 1}</span>
                    <span>{h.text}</span>
                    <span className="text-[10px] font-normal uppercase tracking-wide text-muted-foreground">{h.mecanismo}</span>
                  </li>
                ))}
              </ol>
              <div className={cn("whitespace-pre-line border-l-2 pl-3 text-sm leading-relaxed", !open && "line-clamp-3")}>{g.corpo}</div>
              {g.cta && <p className="border-l-2 border-primary/60 pl-3 text-sm font-medium">CTA: {g.cta}</p>}
              {open && g.notas && <p className="rounded-md bg-muted/50 px-3 py-2 text-xs text-muted-foreground">Notas: {g.notas}</p>}
              {(st === "rejected" || st === "changes_requested") && g.motivo_rejeicao && (
                <p className={cn("text-sm", st === "rejected" ? "text-destructive" : "text-orange-600 dark:text-orange-400")}>
                  {st === "rejected" ? "Motivo" : "Alterações pedidas"}: {g.motivo_rejeicao}
                </p>
              )}
              {g.fonte && (
                <p className="text-xs text-muted-foreground">
                  Fonte:{" "}
                  {/^https?:\/\//.test(g.fonte)
                    ? g.fonte.split(/\s+/).filter(Boolean).map((u, i) => (
                        <a key={i} href={u} target="_blank" rel="noopener" className="mr-2 inline-flex items-center gap-0.5 underline underline-offset-2">
                          {u.replace(/^https?:\/\/(www\.)?/, "").slice(0, 48)} <ExternalLinkIcon className="size-3" />
                        </a>
                      ))
                    : g.fonte}
                </p>
              )}
            </>
          )}

          {(mode === "changes_requested" || mode === "rejected") && (
            <form
              className="flex flex-wrap gap-2"
              onSubmit={(e) => { e.preventDefault(); run(() => actions.transition(g.id, mode, reason, g.lock_version)); }}
            >
              <Input
                id={`${g.id}-reason`} className="min-w-[14rem] flex-1" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus required
                aria-label={mode === "rejected" ? "Motivo da rejeição" : "O que tem de mudar"}
                placeholder={mode === "rejected" ? "Porque não dirias isto?" : "O que tem de mudar?"}
              />
              <Button size="sm" type="submit" variant={mode === "rejected" ? "destructive" : "default"} disabled={busy || !reason.trim()}>
                {busy && <Loader2Icon className="animate-spin" />} {mode === "rejected" ? "Rejeitar" : "Pedir alterações"}
              </Button>
              <Button size="sm" type="button" variant="ghost" onClick={() => setMode("view")}>Cancelar</Button>
            </form>
          )}

          {mode === "view" && (
            <div className="flex flex-wrap items-center gap-1.5">
              <Button size="sm" variant="ghost" onClick={() => setOpen(!open)}>
                {open ? <ChevronUpIcon /> : <ChevronDownIcon />} {open ? "Recolher" : "Ver tudo"}
              </Button>

              {(st === "draft" || st === "changes_requested") && caps.submit && !caps.approve && (
                <Button size="sm" disabled={busy} onClick={() => run(() => actions.transition(g.id, "in_review", undefined, g.lock_version))}>
                  <SendIcon /> Enviar para revisão
                </Button>
              )}
              {(st === "in_review" || ((st === "draft" || st === "changes_requested") && caps.submit)) && caps.approve && (
                <Button size="sm" disabled={busy} onClick={() => run(() => actions.transition(g.id, "approved", undefined, g.lock_version))}>
                  <CheckIcon /> Aprovar
                </Button>
              )}
              {st === "in_review" && caps.reject && (
                <Button size="sm" variant="outline" onClick={() => setMode("changes_requested")}>
                  <MessageSquareWarningIcon /> Pedir alterações
                </Button>
              )}
              {(st === "in_review" || st === "draft" || st === "changes_requested") && caps.reject && (
                <Button size="sm" variant="outline" onClick={() => setMode("rejected")}>
                  <XIcon /> Rejeitar
                </Button>
              )}
              {st === "approved" && caps.approve && (
                <Button size="sm" variant="secondary" disabled={busy} onClick={() => run(() => actions.transition(g.id, "in_review", undefined, g.lock_version))}>
                  <UndoIcon /> Retirar aprovação
                </Button>
              )}
              {st === "rejected" && caps.approve && (
                <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => actions.transition(g.id, "in_review", undefined, g.lock_version))}>
                  <UndoIcon /> Recuperar
                </Button>
              )}
              {st === "archived" && caps.archive && (
                <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => actions.transition(g.id, "restore", undefined, g.lock_version))}>
                  <UndoIcon /> Recuperar do arquivo
                </Button>
              )}
              {st !== "archived" && caps.edit && (
                <Button size="sm" variant="outline" onClick={() => setMode("edit")}>
                  <PencilIcon /> Editar
                </Button>
              )}
              {recordable(g) && caps.record && toggleable && (
                <Button size="sm" variant="ghost" disabled={busy} onClick={() => run(() => actions.record(g.id, !recorded))}>
                  <VideoIcon /> {recorded ? "Desmarcar gravado" : "Marcar gravado"}
                </Button>
              )}
              <Button size="sm" variant="ghost" onClick={() => setCommentsOpen(true)}>
                <MessagesSquareIcon /> Comentários{nComments ? ` (${nComments})` : ""}
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setBriefOpen(true)}>
                <NotebookTextIcon /> Brief e fontes
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setHistoryOpen(true)}>
                <HistoryIcon /> Histórico
              </Button>
              {(caps.create || (caps.archive && st !== "archived")) && (
                <DropdownMenu>
                  <DropdownMenuTrigger render={<Button size="icon-sm" variant="ghost" aria-label="Mais ações" />}>
                    <MoreHorizontalIcon />
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuGroup>
                      {caps.create && (
                        <DropdownMenuItem onClick={() => run(() => actions.duplicate(g.id))}><CopyIcon /> Duplicar como rascunho</DropdownMenuItem>
                      )}
                      {caps.archive && st !== "archived" && (
                        <DropdownMenuItem onClick={() => run(() => actions.transition(g.id, "archived", undefined, g.lock_version))}><ArchiveIcon /> Arquivar</DropdownMenuItem>
                      )}
                    </DropdownMenuGroup>
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
            </div>
          )}
        </div>
      </CardContent>
      <BriefSheet g={g} open={briefOpen} onOpenChange={setBriefOpen} actions={actions} canEdit={caps.edit && st !== "archived"} canRefs={caps.refs} />
      <CommentsSheet g={g} open={commentsOpen} onOpenChange={setCommentsOpen} onCount={setNComments} />
      <HistorySheet g={g} open={historyOpen} onOpenChange={setHistoryOpen} actions={actions} canRestore={caps.edit && st !== "archived"} onError={onError} />
    </Card>
  );
}

/** Editor por blocos: Hook 1..N, Corpo, CTA e Notas. Guarda sozinho (FR-02-02); conflitos recarregam (FR-02-06). */
function BlockEditor({ g, actions, onError, onClose }: { g: Guiao; actions: ScriptActions; onError: (m: string) => void; onClose: () => void }) {
  const [d, setD] = useState<Draft>(() => toDraft(g));
  const [state, setState] = useState<"idle" | "dirty" | "saving" | "saved" | "error">("idle");
  const [savedAt, setSavedAt] = useState<string>("");
  const lock = useRef(g.lock_version);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pending = useRef<Draft | null>(null);
  const wasApproved = g.editorial_status === "approved";

  const flush = useCallback(async () => {
    if (timer.current) { clearTimeout(timer.current); timer.current = null; }
    const next = pending.current;
    if (!next) return true;
    const c = clean(next);
    if (!c.corpo) { setState("error"); onError("O corpo não pode ficar vazio."); return false; }
    pending.current = null;
    setState("saving");
    try {
      const saved = await actions.save(g.id, c, lock.current);
      lock.current = saved.lock_version;
      setSavedAt(new Date().toLocaleTimeString("pt-PT", { hour: "2-digit", minute: "2-digit" }));
      setState(pending.current ? "dirty" : "saved");
      return true;
    } catch (e) {
      setState("error");
      onError((e as Error).message);
      if ((e as { code?: string }).code === "PT409") onClose();
      return false;
    }
  }, [actions, g.id, onClose, onError]);

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  const change = (next: Draft) => {
    setD(next);
    pending.current = next;
    setState("dirty");
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => { void flush(); }, 1200);
  };

  const setHook = (i: number, h: Partial<Hook>) => {
    const hooks = d.hooks.map((x, j) => (j === i ? { ...x, ...h } : x));
    change({ ...d, hooks });
  };

  return (
    <div className="flex flex-col gap-3">
      {wasApproved && (
        <p className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs">
          Este guião está aprovado. Ao mudares o texto volta a rascunho e a aprovação fica guardada na versão anterior.
        </p>
      )}
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-xs font-medium text-muted-foreground">Hooks</legend>
        {d.hooks.map((h, i) => (
          <div key={i} className="grid grid-cols-[minmax(0,1fr)_9rem_auto] gap-2">
            <Input id={`${g.id}-h${i}`} aria-label={`Hook ${i + 1}`} value={h.text} placeholder={`Hook ${i + 1}`} onChange={(e) => setHook(i, { text: e.target.value })} />
            <select
              id={`${g.id}-m${i}`} aria-label={`Mecanismo do hook ${i + 1}`}
              className="h-9 rounded-md border bg-background px-2 text-sm"
              value={h.mecanismo ?? ""}
              onChange={(e) => setHook(i, { mecanismo: e.target.value })}
            >
              <option value="">mecanismo</option>
              {MECH.map((m) => <option key={m} value={m}>{m}</option>)}
            </select>
            <Button
              size="icon" variant="ghost" aria-label={`Remover hook ${i + 1}`} disabled={d.hooks.length <= 1}
              onClick={() => change({ ...d, hooks: d.hooks.filter((_, j) => j !== i) })}
            >
              <Trash2Icon />
            </Button>
          </div>
        ))}
        <Button size="sm" variant="ghost" className="self-start" onClick={() => change({ ...d, hooks: [...d.hooks, { text: "", mecanismo: "" }] })}>
          <PlusIcon /> Adicionar hook
        </Button>
      </fieldset>
      <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">
        Corpo
        <Textarea id={`${g.id}-corpo`} rows={10} className="text-sm font-normal text-foreground" value={d.corpo} onChange={(e) => change({ ...d, corpo: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">
        CTA
        <Input id={`${g.id}-cta`} className="font-normal text-foreground" value={d.cta} placeholder="Opcional: o que pedes no fim" onChange={(e) => change({ ...d, cta: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">
        Notas para quem grava ou edita
        <Textarea id={`${g.id}-notas`} rows={2} className="font-normal text-foreground" value={d.notas} onChange={(e) => change({ ...d, notas: e.target.value })} />
      </label>
      <div className="flex flex-wrap items-center gap-3">
        <Button size="sm" onClick={async () => { if (await flush()) onClose(); }} disabled={state === "saving"}>
          {state === "saving" && <Loader2Icon className="animate-spin" />} Concluir
        </Button>
        <span className="text-xs text-muted-foreground" role="status" aria-live="polite">
          {state === "dirty" && "Alterações por guardar…"}
          {state === "saving" && "A guardar…"}
          {state === "saved" && `Guardado às ${savedAt}. Cada aprovação fica presa à versão que aprovaste.`}
          {state === "error" && <span className="text-destructive">Não ficou guardado.</span>}
          {state === "idle" && "Guarda sozinho enquanto escreves. Uma frase por linha."}
        </span>
      </div>
    </div>
  );
}
