"use client";

import type { ReactNode } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import { useFlags } from "@/lib/flags";

/**
 * Esconde uma página de um módulo em teste (MIG-09) a quem não a tem ligada, também quando se entra pelo endereço.
 * Não é autorização: as RPCs do módulo continuam a verificar as capacidades no servidor (CAP-09).
 */
export function FlagGate({ flag, ws, children }: { flag: string; ws: string | null; children: ReactNode }) {
  const { access, mode } = useSession();
  const flags = useFlags(ws, access?.token ?? null, mode !== "loading");
  if (!flags) return <Skeleton className="h-64" />;
  if (!flags.has(flag)) return <Alert><AlertDescription>Esta funcionalidade ainda está em teste e não está ligada para ti.</AlertDescription></Alert>;
  return <>{children}</>;
}
