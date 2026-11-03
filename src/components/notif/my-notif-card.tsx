"use client";

import { useEffect, useState } from "react";
import { BellOffIcon, Loader2Icon, LockIcon, RotateCwIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { fmtInTz, groupBy, MUTE_OPTIONS, muteUntil, personalLock, suppressedLine } from "@/lib/notif-format";
import { fetchMyNotif, fetchMyNotifWorkspaces, isForbidden, setMyMute, setMyNotif, type MyEvent, type MyNotifPrefs, type MyNotifWorkspace } from "@/lib/notif-prefs";

const selectCls = "h-9 rounded-md border bg-background px-2 text-sm disabled:opacity-60";

/**
 * Perfil → Notificações (FR-14-02, flag notifications.prefs). Por cliente: ligar/desligar por evento e canal dentro do que
 * o cliente permite, e silenciar o cliente. Sem a flag em nenhum cliente não aparece (o perfil fica como antes).
 */
export function MyNotifCard() {
  const [list, setList] = useState<MyNotifWorkspace[] | null>(null);
  const [listErr, setListErr] = useState("");
  const [ws, setWs] = useState("");
  const [res, setRes] = useState<{ ws: string; p: MyNotifPrefs | null; err: string } | null>(null);
  const [busy, setBusy] = useState("");
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const [mute, setMute] = useState("8h");
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchMyNotifWorkspaces()
      .then((l) => { if (alive) { setList(l); setListErr(""); setWs((cur) => (cur && l.some((x) => x.id === cur) ? cur : l[0]?.id ?? "")); } })
      .catch((e: Error) => { if (alive) setListErr(e.message); });
    return () => { alive = false; };
  }, [attempt]);

  useEffect(() => {
    if (!ws) return;
    let alive = true;
    fetchMyNotif(ws)
      .then((x) => { if (alive) setRes({ ws, p: x, err: "" }); })
      .catch((e: Error) => { if (alive) setRes({ ws, p: null, err: isForbidden(e) ? "Já não tens acesso a este cliente." : e.message }); });
    return () => { alive = false; };
  }, [ws, attempt]);

  if (listErr) {
    return (
      <Card><CardHeader><CardTitle>Notificações</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-center gap-2 text-sm"><span className="text-destructive" role="alert">Não consegui ver as tuas notificações: {listErr}</span>
          <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></CardContent></Card>
    );
  }
  if (!list || list.length === 0) return null;
  const cur = res && res.ws === ws ? res : null;
  const p = cur?.p ?? null;
  const err = cur?.err ?? "";   // a carregar ou desligada em todos os clientes: o perfil fica como antes

  const run = async (key: string, fn: () => Promise<MyNotifPrefs>, ok: string) => {
    setBusy(key); setNote(null);
    try { const x = await fn(); setRes({ ws, p: x, err: "" }); setNote({ ok: true, text: ok }); if (key === "mute") setAttempt((n) => n + 1); }
    catch (e) { setNote({ ok: false, text: (e as Error).message }); }
    finally { setBusy(""); }
  };

  return (
    <Card data-my-notif>
      <CardHeader>
        <CardTitle>Notificações</CardTitle>
        <CardDescription>Escolhe o que te chega em cada cliente. As obrigatórias (atribuições, erros de automação para quem gere e as que o cliente marcou) chegam sempre.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 text-sm">
        <label className="flex flex-col gap-1 font-medium sm:w-72">Cliente
          <select aria-label="Cliente das notificações" className={selectCls} value={ws} disabled={!!busy} data-my-notif-ws
            onChange={(e) => setWs(e.target.value)}>
            {list.map((w) => <option key={w.id} value={w.id}>{w.name}{w.muted ? " (silenciado)" : ""}</option>)}
          </select>
        </label>
        {err && (
          <div className="flex flex-wrap items-center gap-2"><span className="text-destructive" role="alert">{err}</span>
            <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></div>
        )}
        {!err && !p && <Skeleton className="h-40" />}
        {p && !p.enabled && <p className="text-muted-foreground">Esta funcionalidade ainda está em teste e não está ligada para ti neste cliente.</p>}
        {p && p.enabled && (
          <>
            <div className="flex flex-wrap items-center gap-2 rounded-md border p-3" data-my-notif-mute>
              <BellOffIcon className="size-4 text-muted-foreground" />
              {p.muted ? (
                <>
                  <span>Silenciado {p.muted_until ? `até ${fmtInTz(p.muted_until, p.workspace.timezone)} (hora do cliente)` : "até voltares a ligar"}.</span>
                  <Button size="sm" variant="outline" disabled={!!busy} data-my-notif-unmute
                    onClick={() => void run("mute", () => setMyMute(ws, false, null), "Notificações deste cliente ligadas outra vez.")}>
                    {busy === "mute" && <Loader2Icon className="animate-spin" />}Voltar a ligar</Button>
                </>
              ) : (
                <>
                  <span>Silenciar {p.workspace.name}</span>
                  <select aria-label="Durante quanto tempo" className={selectCls} value={mute} disabled={!!busy} onChange={(e) => setMute(e.target.value)}>
                    {MUTE_OPTIONS.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
                  </select>
                  <Button size="sm" variant="outline" disabled={!!busy} data-my-notif-mute-go
                    onClick={() => void run("mute", () => setMyMute(ws, true, muteUntil(mute)), "Cliente silenciado. As obrigatórias continuam a chegar.")}>
                    {busy === "mute" && <Loader2Icon className="animate-spin" />}Silenciar</Button>
                </>
              )}
            </div>
            {p.channels.filter((c) => !c.available).map((c) => (
              <p key={c.key} className="text-xs text-muted-foreground"><b>{c.label}: indisponível.</b> {c.unavailable_reason}</p>
            ))}
            {p.events.length === 0 && <p className="text-muted-foreground">Ainda não há tipos de notificação.</p>}
            {groupBy(p.events).map((g) => (
              <div key={g.group} className="flex flex-col gap-2">
                <span className="font-medium">{g.label}</span>
                {g.events.map((ev) => <EventRow key={ev.kind} ev={ev} p={p} busy={busy}
                  onChange={(ch, v) => void run(`${ev.kind}:${ch}`, () => setMyNotif(ws, ev.kind, ch, v), `Guardado: ${ev.label}.`)} />)}
              </div>
            ))}
            {note && <p className={note.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"} role={note.ok ? "status" : "alert"}>{note.text}</p>}
          </>
        )}
      </CardContent>
    </Card>
  );
}

function EventRow({ ev, p, busy, onChange }: {
  ev: MyEvent; p: Extract<MyNotifPrefs, { enabled: true }>; busy: string; onChange: (ch: MyEvent["channels"][number]["channel"], v: boolean) => void;
}) {
  const sup = suppressedLine(p.suppressed_30d, ev.kind);
  return (
    <div className="flex flex-col gap-1 border-b pb-2 last:border-0" data-my-notif-event={ev.kind}>
      <div className="flex flex-wrap items-center gap-2">
        <span>{ev.label}</span>
        {ev.channels.some((c) => c.locked) && <Badge variant="secondary"><LockIcon /> Obrigatória</Badge>}
      </div>
      <div className="flex flex-wrap gap-x-6 gap-y-2">
        {ev.channels.map((c) => {
          const def = p.channels.find((x) => x.key === c.channel);
          const lock = personalLock(c, ev.mandatory ? ev.mandatory_reason : null);
          const id = `mn-${ev.kind}-${c.channel}`;
          return (
            <div key={c.channel} className="flex flex-wrap items-center gap-2" title={lock ?? undefined}>
              <Switch id={id} checked={c.effective} disabled={!!lock || !!busy} data-my-notif-switch={`${ev.kind}:${c.channel}`}
                onCheckedChange={(v) => onChange(c.channel, v)} />
              <label htmlFor={id}>{def?.label ?? c.channel}</label>
              {def && !def.available && <Badge variant="outline">indisponível</Badge>}
              {busy === `${ev.kind}:${c.channel}` && <Loader2Icon className="size-4 animate-spin" aria-label="A guardar" />}
            </div>
          );
        })}
      </div>
      {ev.channels.map((c) => ({ c, lock: personalLock(c, ev.mandatory ? ev.mandatory_reason : null) }))
        .filter((x) => x.lock && x.c.channel === "in_app")
        .map((x) => <p key={x.c.channel} className="text-xs text-muted-foreground">{x.lock}</p>)}
      {sup && <p className="text-xs text-muted-foreground">{sup}</p>}
    </div>
  );
}
