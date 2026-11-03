"use client";

import Link from "next/link";
import { useState } from "react";
import { AlertTriangleIcon, ArrowRightIcon, CircleAlertIcon, InfoIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { SEVERITY_LABEL, type BizOverview, type Severity } from "@/lib/biz";

const TONE: Record<Severity, string> = {
  critico: "border-l-red-500",
  alto: "border-l-amber-500",
  aviso: "border-l-sky-500",
};
const ICON: Record<Severity, typeof AlertTriangleIcon> = { critico: CircleAlertIcon, alto: AlertTriangleIcon, aviso: InfoIcon };

/** Faixa "Precisa da tua atenção" (BIZ-02): no máximo 5 cartões por gravidade, cada um com ação direta. */
export function BizAttention({ attention, compact = false }: { attention: BizOverview["attention"]; compact?: boolean }) {
  const [showRules, setShowRules] = useState(false);
  const { cards, more, unavailable } = attention;
  return (
    <section aria-labelledby="biz-attention" className="flex flex-col gap-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="biz-attention" className="font-medium text-base">Precisa da tua atenção</h2>
        {!compact && unavailable.length > 0 && (
          <Button variant="link" size="sm" className="h-auto p-0 text-xs" aria-expanded={showRules} onClick={() => setShowRules(!showRules)}>
            {showRules ? "Esconder" : "Ver"} alertas ainda sem dados ({unavailable.length})
          </Button>
        )}
      </div>
      {cards.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-muted-foreground text-sm">Nada urgente neste momento nos clientes a que tens acesso.</p>
      ) : (
        <ul className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3" aria-label="Alertas por gravidade">
          {cards.map((c) => {
            const Icon = ICON[c.severity];
            return (
              <li key={`${c.key}:${c.client_id}`} data-card={c.key} data-severity={c.severity}>
                <Card className={`h-full border-l-4 shadow-none dark:ring-0 ${TONE[c.severity]}`}>
                  <CardContent className="flex h-full flex-col gap-2 py-3">
                    <div className="flex items-center gap-2 text-muted-foreground text-xs">
                      <Icon className="size-3.5" aria-hidden />
                      <span className="font-medium text-foreground">{SEVERITY_LABEL[c.severity]}</span>
                      <span aria-hidden>·</span>
                      <span>{c.client_name}</span>
                      {c.level === "financeiro" && <><span aria-hidden>·</span><span>Financeiro</span></>}
                    </div>
                    <p className="font-medium text-sm">{c.title}</p>
                    <p className="text-muted-foreground text-xs">{c.detail}</p>
                    <div className="mt-auto pt-1">
                      <Button size="sm" variant="outline" nativeButton={false} render={<Link href={c.action_href} />}>
                        {c.action_label} <ArrowRightIcon />
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ul>
      )}
      {more > 0 && <p className="text-muted-foreground text-xs">Mais {more} {more === 1 ? "alerta" : "alertas"} de menor gravidade na tabela por cliente.</p>}
      {showRules && (
        <ul className="flex flex-col gap-1 rounded-lg border p-3 text-xs" aria-label="Alertas ainda sem dados">
          {unavailable.map((u) => <li key={u.key}><span className="font-medium">{u.label}:</span> <span className="text-muted-foreground">{u.reason}</span></li>)}
        </ul>
      )}
    </section>
  );
}
