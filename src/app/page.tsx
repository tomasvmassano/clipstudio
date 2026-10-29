"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRightIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { Delta, DeltaIcon, DeltaValue } from "@/components/delta";
import { KpiCard } from "@/components/kpi-card";
import { useSession } from "@/components/session-provider";
import { WorkspaceGate } from "@/components/workspace-gate";
import { clientPath } from "@/lib/ws-path";
import { useLogoUrl } from "@/lib/branding";
import {
  LOWER_IS_BETTER, PERIODS, asKpi, deltaPct, fetchAgency, fmtKpi, fmtRange, loadPeriod, rangeFor, savePeriod,
  type AgencyClient, type AgencyResp, type PeriodKey,
} from "@/lib/dashboard";

/*
 * Painel da agência (PRD R-04): todos os clientes a que tens acesso lado a lado.
 * Cada número só aparece se tens a permissão dele nesse cliente; nos totais diz-se quantos clientes ficaram de fora.
 */

const COLS = [
  { key: "kpi.scripts_created", label: "Guiões criados", desc: "Guiões novos criados no período." },
  { key: "kpi.pending_approval", label: "À espera", desc: "Guiões em revisão neste momento (sem comparação).", snapshot: true },
  { key: "kpi.approved", label: "Aprovados", desc: "Guiões que passaram a aprovados no período." },
  { key: "kpi.recorded", label: "Gravados", desc: "Guiões gravados no período." },
  { key: "kpi.published", label: "Publicados", desc: "Conteúdos marcados como publicados no período." },
  { key: "kpi.views", label: "Views", desc: "Views dos reels das contas de cada cliente publicados no período." },
  { key: "kpi.engagement", label: "Engagement", desc: "Interações ÷ views; no total, média ponderada pelas views de cada cliente." },
  { key: "kpi.sources", label: "Fontes", desc: "Fontes que entraram no período." },
  { key: "kpi.tasks_done", label: "Tarefas feitas", desc: "Tarefas concluídas no período." },
  { key: "kpi.costs", label: "Custo agentes", desc: "Custo das execuções dos agentes no período, em EUR." },
] as const;

/** Entrada da app: a equipa da agência fica no Painel; quem é de um cliente (ou entra com código) vai direto para o seu cliente. */
export default function AgenciaPage() {
  const { mode, canOrg, lastWs } = useSession();
  const router = useRouter();
  const agency = canOrg("dashboard.agency");
  const target = !agency && (mode === "user" || mode === "code") ? lastWs() : null;
  useEffect(() => { if (target) router.replace(clientPath(target)); }, [target, router]);
  if (mode === "loading" || target) return <Skeleton className="h-64" />;
  if (!agency) {
    // sem clientes nem agência: o WorkspaceGate explica o que falta (convite, entrar)
    return <WorkspaceGate>{() => null}</WorkspaceGate>;
  }
  return <Agencia />;
}

