"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { KeyRoundIcon, Loader2Icon } from "lucide-react";
import { LogoIcon } from "@/components/logo";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useSession } from "@/components/session-provider";
import { SUPABASE_KEY, SUPABASE_URL, supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";
import { safeNext } from "@/lib/safe-next";


function authError(msg: string): string {
  const m = msg.toLowerCase();
  if (m.includes("invalid login credentials")) return "Email ou palavra-passe errados.";
  if (m.includes("email not confirmed")) return "Ainda não confirmaste o email. Abre o link que te enviámos.";
  if (m.includes("user already registered")) return "Já existe uma conta com este email. Entra em vez de criar.";
  if (m.includes("password should be")) return "A palavra-passe tem de ter pelo menos 8 caracteres.";
  if (m.includes("rate limit") || m.includes("too many")) return "Demasiadas tentativas. Espera um minuto e tenta de novo.";
  if (m.includes("code verifier")) return "Abre o link no mesmo browser onde criaste a conta ou começaste a entrar.";
  if (m === "link_invalido") return "O link não é válido ou já foi usado. Entra ou pede outro.";
  return friendlyError(msg);
}

export default function LoginPage() {
  const params = useSearchParams();
  const router = useRouter();
  const next = safeNext(params.get("next"), typeof location === "undefined" ? undefined : location.origin);
  const { mode, signInCode } = useSession();
  const [tab, setTab] = useState<"entrar" | "criar" | "codigo">("entrar");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(params.get("erro") ? authError(params.get("erro")!) : "");
  const [notice, setNotice] = useState("");
  const [google, setGoogle] = useState<boolean | null>(null);

  // Já tem sessão: segue para onde ia.
  useEffect(() => { if (mode === "user" || mode === "code") router.replace(next); }, [mode, next, router]);

  // O botão Google só aparece quando o fornecedor está mesmo ativo no Supabase (nada de botões decorativos).
  useEffect(() => {
    let alive = true;
    fetch(`${SUPABASE_URL}/auth/v1/settings`, { headers: { apikey: SUPABASE_KEY } })
      .then((r) => (r.ok ? r.json() : null))
      .then((s) => { if (alive) setGoogle(!!s?.external?.google); })
      .catch(() => { if (alive) setGoogle(false); });
    return () => { alive = false; };
  }, []);

  const redirectTo = () => `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setError(""); setNotice("");
    try {
      if (tab === "codigo") {
        const ok = await signInCode(code);
        if (!ok) setError("Código inválido. Confirma com quem gere a equipa.");
        return;
      }
      const sb = supabase();
      if (tab === "entrar") {
        const { error } = await sb.auth.signInWithPassword({ email: email.trim(), password });
        if (error) setError(authError(error.message));
      } else {
        if (password.length < 8) { setError("A palavra-passe tem de ter pelo menos 8 caracteres."); return; }
        const { data, error } = await sb.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: redirectTo() } });
        if (error) setError(authError(error.message));
        else if (!data.session) setNotice(`Enviámos um link de confirmação para ${email.trim()}. Abre-o neste dispositivo para entrares.`);
      }
    } catch (err) {
      setError(authError((err as Error).message));
    } finally {
      setBusy(false);
    }
  };

  const withGoogle = async () => {
    setBusy(true); setError("");
    const { error } = await supabase().auth.signInWithOAuth({ provider: "google", options: { redirectTo: redirectTo() } });
    if (error) { setError(authError(error.message)); setBusy(false); }
  };

  return (
    <Card className="w-full max-w-sm">
      <CardHeader className="items-center text-center">
        <LogoIcon className="mx-auto size-8" />
        <CardTitle className="text-xl">ClipStudio</CardTitle>
        <CardDescription>Cada pessoa entra com a sua conta. Vês só os clientes a que tens acesso.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <Tabs value={tab} onValueChange={(v) => { setTab(v as typeof tab); setError(""); setNotice(""); }}>
          <TabsList className="w-full">
            <TabsTrigger value="entrar">Entrar</TabsTrigger>
            <TabsTrigger value="criar">Criar conta</TabsTrigger>
            <TabsTrigger value="codigo">Código</TabsTrigger>
          </TabsList>
        </Tabs>

        {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}
        {notice && <Alert><AlertDescription>{notice}</AlertDescription></Alert>}

        <form className="flex flex-col gap-3" onSubmit={submit}>
          {tab === "codigo" ? (
            <>
              <label className="text-sm font-medium" htmlFor="code">Código de equipa</label>
              <Input id="code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Cola aqui o código" autoComplete="off" />
              <p className="text-xs text-muted-foreground">Acesso de transição para a equipa do cliente, até cada pessoa ter a sua conta.</p>
            </>
          ) : (
            <>
              <label className="text-sm font-medium" htmlFor="email">Email</label>
              <Input id="email" type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <label className="text-sm font-medium" htmlFor="password">Palavra-passe</label>
              <Input
                id="password" type="password" required minLength={tab === "criar" ? 8 : undefined}
                autoComplete={tab === "criar" ? "new-password" : "current-password"}
                value={password} onChange={(e) => setPassword(e.target.value)}
              />
              {tab === "criar" && <p className="text-xs text-muted-foreground">Usa o email do convite. Sem convite, a conta fica criada mas sem acesso a clientes.</p>}
            </>
          )}
          <Button type="submit" disabled={busy || (tab === "codigo" ? !code.trim() : !email.trim() || !password)}>
            {busy && <Loader2Icon className="animate-spin" />}
            {tab === "entrar" ? "Entrar" : tab === "criar" ? "Criar conta" : <><KeyRoundIcon /> Entrar com código</>}
          </Button>
        </form>

        {tab !== "codigo" && google && (
          <>
            <div className="flex items-center gap-3 text-xs text-muted-foreground"><Separator className="flex-1" />ou<Separator className="flex-1" /></div>
            <Button variant="outline" disabled={busy} onClick={withGoogle}>Continuar com Google</Button>
          </>
        )}

        <p className="text-center text-xs text-muted-foreground">
          Problemas a entrar? Fala com quem gere a equipa. <Link className="underline" href="/legacy/index.html">Versão antiga</Link>
        </p>
      </CardContent>
    </Card>
  );
}
