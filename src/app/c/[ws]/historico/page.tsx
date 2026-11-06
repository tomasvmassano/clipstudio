"use client";

import { useCallback, useEffect, useState } from "react";
import { ChevronDownIcon, ChevronRightIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import {
  ACTION_LABEL, AFFILIATION_LABEL, actionLabel, attemptLabel, changes, fetchAudit, fetchDenials,
  type AuditPage, type AuditRow, type DenialPage, type DenialRow,
} from "@/lib/audit";
import { fromLocalInput } from "@/lib/tasks";

/*
 * Histórico de ações do cliente (PRD R-05). Só leitura: o registo não se altera nem se apaga.
 * "Tentativas recusadas" lista as recusas gravadas por audit_denied_record (ADR-0066): quem, o quê, quando.
 * As tentativas de quem não tem acesso a este cliente só aparecem a quem audita a agência (nunca ao admin do cliente).
 */

const selectCls = "h-9 rounded-md border bg-background px-2 text-sm";
/** "Até" inclui o dia inteiro: o limite é a meia-noite do dia seguinte, no fuso do cliente. */
const nextDay = (d: string) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + 1); return `${x.toISOString().slice(0, 10)}T00:00`; };

export default function AuditoriaPage() {
  return <WorkspaceGate need="audit.read">{(access) => <Auditoria access={access} />}</WorkspaceGate>;
}

type Filters = { action: string; actor: string; from: string; to: string };

function Auditoria({ access }: { access: Access }) {
  const [view, setView] = useState<"all" | "denied">("all");
  const { ws } = useSession();
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Histórico</h1>
        <p className="text-sm text-muted-foreground">Quem fez o quê em {ws?.name}, com o antes e o depois. Não se altera nem se apaga.</p>
      </div>
      <div role="group" aria-label="Vista do histórico" className="flex gap-1">
        <Button size="sm" variant={view === "all" ? "secondary" : "ghost"} aria-pressed={view === "all"} onClick={() => setView("all")}>Todas as ações</Button>
        <Button size="sm" variant={view === "denied" ? "secondary" : "ghost"} aria-pressed={view === "denied"} onClick={() => setView("denied")}>Tentativas recusadas</Button>
      </div>
      {view === "all" ? <Actions access={access} /> : <Denials access={access} />}
    </div>
  );
}

