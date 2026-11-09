"use client";

import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { AutoEditView } from "@/components/editor/auto-edit";
import { ScriptPackagesSection } from "@/components/editor/script-packages";
import { useSession } from "@/components/session-provider";
import type { Access } from "@/lib/access";
import { useFlags } from "@/lib/flags";

/*
 * Edição automática (EDL-01, ING-03, ADR-0048): da sessão gravada (duas câmaras no R2) às versões 1 dos documentos de
 * edição, uma por hook de cada guião; depois rever no editor e exportar. Pedir exige edit.timeline (servidor decide).
 * Pacote por guião (STU-03, ADR-0070): secção extra só com a flag edit.package_script; sem ela a página fica como antes.
 */
export default function EdicaoAutomaticaPage() {
  return (
    <WorkspaceGate need="media.read">
      {(access) => (
        <FlagGate flag="edit.studio" ws={access.ws}>
          <div className="flex min-w-0 flex-col gap-6">
            <AutoEditView access={access} />
            <ScriptPackagesIfOn access={access} />
          </div>
        </FlagGate>
      )}
    </WorkspaceGate>
  );
}

function ScriptPackagesIfOn({ access }: { access: Access }) {
  const { mode } = useSession();
  const flags = useFlags(access.ws, access.token ?? null, mode !== "loading");
  if (!flags?.has("edit.package_script")) return null;
  return <ScriptPackagesSection access={access} />;
}
