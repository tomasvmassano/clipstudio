"use client";

import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { ClipMinerView } from "@/components/editor/clip-miner";

/*
 * Cortes de vídeos longos (Clip Miner, CLIP-01..07, ADR-0063): de um vídeo longo na Biblioteca (R2) a 5-10 documentos de
 * edição de cortes verticais; rever no editor, exportar e decidir na revisão em lote. Pedir exige clips.mine (servidor decide).
 */
export default function CortesPage() {
  return (
    <WorkspaceGate need="media.read">
      {(access) => (
        <FlagGate flag="edit.studio" ws={access.ws}>
          <FlagGate flag="clips.miner" ws={access.ws}><ClipMinerView access={access} /></FlagGate>
        </FlagGate>
      )}
    </WorkspaceGate>
  );
}
