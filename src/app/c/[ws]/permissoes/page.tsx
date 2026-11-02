"use client";

import { useEffect, useMemo, useState } from "react";
import { BanIcon, CheckIcon, HelpCircleIcon, Loader2Icon, MinusIcon, RotateCwIcon, UndoIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { WorkspaceGate } from "@/components/workspace-gate";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL, type Access } from "@/lib/access";
import { supabase } from "@/lib/supabase";
import { explainAccess, fetchCapabilityLabels, fetchMatrix, isLive, revokeGrant, setGrant, simulateAccess, type Capability, type Explain, type Grant, type Matrix, type PermMember, type Simulation } from "@/lib/permissions";
import { clientNavGroups } from "@/components/app-shared";
import { INVITE_ROLES } from "@/lib/team";
import { cn } from "@/lib/utils";

/*
 * Permissões (PRD CAP-02/03/05). Por pessoa: o que tem, porquê, e exceções (permitir/negar com motivo e prazo).
 * Por papel: o que cada papel dá. Quem não gere permissões vê só as suas, com o porquê.
 */

const RISK = { A: "alto", M: "médio", B: "baixo" } as const;
const fmt = (iso: string | null) => (iso ? new Date(iso).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "");

export default function PermissoesPage() {
  return <WorkspaceGate need="team.read">{(access) => <Permissoes access={access} />}</WorkspaceGate>;
}

function Permissoes({ access }: { access: Access }) {
  const { can, mode } = useSession();
  if (mode === "code") return <Alert><AlertDescription>As permissões só abrem com conta própria.</AlertDescription></Alert>;
  return can("permissions.manage") ? <Console access={access} /> : <Mine access={access} />;
}

function byModule(caps: Capability[]) {
  const m = new Map<string, Capability[]>();
  for (const c of caps) m.set(c.module, [...(m.get(c.module) ?? []), c]);
  return [...m.entries()];
}

function WhyButton({ ws, user, cap }: { ws: string; user: string; cap: string }) {
  const [e, setE] = useState<Explain | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <span className="inline-flex flex-col items-end">
      <Button size="sm" variant="ghost" aria-label="Porquê?" disabled={busy} onClick={async () => {
        if (e) { setE(null); return; }
        setBusy(true); setErr("");
        try { setE(await explainAccess(ws, user, cap)); } catch (x) { setErr((x as Error).message); } finally { setBusy(false); }
      }}>{busy ? <Loader2Icon className="animate-spin" /> : <HelpCircleIcon />} Porquê?</Button>
      {e && <span className={cn("max-w-xs text-right text-xs", e.allowed ? "text-emerald-600 dark:text-emerald-400" : "text-muted-foreground")} role="status">{e.reasons.join(" ")}</span>}
      {err && <span className="text-xs text-destructive">{err}</span>}
    </span>
  );
}

function Mine({ access }: { access: Access }) {
  const { ws, email } = useSession();
  const [me, setMe] = useState<string | null>(null);
  const [labels, setLabels] = useState<Record<string, { label: string; module: string }>>({});
  useEffect(() => {
    let alive = true;
    supabase().auth.getUser().then(({ data }) => { if (alive) setMe(data.user?.id ?? null); });
    fetchCapabilityLabels().then((l) => { if (alive) setLabels(l); }).catch(() => undefined);   // sem nomes mostra a chave
    return () => { alive = false; };
  }, []);
  const caps = [...(ws?.capabilities ?? [])].sort((a, b) => (labels[a]?.module ?? a).localeCompare(labels[b]?.module ?? b));
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">As tuas permissões</h1>
        <p className="text-sm text-muted-foreground">O que {email} pode fazer em {ws?.name}. Para mudar, fala com quem gere as permissões deste cliente.</p>
      </div>
      <Card><CardContent className="flex flex-col divide-y pt-4 text-sm">
        {caps.length === 0 && <span className="text-muted-foreground">Sem permissões neste cliente.</span>}
        {caps.map((c) => (
          <div key={c} data-cap={c} className="flex items-center justify-between gap-3 py-2">
            <span><CheckIcon className="mr-2 inline size-4 text-emerald-600" />{labels[c]?.label ?? c}<span className="ml-2 text-xs text-muted-foreground">{labels[c]?.module}</span></span>
            {me && <WhyButton ws={access.ws} user={me} cap={c} />}
          </div>
        ))}
      </CardContent></Card>
    </div>
  );
}

