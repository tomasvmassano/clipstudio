"use client";

import { useState } from "react";
import Link from "next/link";
import { Loader2Icon, SendIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { Meter, Notice } from "@/components/portal/portal-shared";
import type { Access } from "@/lib/access";
import { createRequest, type DeliveriesBlock, type ReportsBlock, type RequestsBlock } from "@/lib/portal";
import { EDITORIAL_LABEL, indexLabel, monthTitle, ofContracted, progressPct, requestStatusLabel, requestTextError } from "@/lib/portal-format";
import { PLATFORM_LABEL, type Platform } from "@/lib/pub-rules";
import { clientPath } from "@/lib/ws-path";

/** Entregas do mês contra o volume contratado. Só volumes e prazos: o servidor nunca manda valores do contrato. */
export function Deliveries({ block }: { block: DeliveriesBlock }) {
  const v = block.videos; const s = block.scripts;
  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        {monthTitle(block.month)}
        {block.contract ? ` · contratado: ${block.contract.videos_per_month ?? "-"} vídeos e ${block.contract.scripts_per_month ?? "-"} guiões por mês, prazo de ${block.contract.deadline_days} dias`
          + (block.contract.platforms.length ? ` (${block.contract.platforms.map((p) => PLATFORM_LABEL[p as Platform] ?? p).join(", ")})` : "") : ""}
      </p>
      {block.contract_reason && <p className="text-sm text-muted-foreground">{block.contract_reason}</p>}
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-3" data-delivery="videos">
          <Meter label="Vídeos publicados" value={progressPct(v.published, v.contracted)} text={ofContracted(v.published, v.contracted)} />
          <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
            <dt className="text-muted-foreground">No prazo</dt><dd className="tabular-nums">{v.on_time}</dd>
            <dt className="text-muted-foreground">Fora do prazo</dt><dd className="tabular-nums">{v.late}</dd>
            <dt className="text-muted-foreground">Em atraso por publicar</dt><dd className="tabular-nums">{v.overdue}</dd>
            <dt className="text-muted-foreground">Com prazo hoje</dt><dd className="tabular-nums">{v.due_today}</dd>
            {v.expected_to_date !== null && <><dt className="text-muted-foreground">Esperado até hoje</dt><dd className="tabular-nums">{String(v.expected_to_date).replace(".", ",")}</dd></>}
          </dl>
        </div>
        <div className="flex flex-col gap-3" data-delivery="scripts">
          <Meter label="Guiões aprovados" value={progressPct(s.approved, s.contracted)} text={ofContracted(s.approved, s.contracted)} />
          <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
            <dt className="text-muted-foreground">No calendário este mês</dt><dd className="tabular-nums">{s.planned}</dd>
            <dt className="text-muted-foreground">À espera de aprovação</dt><dd className="tabular-nums">{s.waiting_approval}</dd>
          </dl>
        </div>
      </div>
      <p className="text-xs text-muted-foreground">{block.assumption}</p>
    </div>
  );
}