function Agencia() {
  const { setWorkspace } = useSession();
  const tz = "Asia/Dubai";
  const [p, setP] = useState(loadPeriod);
  const range = useMemo(() => rangeFor(p.key, tz, { from: p.from, to: p.to }), [p]);
  const [data, setData] = useState<AgencyResp | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const setPeriod = (next: typeof p) => { setP(next); savePeriod(next); };

  useEffect(() => {
    let alive = true;
    fetchAgency(range.from, range.to).then((d) => { if (alive) { setData(d); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [range.from, range.to, rev]);

  const open = (c: AgencyClient) => setWorkspace(c.id);
  const visible = COLS.filter((c) => data && (data.totals[c.key] || data.clients.some((x) => asKpi(x.kpis[c.key]))));

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Painel da agência</h1>
        <p className="text-sm text-muted-foreground">
          {data ? `${data.count} ${data.count === 1 ? "cliente" : "clientes"} a que tens acesso` : "Os clientes a que tens acesso"} · {fmtRange(range.from, range.to)} · datas no fuso de cada cliente
        </p>
      </div>
      <div className="flex flex-wrap items-end gap-2">
        <ToggleGroup value={[p.key]} variant="outline" size="sm" aria-label="Período"
          onValueChange={(v) => { const k = (v as string[])[0] as PeriodKey | undefined; if (k) setPeriod({ ...p, key: k }); }}>
          {PERIODS.map((x) => <ToggleGroupItem key={x.key} value={x.key}>{x.label}</ToggleGroupItem>)}
          <ToggleGroupItem value="custom">Outro</ToggleGroupItem>
        </ToggleGroup>
        {p.key === "custom" && (
          <>
            <label className="flex flex-col gap-1 text-xs">De<Input type="date" value={p.from} onChange={(e) => setPeriod({ ...p, from: e.target.value })} /></label>
            <label className="flex flex-col gap-1 text-xs">Até<Input type="date" value={p.to} onChange={(e) => setPeriod({ ...p, to: e.target.value })} /></label>
          </>
        )}
      </div>

      {err ? (
        <Alert variant="destructive">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>Não consegui carregar o painel: {err}</span>
            <Button size="sm" variant="outline" onClick={() => { setErr(""); setRev((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button>
          </AlertDescription>
        </Alert>
      ) : !data ? (
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">{Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-32" />)}</div>
      ) : data.count === 0 ? (
        <Alert><AlertDescription>Ainda não tens acesso a nenhum cliente ativo. Pede ao dono da agência que te atribua aos clientes em que trabalhas.</AlertDescription></Alert>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {visible.filter((c) => data.totals[c.key]).slice(0, 8).map((c) => {
              const miss = data.missing[c.key];
              return <KpiCard key={c.key} w={{ key: c.key, label: `${c.label} (total)`, description: c.desc, snapshot: "snapshot" in c }} k={data.totals[c.key]}
                period={data.period} extra={miss ? `Sem ${miss} ${miss === 1 ? "cliente" : "clientes"} a que não tens acesso a este número.` : undefined} />;
            })}
          </div>
          <Card className="shadow-none dark:ring-0">
            <CardContent className="overflow-x-auto p-0">
              <table className="w-full min-w-[720px] text-sm">
                <thead>
                  <tr className="border-b text-left text-xs text-muted-foreground">
                    <th className="px-4 py-2 font-normal">Cliente</th>
                    {visible.map((c) => <th key={c.key} className="px-3 py-2 text-right font-normal" title={c.desc}>{c.label}</th>)}
                    <th className="px-3 py-2"><span className="sr-only">Abrir</span></th>
                  </tr>
                </thead>
                <tbody>
                  {data.clients.map((c) => (
                    <tr key={c.id} className="border-b last:border-0">
                      <td className="px-4 py-2">
                        <span className="flex items-center gap-2"><ClientMark c={c} /><span className="font-medium">{c.name}</span>
                          {c.handle && <span className="text-xs text-muted-foreground">@{c.handle}</span>}</span>
                      </td>
                      {visible.map((col) => {
                        const k = asKpi(c.kpis[col.key]);
                        const d = deltaPct(k, "snapshot" in col);
                        return (
                          <td key={col.key} className="px-3 py-2 text-right tabular-nums">
                            {k ? (
                              <span className="inline-flex flex-col items-end">
                                {fmtKpi(col.key, k.value)}
                                {d != null && (
                                  <Delta value={LOWER_IS_BETTER.has(col.key) ? -d : d} className="text-xs"><DeltaIcon /><DeltaValue precision={0} /></Delta>
                                )}
                              </span>
                            ) : <span className="text-xs text-muted-foreground" title="Sem permissão para este número neste cliente">sem acesso</span>}
                          </td>
                        );
                      })}
                      <td className="px-3 py-2 text-right">
                        <Button size="sm" variant="ghost" onClick={() => open(c)} aria-label={`Abrir o Início de ${c.name}`}>Abrir <ArrowRightIcon /></Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}

function ClientMark({ c }: { c: AgencyClient }) {
  const url = useLogoUrl(c.logo_path);
  // eslint-disable-next-line @next/next/no-img-element
  if (url) return <img src={url} alt="" className="size-6 rounded-sm object-contain" style={{ backgroundColor: c.brand_color ?? undefined }} />;
  return <span aria-hidden className="size-6 rounded-sm bg-muted" style={{ backgroundColor: c.brand_color ?? undefined }} />;
}
