"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import { WorkspaceGate } from "@/components/workspace-gate";
import { clientPath } from "@/lib/ws-path";

/**
 * Rotas antigas sem cliente (/guioes, /tarefas?tab=…): manda para a mesma página do último cliente aberto,
 * mantendo os parâmetros. Não dá acesso a nada: a página de destino volta a verificar tudo.
 */
export function ToClient({ sub }: { sub: string }) {
  const { mode, lastWs } = useSession();
  const router = useRouter();
  const target = mode === "user" || mode === "code" ? lastWs() : null;
  useEffect(() => {
    if (target) router.replace(clientPath(target, sub) + window.location.search);
  }, [target, sub, router]);
  if (mode === "loading" || target) return <Skeleton className="h-64" aria-label="A abrir o cliente" />;
  return <WorkspaceGate>{() => null}</WorkspaceGate>;
}
