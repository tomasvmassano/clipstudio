"use client";

import { useEffect } from "react";
import { useSession } from "@/components/session-provider";
import { useFlags } from "@/lib/flags";
import { pingPresence } from "@/lib/ops";

/**
 * Sinal de vida da presença (OPS-02, OPS-10): com a flag ops.team_presence ligada e uma conta pessoal, a app aberta num
 * cliente avisa o servidor a cada minuto, só com o separador visível. "Ativo" só é guardado se a pessoa o aceitou
 * (o servidor ignora sem consentimento). Não mexe em tarefas nem conta horas.
 */
export function PresenceBeacon() {
  const { mode, wsRequested, can } = useSession();
  const flags = useFlags(wsRequested, null, mode === "user" && !!wsRequested);
  const on = mode === "user" && !!wsRequested && !!flags?.has("ops.team_presence") && can("tasks.read");

  useEffect(() => {
    if (!on || !wsRequested) return;
    let input = false;
    const mark = () => { input = true; };
    const events = ["pointerdown", "keydown", "wheel", "touchstart"] as const;
    events.forEach((e) => window.addEventListener(e, mark, { passive: true }));
    const tick = () => {
      if (document.visibilityState !== "visible") return;
      const active = input; input = false;
      // falhar o sinal não é erro para a pessoa: o próximo minuto volta a tentar e o estado expira sozinho
      pingPresence(wsRequested, active).catch(() => undefined);
    };
    tick();
    const id = setInterval(tick, 60_000);
    const vis = () => { if (document.visibilityState === "visible") tick(); };
    document.addEventListener("visibilitychange", vis);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", vis);
      events.forEach((e) => window.removeEventListener(e, mark));
    };
  }, [on, wsRequested]);
  return null;
}
