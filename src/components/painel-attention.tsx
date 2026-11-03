"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ArrowRightIcon, RotateCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { BizAttention } from "@/components/biz-attention";
import { useSession } from "@/components/session-provider";
import { useFlags } from "@/lib/flags";
import { currentMonth, fetchOverview, isForbidden, type BizOverview } from "@/lib/biz";

/**
 * Faixa "Precisa da tua atenção" (BIZ-02) no topo do Painel da agência. Só com a flag biz.view ligada e a capacidade
 * biz.read; os cartões financeiros só vêm do servidor a quem tem biz.finance.
 */
export function PainelAttention() {
  const { mode, canOrg } = useSession();
  const allowed = mode === "user" && canOrg("biz.read");
  const flags = useFlags(null, null, allowed);
  if (!allowed || !flags?.has("biz.view")) return null;
  return <Strip />;
}

function Strip() {
  const [data, setData] = useState<BizOverview["attention"] | null>(null);
  const [err, setErr] = useState("");
  const [hidden, setHidden] = useState(false);
  const [rev, setRev] = useState(0);
  useEffect(() => {
    let alive = true;
    fetchOverview(`${currentMonth()}-01`, "EUR")
      .then((d) => { if (alive) { setData(d.attention); setErr(""); } })
      .catch((e: Error) => { if (!alive) return; if (isForbidden(e)) setHidden(true); else setErr(e.message); });
    return () => { alive = false; };
  }, [rev]);
  if (hidden) return null;
  if (err) {
    return (
      <p role="alert" className="flex flex-wrap items-center gap-2 text-red-500 text-xs">
        Não consegui carregar os alertas: {err}
        <Button size="sm" variant="outline" onClick={() => { setErr(""); setRev((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button>
      </p>
    );
  }
  if (!data) return <Skeleton className="h-28" />;
  return (
    <div className="flex flex-col gap-1">
      <BizAttention attention={data} compact />
      <Link href="/negocio" className="inline-flex items-center gap-1 self-start text-muted-foreground text-xs underline-offset-4 hover:underline">
        Abrir a vista de negócio <ArrowRightIcon className="size-3" />
      </Link>
    </div>
  );
}
