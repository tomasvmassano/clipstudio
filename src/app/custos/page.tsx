"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { FlagGate } from "@/components/flag-gate";
import { useSession } from "@/components/session-provider";
import { AiUsageView } from "@/components/costs/ai-usage";

/*
 * Custos da agência (PRD §2 espaço da agência, M10 FR-10-01; ADR-0060): consumo de IA de todos os clientes em que a pessoa
 * tem costs.read, por cliente, agente, modelo e execução. Só com costs.read_agency (por defeito o dono da agência); o
 * servidor volta a verificar tudo e omite os clientes sem acesso. A equipa do cliente e o código de equipa nunca entram.
 */
export default function AgencyCostsPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("costs.read_agency")) return <Alert><AlertDescription>Os custos da agência são só para quem tem acesso aos custos da agência.</AlertDescription></Alert>;
  return (
    <FlagGate flag="costs.agency" ws={null}>
      <div className="flex min-w-0 flex-col gap-4">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight">Custos da agência</h1>
          <p className="text-sm text-muted-foreground">Consumo de IA dos agentes em todos os clientes a que tens acesso, por cliente, agente, modelo e execução.</p>
        </div>
        <AiUsageView ws={null} token={null} />
      </div>
    </FlagGate>
  );
}
