"use client";

import { useEffect, useState } from "react";
import { ArrowLeftIcon, Loader2Icon, LockIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { WsLink } from "@/components/ws-link";
import { groupBy, suppressedLine, type NotifChannel } from "@/lib/notif-format";
import { fetchWsNotif, isFlagOff, isForbidden, setWsNotif, type WsEvent, type WsNotifSettings } from "@/lib/notif-prefs";

/**
 * Definições → Notificações (FR-15-05, flag notifications.prefs). Que eventos geram notificação neste cliente e em que
 * canal, e quais são obrigatórios. Quem não tem settings.manage vê sem mudar; o servidor decide sempre.
 */
export function WsNotifSettingsPage({ ws }: { ws: string }) {
  const [s, setS] = useState<WsNotifSettings | null>(null);
  const [err, setErr] = useState<{ text: string; forbidden: boolean; off: boolean } | null>(null);
  const [rev, setRev] = useState(0);
  const [busy, setBusy] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    let alive = true;
    fetchWsNotif(ws)
      .then((x) => { if (alive) { setS(x); setErr(null); } })
      .catch((e: Error) => { if (alive) setErr({ text: e.message, forbidden: isForbidden(e), off: isFlagOff(e) }); });
    return () => { alive = false; };
  }, [ws, rev]);

  const header = (
    <div className="flex flex-col gap-1">
      <WsLink href="/definicoes" className="inline-flex w-fit items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeftIcon className="size-4" /> Definições
      </WsLink>
      <h1 className="text-2xl font-semibold tracking-tight">Notificações</h1>
    </div>
  );

  if (err) {
    return (
      <div className="flex flex-col gap-4">{header}
        <Alert variant={err.forbidden || err.off ? "default" : "destructive"} data-notif-error>
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            {err.forbidden ? "Não tens acesso às definições deste cliente." : err.text}
            {!err.forbidden && <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button>}
          </AlertDescription>
        </Alert>
      </div>
    );
  }
  if (!s) return <div className="flex flex-col gap-4">{header}<Skeleton className="h-96" /></div>;
  if (!s.enabled) {
    return <div className="flex flex-col gap-4">{header}<Alert data-notif-off><AlertDescription>Esta funcionalidade ainda está em teste e não está ligada para ti neste cliente.</AlertDescription></Alert></div>;
  }

  const change = async (ev: WsEvent, channel: NotifChannel["key"], enabled: boolean, required: boolean) => {
    const k = `${ev.kind}:${channel}`;
    setBusy(k); setMsg(null);
    try { setS(await setWsNotif(ws, ev.kind, channel, enabled, required)); setMsg({ ok: true, text: `Guardado: ${ev.label}.` }); }
    catch (e) { setMsg({ ok: false, text: (e as Error).message }); }
    finally { setBusy(""); }
  };
  const unavailable = s.channels.filter((c) => !c.available);

  return (
    <div className="flex flex-col gap-4" data-notif-settings>
      {header}
      <p className="text-sm text-muted-foreground">
        {s.can_manage
          ? "Escolhe que eventos geram notificação para a equipa deste cliente. Cada pessoa pode desligar o que não for obrigatório no seu perfil. As mudanças ficam no histórico."
          : "Só quem gere as definições deste cliente pode mudar isto. As tuas preferências pessoais estão no perfil."}
      </p>
      {unavailable.length > 0 && (
        <Alert data-notif-unavailable>
          <AlertDescription className="flex flex-col gap-1">
            {unavailable.map((c) => <span key={c.key}><b>{c.label}: indisponível.</b> {c.unavailable_reason}</span>)}
          </AlertDescription>
        </Alert>
      )}
      {msg && <p className={`text-sm ${msg.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"}`} role={msg.ok ? "status" : "alert"}>{msg.text}</p>}
      {s.events.length === 0 && <Alert><AlertDescription>Ainda não há tipos de notificação.</AlertDescription></Alert>}
      {groupBy(s.events).map((g) => (
        <Card key={g.group}>
          <CardHeader><CardTitle className="text-base">{g.label}</CardTitle></CardHeader>
          <CardContent className="flex flex-col divide-y">
            {g.events.map((ev) => (
              <div key={ev.kind} className="flex flex-col gap-2 py-3 first:pt-0 last:pb-0" data-notif-event={ev.kind}>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{ev.label}</span>
                  {ev.mandatory && <Badge variant="secondary"><LockIcon /> Obrigatória</Badge>}
                </div>
                <p className="text-xs text-muted-foreground">{ev.description} Recebe: {ev.recipients}.{ev.mandatory && ev.mandatory_reason ? ` ${ev.mandatory_reason}` : ""}</p>
                <div className="flex flex-wrap gap-x-6 gap-y-2">
                  {ev.channels.map((c) => {
                    const def = s.channels.find((x) => x.key === c.channel);
                    const k = `${ev.kind}:${c.channel}`;
                    const lockedByCatalog = ev.mandatory && c.channel === "in_app";
                    const id = `nw-${ev.kind}-${c.channel}`;
                    return (
                      <div key={c.channel} className="flex flex-wrap items-center gap-2 text-sm">
                        <Switch id={id} checked={c.enabled} disabled={!s.can_manage || lockedByCatalog || c.required || !!busy}
                          data-notif-switch={k}
                          onCheckedChange={(v) => void change(ev, c.channel, v, false)} />
                        <label htmlFor={id}>{def?.label ?? c.channel}</label>
                        {def && !def.available && <Badge variant="outline">indisponível</Badge>}
                        {busy === k && <Loader2Icon className="size-4 animate-spin" aria-label="A guardar" />}
                        {c.channel === "in_app" && !lockedByCatalog && (s.can_manage || c.required) && (
                          <label className="flex items-center gap-1 text-xs text-muted-foreground">
                            <input type="checkbox" className="size-4" checked={c.required} disabled={!s.can_manage || !c.enabled || !!busy}
                              data-notif-required={ev.kind}
                              onChange={(e) => void change(ev, "in_app", true, e.target.checked)} />
                            obrigatória neste cliente
                          </label>
                        )}
                      </div>
                    );
                  })}
                </div>
                {s.can_manage && suppressedLine(s.suppressed_30d, ev.kind) && (
                  <p className="text-xs text-muted-foreground" data-notif-suppressed={ev.kind}>{suppressedLine(s.suppressed_30d, ev.kind)}</p>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      ))}
      <Card>
        <CardHeader><CardTitle className="text-base">Como funciona</CardTitle>
          <CardDescription>Uma notificação desligada não é criada; fica só contada (por dia), para se ver o efeito aqui. As obrigatórias chegam sempre, mesmo a quem silenciou o cliente.</CardDescription></CardHeader>
      </Card>
    </div>
  );
}
