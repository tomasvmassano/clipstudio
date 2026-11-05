"use client";

import { useCallback, useEffect, useState } from "react";
import { CheckCheckIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { WsLink } from "@/components/ws-link";
import type { Access } from "@/lib/access";
import { PRODUCTION_LABEL, type ProductionStatus } from "@/lib/calendar";
import { approvable, blockedReason, fetchPendingApproval, type PendingApproval } from "@/lib/pending-approval";
import { bulkRun, type BulkItem, type BulkResult } from "@/lib/search";
import { EDITORIAL_LABEL, type EditorialStatus } from "@/lib/types";

/*
 * "Gravados por aprovar" (FR-02-05, FR-17-07; ADR-0047): guiões já gravados que ficaram em revisão, de todos os dias, para
 * aprovar em lote. Pré-visualização primeiro (o servidor corre e desfaz), confirmação com chave de idempotência. Só entram os
 * que têm o texto igual ao que foi gravado; o servidor volta a verificar cada um (recorded_only).
 */
export function PendingApprovalButton({ access, onDone }: { access: Access; onDone: () => Promise<void> | void }) {
  const [data, setData] = useState<PendingApproval | null>(null);
  const [err, setErr] = useState("");
  const [open, setOpen] = useState(false);
  const load = useCallback(async () => {
    try { setData(await fetchPendingApproval(access)); setErr(""); }
    catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => {
    let alive = true;
    fetchPendingApproval(access).then((d) => { if (alive) setData(d); }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access]);
  const n = data?.items.length ?? 0;
  if (!err && n === 0) return null;   // nada por aprovar (ou ainda a carregar): sem botão
  return (
    <>
      <Button size="sm" variant="outline" onClick={() => { setOpen(true); void load(); }} title={err || undefined}>
        <CheckCheckIcon /> Gravados por aprovar {err ? "" : <Badge variant="secondary" className="ml-1 tabular-nums">{n}</Badge>}
      </Button>
      {open && <PendingDialog access={access} data={data} err={err} reload={load}
        onClose={async (changed) => { setOpen(false); if (changed) { await load(); await onDone(); } }} />}
    </>
  );
}

type Step = "pick" | "preview" | "done";

function PendingDialog({ access, data, err, reload, onClose }: {
  access: Access; data: PendingApproval | null; err: string; reload: () => Promise<void>; onClose: (changed: boolean) => void;
}) {
  const items = data?.items ?? [];
  const can = data?.can ?? { submit: false, bulk: false };
  const ok = items.filter((it) => approvable(it, can)).map((it) => it.id);
  const [sel, setSel] = useState<Set<string>>(() => new Set());
  const [step, setStep] = useState<Step>("pick");
  const [res, setRes] = useState<BulkResult | null>(null);
  const [key, setKey] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const ids = ok.filter((id) => sel.has(id));
  const byId = new Map(items.map((it) => [it.id, it]));
  const label = (id: string) => { const it = byId.get(id); return it ? `Guião ${it.n} de ${it.date}${it.tema ? ` · ${it.tema}` : ""}` : id; };
  const toggle = (id: string) => setSel((p) => { const s = new Set(p); if (s.has(id)) s.delete(id); else s.add(id); return s; });

  const preview = async () => {
    setBusy(true); setMsg("");
    try { setRes(await bulkRun(access, ids, "approve", { recorded_only: true }, null, true)); setKey(crypto.randomUUID()); setStep("preview"); }
    catch (e) { setMsg((e as Error).message); }
    finally { setBusy(false); }
  };
  const confirm = async () => {
    setBusy(true); setMsg("");
    try { setRes(await bulkRun(access, ids, "approve", { recorded_only: true }, key, false)); setStep("done"); }
    catch (e) { setMsg(`${(e as Error).message} Podes tentar de novo: não se aplica duas vezes.`); }
    finally { setBusy(false); }
  };
  const itemLine = (it: BulkItem) => (
    <li key={it.id} className="rounded-md border px-2 py-1.5 text-sm">
      <div className="truncate font-medium">{label(it.id)}</div>
      {it.ok
        ? <div className="text-xs text-muted-foreground">{it.changed ? "Fica aprovado (a versão gravada)" : "Já estava aprovado"}</div>
        : <div className="text-xs text-destructive">Não pode: {it.detail || it.error}</div>}
    </li>
  );

  return (
    <Dialog open onOpenChange={(o) => { if (!o && !busy) onClose(step === "done"); }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Gravados por aprovar</DialogTitle>
          <DialogDescription>
            {step === "pick" ? "Guiões já gravados que ainda não estão aprovados, de todos os dias. Cada aprovação fica presa à versão que foi gravada."
              : step === "preview" ? "Pré-visualização: ainda nada foi gravado."
              : res?.replayed ? "Este pedido já tinha sido aplicado: mostro o resultado guardado." : "Feito. Cada aprovação ficou no histórico do guião."}
          </DialogDescription>
        </DialogHeader>

        {err && (
          <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
            <Button size="sm" variant="outline" onClick={() => void reload()}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
        )}
        {!can.bulk && data && (
          <Alert><AlertDescription>A aprovação em lote ainda não está ligada neste cliente (Funcionalidades em teste: <i>Operações em lote nos guiões</i>). Podes aprovar cada guião no dia dele.</AlertDescription></Alert>
        )}

        {step === "pick" && (
          !data ? <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2Icon className="size-4 animate-spin" /> A carregar…</div>
          : items.length === 0 ? <p className="text-sm text-muted-foreground">Não há guiões gravados por aprovar.</p>
          : (
            <div className="flex flex-col gap-2">
              <div className="flex items-center justify-between gap-2 text-sm">
                <span aria-live="polite"><b className="tabular-nums">{ids.length}</b> de {ok.length} selecionados{ok.length < items.length ? ` (${items.length - ok.length} precisam de ser vistos à mão)` : ""}</span>
                <Button size="sm" variant="ghost" disabled={!ok.length} onClick={() => setSel(ids.length === ok.length ? new Set() : new Set(ok))}>
                  {ids.length === ok.length && ok.length ? "Limpar seleção" : "Selecionar os que podem"}
                </Button>
              </div>
              <ul className="flex max-h-[50vh] flex-col gap-1 overflow-y-auto">
                {items.map((it) => {
                  const why = blockedReason(it, can);
                  return (
                    <li key={it.id} className="flex items-start gap-2 rounded-md border px-2 py-1.5 text-sm">
                      <input type="checkbox" className="mt-1 size-4 shrink-0 accent-primary" disabled={!!why || !can.bulk} checked={!why && sel.has(it.id)}
                             onChange={() => toggle(it.id)} aria-label={`Selecionar ${label(it.id)}`} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate font-medium">{label(it.id)}</div>
                        <div className="truncate text-xs text-muted-foreground">{it.hook ?? ""}</div>
                        <div className="flex flex-wrap items-center gap-1 pt-0.5 text-xs">
                          <Badge variant="outline">{EDITORIAL_LABEL[it.editorial_status as EditorialStatus] ?? it.editorial_status}</Badge>
                          <Badge variant="outline">{PRODUCTION_LABEL[it.production_status as ProductionStatus] ?? it.production_status}</Badge>
                          {it.recorded_version_no != null && <span className="text-muted-foreground">versão gravada v{it.recorded_version_no}</span>}
                        </div>
                        {why && (
                          <div className="text-xs text-amber-700 dark:text-amber-400">
                            {why} <WsLink className="underline underline-offset-2" href={`/guioes?date=${it.date}&open=${encodeURIComponent(it.id)}`}>Abrir</WsLink>
                          </div>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            </div>
          )
        )}
        {step !== "pick" && res && (
          <div className="flex flex-col gap-2">
            <p className="text-sm"><b>{res.summary.changed}</b> {step === "done" ? "aprovados" : "ficam aprovados"}
              {res.summary.failed ? <>, <b className="text-destructive">{res.summary.failed}</b> não podem</> : null}.</p>
            <ul className="flex max-h-[45vh] flex-col gap-1 overflow-y-auto">{res.results.map(itemLine)}</ul>
          </div>
        )}
        {msg && <Alert variant="destructive"><AlertDescription>{msg}</AlertDescription></Alert>}

        <DialogFooter>
          {step === "pick" && <>
            <Button variant="ghost" disabled={busy} onClick={() => onClose(false)}>Fechar</Button>
            <Button disabled={!ids.length || busy || !can.bulk} onClick={preview}>{busy ? <Loader2Icon className="animate-spin" /> : <CheckCheckIcon />} Aprovar selecionados</Button>
          </>}
          {step === "preview" && <>
            <Button variant="ghost" disabled={busy} onClick={() => setStep("pick")}>Voltar</Button>
            <Button disabled={busy || !res?.summary.changed} onClick={confirm}>{busy ? <Loader2Icon className="animate-spin" /> : null} Confirmar {res?.summary.changed ?? 0} aprovações</Button>
          </>}
          {step === "done" && <Button onClick={() => onClose(true)}>Fechar</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
