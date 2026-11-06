"use client";

import Link from "next/link";
import { ArrowRightIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSession } from "@/components/session-provider";
import { WidgetBoundary } from "@/components/widget-boundary";
import { useLoad } from "@/components/perf/perf-shared";
import { clientPath } from "@/lib/ws-path";
import { fetchHealth, isForbidden, type Health, type HealthQueue, type HealthWorkspace, type WsCounts } from "@/lib/health";
import {
  HEARTBEAT_LABEL, SOURCE_LABEL, STATUS_LABEL, ago, heartbeatState, jobPath, kindLabel, overallTone, redactSecrets,
} from "@/lib/health-format";

/*
 * Saúde do sistema (PRD FR-17-15; ADR-0058). Agência, com ops.health (dono e admin). Só o que está na base: workers
 * (agent_workers), filas (agent_jobs, media_jobs), trabalhos a correr com o último sinal, falhas com o erro sem segredos,
 * e os alertas que o tick de 5 em 5 minutos enviou aos donos da agência. O servidor filtra os clientes por pessoa.
 */

const FORBIDDEN = "A saúde do sistema é do dono e dos administradores da agência. Não tens acesso a ela.";

export default function SaudePage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("ops.health")) return <Alert><AlertDescription>{FORBIDDEN}</AlertDescription></Alert>;
  return <Saude />;
}

function Saude() {
  const r = useLoad(fetchHealth, "health");
  const d = r.data;
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Saúde do sistema</h1>
          <p className="text-sm text-muted-foreground">
            Workers, filas e falhas lidos da base{d ? ` · atualizado ${ago(d.generated_at)}` : ""}. Só os clientes a que tens acesso.
          </p>
        </div>
        <Button size="sm" variant="outline" onClick={r.reload} disabled={r.loading}><RotateCwIcon /> Atualizar</Button>
      </div>
      {r.error ? (
        isForbidden(r.error) ? <Alert><AlertDescription>{FORBIDDEN}</AlertDescription></Alert> : (
          <Alert variant="destructive" role="alert">
            <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
              <span>Não consegui carregar a saúde do sistema: {(r.error as Error).message}</span>
              <Button size="sm" variant="outline" onClick={r.reload}><RotateCwIcon /> Tentar de novo</Button>
            </AlertDescription>
          </Alert>
        )
      ) : r.loading || !d ? (
        <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar a saúde do sistema">
          <div className="grid gap-3 md:grid-cols-3">{Array.from({ length: 3 }, (_, i) => <Skeleton key={i} className="h-32" />)}</div>
          <Skeleton className="h-48" />
        </div>
      ) : <HealthView d={d} />}
    </div>
  );
}

const TONE = {
  bad: { label: "Há problemas agora", cls: "border-red-500/40 bg-red-500/5" },
  warn: { label: "Houve falhas nas últimas 24 h", cls: "border-amber-500/40 bg-amber-500/5" },
  good: { label: "Sem problemas", cls: "border-emerald-500/40 bg-emerald-500/5" },
} as const;

function HealthView({ d }: { d: Health }) {
  const dead24 = d.failure_counts.agent.dead_24h + d.failure_counts.media.dead_24h;
  const tone = overallTone(d.queues, dead24);
  return (
    <>
      <div className={`rounded-lg border p-3 text-sm ${TONE[tone].cls}`} role="status" data-health={tone}>
        <p className="font-medium">{TONE[tone].label}</p>
        <ul className="mt-1 list-disc pl-5 text-muted-foreground">
          {d.queues.filter((q) => q.uncovered > 0).map((q) => (
            <li key={q.source}>{SOURCE_LABEL[q.source]}: {q.uncovered} {q.uncovered === 1 ? "trabalho pronto" : "trabalhos prontos"} sem worker visto nos últimos {d.thresholds.worker_stale_minutes} min ({q.uncovered_kinds.map(kindLabel).join(", ")}).</li>
          ))}
          {d.queues.filter((q) => q.stalled > 0).map((q) => (
            <li key={`s-${q.source}`}>{SOURCE_LABEL[q.source]}: {q.stalled} a correr sem sinal (lease expirada). Voltam à fila quando um worker reclamar trabalho.</li>
          ))}
          {dead24 > 0 && <li>{dead24} {dead24 === 1 ? "trabalho esgotou" : "trabalhos esgotaram"} as tentativas nas últimas 24 h.</li>}
          <li>
            Alertas automáticos: {d.tick.scheduled ? "agendados de 5 em 5 minutos" : "não estão agendados nesta base"}
            {" · "}última verificação {ago(d.tick.last_run_at)}.
          </li>
        </ul>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <WidgetBoundary label="Workers"><Workers d={d} /></WidgetBoundary>
        {d.queues.map((q) => <WidgetBoundary key={q.source} label={`Fila de ${SOURCE_LABEL[q.source]}`}><QueueCard q={q} d={d} /></WidgetBoundary>)}
      </div>

      <WidgetBoundary label="A correr"><Running d={d} /></WidgetBoundary>
      <WidgetBoundary label="Falhas"><Failures d={d} /></WidgetBoundary>
      <WidgetBoundary label="Por cliente"><PerWorkspace d={d} /></WidgetBoundary>
      <WidgetBoundary label="Alertas enviados"><Alerts d={d} /></WidgetBoundary>
    </>
  );
}

