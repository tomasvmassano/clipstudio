"use client";

import { useEffect, useState } from "react";
import { Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { ScriptActions } from "@/components/use-guioes";
import type { ReworkReason } from "@/lib/learn";
import type { Guiao } from "@/lib/types";

const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";

/**
 * Rejeitar ou pedir alterações (PRD §4). Com a flag learn.rework e motivos configurados, pede também a categoria
 * (FR-17-10); o texto livre continua obrigatório. Sem flag ou sem motivos fica exatamente como antes.
 */
export function ReasonForm({ g, mode, actions, busy, run, onCancel }: {
  g: Guiao; mode: "changes_requested" | "rejected"; actions: ScriptActions; busy: boolean;
  run: (fn: () => Promise<unknown>) => Promise<void>; onCancel: () => void;
}) {
  const [reason, setReason] = useState("");
  const [code, setCode] = useState("");
  const [reasons, setReasons] = useState<ReworkReason[] | null>(null);
  const [loadErr, setLoadErr] = useState(false);
  useEffect(() => {
    let alive = true;
    actions.reworkReasons()
      .then((l) => { if (alive) setReasons(l.enabled ? l.reasons.filter((r) => r.active && r.applies_to.includes("guiao")) : []); })
      .catch(() => { if (alive) { setLoadErr(true); setReasons([]); } });
    return () => { alive = false; };
  }, [actions]);

  const withCategory = !!reasons?.length;
  const rejected = mode === "rejected";
  const ready = reasons !== null && !!reason.trim() && (!withCategory || !!code);

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        if (!ready) return;
        void run(() => withCategory
          ? actions.transitionReasoned(g.id, mode, reason, code, g.lock_version)
          : actions.transition(g.id, mode, reason, g.lock_version));
      }}
    >
      <div className="flex flex-wrap gap-2">
        {withCategory && (
          <select
            id={`${g.id}-reason-code`} className={selectCls} value={code} onChange={(e) => setCode(e.target.value)} required
            aria-label={rejected ? "Categoria da rejeição" : "Categoria do pedido de alterações"}
          >
            <option value="">Categoria…</option>
            {reasons!.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}
          </select>
        )}
        <Input
          id={`${g.id}-reason`} className="min-w-[14rem] flex-1" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus required
          aria-label={rejected ? "Motivo da rejeição" : "O que tem de mudar"}
          placeholder={rejected ? "Porque não dirias isto?" : "O que tem de mudar?"}
        />
        <Button size="sm" type="submit" variant={rejected ? "destructive" : "default"} disabled={busy || !ready}>
          {(busy || reasons === null) && <Loader2Icon className="animate-spin" />} {rejected ? "Rejeitar" : "Pedir alterações"}
        </Button>
        <Button size="sm" type="button" variant="ghost" onClick={onCancel}>Cancelar</Button>
      </div>
      {loadErr && <p className="text-xs text-muted-foreground" role="status">Não consegui carregar as categorias de motivo; segue só com o texto.</p>}
    </form>
  );
}
