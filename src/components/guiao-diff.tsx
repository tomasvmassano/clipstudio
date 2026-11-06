"use client";

import { useMemo, useState } from "react";
import { Loader2Icon, RotateCcwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { FORMATO_LABEL, type ContentHistory, type Guiao } from "@/lib/types";
import { diffStats, diffVersions, recordedVersionNo, type DiffOp, type FieldDiff, type VersionText } from "@/lib/version-diff";

const fmt = (iso: string) => new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Dubai" });
const WORK = "work";

type Entry = VersionText & {
  id: string; label: string; versionNo: number | null; at: string | null; author: string | null;
  approved: boolean; recorded: boolean; current: boolean; hasMeta: boolean;
};

const sameText = (a: VersionText, b: VersionText) =>
  a.corpo === b.corpo && (a.cta ?? "") === (b.cta ?? "") && (a.formato ?? "") === (b.formato ?? "") && (a.tema ?? "") === (b.tema ?? "")
  && a.hooks.length === b.hooks.length && a.hooks.every((x, i) => x.text === b.hooks[i].text);

/** Versões do histórico mais a cópia de trabalho (quando ainda não foi guardada como versão). */
export function compareEntries(g: Guiao, h: ContentHistory): Entry[] {
  const recNo = recordedVersionNo(h.transitions);
  const recId = h.recorded_version_id !== undefined ? h.recorded_version_id : h.versions.find((v) => v.version_no === recNo)?.id ?? null;
  const list: Entry[] = h.versions.map((v) => ({
    id: v.id, label: `v${v.version_no}`, versionNo: v.version_no, at: v.created_at, author: v.author,
    hooks: v.hooks, corpo: v.corpo, cta: v.cta, formato: v.formato ?? null, tema: v.tema ?? null,
    approved: v.is_approved, recorded: v.is_recorded ?? v.id === recId, current: v.is_current, hasMeta: "formato" in v,
  }));
  const work: Entry = {
    id: WORK, label: "Cópia de trabalho", versionNo: null, at: g.updated_at, author: null,
    hooks: g.hooks, corpo: g.corpo, cta: g.cta, formato: g.formato, tema: g.tema,
    approved: false, recorded: false, current: false, hasMeta: true,
  };
  const cur = list.find((e) => e.current);
  if (!cur || !sameText(cur, work)) list.unshift(work);
  return list;
}

function Marks({ e }: { e: Entry }) {
  return (
    <>
      {e.approved && <Badge className="bg-primary text-primary-foreground">aprovada</Badge>}
      {e.recorded && <Badge variant="secondary">gravada</Badge>}
      {e.current && <Badge variant="outline">em vigor</Badge>}
      {e.id === WORK && <Badge variant="outline">por guardar como versão</Badge>}
    </>
  );
}

/** Um troço do diff. Cor nunca é o único sinal: marcador visível (− / +), risco ou sublinhado e texto para leitores de ecrã. */
function Piece({ o }: { o: DiffOp }) {
  if (o.op === "eq") return <span>{o.text}</span>;
  if (o.op === "del")
    return (
      <del className="rounded-sm bg-destructive/15 text-foreground decoration-destructive decoration-2">
        <span className="sr-only">[removido: </span><span aria-hidden className="font-mono text-[0.85em] font-bold text-destructive">−</span>{o.text}<span className="sr-only">]</span>
      </del>
    );
  return (
    <ins className="rounded-sm bg-emerald-500/15 text-foreground underline decoration-emerald-600 decoration-2">
      <span className="sr-only">[acrescentado: </span><span aria-hidden className="font-mono text-[0.85em] font-bold text-emerald-700 dark:text-emerald-400">+</span>{o.text}<span className="sr-only">]</span>
    </ins>
  );
}

const STATUS: Record<FieldDiff["status"], string> = { same: "igual", changed: "alterado", added: "acrescentado", removed: "removido" };

function Field({ f, mode }: { f: FieldDiff; mode: "side" | "inline" }) {
  const empty = <span className="italic text-muted-foreground">vazio</span>;
  const left = f.ops.filter((o) => o.op !== "add"), right = f.ops.filter((o) => o.op !== "del");
  return (
    <section className="rounded-lg border p-3 text-sm" aria-label={`${f.label}: ${STATUS[f.status]}`} data-field={f.key} data-status={f.status}>
      <h4 className="mb-1.5 flex items-center gap-2 text-xs font-medium">
        {f.label}
        <span className="text-muted-foreground">· {STATUS[f.status]}</span>
      </h4>
      {mode === "inline" ? (
        <p className="whitespace-pre-line leading-relaxed">{f.ops.length ? f.ops.map((o, i) => <Piece key={i} o={o} />) : empty}</p>
      ) : (
        <div className="grid gap-2 md:grid-cols-2">
          <p className="whitespace-pre-line leading-relaxed" aria-label="antes">{left.some((o) => o.text) ? left.map((o, i) => <Piece key={i} o={o} />) : empty}</p>
          <p className="whitespace-pre-line leading-relaxed md:border-l md:pl-3" aria-label="depois">{right.some((o) => o.text) ? right.map((o, i) => <Piece key={i} o={o} />) : empty}</p>
        </div>
      )}
    </section>
  );
}

/** Comparar duas versões de um guião (FR-02-06, FR-05-06). Restaurar usa o caminho do servidor (content_restore_version). */
export function VersionCompare({ g, h, canRestore, busy, onRestore, initialFrom }: {
  g: Guiao; h: ContentHistory; canRestore: boolean; busy: string | null; onRestore: (versionId: string) => Promise<boolean>; initialFrom?: string | null;
}) {
  const entries = useMemo(() => compareEntries(g, h), [g, h]);
  const defaults = useMemo(() => {
    const to = entries[0]?.id ?? "";
    const asked = initialFrom && initialFrom !== to ? entries.find((e) => e.id === initialFrom) : undefined;
    const approved = entries.find((e) => e.approved && e.id !== to);
    const from = asked?.id ?? approved?.id ?? entries.find((e) => e.id !== to)?.id ?? to;
    return { from, to };
  }, [entries, initialFrom]);
  const [pick, setPick] = useState<{ from: string; to: string } | null>(null);
  const [mode, setMode] = useState<"side" | "inline">("side");
  const [showSame, setShowSame] = useState(false);
  const [confirm, setConfirm] = useState<string | null>(null);

  const fromId = pick && entries.some((e) => e.id === pick.from) ? pick.from : defaults.from;
  const toId = pick && entries.some((e) => e.id === pick.to) ? pick.to : defaults.to;
  const a = entries.find((e) => e.id === fromId), b = entries.find((e) => e.id === toId);
  const fields = useMemo(() => {
    if (!a || !b) return [];
    const all = diffVersions(a, b, { formato: (v) => (v ? FORMATO_LABEL[v] ?? v : "") });
    return a.hasMeta && b.hasMeta ? all : all.filter((f) => f.key !== "formato" && f.key !== "tema");
  }, [a, b]);
  const stats = diffStats(fields);
  const work = entries.find((e) => e.id === WORK) ?? null;

  if (entries.length < 2 || !a || !b) {
    return <p className="text-sm text-muted-foreground">Só há uma versão deste guião. Quando houver outra, podes compará-las aqui.</p>;
  }

  const select = (key: "from" | "to", label: string) => (
    <label className="flex min-w-0 flex-1 flex-col gap-1 text-xs font-medium">
      {label}
      <select
        className="h-9 rounded-md border bg-background px-2 text-sm"
        value={key === "from" ? fromId : toId}
        onChange={(ev) => setPick({ from: fromId, to: toId, [key]: ev.target.value })}
      >
        {entries.map((e) => (
          <option key={e.id} value={e.id}>
            {e.label}{e.approved ? " · aprovada" : ""}{e.recorded ? " · gravada" : ""}{e.current ? " · em vigor" : ""}
          </option>
        ))}
      </select>
    </label>
  );

  const header = (e: Entry, side: string) => {
    const restorable = canRestore && e.id !== WORK && !sameText(e, work ?? entries.find((x) => x.current) ?? e);
    return (
      <div className="flex min-w-0 flex-1 flex-col gap-1.5 rounded-lg border p-2.5 text-xs">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-muted-foreground">{side}</span>
          <b className="font-mono">{e.label}</b>
          <Marks e={e} />
        </div>
        {e.at && <span className="text-muted-foreground">{e.id === WORK ? "alterada a " : ""}{fmt(e.at)}{e.author ? ` · ${e.author}` : ""}</span>}
        {restorable && confirm !== e.id && (
          <Button size="sm" variant="outline" className="w-fit" disabled={busy !== null} onClick={() => setConfirm(e.id)}>
            <RotateCcwIcon /> Restaurar esta versão
          </Button>
        )}
        {restorable && confirm === e.id && (
          <div role="alertdialog" aria-label={`Restaurar ${e.label}`} className="flex flex-col gap-2 rounded-md bg-muted p-2">
            <p>
              O texto de {e.label} passa para a cópia de trabalho. Nenhuma versão é apagada.
              {g.editorial_status === "approved" && " O guião está aprovado: volta a rascunho e precisa de nova aprovação. A versão aprovada fica guardada tal como está."}
            </p>
            <div className="flex gap-2">
              <Button size="sm" disabled={busy !== null} onClick={async () => { if (await onRestore(e.id)) setConfirm(null); }}>
                {busy === e.id ? <Loader2Icon className="animate-spin" /> : <RotateCcwIcon />} Restaurar
              </Button>
              <Button size="sm" variant="ghost" disabled={busy !== null} onClick={() => setConfirm(null)}>Cancelar</Button>
            </div>
          </div>
        )}
      </div>
    );
  };

  const shown = showSame ? fields : fields.filter((f) => f.changed);
  return (
    <div className="flex flex-col gap-3" data-testid="version-compare">
      <div className="flex flex-col gap-2 sm:flex-row">
        {select("from", "Antes")}
        {select("to", "Depois")}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <div role="group" aria-label="Modo de comparação" className="inline-flex rounded-md border p-0.5">
          <Button size="sm" variant={mode === "side" ? "secondary" : "ghost"} aria-pressed={mode === "side"} onClick={() => setMode("side")}>Lado a lado</Button>
          <Button size="sm" variant={mode === "inline" ? "secondary" : "ghost"} aria-pressed={mode === "inline"} onClick={() => setMode("inline")}>Em linha</Button>
        </div>
        <label className="flex items-center gap-1.5 text-xs">
          <input type="checkbox" checked={showSame} onChange={(ev) => setShowSame(ev.target.checked)} /> Mostrar campos iguais
        </label>
      </div>
      <div className="flex flex-col gap-2 sm:flex-row">
        {header(a, "Antes")}
        {header(b, "Depois")}
      </div>
      <p className="text-xs text-muted-foreground" role="status">
        {fromId === toId ? "Escolheste a mesma versão dos dois lados."
          : stats.fields === 0 ? "Sem diferenças no texto."
          : `${stats.fields} ${stats.fields === 1 ? "campo mudou" : "campos mudaram"}: +${stats.added} ${stats.added === 1 ? "palavra" : "palavras"}, −${stats.removed} ${stats.removed === 1 ? "palavra" : "palavras"}.`}
        {(!a.hasMeta || !b.hasMeta) && " Formato e tema ainda não estão disponíveis nesta comparação."}
      </p>
      <p className="text-xs text-muted-foreground">
        <span aria-hidden className="font-mono font-bold text-destructive">−</span> riscado: saiu ·{" "}
        <span aria-hidden className="font-mono font-bold text-emerald-700 dark:text-emerald-400">+</span> sublinhado: entrou
      </p>
      {shown.map((f) => <Field key={f.key} f={f} mode={mode} />)}
    </div>
  );
}
