"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { FlagGate } from "@/components/flag-gate";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { WsNotifSettingsPage } from "@/components/notif/ws-notif-settings";

/** Definições → Notificações (FR-15-05, flag notifications.prefs, ADR-0040). */
export default function NotificacoesPage() {
  const { mode } = useSession();
  return (
    <WorkspaceGate need="team.read">
      {(access) => mode === "code"
        ? <Alert><AlertDescription>As definições de notificações só abrem com conta própria.</AlertDescription></Alert>
        : <FlagGate flag="notifications.prefs" ws={access.ws}><WsNotifSettingsPage ws={access.ws} /></FlagGate>}
    </WorkspaceGate>
  );
}
