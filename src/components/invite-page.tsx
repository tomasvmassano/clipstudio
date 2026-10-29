"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { CheckIcon, Loader2Icon, XIcon } from "lucide-react";
import { LogoIcon } from "@/components/logo";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { useSession } from "@/components/session-provider";
import { friendlyError, ROLE_LABEL } from "@/lib/access";
import { AGENCY_ROLE_LABEL } from "@/lib/team";
import { supabase } from "@/lib/supabase";

type Preview = {
  status: "pending" | "expired" | "declined" | "accepted" | "revoked" | "invalid";
  email?: string; target?: string; workspace_id?: string | null; kind?: "agency" | "workspace"; role?: string; inviter?: string; expires_at?: string;
};

/** Página do link do convite (FR-13-01): ver, aceitar ou recusar. Funciona sem sessão; aceitar exige entrar com o email do convite. */
export function InvitePage() {
  const params = useSearchParams();
  const router = useRouter();
  const token = params.get("t") ?? "";
  const { mode, email, refresh, signOut } = useSession();
  const [inv, setInv] = useState<Preview | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState<"" | "accept" | "decline">("");

  useEffect(() => {
    let alive = true;
    supabase().rpc("invitation_preview", { p_token: token }).then(({ data, error }) => {
      if (!alive) return;
      if (error) setErr(friendlyError(error.message));
      else setInv(data as Preview);
    });
    return () => { alive = false; };
  }, [token]);

  const dest = inv?.workspace_id ? `/c/${inv.workspace_id}` : "/";
  const role = inv?.role ? (ROLE_LABEL[inv.role] ?? AGENCY_ROLE_LABEL[inv.role] ?? inv.role) : "";
  const sameEmail = !!email && !!inv?.email && email.toLowerCase() === inv.email.toLowerCase();
  const loginHref = `/login?email=${encodeURIComponent(inv?.email ?? "")}&next=${encodeURIComponent(`/convite?t=${token}`)}`;

  async function accept() {
    setBusy("accept"); setErr("");
    try {
      const { error } = await supabase().rpc("accept_invitations");
      if (error) throw new Error(friendlyError(error.message));
      await refresh();
      router.replace(dest);
    } catch (e) { setErr((e as Error).message); setBusy(""); }
  }
  async function decline() {
    setBusy("decline"); setErr("");
    const { data, error } = await supabase().rpc("invitation_decline", { p_token: token });
    if (error) setErr(friendlyError(error.message));
    else setInv((p) => (p ? { ...p, status: data as Preview["status"] } : p));
    setBusy("");
  }

  return (
    <main className="mx-auto flex min-h-svh w-full max-w-md flex-col justify-center gap-6 px-6 py-10">
      <div className="flex items-center gap-2 font-medium"><LogoIcon className="size-5" /> ClipStudio</div>
      {!inv && !err && <p className="flex items-center gap-2 text-muted-foreground"><Loader2Icon className="size-4 animate-spin" /> A abrir o convite…</p>}
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      {inv?.status === "invalid" && (
        <Box title="Link inválido">Este link não corresponde a nenhum convite. Pode ter sido substituído por um envio mais recente: procura o último email ou pede a quem te convidou para reenviar.</Box>
      )}
      {inv && inv.status !== "invalid" && (
        <>
          <div className="flex flex-col gap-2">
            <h1 className="font-heading text-2xl font-bold">Convite para {inv.target}</h1>
            <p className="text-muted-foreground">
              {inv.inviter ?? "A equipa"} convidou <b className="text-foreground">{inv.email}</b> para {inv.kind === "agency" ? "a equipa da agência" : "este cliente"}, como {role}.
            </p>
          </div>
          {inv.status === "pending" && (
            <div className="flex flex-col gap-3">
              {mode === "loading" ? null : mode === "user" && sameEmail ? (
                <Button onClick={accept} disabled={!!busy}>{busy === "accept" ? <Loader2Icon className="animate-spin" /> : <CheckIcon />} Aceitar e entrar</Button>
              ) : mode === "user" ? (
                <Alert><AlertDescription>
                  Estás com a conta {email}. Este convite é para {inv.email}.{" "}
                  <button type="button" className="underline" onClick={async () => { await signOut(); router.replace(loginHref); }}>Sair e entrar com {inv.email}</button>
                </AlertDescription></Alert>
              ) : (
                <Button onClick={() => router.push(loginHref)} disabled={!!busy}><CheckIcon /> Aceitar: entrar ou criar conta com {inv.email}</Button>
              )}
              <Button variant="outline" onClick={decline} disabled={!!busy}>{busy === "decline" ? <Loader2Icon className="animate-spin" /> : <XIcon />} Recusar convite</Button>
              <p className="text-xs text-muted-foreground">Válido até {new Date(inv.expires_at!).toLocaleDateString("pt-PT", { day: "numeric", month: "long" })}.</p>
            </div>
          )}
          {inv.status === "accepted" && (
            <Box title="Convite aceite">Já tens acesso.{" "}{mode === "user" ? <a className="underline" href={dest}>Abrir</a> : <a className="underline" href={loginHref}>Entrar</a>}</Box>
          )}
          {inv.status === "declined" && <Box title="Convite recusado">Recusaste este convite. Se mudares de ideias, pede a quem te convidou para enviar um novo.</Box>}
          {inv.status === "expired" && <Box title="Convite expirado">Este convite já não é válido. Pede a {inv.inviter ?? "quem te convidou"} para o reenviar.</Box>}
          {inv.status === "revoked" && <Box title="Convite cancelado">Quem te convidou cancelou este convite.</Box>}
        </>
      )}
    </main>
  );
}

function Box({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border p-4">
      <h1 className="font-heading text-xl font-bold">{title}</h1>
      <p className="text-muted-foreground">{children}</p>
    </div>
  );
}
