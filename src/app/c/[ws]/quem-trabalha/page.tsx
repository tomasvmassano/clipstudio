"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangleIcon, CalendarClockIcon, CircleIcon, Loader2Icon, PlayIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { FlagGate } from "@/components/flag-gate";
import { useSession } from "@/components/session-provider";
import { WorkspaceGate } from "@/components/workspace-gate";
import { WsLink } from "@/components/ws-link";
import { selectCls } from "@/components/ops/queue-parts";
import type { Access } from "@/lib/access";
import {
  AVAILABILITY_LABEL, fetchTeamPresence, fmtAgo, fmtWhen, setAvailability, subscribePresence,
  type Availability, type Member, type TeamPresence,
} from "@/lib/ops";
import { cn } from "@/lib/utils";

/*
 * Quem trabalha em quê (OPS-04) com estados distintos (OPS-02): online (app aberta neste cliente), ativo (só com
 * consentimento), a trabalhar (tarefa iniciada pela própria pessoa) e estado escolhido. Nada disto mede horas.
 * Só pessoas e tarefas deste cliente (OPS-10); o servidor filtra tudo por cliente.
 */

export default function QuemTrabalhaPage() {
  const { wsRequested } = useSession();
  return (
    <FlagGate flag="ops.team_presence" ws={wsRequested}>
      <WorkspaceGate need="ops.presence">{(access) => <Team access={access} />}</WorkspaceGate>
    </FlagGate>
  );
}

const ROLE_LABEL: Record<string, string> = {
  workspace_owner: "Dono", workspace_admin: "Administração", manager: "Gestão", contributor: "Colaboração", reviewer: "Revisão", viewer: "Leitura",
};
const UNTIL = [
  { key: "", label: "Até mudar" },
  { key: "60", label: "Durante 1 hora" },
  { key: "240", label: "Durante 4 horas" },
  { key: "1440", label: "Durante 1 dia" },
];

