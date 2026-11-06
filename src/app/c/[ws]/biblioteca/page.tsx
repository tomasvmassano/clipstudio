"use client";

import { Suspense, useCallback } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { MediaLibraryView } from "@/components/media/media-library";
import { Skeleton } from "@/components/ui/skeleton";
import type { Access } from "@/lib/access";

/*
 * Biblioteca de media (PRD M08 FR-08-01..06, ING-01, ADR-0038): ativos finais por cliente com versões, envio com progresso
 * e retentativa, links temporários, lixo e órfãos. Só com media.read; cada ação volta a ser verificada no servidor.
 * ?asset=<id> abre esse ativo (resultado da pesquisa global, W10/ADR-0054); o servidor volta a verificar o acesso.
 */
function Library({ access }: { access: Access }) {
  const sp = useSearchParams(); const router = useRouter(); const path = usePathname();
  const setAsset = useCallback((id: string | null) => {
    const p = new URLSearchParams(window.location.search);
    if (id) p.set("asset", id); else p.delete("asset");
    if (p.get("asset") === sp.get("asset")) return;
    router.replace(`${path}${p.size ? `?${p}` : ""}`, { scroll: false });
  }, [path, router, sp]);
  return <MediaLibraryView access={access} asset={sp.get("asset")} onAsset={setAsset} />;
}

export default function BibliotecaPage() {
  return (
    <Suspense fallback={<Skeleton className="h-40 w-full" />}>
      <WorkspaceGate need="media.read">
        {(access) => <FlagGate flag="media.library" ws={access.ws}><Library access={access} /></FlagGate>}
      </WorkspaceGate>
    </Suspense>
  );
}
