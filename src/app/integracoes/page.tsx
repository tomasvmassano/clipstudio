"use client";

import Link from "next/link";
import { ArrowRightIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSession } from "@/components/session-provider";
import { WidgetBoundary } from "@/components/widget-boundary";
import { IntegState, LimitLine, StateBadge, UnavailableActions } from "@/components/integ/integ-parts";
import { useLoad } from "@/components/perf/perf-shared";
import { JOB_STATUS_LABEL, ago } from "@/lib/integ-format";
import { clientPath } from "@/lib/ws-path";
import { fetchAgencyIntegrations, type AgencyClient, type IntegAgency } from "@/lib/integrations";

/*
 * Integrações da agência (PRD FR-17-16, ING-01, FR-13-01; ADR-0039). Só para o dono da agência: o que é da agência
 * (armazenamento, email, limites das APIs, workers) e o estado das integrações de cada cliente. Nada aqui liga contas:
 * o que ainda não existe aparece por ligar com o motivo.
 */

export default function IntegracoesAgenciaPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("integrations.agency.read")) return <Alert><AlertDescription>As integrações da agência são só do dono da agência.</AlertDescription></Alert>;
  return <Agencia />;
}

function Agencia() {
  const r = useLoad(fetchAgencyIntegrations, "agency");
  const d = r.data;
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Integrações da agência</h1>
          <p className="text-sm text-muted-foreground">Estados reais. Ligar contas das plataformas fica indisponível até as plataformas aprovarem a app (PLAT-01..03).</p>
        </div>
        <Button size="sm" variant="outline" onClick={r.reload}><RotateCwIcon /> Atualizar</Button>
      </div>
      <IntegState loading={r.loading} error={r.error} reload={r.reload} forbidden="As integrações da agência são só do dono da agência.">
        {d && <AgencyView d={d} />}
      </IntegState>
    </div>
  );
}

function AgencyView({ d }: { d: IntegAgency }) {
  return (
    <>
      <section aria-labelledby="integ-agencia" className="flex flex-col gap-2">
        <h2 id="integ-agencia" className="text-base font-medium">Da agência</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {d.items.map((it) => (
            <WidgetBoundary key={it.key} label={it.label}>
              <Card data-integration={it.key}>
                <CardHeader>
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <CardTitle className="text-base">{it.label}</CardTitle>
                    <StateBadge state={it.state} />
                  </div>
                  <CardDescription>{it.provides}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-2 text-sm">
                  {it.kind === "limits" && (d.limits.length === 0
                    ? <p className="text-muted-foreground">Sem limites registados.</p>
                    : d.limits.map((l) => <div key={l.platform}><span className="font-medium capitalize">{l.platform}</span><LimitLine l={l} /></div>))}
                  {it.kind === "limits" && <p className="text-xs text-muted-foreground">Editam-se nas regras do calendário de publicações.</p>}
                  {it.blocked_reason && <p className="text-xs text-muted-foreground">{it.blocked_reason}</p>}
                  {it.missing && <p className="text-xs text-muted-foreground"><span className="font-medium text-foreground">O que falta:</span> {it.missing}</p>}
                  <UnavailableActions actions={it.actions} />
                </CardContent>
              </Card>
            </WidgetBoundary>
          ))}
          <WidgetBoundary label="Workers">
            <Card data-integration="workers">
              <CardHeader>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <CardTitle className="text-base">Workers do motor de agentes</CardTitle>
                  <StateBadge state={d.workers.some((w) => w.active) ? "ativo" : "por_alojar"} />
                </div>
                <CardDescription>Processos que correm as execuções dos agentes. Aparecem quando contactam a base.</CardDescription>
              </CardHeader>
              <CardContent className="text-sm">
                {d.workers.length === 0 ? <p className="text-muted-foreground">Nenhum worker contactou a base: está por alojar (FR-17-14).</p> : (
                  <ul className="flex flex-col gap-1">
                    {d.workers.map((w) => (
                      <li key={w.id} className="flex flex-wrap justify-between gap-2 text-xs" data-worker={w.id}>
                        <span className="font-medium">{w.id}{w.version ? ` · ${w.version}` : ""}</span>
                        <span className="text-muted-foreground">{w.active ? "ativo" : "sem contacto"} · {ago(w.last_seen)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          </WidgetBoundary>
        </div>
      </section>
      <WidgetBoundary label="Por cliente">
        <section aria-labelledby="integ-clientes" className="flex flex-col gap-2">
          <h2 id="integ-clientes" className="text-base font-medium">Por cliente</h2>
          {d.clients.length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há clientes ativos.</p> : (
            <Card className="shadow-none dark:ring-0">
              <CardContent className="overflow-x-auto p-0">
                <Table className="min-w-[720px]">
                  <TableHeader><TableRow>
                    <TableHead>Cliente</TableHead><TableHead>Contas sociais</TableHead><TableHead>Recolha de métricas</TableHead>
                    <TableHead>Motor de agentes</TableHead><TableHead><span className="sr-only">Abrir</span></TableHead>
                  </TableRow></TableHeader>
                  <TableBody>{d.clients.map((c) => <ClientRow key={c.id} c={c} />)}</TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </section>
      </WidgetBoundary>
    </>
  );
}

function ClientRow({ c }: { c: AgencyClient }) {
  const s = c.social;
  return (
    <TableRow data-client={c.id}>
      <TableCell className="align-top font-medium">{c.name}{!c.enabled && <span className="block text-xs font-normal text-muted-foreground">centro desligado neste cliente</span>}</TableCell>
      <TableCell className="align-top text-xs">
        {s.total === 0 ? <span className="text-muted-foreground">sem contas</span> : (
          <>{s.ligada} ligadas · {s.por_ligar} por ligar{s.expirada ? ` · ${s.expirada} expiradas` : ""}{s.revogada ? ` · ${s.revogada} revogadas` : ""}</>
        )}
      </TableCell>
      <TableCell className="align-top"><StateBadge state={c.scraping.state} /><span className="block text-xs text-muted-foreground">{ago(c.scraping.last_sync_at)}</span></TableCell>
      <TableCell className="align-top">
        <StateBadge state={c.worker.state} />
        <span className="block text-xs text-muted-foreground">
          {c.worker.last_job ? `${JOB_STATUS_LABEL[c.worker.last_job.status] ?? c.worker.last_job.status} ${ago(c.worker.last_job.finished_at ?? c.worker.last_job.started_at ?? c.worker.last_job.created_at)}` : "sem execuções"}
          {c.worker.queued ? ` · ${c.worker.queued} na fila` : ""}
        </span>
      </TableCell>
      <TableCell className="text-right align-top">
        <Button size="sm" variant="ghost" render={<Link href={clientPath(c.id, "/definicoes/integracoes")} />} nativeButton={false} aria-label={`Abrir as integrações de ${c.name}`}>Abrir <ArrowRightIcon /></Button>
      </TableCell>
    </TableRow>
  );
}