function Team({ access }: { access: Access }) {
  const { mode, ws } = useSession();
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [data, setData] = useState<TeamPresence | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reload = useCallback(() => setRev((n) => n + 1), []);

  useEffect(() => {
    if (mode !== "user") return;
    let alive = true;
    fetchTeamPresence(access.ws).then((d) => { if (alive) { setData(d); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access.ws, mode, rev]);

  // atualiza a cada minuto e quando o canal privado avisa (no máximo uma leitura a cada 3 s)
  useEffect(() => {
    if (mode !== "user") return;
    const id = setInterval(reload, 60_000);
    const off = subscribePresence(access, () => {
      if (timer.current) return;
      timer.current = setTimeout(() => { timer.current = null; reload(); }, 3000);
    });
    return () => { clearInterval(id); off?.(); if (timer.current) { clearTimeout(timer.current); timer.current = null; } };
  }, [access, mode, reload]);

  if (mode === "code") {
    return <Alert><AlertDescription>Quem trabalha em quê precisa de uma conta com o teu email. O código de equipa não tem estado pessoal.</AlertDescription></Alert>;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Quem trabalha em quê</h1>
          <p className="text-sm text-muted-foreground">Equipa de {ws?.name}: estado, tarefa em curso, bloqueios e prazos. Só deste cliente.</p>
        </div>
        <Button size="sm" variant="outline" onClick={reload} aria-label="Atualizar"><RotateCwIcon /></Button>
      </div>

      <Card>
        <CardContent className="grid gap-1 py-3 text-xs text-muted-foreground sm:grid-cols-2">
          <span><b className="text-foreground">Online</b>: tem a app aberta neste cliente (atualiza em até 2 minutos).</span>
          <span><b className="text-foreground">Ativo</b>: mexeu na app nos últimos 5 minutos, só se a pessoa aceitou mostrar.</span>
          <span><b className="text-foreground">A trabalhar</b>: tem uma tarefa que ela própria pôs em curso. Sair da app não a fecha.</span>
          <span><b className="text-foreground">Estado</b>: escolhido pela pessoa. Nada disto conta horas nem mede produtividade.</span>
        </CardContent>
      </Card>

      {err && (
        <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center justify-between gap-2">
          <span>Não consegui carregar a equipa: {err}</span>
          <Button size="sm" variant="outline" onClick={reload}><RotateCwIcon /> Tentar de novo</Button>
        </AlertDescription></Alert>
      )}

      {!data ? (
        !err && <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3" aria-busy="true" aria-label="A carregar">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-44" />)}</div>
      ) : (
        <>
          <MyStatus me={data.me} onSaved={reload} />
          <div className="flex flex-wrap gap-2" aria-label="Totais">
            {([["members", "pessoas"], ["online", "online"], ["active", "ativas"], ["working", "a trabalhar"], ["available", "disponíveis"],
               ["busy", "ocupadas"], ["away", "ausentes"], ["blocked", "com bloqueios"]] as const).map(([k, l]) => (
              <span key={k} className={cn("inline-flex items-baseline gap-1.5 rounded-full border bg-background px-3 py-1 text-sm", k === "blocked" && data.counts.blocked > 0 && "border-destructive/60")}>
                <b className="tabular-nums">{data.counts[k]}</b><span className="text-muted-foreground">{l}</span>
              </span>
            ))}
          </div>
          {data.members.length === 0 ? (
            <Alert><AlertDescription>Ainda não há pessoas atribuídas a este cliente.</AlertDescription></Alert>
          ) : (
            <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3" aria-label="Pessoas">
              {data.members.map((m) => <MemberCard key={m.user_id} m={m} tz={tz} />)}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

function MyStatus({ me, onSaved }: { me: TeamPresence["me"]; onSaved: () => void }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const save = async (patch: Parameters<typeof setAvailability>[0]) => {
    setBusy(true); setErr("");
    try { await setAvailability(patch); onSaved(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">O meu estado</CardTitle></CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        {!me.member && <p className="text-muted-foreground">Não apareces nos cartões porque não estás atribuído a este cliente. O teu estado vale nos clientes onde estás.</p>}
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1">Estado
            <select className={selectCls} disabled={busy} value={me.status ?? ""}
              onChange={(e) => save({ status: (e.target.value || null) as Availability | null, until: null })}>
              <option value="">Sem estado</option>
              {(Object.keys(AVAILABILITY_LABEL) as Availability[]).map((k) => <option key={k} value={k}>{AVAILABILITY_LABEL[k]}</option>)}
            </select>
          </label>
          {me.status && (
            <label className="flex flex-col gap-1">Durante
              <select className={selectCls} disabled={busy} value="" onChange={(e) => {
                const min = Number(e.target.value);
                save({ status: me.status, until: min ? new Date(Date.now() + min * 60000).toISOString() : null });
              }}>
                <option value="" disabled>{me.until ? `Até ${new Date(me.until).toLocaleString("pt-PT", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })}` : "Até mudar"}</option>
                {UNTIL.map((u) => <option key={u.key} value={u.key || "0"}>{u.label}</option>)}
              </select>
            </label>
          )}
          {busy && <Loader2Icon className="mb-2 size-4 animate-spin" aria-label="A guardar" />}
        </div>
        <label className="flex items-center gap-2">
          <Switch checked={me.share_activity} disabled={busy} onCheckedChange={(v) => save({ share_activity: v })} aria-describedby="share-help" />
          Mostrar quando estou ativo
        </label>
        <p id="share-help" className="text-xs text-muted-foreground">Desligado, os outros só veem se tens a app aberta. Ao desligar, a última atividade guardada é apagada.</p>
        {err && <p role="alert" className="text-destructive">{err}</p>}
      </CardContent>
    </Card>
  );
}

function MemberCard({ m, tz }: { m: Member; tz: string }) {
  return (
    <li>
      <Card className="h-full" data-member={m.email}>
        <CardContent className="flex h-full flex-col gap-2 py-3 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1.5" title={m.online ? "Online" : "Não está online"}>
              <CircleIcon aria-hidden className={cn("size-2.5", m.online ? "fill-emerald-500 text-emerald-500" : "text-muted-foreground")} />
              <span className="sr-only">{m.online ? "Online" : "Não está online"}</span>
            </span>
            <span className="min-w-0 flex-1 truncate font-medium">{m.label}{m.is_me ? " (tu)" : ""}</span>
            <Badge variant="outline" className="text-[11px]">{m.affiliation === "agency_staff" ? "Agência" : "Cliente"}</Badge>
          </div>
          <div className="flex flex-wrap gap-1.5 text-xs">
            <Badge variant={m.online ? "secondary" : "outline"}>{m.online ? (m.active ? "Online e ativo" : "Online") : "Offline"}</Badge>
            {m.availability && <Badge variant={m.availability === "available" ? "secondary" : "outline"}>{AVAILABILITY_LABEL[m.availability]}{m.availability_until ? ` até ${fmtWhen(m.availability_until, tz)}` : ""}</Badge>}
            <Badge variant="outline">{ROLE_LABEL[m.role] ?? m.role}{m.job_title ? ` · ${m.job_title}` : ""}</Badge>
          </div>
          {m.current ? (
            <WsLink href={`/tarefas?task=${m.current.id}`} className="rounded-md border p-2 outline-none hover:bg-muted/60 focus-visible:ring-2 focus-visible:ring-ring">
              <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><PlayIcon className="size-3.5" aria-hidden /> A trabalhar em</span>
              <span className="block truncate">{m.current.title}</span>
              {m.current.content && (
                <span className="block truncate text-xs text-muted-foreground">
                  Guião {m.current.content.n}{m.current.content.tema ? ` · ${m.current.content.tema}` : ""}{m.current.content.project ? ` · ${m.current.content.project}` : ""}
                </span>
              )}
              {m.current.due_at && <span className="block text-xs text-muted-foreground">Prazo {fmtWhen(m.current.due_at, tz)}</span>}
            </WsLink>
          ) : (
            <p className="text-xs text-muted-foreground">Sem tarefa em curso.</p>
          )}
          <p className="text-xs text-muted-foreground">
            {m.open} aberta{m.open === 1 ? "" : "s"}
            {m.overdue > 0 && <span className="text-destructive"> · {m.overdue} atrasada{m.overdue === 1 ? "" : "s"}</span>}
            {m.next_due && <> · <CalendarClockIcon className="inline size-3" aria-hidden /> próximo prazo {fmtWhen(m.next_due, tz)}</>}
          </p>
          {m.blocked_tasks.length > 0 && (
            <ul className="flex flex-col gap-1" aria-label={`Bloqueios de ${m.label}`}>
              {m.blocked_tasks.map((b) => (
                <li key={b.id}>
                  <WsLink href={`/tarefas?task=${b.id}`} className="flex items-start gap-1.5 text-xs text-destructive hover:underline">
                    <AlertTriangleIcon className="mt-0.5 size-3.5 shrink-0" aria-hidden />
                    <span className="min-w-0 truncate">{b.title}{b.reason ? `: ${b.reason}` : ""}</span>
                  </WsLink>
                </li>
              ))}
            </ul>
          )}
          <p className="mt-auto text-[11px] text-muted-foreground">Última atualização em tarefas: {fmtAgo(m.last_update)}</p>
        </CardContent>
      </Card>
    </li>
  );
}
