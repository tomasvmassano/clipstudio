"use client";

import { useState } from "react";
import { DownloadIcon, Loader2Icon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { WidgetBoundary } from "@/components/widget-boundary";
import { LearnState, Stat, selectCls, useLoad } from "@/components/learn/learn-shared";
import { download, toCsv } from "@/lib/learn";
import { exportAiUsage, fetchAiUsage, type AiUsage } from "@/lib/costs";
import {
  KIND_LABEL, STATUS_LABEL, csvFor, customError, duration, money, tokens, trend,
  type CostRow, type CostTable, type Money, type PeriodSel,
} from "@/lib/costs-format";

/*
 * Consumo de IA por cliente, agente, modelo e execução (FR-10-01, ADR-0062). A mesma vista serve a agência (ws nulo: todos os
 * clientes em que a pessoa tem costs.read) e o cliente (só esse cliente). Tudo estimado: o rótulo diz sempre de onde vem.
 */

const dateFmt = (iso: string | null, tz: string) =>
  iso ? new Intl.DateTimeFormat("pt-PT", { dateStyle: "short", timeStyle: "short", timeZone: tz }).format(new Date(iso)) : "-";
const dayFmt = (d: string) => new Intl.DateTimeFormat("pt-PT", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));

export function AiUsageView({ ws, token }: { ws: string | null; token: string | null }) {
  const agency = ws === null;
  const [period, setPeriod] = useState<PeriodSel>({ days: 30 });
  const [mode, setMode] = useState<"7" | "30" | "90" | "custom">("30");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [formErr, setFormErr] = useState("");
  const [table, setTable] = useState<CostTable>(agency ? "workspaces" : "agents");
  const [cur, setCur] = useState<Money>("EUR");
  const [busy, setBusy] = useState(false);
  const [expErr, setExpErr] = useState("");
  const key = `${ws ?? "agencia"}:${JSON.stringify(period)}`;
  const rep = useLoad(() => fetchAiUsage(ws, token, period), key);
  const d = rep.data;

  const choose = (v: string) => {
    setMode(v as typeof mode); setFormErr("");
    if (v !== "custom") setPeriod({ days: Number(v) as 7 | 30 | 90 });
  };
  const applyCustom = () => {
    const e = customError(from, to);
    setFormErr(e ?? "");
    if (!e) setPeriod({ from, to });
  };
  const doExport = async () => {
    setBusy(true); setExpErr("");
    try {
      const r: AiUsage = await exportAiUsage(table, ws, token, period);
      const { header, rows } = csvFor(table, r, cur, r.fx);
      download(`custos-ia-${ws ?? "agencia"}-${table}-${r.from}-${r.to}.csv`, toCsv(header, rows), "text/csv;charset=utf-8");
    } catch (e) { setExpErr((e as Error).message); } finally { setBusy(false); }
  };

  const tr = d ? trend(d.totals.cost, d.totals.prev_cost, d.totals.prev_jobs) : null;
  const fxMissing = cur === "AED" && d && !d.fx;
  const tables: { key: CostTable; label: string }[] = [
    ...(agency ? [{ key: "workspaces" as const, label: "Por cliente" }] : []),
    { key: "agents", label: "Por agente" }, { key: "models", label: "Por modelo" }, { key: "runs", label: "Execuções" },
  ];

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex items-center gap-2 text-sm">Período
          <select className={selectCls} value={mode} onChange={(e) => choose(e.target.value)} aria-label="Período">
            <option value="7">Últimos 7 dias</option><option value="30">Últimos 30 dias</option><option value="90">Últimos 90 dias</option>
            <option value="custom">Personalizado</option>
          </select>
        </label>
        {mode === "custom" && (
          <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); applyCustom(); }}>
            <label className="flex items-center gap-2 text-sm">De <Input type="date" className="h-8 w-auto" value={from} onChange={(e) => setFrom(e.target.value)} aria-invalid={!!formErr} /></label>
            <label className="flex items-center gap-2 text-sm">Até <Input type="date" className="h-8 w-auto" value={to} onChange={(e) => setTo(e.target.value)} aria-invalid={!!formErr} /></label>
            <Button size="sm" type="submit" variant="outline">Aplicar</Button>
          </form>
        )}
        <label className="flex items-center gap-2 text-sm">Moeda
          <select className={selectCls} value={cur} onChange={(e) => setCur(e.target.value as Money)} aria-label="Moeda">
            <option value="EUR">EUR</option><option value="AED">AED</option>
          </select>
        </label>
        <Button size="sm" variant="outline" onClick={rep.reload}><RotateCwIcon /> Atualizar</Button>
      </div>
      {formErr && <p role="alert" className="text-sm text-destructive">{formErr}</p>}
      <LearnState loading={rep.loading} error={rep.error} reload={rep.reload} label="os custos de IA"
        forbidden={agency ? "Os custos da agência são só para quem tem acesso aos custos da agência." : "Não tens acesso aos custos deste cliente."}>
        {d && tr && (
          <>
            <p className="text-xs text-muted-foreground">
              {dayFmt(d.from)} a {dayFmt(d.to)} ({d.days} dias, fuso {d.timezone}). Comparado com {dayFmt(d.prev_from)} a {dayFmt(d.prev_to)}.
              {agency && ` ${d.workspaces.length} ${d.workspaces.length === 1 ? "cliente" : "clientes"} com custos visíveis para ti.`}
            </p>
            <Alert>
              <AlertDescription className="text-xs">
                <strong>Valores estimados.</strong> {d.basis.note}
                {cur === "AED" && d.fx && ` Em AED à taxa da agência de ${String(d.fx.rate).replace(".", ",")} por EUR (${dayFmt(d.fx.as_of)}${d.fx.source ? `, ${d.fx.source}` : ""}).`}
                {fxMissing && " Ainda não há taxa EUR/AED registada pela agência: os valores ficam em EUR."}
              </AlertDescription>
            </Alert>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Stat label="Custo das execuções" value={money(d.totals.cost, fxMissing ? "EUR" : cur, d.fx)} hint={tr.text} />
              <Stat label="Execuções terminadas" value={d.totals.jobs}
                hint={[d.totals.jobs_unknown ? `${d.totals.jobs_unknown} sem custo conhecido` : "", d.totals.jobs_failed ? `${d.totals.jobs_failed} falhadas` : ""].filter(Boolean).join(" · ") || undefined} />
              <Stat label="Custo médio por execução" value={d.totals.jobs - d.totals.jobs_unknown > 0 ? money(d.totals.cost / (d.totals.jobs - d.totals.jobs_unknown), fxMissing ? "EUR" : cur, d.fx, 3) : "sem execuções com custo"} />
              <Stat label="Tokens (entrada / saída)" value={`${tokens(d.totals.tokens_in)} / ${tokens(d.totals.tokens_out)}`} />
            </div>
            <WidgetBoundary label="Tabela de custos">
              <Card>
                <CardHeader className="flex flex-row flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <CardTitle>Detalhe</CardTitle>
                    <CardDescription>
                      {table === "agents" || table === "models"
                        ? `Soma das chamadas registadas pelo motor (${money(d.totals.calls_cost, fxMissing ? "EUR" : cur, d.fx)}). Pode diferir do custo das execuções: pesquisas web contam só na execução e o motor antigo registava chamadas fora da fila.`
                        : table === "runs" ? "As 50 execuções mais caras do período; as de custo desconhecido ficam no fim." : "Execuções terminadas no período, por cliente."}
                    </CardDescription>
                  </div>
                  {d.can_export
                    ? <Button size="sm" onClick={() => void doExport()} disabled={busy}>{busy ? <Loader2Icon className="animate-spin" /> : <DownloadIcon />} Exportar CSV</Button>
                    : <span className="text-xs text-muted-foreground">Sem permissão para exportar.</span>}
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                  {expErr && <Alert variant="destructive"><AlertDescription>Não consegui exportar: {expErr}</AlertDescription></Alert>}
                  <Tabs value={table} onValueChange={(x) => setTable(String(x) as CostTable)}>
                    <TabsList className="flex h-auto flex-wrap justify-start">
                      {tables.map((t) => <TabsTrigger key={t.key} value={t.key}>{t.label}</TabsTrigger>)}
                    </TabsList>
                  </Tabs>
                  <div className="max-h-[36rem] overflow-auto">
                    {table === "workspaces" && <WsTable d={d} cur={fxMissing ? "EUR" : cur} />}
                    {(table === "agents" || table === "models") && <DimTable rows={table === "agents" ? d.agents : d.models} label={table === "agents" ? "Agente" : "Modelo"} d={d} cur={fxMissing ? "EUR" : cur} />}
                    {table === "runs" && <RunsTable d={d} cur={fxMissing ? "EUR" : cur} agency={agency} />}
                  </div>
                </CardContent>
              </Card>
            </WidgetBoundary>
            <details className="text-xs text-muted-foreground">
              <summary className="cursor-pointer">Preços usados na estimativa</summary>
              <ul className="mt-2 flex flex-col gap-1">
                {d.basis.prices.map((p) => (
                  <li key={p.model}>{p.label}: {p.eur_per_mtok_in === null ? "sem preço (custo desconhecido)" : `${money(p.eur_per_mtok_in, "EUR", null, 4)} entrada e ${money(p.eur_per_mtok_out, "EUR", null, 4)} saída por milhão de tokens`}{p.source ? ` · ${p.source}` : ""}</li>
                ))}
                {d.basis.tools.map((t) => <li key={t.key}>{t.label}: {money(t.eur_per_use, "EUR", null, 4)} por uso · {t.source}</li>)}
              </ul>
            </details>
          </>
        )}
      </LearnState>
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">{text}</p>;
}

