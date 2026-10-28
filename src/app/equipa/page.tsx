"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, MailPlusIcon, RotateCwIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL, type Access } from "@/lib/access";
import { fetchTeam, INVITE_ROLES, inviteMember, revokeInvitation, type Team } from "@/lib/team";

const AFF_LABEL = { agency_staff: "Agência", client_staff: "Cliente" } as const;
const fmtDate = (iso: string | null) =>
	iso ? new Date(iso).toLocaleDateString("pt-PT", { day: "2-digit", month: "short", year: "numeric" }) : "—";

export default function EquipaPage() {
	return <WorkspaceGate need="team.read">{(access) => <EquipaView access={access} />}</WorkspaceGate>;
}

function EquipaView({ access }: { access: Access }) {
	const { ws } = useSession();
	const [team, setTeam] = useState<Team | null>(null);
	const [error, setError] = useState("");
	const [attempt, setAttempt] = useState(0);

	useEffect(() => {
		let alive = true;
		fetchTeam(access.ws)
			.then((t) => { if (alive) { setTeam(t); setError(""); } })
			.catch((e: Error) => { if (alive) setError(e.message); });
		return () => { alive = false; };
	}, [access.ws, attempt]);
	const reload = useCallback(() => setAttempt((n) => n + 1), []);

	return (
		<div className="flex flex-col gap-4">
			<div>
				<h1 className="text-2xl font-semibold tracking-tight">Equipa</h1>
				<p className="text-sm text-muted-foreground">
					Quem tem acesso a {ws?.name ?? "este cliente"}. O cargo (editor, clipper…) não dá permissões: o papel é que dá.
				</p>
			</div>

			{error && (
				<Alert variant="destructive">
					<AlertDescription className="flex flex-wrap items-center justify-between gap-2">
						<span>Não consegui carregar a equipa: {error}</span>
						<Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
					</AlertDescription>
				</Alert>
			)}

			{!team ? (
				!error && <Skeleton className="h-64 w-full" />
			) : (
				<>
					{team.can_invite && <InviteCard ws={access.ws} myRole={ws?.role ?? "viewer"} canAgency={team.can_invite_agency} onDone={reload} />}
					<MembersCard team={team} />
					<InvitesCard team={team} onChange={reload} />
				</>
			)}
		</div>
	);
}

function InviteCard({ ws, myRole, canAgency, onDone }: { ws: string; myRole: string; canAgency: boolean; onDone: () => void }) {
	const [email, setEmail] = useState("");
	const [role, setRole] = useState<string>("contributor");
	const [aff, setAff] = useState<"client_staff" | "agency_staff">("client_staff");
	const [busy, setBusy] = useState(false);
	const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

	// A UI só sugere papéis até ao teu; o servidor recusa o resto (acima_do_teto).
	const myRank = INVITE_ROLES.indexOf(myRole as (typeof INVITE_ROLES)[number]);
	const roles = myRank < 0 ? INVITE_ROLES : INVITE_ROLES.slice(0, myRank + 1);
	const items = roles.map((r) => ({ value: r, label: ROLE_LABEL[r] ?? r }));

	return (
		<Card>
			<CardHeader>
				<CardTitle>Convidar</CardTitle>
				<CardDescription>
					O convite fica associado ao email. A pessoa cria conta com esse email, confirma-o e ganha acesso só a este cliente.
					Ainda não enviamos o email automaticamente: avisa a pessoa e manda-lhe o link da app.
				</CardDescription>
			</CardHeader>
			<CardContent>
				<form
					className="flex flex-col gap-3 sm:flex-row sm:items-end"
					onSubmit={async (e) => {
						e.preventDefault();
						setBusy(true); setMsg(null);
						try {
							await inviteMember(ws, email, role, aff);
							setMsg({ ok: true, text: `Convite criado para ${email.trim().toLowerCase()}. Válido 14 dias.` });
							setEmail("");
							onDone();
						} catch (err) {
							setMsg({ ok: false, text: (err as Error).message });
						} finally {
							setBusy(false);
						}
					}}
				>
					<div className="flex flex-1 flex-col gap-1.5">
						<label className="text-sm font-medium" htmlFor="inv-email">Email</label>
						<Input id="inv-email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nome@exemplo.com" />
					</div>
					<div className="flex flex-col gap-1.5">
						<span className="text-sm font-medium" id="inv-role">Papel</span>
						<Select items={items} value={role} onValueChange={(v) => setRole(String(v))}>
							<SelectTrigger aria-labelledby="inv-role" className="min-w-40"><SelectValue /></SelectTrigger>
							<SelectContent>{items.map((i) => <SelectItem key={i.value} value={i.value}>{i.label}</SelectItem>)}</SelectContent>
						</Select>
					</div>
					{canAgency && (
						<div className="flex flex-col gap-1.5">
							<span className="text-sm font-medium" id="inv-aff">Lado</span>
							<Select
								items={[{ value: "client_staff", label: "Equipa do cliente" }, { value: "agency_staff", label: "Equipa da agência" }]}
								value={aff}
								onValueChange={(v) => setAff(v as typeof aff)}
							>
								<SelectTrigger aria-labelledby="inv-aff" className="min-w-44"><SelectValue /></SelectTrigger>
								<SelectContent>
									<SelectItem value="client_staff">Equipa do cliente</SelectItem>
									<SelectItem value="agency_staff">Equipa da agência</SelectItem>
								</SelectContent>
							</Select>
						</div>
					)}
					<Button type="submit" disabled={busy || !email.trim()}>
						{busy ? <Loader2Icon className="animate-spin" /> : <MailPlusIcon />} Convidar
					</Button>
				</form>
				{msg && <p className={`mt-3 text-sm ${msg.ok ? "text-emerald-500" : "text-destructive"}`} role="status">{msg.text}</p>}
			</CardContent>
		</Card>
	);
}

