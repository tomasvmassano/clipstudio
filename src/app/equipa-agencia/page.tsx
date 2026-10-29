"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, MailPlusIcon, RotateCwIcon, XIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL } from "@/lib/access";
import {
  AGENCY_ROLES, AGENCY_ROLE_LABEL, INVITE_ROLES, assignAgencyStaff, fetchAgencyTeam, inviteAgency, removeMember, revokeAgencyInvite,
  updateAgencyMember, type AgencyStaff, type AgencyTeam,
} from "@/lib/team";

/*
 * Equipa da agência (espaço da agência, W1-13; ADR-0020). Quem é staff, com que papel, em que clientes trabalha e com quanta carga.
 * Ver: admin e dono da agência. Convidar, mudar papel, suspender e atribuir a clientes: só o dono. O servidor volta a verificar tudo.
 */

const selectCls = "h-8 rounded-md border bg-background px-2 text-sm";
const fmt = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("pt-PT", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Dubai" }) : "nunca");

export default function EquipaAgenciaPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("team.read")) return <Alert><AlertDescription>A equipa da agência só é visível ao dono e aos admins da agência.</AlertDescription></Alert>;
  return <EquipaAgencia />;
}

function EquipaAgencia() {
  const [team, setTeam] = useState<AgencyTeam | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const reload = useCallback(() => setRev((n) => n + 1), []);

  useEffect(() => {
    let alive = true;
    fetchAgencyTeam().then((t) => { if (alive) { setTeam(t); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [rev]);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Equipa da agência</h1>
        <p className="text-sm text-muted-foreground">Quem trabalha na agência, com que papel, em que clientes e com quantas tarefas abertas. O papel em cada cliente muda-se dentro do cliente.</p>
      </div>
      {err ? (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{err}
          <Button size="sm" variant="outline" onClick={() => { setErr(""); reload(); }}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
      ) : !team ? <Skeleton className="h-64" /> : (
        <>
          {team.can.invite && <InviteCard onDone={reload} />}
          <Card className="shadow-none dark:ring-0">
            <CardHeader><CardTitle>Staff ({team.staff.length})</CardTitle>
              <CardDescription>Suspender corta logo o acesso a todos os clientes; reativar devolve-o. Nada é apagado.</CardDescription></CardHeader>
            <CardContent className="flex flex-col divide-y p-0">
              {team.staff.map((s) => <StaffRow key={s.user_id} s={s} team={team} onDone={reload} />)}
            </CardContent>
          </Card>
          {team.can.invite && team.invites.length > 0 && <Invites team={team} onDone={reload} />}
        </>
      )}
    </div>
  );
}

function InviteCard({ onDone }: { onDone: () => void }) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<string>("agency_member");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  return (
    <Card className="shadow-none dark:ring-0">
      <CardHeader><CardTitle>Convidar para a agência</CardTitle>
        <CardDescription>A pessoa cria conta com este email e entra na agência sem acesso a clientes; depois atribuis-lhe os clientes em que trabalha. Ainda não enviamos o email: avisa a pessoa e manda-lhe o link da app.</CardDescription></CardHeader>
      <CardContent>
        <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setMsg(null);
          try { await inviteAgency(email, role); setMsg({ ok: true, text: `Convite criado para ${email.trim().toLowerCase()}. Válido 14 dias.` }); setEmail(""); onDone(); }
          catch (e2) { setMsg({ ok: false, text: (e2 as Error).message }); }
          finally { setBusy(false); }
        }}>
          <label className="flex min-w-64 flex-1 flex-col gap-1 text-sm">Email<Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nome@agencia.com" /></label>
          <label className="flex flex-col gap-1 text-sm">Papel na agência
            <select aria-label="Papel na agência" className={selectCls} value={role} onChange={(e) => setRole(e.target.value)}>
              {AGENCY_ROLES.map((r) => <option key={r} value={r}>{AGENCY_ROLE_LABEL[r]}</option>)}
            </select>
          </label>
          <Button type="submit" disabled={busy || !email.trim()}>{busy ? <Loader2Icon className="animate-spin" /> : <MailPlusIcon />} Convidar</Button>
        </form>
        {msg && <p className={`mt-2 text-sm ${msg.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"}`} role={msg.ok ? "status" : "alert"}>{msg.text}</p>}
      </CardContent>
    </Card>
  );
}

