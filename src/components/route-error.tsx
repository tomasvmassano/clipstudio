"use client";

import { useEffect } from "react";
import Link from "next/link";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

/**
 * Quando uma página rebenta (ADR-0019): explica em português, deixa tentar de novo e voltar, e nunca mostra
 * detalhes técnicos ao utilizador. O erro vai para a consola com a referência para o encontrar nos registos.
 */
export function RouteError({ error, retry, home = "/", homeLabel = "Voltar ao início" }: { error: unknown; retry: () => void; home?: string; homeLabel?: string }) {
  useEffect(() => { console.error("[clipstudio] erro na página", error); }, [error]);
  const ref = error instanceof Error && "digest" in error ? String((error as Error & { digest?: string }).digest ?? "") : "";
  return (
    <Alert variant="destructive" role="alert">
      <AlertDescription className="flex flex-col gap-3">
        <span><b>Esta página não carregou.</b> Algo correu mal do nosso lado; nada do que fizeste se perdeu. Tenta de novo; se continuar, avisa a equipa{ref ? ` com a referência ${ref}` : ""}.</span>
        <span className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => retry()}><RotateCwIcon /> Tentar de novo</Button>
          <Button size="sm" variant="outline" render={<Link href={home} />} nativeButton={false}>{homeLabel}</Button>
        </span>
      </AlertDescription>
    </Alert>
  );
}
