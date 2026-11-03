"use client";

import { useEffect, useState } from "react";
import { CheckCheckIcon, DownloadIcon, Loader2Icon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { friendlyError, type Access } from "@/lib/access";
import { addDays, todayDubai } from "@/lib/data";
import { fetchOwners, fetchProjects, parseTags, type Owner, type Project } from "@/lib/projects";
import { bulkExport, bulkRun, toCsv, type BulkAction, type BulkItem, type BulkResult, type BulkSnapshot } from "@/lib/search";
import { EDITORIAL_LABEL, type EditorialStatus, type Guiao } from "@/lib/types";

/*
 * Operações em lote nos guiões (FR-17-07, ADR-0035): responsável, campanha, etiquetas, aprovar, reagendar e exportar CSV.
 * Cada ação mostra primeiro o impacto (o servidor corre o lote e desfaz) e só grava depois de confirmar. A confirmação leva
 * uma chave de idempotência: repetir depois de uma falha de rede não aplica duas vezes.
 */

export type BulkCaps = { edit: boolean; approve: boolean; schedule: boolean; export: boolean };
const selectCls = "h-8 w-full rounded-md border bg-background px-2 text-sm";
const ACTION_LABEL: Record<BulkAction, string> = {
  owner: "Mudar responsável", project: "Mudar campanha", tags: "Etiquetas", approve: "Aprovar", reschedule: "Reagendar",
};

function describe(action: BulkAction, s: BulkSnapshot | null | undefined): string {
  if (!s) return "";
  switch (action) {
    case "owner": return s.owner ?? "sem responsável";
    case "project": return s.project ?? "sem campanha";
    case "tags": return s.tags.length ? s.tags.map((t) => `#${t}`).join(" ") : "sem etiquetas";
    case "approve": return EDITORIAL_LABEL[s.editorial_status as EditorialStatus] ?? s.editorial_status;
    case "reschedule": return s.date;
  }
}
const itemError = (it: BulkItem) => it.detail || friendlyError(it.error ?? "");

export function GuioesBulkBar({ access, selected, rows, caps, onClear, onSelectAll, allSelected, onDone }: {
  access: Access; selected: string[]; rows: Guiao[]; caps: BulkCaps; onClear: () => void; onSelectAll: () => void; allSelected: boolean;
  onDone: () => Promise<void> | void;
}) {
  const [action, setAction] = useState<BulkAction | null>(null);
  const [exporting, setExporting] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const n = selected.length;

  const doExport = async () => {
    setExporting(true); setMsg(null);
    try {
      const r = await bulkExport(access, selected);
      const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([toCsv(r.rows)], { type: "text/csv;charset=utf-8" }));
      a.download = `guioes-${access.ws}-${todayDubai()}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      setMsg({ kind: "ok", text: `Exportados ${r.rows.length} guiões${r.missing ? ` (${r.missing} já não existem ou não são deste cliente)` : ""}.` });
    } catch (e) { setMsg({ kind: "err", text: (e as Error).message }); }
    finally { setExporting(false); }
  };

  return (
    <div className="sticky top-0 z-10 flex flex-col gap-2 rounded-lg border bg-background/95 p-2 shadow-sm backdrop-blur" role="region" aria-label="Ações em lote">
      <div className="flex flex-wrap items-center gap-2">
        <span className="px-1 text-sm font-medium tabular-nums" aria-live="polite">{n} {n === 1 ? "selecionado" : "selecionados"}</span>
        <Button size="sm" variant="ghost" onClick={allSelected ? onClear : onSelectAll}>{allSelected ? "Limpar seleção" : "Selecionar todos os visíveis"}</Button>
        <div className="flex flex-wrap items-center gap-1 sm:ml-auto">
          {caps.edit && (["owner", "project", "tags"] as BulkAction[]).map((a) => (
            <Button key={a} size="sm" variant="outline" disabled={!n} onClick={() => { setMsg(null); setAction(a); }}>{ACTION_LABEL[a]}</Button>
          ))}
          {caps.schedule && <Button size="sm" variant="outline" disabled={!n} onClick={() => { setMsg(null); setAction("reschedule"); }}>Reagendar</Button>}
          {caps.approve && <Button size="sm" variant="outline" disabled={!n} onClick={() => { setMsg(null); setAction("approve"); }}><CheckCheckIcon /> Aprovar</Button>}
          {caps.export && <Button size="sm" variant="outline" disabled={!n || exporting} onClick={doExport}>{exporting ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Exportar CSV</Button>}
          <Button size="icon-sm" variant="ghost" aria-label="Sair da seleção" onClick={onClear}><XIcon /></Button>
        </div>
      </div>
      {!caps.edit && !caps.approve && !caps.schedule && !caps.export && (
        <p className="px-1 text-xs text-muted-foreground">Não tens permissão para ações em lote neste cliente.</p>
      )}
      {msg && (
        <Alert variant={msg.kind === "err" ? "destructive" : "default"}>
          <AlertDescription className="flex items-center justify-between gap-2"><span>{msg.text}</span><Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button></AlertDescription>
        </Alert>
      )}
      {action && (
        <BulkDialog
          key={action}
          access={access}
          action={action}
          ids={selected}
          rows={rows}
          onClose={async (changed, summary) => {
            setAction(null);
            if (summary) setMsg({ kind: summary.failed ? "err" : "ok", text: `${ACTION_LABEL[action]}: ${summary.changed} mudaram${summary.failed ? `, ${summary.failed} não puderam mudar` : ""}.` });
            if (changed) await onDone();
          }}
        />
      )}
    </div>
  );
}

type Step = "input" | "preview" | "done";

function BulkDialog({ access, action, ids, rows, onClose }: {
  access: Access; action: BulkAction; ids: string[]; rows: Guiao[]; onClose: (changed: boolean, summary?: BulkResult["summary"]) => void;
}) {
  const [step, setStep] = useState<Step>(action === "approve" ? "preview" : "input");
  const [args, setArgs] = useState<Record<string, unknown>>(() => action === "tags" ? { mode: "add", tags: [] } : action === "reschedule" ? { date: addDays(todayDubai(), 1) } : {});
  const [tagText, setTagText] = useState("");
  const [owners, setOwners] = useState<Owner[] | null>(null);
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [listErr, setListErr] = useState("");
  const [preview, setPreview] = useState<BulkResult | null>(null);
  const [result, setResult] = useState<BulkResult | null>(null);
  const [busy, setBusy] = useState(action === "approve");
  const [err, setErr] = useState("");
  const [key, setKey] = useState<string | null>(null);
  const byId = new Map(rows.map((g) => [g.id, g]));
  const label = (id: string) => { const g = byId.get(id); return g ? `Guião ${g.n}${g.tema ? ` · ${g.tema}` : ""}` : id; };

  useEffect(() => {
    let alive = true;
    if (action === "owner") fetchOwners(access).then((o) => { if (alive) setOwners(o); }).catch((e: Error) => { if (alive) setListErr(e.message); });
    if (action === "project") fetchProjects(access, true).then((p) => { if (alive) setProjects(p.projects.filter((x) => x.status === "ativa")); }).catch((e: Error) => { if (alive) setListErr(e.message); });
    return () => { alive = false; };
  }, [access, action]);

  const finalArgs = () => (action === "tags" ? { ...args, tags: parseTags(tagText) } : args);
  const runPreview = async () => {
    setBusy(true); setErr("");
    try { setPreview(await bulkRun(access, ids, action, finalArgs(), null, true)); setKey(crypto.randomUUID()); setStep("preview"); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };
  // aprovar não tem argumentos: o impacto aparece logo
  useEffect(() => {
    if (action !== "approve") return;
    let alive = true;
    bulkRun(access, ids, "approve", {}, null, true)
      .then((r) => { if (alive) { setPreview(r); setKey(crypto.randomUUID()); } })
      .catch((e: Error) => { if (alive) setErr(e.message); })
      .finally(() => { if (alive) setBusy(false); });
    return () => { alive = false; };
  }, [access, action, ids]);

  const confirm = async () => {
    setBusy(true); setErr("");
    try { const r = await bulkRun(access, ids, action, finalArgs(), key, false); setResult(r); setStep("done"); }
    catch (e) { setErr(`${(e as Error).message} Podes tentar de novo: não se aplica duas vezes.`); }
    finally { setBusy(false); }
  };

  const valid = action === "owner" ? "owner_id" in args : action === "project" ? "project_id" in args
    : action === "tags" ? (args.mode === "replace" || parseTags(tagText).length > 0) : action === "reschedule" ? !!args.date : true;
  const list = (r: BulkResult) => (
    <ul className="flex max-h-[45vh] flex-col gap-1 overflow-y-auto text-sm">
      {r.results.map((it) => (
        <li key={it.id} className="rounded-md border px-2 py-1.5">
          <div className="truncate font-medium">{label(it.id)}</div>
          {it.ok ? (
            it.changed
              ? <div className="text-xs text-muted-foreground">{describe(action, it.before)} → <span className="text-foreground">{describe(action, it.after)}</span></div>
              : <div className="text-xs text-muted-foreground">Fica igual ({describe(action, it.before)})</div>
          ) : <div className="text-xs text-destructive">Não pode: {itemError(it)}</div>}
        </li>
      ))}
    </ul>
  );

  return (
    <Dialog open onOpenChange={(o) => { if (!o && !busy) onClose(step === "done", result?.summary); }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{ACTION_LABEL[action]} em {ids.length} {ids.length === 1 ? "guião" : "guiões"}</DialogTitle>
          <DialogDescription>
            {step === "input" ? "Escolhe o valor. A seguir vês o que muda em cada guião antes de confirmar."
              : step === "preview" ? "Pré-visualização: ainda nada foi gravado."
              : result?.replayed ? "Este pedido já tinha sido aplicado: mostro o resultado guardado." : "Feito. Cada alteração ficou registada no histórico."}
          </DialogDescription>
        </DialogHeader>

        {step === "input" && (
          <div className="flex flex-col gap-3">
            {listErr && <Alert variant="destructive"><AlertDescription>{listErr}</AlertDescription></Alert>}
            {action === "owner" && (
              <label className="flex flex-col gap-1 text-sm">Responsável
                <select className={selectCls} disabled={!owners} value={"owner_id" in args ? String(args.owner_id ?? "") : "-"}
                        onChange={(e) => setArgs(e.target.value === "-" ? {} : { owner_id: e.target.value || null })}>
                  <option value="-">{owners ? "Escolhe" : "A carregar…"}</option>
                  <option value="">Sem responsável</option>
                  {owners?.map((o) => <option key={o.user_id} value={o.user_id}>{o.label}</option>)}
                </select>
              </label>
            )}
            {action === "project" && (
              <label className="flex flex-col gap-1 text-sm">Campanha
                <select className={selectCls} disabled={!projects} value={"project_id" in args ? String(args.project_id ?? "") : "-"}
                        onChange={(e) => setArgs(e.target.value === "-" ? {} : { project_id: e.target.value || null })}>
                  <option value="-">{projects ? "Escolhe" : "A carregar…"}</option>
                  <option value="">Sem campanha</option>
                  {projects?.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
                {projects && projects.length === 0 && <span className="text-xs text-muted-foreground">Ainda não há campanhas ativas neste cliente.</span>}
              </label>
            )}
            {action === "tags" && (
              <>
                <label className="flex flex-col gap-1 text-sm">O que fazer
                  <select className={selectCls} value={String(args.mode)} onChange={(e) => setArgs({ ...args, mode: e.target.value })}>
                    <option value="add">Acrescentar etiquetas</option>
                    <option value="remove">Retirar etiquetas</option>
                    <option value="replace">Substituir todas as etiquetas</option>
                  </select>
                </label>
                <label className="flex flex-col gap-1 text-sm">Etiquetas (separadas por vírgula)
                  <Input value={tagText} onChange={(e) => setTagText(e.target.value)} placeholder="ex.: dinheiro, impostos" />
                </label>
                {args.mode === "replace" && <p className="text-xs text-muted-foreground">Substituir apaga as etiquetas que cada guião já tem. Vazio retira todas.</p>}
              </>
            )}
            {action === "reschedule" && (
              <label className="flex flex-col gap-1 text-sm">Nova data
                <Input type="date" min={todayDubai()} value={String(args.date ?? "")} onChange={(e) => setArgs({ date: e.target.value })} />
              </label>
            )}
          </div>
        )}

        {step === "preview" && (
          busy && !preview ? <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2Icon className="size-4 animate-spin" /> A calcular o impacto…</div>
          : preview && (
            <div className="flex flex-col gap-2">
              <p className="text-sm">
                <b>{preview.summary.changed}</b> mudam, <b>{preview.summary.ok - preview.summary.changed}</b> ficam iguais
                {preview.summary.failed ? <>, <b className="text-destructive">{preview.summary.failed}</b> não podem mudar</> : null}.
              </p>
              {action === "approve" && preview.summary.changed > 0 && (
                <Alert><AlertDescription>Cada aprovação fica presa à versão atual de cada guião. Confirma só se leste estas versões.</AlertDescription></Alert>
              )}
              {list(preview)}
            </div>
          )
        )}

        {step === "done" && result && (
          <div className="flex flex-col gap-2">
            <p className="text-sm"><b>{result.summary.changed}</b> mudaram{result.summary.failed ? <>, <b className="text-destructive">{result.summary.failed}</b> não puderam mudar</> : null}.</p>
            {list(result)}
          </div>
        )}

        {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}

        <DialogFooter>
          {step === "input" && (
            <>
              <Button variant="ghost" onClick={() => onClose(false)} disabled={busy}>Cancelar</Button>
              <Button onClick={runPreview} disabled={!valid || busy}>{busy ? <Loader2Icon className="animate-spin" /> : null} Ver impacto</Button>
            </>
          )}
          {step === "preview" && (
            <>
              <Button variant="ghost" onClick={() => (action === "approve" ? onClose(false) : setStep("input"))} disabled={busy}>{action === "approve" ? "Cancelar" : "Voltar"}</Button>
              <Button onClick={confirm} disabled={busy || !preview || preview.summary.changed === 0}>
                {busy && preview ? <Loader2Icon className="animate-spin" /> : null} Confirmar em {preview?.summary.changed ?? 0}
              </Button>
            </>
          )}
          {step === "done" && <Button onClick={() => onClose(true, result?.summary)}>Fechar</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
