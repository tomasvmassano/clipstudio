"use client";

import { useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { LoadState, useLoad } from "@/components/perf/perf-shared";
import { PerfAccounts, PerfFamilies } from "@/components/perf/perf-accounts";
import { PerfPublications } from "@/components/perf/perf-publications";
import { PerfLevers, PerfViews } from "@/components/perf/perf-views";
import type { Access } from "@/lib/access";
import { fetchPerfCenter } from "@/lib/perf";
import { clientPath } from "@/lib/ws-path";

/*
 * Centro de desempenho (PRD §40, ADR-0033): fotografias por idade, índice normalizado por conta, vistas por atributo,
 * origem (R-16) e linhagem (R-18) de cada publicação, alavancas "o que replicar". Em teste: flag perf.center.
 * A flag é disponibilidade; o servidor verifica analytics.read em cada RPC.
 */

export default function CentroPage() {
  return (
    <WorkspaceGate need="analytics.read">
      {(access) => <FlagGate flag="perf.center" ws={access.ws}><CentroView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

function CentroView({ access }: { access: Access }) {
  const [tab, setTab] = useState("contas");
  const [onlySystem, setOnlySystem] = useState(true);
  const center = useLoad(() => fetchPerfCenter(access), access.ws);
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Centro de desempenho</h1>
          <p className="text-sm text-muted-foreground">
            Cada publicação comparada com o normal da própria conta, na mesma idade. Métricas da recolha por scraping; alcance, retenção e crescimento chegam quando as contas forem ligadas pela API oficial.
          </p>
        </div>
        <Button size="sm" variant="outline" render={<Link href={clientPath(access.ws, "/desempenho")} />} nativeButton={false}>Desempenho clássico</Button>
      </div>
      <LoadState loading={center.loading} error={center.error} reload={center.reload} label="o centro de desempenho">
        {center.data && (
          <Tabs value={tab} onValueChange={(v) => setTab(String(v))}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="max-w-full overflow-x-auto">
                <TabsList aria-label="Secções do centro de desempenho">
                  <TabsTrigger value="contas">Contas</TabsTrigger>
                  <TabsTrigger value="publicacoes">Publicações</TabsTrigger>
                  <TabsTrigger value="vistas">Vistas</TabsTrigger>
                  <TabsTrigger value="replicar">O que replicar</TabsTrigger>
                  <TabsTrigger value="metricas">Métricas</TabsTrigger>
                </TabsList>
              </div>
              {(tab === "vistas" || tab === "replicar") && (
                <label className="flex items-center gap-2 text-sm">
                  <Switch aria-label="Só o que fizemos" checked={onlySystem} onCheckedChange={(c) => setOnlySystem(Boolean(c))} />
                  Só o que fizemos
                </label>
              )}
            </div>
            <TabsContent value="contas">
              <WidgetBoundary label="Contas"><PerfAccounts access={access} center={center.data} onChange={center.setData} /></WidgetBoundary>
            </TabsContent>
            <TabsContent value="publicacoes">
              <WidgetBoundary label="Publicações"><PerfPublications access={access} center={center.data} /></WidgetBoundary>
            </TabsContent>
            <TabsContent value="vistas">
              <WidgetBoundary label="Vistas"><PerfViews access={access} onlySystem={onlySystem} /></WidgetBoundary>
            </TabsContent>
            <TabsContent value="replicar">
              <WidgetBoundary label="O que replicar"><PerfLevers access={access} center={center.data} onlySystem={onlySystem} /></WidgetBoundary>
            </TabsContent>
            <TabsContent value="metricas">
              <WidgetBoundary label="Métricas"><PerfFamilies center={center.data} /></WidgetBoundary>
            </TabsContent>
          </Tabs>
        )}
      </LoadState>
    </div>
  );
}
