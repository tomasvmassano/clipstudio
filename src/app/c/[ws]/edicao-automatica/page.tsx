"use client";

import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { AutoEditView } from "@/components/editor/auto-edit";

/*
 * Edição automática (EDL-01, ING-03, ADR-0048): da sessão gravada (duas câmaras no R2) às versões 1 dos documentos de
 * edição, uma por hook de cada guião; depois rever no editor e exportar. Pedir exige edit.timeline (servidor decide).
 */
export default function EdicaoAutomaticaPage() {
  return (
    <WorkspaceGate need="media.read">
      {(access) => <FlagGate flag="edit.studio" ws={access.ws}><AutoEditView access={access} /></FlagGate>}
    </WorkspaceGate>
  );
}
