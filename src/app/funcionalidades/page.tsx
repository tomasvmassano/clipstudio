"use client";

import { useCallback, useEffect, useState } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSession } from "@/components/session-provider";
import { fetchFlagsAdmin, setFlag, STAGE_LABEL, type FlagStage, type FlagsAdmin } from "@/lib/flags";

/** Funcionalidades em teste (MIG-09): ligar módulos novos cliente a cliente. Só o dono da agência. */
export default function FuncionalidadesPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("flags.manage")) return <Alert><AlertDescription>Só o dono da agência liga e desliga funcionalidades em teste.</AlertDescription></Alert>;
  return <Funcionalidades />;
}

const STAGES: FlagStage[] = ["off", "owner", "agency", "all"];

function Funcionalidades() {
  const [data, setData] = useState<FlagsAdmin | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState("");
  const load = useCallback(() => {
    fetchFlagsAdmin().then((d) => { setData(d); setErr(""); }).catch((e: Error) => setErr(e.message));
  }, []);
  useEffect(() => {
    let alive = true;
    fetchFlagsAdmin().then((d) => { if (alive) { setData(d); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, []);

  const change = async (key: string, ws: string | null, v: string) => {
    setBusy(`${key}:${ws ?? ""}`); setErr("");
    try { setData(await setFlag(key, ws, v === "" ? null : (v as FlagStage))); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Funcionalidades em teste</h1>
          <p className="text-sm text-muted-foreground">Os módulos novos entram só para ti. Liga-os para a equipa da agência ou para todos, cliente a cliente. Isto não dá permissões: quem não tem acesso continua sem ele.</p>
        </div>
        <Button variant="outline" size="sm" onClick={load}><RotateCwIcon />Atualizar</Button>
      </div>
      {err && <Alert variant="destructive"><AlertDescription className="flex flex-wrap items-center gap-2">{err}<Button size="sm" variant="outline" onClick={load}>Tentar de novo</Button></AlertDescription></Alert>}
      {!data && !err && <Skeleton className="h-64" />}
      {data && data.flags.length === 0 && <p className="text-sm text-muted-foreground">Não há funcionalidades em teste neste momento.</p>}
      {data && data.flags.length > 0 && (
        <div className="overflow-x-auto rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Funcionalidade</TableHead>
                <TableHead>Agência (todos os clientes)</TableHead>
                {data.clients.map((c) => <TableHead key={c.id}>{c.name}</TableHead>)}
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.flags.map((f) => (
                <TableRow key={f.key} data-flag={f.key}>
                  <TableCell className="min-w-[14rem] align-top">
                    <div className="font-medium">{f.label}</div>
                    <div className="text-xs text-muted-foreground">{f.module} · {f.key}</div>
                    {f.description && <div className="mt-1 text-xs text-muted-foreground">{f.description}</div>}
                  </TableCell>
                  <TableCell className="align-top">
                    <select aria-label={`${f.label}: agência`} className="h-8 rounded-md border bg-background px-2 text-sm" disabled={!!busy}
                      value={f.agency_stage ?? ""} onChange={(e) => void change(f.key, null, e.target.value)}>
                      <option value="">Por defeito ({STAGE_LABEL[f.default_stage].toLowerCase()})</option>
                      {STAGES.map((s) => <option key={s} value={s}>{STAGE_LABEL[s]}</option>)}
                    </select>
                  </TableCell>
                  {data.clients.map((c) => (
                    <TableCell key={c.id} className="align-top">
                      {f.scope === "org" ? <span className="text-xs text-muted-foreground">só na agência</span> : (
                        <select aria-label={`${f.label}: ${c.name}`} className="h-8 rounded-md border bg-background px-2 text-sm" disabled={!!busy}
                          value={f.clients[c.id] ?? ""} onChange={(e) => void change(f.key, c.id, e.target.value)}>
                          <option value="">Como a agência</option>
                          {STAGES.map((s) => <option key={s} value={s}>{STAGE_LABEL[s]}</option>)}
                        </select>
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
