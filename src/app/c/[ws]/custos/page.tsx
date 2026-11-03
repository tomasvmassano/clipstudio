"use client";

import { useState } from "react";
import { DownloadIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { Bar, LearnState, Stat, selectCls, useLoad } from "@/components/learn/learn-shared";
import type { Access } from "@/lib/access";
import { download, eur, exportCosts, fetchCosts, monthLabel, toCsv, type CostReport } from "@/lib/learn";
import { EDITORIAL_LABEL, type EditorialStatus } from "@/lib/types";

/*
 * Custo por guião, vídeo e publicação (FR-10-05, ADR-0037): custo dos agentes repartido pelos guiões que cada execução
 * gerou e pelas publicações de cada guião, tendência mensal e CSV. Só com costs.read (o servidor omite tudo o resto).
 */

export default function CustosPage() {
  return (
    <WorkspaceGate need="costs.read">
      {(access) => <FlagGate flag="costs.content" ws={access.ws}><CostsView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

const METHOD: Record<string, string> = { partes_iguais: "partes iguais", por_posicao: "por posição", desconhecido: "custo desconhecido" };

function CostsView({ access }: { access: Access }) {
  const [months, setMonths] = useState(6);
  const rep = useLoad(() => fetchCosts(access, months), `${access.ws}:${months}`);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const d = rep.data;
  const csv = async () => {
    setBusy(true); setErr("");
    try {
      const r: CostReport = await exportCosts(access, months);
      download(`custos-${access.ws}-${months}m.csv`, toCsv(
        ["guiao", "n", "data", "tema", "estado", "custo_eur", "repartição", "execuções", "publicações", "custo_por_publicacao_eur"],
        r.scripts.map((s) => [s.content_id, s.n, s.date, s.tema, s.editorial_status, s.cost_eur, METHOD[s.method] ?? s.method, s.jobs, s.publications, s.cost_per_publication])), "text/csv;charset=utf-8");
    } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const cur = d?.by_month[0];
  const maxMonth = Math.max(0.01, ...(d?.by_month ?? []).map((m) => m.ai_total));
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Custos por guião e publicação</h1>
          <p className="text-sm text-muted-foreground">Custo dos agentes em EUR. Execuções sem custo conhecido ficam à parte e nunca contam como zero.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2 text-sm">Período
            <select className={selectCls} value={months} onChange={(e) => setMonths(Number(e.target.value))}>
              <option value={3}>3 meses</option><option value={6}>6 meses</option><option value={12}>12 meses</option>
            </select>
          </label>
          <Button size="sm" variant="outline" onClick={rep.reload}><RotateCwIcon /> Atualizar</Button>
          <Button size="sm" onClick={() => void csv()} disabled={busy || !d}>{busy ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Exportar CSV</Button>
        </div>
      </div>
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      <LearnState loading={rep.loading} error={rep.error} reload={rep.reload} label="os custos" forbidden="Não tens acesso aos custos deste cliente.">
        {d && cur && (
          <>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Stat label={`Agentes em ${monthLabel(cur.month)}`} value={eur(cur.ai_total)} hint={cur.jobs_unknown ? `${cur.jobs_unknown} execuções sem custo conhecido` : undefined} />
              <Stat label="Por guião" value={cur.cost_per_script === null ? "sem guiões" : eur(cur.cost_per_script, 3)} hint={`${cur.scripts} guiões com custo`} />
              <Stat label="Por publicação" value={cur.cost_per_publication === null ? "sem publicações" : eur(cur.cost_per_publication, 3)} hint={`${cur.publications} publicações`} />
              <Stat label="Por vídeo" value="indisponível" hint={d.video.reason} />
            </div>
            <p className="text-xs text-muted-foreground">{d.allocation}</p>
            <div className="grid gap-4 lg:grid-cols-2">
              <WidgetBoundary label="Tendência mensal">
                <Card>
                  <CardHeader><CardTitle>Tendência mensal</CardTitle><CardDescription>Execuções terminadas no mês, fuso do cliente.</CardDescription></CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Mês</TableHead><TableHead className="min-w-[8rem]">Agentes</TableHead><TableHead className="text-right">Por guião</TableHead>
                        <TableHead className="text-right">Por publicação</TableHead><TableHead className="text-right">Sem guião</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {d.by_month.map((m) => (
                          <TableRow key={m.month}>
                            <TableCell>{monthLabel(m.month)}</TableCell>
                            <TableCell>
                              <span className="tabular-nums">{eur(m.ai_total)}</span>
                              <Bar value={Math.round(m.ai_total * 100) / 100} max={maxMonth} label={`${monthLabel(m.month)}: ${eur(m.ai_total)}`} text="" />
                              {m.jobs_unknown > 0 && <span className="block text-xs text-muted-foreground">{m.jobs_unknown} sem custo</span>}
                            </TableCell>
                            <TableCell className="text-right tabular-nums">{m.cost_per_script === null ? "-" : eur(m.cost_per_script, 3)}</TableCell>
                            <TableCell className="text-right tabular-nums">{m.cost_per_publication === null ? "-" : eur(m.cost_per_publication, 3)}</TableCell>
                            <TableCell className="text-right tabular-nums" title="Execuções sem guiões (ex.: pesquisa, análise)">{eur(m.unattributed)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              </WidgetBoundary>
              <WidgetBoundary label="Por guião">
                <Card>
                  <CardHeader><CardTitle>Por guião</CardTitle><CardDescription>Guiões gerados pelo motor no período.</CardDescription></CardHeader>
                  <CardContent className="max-h-[32rem] overflow-auto">
                    {d.scripts.length === 0 ? <p className="text-sm text-muted-foreground">Sem guiões gerados pelo motor neste período.</p> : (
                      <Table>
                        <TableHeader><TableRow>
                          <TableHead>Guião</TableHead><TableHead className="text-right">Custo</TableHead><TableHead className="text-right">Publicações</TableHead><TableHead className="text-right">Por publicação</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {d.scripts.map((s) => (
                            <TableRow key={s.content_id} data-cost={s.content_id}>
                              <TableCell className="max-w-[14rem]">
                                <span className="block truncate">{s.date} · {s.n} · {s.tema ?? "sem tema"}</span>
                                <span className="text-xs text-muted-foreground">{EDITORIAL_LABEL[s.editorial_status as EditorialStatus] ?? s.editorial_status} · {METHOD[s.method] ?? s.method}</span>
                              </TableCell>
                              <TableCell className="text-right tabular-nums">{s.cost_known ? eur(s.cost_eur, 3) : "desconhecido"}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.publications}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.cost_per_publication === null ? "-" : eur(s.cost_per_publication, 3)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    )}
                  </CardContent>
                </Card>
              </WidgetBoundary>
            </div>
          </>
        )}
      </LearnState>
    </div>
  );
}