function StaffRow({ s, team, onDone }: { s: AgencyStaff; team: AgencyTeam; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [confirm, setConfirm] = useState<null | { kind: "suspend" } | { kind: "unassign"; ws: string; name: string; tasks: number }>(null);
  const [assign, setAssign] = useState({ ws: "", role: "contributor" });
  const editable = team.can.manage && s.user_id !== team.me && s.agency_role !== "agency_owner";
  const run = async (f: () => Promise<unknown>) => {
    setBusy(true); setErr("");
    try { await f(); setConfirm(null); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  const free = team.clients.filter((c) => !s.clients.some((x) => x.id === c.id));
  return (
    <div className="flex flex-col gap-2 px-4 py-3 text-sm" data-staff={s.email}>
      <div className="flex flex-wrap items-center gap-2">
        <b className="mr-1">{s.email}</b>
        {s.user_id === team.me && <Badge variant="secondary">tu</Badge>}
        {s.status === "suspended" && <Badge variant="destructive">suspenso</Badge>}
        {editable ? (
          <select aria-label={`Papel de ${s.email} na agência`} className={selectCls} value={s.agency_role} disabled={busy}
            onChange={(e) => run(() => updateAgencyMember(s.user_id, { agency_role: e.target.value }))}>
            {AGENCY_ROLES.map((r) => <option key={r} value={r}>{AGENCY_ROLE_LABEL[r]}</option>)}
          </select>
        ) : <span className="text-muted-foreground">{AGENCY_ROLE_LABEL[s.agency_role] ?? s.agency_role}</span>}
        <span className="text-xs text-muted-foreground">· {s.open_tasks} {s.open_tasks === 1 ? "tarefa aberta" : "tarefas abertas"} · último acesso {fmt(s.last_sign_in)}</span>
        {editable && (
          <span className="ml-auto">
            {s.status === "active"
              ? <Button size="sm" variant="ghost" disabled={busy} onClick={() => setConfirm({ kind: "suspend" })}>Suspender</Button>
              : <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => updateAgencyMember(s.user_id, { status: "active" }))}>Reativar</Button>}
          </span>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-1.5">
        {s.clients.length === 0 && <span className="text-xs text-muted-foreground">Ainda não trabalha em nenhum cliente que possas ver.</span>}
        {s.clients.map((c) => (
          <span key={c.id} className="inline-flex items-center gap-1 rounded-md border px-2 py-0.5 text-xs">
            {c.name} · {ROLE_LABEL[c.role] ?? c.role}{c.open_tasks ? ` · ${c.open_tasks} abertas` : ""}
            {editable && (
              <button type="button" aria-label={`Tirar ${s.email} de ${c.name}`} className="rounded p-0.5 hover:bg-muted" disabled={busy}
                onClick={() => setConfirm({ kind: "unassign", ws: c.id, name: c.name, tasks: c.open_tasks })}><XIcon className="size-3" /></button>
            )}
          </span>
        ))}
      </div>
      {editable && s.status === "active" && free.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label={`Cliente para ${s.email}`} className={selectCls} value={assign.ws} onChange={(e) => setAssign({ ...assign, ws: e.target.value })}>
            <option value="">Atribuir a um cliente…</option>
            {free.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select aria-label={`Papel de ${s.email} no cliente`} className={selectCls} value={assign.role} onChange={(e) => setAssign({ ...assign, role: e.target.value })}>
            {INVITE_ROLES.map((r) => <option key={r} value={r}>{ROLE_LABEL[r] ?? r}</option>)}
          </select>
          <Button size="sm" variant="outline" disabled={busy || !assign.ws} onClick={() => run(async () => { await assignAgencyStaff(assign.ws, s.user_id, assign.role); setAssign({ ws: "", role: "contributor" }); })}>
            {busy && <Loader2Icon className="animate-spin" />} Atribuir
          </Button>
        </div>
      )}
      {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
      {confirm && (
        <Dialog open onOpenChange={(o) => { if (!o) setConfirm(null); }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>{confirm.kind === "suspend" ? `Suspender ${s.email}` : `Tirar ${s.email} de ${confirm.name}`}</DialogTitle>
              <DialogDescription>
                {confirm.kind === "suspend"
                  ? "Perde já o acesso à agência e a todos os clientes. As tarefas ficam com ela; podes reativar quando quiseres."
                  : `Perde já o acesso a ${confirm.name}.${confirm.tasks ? ` As ${confirm.tasks} tarefas abertas ficam sem responsável: reatribui-as no cliente.` : ""} O que fez fica no histórico.`}
              </DialogDescription>
            </DialogHeader>
            {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
            <DialogFooter>
              <Button variant="ghost" onClick={() => setConfirm(null)}>Cancelar</Button>
              <Button variant="destructive" disabled={busy} onClick={() => run(() => confirm.kind === "suspend"
                ? updateAgencyMember(s.user_id, { status: "suspended" })
                : removeMember(confirm.ws, s.user_id, null))}>
                {busy && <Loader2Icon className="animate-spin" />} {confirm.kind === "suspend" ? "Suspender" : "Tirar do cliente"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

function Invites({ team, onDone }: { team: AgencyTeam; onDone: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState("");
  return (
    <Card className="shadow-none dark:ring-0">
      <CardHeader><CardTitle>Convites pendentes</CardTitle><CardDescription>Ficam pendentes até a pessoa criar conta com o email e o confirmar.</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {team.invites.map((i) => (
          <div key={i.id} className="flex flex-wrap items-center gap-2">
            <b>{i.email}</b><span className="text-muted-foreground">{AGENCY_ROLE_LABEL[i.agency_role]} · expira {fmt(i.expires_at)}</span>
            <Button size="sm" variant="ghost" className="ml-auto" disabled={busy === i.id} aria-label={`Cancelar convite de ${i.email}`}
              onClick={async () => { setBusy(i.id); setErr(""); try { await revokeAgencyInvite(i.id); onDone(); } catch (e) { setErr((e as Error).message); } finally { setBusy(null); } }}>
              Cancelar convite
            </Button>
          </div>
        ))}
        {err && <p className="text-destructive" role="alert">{err}</p>}
      </CardContent>
    </Card>
  );
}
