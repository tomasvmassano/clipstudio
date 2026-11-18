"use client";

import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { EpisodeEditorView } from "@/components/editor/episode-editor";

/*
 * Edição do episódio completo (POD-01..06, CHG-013, ADR-0087): de uma ou várias câmaras na Biblioteca (R2) a um master limpo,
 * com áudio, legendas, capítulos e notas. Pedir exige edit.episode; descarregar exige media.download (o servidor decide).
 */
export default function EpisodiosPage() {
  return (
    <WorkspaceGate need="media.read">
      {(access) => (
        <FlagGate flag="edit.studio" ws={access.ws}>
          <FlagGate flag="edit.episode" ws={access.ws}><EpisodeEditorView access={access} /></FlagGate>
        </FlagGate>
      )}
    </WorkspaceGate>
  );
}
