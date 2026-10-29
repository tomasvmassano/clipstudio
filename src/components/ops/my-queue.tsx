"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { InboxIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { WsLink } from "@/components/ws-link";
import { QueueRow, useQueue } from "@/components/ops/queue-parts";
import { CATEGORY_PLURAL, type QueueCategory, type QueueItem } from "@/lib/ops";
import { clientPath } from "@/lib/ws-path";
import { cn } from "@/lib/utils";

const CHIPS: QueueCategory[] = ["task", "approval", "recording", "decision", "alert"];
const MAX = 6;

/**
 * A minha fila no Início do cliente (FR-01-03): tarefas, aprovações, gravações de hoje, decisões, prazos e alertas
 * deste cliente. Cada linha abre o objeto. Só aparece com a flag ops.workspace e com conta pessoal.
 */
export function MyQueue({ ws, tz }: { ws: string; tz: string }) {
  const router = useRouter();
  const { data, err, reload } = useQueue(ws);
  const [only, setOnly] = useState<QueueCategory | null>(null);
  const [actionErr, setActionErr] = useState("");
  const open = (i: QueueItem) => router.push(clientPath(i.workspace_id, i.href));
  const items = (data?.items ?? []).filter((i) => !only || i.categories.includes(only));

  return (
    <Card aria-labelledby="my-queue-title">
      <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2">
        <CardTitle id="my-queue-title" className="flex items-center gap-2 text-base"><InboxIcon className="size-4" aria-hidden /> A minha fila</CardTitle>
        <div className="flex items-center gap-1">
          <Button size="sm" variant="ghost" onClick={reload} aria-label="Atualizar a minha fila"><RotateCwIcon /></Button>
          <Button size="sm" variant="outline" render={<WsLink href="/caixa" />} nativeButton={false}>Abrir a caixa</Button>
        </div>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {err ? (
          <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>Não consegui carregar a tua fila: {err}</span>
            <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
          </AlertDescription></Alert>
        ) : !data ? (
          <div className="flex flex-col gap-2" aria-busy="true" aria-label="A carregar a minha fila"><Skeleton className="h-8" /><Skeleton className="h-14" /><Skeleton className="h-14" /></div>
        ) : (
          <>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filtrar a minha fila">
              {CHIPS.map((c) => (
                <button key={c} type="button" aria-pressed={only === c} onClick={() => setOnly(only === c ? null : c)}
                  className={cn("inline-flex items-baseline gap-1.5 rounded-full border px-3 py-1 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    only === c ? "border-primary bg-primary/10" : "bg-background", c === "alert" && data.counts.alert > 0 && "border-destructive/60")}>
                  <b className="tabular-nums">{data.counts[c]}</b><span className="text-muted-foreground">{CATEGORY_PLURAL[c]}</span>
                </button>
              ))}
            </div>
            {actionErr && <p role="alert" className="text-sm text-destructive">{actionErr}</p>}
            {items.length === 0 ? (
              <p className="text-sm text-muted-foreground">{only ? "Nada deste tipo agora." : "Não tens nada pendente neste cliente."}</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {items.slice(0, MAX).map((i) => (
                  <QueueRow key={i.key} item={i} tz={tz} showWorkspace={false} compact onOpen={open} onChanged={reload} onError={setActionErr} />
                ))}
              </ul>
            )}
            {items.length > MAX && <p className="text-xs text-muted-foreground">E mais {items.length - MAX}. Abre a caixa para ver tudo.</p>}
          </>
        )}
      </CardContent>
    </Card>
  );
}
