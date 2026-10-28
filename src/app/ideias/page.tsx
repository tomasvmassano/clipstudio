"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { fetchIdeas } from "@/lib/data";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import type { Idea } from "@/lib/types";

const FONTE: Record<string, string> = { reporter: "Repórter", curious: "Curioso", philosopher: "Filósofo", manual: "Manual" };

export default function IdeiasPage() {
  return <WorkspaceGate need="sources.read">{(access) => <Ideias access={access} />}</WorkspaceGate>;
}

function Ideias({ access }: { access: Access }) {
  const [ideas, setIdeas] = useState<Idea[] | null>(null);
  const [err, setErr] = useState("");
  useEffect(() => {
    let alive = true;
    fetchIdeas(access).then((x) => { if (alive) setIdeas(x); }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access]);
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Ideias</h1>
        <p className="text-sm text-muted-foreground">O que o Repórter, o Curioso e o Filósofo trouxeram. Entram em 35% dos guiões do dia.</p>
      </div>
      {err && <Alert variant="destructive"><AlertDescription>{err}</AlertDescription></Alert>}
      {!ideas ? (
        <div className="grid gap-3 md:grid-cols-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-32" />)}</div>
      ) : ideas.length === 0 ? (
        <Alert><AlertDescription>Ainda não há ideias. Aparecem aqui depois da primeira corrida diária dos agentes.</AlertDescription></Alert>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {ideas.map((i) => {
            const d = (i.data ?? {}) as Record<string, unknown>;
            const expired = i.expires_at && i.expires_at < new Date().toISOString();
            return (
              <Card key={i.id} className={expired ? "opacity-60" : ""}>
                <CardContent className="flex flex-col gap-2 p-4">
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    <Badge variant="outline">{FONTE[i.fonte_tipo ?? ""] ?? i.fonte_tipo}</Badge>
                    {i.categoria && <Badge variant="secondary">{i.categoria}</Badge>}
                    {i.status && <Badge variant={i.status === "used" ? "default" : "outline"}>{i.status}</Badge>}
                    {expired && <Badge variant="destructive">expirada</Badge>}
                    <span className="ml-auto text-muted-foreground">{i.created_at.slice(0, 10)}</span>
                  </div>
                  <div className="font-semibold">{i.titulo}</div>
                  {i.take_numeiro && <p className="text-sm text-muted-foreground">{i.take_numeiro}</p>}
                  {typeof d.fonte_url === "string" && (
                    <a href={d.fonte_url} target="_blank" rel="noopener" className="truncate text-xs underline underline-offset-2">{d.fonte_url}</a>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
