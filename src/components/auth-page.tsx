"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeftIcon, AtSignIcon, KeyRoundIcon, Loader2Icon, LockIcon } from "lucide-react";
import { GoogleIcon } from "@/components/icons/google-icon";
import { LogoIcon } from "@/components/logo";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { AuthDivider } from "@/components/auth-divider";
import { FloatingPaths } from "@/components/floating-paths";
import { useSession } from "@/components/session-provider";
import { SUPABASE_KEY, SUPABASE_URL, supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";
import { safeNext } from "@/lib/safe-next";

/** Bloco efferd auth-5 adaptado: email primeiro, depois palavra-passe (entrar ou criar), Google só se estiver ativo. */
type Step = "email" | "password" | "signup" | "code" | "sent" | "mfa" | "reset_sent";

function authError(msg: string): string {
	const m = msg.toLowerCase();
	if (m.includes("invalid login credentials")) return "Email ou palavra-passe errados.";
	if (m.includes("email not confirmed")) return "Ainda não confirmaste o email. Abre o link mais recente que te enviámos.";
	if (m.includes("user already registered")) return "Já existe uma conta com este email. Entra com a palavra-passe.";
	if (m.includes("password should be")) return "A palavra-passe tem de ter pelo menos 8 caracteres.";
	if (m.includes("rate limit") || m.includes("too many")) return "Demasiadas tentativas. Espera um minuto e tenta de novo.";
	if (m.includes("code verifier")) return "Abre o link no mesmo browser onde criaste a conta ou começaste a entrar.";
	if (m.includes("expired") || m.includes("invalid") || m === "link_invalido")
		return "Este link já foi usado ou expirou. Se já confirmaste o email, entra com a palavra-passe.";
	return friendlyError(msg);
}

export function AuthPage() {
	const params = useSearchParams();
	const router = useRouter();
	const { mode, signInCode, mfaRequired, refresh, signOut } = useSession();
	const next = useMemo(() => safeNext(params.get("next")), [params]);
	const [step, setStep] = useState<Step>("email");
	const [email, setEmail] = useState(() => params.get("email") ?? "");
	const [password, setPassword] = useState("");
	const [code, setCode] = useState("");
	const [otp, setOtp] = useState("");
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState(() => (params.get("erro") ? authError(params.get("erro")!) : ""));
	const [google, setGoogle] = useState(false);

	// Erros que o Supabase põe no #hash (o servidor não os vê): mostra e limpa o URL.
	useEffect(() => {
		if (!location.hash) return;
		const err = new URLSearchParams(location.hash.slice(1)).get("error_description");
		history.replaceState(null, "", location.pathname + location.search);
		if (err) queueMicrotask(() => setError(authError(err)));
	}, []);

	useEffect(() => {
		// com MFA ativo a sessão só serve depois do código (o servidor recusa tudo até lá)
		if (mode === "user" && mfaRequired) { queueMicrotask(() => setStep("mfa")); return; }
		if (mode === "user" || mode === "code") router.replace(next);
	}, [mode, mfaRequired, next, router]);

	// Nada de botões decorativos: o Google só aparece quando o fornecedor está ligado no Supabase.
	useEffect(() => {
		let alive = true;
		fetch(`${SUPABASE_URL}/auth/v1/settings`, { headers: { apikey: SUPABASE_KEY } })
			.then((r) => (r.ok ? r.json() : null))
			.then((s) => { if (alive) setGoogle(!!s?.external?.google); })
			.catch(() => undefined);
		return () => { alive = false; };
	}, []);

	const redirectTo = () => `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`;
	const go = (s: Step) => { setStep(s); setError(""); setPassword(""); };

	const submit = async (e: React.FormEvent) => {
		e.preventDefault();
		setError("");
		if (step === "email") { go("password"); return; }
		setBusy(true);
		try {
			const sb = supabase();
			if (step === "password") {
				const { error } = await sb.auth.signInWithPassword({ email: email.trim(), password });
				if (error) setError(authError(error.message));
			} else if (step === "signup") {
				if (password.length < 8) { setError("A palavra-passe tem de ter pelo menos 8 caracteres."); return; }
				const { data, error } = await sb.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: redirectTo() } });
				if (error) setError(authError(error.message));
				else if (!data.session) setStep("sent");
			} else if (step === "code") {
				if (!(await signInCode(code))) setError("Código inválido. Confirma com quem gere a equipa.");
			} else if (step === "mfa") {
				const { data: f, error: fe } = await sb.auth.mfa.listFactors();
				const factor = f?.totp?.find((x) => x.status === "verified");
				if (fe || !factor) { setError("Não encontrei a app de autenticação desta conta. Sai e entra de novo."); return; }
				const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: factor.id, code: otp.replace(/\s/g, "") });
				if (error) setError(error.message.toLowerCase().includes("invalid") ? "Código errado ou expirado. Usa o código que está agora na app." : authError(error.message));
				else await refresh();
			}
		} catch (err) {
			setError(authError((err as Error).message));
		} finally {
			setBusy(false);
		}
	};

	const forgot = async () => {
		if (!email.trim()) { setError("Escreve o teu email primeiro."); return; }
		setBusy(true); setError("");
		const { error } = await supabase().auth.resetPasswordForEmail(email.trim(), {
			redirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent("/perfil?recuperar=1")}`,
		});
		setBusy(false);
		if (error) setError(authError(error.message)); else setStep("reset_sent");
	};

	const withGoogle = async () => {
		setBusy(true); setError("");
		const { error } = await supabase().auth.signInWithOAuth({ provider: "google", options: { redirectTo: redirectTo() } });
		if (error) { setError(authError(error.message)); setBusy(false); }
	};

	const title = {
		email: "Entrar no ClipStudio",
		password: "Bem-vindo de volta",
		signup: "Criar conta",
		code: "Código de equipa",
		sent: "Confirma o teu email",
		mfa: "Verificação em dois passos",
		reset_sent: "Vê o teu email",
	}[step];
	const subtitle = {
		email: "Cada pessoa entra com a sua conta e vê só os clientes a que tem acesso.",
		password: email,
		signup: `Usa o email do convite (${email}). Sem convite, a conta fica sem clientes.`,
		code: "Acesso de transição para a equipa do cliente, até cada pessoa ter a sua conta.",
		sent: `Enviámos um link para ${email}. Abre-o uma vez, neste browser. Depois disso entras só com a palavra-passe.`,
		mfa: "Escreve o código de 6 dígitos da tua app de autenticação.",
		reset_sent: `Se ${email} tiver conta, recebe um link para escolher uma palavra-passe nova. Abre-o neste browser.`,
	}[step];

	return (
		<main className="relative w-full md:h-screen md:overflow-hidden lg:grid lg:grid-cols-2">
			<div className="relative hidden h-full flex-col border-r bg-secondary p-10 lg:flex dark:bg-secondary/20">
				<div className="absolute inset-0 bg-linear-to-b from-transparent via-transparent to-background" />
				<div className="z-10 mr-auto flex items-center gap-2 font-medium"><LogoIcon className="size-5" /> ClipStudio</div>
				<div className="z-10 mt-auto space-y-2">
					<p className="text-xl">Das fontes à publicação: guiões, gravação, revisão e desempenho de cada cliente num só sítio.</p>
					<p className="font-mono text-sm text-muted-foreground">Fontes → Guiões → Aprovação → Gravação → Revisão → Publicação → Análise</p>
				</div>
				<div className="absolute inset-0">
					<FloatingPaths position={1} />
					<FloatingPaths position={-1} />
				</div>
			</div>

			<div className="relative flex min-h-screen flex-col justify-center px-8">
				<div aria-hidden className="absolute inset-0 isolate -z-10 opacity-60 contain-strict">
					<div className="absolute top-0 right-0 h-320 w-140 -translate-y-87.5 rounded-full bg-[radial-gradient(68.54%_68.72%_at_55.02%_31.46%,--theme(--color-foreground/.06)_0,hsla(0,0%,55%,.02)_50%,--theme(--color-foreground/.01)_80%)]" />
					<div className="absolute top-0 right-0 h-320 w-60 rounded-full bg-[radial-gradient(50%_50%_at_50%_50%,--theme(--color-foreground/.04)_0,--theme(--color-foreground/.01)_80%,transparent_100%)] [translate:5%_-50%]" />
					<div className="absolute top-0 right-0 h-320 w-60 -translate-y-87.5 rounded-full bg-[radial-gradient(50%_50%_at_50%_50%,--theme(--color-foreground/.04)_0,--theme(--color-foreground/.01)_80%,transparent_100%)]" />
				</div>

				{step !== "email" && (
					<Button className="absolute top-7 left-5" variant="ghost" onClick={() => go("email")}>
						<ArrowLeftIcon data-icon="inline-start" /> Voltar
					</Button>
				)}

				<div className="mx-auto w-full space-y-4 sm:w-sm">
					<div className="flex items-center gap-2 font-medium lg:hidden"><LogoIcon className="size-5" /> ClipStudio</div>
					<div className="flex flex-col space-y-1">
						<h1 className="font-bold font-heading text-2xl tracking-wide">{title}</h1>
						<p className="break-words text-base text-muted-foreground">{subtitle}</p>
					</div>

					{error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

					{step === "email" && google && (
						<>
							<Button className="w-full" disabled={busy} onClick={withGoogle}>
								<GoogleIcon data-icon="inline-start" /> Continuar com Google
							</Button>
							<AuthDivider>OU</AuthDivider>
						</>
					)}

					{step === "sent" || step === "reset_sent" ? (
						<Button className="w-full" variant="outline" onClick={() => go("password")}>{step === "sent" ? "Já confirmei, entrar" : "Voltar a entrar"}</Button>
					) : (
						<form className="space-y-2" onSubmit={submit}>
							{step === "email" && (
								<>
									<label className="text-start text-muted-foreground text-xs" htmlFor="email">O teu email de trabalho</label>
									<InputGroup>
										<InputGroupInput id="email" placeholder="nome@exemplo.com" type="email" required autoComplete="email" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} />
										<InputGroupAddon align="inline-start"><AtSignIcon /></InputGroupAddon>
									</InputGroup>
								</>
							)}
							{(step === "password" || step === "signup") && (
								<>
									<label className="text-start text-muted-foreground text-xs" htmlFor="password">
										{step === "signup" ? "Escolhe uma palavra-passe (mínimo 8 caracteres)" : "Palavra-passe"}
									</label>
									<InputGroup>
										<InputGroupInput
											id="password" type="password" required autoFocus minLength={step === "signup" ? 8 : undefined}
											autoComplete={step === "signup" ? "new-password" : "current-password"}
											value={password} onChange={(e) => setPassword(e.target.value)}
										/>
										<InputGroupAddon align="inline-start"><LockIcon /></InputGroupAddon>
									</InputGroup>
								</>
							)}
							{step === "code" && (
								<>
									<label className="text-start text-muted-foreground text-xs" htmlFor="code">Código</label>
									<InputGroup>
										<InputGroupInput id="code" autoFocus autoComplete="off" placeholder="Cola aqui o código" value={code} onChange={(e) => setCode(e.target.value)} />
										<InputGroupAddon align="inline-start"><KeyRoundIcon /></InputGroupAddon>
									</InputGroup>
								</>
							)}
							{step === "mfa" && (
								<>
									<label className="text-start text-muted-foreground text-xs" htmlFor="otp">Código da app</label>
									<InputGroup>
										<InputGroupInput id="otp" autoFocus inputMode="numeric" autoComplete="one-time-code" placeholder="123456" maxLength={8} value={otp} onChange={(e) => setOtp(e.target.value)} />
										<InputGroupAddon align="inline-start"><KeyRoundIcon /></InputGroupAddon>
									</InputGroup>
								</>
							)}
							<Button className="w-full" type="submit" disabled={busy || (step === "email" ? !email.trim() : step === "code" ? !code.trim() : step === "mfa" ? otp.replace(/\s/g, "").length < 6 : !password)}>
								{busy && <Loader2Icon className="animate-spin" data-icon="inline-start" />}
								{{ email: "Continuar com email", password: "Entrar", signup: "Criar conta", code: "Entrar com código", mfa: "Verificar" }[step]}
							</Button>
						</form>
					)}

					<div className="flex flex-col gap-1 text-sm text-muted-foreground">
						{step === "password" && (
							<>
								<button type="button" className="text-start underline underline-offset-4 hover:text-primary" disabled={busy} onClick={forgot}>
									Esqueci-me da palavra-passe
								</button>
								<button type="button" className="text-start underline underline-offset-4 hover:text-primary" onClick={() => go("signup")}>
									Ainda não tenho conta, criar uma
								</button>
							</>
						)}
						{step === "mfa" && (
							<button type="button" className="text-start underline underline-offset-4 hover:text-primary" onClick={() => void signOut()}>
								Sair e entrar com outra conta
							</button>
						)}
						{step === "signup" && (
							<button type="button" className="text-start underline underline-offset-4 hover:text-primary" onClick={() => go("password")}>
								Já tenho conta, entrar
							</button>
						)}
						{step === "email" && (
							<button type="button" className="text-start underline underline-offset-4 hover:text-primary" onClick={() => go("code")}>
								Tenho um código de equipa
							</button>
						)}
					</div>
				</div>
			</div>
		</main>
	);
}
