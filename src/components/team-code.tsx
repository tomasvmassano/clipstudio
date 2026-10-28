"use client";

import { useState } from "react";
import { KeyRoundIcon, LogOutIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { useSession } from "@/components/session-provider";

/** Botão de sessão: pede o código de equipa, ou mostra quem está ligado. */
export function TeamCode() {
  const { session, ready, signIn, signOut } = useSession();
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);

  if (!ready) return null;
  if (session) {
    return (
      <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={signOut} title={session.label ?? session.role}>
        <LogOutIcon /> {session.label ?? session.role}
      </Button>
    );
  }
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <KeyRoundIcon /> Código de equipa
      </DialogTrigger>
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
            if (ok) setOpen(false);
            else setErr("Código inválido. Confirma com o Tomás.");
          }}
        >
          <Input id="team-code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Cola aqui o código" autoFocus />
          {err && <p className="text-sm text-destructive">{err}</p>}
          <DialogFooter>
            <Button type="submit" disabled={busy || !code.trim()}>
              Entrar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
