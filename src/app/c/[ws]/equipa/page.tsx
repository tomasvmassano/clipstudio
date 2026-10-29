"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, MailPlusIcon, PauseIcon, PlayIcon, RotateCwIcon, UserMinusIcon, UserPlusIcon, XIcon } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
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
import { assignAgencyStaff, fetchTeam, INVITE_ROLES, inviteMember, removeMember, revokeInvitation, updateMember, type Member, type Team } from "@/lib/team";

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
					{!!team.agency_staff?.length && <AssignCard ws={access.ws} staff={team.agency_staff} onDone={reload} />}
					<MembersCard ws={access.ws} team={team} onChange={reload} />
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

const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";
const STATUS_LABEL = { active: "Ativo", suspended: "Suspenso" } as const;

function MembersCard({ ws, team, onChange }: { ws: string; team: Team; onChange: () => void }) {
	const [busy, setBusy] = useState<string | null>(null);
	const [err, setErr] = useState("");
	const [removing, setRemoving] = useState<Member | null>(null);
	const roles = INVITE_ROLES.filter((_, i) => i + 1 <= (team.my_rank ?? 0));
	const act = async (m: Member, f: () => Promise<unknown>) => {
		setBusy(m.user_id); setErr("");
		try { await f(); onChange(); } catch (e) { setErr((e as Error).message); } finally { setBusy(null); }
	};
	return (
		<Card>
			<CardHeader>
				<CardTitle>Com acesso</CardTitle>
				<CardDescription>
					{team.members.length} pessoa{team.members.length === 1 ? "" : "s"}.
					{team.can_manage ? " Só mudas quem está ao teu nível ou abaixo, e nunca a ti próprio." : ""}
				</CardDescription>
			</CardHeader>
			<CardContent>
				{err && <p className="mb-3 text-sm text-destructive" role="alert">{err}</p>}
				{team.members.length === 0 ? (
					<p className="text-sm text-muted-foreground">Ainda ninguém entrou com conta própria neste cliente. O dono da agência tem acesso sem aparecer aqui.</p>
				) : (
					<Table>
						<TableHeader>
							<TableRow><TableHead>Email</TableHead><TableHead>Lado</TableHead><TableHead>Papel</TableHead><TableHead>Estado</TableHead><TableHead>Desde</TableHead>{team.can_manage && <TableHead />}</TableRow>
						</TableHeader>
						<TableBody>
							{team.members.map((m) => (
								<TableRow key={m.user_id} data-member={m.email}>
									<TableCell className="font-medium">{m.email}{m.job_title && <span className="ml-2 text-xs text-muted-foreground">{m.job_title}</span>}</TableCell>
									<TableCell>{AFF_LABEL[m.affiliation]}</TableCell>
									<TableCell>
										{m.can_manage ? (
											<select aria-label={`Papel de ${m.email}`} className={selectCls} value={m.role} disabled={busy === m.user_id}
												onChange={(e) => act(m, () => updateMember(ws, m.user_id, { role: e.target.value }))}>
												{(roles.includes(m.role as (typeof INVITE_ROLES)[number]) ? roles : [m.role, ...roles]).map((r) => <option key={r} value={r}>{ROLE_LABEL[r] ?? r}</option>)}
											</select>
										) : (ROLE_LABEL[m.role] ?? m.role)}
									</TableCell>
									<TableCell><Badge variant={m.status === "active" ? "secondary" : "outline"}>{STATUS_LABEL[m.status] ?? m.status}</Badge></TableCell>
									<TableCell className="text-muted-foreground">{fmtDate(m.since)}</TableCell>
									{team.can_manage && (
										<TableCell className="text-right">
											{m.can_manage && (
												<div className="flex justify-end gap-1">
													{m.status === "active"
														? <Button size="sm" variant="ghost" disabled={busy === m.user_id} onClick={() => act(m, () => updateMember(ws, m.user_id, { status: "suspended" }))}><PauseIcon /> Suspender</Button>
														: <Button size="sm" variant="ghost" disabled={busy === m.user_id} onClick={() => act(m, () => updateMember(ws, m.user_id, { status: "active" }))}><PlayIcon /> Reativar</Button>}
													<Button size="sm" variant="ghost" className="text-destructive" disabled={busy === m.user_id} onClick={() => setRemoving(m)}><UserMinusIcon /> Remover</Button>
												</div>
											)}
										</TableCell>
									)}
								</TableRow>
							))}
						</TableBody>
					</Table>
				)}
			</CardContent>
			{removing && <RemoveDialog ws={ws} member={removing} others={team.members.filter((x) => x.user_id !== removing.user_id && x.status === "active")}
				onClose={() => setRemoving(null)} onDone={() => { setRemoving(null); onChange(); }} />}
		</Card>
	);
}

