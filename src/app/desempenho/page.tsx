"use client";

import { useEffect, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { Formatos, KpiCard, Producao, Recentes, Referencias, TopReels, ViewsPorSemana } from "@/components/desempenho-cards";
import { fetchDesempenho, fmtCompact, fmtDay, fmtInt, type Desempenho } from "@/lib/desempenho";

export default function DesempenhoPage() {
  const [d, setD] = useState<Desempenho | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    fetchDesempenho().then(setD).catch((e: Error) => setError(e.message));
  }, []);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Desempenho</h1>
        <p className="text-sm text-muted-foreground">
          @itsnumeiro no Instagram, a partir dos reels guardados pelo scraper. Dados de hoje chegam quando a recolha diária correr.
        </p>
      </div>

      {error && (
        <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>
      )}

      {!d ? (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4, 5, 6].map((i) => <Skeleton key={i} className="h-32 w-full" />)}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
          <ViewsPorSemana d={d} />
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-1">
            <KpiCard label="Últimos 30 dias" value={fmtCompact(d.kpi.views_30d)} hint={`${fmtInt(d.kpi.reels_30d)} reels · último a ${fmtDay(d.kpi.ultimo)}`} />
            <KpiCard label="Mediana por reel" value={fmtCompact(d.kpi.mediana)} hint={`média ${fmtCompact(d.kpi.media)} · ${fmtInt(d.kpi.outliers)} virais (≥2×)`} />
            <KpiCard label="Comentários" value={fmtCompact(d.kpi.comentarios)} hint={`${fmtCompact(d.kpi.likes)} likes no total`} />
          </div>
          <TopReels d={d} />
          <Referencias d={d} />
          <Formatos d={d} />
          <Recentes d={d} />
          <Producao d={d} />
        </div>
      )}
    </div>
  );
}
