"use client";

import { useEffect, useState } from "react";
import { DownloadIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { download, exportMyData, fetchMyDataStatus, requestDeletion, type PrivacyRequest } from "@/lib/learn";

const STATUS: Record<PrivacyRequest["status"], string> = { pendente: "Pendente", tratado: "Tratado", recusado: "Recusado", cancelado: "Cancelado" };
const fmt = (d: string) => new Date(d).toLocaleString("pt-PT", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

/**
 * Os meus dados (FR-14-05, flag profile.data_export): descarregar os próprios dados em JSON e pedir a eliminação ao dono
 * da agência. Nada se apaga sozinho. Sem a flag não aparece (fica como antes).
 */
export function MyDataCard() {
  const [st, setSt] = useState<{ available: boolean; requests: PrivacyRequest[] } | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState<"" | "export" | "delete">("");
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let alive = true;
    fetchMyDataStatus().then((s) => { if (alive) { setSt(s); setErr(""); } }).catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [attempt]);
  if (err) {
    return (
      <Card><CardHeader><CardTitle>Os meus dados</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-center gap-2 text-sm"><span className="text-destructive" role="alert">Não consegui ver o estado: {err}</span>
          <Button size="sm" variant="outline" onClick={() => setAttempt((n) => n + 1)}>Tentar de novo</Button></CardContent></Card>
    );
  }
  if (!st?.available) return null;
  const pending = st.requests.find((r) => r.status === "pendente");
  return (
    <Card data-my-data>
      <CardHeader>
        <CardTitle>Os meus dados</CardTitle>
        <CardDescription>Descarrega o teu perfil, os teus comentários, as tuas tarefas e o histórico das tuas ações nos clientes a que tens acesso. O pedido de eliminação vai para o dono da agência, que o trata conforme a política; nada se apaga sozinho.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" disabled={!!busy} onClick={async () => {
            setBusy("export"); setNote(null);
            try {
              const data = await exportMyData();
              download(`os-meus-dados-${new Date().toISOString().slice(0, 10)}.json`, JSON.stringify(data, null, 2), "application/json");
              setNote({ ok: true, text: "Ficheiro descarregado." });
            } catch (e) { setNote({ ok: false, text: (e as Error).message }); } finally { setBusy(""); }
          }}>{busy === "export" ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Descarregar os meus dados (JSON)</Button>
          {!pending && !asking && <Button variant="ghost" onClick={() => setAsking(true)}>Pedir eliminação</Button>}
        </div>
        {asking && !pending && (
          <form className="flex flex-col gap-2 rounded-md border p-3" onSubmit={async (e) => {
            e.preventDefault(); setBusy("delete"); setNote(null);
            try { await requestDeletion(reason); setAsking(false); setReason(""); setAttempt((n) => n + 1); setNote({ ok: true, text: "Pedido registado. O dono da agência vai tratá-lo." }); }
            catch (x) { setNote({ ok: false, text: (x as Error).message }); } finally { setBusy(""); }
          }}>
            <label htmlFor="del-reason" className="font-medium">Pedir a eliminação dos meus dados</label>
            <Textarea id="del-reason" value={reason} maxLength={1000} onChange={(e) => setReason(e.target.value)} placeholder="Motivo (opcional)" />
            <p className="text-xs text-muted-foreground">Continuas com acesso até o pedido ser tratado. Podes descarregar os teus dados antes.</p>
            <div className="flex gap-2">
              <Button type="submit" variant="destructive" disabled={!!busy}>{busy === "delete" && <Loader2Icon className="animate-spin" />}Enviar pedido</Button>
              <Button type="button" variant="ghost" onClick={() => setAsking(false)}>Cancelar</Button>
            </div>
          </form>
        )}
        {note && <p className={note.ok ? "text-emerald-600 dark:text-emerald-400" : "text-destructive"} role={note.ok ? "status" : "alert"}>{note.text}</p>}
        {st.requests.length > 0 && (
          <div className="flex flex-col gap-1">
            <span className="font-medium">Pedidos</span>
            {st.requests.map((r) => (
              <div key={r.id} className="flex flex-wrap justify-between gap-2 border-b py-1 last:border-0">
                <span>Eliminação · {STATUS[r.status]}{r.resolution ? `: ${r.resolution}` : ""}</span>
                <span className="text-muted-foreground">{fmt(r.created_at)}</span>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