function RemoveDialog({ ws, member, others, onClose, onDone }: { ws: string; member: Member; others: Member[]; onClose: () => void; onDone: () => void }) {
	const [to, setTo] = useState("");
	const [busy, setBusy] = useState(false);
	const [err, setErr] = useState("");
	const n = member.open_tasks ?? 0;
	return (
		<Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>Remover {member.email}</DialogTitle>
					<DialogDescription>Perde o acesso já. O que fez fica com o nome dela no histórico. Para voltar a entrar precisa de um convite novo.</DialogDescription>
				</DialogHeader>
				{n > 0 && (
					<label className="flex flex-col gap-1 text-sm">{n} tarefa{n === 1 ? "" : "s"} aberta{n === 1 ? "" : "s"} passa{n === 1 ? "" : "m"} para
						<select aria-label="Passar tarefas para" className="h-9 rounded-md border bg-background px-2 text-sm" value={to} onChange={(e) => setTo(e.target.value)}>
							<option value="">Ninguém (ficam sem responsável)</option>
							{others.map((o) => <option key={o.user_id} value={o.user_id}>{o.email}</option>)}
						</select>
					</label>
				)}
				{err && <p className="text-sm text-destructive" role="alert">{err}</p>}
				<DialogFooter>
					<Button variant="ghost" onClick={onClose}>Cancelar</Button>
					<Button variant="destructive" disabled={busy} onClick={async () => {
						setBusy(true); setErr("");
						try { await removeMember(ws, member.user_id, to || null); onDone(); }
						catch (e) { setErr((e as Error).message); }
						finally { setBusy(false); }
					}}>{busy && <Loader2Icon className="animate-spin" />} Remover</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}

function AssignCard({ ws, staff, onDone }: { ws: string; staff: { user_id: string; email: string }[]; onDone: () => void }) {
	const [user, setUser] = useState(staff[0]?.user_id ?? "");
	const [role, setRole] = useState("contributor");
	const [busy, setBusy] = useState(false);
	const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
	return (
		<Card>
			<CardHeader>
				<CardTitle>Atribuir alguém da agência</CardTitle>
				<CardDescription>Para quem já tem conta na agência: entra neste cliente com o papel que escolheres, sem convite. O papel aqui não muda o que tem nos outros clientes.</CardDescription>
			</CardHeader>
			<CardContent className="flex flex-col gap-3 sm:flex-row sm:items-end">
				<label className="flex flex-1 flex-col gap-1.5 text-sm font-medium">Pessoa
					<select aria-label="Pessoa da agência" className="h-9 rounded-md border bg-background px-2 text-sm font-normal" value={user} onChange={(e) => setUser(e.target.value)}>
						{staff.map((s) => <option key={s.user_id} value={s.user_id}>{s.email}</option>)}
					</select>
				</label>
				<label className="flex flex-col gap-1.5 text-sm font-medium">Papel
					<select aria-label="Papel da pessoa da agência" className="h-9 min-w-40 rounded-md border bg-background px-2 text-sm font-normal" value={role} onChange={(e) => setRole(e.target.value)}>
						{INVITE_ROLES.map((r) => <option key={r} value={r}>{ROLE_LABEL[r] ?? r}</option>)}
					</select>
				</label>
				<Button disabled={busy || !user} onClick={async () => {
					setBusy(true); setMsg(null);
					try { await assignAgencyStaff(ws, user, role); setMsg({ ok: true, text: "Atribuído." }); onDone(); }
					catch (e) { setMsg({ ok: false, text: (e as Error).message }); }
					finally { setBusy(false); }
				}}>{busy ? <Loader2Icon className="animate-spin" /> : <UserPlusIcon />} Atribuir</Button>
			</CardContent>
			{msg && <p className={`px-6 pb-4 text-sm ${msg.ok ? "text-emerald-500" : "text-destructive"}`} role="status">{msg.text}</p>}
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
