"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Download, Loader2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { Access } from "@/lib/access";
import { cancelExport, EXPORT_STATUS, listExports, requestExport, type ExportJob } from "@/lib/edit-media";

/**
 * Exportar (EDL-11): pede ao worker o render da versão gravada; o estado vem do job persistido (fila, a exportar com
 * progresso, pronto com a versão nova do vídeo na revisão, falhou com o motivo e a opção de tentar outra vez).
 */
export function ExportPanel({ access, ws, asset, versionId, versionNo, dirty, canExport }: {
  access: Access; ws: string; asset: string; versionId: string | null; versionNo: number | null; dirty: boolean; canExport: boolean;
}) {
  const [jobs, setJobs] = useState<ExportJob[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    try { setJobs(await listExports(access, asset)); setErr(null); } catch (e) { setErr((e as Error).message); }
  }, [access, asset]);

  useEffect(() => {
    const first = setTimeout(load, 0);
    return () => clearTimeout(first);
  }, [load]);
  const active = jobs?.some((j) => j.status === "queued" || j.status === "running");
  useEffect(() => {
    if (!active) return;
    const id = setInterval(load, 5000);
    return () => clearInterval(id);
  }, [active, load]);

  const go = async () => {
    setBusy(true); setErr(null);
    try { await requestExport(access, asset, versionId); await load(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const latest = jobs?.[0];
  const reason = !canExport ? "Sem permissão para exportar." : dirty ? "Grava a versão antes de exportar." : !versionId ? "Ainda não há versão gravada." : null;

  return (
    <div className="flex flex-col gap-2 text-sm" aria-live="polite">
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" onClick={go} disabled={!!reason || busy || !!active} title={reason ?? undefined}>
          {busy ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
          Exportar{versionNo ? ` v${versionNo}` : ""}
        </Button>
        {reason && <span className="text-xs text-muted-foreground">{reason}</span>}
      </div>
      {err && <p className="text-xs text-destructive" role="alert">{err} <button className="underline" onClick={load}>Tentar de novo</button></p>}
      {jobs === null && !err && <p className="text-xs text-muted-foreground">A carregar exportações…</p>}
      {latest && (
        <div className="rounded-md border p-2 text-xs">
          <div className="flex items-center justify-between gap-2">
            <span>
              Edição v{latest.edit_version_no ?? "?"} · <strong>{EXPORT_STATUS[latest.status]}</strong>
              {latest.status === "running" && latest.progress?.pct != null ? ` · ${Math.round(latest.progress.pct)}%` : ""}
              {latest.status === "running" && latest.progress?.step ? ` · ${latest.progress.step}` : ""}
            </span>
            {(latest.status === "queued" || latest.status === "running") && (
              <button className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground"
                onClick={async () => { try { await cancelExport(access, latest.id); await load(); } catch (e) { setErr((e as Error).message); } }}>
                <X className="size-3" /> Cancelar
              </button>
            )}
          </div>
          {latest.status === "queued" && !latest.worker_seen && (
            <p className="mt-1 text-muted-foreground">O worker não está ligado agora: o pedido fica na fila e começa quando ele voltar.</p>
          )}
          {latest.last_error && latest.status !== "done" && <p className="mt-1 text-destructive">{latest.last_error}</p>}
          {latest.status === "done" && latest.result?.version_no && (
            <p className="mt-1">Versão v{latest.result.version_no} do vídeo pronta. <Link className="underline" href={`/c/${ws}/revisao?ver=videos&asset=${asset}`}>Abrir na revisão</Link></p>
          )}
        </div>
      )}
    </div>
  );
}
