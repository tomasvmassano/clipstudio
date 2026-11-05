"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, RotateCwIcon, Trash2Icon, UndoIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import type { Access } from "@/lib/access";
import { CONFIRM_WORD, confirmOk, fetchDeleted, undeleteContent, type DeletedScript } from "@/lib/content-delete";
import type { Guiao } from "@/lib/types";

/*
 * Eliminar um guião arquivado (FR-02-01, ADR-0051). Confirmação explícita: escrever "eliminar". O servidor recusa se o guião
 * tiver tarefas abertas, publicações por cancelar, já publicado ou ativos na biblioteca, e diz qual.
 */
export function DeleteScriptDialog({ g, onDelete, onClose }: {
  g: Guiao; onDelete: (reason: string) => Promise<void>; onClose: () => void;
}) {
  const [typed, setTyped] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const ok = confirmOk(typed);
  const submit = async () => {
    if (!ok || busy) return;
    setBusy(true); setErr("");
    try { await onDelete(reason); onClose(); }
    catch (e) { setErr((e as Error).message); setBusy(false); }
  };
  return (
    <Dialog open onOpenChange={(o) => { if (!o && !busy) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Eliminar o guião {g.n}{g.tema ? ` · ${g.tema}` : ""}?</DialogTitle>
          <DialogDescription>
            Sai de todas as listas, da pesquisa, do calendário e das exportações, e deixa de se poder editar. Durante 30 dias quem pode
            eliminar guiões consegue recuperá-lo em <i>Arquivados</i>; depois já não. O histórico de versões e aprovações fica guardado
            para auditoria.
          </DialogDescription>
        </DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={(e) => { e.preventDefault(); void submit(); }}>
          <label className="flex flex-col gap-1 text-sm">
            <span>Motivo (opcional)</span>
            <Textarea value={reason} maxLength={500} rows={2} onChange={(e) => setReason(e.target.value)} placeholder="ex.: duplicado do guião 4" />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span>Para confirmar, escreve <b>{CONFIRM_WORD}</b></span>
            <Input value={typed} autoComplete="off" onChange={(e) => setTyped(e.target.value)} aria-describedby={`del-hint-${g.id}`} />
            <span id={`del-hint-${g.id}`} className="text-xs text-muted-foreground">Não há anular depois de 30 dias.</span>
          </label>
          {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
          <DialogFooter>
            <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>Cancelar</Button>
            <Button type="submit" variant="destructive" disabled={!ok || busy}>
              {busy ? <Loader2Icon className="animate-spin" /> : <Trash2Icon />} Eliminar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

const when = (iso: string) => new Date(iso).toLocaleDateString("pt-PT", { day: "numeric", month: "short" });

/** Eliminados nos últimos 30 dias, para quem pode eliminar: recuperar devolve-os ao arquivo. */
export function DeletedScripts({ access, onRestored }: { access: Access; onRestored: () => Promise<void> | void }) {
  const [rows, setRows] = useState<DeletedScript[] | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState("");
  const load = useCallback(async () => {
    try { setRows(await fetchDeleted(access)); setErr(""); }
    catch (e) { setErr((e as Error).message); }
  }, [access]);
  useEffect(() => { let alive = true; fetchDeleted(access).then((r) => { if (alive) setRows(r); }).catch((e: Error) => { if (alive) setErr(e.message); }); return () => { alive = false; }; }, [access]);

  const restore = async (d: DeletedScript) => {
    setBusy(d.id); setMsg("");
    try { await undeleteContent(access, d.id); setMsg(`Guião ${d.n} voltou ao arquivo.`); await load(); await onRestored(); }
    catch (e) { setMsg((e as Error).message); }
    finally { setBusy(null); }
  };

  return (
    <section aria-label="Guiões eliminados" className="flex flex-col gap-2 rounded-lg border border-dashed p-3">
      <h2 className="text-sm font-semibold">Eliminados nos últimos 30 dias</h2>
      {err ? (
        <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ) : rows === null ? (
        <p className="text-sm text-muted-foreground">A carregar…</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhum guião eliminado nos últimos 30 dias.</p>
      ) : (
        <ul className="flex flex-col gap-1 text-sm">
          {rows.map((d) => (
            <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border px-2 py-1.5">
              <span className="min-w-0">
                <b>Guião {d.n}</b> de {d.date}{d.tema ? ` · ${d.tema}` : ""}
                <span className="block text-xs text-muted-foreground">
                  Eliminado a {when(d.deleted_at)}{d.deleted_by ? ` por ${d.deleted_by}` : ""}{d.reason ? ` · ${d.reason}` : ""} · recuperável até {when(d.recoverable_until)}
                </span>
              </span>
              <Button size="sm" variant="outline" disabled={busy !== null} onClick={() => void restore(d)}>
                {busy === d.id ? <Loader2Icon className="animate-spin" /> : <UndoIcon />} Recuperar
              </Button>
            </li>
          ))}
        </ul>
      )}
      {msg && <p className="text-sm" role="status">{msg}</p>}
    </section>
  );
}