function TrendCell({ cur, prev, prevCount }: { cur: number; prev: number; prevCount: number }) {
  const t = trend(cur, prev, prevCount);
  return <span className="text-xs text-muted-foreground">{t.kind === "up" || t.kind === "down" ? t.text.replace(" face ao período anterior", "") : t.kind === "flat" ? "estável" : "-"}</span>;
}

function WsTable({ d, cur }: { d: AiUsage; cur: Money }) {
  if (d.workspaces.length === 0) return <Empty text="Não tens acesso aos custos de nenhum cliente ativo." />;
  return (
    <Table>
      <TableHeader><TableRow>
        <TableHead>Cliente</TableHead><TableHead className="text-right">Custo</TableHead><TableHead className="text-right">Tendência</TableHead>
        <TableHead className="text-right">Execuções</TableHead><TableHead className="text-right">Tokens</TableHead>
      </TableRow></TableHeader>
      <TableBody>
        {d.workspaces.map((w) => (
          <TableRow key={w.id}>
            <TableCell>{w.name}</TableCell>
            <TableCell className="text-right tabular-nums">{money(w.cost, cur, d.fx)}</TableCell>
            <TableCell className="text-right"><TrendCell cur={w.cost} prev={w.prev_cost} prevCount={w.prev_jobs} /></TableCell>
            <TableCell className="text-right tabular-nums">{w.jobs}{w.jobs_unknown > 0 && <span className="block text-xs text-muted-foreground">{w.jobs_unknown} sem custo</span>}</TableCell>
            <TableCell className="text-right tabular-nums">{tokens(w.tokens_in)} / {tokens(w.tokens_out)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function DimTable({ rows, label, d, cur }: { rows: CostRow[]; label: string; d: AiUsage; cur: Money }) {
  if (rows.length === 0) return <Empty text="Sem chamadas registadas pelo motor neste período." />;
  return (
    <Table>
      <TableHeader><TableRow>
        <TableHead>{label}</TableHead><TableHead className="text-right">Custo</TableHead><TableHead className="text-right">Tendência</TableHead>
        <TableHead className="text-right">Chamadas</TableHead><TableHead className="text-right">Tokens</TableHead>
      </TableRow></TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.key}>
            <TableCell>{r.name}{r.name !== r.key && <span className="block text-xs text-muted-foreground">{r.key}</span>}</TableCell>
            <TableCell className="text-right tabular-nums">{money(r.cost, cur, d.fx, 3)}</TableCell>
            <TableCell className="text-right"><TrendCell cur={r.cost} prev={r.prev_cost} prevCount={r.prev_calls} /></TableCell>
            <TableCell className="text-right tabular-nums">{r.calls}{r.calls_unknown > 0 && <span className="block text-xs text-muted-foreground">{r.calls_unknown} sem custo</span>}</TableCell>
            <TableCell className="text-right tabular-nums">{tokens(r.tokens_in)} / {tokens(r.tokens_out)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function RunsTable({ d, cur, agency }: { d: AiUsage; cur: Money; agency: boolean }) {
  if (d.runs.length === 0) return <Empty text="Sem execuções terminadas neste período." />;
  return (
    <Table>
      <TableHeader><TableRow>
        <TableHead>Execução</TableHead>{agency && <TableHead>Cliente</TableHead>}<TableHead className="text-right">Custo</TableHead>
        <TableHead className="text-right">Tokens</TableHead><TableHead className="text-right">Duração</TableHead>
      </TableRow></TableHeader>
      <TableBody>
        {d.runs.map((r) => (
          <TableRow key={r.id}>
            <TableCell>
              <span className="block">{KIND_LABEL[r.kind] ?? r.kind} · {STATUS_LABEL[r.status] ?? r.status}</span>
              <span className="text-xs text-muted-foreground">{dateFmt(r.finished_at, d.timezone)}{r.attempts > 1 ? ` · ${r.attempts} tentativas` : ""}</span>
            </TableCell>
            {agency && <TableCell>{r.workspace_name}</TableCell>}
            <TableCell className="text-right tabular-nums">{r.cost_known ? money(r.cost_eur, cur, d.fx, 3) : "sem custo conhecido"}</TableCell>
            <TableCell className="text-right tabular-nums">{tokens(r.tokens_in)} / {tokens(r.tokens_out)}</TableCell>
            <TableCell className="text-right tabular-nums">{duration(r.duration_s)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
