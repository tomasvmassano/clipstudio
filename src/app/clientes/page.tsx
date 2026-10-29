"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { ArchiveIcon, ArchiveRestoreIcon, Building2Icon, Loader2Icon, PencilIcon, PlusIcon, RotateCwIcon, UsersIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/components/session-provider";
import { archiveClient, createClient, CURRENCIES, fetchClients, restoreClient, TIMEZONES, updateClient, type ClientRow, type ClientsList } from "@/lib/clients";

/*
 * Clientes da agência (PRD §2, §3, CAP-08). O dono da agência vê todos e cria/arquiva; o resto da agência
 * só vê os clientes a que foi atribuído. A equipa de um cliente nunca chega aqui (e o servidor recusa).
 */

const selectCls = "h-9 w-full rounded-md border bg-background px-2 text-sm";
const fmtDate = (iso: string) => new Date(iso).toLocaleDateString("pt-PT", { day: "2-digit", month: "short", year: "numeric" });

export default function ClientesPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (mode === "anon") {
    return <Alert><AlertDescription className="flex items-center justify-between gap-3">Precisas de entrar para ver isto.
      <Button size="sm" nativeButton={false} render={<Link href="/login" />}>Entrar</Button></AlertDescription></Alert>;
  }
  if (mode !== "user" || !canOrg("workspaces.read")) {
    return <Alert><AlertDescription>A lista de clientes é só para a equipa da agência com essa permissão. Com o código de equipa ou como equipa de um cliente, trabalhas só no teu cliente.</AlertDescription></Alert>;
  }
  return <Clientes />;
}

