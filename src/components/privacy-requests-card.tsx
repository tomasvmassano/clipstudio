"use client";

import { useEffect, useState } from "react";
import { Loader2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { fetchPrivacyRequests, resolvePrivacyRequest, type PrivacyRequest } from "@/lib/learn";

const fmt = (d: string) => new Date(d).toLocaleDateString("pt-PT", { day: "numeric", month: "short", year: "numeric" });

/**
 * Pedidos de eliminação de dados (FR-14-05), só para quem tem privacy.manage (dono da agência). Tratar é registar o
 * que foi feito; a app não apaga nada sozinha. Sem pedidos, o cartão não aparece.
 */
export function PrivacyRequestsCard() {
  const [items, setItems] = useState<PrivacyRequest[] | null>(null);
  const [err, setErr] = useState("");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let alive = true;
    fetchPrivacyRequests().then((r) => { if (alive) { setItems(r.items); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [attempt]);
  if (err) {
    return (
      <Card className="shadow-none dark:ring-0"><CardHeader><CardTitle>Pedidos de eliminação</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-center gap-2 text-sm"><span className="text-destructive" role="alert">Não consegui carregar: {err}</span>
          <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}>Tentar de novo</Button></CardContent></Card>
    );
  }
  if (!items || items.length === 0) return null;
  return (
    <Card className="shadow-none dark:ring-0" data-privacy-requests>
      <CardHeader>
        <CardTitle>Pedidos de eliminação ({items.filter((i) => i.status === "pendente").length} pendentes)</CardTitle>
        <CardDescription>Trata cada pedido conforme a política de dados e regista o que foi feito. A app não apaga nada sozinha.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col divide-y p-0">
        {items.map((r) => <Row key={r.id} r={r} onDone={setItems} />)}
      </CardContent>
    </Card>
  );
}

function Row({ r, onDone }: { r: PrivacyRequest; onDone: (i: PrivacyRequest[]) => void }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const act = async (status: "tratado" | "recusado") => {
    setBusy(true); setErr("");
    try { onDone((await resolvePrivacyRequest(r.id, status, text)).items); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <div className="flex flex-col gap-2 px-4 py-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium">{r.email}</span>
        <Badge variant={r.status === "pendente" ? "default" : "outline"}>{r.status}</Badge>
        <span className="text-muted-foreground">{fmt(r.created_at)} · {(r.workspaces ?? []).join(", ") || "só agência"}</span>
      </div>
      {r.reason && <p className="text-muted-foreground">Motivo: {r.reason}</p>}
      {r.resolution && <p>Resolução: {r.resolution}</p>}
      {r.status === "pendente" && (
        <div className="flex flex-wrap gap-2">
          <Input aria-label={`O que foi feito com o pedido de ${r.email}`} className="h-8 min-w-[14rem] flex-1" value={text} maxLength={1000}
            placeholder="O que foi feito (ex.: conta anonimizada)" onChange={(e) => setText(e.target.value)} />
          <Button size="sm" disabled={busy || text.trim().length < 5} onClick={() => void act("tratado")}>{busy && <Loader2Icon className="animate-spin" />}Marcar tratado</Button>
          <Button size="sm" variant="outline" disabled={busy || text.trim().length < 5} onClick={() => void act("recusado")}>Recusar</Button>
        </div>
      )}
      {err && <p className="text-destructive" role="alert">{err}</p>}
    </div>
  );
}
