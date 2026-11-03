"use client";

import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { MediaLibraryView } from "@/components/media/media-library";

/*
 * Biblioteca de media (PRD M08 FR-08-01..06, ING-01, ADR-0038): ativos finais por cliente com versões, envio com progresso
 * e retentativa, links temporários, lixo e órfãos. Só com media.read; cada ação volta a ser verificada no servidor.
 */
export default function BibliotecaPage() {
  return (
    <WorkspaceGate need="media.read">
      {(access) => <FlagGate flag="media.library" ws={access.ws}><MediaLibraryView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}