function Clientes() {
  const router = useRouter();
  const { setWorkspace, refresh } = useSession();
  const [data, setData] = useState<ClientsList | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<ClientRow | null>(null);
  const [archiving, setArchiving] = useState<ClientRow | null>(null);
  const [msg, setMsg] = useState<{ text: string; open?: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    fetchClients().then((d) => { if (alive) { setData(d); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [rev]);
  const reload = useCallback(async () => { setRev((n) => n + 1); await refresh(); }, [refresh]);
  const open = (id: string, path = "/") => { setWorkspace(id); router.push(path); };

  if (err) {
    return <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
      <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>;
  }
  if (!data) return <Skeleton className="h-64" />;
  const active = data.clients.filter((c) => c.status === "active");
  const archived = data.clients.filter((c) => c.status === "archived");

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Clientes</h1>
          <p className="text-sm text-muted-foreground">Cada cliente tem equipa, guiões, agentes e dados separados. A equipa de um cliente nunca vê os outros.</p>
        </div>
        {data.can.create && <Button onClick={() => setCreating(true)}><PlusIcon /> Novo cliente</Button>}
      </div>

      {msg && (
        <Alert><AlertDescription className="flex flex-wrap items-center justify-between gap-2">{msg.text}
          <span className="flex gap-2">
            {msg.open && <Button size="sm" onClick={() => open(msg.open!)}>Abrir cliente</Button>}
            <Button size="sm" variant="ghost" onClick={() => setMsg(null)}>Fechar</Button>
          </span></AlertDescription></Alert>
      )}

      {active.length === 0 ? (
        <Card><CardContent className="flex flex-col items-start gap-3 py-8">
          <Building2Icon className="size-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">{data.can.create ? "Ainda não há clientes. Cria o primeiro." : "Ainda não foste atribuído a nenhum cliente."}</p>
        </CardContent></Card>
      ) : (
        <Table>
          <TableHeader><TableRow>
            <TableHead>Cliente</TableHead><TableHead>Fuso e moeda</TableHead><TableHead>Equipa</TableHead><TableHead>Agentes</TableHead><TableHead>Desde</TableHead><TableHead />
          </TableRow></TableHeader>
          <TableBody>
            {active.map((c) => (
              <TableRow key={c.id} data-client={c.id}>
                <TableCell>
                  <button className="text-left font-medium hover:underline" onClick={() => open(c.id)}>{c.name}</button>
                  <div className="text-xs text-muted-foreground">{c.handle ? `@${c.handle} · ` : ""}{c.id}</div>
                </TableCell>
                <TableCell className="text-sm">{c.timezone.replace("_", " ")} · {c.currency}</TableCell>
                <TableCell className="text-sm">{c.members} {c.members === 1 ? "pessoa" : "pessoas"}{c.invites ? <span className="text-muted-foreground"> · {c.invites} convite{c.invites === 1 ? "" : "s"}</span> : null}</TableCell>
                <TableCell>
                  {c.agent_config === "active" ? <Badge variant="secondary">Configurados</Badge>
                    : c.agent_config === "draft" ? <Badge variant="outline" className="border-amber-500 text-amber-700 dark:text-amber-300">Por terminar</Badge>
                    : <span className="text-xs text-muted-foreground">Sem configuração</span>}
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">{fmtDate(c.created_at)}</TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end gap-1">
                    <Button size="sm" variant="ghost" onClick={() => open(c.id, "/equipa")}><UsersIcon /> Equipa</Button>
                    {c.can_edit && <Button size="sm" variant="ghost" onClick={() => setEditing(c)}><PencilIcon /> Editar</Button>}
                    {data.can.archive && <Button size="sm" variant="ghost" onClick={() => setArchiving(c)}><ArchiveIcon /> Arquivar</Button>}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {archived.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Arquivados</CardTitle>
            <CardDescription>Ninguém entra num cliente arquivado e a agenda dos agentes pára. Os dados ficam guardados e podes recuperá-lo.</CardDescription></CardHeader>
          <CardContent className="flex flex-col gap-2">
            {archived.map((c) => (
              <div key={c.id} data-archived={c.id} className="flex items-center justify-between gap-2 rounded-md border p-2 text-sm">
                <span><b>{c.name}</b> <span className="text-muted-foreground">{c.id}</span></span>
                <Button size="sm" variant="outline" disabled={busy === c.id} onClick={async () => {
                  setBusy(c.id);
                  try { await restoreClient(c.id); setMsg({ text: `${c.name} recuperado.`, open: c.id }); await reload(); }
                  catch (e) { setMsg({ text: (e as Error).message }); }
                  finally { setBusy(null); }
                }}>{busy === c.id ? <Loader2Icon className="animate-spin" /> : <ArchiveRestoreIcon />} Recuperar</Button>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <CreateDialog open={creating} onOpenChange={setCreating} sources={active} onDone={async (r) => {
        const extra = [r.copied.agentes && "estrutura dos agentes (falta a voz)", r.copied.templates && `${r.copied.templates} template(s)`,
          r.copied.automacoes && `${r.copied.automacoes} automação(ões) sem responsável`].filter(Boolean).join(", ");
        setMsg({ text: `${r.name} criado.${extra ? ` Copiado: ${extra}.` : ""} Próximo passo: convidar a equipa.`, open: r.id });
        await reload();
      }} />
      {editing && <EditDialog client={editing} onClose={() => setEditing(null)} onDone={async (c) => { setMsg({ text: `${c.name} atualizado.` }); setEditing(null); await reload(); }} />}
      {archiving && <ArchiveDialog client={archiving} onClose={() => setArchiving(null)} onDone={async (n) => {
        setMsg({ text: `${archiving.name} arquivado.${n ? ` ${n} execução(ões) em fila cancelada(s).` : ""}` }); setArchiving(null); await reload();
      }} />}
    </div>
  );
}

function ClientFields({ v, set }: { v: { name: string; handle: string; timezone: string; currency: string }; set: (p: Partial<typeof v>) => void }) {
  const tzs = TIMEZONES.includes(v.timezone) ? TIMEZONES : [v.timezone, ...TIMEZONES];
  const curs = CURRENCIES.includes(v.currency) ? CURRENCIES : [v.currency, ...CURRENCIES];
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">Nome<Input required value={v.name} maxLength={80} onChange={(e) => set({ name: e.target.value })} placeholder="Ex.: Clínica Sorriso" /></label>
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">@ principal (opcional)<Input value={v.handle} maxLength={31} onChange={(e) => set({ handle: e.target.value })} placeholder="clinicasorriso" /></label>
      <label className="flex flex-col gap-1 text-sm">Fuso horário
        <select aria-label="Fuso horário" className={selectCls} value={v.timezone} onChange={(e) => set({ timezone: e.target.value })}>{tzs.map((t) => <option key={t} value={t}>{t.replace("_", " ")}</option>)}</select>
      </label>
      <label className="flex flex-col gap-1 text-sm">Moeda
        <select aria-label="Moeda" className={selectCls} value={v.currency} onChange={(e) => set({ currency: e.target.value })}>{curs.map((c) => <option key={c} value={c}>{c}</option>)}</select>
      </label>
    </div>
  );
}

function CreateDialog({ open, onOpenChange, sources, onDone }: {
  open: boolean; onOpenChange: (v: boolean) => void; sources: ClientRow[];
  onDone: (r: Awaited<ReturnType<typeof createClient>>) => void | Promise<void>;
}) {
  const empty = { name: "", handle: "", timezone: "Asia/Dubai", currency: "EUR" };
  const [v, setV] = useState(empty);
  const [copyFrom, setCopyFrom] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <Dialog open={open} onOpenChange={(o) => { onOpenChange(o); if (!o) { setErr(""); setV(empty); setCopyFrom(""); } }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Novo cliente</DialogTitle>
          <DialogDescription>Cria um espaço isolado para o cliente. Depois convidas a equipa dele e atribuis quem da agência trabalha nele.</DialogDescription>
        </DialogHeader>
        <form className="flex flex-col gap-4" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          try { const r = await createClient({ ...v, copyFrom: copyFrom || null }); onOpenChange(false); setV(empty); setCopyFrom(""); await onDone(r); }
          catch (e2) { setErr((e2 as Error).message); }
          finally { setBusy(false); }
        }}>
          <ClientFields v={v} set={(p) => setV({ ...v, ...p })} />
          <label className="flex flex-col gap-1 text-sm">Começar com a estrutura de
            <select aria-label="Copiar estrutura de" className={selectCls} value={copyFrom} onChange={(e) => setCopyFrom(e.target.value)}>
              <option value="">Nenhum (começar do zero)</option>
              {sources.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <span className="text-xs text-muted-foreground">Copia formatos e regras dos agentes, templates de produção e automações. Não copia a voz, o léxico, as notícias, pessoas, guiões nem dados.</span>
          </label>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
            <Button type="submit" disabled={busy || v.name.trim().length < 2}>{busy && <Loader2Icon className="animate-spin" />} Criar cliente</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function EditDialog({ client, onClose, onDone }: { client: ClientRow; onClose: () => void; onDone: (c: ClientRow) => void | Promise<void> }) {
  const [v, setV] = useState({ name: client.name, handle: client.handle ?? "", timezone: client.timezone, currency: client.currency });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader><DialogTitle>Editar {client.name}</DialogTitle>
          <DialogDescription>Mudar o fuso altera a hora a que se mostram prazos e a corrida diária dos agentes deste cliente.</DialogDescription></DialogHeader>
        <form className="flex flex-col gap-4" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          const patch: Record<string, string> = {};
          if (v.name.trim() !== client.name) patch.name = v.name.trim();
          if (v.handle.trim() !== (client.handle ?? "")) patch.handle = v.handle.trim();
          if (v.timezone !== client.timezone) patch.timezone = v.timezone;
          if (v.currency !== client.currency) patch.currency = v.currency;
          try { await onDone(await updateClient(client.id, patch)); }
          catch (e2) { setErr((e2 as Error).message); }
          finally { setBusy(false); }
        }}>
          <ClientFields v={v} set={(p) => setV({ ...v, ...p })} />
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>Cancelar</Button>
            <Button type="submit" disabled={busy}>{busy && <Loader2Icon className="animate-spin" />} Guardar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function ArchiveDialog({ client, onClose, onDone }: { client: ClientRow; onClose: () => void; onDone: (jobs: number) => void | Promise<void> }) {
  const [reason, setReason] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader><DialogTitle>Arquivar {client.name}</DialogTitle>
          <DialogDescription>Toda a equipa deste cliente perde o acesso já, a agenda dos agentes pára e as execuções em fila são canceladas. Nada é apagado: podes recuperar depois.</DialogDescription></DialogHeader>
        <form className="flex flex-col gap-3" onSubmit={async (e) => {
          e.preventDefault(); setBusy(true); setErr("");
          try { const r = await archiveClient(client.id, reason); await onDone(r.jobs_cancelled ?? 0); }
          catch (e2) { setErr((e2 as Error).message); }
          finally { setBusy(false); }
        }}>
          <label className="flex flex-col gap-1 text-sm">Motivo<Textarea rows={2} value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} placeholder="Ex.: fim do contrato" /></label>
          <label className="flex flex-col gap-1 text-sm">Escreve <b>{client.id}</b> para confirmar<Input value={confirm} onChange={(e) => setConfirm(e.target.value)} /></label>
          {err && <p className="text-sm text-destructive" role="alert">{err}</p>}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>Cancelar</Button>
            <Button type="submit" variant="destructive" disabled={busy || reason.trim().length < 3 || confirm.trim() !== client.id}>{busy && <Loader2Icon className="animate-spin" />} Arquivar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