function MembersCard({ team }: { team: Team }) {
	return (
		<Card>
			<CardHeader>
				<CardTitle>Com acesso</CardTitle>
				<CardDescription>{team.members.length} pessoa{team.members.length === 1 ? "" : "s"}</CardDescription>
			</CardHeader>
			<CardContent>
				{team.members.length === 0 ? (
					<p className="text-sm text-muted-foreground">Ainda ninguém entrou com conta própria neste cliente. O dono da agência tem acesso sem aparecer aqui.</p>
				) : (
					<Table>
						<TableHeader>
							<TableRow><TableHead>Email</TableHead><TableHead>Lado</TableHead><TableHead>Papel</TableHead><TableHead>Estado</TableHead><TableHead>Desde</TableHead></TableRow>
						</TableHeader>
						<TableBody>
							{team.members.map((m) => (
								<TableRow key={m.user_id}>
									<TableCell className="font-medium">{m.email}{m.job_title && <span className="ml-2 text-xs text-muted-foreground">{m.job_title}</span>}</TableCell>
									<TableCell>{AFF_LABEL[m.affiliation]}</TableCell>
									<TableCell>{ROLE_LABEL[m.role] ?? m.role}</TableCell>
									<TableCell><Badge variant={m.status === "active" ? "secondary" : "outline"}>{m.status === "active" ? "Ativo" : m.status}</Badge></TableCell>
									<TableCell className="text-muted-foreground">{fmtDate(m.since)}</TableCell>
								</TableRow>
							))}
						</TableBody>
					</Table>
				)}
			</CardContent>
		</Card>
	);
}

function InvitesCard({ team, onChange }: { team: Team; onChange: () => void }) {
	const [busy, setBusy] = useState<string | null>(null);
	const [err, setErr] = useState("");
	if (team.invitations.length === 0) return null;
	return (
		<Card>
			<CardHeader>
				<CardTitle>Convites pendentes</CardTitle>
				<CardDescription>Ficam pendentes até a pessoa confirmar o email.</CardDescription>
			</CardHeader>
			<CardContent>
				{err && <p className="mb-3 text-sm text-destructive">{err}</p>}
				<Table>
					<TableHeader>
						<TableRow><TableHead>Email</TableHead><TableHead>Lado</TableHead><TableHead>Papel</TableHead><TableHead>Expira</TableHead>{team.can_invite && <TableHead className="w-0" />}</TableRow>
					</TableHeader>
					<TableBody>
						{team.invitations.map((i) => (
							<TableRow key={i.id}>
								<TableCell className="font-medium">{i.email}</TableCell>
								<TableCell>{AFF_LABEL[i.affiliation]}</TableCell>
								<TableCell>{ROLE_LABEL[i.role] ?? i.role}</TableCell>
								<TableCell className="text-muted-foreground">{fmtDate(i.expires_at)}</TableCell>
								{team.can_invite && (
									<TableCell>
										<Button
											size="sm" variant="ghost" disabled={busy === i.id} aria-label={`Cancelar convite de ${i.email}`}
											onClick={async () => {
												setBusy(i.id); setErr("");
												try { await revokeInvitation(i.id); onChange(); }
												catch (e) { setErr((e as Error).message); }
												finally { setBusy(null); }
											}}
										>
											{busy === i.id ? <Loader2Icon className="animate-spin" /> : <XIcon />} Cancelar
										</Button>
									</TableCell>
								)}
							</TableRow>
						))}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	);
}
