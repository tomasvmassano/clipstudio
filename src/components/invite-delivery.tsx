"use client";

import { useState } from "react";
import { CheckIcon, CopyIcon, Loader2Icon, SendIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { sendInvite, type InviteSend } from "@/lib/team";

/** O que aconteceu ao envio: email enviado, ou link para copiar quando o email não está ligado (ou falhou). */
export function InviteDeliveryNote({ result }: { result: InviteSend }) {
  const [copied, setCopied] = useState(false);
  if (result.sent) return <p className="text-sm text-emerald-600 dark:text-emerald-400" role="status">Email enviado para {result.email}.</p>;
  return (
    <div className="flex flex-col gap-2 rounded-md border p-3" role="status">
      <p className="text-sm">
        {result.error ? `${result.error} ` : "O envio por email ainda não está ligado. "}
        Copia o link e manda-o a {result.email}: só funciona com esse email e substitui links anteriores.
      </p>
      {result.link && (
        <div className="flex gap-2">
          <Input readOnly value={result.link} aria-label="Link do convite" onFocus={(e) => e.currentTarget.select()} />
          <Button
            type="button" variant="outline"
            onClick={async () => {
              try { await navigator.clipboard.writeText(result.link!); setCopied(true); setTimeout(() => setCopied(false), 2000); } catch { /* o campo fica selecionável */ }
            }}
          >
            {copied ? <CheckIcon /> : <CopyIcon />} {copied ? "Copiado" : "Copiar"}
          </Button>
        </div>
      )}
    </div>
  );
}

/** Botão Reenviar para um convite da lista. */
export function ResendInvite({ id, email, onDone }: { id: string; email: string; onDone: (r: InviteSend) => void }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <span className="inline-flex flex-col items-end">
      <Button
        size="sm" variant="ghost" disabled={busy} aria-label={`Reenviar convite a ${email}`}
        onClick={async () => {
          setBusy(true); setErr("");
          try { onDone(await sendInvite(id)); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
        }}
      >
        {busy ? <Loader2Icon className="animate-spin" /> : <SendIcon />} Reenviar
      </Button>
      {err && <span className="max-w-56 text-right text-xs text-destructive" role="alert">{err}</span>}
    </span>
  );
}
