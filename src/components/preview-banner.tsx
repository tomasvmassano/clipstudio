"use client";

import { useState } from "react";
import { EyeIcon, Loader2Icon, XIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL } from "@/lib/access";
import { untilLabel } from "@/lib/preview";

/** Faixa fixa enquanto se navega como outro papel ou pessoa (BIZ-07). Sair está sempre à mão. */
export function PreviewBanner() {
  const { preview, ws, endPreview } = useSession();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  if (!preview || !ws) return null;
  const who = preview.kind === "role" ? `papel ${ROLE_LABEL[preview.label] ?? preview.label}`
    : `${preview.label}${preview.role ? ` (${ROLE_LABEL[preview.role] ?? preview.role})` : ""}`;
  return (
    <div role="status" aria-live="polite" data-preview-banner
      className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-amber-500/50 bg-amber-500/15 px-4 py-2 text-sm">
      <EyeIcon className="size-4 shrink-0" aria-hidden />
      <span className="min-w-0 flex-1">
        Pré-visualização como <b>{who}</b> em {ws.name}. Só leitura: vês o que esta pessoa vê e nada se grava. Termina às {untilLabel(preview.expires_at, ws.timezone)}.
        {err && <span className="ml-2 text-destructive">{err}</span>}
      </span>
      <Button size="sm" variant="outline" disabled={busy}
        onClick={async () => { setBusy(true); setErr(""); try { await endPreview(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); } }}>
        {busy ? <Loader2Icon className="animate-spin" /> : <XIcon />} Sair da pré-visualização
      </Button>
    </div>
  );
}
