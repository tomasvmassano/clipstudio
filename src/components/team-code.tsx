"use client";

import { useState } from "react";
import { KeyRoundIcon, LogOutIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useSession } from "@/components/session-provider";

/** Diálogo único do código de equipa (montado no AppShell). */
export function TeamCodeDialog() {
  const { signIn, dialogOpen, setDialogOpen } = useSession();
  const [code, setCode] = useState("");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Entrar com o código de equipa</DialogTitle>
          <DialogDescription>Sem código podes ler os guiões e usar o teleprompter. Com código podes validar, editar e rejeitar.</DialogDescription>
        </DialogHeader>
        <form
          className="flex flex-col gap-3"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setErr("");
            const ok = await signIn(code);
            setBusy(false);
            if (ok) { setDialogOpen(false); setCode(""); }
            else setErr("Código inválido. Confirma com o Tomás.");
          }}
        >
          <Input id="team-code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Cola aqui o código" autoFocus />
          {err && <p className="text-sm text-destructive">{err}</p>}
          <DialogFooter>
            <Button type="submit" disabled={busy || !code.trim()}>Entrar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Botão de sessão para as páginas: abre o diálogo, ou mostra quem está ligado e permite sair. */
export function TeamCode() {
  const { session, ready, signOut, setDialogOpen } = useSession();
  if (!ready) return null;
  if (session) {
    return (
      <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={signOut} title="Sair">
        <LogOutIcon /> {session.label ?? session.role}
      </Button>
    );
  }
  return (
    <Button size="sm" variant="outline" onClick={() => setDialogOpen(true)}>
      <KeyRoundIcon /> Código de equipa
    </Button>
  );
}