function Workers({ d }: { d: Health }) {
  return (
    <Card className="h-full shadow-none dark:ring-0" data-section="workers">
      <CardHeader>
        <CardTitle className="text-base">Workers</CardTitle>
        <CardDescription>Aparecem quando pedem trabalho ou dão sinal. Recente = nos últimos {d.thresholds.worker_stale_minutes} min.</CardDescription>
      </CardHeader>
      <CardContent className="text-sm">
        {d.workers.length === 0 ? <p className="text-muted-foreground">Nenhum worker contactou a base até hoje.</p> : (
          <ul className="flex flex-col gap-2">
            {d.workers.map((w) => (
              <li key={w.id} className="flex flex-col gap-0.5" data-worker={w.id}>
                <span className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium break-all">{w.id}{w.version ? ` · ${w.version}` : ""}</span>
                  <Badge variant={w.recent ? "secondary" : "destructive"}>{w.recent ? "recente" : "sem contacto"}</Badge>
                </span>
                <span className="text-xs text-muted-foreground">{ago(w.last_seen)} · {w.kinds.map(kindLabel).join(", ") || "sem tipos"}</span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

function QueueCard({ q, d }: { q: HealthQueue; d: Health }) {
  const fc = d.failure_counts[q.source];
  return (
    <Card className="h-full shadow-none dark:ring-0" data-queue={q.source}>
      <CardHeader>
        <CardTitle className="text-base">Fila de {SOURCE_LABEL[q.source].toLowerCase()}</CardTitle>
        <CardDescription>{q.source === "agent" ? "Execuções dos agentes (agent_jobs)." : "Verificação de envios, exportações e pacotes (media_jobs)."}</CardDescription>
      </CardHeader>
      <CardContent className="grid grid-cols-2 gap-2 text-sm">
        <Num label="Prontos à espera" v={q.ready} bad={q.uncovered > 0} />
        <Num label="Agendados para depois" v={q.queued - q.ready} />
        <Num label="A correr" v={q.running} />
        <Num label="Sem sinal" v={q.stalled} bad={q.stalled > 0} />
        <Num label="Falhas 24 h" v={fc.failed_24h + fc.dead_24h} bad={fc.dead_24h > 0} />
        <Num label="Falhas 7 dias" v={fc.failed_7d + fc.dead_7d} />
        <p className="col-span-2 text-xs text-muted-foreground">Mais antigo pronto: {q.oldest_ready_at ? ago(q.oldest_ready_at) : "nenhum"}</p>
      </CardContent>
    </Card>
  );
}

const Num = ({ label, v, bad }: { label: string; v: number; bad?: boolean }) => (
  <div><p className={`text-xl font-semibold tabular-nums ${bad ? "text-red-500" : ""}`}>{v}</p><p className="text-xs text-muted-foreground">{label}</p></div>
);

function Running({ d }: { d: Health }) {
  return (
    <section aria-labelledby="saude-running" className="flex flex-col gap-2">
      <h2 id="saude-running" className="text-base font-medium">A correr agora</h2>
      {d.running.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum trabalho a correr.</p> : (
        <Card className="shadow-none dark:ring-0">
          <CardContent className="overflow-x-auto p-0">
            <Table className="min-w-[720px]">
              <TableHeader><TableRow>
                <TableHead>Cliente</TableHead><TableHead>Trabalho</TableHead><TableHead>Último sinal</TableHead><TableHead>Tentativa</TableHead>
                <TableHead>Worker</TableHead><TableHead><span className="sr-only">Abrir</span></TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {d.running.map((j) => {
                  const hb = heartbeatState(j);
                  return (
                    <TableRow key={j.id} data-job={j.id}>
                      <TableCell className="font-medium">{j.workspace}</TableCell>
                      <TableCell>{SOURCE_LABEL[j.source]} · {kindLabel(j.kind)}{j.cancel_requested ? " · cancelamento pedido" : ""}</TableCell>
                      <TableCell><span className={hb === "ok" ? "" : "text-red-500"}>{HEARTBEAT_LABEL[hb]}</span><span className="block text-xs text-muted-foreground">{ago(j.heartbeat_at)}</span></TableCell>
                      <TableCell className="tabular-nums">{j.attempts} de {j.max_attempts}</TableCell>
                      <TableCell className="text-xs break-all">{j.locked_by ?? "-"}</TableCell>
                      <TableCell className="text-right"><OpenLink ws={j.workspace_id} name={j.workspace} path={jobPath(j.source, j.kind, j.asset_id)} /></TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </section>
  );
}

function Failures({ d }: { d: Health }) {
  return (
    <section aria-labelledby="saude-failures" className="flex flex-col gap-2">
      <h2 id="saude-failures" className="text-base font-medium">Falhas nos últimos {d.thresholds.window_days} dias</h2>
      {d.failures.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum trabalho falhou nos últimos {d.thresholds.window_days} dias.</p> : (
        <Card className="shadow-none dark:ring-0">
          <CardContent className="overflow-x-auto p-0">
            <Table className="min-w-[760px]">
              <TableHeader><TableRow>
                <TableHead>Quando</TableHead><TableHead>Cliente</TableHead><TableHead>Trabalho</TableHead><TableHead>Estado</TableHead>
                <TableHead>Último erro</TableHead><TableHead><span className="sr-only">Abrir</span></TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {d.failures.map((f) => (
                  <TableRow key={f.id} data-failure={f.id}>
                    <TableCell className="whitespace-nowrap text-xs">{ago(f.finished_at)}</TableCell>
                    <TableCell className="font-medium">{f.workspace}</TableCell>
                    <TableCell>{SOURCE_LABEL[f.source]} · {kindLabel(f.kind)}{f.run_id ? <span className="block text-xs text-muted-foreground">execução {f.run_id}</span> : null}</TableCell>
                    <TableCell><span className={f.status === "dead" ? "text-red-500" : "text-amber-500"}>{STATUS_LABEL[f.status]}</span><span className="block text-xs text-muted-foreground">{f.attempts} de {f.max_attempts} tentativas</span></TableCell>
                    <TableCell className="max-w-[360px] text-xs break-words whitespace-normal">{f.last_error ? redactSecrets(f.last_error) : <span className="text-muted-foreground">sem mensagem</span>}</TableCell>
                    <TableCell className="text-right"><OpenLink ws={f.workspace_id} name={f.workspace} path={jobPath(f.source, f.kind, f.asset_id)} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </section>
  );
}

function PerWorkspace({ d }: { d: Health }) {
  return (
    <section aria-labelledby="saude-ws" className="flex flex-col gap-2">
      <h2 id="saude-ws" className="text-base font-medium">Por cliente</h2>
      {d.workspaces.length === 0 ? <p className="text-sm text-muted-foreground">Ainda não tens nenhum cliente ativo atribuído. Pede ao dono da agência que te atribua aos clientes em que trabalhas.</p> : (
        <Card className="shadow-none dark:ring-0">
          <CardContent className="overflow-x-auto p-0">
            <Table className="min-w-[640px]">
              <TableHeader><TableRow><TableHead>Cliente</TableHead><TableHead>Agentes</TableHead><TableHead>Media</TableHead></TableRow></TableHeader>
              <TableBody>{d.workspaces.map((w) => <WsRow key={w.id} w={w} />)}</TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </section>
  );
}

function WsRow({ w }: { w: HealthWorkspace }) {
  return (
    <TableRow data-client={w.id}>
      <TableCell className="align-top font-medium">{w.name}</TableCell>
      <TableCell className="align-top text-xs"><Counts c={w.agent} /></TableCell>
      <TableCell className="align-top text-xs"><Counts c={w.media} /></TableCell>
    </TableRow>
  );
}

function Counts({ c }: { c: WsCounts | null }) {
  if (!c) return <span className="text-muted-foreground" title="Sem permissão de leitura neste cliente">sem acesso</span>;
  return (
    <span className="flex flex-col gap-0.5">
      <span>{c.ready} prontos · {c.queued - c.ready} agendados · {c.running} a correr{c.stalled ? <span className="text-red-500"> · {c.stalled} sem sinal</span> : null}</span>
      <span className={c.failed_24h ? "text-red-500" : "text-muted-foreground"}>{c.failed_24h} falhas em 24 h · {c.failed_7d} em 7 dias</span>
      {c.oldest_ready_at && <span className="text-muted-foreground">mais antigo pronto {ago(c.oldest_ready_at)}</span>}
    </span>
  );
}

function Alerts({ d }: { d: Health }) {
  return (
    <section aria-labelledby="saude-alerts" className="flex flex-col gap-2">
      <h2 id="saude-alerts" className="text-base font-medium">Alertas enviados (7 dias)</h2>
      <p className="text-xs text-muted-foreground">Vão para a caixa de entrada dos donos da agência, uma vez por incidente.</p>
      {d.alerts.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum alerta nos últimos 7 dias.</p> : (
        <ul className="flex flex-col gap-1 text-sm">
          {d.alerts.map((a) => (
            <li key={a.id} className="flex flex-wrap justify-between gap-2 border-b py-1 last:border-0" data-alert={a.kind}>
              <span>
                <span className="font-medium">{a.kind === "worker_down" ? "Worker sem contacto" : "Trabalho esgotou as tentativas"}</span>
                {" · "}{SOURCE_LABEL[a.source]} · {a.workspace}
              </span>
              <span className="text-xs text-muted-foreground">{ago(a.created_at)} · {a.notified} {a.notified === 1 ? "pessoa avisada" : "pessoas avisadas"}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function OpenLink({ ws, name, path }: { ws: string; name: string; path: string }) {
  return (
    <Button size="sm" variant="ghost" render={<Link href={clientPath(ws, path)} />} nativeButton={false} aria-label={`Abrir em ${name}`}>
      Abrir <ArrowRightIcon />
    </Button>
  );
}