function Console({ access }: { access: Access }) {
  const [m, setM] = useState<Matrix | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [tab, setTab] = useState<"pessoa" | "papeis" | "excecoes" | "ver">("pessoa");
  const [sel, setSel] = useState<string | null>(null);
  const [onlyLive, setOnlyLive] = useState(true);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    let alive = true;
    fetchMatrix(access.ws).then((x) => { if (alive) { setM(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access.ws, rev]);

  if (err) return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
    <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  if (!m) return <Skeleton className="h-96" />;
  const caps = m.capabilities.filter((c) => !onlyLive || isLive(c));
  const member = m.members.find((x) => x.user_id === sel) ?? m.members[0] ?? null;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Permissões</h1>
          <p className="text-sm text-muted-foreground">O papel dá o conjunto base; as exceções acrescentam ou tiram uma capacidade a uma pessoa. Negar prevalece sempre. O cargo não dá permissões.</p>
        </div>
        <ToggleGroup value={[tab]} onValueChange={(v) => { const t = (v as string[])[0] as typeof tab | undefined; if (t) setTab(t); }} variant="outline" size="sm">
          <ToggleGroupItem value="pessoa">Por pessoa</ToggleGroupItem>
          <ToggleGroupItem value="papeis">Por papel</ToggleGroupItem>
          <ToggleGroupItem value="excecoes">Exceções ({m.grants.length})</ToggleGroupItem>
          <ToggleGroupItem value="ver">Ver como</ToggleGroupItem>
        </ToggleGroup>
      </div>
      <label className="inline-flex items-center gap-2 text-sm text-muted-foreground"><input type="checkbox" checked={onlyLive} onChange={(e) => setOnlyLive(e.target.checked)} /> Só o que já existe na app</label>
      {msg && <Alert variant={msg.ok ? "default" : "destructive"}><AlertDescription className="flex items-center justify-between gap-2" role="status">{msg.text}
        <Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button></AlertDescription></Alert>}

      {tab === "ver" && <SeeAs ws={access.ws} m={m} onlyLive={onlyLive} />}
      {tab === "pessoa" && (m.members.length === 0 ? (
        <Alert><AlertDescription>Ainda ninguém tem conta neste cliente. O dono da agência tem acesso a tudo sem aparecer aqui.</AlertDescription></Alert>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[16rem_1fr]">
          <Card className="h-fit"><CardContent className="flex flex-col gap-1 p-2">
            {m.members.map((p) => (
              <button key={p.user_id} data-person={p.email} onClick={() => setSel(p.user_id)}
                className={cn("rounded-md px-3 py-2 text-left text-sm hover:bg-muted", member?.user_id === p.user_id && "bg-muted")}>
                <div className="truncate font-medium">{p.email}</div>
                <div className="text-xs text-muted-foreground">{ROLE_LABEL[p.role] ?? p.role}{p.affiliation === "agency_staff" ? " · agência" : ""}{p.status !== "active" ? " · suspenso" : ""}
                  {m.grants.some((g) => g.user_id === p.user_id) ? " · com exceções" : ""}</div>
              </button>
            ))}
          </CardContent></Card>
          {member && <PersonCaps ws={access.ws} m={m} p={member} caps={caps} onDone={(t) => { setMsg({ ok: true, text: t }); setRev((n) => n + 1); }} onErr={(t) => setMsg({ ok: false, text: t })} />}
        </div>
      ))}
      {tab === "papeis" && <RolesTable m={m} caps={caps} />}
      {tab === "excecoes" && <GrantsList m={m} onDone={(t) => { setMsg({ ok: true, text: t }); setRev((n) => n + 1); }} onErr={(t) => setMsg({ ok: false, text: t })} />}
    </div>
  );
}

type Pending = { cap: Capability; effect: "allow" | "deny" } | { cap: Capability; revoke: Grant };

function PersonCaps({ ws, m, p, caps, onDone, onErr }: { ws: string; m: Matrix; p: PermMember; caps: Capability[]; onDone: (t: string) => void; onErr: (t: string) => void }) {
  const [pending, setPending] = useState<Pending | null>(null);
  const roleCaps = useMemo(() => new Set(m.roles[p.role] ?? []), [m.roles, p.role]);
  const eff = useMemo(() => new Set(p.effective), [p.effective]);
  const grants = useMemo(() => new Map(m.grants.filter((g) => g.user_id === p.user_id).map((g) => [g.capability, g])), [m.grants, p.user_id]);
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{p.email}</CardTitle>
        <CardDescription>
          {ROLE_LABEL[p.role] ?? p.role}{p.job_title ? ` · ${p.job_title}` : ""}. {p.effective.length} capacidades ativas.
          {!p.can_edit && " Não podes mudar as permissões desta pessoa (és tu, está acima de ti ou é da agência)."}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-5">
        {byModule(caps).map(([mod, list]) => (
          <div key={mod}>
            <h3 className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">{mod}</h3>
            <div className="divide-y rounded-md border">
              {list.map((c) => {
                const g = grants.get(c.key);
                const on = eff.has(c.key);
                const state = g?.effect === "deny" ? "deny" : g?.effect === "allow" && !roleCaps.has(c.key) ? "grant" : roleCaps.has(c.key) ? "role" : "none";
                return (
                  <div key={c.key} data-cap={c.key} className={cn("flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm", !isLive(c) && "opacity-60")}>
                    <div className="min-w-48 flex-1">
                      <span className="mr-2 inline-flex size-5 items-center justify-center align-middle">
                        {on ? <CheckIcon className="size-4 text-emerald-600" aria-label="tem" /> : state === "deny" ? <BanIcon className="size-4 text-destructive" aria-label="negado" /> : <MinusIcon className="size-4 text-muted-foreground" aria-label="não tem" />}
                      </span>
                      {c.label}
                      {c.risk === "A" && <Badge variant="outline" className="ml-2 text-[10px]">risco {RISK[c.risk]}</Badge>}
                      {!isLive(c) && <span className="ml-2 text-xs text-muted-foreground">(ainda não existe na app)</span>}
                      <span className="block pl-7 text-xs text-muted-foreground">
                        {state === "role" ? "pelo papel" : state === "grant" ? `exceção${g?.expires_at ? ` até ${fmt(g.expires_at)}` : ""}${g?.reason ? `: ${g.reason}` : ""}`
                          : state === "deny" ? `negado${g?.expires_at ? ` até ${fmt(g.expires_at)}` : ""}${g?.reason ? `: ${g.reason}` : ""}` : "sem acesso"}
                      </span>
                    </div>
                    <div className="flex items-center gap-1">
                      {p.can_edit && !g && !on && c.mine && <Button size="sm" variant="outline" onClick={() => setPending({ cap: c, effect: "allow" })}><CheckIcon /> Permitir</Button>}
                      {p.can_edit && !g && on && <Button size="sm" variant="outline" onClick={() => setPending({ cap: c, effect: "deny" })}><BanIcon /> Negar</Button>}
                      {p.can_edit && g && <Button size="sm" variant="ghost" onClick={() => setPending({ cap: c, revoke: g })}><UndoIcon /> Retirar exceção</Button>}
                      <WhyButton ws={ws} user={p.user_id} cap={c.key} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </CardContent>
      {pending && <GrantDialog ws={ws} p={p} pending={pending} onClose={() => setPending(null)}
        onDone={(t) => { setPending(null); onDone(t); }} onErr={(t) => { setPending(null); onErr(t); }} />}
    </Card>
  );
}

function GrantDialog({ ws, p, pending, onClose, onDone, onErr }: { ws: string; p: PermMember; pending: Pending; onClose: () => void; onDone: (t: string) => void; onErr: (t: string) => void }) {
  const [reason, setReason] = useState("");
  const [until, setUntil] = useState("");
  const [busy, setBusy] = useState(false);
  const revoke = "revoke" in pending;
  const title = revoke ? `Retirar a exceção de ${p.email}` : pending.effect === "allow" ? `Permitir a ${p.email}` : `Negar a ${p.email}`;
  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            <b>{pending.cap.label}</b>. {revoke ? "Volta a valer só o que o papel dá." : pending.effect === "deny" ? "A negação prevalece sobre o papel até a retirares ou expirar." : "Só podes dar o que tu próprio tens."} Fica no histórico com o motivo.
          </DialogDescription>
        </DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true);
          try {
            if ("revoke" in pending) { await revokeGrant(pending.revoke.id, reason); onDone(`Exceção retirada: ${pending.cap.label}.`); }
            else {
              const r = await setGrant(ws, p.user_id, pending.cap.key, pending.effect, until ? new Date(until).toISOString() : null, reason);
              onDone(`${pending.effect === "allow" ? "Permitido" : "Negado"}: ${pending.cap.label}. ${r.now.reasons.join(" ")}`);
            }
          } catch (x) { onErr((x as Error).message); }
          finally { setBusy(false); }
        }}>
          <label className="flex flex-col gap-1 text-sm">Motivo<Input value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} placeholder="Ex.: cobre as férias da Ana" /></label>
          {!revoke && <label className="flex flex-col gap-1 text-sm">Válido até (opcional, máximo um ano)<Input type="datetime-local" value={until} onChange={(e) => setUntil(e.target.value)} /></label>}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>Cancelar</Button>
            <Button type="submit" variant={!revoke && pending.effect === "deny" ? "destructive" : "default"} disabled={busy || (!revoke && reason.trim().length < 3)}>
              {busy && <Loader2Icon className="animate-spin" />} Confirmar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function RolesTable({ m, caps }: { m: Matrix; caps: Capability[] }) {
  const roles = [...INVITE_ROLES].reverse();
  return (
    <Card><CardContent className="overflow-x-auto pt-4">
      <Table>
        <TableHeader><TableRow><TableHead>Capacidade</TableHead>{roles.map((r) => <TableHead key={r} className="text-center">{ROLE_LABEL[r] ?? r}</TableHead>)}</TableRow></TableHeader>
        <TableBody>
          {caps.map((c) => (
            <TableRow key={c.key}>
              <TableCell><span className="text-xs text-muted-foreground">{c.module} · </span>{c.label}</TableCell>
              {roles.map((r) => <TableCell key={r} className="text-center">{(m.roles[r] ?? []).includes(c.key) ? <CheckIcon className="mx-auto size-4 text-emerald-600" aria-label="sim" /> : <span className="text-muted-foreground" aria-label="não">·</span>}</TableCell>)}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <p className="mt-3 text-xs text-muted-foreground">Os papéis ainda não se editam aqui: para casos à parte usa exceções por pessoa.</p>
    </CardContent></Card>
  );
}

function GrantsList({ m, onDone, onErr }: { m: Matrix; onDone: (t: string) => void; onErr: (t: string) => void }) {
  const [busy, setBusy] = useState<number | null>(null);
  const label = (k: string) => m.capabilities.find((c) => c.key === k)?.label ?? k;
  const who = (u: string) => m.members.find((x) => x.user_id === u);
  if (m.grants.length === 0) return <Alert><AlertDescription>Não há exceções ativas: cada pessoa tem exatamente o que o papel dá.</AlertDescription></Alert>;
  return (
    <Card><CardContent className="pt-4">
      <Table>
        <TableHeader><TableRow><TableHead>Pessoa</TableHead><TableHead>Capacidade</TableHead><TableHead>Exceção</TableHead><TableHead>Motivo</TableHead><TableHead>Por</TableHead><TableHead /></TableRow></TableHeader>
        <TableBody>
          {m.grants.map((g) => (
            <TableRow key={g.id}>
              <TableCell className="font-medium">{who(g.user_id)?.email ?? "—"}</TableCell>
              <TableCell>{label(g.capability)}</TableCell>
              <TableCell>{g.effect === "allow" ? <Badge variant="secondary">permitido</Badge> : <Badge variant="destructive">negado</Badge>}{g.expires_at && <div className="text-xs text-muted-foreground">até {fmt(g.expires_at)}</div>}</TableCell>
              <TableCell className="max-w-xs text-sm">{g.reason}</TableCell>
              <TableCell className="text-xs text-muted-foreground">{g.by}<div>{fmt(g.created_at)}</div></TableCell>
              <TableCell className="text-right">{who(g.user_id)?.can_edit && <Button size="sm" variant="ghost" disabled={busy === g.id} onClick={async () => {
                setBusy(g.id);
                try { await revokeGrant(g.id, "retirada na lista de exceções"); onDone(`Exceção retirada: ${label(g.capability)}.`); } catch (x) { onErr((x as Error).message); } finally { setBusy(null); }
              }}>{busy === g.id ? <Loader2Icon className="animate-spin" /> : <UndoIcon />} Retirar</Button>}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </CardContent></Card>
  );
}

/** "Ver como" (CAP-05, BIZ-07): o que uma pessoa ou um papel vê e pode fazer neste cliente. Só leitura; fica no histórico. */
function SeeAs({ ws, m, onlyLive }: { ws: string; m: Matrix; onlyLive: boolean }) {
  const [target, setTarget] = useState("");
  const [sim, setSim] = useState<Simulation | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const run = async () => {
    const [kind, id] = target.split(":");
    setBusy(true); setErr("");
    try { setSim(await simulateAccess(ws, kind === "u" ? { user: id } : { role: id })); }
    catch (e) { setErr((e as Error).message); setSim(null); }
    finally { setBusy(false); }
  };
  const allowed = new Set((sim?.capabilities ?? []).filter((c) => c.allowed).map((c) => c.key));
  const menu = clientNavGroups.flatMap((g) => g.items).filter((i) => i.path && !i.soon && !i.orgCap && (!i.cap || allowed.has(i.cap)));
  const caps = (sim?.capabilities ?? []).filter((c) => !onlyLive || isLive(c as unknown as Capability));
  return (
    <section aria-label="Ver como" className="flex flex-col gap-3">
      <form className="flex flex-wrap items-center gap-2" onSubmit={(e) => { e.preventDefault(); if (target) void run(); }}>
        <select aria-label="Ver como quem" className="h-9 rounded-md border bg-background px-2 text-sm" value={target} onChange={(e) => { setTarget(e.target.value); setSim(null); }}>
          <option value="">Escolhe uma pessoa ou um papel</option>
          <optgroup label="Pessoas">
            {m.members.map((p) => <option key={p.user_id} value={`u:${p.user_id}`}>{p.email} ({ROLE_LABEL[p.role] ?? p.role})</option>)}
          </optgroup>
          <optgroup label="Papéis">
            {Object.keys(m.roles).map((r) => <option key={r} value={`r:${r}`}>{ROLE_LABEL[r] ?? r}</option>)}
          </optgroup>
        </select>
        <Button type="submit" size="sm" disabled={!target || busy}>{busy && <Loader2Icon className="animate-spin" />} Ver</Button>
      </form>
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      {sim && (
        <>
          <div role="status" className="rounded-md border border-amber-500/50 bg-amber-500/10 px-3 py-2 text-sm">
            Pré-visualização como <b>{sim.target.kind === "role" ? `papel ${ROLE_LABEL[sim.target.label] ?? sim.target.label}` : sim.target.label}</b>
            {sim.target.kind === "user" && sim.target.role ? ` (${ROLE_LABEL[sim.target.role] ?? sim.target.role})` : ""}. Só leitura: nada muda e fica registado no histórico.
          </div>
          <div className="grid gap-4 md:grid-cols-[minmax(0,14rem)_1fr]">
            <div>
              <h3 className="mb-1 text-sm font-medium">Vê no menu</h3>
              {menu.length === 0 ? <p className="text-sm text-muted-foreground">Nada: não abre este cliente.</p> : (
                <ul className="flex flex-col gap-1 text-sm" aria-label="Menu visto">{menu.map((i) => <li key={i.path}>{i.title}</li>)}</ul>
              )}
            </div>
            <div>
              <h3 className="mb-1 text-sm font-medium">Pode fazer</h3>
              <ul className="flex flex-col gap-1 text-sm" aria-label="Capacidades simuladas">
                {caps.map((c) => (
                  <li key={c.key} data-cap={c.key} className="flex flex-wrap items-baseline gap-2">
                    <span className={cn("w-4", c.allowed ? "text-emerald-600 dark:text-emerald-400" : "text-muted-foreground")}>{c.allowed ? "✓" : "✗"}</span>
                    <span className={cn(!c.allowed && "text-muted-foreground")}>{c.label}</span>
                    <span className="text-xs text-muted-foreground">{c.module} · {c.reasons.join(" ")}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </>
      )}
    </section>
  );
}
