"use client";

import { useState, type ReactNode } from "react";
import { ArrowUpRightIcon, CheckIcon, ChevronDownIcon, ChevronUpIcon, Loader2Icon, PencilIcon, PlayIcon, RotateCwIcon, UndoIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { LearnState, Stat, useLoad } from "@/components/learn/learn-shared";
import type { Access } from "@/lib/access";
import {
  GROUP_LABEL, JOB_LABEL, decideLesson, fetchLessons, pctRatio, promoteLesson, restoreLessonVersion, retireLesson, runLessonEditor,
  type Lesson, type LessonVersion, type LessonsPage,
} from "@/lib/lessons";

/*
 * Aprendizagem → Lições (PRD LRN-02, LRN-03, LRN-04; ADR-0069). O Editor de lições do motor propõe; quem tem
 * learn.lessons.approve aprova (com ou sem editar) ou rejeita. Cada aprovação, retirada ou volta atrás cria uma nova
 * versão imutável do conjunto que o motor lê. Nada muda sozinho. Em teste: flag learn.lessons. O servidor verifica tudo.
 */

const fmt = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";

export default function LicoesPage() {
  return (
    <WorkspaceGate need="learn.read">
      {(access) => <FlagGate flag="learn.lessons" ws={access.ws}><LessonsView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

function LessonsView({ access }: { access: Access }) {
  const page = useLoad(() => fetchLessons(access), access.ws);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState("");
  const act = async (key: string, fn: () => Promise<unknown>) => {
    setBusy(key); setErr("");
    try { await fn(); page.reload(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };
  const d = page.data ?? page.last;
  const jobActive = d?.job && ["queued", "running"].includes(d.job.status);

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Lições</h1>
          <p className="text-sm text-muted-foreground">
            O Editor de lições junta as edições e os motivos de cada dia e propõe regras curtas com evidência. Só passam a valer
            para o motor depois de alguém as aprovar; cada mudança fica numa versão a que podes voltar.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {d?.can.approve && (
            <Button size="sm" disabled={!!busy || !!jobActive} onClick={() => act("run", () => runLessonEditor(access))}>
              {busy === "run" ? <Loader2Icon className="animate-spin" /> : <PlayIcon />} Propor lições agora
            </Button>
          )}
          <Button size="sm" variant="outline" onClick={page.reload}><RotateCwIcon /> Atualizar</Button>
        </div>
      </div>
      {err && <Alert variant="destructive" role="alert"><AlertDescription>{err}</AlertDescription></Alert>}
      <LearnState loading={page.loading && !d} error={page.error} reload={page.reload} label="as lições" forbidden="Não tens acesso às lições deste cliente.">
        {d && <Body d={d} access={access} busy={busy} act={act} />}
      </LearnState>
    </div>
  );
}

type Act = (key: string, fn: () => Promise<unknown>) => Promise<void>;

function Body({ d, access, busy, act }: { d: LessonsPage; access: Access; busy: string; act: Act }) {
  const [showDecided, setShowDecided] = useState(false);
  const activeIds = new Set((d.active?.lessons ?? []).map((l) => l.id));
  return (
    <>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Edições com par" value={d.signals.edits} hint={`desde ${fmt(d.signals.since)}`} />
        <Stat label="Sem motivo" value={d.signals.no_reason} hint="decisões sem chip nem texto" />
        <Stat label="Aprovados sem editar" value={d.signals.unedited} hint="sinal positivo" />
        <Stat label="Alterações e rejeições" value={d.signals.rejected} />
      </div>
      {d.job && (
        <p className="text-xs text-muted-foreground" role="status">
          Última execução do Editor de lições: {JOB_LABEL[d.job.status] ?? d.job.status} ({fmt(d.job.finished_at ?? d.job.created_at)})
          {d.job.last_error ? `. Erro: ${d.job.last_error}` : ""}
        </p>
      )}

      <WidgetBoundary label="lições propostas">
        <section aria-labelledby="lrn-proposed" className="flex flex-col gap-3">
          <h2 id="lrn-proposed" className="text-lg font-semibold">Propostas <span className="text-sm font-normal text-muted-foreground">({d.proposed.length})</span></h2>
          {d.proposed.length === 0 ? (
            <Alert><AlertDescription>Sem lições propostas. O Editor de lições corre todas as manhãs com as edições do dia anterior{d.can.approve ? ", ou carrega em Propor lições agora" : ""}.</AlertDescription></Alert>
          ) : d.proposed.map((l) => <ProposedCard key={l.id} l={l} access={access} canDecide={d.can.approve} busy={busy} act={act} />)}
        </section>
      </WidgetBoundary>

      <WidgetBoundary label="lições em vigor">
        <section aria-labelledby="lrn-active" className="flex flex-col gap-3">
          <h2 id="lrn-active" className="text-lg font-semibold">Em vigor {d.active && <span className="text-sm font-normal text-muted-foreground">(versão {d.active.version_no})</span>}</h2>
          <VersionLessons v={d.active} empty="Ainda não há lições aprovadas neste cliente."
            action={d.can.approve ? (id) => (
              <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => act(`ret:${id}`, () => retireLesson(access, id))}>
                {busy === `ret:${id}` ? <Loader2Icon className="animate-spin" /> : <XIcon />} Retirar
              </Button>
            ) : undefined}
            extra={d.can.agency ? (id) => {
              const l = d.decided.find((x) => x.id === id);
              return l ? <PromoteButton l={l} access={access} busy={busy} act={act} /> : null;
            } : undefined}
          />
          {d.versions.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm">Versões</CardTitle><CardDescription>Voltar a uma versão cria uma versão nova com as mesmas lições; nada é apagado.</CardDescription></CardHeader>
              <CardContent>
                <ol className="flex flex-col divide-y text-sm">
                  {d.versions.map((v) => (
                    <li key={v.id} className="flex flex-wrap items-center gap-2 py-2">
                      <span className="font-medium tabular-nums">v{v.version_no}</span>
                      {v.active && <Badge>em vigor</Badge>}
                      <span className="text-muted-foreground">{v.n} {v.n === 1 ? "lição" : "lições"} · {changeLabel(v.change)} · {v.created_label ?? "—"} · {fmt(v.created_at)}</span>
                      {!v.active && d.can.approve && (
                        <Button size="sm" variant="ghost" className="ml-auto" disabled={!!busy} onClick={() => act(`rv:${v.id}`, () => restoreLessonVersion(access, v.id))}>
                          {busy === `rv:${v.id}` ? <Loader2Icon className="animate-spin" /> : <UndoIcon />} Voltar a esta versão
                        </Button>
                      )}
                    </li>
                  ))}
                </ol>
              </CardContent>
            </Card>
          )}
        </section>
      </WidgetBoundary>

      {d.agency && (
        <WidgetBoundary label="lições da agência">
          <section aria-labelledby="lrn-agency" className="flex flex-col gap-3 rounded-lg border border-dashed p-3">
            <h2 id="lrn-agency" className="text-lg font-semibold">Agência <span className="text-sm font-normal text-muted-foreground">(só a equipa da agência vê esta secção)</span></h2>
            <p className="text-sm text-muted-foreground">Regras gerais herdadas por todos os clientes. Guardam só a regra, nunca guiões ou números de um cliente. Em conflito prevalece a lição do cliente.</p>
            <VersionLessons v={d.agency.active} empty="Sem lições da agência em vigor." />
            {d.agency.proposed.map((l) => <ProposedCard key={l.id} l={l} access={access} canDecide={d.can.agency} busy={busy} act={act} />)}
          </section>
        </WidgetBoundary>
      )}

      {d.decided.length > 0 && (
        <section className="flex flex-col gap-2">
          <Button variant="ghost" size="sm" className="self-start" aria-expanded={showDecided} onClick={() => setShowDecided(!showDecided)}>
            {showDecided ? <ChevronUpIcon /> : <ChevronDownIcon />} Decididas ({d.decided.length})
          </Button>
          {showDecided && (
            <ul className="flex flex-col gap-2 text-sm">
              {d.decided.map((l) => (
                <li key={l.id} className="flex flex-wrap items-baseline gap-2 rounded-md border p-2">
                  <Badge variant={l.status === "approved" ? "default" : "outline"}>{l.status === "approved" ? (activeIds.has(l.id) ? "aprovada, em vigor" : "aprovada") : "rejeitada"}</Badge>
                  <Badge variant="outline">{GROUP_LABEL[l.category]}</Badge>
                  <span className="min-w-0 flex-1">{l.text}</span>
                  <span className="text-xs text-muted-foreground">{l.decided_label} · {fmt(l.decided_at)}{l.decision_note ? ` · “${l.decision_note}”` : ""}</span>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  );
}

const changeLabel = (c: LessonVersion["change"]) =>
  c.action === "approve" ? "lição aprovada" : c.action === "retire" ? "lição retirada" : `volta à v${c.from_version ?? "?"}`;

function VersionLessons({ v, empty, action, extra }: {
  v: LessonVersion | null; empty: string; action?: (id: string) => ReactNode; extra?: (id: string) => ReactNode;
}) {
  if (!v || v.lessons.length === 0) return <p className="text-sm text-muted-foreground">{empty}</p>;
  return (
    <ul className="flex flex-col gap-2">
      {v.lessons.map((l) => (
        <li key={l.id} className="flex flex-wrap items-center gap-2 rounded-md border p-2 text-sm">
          <Badge variant="outline">{GROUP_LABEL[l.category]}</Badge>
          <span className="min-w-0 flex-1">{l.text}</span>
          {extra?.(l.id)}
          {action?.(l.id)}
        </li>
      ))}
    </ul>
  );
}

function ProposedCard({ l, access, canDecide, busy, act }: { l: Lesson; access: Access; canDecide: boolean; busy: string; act: Act }) {
  const [editing, setEditing] = useState(false);
  const [rejecting, setRejecting] = useState(false);
  const [text, setText] = useState(l.text);
  const [note, setNote] = useState("");
  const [open, setOpen] = useState(false);
  const ex = l.evidence.examples ?? [];
  const textOk = text.trim().length >= 5 && text.trim().length <= 400;
  return (
    <Card data-lesson={l.id}>
      <CardContent className="flex flex-col gap-2 p-4">
        <div className="flex flex-wrap items-center gap-2 text-xs">
          <Badge variant="outline">{GROUP_LABEL[l.category]}</Badge>
          {l.level === "agency" && <Badge variant="secondary">agência</Badge>}
          {l.evidence.edits != null && <span className="text-muted-foreground">{l.evidence.edits} {l.evidence.edits === 1 ? "edição" : "edições"} como evidência</span>}
          <span className="ml-auto text-muted-foreground">{l.source === "engine" ? "Editor de lições" : "promovida de um cliente"} · {fmt(l.proposed_at)}</span>
        </div>
        {editing ? (
          <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">Texto da lição
            <Textarea rows={2} value={text} onChange={(e) => setText(e.target.value)} maxLength={400} className="text-sm font-normal text-foreground" />
          </label>
        ) : <p className="text-[15px] font-medium leading-snug">{l.text}</p>}
        {l.rationale && <p className="text-sm text-muted-foreground">{l.rationale}</p>}
        {l.evidence.codes && Object.keys(l.evidence.codes).length > 0 && (
          <p className="text-xs text-muted-foreground">Motivos: {Object.entries(l.evidence.codes).map(([c, n]) => `${c} (${n})`).join(", ")}</p>
        )}
        {ex.length > 0 && (
          <div>
            <Button size="sm" variant="ghost" aria-expanded={open} onClick={() => setOpen(!open)}>
              {open ? <ChevronUpIcon /> : <ChevronDownIcon />} Exemplos antes/depois ({ex.length})
            </Button>
            {open && (
              <ul className="mt-1 flex flex-col gap-2">
                {ex.map((e) => (
                  <li key={e.signal_id} className="grid gap-2 rounded-md bg-muted/40 p-2 text-xs sm:grid-cols-2">
                    <div><span className="font-medium">Motor</span> <span className="text-muted-foreground">· {e.content_id}</span><p className="mt-1 whitespace-pre-line">{e.before}</p></div>
                    <div><span className="font-medium">{e.after ? `Aprovado (mudou ${pctRatio(e.edit_ratio)})` : "Aprovado sem editar"}</span>
                      {e.after && <p className="mt-1 whitespace-pre-line">{e.after}</p>}
                      {e.note && <p className="mt-1 text-muted-foreground">“{e.note}”</p>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
        {canDecide && (
          rejecting ? (
            <form className="flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); void act(`rej:${l.id}`, () => decideLesson(access, l.id, "reject", undefined, note.trim())); }}>
              <Input className="min-w-[14rem] flex-1" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} autoFocus aria-label="Porque rejeitas (opcional)" placeholder="Porque rejeitas? (opcional)" />
              <Button size="sm" type="submit" variant="destructive" disabled={!!busy}>{busy === `rej:${l.id}` && <Loader2Icon className="animate-spin" />} Rejeitar</Button>
              <Button size="sm" type="button" variant="ghost" onClick={() => setRejecting(false)}>Cancelar</Button>
            </form>
          ) : (
            <div className="flex flex-wrap gap-2">
              <Button size="sm" disabled={!!busy || (editing && !textOk)}
                onClick={() => act(`ap:${l.id}`, () => decideLesson(access, l.id, "approve", editing && text.trim() !== l.text ? text.trim() : undefined))}>
                {busy === `ap:${l.id}` ? <Loader2Icon className="animate-spin" /> : <CheckIcon />} {editing ? "Aprovar com este texto" : "Aprovar"}
              </Button>
              {!editing && <Button size="sm" variant="outline" onClick={() => setEditing(true)}><PencilIcon /> Editar</Button>}
              {editing && <Button size="sm" variant="ghost" onClick={() => { setEditing(false); setText(l.text); }}>Desfazer edição</Button>}
              <Button size="sm" variant="outline" onClick={() => setRejecting(true)}><XIcon /> Rejeitar</Button>
            </div>
          )
        )}
      </CardContent>
    </Card>
  );
}

function PromoteButton({ l, access, busy, act }: { l: Lesson; access: Access; busy: string; act: Act }) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState(l.text);
  if (!open) return <Button size="sm" variant="ghost" onClick={() => setOpen(true)}><ArrowUpRightIcon /> Propor à agência</Button>;
  return (
    <form className="flex w-full flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); void act(`pr:${l.id}`, () => promoteLesson(access, l.id, text.trim())).then(() => setOpen(false)); }}>
      <Input className="min-w-[14rem] flex-1" value={text} onChange={(e) => setText(e.target.value)} maxLength={400} aria-label="Regra geral para a agência"
        placeholder="Escreve a regra sem nada deste cliente" />
      <Button size="sm" type="submit" disabled={!!busy || text.trim().length < 5}>{busy === `pr:${l.id}` && <Loader2Icon className="animate-spin" />} Propor</Button>
      <Button size="sm" type="button" variant="ghost" onClick={() => setOpen(false)}>Cancelar</Button>
    </form>
  );
}
