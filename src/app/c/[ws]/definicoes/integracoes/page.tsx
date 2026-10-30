"use client";

import { RotateCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WidgetBoundary } from "@/components/widget-boundary";
import { IntegCard, IntegState } from "@/components/integ/integ-parts";
import { useLoad } from "@/components/perf/perf-shared";
import type { Access } from "@/lib/access";
import { fetchIntegrations } from "@/lib/integrations";
import { dateTime } from "@/lib/perf-format";

/*
 * Centro de integrações do cliente (PRD FR-15-03, FR-17-16; ADR-0039). Só estados reais: contas sociais por ligar até as
 * plataformas aprovarem a app, recolha de métricas e motor de agentes lidos da base. Ligar e renovar aparecem
 * indisponíveis com o motivo; revogar e testar só para quem gere (o servidor decide).
 */

export default function IntegracoesPage() {
  return (
    <WorkspaceGate need="integrations.read">
      {(access) => <FlagGate flag="integrations.center" ws={access.ws}><Integracoes access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}

function Integracoes({ access }: { access: Access }) {
  const r = useLoad(() => fetchIntegrations(access), access.ws);
  const d = r.data;
  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Integrações</h1>
          <p className="text-sm text-muted-foreground">
            Estado real de cada ligação deste cliente. {d ? (d.can_manage ? "Testar e revogar ficam no histórico com quem o fez." : "Só quem gere as integrações deste cliente pode testar ou revogar.") : ""}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {d && <span className="text-xs text-muted-foreground">Atualizado {dateTime(d.generated_at, d.timezone)}</span>}
          <Button size="sm" variant="outline" onClick={r.reload}><RotateCwIcon /> Atualizar</Button>
        </div>
      </div>
      <IntegState loading={r.loading} error={r.error} reload={r.reload} forbidden="Não tens acesso às integrações deste cliente.">
        {d && (
          d.items.length === 0 ? <p className="text-sm text-muted-foreground">Não há integrações registadas para clientes.</p> : (
            <div className="grid gap-3 md:grid-cols-2">
              {d.items.map((it) => (
                <WidgetBoundary key={it.key} label={it.label}>
                  <IntegCard item={it} access={access} tz={d.timezone} canManage={d.can_manage} onChanged={r.reload} />
                </WidgetBoundary>
              ))}
            </div>
          )
        )}
      </IntegState>
    </div>
  );
}
