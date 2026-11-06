"use client";

import { useEffect, useState } from "react";
import { CheckIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import type { ScriptActions } from "@/components/use-guioes";
import { GROUP_LABEL, pctRatio, type EditCode, type EditGroup, type EditOptions, type EditRatio } from "@/lib/lessons";
import type { Guiao } from "@/lib/types";

/*
 * LRN-01 (ADR-0069): motivo de um toque em cada edição a um guião do motor. Com a flag learn.edits desligada nada disto
 * aparece e o cartão fica como antes. O servidor volta a verificar tudo (capacidade, flag, códigos e a regra dos 30%).
 */

/** Opções do cliente aberto; null enquanto carrega. Sem resposta = desligado (o cartão fica como antes). */
export function useEditOptions(actions: ScriptActions): EditOptions | null {
  const [o, setO] = useState<EditOptions | null>(null);
  useEffect(() => {
    let alive = true;
    actions.editOptions()
      .then((x) => { if (alive) setO(x); })
      .catch(() => { if (alive) setO({ enabled: false, threshold: 0.3, codes: [] }); });
    return () => { alive = false; };
  }, [actions]);
  return o;
}

const GROUPS: EditGroup[] = ["hook", "corpo", "cta", "facto", "tom", "outro"];

/** Chips agrupados por parte do guião; cada um é um botão com estado (aria-pressed). */
export function ReasonChips({ codes, value, onChange, label }: { codes: EditCode[]; value: string[]; onChange: (v: string[]) => void; label: string }) {
  const toggle = (c: string) => onChange(value.includes(c) ? value.filter((x) => x !== c) : [...value, c].slice(0, 8));
  return (
    <div role="group" aria-label={label} className="flex flex-col gap-1.5">
      {GROUPS.map((gr) => {
        const list = codes.filter((c) => c.group === gr);
        if (!list.length) return null;
        return (
          <div key={gr} className="flex flex-wrap items-center gap-1.5">
            <span className="w-16 shrink-0 text-[11px] uppercase tracking-wide text-muted-foreground">{GROUP_LABEL[gr]}</span>
            {list.map((c) => {
              const on = value.includes(c.code);
              return (
                <button
                  key={c.code} type="button" aria-pressed={on} onClick={() => toggle(c.code)}
                  className={cn("inline-flex min-h-8 items-center gap-1 rounded-full border px-2.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    on ? "border-primary bg-primary text-primary-foreground" : "hover:bg-muted")}
                >
                  {on && <CheckIcon className="size-3" aria-hidden />}{c.label}
                </button>
              );
            })}
          </div>
        );
      })}
    </div>
  );
}

/** Depois de "Concluir" uma edição: "Porque mudaste?" (opcional). Sem edição em relação ao motor fecha sozinho. */
export function EditReasonPrompt({ g, actions, codes, onDone, onError }: {
  g: Guiao; actions: ScriptActions; codes: EditCode[]; onDone: () => void; onError: (m: string) => void;
}) {
  const [ratio, setRatio] = useState<EditRatio | null>(null);
  const [sel, setSel] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    actions.editRatio(g.id)
      .then((r) => { if (!alive) return; if (!r.engine || !r.ratio) onDone(); else setRatio(r); })
      .catch(() => { if (alive) onDone(); });   // sem leitura: não pergunta (o motivo é opcional ao concluir)
    return () => { alive = false; };
  }, [actions, g.id, onDone]);

  if (!ratio) return <p className="text-xs text-muted-foreground" role="status"><Loader2Icon className="mr-1 inline size-3 animate-spin" />A comparar com a versão do motor…</p>;
  const can = sel.length > 0 || note.trim().length > 0;
  return (
    <form
      className="flex flex-col gap-2 rounded-md border bg-muted/30 p-3" data-testid="edit-reason"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!can) return;
        setBusy(true);
        try { await actions.editReason(g.id, sel, note.trim()); onDone(); }
        catch (err) { onError((err as Error).message); }
        finally { setBusy(false); }
      }}
    >
      <p className="text-sm font-medium">Porque mudaste o texto do motor? <span className="font-normal text-muted-foreground">(opcional, mudaste {pctRatio(ratio.ratio)})</span></p>
      <ReasonChips codes={codes} value={sel} onChange={setSel} label="Motivos da edição" />
      <Input value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} aria-label="Motivo em texto livre (opcional)" placeholder="Outro motivo (opcional)" />
      <div className="flex flex-wrap gap-2">
        <Button size="sm" type="submit" disabled={busy || !can}>{busy && <Loader2Icon className="animate-spin" />} Guardar motivo</Button>
        <Button size="sm" type="button" variant="ghost" onClick={onDone} disabled={busy}>Agora não</Button>
      </div>
      {ratio.required && <p className="text-xs text-muted-foreground">Mudaste mais de {pctRatio(ratio.threshold ?? 0.3)} do texto: ao aprovar, o motivo vai ser pedido.</p>}
    </form>
  );
}

/** Aprovar um guião do motor que foi editado: chips (pré-preenchidos com os motivos das edições) e regra dos 30%. */
export function ApproveLearnForm({ g, actions, codes, ratio, busy, run, onCancel }: {
  g: Guiao; actions: ScriptActions; codes: EditCode[]; ratio: EditRatio; busy: boolean;
  run: (fn: () => Promise<unknown>) => Promise<void>; onCancel: () => void;
}) {
  const known = new Set(codes.map((c) => c.code));
  const [sel, setSel] = useState<string[]>(() => [...new Set((ratio.edits ?? []).flatMap((e) => e.codes))].filter((c) => known.has(c)).slice(0, 8));
  const [note, setNote] = useState("");
  const has = sel.length > 0 || note.trim().length > 0;
  const blocked = ratio.required && !has;
  const go = () => run(() => actions.decideLearned(g.id, "approved", { codes: sel, note: note.trim(), lock: g.lock_version }));
  return (
    <form className="flex flex-col gap-2 rounded-md border bg-muted/30 p-3" data-testid="approve-learn" onSubmit={(e) => { e.preventDefault(); if (!blocked) void go(); }}>
      <p className="text-sm font-medium">
        Mudaste {pctRatio(ratio.ratio)} do texto do motor.{" "}
        <span className="font-normal text-muted-foreground">
          {ratio.required ? "Acima de 30% o motivo é obrigatório: um toque chega." : "Diz porquê se quiseres; ajuda o motor a aprender."}
        </span>
      </p>
      <ReasonChips codes={codes} value={sel} onChange={setSel} label="Motivos da edição" />
      <Input value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} aria-label="Motivo em texto livre" placeholder={ratio.required ? "Ou escreve porquê" : "Outro motivo (opcional)"} />
      <div className="flex flex-wrap gap-2">
        <Button size="sm" type="submit" disabled={busy || blocked}>{busy ? <Loader2Icon className="animate-spin" /> : <CheckIcon />} {has || ratio.required ? "Aprovar" : "Aprovar sem motivo"}</Button>
        <Button size="sm" type="button" variant="ghost" onClick={onCancel} disabled={busy}>Cancelar</Button>
      </div>
    </form>
  );
}
