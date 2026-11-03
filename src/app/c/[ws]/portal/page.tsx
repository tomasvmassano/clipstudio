"use client";

import { useCallback, useEffect, useState } from "react";
import { EyeIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { BlockCard } from "@/components/portal/portal-shared";
import { PublicationApprovals, ScriptApprovals } from "@/components/portal/portal-approvals";
import { Deliveries, Reports, Requests } from "@/components/portal/portal-status";
import type { Access } from "@/lib/access";
import { fetchPortal, fetchPortalBlock, type BlockKey, type PortalHome } from "@/lib/portal";

/*
 * Portal do cliente (SCALE-08, ADR-0041). Espaço do cliente. Aprovações, entregas do mês (sem valores), relatório de
 * desempenho e pedidos de conteúdo. Em teste: flag client.portal. Cada bloco é verificado no servidor e pode vir
 * indisponível com o motivo; um bloco que falha não derruba os outros.
 */

export default function PortalPage() {
  return (
    <WorkspaceGate need="scripts.read">
      {(access) => <FlagGate flag="client.portal" ws={access.ws}><Portal access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

function Portal({ access }: { access: Access }) {
  const [home, setHome] = useState<PortalHome | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchPortal(access)
      .then((h) => { if (alive) { setHome(h); setErr(null); } })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, attempt]);

  // recarregar só um bloco (depois de uma ação ou de "tentar de novo"); se falhar, o bloco mostra o erro
  const reload = useCallback(<K extends BlockKey>(k: K) => {
    fetchPortalBlock(access, k)
      .then((b) => setHome((h) => (h ? { ...h, blocks: { ...h.blocks, [k]: b } } : h)))
      .catch((e: Error) => setHome((h) => (h ? { ...h, blocks: { ...h.blocks, [k]: { available: false, code: "erro", reason: e.message } } } : h)));
  }, [access]);

  if (err) {
    return (
      <Alert variant="destructive" role="alert">
        <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
          <span>Não consegui abrir o portal: {err}</span>
          <Button size="sm" variant="outline" onClick={() => { setErr(null); setAttempt((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button>
        </AlertDescription>
      </Alert>
    );
  }
  if (!home) {
    return (
      <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar o portal">
        <Skeleton className="h-10 w-64" /><Skeleton className="h-48 w-full" /><Skeleton className="h-48 w-full" />
      </div>
    );
  }
  const b = home.blocks;
  const tz = home.client.timezone;
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Portal</h1>
          <p className="text-sm text-muted-foreground">O que espera por ti, o que foi entregue este mês, como está a correr e os teus pedidos. Horas em {tz}.</p>
        </div>
        <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}><RotateCwIcon /> Atualizar</Button>
      </div>
      {home.viewer.as_client && (
        <Alert data-portal-as-client>
          <AlertDescription className="flex items-center gap-2"><EyeIcon className="size-4 shrink-0" />
            Estás a ver o portal como a equipa do cliente o vê. As ações que fizeres aqui contam como da agência.
          </AlertDescription>
        </Alert>
      )}
      <div className="grid min-w-0 gap-4 xl:grid-cols-2">
        <WidgetBoundary label="guiões por aprovar">
          <BlockCard id="guioes" title="Guiões por aprovar" description="Lê, aprova ou pede alterações. A decisão fica presa a esta versão."
            block={b.scripts} reload={() => reload("scripts")}>
            {(x) => <ScriptApprovals access={access} block={x} onChanged={() => { reload("scripts"); reload("deliveries"); }} />}
          </BlockCard>
        </WidgetBoundary>
        <WidgetBoundary label="publicações por aprovar">
          <BlockCard id="publicacoes" title="Publicações por aprovar" description="Conta, dia, hora, legenda e versão exatos. Se algo mudar, voltas a aprovar."
            block={b.publications} reload={() => reload("publications")}>
            {(x) => <PublicationApprovals access={access} block={x} tz={tz} onChanged={() => reload("publications")} />}
          </BlockCard>
        </WidgetBoundary>
        <WidgetBoundary label="entregas do mês">
          <BlockCard id="entregas" title="Entregas do mês" description="Entregue e publicado contra o volume contratado."
            block={b.deliveries} reload={() => reload("deliveries")}>
            {(x) => <Deliveries block={x} />}
          </BlockCard>
        </WidgetBoundary>
        <WidgetBoundary label="relatório de desempenho">
          <BlockCard id="relatorios" title="Desempenho" description="Resumo dos últimos 30 dias por conta e os melhores da semana."
            block={b.reports} reload={() => reload("reports")}>
            {(x) => <Reports block={x} ws={access.ws} />}
          </BlockCard>
        </WidgetBoundary>
        <WidgetBoundary label="pedidos de conteúdo">
          <BlockCard id="pedidos" title="Pedidos de conteúdo" description="Pede vídeos e acompanha o que acontece a cada pedido."
            block={b.requests} reload={() => reload("requests")}>
            {(x) => <Requests access={access} block={x} onChanged={() => reload("requests")} />}
          </BlockCard>
        </WidgetBoundary>
      </div>
    </div>
  );
}
