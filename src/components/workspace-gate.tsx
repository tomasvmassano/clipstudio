"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";

/**
 * Porta comum das páginas: só mostra o conteúdo com sessão e workspace escolhido.
 * `need` esconde a página a quem não tem a capacidade (o servidor recusaria de qualquer forma).
 */
export function WorkspaceGate({ need, children }: { need?: string; children: (access: Access) => ReactNode }) {
  const { mode, access, workspaces, email, can, error, refresh, signOut } = useSession();

  if (mode === "loading") {
    return (
      <div className="flex flex-col gap-3" aria-busy="true" aria-label="A carregar">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }
  if (mode === "anon") {
    return (
      <Alert>
        <AlertDescription className="flex flex-wrap items-center justify-between gap-3">
          <span>{error || "Precisas de entrar para ver isto."}</span>
          <Button size="sm" render={<Link href="/login" />} nativeButton={false}>Entrar</Button>
        </AlertDescription>
      </Alert>
    );
  }
  if (mode === "user" && workspaces.length === 0) {
    return (
      <Alert>
        <AlertDescription className="flex flex-col gap-3">
          <span>
            Entraste como <b>{email}</b>, mas ainda não tens acesso a nenhum cliente. Pede a quem gere a equipa um convite para este email. Quando o convite existir, carrega em Verificar.
          </span>
          <span className="flex gap-2">
            <Button size="sm" onClick={() => refresh()}>Verificar outra vez</Button>
            <Button size="sm" variant="ghost" onClick={() => signOut()}>Sair</Button>
          </span>
        </AlertDescription>
      </Alert>
    );
  }
  if (!access) return null;
  if (need && !can(need)) {
    return (
      <Alert>
        <AlertDescription>Não tens permissão para esta página neste workspace. Se precisas dela, pede a quem gere a equipa.</AlertDescription>
      </Alert>
    );
  }
  return <>{children(access)}</>;
}