function Actions({ access }: { access: Access }) {
  const { ws } = useSession();
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [f, setF] = useState<Filters>({ action: "", actor: "", from: "", to: "" });
  const [page, setPage] = useState<AuditPage | null>(null);
  const [rows, setRows] = useState<AuditRow[]>([]);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);

  const load = useCallback((before: number | null) => fetchAudit(access.ws, {
    action: f.action || null, actor: f.actor || null,
    from: f.from ? fromLocalInput(`${f.from}T00:00`, tz) : null, to: f.to ? fromLocalInput(nextDay(f.to), tz) : null, before,
  }), [access.ws, f, tz]);

  useEffect(() => {
    let alive = true;
    load(null).then((p) => { if (alive) { setPage(p); setRows(p.rows); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [load, rev]);

  return (
    <div className="flex flex-col gap-4">
      <Card><CardContent className="flex flex-wrap items-end gap-3 pt-4 text-sm">
        <label className="flex flex-col gap-1">Ação
          <select aria-label="Filtrar por ação" className={selectCls} value={f.action} onChange={(e) => setF({ ...f, action: e.target.value })}>
            <option value="">Todas</option>
            {(page?.actions ?? []).map((a) => <option key={a} value={a}>{actionLabel(a)}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">Pessoa
          <select aria-label="Filtrar por pessoa" className={selectCls} value={f.actor} onChange={(e) => setF({ ...f, actor: e.target.value })}>
            <option value="">Todas</option>
            {(page?.actors ?? []).map((a) => <option key={a.id} value={a.id}>{a.label ?? a.id}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">De<Input type="date" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></label>
        <label className="flex flex-col gap-1">Até<Input type="date" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></label>
        {(f.action || f.actor || f.from || f.to) && <Button size="sm" variant="ghost" onClick={() => setF({ action: "", actor: "", from: "", to: "" })}>Limpar filtros</Button>}
      </CardContent></Card>

      {err ? (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ) : !page ? <Skeleton className="h-64" /> : rows.length === 0 ? (
        <Alert><AlertDescription>Nada no histórico com estes filtros.</AlertDescription></Alert>
      ) : (
        <Card><CardContent className="divide-y p-0">
          {rows.map((r) => <Row key={r.id} r={r} tz={tz} />)}
        </CardContent></Card>
      )}
      {page?.next_before && !err && (
        <div><Button variant="outline" disabled={busy} onClick={async () => {
          setBusy(true);
          try { const p = await load(page.next_before); setPage({ ...p, actions: page.actions, actors: page.actors }); setRows((x) => [...x, ...p.rows]); }
          catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
        }}>{busy && <Loader2Icon className="animate-spin" />} Carregar mais</Button></div>
      )}
    </div>
  );
}

function Row({ r, tz }: { r: AuditRow; tz: string }) {
  const [open, setOpen] = useState(false);
  const diff = changes(r.before, r.after);
  const when = new Date(r.at).toLocaleString("pt-PT", { timeZone: tz, day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  return (
    <div data-audit={r.id} className="px-4 py-3 text-sm">
      <button className="flex w-full items-start gap-2 text-left" onClick={() => setOpen(!open)} aria-expanded={open} disabled={diff.length === 0}>
        {diff.length ? (open ? <ChevronDownIcon className="mt-0.5 size-4 shrink-0" /> : <ChevronRightIcon className="mt-0.5 size-4 shrink-0" />) : <span className="size-4 shrink-0" />}
        <span className="flex-1">
          <b>{r.actor ?? "Desconhecido"}</b> · {ACTION_LABEL[r.action] ?? actionLabel(r.action)}
          {r.entity_id && <span className="text-muted-foreground"> · {r.entity_type} {r.entity_id.length > 24 ? r.entity_id.slice(0, 8) + "…" : r.entity_id}</span>}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground">{when}</span>
      </button>
      {open && diff.length > 0 && (
        <table className="mt-2 ml-6 text-xs">
          <tbody>
            {diff.map((d) => (
              <tr key={d.key} className="align-top">
                <td className="pr-3 font-medium">{d.key}</td>
                <td className="pr-3 text-muted-foreground line-through">{d.before}</td>
                <td>{d.after}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

function Denials({ access }: { access: Access }) {
  const { ws } = useSession();
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [page, setPage] = useState<DenialPage | null>(null);
  const [rows, setRows] = useState<DenialRow[]>([]);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchDenials(access.ws, null).then((p) => { if (alive) { setPage(p); setRows(p.rows); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access.ws, rev]);

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        Pedidos que o servidor recusou por falta de permissão, com quem tentou, o quê e quando.
        {page?.includes_outside ? " Inclui tentativas de quem não tem acesso a este cliente (só a agência vê estas)." : ""}
      </p>
      {err ? (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => { setErr(""); setPage(null); setRev((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ) : !page ? <Skeleton className="h-64" /> : rows.length === 0 ? (
        <Alert><AlertDescription>Nenhuma tentativa recusada registada.</AlertDescription></Alert>
      ) : (
        <Card><CardContent className="divide-y p-0">
          {rows.map((r) => <DenialItem key={r.id} r={r} tz={tz} />)}
        </CardContent></Card>
      )}
      {page?.next_before && !err && (
        <div><Button variant="outline" disabled={busy} onClick={async () => {
          setBusy(true);
          try { const p = await fetchDenials(access.ws, page.next_before); setPage(p); setRows((x) => [...x, ...p.rows]); }
          catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
        }}>{busy && <Loader2Icon className="animate-spin" />} Carregar mais</Button></div>
      )}
    </div>
  );
}

function DenialItem({ r, tz }: { r: DenialRow; tz: string }) {
  const when = new Date(r.at).toLocaleString("pt-PT", { timeZone: tz, day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  return (
    <div data-denial={r.id} className="flex flex-col gap-1 px-4 py-3 text-sm">
      <div className="flex items-start gap-2">
        <span className="flex-1">
          <b>{r.actor ?? "Desconhecido"}</b> · tentou <span className="font-medium">{attemptLabel(r.attempted)}</span>
          {r.entity_id && <span className="text-muted-foreground"> · {r.entity_id.length > 24 ? r.entity_id.slice(0, 8) + "…" : r.entity_id}</span>}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground">{when}</span>
      </div>
      <div className="flex flex-wrap gap-1.5 text-xs text-muted-foreground">
        {r.scope === "fora" && <Badge variant="destructive">fora deste cliente</Badge>}
        {r.affiliation && <span>{AFFILIATION_LABEL[r.affiliation] ?? r.affiliation}</span>}
        {r.capability && <span>· precisava de {r.capability}{r.verified === false ? " (já tem: recusa por outro motivo)" : ""}</span>}
        {r.preview && <span>· durante a pré-visualização de outro papel</span>}
        {r.via === "api" && <span>· pedido ao servidor</span>}
      </div>
    </div>
  );
}