/** Resumo do centro de desempenho (mesmas contas, mesmas amostras mínimas). */
export function Reports({ block, ws }: { block: ReportsBlock; ws: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <p className="text-sm text-muted-foreground">
        {block.totals.publications} publicações lidas{block.first_reading_at ? ` desde ${new Date(block.first_reading_at).toLocaleDateString("pt-PT")}` : ""}.
        Índice: views do reel ÷ mediana da própria conta às 72 h (1× = normal da conta).
        Fonte: {block.source === "scraping" ? "leitura pública diária (sem alcance nem retenção)" : block.source}.
      </p>
      {block.accounts.length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há contas com leituras.</p> : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Conta</TableHead><TableHead className="text-right">Publicações 30 d</TableHead><TableHead className="text-right">Índice mediano</TableHead><TableHead>Últimos 7 dias vs 30 anteriores</TableHead></TableRow></TableHeader>
            <TableBody>
              {block.accounts.map((a) => (
                <TableRow key={a.id} data-report-account={a.id}>
                  <TableCell>{PLATFORM_LABEL[a.platform as Platform] ?? a.platform} · @{a.handle}</TableCell>
                  <TableCell className="text-right tabular-nums">{a.n_30d}</TableCell>
                  <TableCell className="text-right tabular-nums">{a.idx72_n_30d >= 1 ? indexLabel(a.idx72_median_30d) : "sem amostra"}</TableCell>
                  <TableCell className="text-sm">
                    {a.median_ratio === null ? <span className="text-muted-foreground">poucos dados</span>
                      : a.median_drop ? <span>a descer ({indexLabel(a.median_ratio)})</span>
                      : <span>sem queda ({indexLabel(a.median_ratio)})</span>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium">Melhores da semana</p>
        {block.week.top.length === 0 ? <p className="text-sm text-muted-foreground">Ainda sem reels com 3 a 10 dias e índice calculado.</p> : (
          <ol className="list-decimal pl-5 text-sm">
            {block.week.top.map((t) => <li key={t.reel_id}>{t.hook_text ?? "Sem hook registado"} <span className="text-muted-foreground">· @{t.handle} · {indexLabel(t.idx72)}</span></li>)}
          </ol>
        )}
      </div>
      <Link className="text-sm underline underline-offset-4" href={clientPath(ws, "/desempenho/centro")}>Ver o centro de desempenho</Link>
    </div>
  );
}

/** Pedidos de conteúdo: cria com talent_request_create (requests.create) e acompanha o que aconteceu a cada um. */
export function Requests({ access, block, onChanged }: { access: Access; block: RequestsBlock; onChanged: () => void }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const invalid = text ? requestTextError(text) : null;
  const send = async () => {
    const e = requestTextError(text);
    if (e) { setMsg({ kind: "err", text: e }); return; }
    setBusy(true);
    try { await createRequest(access, text.trim()); setText(""); setMsg({ kind: "ok", text: "Pedido enviado. A agência vê-o na triagem." }); onChanged(); }
    catch (err) { setMsg({ kind: "err", text: (err as Error).message || "Não consegui enviar. Tenta de novo." }); }
    finally { setBusy(false); }
  };
  return (
    <div className="flex min-w-0 flex-col gap-3">
      {block.can_create ? (
        <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); void send(); }}>
          <label htmlFor="portal-request" className="text-sm font-medium">Novo pedido</label>
          <Textarea id="portal-request" value={text} onChange={(e) => setText(e.target.value)} maxLength={2000} rows={3}
            placeholder="Que vídeo gostavas de ver? Tema, ideia, data importante…" aria-invalid={!!invalid} />
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" type="submit" disabled={busy || !text.trim()}>{busy ? <Loader2Icon className="animate-spin" /> : <SendIcon />} Enviar pedido</Button>
            {invalid && <span className="text-xs text-muted-foreground">{invalid}</span>}
          </div>
        </form>
      ) : <p className="text-sm text-muted-foreground">Não tens permissão para criar pedidos neste cliente; podes acompanhar os que existem.</p>}
      <Notice msg={msg} />
      <p className="text-sm text-muted-foreground">{block.open} em aberto · {block.total} nos últimos {block.window_days} dias.</p>
      {block.items.length === 0 ? <p className="text-sm text-muted-foreground">Ainda não há pedidos.</p> : (
        <ul className="flex flex-col gap-2">
          {block.items.map((r) => (
            <li key={r.id} className="flex min-w-0 flex-col gap-1 rounded-lg border p-3" data-portal-request={r.id}>
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Badge variant={r.status === "descartada" ? "outline" : "default"}>{requestStatusLabel(r.status)}</Badge>
                <span className="text-muted-foreground">{r.created_local}{r.mine ? " · teu" : ""}</span>
              </div>
              <p className="whitespace-pre-wrap break-words text-sm">{r.texto ?? r.titulo}</p>
              {r.status_reason && <p className="text-xs text-muted-foreground">Motivo: {r.status_reason}</p>}
              {r.scripts.length > 0 && (
                <p className="text-xs text-muted-foreground">
                  Deu origem a: {r.scripts.map((g) => `guião ${g.n} de ${g.date.split("-").reverse().join("/")} (${EDITORIAL_LABEL[g.editorial_status] ?? g.editorial_status})`).join("; ")}
                </p>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
