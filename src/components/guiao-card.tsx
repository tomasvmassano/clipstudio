"use client";

import { useState } from "react";
import { CheckIcon, PencilIcon, XIcon, UndoIcon, VideoIcon, ChevronDownIcon, ChevronUpIcon, ExternalLinkIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { words } from "@/lib/data";
import { FORMATO_LABEL, WPS, type Guiao, type GuiaoPatch, type Hook } from "@/lib/types";
import type { ScriptCaps } from "@/components/use-guioes";

const MECH = ["pergunta", "contra", "numero", "ego", "confissao", "segredo"];

type Props = {
  g: Guiao;
  carried?: boolean;
  caps: ScriptCaps;
  onPatch: (id: string, p: GuiaoPatch) => Promise<unknown>;
  onError: (msg: string) => void;
};

export function GuiaoCard({ g, carried, caps, onPatch, onError }: Props) {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"view" | "edit" | "reject">("view");
  const [busy, setBusy] = useState(false);
  const [draft, setDraft] = useState<{ hooks: Hook[]; corpo: string; formato: string; tema: string }>({
    hooks: g.hooks, corpo: g.corpo, formato: g.formato ?? "", tema: g.tema ?? "",
  });
  const [reason, setReason] = useState("");

  const rej = g.status === "rejeitado";
  const dur = Math.round((words(g.corpo) + words(g.hooks[0]?.text)) / WPS);

  const run = async (p: GuiaoPatch) => {
    setBusy(true);
    try {
      await onPatch(g.id, p);
      setMode("view");
    } catch (e) {
      onError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const meta = (
    <div className="flex flex-wrap items-center gap-1.5 text-xs">
      {g.formato && <Badge variant="outline">{FORMATO_LABEL[g.formato] ?? g.formato}</Badge>}
      {g.tema && <Badge variant="secondary" className="max-w-[18rem] truncate">{g.tema}</Badge>}
      {carried && <Badge variant="outline" className="border-amber-500/50 text-amber-600 dark:text-amber-400">por gravar de {g.date}</Badge>}
      {rej ? (
        <Badge variant="destructive">rejeitado</Badge>
      ) : g.gravado ? (
        <Badge className="bg-emerald-600 text-white">gravado</Badge>
      ) : g.validado ? (
        <Badge className="bg-primary text-primary-foreground">validado</Badge>
      ) : null}
      <span className="text-muted-foreground tabular-nums">~{dur}s</span>
      {g.critic_score != null && <span className="ml-auto font-medium tabular-nums text-muted-foreground">{Number(g.critic_score).toFixed(1)}</span>}
    </div>
  );

  return (
    <Card className={cn("overflow-hidden", rej && "opacity-60", g.gravado && "border-emerald-600/40")}>
      <CardContent className="grid grid-cols-[3rem_minmax(0,1fr)] gap-4 p-0">
        <div className={cn("flex items-start justify-center border-r bg-muted/40 pt-4 font-mono text-2xl font-semibold tabular-nums text-muted-foreground", g.gravado && "text-emerald-600")}>
          {g.n}
        </div>
        <div className="flex min-w-0 flex-col gap-3 py-4 pr-4">
          {meta}

          {mode === "edit" ? (
            <div className="flex flex-col gap-2">
              {[0, 1, 2].map((i) => (
                <div key={i} className="grid grid-cols-[minmax(0,1fr)_9rem] gap-2">
                  <Input
                    id={`${g.id}-h${i}`}
                    value={draft.hooks[i]?.text ?? ""}
                    placeholder={`Hook ${i + 1}`}
                    onChange={(e) => {
                      const hooks = [...draft.hooks];
                      hooks[i] = { text: e.target.value, mecanismo: hooks[i]?.mecanismo ?? "" };
                      setDraft({ ...draft, hooks });
                    }}
                  />
                  <select
                    id={`${g.id}-m${i}`}
                    className="h-9 rounded-md border bg-background px-2 text-sm"
                    value={draft.hooks[i]?.mecanismo ?? ""}
                    onChange={(e) => {
                      const hooks = [...draft.hooks];
                      hooks[i] = { text: hooks[i]?.text ?? "", mecanismo: e.target.value };
                      setDraft({ ...draft, hooks });
                    }}
                  >
                    <option value="">mecanismo</option>
                    {MECH.map((m) => (
                      <option key={m} value={m}>{m}</option>
                    ))}
                  </select>
                </div>
              ))}
              <Textarea id={`${g.id}-corpo`} rows={10} value={draft.corpo} onChange={(e) => setDraft({ ...draft, corpo: e.target.value })} />
              <p className="text-xs text-muted-foreground">Uma frase por linha. Só o que ele diz. O original fica no histórico.</p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  disabled={busy}
                  onClick={() =>
                    run({
                      hooks: draft.hooks.filter((h) => h.text.trim()).map((h) => ({ text: h.text.trim(), mecanismo: h.mecanismo })),
                      corpo: draft.corpo.split("\n").map((l) => l.trim()).filter(Boolean).join("\n"),
                    })
                  }
                >
                  Guardar
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setMode("view")}>Cancelar</Button>
              </div>
            </div>
          ) : (
            <>
              <ol className="flex flex-col gap-1.5">
                {g.hooks.map((h, i) => (
                  <li key={i} className="grid grid-cols-[1.25rem_minmax(0,1fr)_auto] items-baseline gap-2 text-[15px] font-semibold leading-snug">
                    <span className="font-mono text-xs text-primary">{i + 1}</span>
                    <span>{h.text}</span>
                    <span className="text-[10px] font-normal uppercase tracking-wide text-muted-foreground">{h.mecanismo}</span>
                  </li>
                ))}
              </ol>
              <div className={cn("whitespace-pre-line border-l-2 pl-3 text-sm leading-relaxed", !open && "line-clamp-3")}>{g.corpo}</div>
              {rej && g.motivo_rejeicao && <p className="text-sm text-destructive">Motivo: {g.motivo_rejeicao}</p>}
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

          {mode === "reject" && (
            <div className="flex flex-wrap gap-2">
              <Input id={`${g.id}-reason`} className="min-w-[14rem] flex-1" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Porque não dirias isto?" autoFocus />
              <Button size="sm" variant="destructive" disabled={busy} onClick={() => run({ status: "rejeitado", motivo_rejeicao: reason.trim() || "sem motivo" })}>
                Rejeitar
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setMode("view")}>Cancelar</Button>
            </div>
          )}

          {mode === "view" && (
            <div className="flex flex-wrap items-center gap-1.5">
              <Button size="sm" variant="ghost" onClick={() => setOpen(!open)}>
                {open ? <ChevronUpIcon /> : <ChevronDownIcon />} {open ? "Recolher" : "Ver tudo"}
              </Button>
              {!rej && caps.approve && (
                <Button size="sm" variant={g.validado ? "secondary" : "default"} disabled={busy} onClick={() => run({ validado: !g.validado })}>
                  <CheckIcon /> {g.validado ? "Retirar validação" : "Validar"}
                </Button>
              )}
              {!rej && caps.edit && (
                <Button size="sm" variant="outline" onClick={() => { setDraft({ hooks: g.hooks, corpo: g.corpo, formato: g.formato ?? "", tema: g.tema ?? "" }); setMode("edit"); }}>
                  <PencilIcon /> Editar
                </Button>
              )}
              {!rej && caps.reject && (
                <Button size="sm" variant="outline" onClick={() => setMode("reject")}>
                  <XIcon /> Rejeitar
                </Button>
              )}
              {!rej && caps.record && (
                <Button size="sm" variant="ghost" disabled={busy} onClick={() => run({ gravado: !g.gravado })}>
                  <VideoIcon /> {g.gravado ? "Desmarcar gravado" : "Marcar gravado"}
                </Button>
              )}
              {rej && caps.reject && (
                <Button size="sm" variant="outline" disabled={busy} onClick={() => run({ status: "aprovado", motivo_rejeicao: "" })}>
                  <UndoIcon /> Repor
                </Button>
              )}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
