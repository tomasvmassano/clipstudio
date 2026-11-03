"use client";

import type { ReactNode } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { Block, Off } from "@/lib/portal";

/** Moldura de um bloco do portal: título, e o bloco ou o motivo de estar indisponível (nunca um vazio mudo). */
export function BlockCard<T>({ id, title, description, block, reload, children }: {
  id: string; title: string; description?: string; block: Block<T>; reload: () => void; children: (b: { available: true } & T) => ReactNode;
}) {
  return (
    <Card id={id} data-portal-block={id} className="min-w-0">
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
        {description && <CardDescription>{description}</CardDescription>}
      </CardHeader>
      <CardContent className="flex min-w-0 flex-col gap-3">
        {block.available ? children(block as { available: true } & T) : <Unavailable off={block as Off} reload={reload} />}
      </CardContent>
    </Card>
  );
}

export function Unavailable({ off, reload }: { off: Off; reload: () => void }) {
  if (off.code === "erro") {
    return (
      <Alert variant="destructive" role="alert">
        <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
          <span>{off.reason}</span>
          <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
        </AlertDescription>
      </Alert>
    );
  }
  return (
    <p className="text-sm text-muted-foreground" data-unavailable={off.code}>
      Indisponível: {off.reason}
    </p>
  );
}

/** Resultado de uma ação (só depois da resposta do servidor; nunca otimista). */
export function Notice({ msg }: { msg: { kind: "ok" | "err"; text: string } | null }) {
  if (!msg) return null;
  return (
    <p role={msg.kind === "err" ? "alert" : "status"} className={msg.kind === "err" ? "text-sm text-destructive" : "text-sm text-muted-foreground"}>
      {msg.text}
    </p>
  );
}

export function Meter({ label, value, text }: { label: string; value: number | null; text: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <div className="flex items-baseline justify-between gap-2 text-sm">
        <span className="text-muted-foreground">{label}</span>
        <span className="font-semibold tabular-nums">{text}</span>
      </div>
      {value !== null && (
        <div className="h-2 rounded-full bg-muted" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={value}>
          <div className="h-2 rounded-full bg-primary" style={{ width: `${Math.max(2, value)}%` }} />
        </div>
      )}
    </div>
  );
}

export const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";
