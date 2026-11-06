"use client";

import { useCallback, useEffect, useState } from "react";
import { Loader2Icon, LogOutIcon, MonitorIcon, RotateCwIcon, SmartphoneIcon, TabletIcon, HelpCircleIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useSession } from "@/components/session-provider";
import { supabase } from "@/lib/supabase";
import { mySessions, securityEvent, terminateOtherSessions, terminateSession } from "@/lib/profile";
import { agoLabel, parseDevice, sortSessions, type DeviceKind, type SessionRow } from "@/lib/session-format";

const ICON: Record<DeviceKind, typeof MonitorIcon> = { desktop: MonitorIcon, mobile: SmartphoneIcon, tablet: TabletIcon, unknown: HelpCircleIcon };
const fmt = (d: string) => new Date(d).toLocaleString("pt-PT", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

type Note = { ok: boolean; text: string } | null;

/**
 * Sessões e dispositivos ativos (W10-08, FR-14-03). A lista e as ações vêm de RPCs que só tocam nas sessões da própria
 * pessoa; terminar uma sessão corta o acesso dela logo no pedido seguinte (o servidor verifica a sessão em cada pedido).
 */
export function SessionsCard({ onChanged }: { onChanged?: () => void }) {
  const { signOut } = useSession();
  const [rows, setRows] = useState<SessionRow[] | null>(null);
  const [loadErr, setLoadErr] = useState("");
  const [busy, setBusy] = useState<string>("");            // id da sessão em curso, "others" ou ""
  const [confirm, setConfirm] = useState<string>("");      // id à espera de confirmação, "others" ou ""
  const [note, setNote] = useState<Note>(null);

  const load = useCallback(async () => {
    setLoadErr("");
    try { setRows(sortSessions(await mySessions())); }
    catch (e) { setLoadErr((e as Error).message || "Não foi possível carregar as sessões."); setRows((r) => r ?? []); }
  }, []);
  useEffect(() => { queueMicrotask(() => void load()); }, [load]);

  const others = rows?.filter((r) => !r.current) ?? [];

  const endOne = async (r: SessionRow) => {
    setBusy(r.id); setNote(null); setConfirm("");
    try {
      if (r.current) {
        // esta: o signOut local do Supabase Auth apaga esta sessão no servidor e deixa as outras abertas
        await securityEvent("security.signed_out_here");
        const { error } = await supabase().auth.signOut({ scope: "local" });
        if (error) throw new Error("Não foi possível terminar esta sessão. Tenta outra vez.");
        await signOut();
        return;
      }
      await terminateSession(r.id);
      setRows((l) => l?.filter((x) => x.id !== r.id) ?? l);
      setNote({ ok: true, text: `Sessão terminada: ${parseDevice(r.user_agent).label}.` });
      onChanged?.();
    } catch (e) {
      setNote({ ok: false, text: (e as Error).message });
      void load();
    } finally { setBusy(""); }
  };

  const endOthers = async () => {
    setBusy("others"); setNote(null); setConfirm("");
    try {
      const n = await terminateOtherSessions();
      setNote({ ok: true, text: n === 0 ? "Não havia outras sessões abertas." : n === 1 ? "Terminada 1 sessão noutro dispositivo." : `Terminadas ${n} sessões noutros dispositivos.` });
      await load();
      onChanged?.();
    } catch (e) { setNote({ ok: false, text: (e as Error).message }); }
    finally { setBusy(""); }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sessões e dispositivos</CardTitle>
        <CardDescription>Onde tens a conta aberta agora. Se não reconheces um dispositivo, termina essa sessão e muda a palavra-passe.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {rows === null && <div className="flex flex-col gap-2" aria-busy="true"><Skeleton className="h-14" /><Skeleton className="h-14" /></div>}
        {loadErr && (
          <div className="flex flex-wrap items-center gap-2 text-sm" role="alert">
            <span className="text-destructive">{loadErr}</span>
            <Button size="sm" variant="outline" onClick={() => void load()}><RotateCwIcon /> Tentar outra vez</Button>
          </div>
        )}
        {rows && rows.length === 0 && !loadErr && <p className="text-sm text-muted-foreground">Não encontrámos sessões ativas. Se acabaste de entrar, recarrega a página.</p>}
        {rows && rows.length > 0 && (
          <ul className="flex flex-col divide-y rounded-md border" aria-label="Sessões ativas">
            {rows.map((r) => {
              const d = parseDevice(r.user_agent);
              const Icon = ICON[d.kind];
              return (
                <li key={r.id} className="flex flex-col gap-2 p-3 sm:flex-row sm:items-center sm:justify-between" data-testid="session-row">
                  <div className="flex min-w-0 items-start gap-3">
                    <Icon className="mt-0.5 size-5 shrink-0 text-muted-foreground" aria-hidden />
                    <div className="flex min-w-0 flex-col text-sm">
                      <span className="flex flex-wrap items-center gap-2 font-medium">
                        {d.label}
                        {r.current && <Badge variant="secondary">Esta sessão</Badge>}
                      </span>
                      <span className="text-muted-foreground">
                        {r.current ? "Ativa agora" : `Última atividade ${agoLabel(r.last_active_at)}`}
                        {r.ip ? ` · IP ${r.ip}` : ""}
                      </span>
                      <span className="text-xs text-muted-foreground">Entrou a {fmt(r.created_at)}</span>
                    </div>
                  </div>
                  {confirm === r.id ? (
                    <div className="flex shrink-0 gap-2">
                      <Button size="sm" variant="destructive" disabled={!!busy} onClick={() => void endOne(r)}>
                        {busy === r.id && <Loader2Icon className="animate-spin" />} {r.current ? "Sim, sair daqui" : "Sim, terminar"}
                      </Button>
                      <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => setConfirm("")}>Cancelar</Button>
                    </div>
                  ) : (
                    <Button size="sm" variant="outline" className="shrink-0" disabled={!!busy} onClick={() => setConfirm(r.id)}
                      aria-label={r.current ? "Terminar esta sessão" : `Terminar a sessão ${d.label}`}>
                      <LogOutIcon /> {r.current ? "Terminar esta sessão" : "Terminar"}
                    </Button>
                  )}
                </li>
              );
            })}
          </ul>
        )}
        {rows && others.length > 0 && (
          confirm === "others" ? (
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span>Terminar {others.length === 1 ? "a outra sessão" : `as ${others.length} outras sessões`}? Esta fica aberta.</span>
              <Button size="sm" variant="destructive" disabled={!!busy} onClick={() => void endOthers()}>
                {busy === "others" && <Loader2Icon className="animate-spin" />} Sim, terminar
              </Button>
              <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => setConfirm("")}>Cancelar</Button>
            </div>
          ) : (
            <div><Button variant="outline" disabled={!!busy} onClick={() => setConfirm("others")}><LogOutIcon /> Terminar todas as outras</Button></div>
          )
        )}
        {note && <p className={`text-sm ${note.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"}`} role={note.ok ? "status" : "alert"}>{note.text}</p>}
        <p className="text-xs text-muted-foreground">
          Um dispositivo com a sessão terminada perde o acesso aos dados no pedido seguinte e tem de voltar a entrar.
        </p>
      </CardContent>
    </Card>
  );
}
