"use client";

import { useEffect, useState } from "react";
import { RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import type { Access } from "@/lib/access";
import { fetchPrereqs, prereqGrid, setPrereq, type Prereqs } from "@/lib/workflow-prereqs";

/*
 * Pré-requisitos das transições de produção (FR-17-05, ADR-0051): por cliente, que condições têm de se verificar antes de
 * agendar, marcar gravado, passar a edição ou marcar pronto. O servidor recusa a transição e diz a causa e quem tem de agir.
 * "Marcar gravado × guião aprovado" é a mesma regra que "Só se gravam guiões aprovados" (acima): mudar uma muda a outra.
 */
export function WorkflowPrereqsCard({ access, version, onChanged }: { access: Access; version: boolean; onChanged: () => void }) {
  const [p, setP] = useState<Prereqs | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  useEffect(() => {
    let alive = true;
    fetchPrereqs(access).then((x) => { if (alive) { setP(x); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, rev, version]);

  const toggle = async (transition: string, requirement: string, enabled: boolean, label: string) => {
    setBusy(`${transition}:${requirement}`); setMsg(null);
    try {
      setP(await setPrereq(access, transition, requirement, enabled));
      setMsg({ ok: true, text: enabled ? `A partir de agora: ${label}.` : `Deixou de ser preciso: ${label}.` });
      if (transition === "production.recorded" && requirement === "script_approved") onChanged();
    } catch (e) { setMsg({ ok: false, text: (e as Error).message }); setRev((n) => n + 1); }
    finally { setBusy(null); }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Pré-requisitos das transições</CardTitle>
        <CardDescription>O que tem de estar feito antes de cada passo da produção. Voltar atrás nunca é bloqueado. Quem esbarra numa regra vê a causa e quem tem de agir.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        {err ? (
          <Alert variant="destructive"><AlertDescription className="flex items-center justify-between gap-2">{err}
            <Button size="sm" variant="outline" onClick={() => setRev((n) => n + 1)}><RotateCwIcon /> Tentar de novo</Button></AlertDescription></Alert>
        ) : !p ? <Skeleton className="h-40" /> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[32rem] border-collapse text-left">
              <thead>
                <tr className="border-b text-xs text-muted-foreground">
                  <th scope="col" className="py-2 pr-3 font-medium">Passo</th>
                  {p.catalog.requirements.map((r) => <th key={r.key} scope="col" className="px-2 py-2 font-medium">{r.label}</th>)}
                </tr>
              </thead>
              <tbody>
                {prereqGrid(p).map(({ transition, cells }) => (
                  <tr key={transition.key} className="border-b last:border-0">
                    <th scope="row" className="py-2 pr-3 font-medium">{transition.label}</th>
                    {cells.map((c, i) => {
                      const req = p.catalog.requirements[i];
                      const label = `${transition.label} exige ${req.label.toLowerCase()}`;
                      return (
                        <td key={req.key} className="px-2 py-2">
                          {c ? <Switch aria-label={label} checked={c.enabled} disabled={!p.can.manage || busy !== null}
                                       onCheckedChange={(v) => void toggle(transition.key, req.key, v, label)} />
                             : <span className="text-xs text-muted-foreground" aria-label="não se aplica">—</span>}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {p && !p.can.manage && <p className="text-xs text-muted-foreground">Só quem gere as definições deste cliente muda estas regras.</p>}
        {msg && <p role="status" className={msg.ok ? "text-muted-foreground" : "text-destructive"}>{msg.text}</p>}
      </CardContent>
    </Card>
  );
}
