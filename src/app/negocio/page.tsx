"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ArrowRightIcon, InfoIcon, RotateCwIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { BizAttention } from "@/components/biz-attention";
import { FlagGate } from "@/components/flag-gate";
import { useSession } from "@/components/session-provider";
import {
  PAYMENT_LABEL, attainmentTone, currentMonth, fetchOverview, fmtDate, fmtHours, fmtMoney, fmtNum, fmtPct, isForbidden, monthLabel,
  type BizClient, type BizMetric, type BizOverview, type Currency,
} from "@/lib/biz";

/** Vista de negócio da agência (PRD §38). Operacional para quem tem a capacidade; financeiro só para quem o servidor deixa. */
export default function NegocioPage() {
  const { mode, canOrg } = useSession();
  if (mode === "loading") return <Skeleton className="h-64" />;
  if (!canOrg("biz.read")) return <Alert><AlertDescription>A vista de negócio é da equipa da agência. Não tens acesso a ela.</AlertDescription></Alert>;
  return <FlagGate flag="biz.view" ws={null}><Negocio /></FlagGate>;
}

const TONE_CLASS = { bad: "text-red-500", warn: "text-amber-500", good: "text-emerald-500", none: "" } as const;

function Negocio() {
  const [month, setMonth] = useState(currentMonth);
  const [cur, setCur] = useState<Currency>("EUR");
  const [data, setData] = useState<BizOverview | null>(null);
  const [err, setErr] = useState<{ msg: string; forbidden: boolean } | null>(null);
  const [rev, setRev] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchOverview(`${month}-01`, cur)
      .then((d) => { if (alive) { setData(d); setErr(null); } })
      .catch((e: Error) => { if (alive) setErr({ msg: e.message, forbidden: isForbidden(e) }); });
    return () => { alive = false; };
  }, [month, cur, rev]);

  const metric = (k: string) => data?.metrics.find((m) => m.key === k);
  const unavailableMetrics = data?.metrics.filter((m) => !m.available) ?? [];
  const loading = !data || data.month.slice(0, 7) !== month || data.currency !== cur;

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Vista de negócio</h1>
          <p className="text-sm text-muted-foreground">
            {data ? `${data.count} ${data.count === 1 ? "cliente" : "clientes"} a que tens acesso` : "Os clientes a que tens acesso"} · {monthLabel(month)} · datas no fuso de cada cliente
          </p>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs">Mês
            <Input type="month" value={month} max={currentMonth()} onChange={(e) => { if (e.target.value) setMonth(e.target.value); }} className="w-40" />
          </label>
          {data?.finance && (
            <ToggleGroup value={[cur]} variant="outline" size="sm" aria-label="Moeda dos totais"
              onValueChange={(v) => { const c = (v as string[])[0] as Currency | undefined; if (c) setCur(c); }}>
              <ToggleGroupItem value="EUR">EUR</ToggleGroupItem>
              <ToggleGroupItem value="AED">AED</ToggleGroupItem>
            </ToggleGroup>
          )}
        </div>
      </div>

      {err ? (
        err.forbidden ? <Alert><AlertDescription>{err.msg}</AlertDescription></Alert> : (
          <Alert variant="destructive">
            <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
              <span>Não consegui carregar a vista de negócio: {err.msg}</span>
              <Button size="sm" variant="outline" onClick={() => { setErr(null); setRev((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button>
            </AlertDescription>
          </Alert>
        )
      ) : loading ? (
        <div className="flex flex-col gap-4" aria-busy="true" aria-label="A carregar">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">{Array.from({ length: 3 }, (_, i) => <Skeleton key={i} className="h-28" />)}</div>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">{Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-24" />)}</div>
          <Skeleton className="h-48" />
        </div>
      ) : data.count === 0 ? (
        <Alert><AlertDescription>Ainda não tens nenhum cliente ativo atribuído. Pede ao dono da agência que te atribua aos clientes em que trabalhas.</AlertDescription></Alert>
      ) : (
        <>
          {data.finance && <FxLine data={data} />}
          <BizAttention attention={data.attention} />
          <section aria-labelledby="biz-kpis" className="flex flex-col gap-2">
            <h2 id="biz-kpis" className="font-medium text-base">Indicadores</h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Kpi m={metric("ops.attainment")} value={fmtPct(data.totals["ops.attainment"]?.pct)} tone={attainmentTone(data.totals["ops.attainment"])} missing={data.missing["ops.attainment"]}
                sub={data.totals["ops.attainment"]?.contracted ? `${fmtNum(data.totals["ops.attainment"].on_time)} no prazo de ${fmtNum(data.totals["ops.attainment"].contracted)} contratados · ritmo até hoje ${fmtPct(data.totals["ops.attainment"].pace)} · meta ${data.totals["ops.attainment"].target}%` : "Sem volume contratado registado."} />
              <Kpi m={metric("ops.first_pass")} value={fmtPct(data.totals["ops.first_pass"]?.pct)} missing={data.missing["ops.first_pass"]}
                sub={`${fmtNum(data.totals["ops.first_pass"]?.first_pass)} de ${fmtNum(data.totals["ops.first_pass"]?.approved)} aprovados`} />
              <Kpi m={metric("ops.approval_time")} value={fmtHours(data.totals["ops.approval_time"]?.median_h)} missing={data.missing["ops.approval_time"]}
                sub={data.totals["ops.approval_time"]?.n ? `mediana de ${data.totals["ops.approval_time"].n} aprovações do cliente` : "Sem aprovações da equipa do cliente no mês."} />
              <Kpi m={metric("ops.performance")} value={data.totals["ops.performance"]?.median != null ? `${fmtNum(data.totals["ops.performance"].median, 2)}×` : "-"} missing={data.missing["ops.performance"]}
                sub={data.totals["ops.performance"]?.n ? `${data.totals["ops.performance"].n} reels com base de comparação` : "Sem reels com 30 dias de base na conta."} />
              {data.finance && (
                <>
                  <Kpi m={metric("fin.mrr")} value={fmtMoney(data.totals["fin.mrr"], cur)} sub={data.fx_missing ? "Há valores sem conversão (falta a taxa de câmbio)." : "Contratos ativos no fim do mês."} />
                  <Kpi m={metric("fin.margin")} value={fmtPct(data.totals["fin.margin"])} tone={data.totals["fin.margin"] == null ? "none" : data.totals["fin.margin"] < 50 ? "bad" : "good"}
                    sub={`Custo ${fmtMoney(data.totals["fin.cost"], cur)}`} />
                  <Kpi m={metric("fin.cost_per_video")} value={fmtMoney(data.totals["fin.cost_per_video"], cur)} sub={`Por 1.000 views: ${fmtMoney(data.totals["fin.cost_per_1k"], cur)}`} />
                  <Kpi m={{ key: "fin.at_risk", label: "Clientes em risco", description: "Fatura vencida há mais de 15 dias, margem abaixo de 50%, ou renovação em 30 dias com entrega abaixo de 90%." }}
                    value={fmtNum(data.totals.at_risk)} tone={data.totals.at_risk ? "bad" : "good"} sub={`de ${data.count} clientes`} />
                </>
              )}
            </div>
          </section>
          <ClientTable data={data} cur={cur} />
          {unavailableMetrics.length > 0 && (
            <ul className="flex flex-col gap-1 text-muted-foreground text-xs" aria-label="Métricas ainda sem dados">
              {unavailableMetrics.map((m) => <li key={m.key}><span className="font-medium text-foreground">{m.label}: indisponível.</span> {m.unavailable_reason}</li>)}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

function FxLine({ data }: { data: BizOverview }) {
  return (
    <div className="flex flex-wrap items-center gap-2 text-xs">
      {data.fx ? (
        <span className="text-muted-foreground">Câmbio: 1 EUR = {fmtNum(data.fx.rate, 4)} AED, taxa de {fmtDate(data.fx.as_of)}{data.fx.source ? ` (${data.fx.source})` : ""}.</span>
      ) : <span className="text-amber-500">Ainda não há taxa de câmbio: os valores noutra moeda ficam sem conversão.</span>}
      {data.can_manage && <Link href="/negocio/contratos" className="underline underline-offset-4">Contratos, câmbio e custos</Link>}
    </div>
  );
}

function Kpi({ m, value, sub, tone = "none", missing }: { m?: Pick<BizMetric, "key" | "label" | "description">; value: string; sub?: string; tone?: keyof typeof TONE_CLASS; missing?: number }) {
  const [open, setOpen] = useState(false);
  if (!m) return null;
  return (
    <Card className="shadow-none dark:ring-0" data-kpi={m.key}>
      <CardHeader className="flex flex-row items-start justify-between gap-2">
        <CardTitle className="font-normal text-muted-foreground text-xs">{m.label}</CardTitle>
        <button type="button" aria-label={`O que é: ${m.label}`} aria-expanded={open} onClick={() => setOpen(!open)}
          className="-m-2 rounded p-2 text-muted-foreground hover:text-foreground focus-visible:outline-2 focus-visible:outline-ring">
          <InfoIcon className="size-3.5" />
        </button>
      </CardHeader>
      <CardContent className="flex flex-col gap-1">
        <p className={`font-semibold text-2xl tabular-nums ${TONE_CLASS[tone]}`}>{value}</p>
        {sub && <p className="text-muted-foreground text-xs">{sub}</p>}
        {missing ? <p className="text-muted-foreground text-xs">Sem {missing} {missing === 1 ? "cliente" : "clientes"} a que não tens acesso a este número.</p> : null}
        {open && <p className="border-t pt-2 text-muted-foreground text-xs">{m.description}</p>}
      </CardContent>
    </Card>
  );
}

const NO = <span className="text-muted-foreground text-xs" title="Sem permissão para este número neste cliente">sem acesso</span>;

/** Tabela por cliente: da causa (produção do dia, parados, aprovações) para o resultado (desempenho, receita, custo, margem). */
function ClientTable({ data, cur }: { data: BizOverview; cur: Currency }) {
  const label = (k: string) => data.metrics.find((m) => m.key === k);
  const th = (k: string, extra = "") => {
    const m = label(k);
    return <th key={k} scope="col" className={`px-3 py-2 text-right font-normal ${extra}`} title={m?.description}>{m?.label ?? k}</th>;
  };
  return (
    <section aria-labelledby="biz-table" className="flex flex-col gap-2">
      <h2 id="biz-table" className="font-medium text-base">Por cliente</h2>
      <Card className="shadow-none dark:ring-0">
        <CardContent className="overflow-x-auto p-0">
          <table className="w-full min-w-[860px] text-sm">
            <thead>
              <tr className="border-b text-left text-xs text-muted-foreground">
                <th scope="col" className="px-4 py-2 font-normal">Cliente</th>
                {th("ops.today")}{th("ops.stalled")}{th("ops.approvals")}{th("ops.attainment")}{th("ops.performance")}{th("ops.reach")}
                {data.finance && <>{th("fin.mrr", "border-l")}{th("fin.cost")}{th("fin.margin")}{th("fin.payment")}{th("fin.renewal")}</>}
                <th scope="col" className="px-3 py-2"><span className="sr-only">Abrir</span></th>
              </tr>
            </thead>
            <tbody>
              {data.clients.map((c) => <Row key={c.id} c={c} cur={cur} finance={data.finance} />)}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </section>
  );
}

function Row({ c, cur, finance }: { c: BizClient; cur: Currency; finance: boolean }) {
  const { setWorkspace } = useSession();
  const o = c.ops;
  const a = o["ops.attainment"];
  const f = c.fin;
  const td = "px-3 py-2 text-right tabular-nums align-top";
  return (
    <tr className="border-b last:border-0" data-client={c.id}>
      <td className="px-4 py-2 align-top">
        <span className="flex items-center gap-2">
          <span aria-hidden className="size-3 rounded-sm bg-muted" style={{ backgroundColor: c.brand_color ?? undefined }} />
          <span className="font-medium">{c.name}</span>
        </span>
      </td>
      <td className={td}>{o["ops.today"] ? <>{fmtNum(o["ops.today"].recorded)} / {fmtNum(o["ops.today"].planned)}<Sub>gravados hoje</Sub></> : NO}</td>
      <td className={td}>{o["ops.stalled"] ? (
        <>
          <span className={o["ops.stalled"].over_p70 ? "text-red-500" : o["ops.stalled"].over_p50 ? "text-amber-500" : ""}>{fmtNum(o["ops.stalled"].over_p70)}</span>
          <Sub>{o["ops.stalled"].over_p50 ? `+${o["ops.stalled"].over_p50} em aviso` : o["ops.stalled"].unmeasured ? `${o["ops.stalled"].unmeasured} sem amostra` : "acima do p70"}</Sub>
        </>
      ) : NO}</td>
      <td className={td}>{o["ops.approvals"] ? <>{fmtNum(o["ops.approvals"].pending)}<Sub>{o["ops.approvals"].over_48h ? `${o["ops.approvals"].over_48h} há +48 h` : "pendentes"}</Sub></> : NO}</td>
      <td className={td}>{a ? (
        a.contracted == null ? <span className="text-muted-foreground text-xs">sem contrato</span> : (
          <>
            <span className={TONE_CLASS[attainmentTone(a)]}>{fmtPct(a.pct)}</span>
            <Sub>{`${a.on_time}/${a.contracted} · ritmo ${fmtPct(a.pace)}`}</Sub>
            {(a.late_client ?? 0) + (a.late_agency ?? 0) > 0 && <Sub>{`atrasos: ${a.late_agency ?? 0} agência, ${a.late_client ?? 0} cliente`}</Sub>}
          </>
        )
      ) : NO}</td>
      <td className={td}>{o["ops.performance"] ? (o["ops.performance"].median != null ? `${fmtNum(o["ops.performance"].median, 2)}×` : <span className="text-muted-foreground text-xs">sem base</span>) : NO}</td>
      <td className={td}>{o["ops.reach"] ? (
        o["ops.reach"].ratio != null ? <span className={o["ops.reach"].ratio < 60 ? "text-red-500" : ""}>{fmtPct(o["ops.reach"].ratio)}</span> : <span className="text-muted-foreground text-xs">poucos reels</span>
      ) : NO}</td>
      {finance && (
        <>
          <td className={`${td} border-l`}>{f?.contract ? <>{fmtMoney(f["fin.mrr"], cur)}{f.contract_currency && f.contract_currency !== cur && <Sub>{fmtMoney(f.mrr_original, f.contract_currency)}</Sub>}</> : <span className="text-muted-foreground text-xs">sem contrato</span>}</td>
          <td className={td}>{fmtMoney(f?.["fin.cost"], cur)}{f && <Sub>{`IA ${fmtMoney(f.cost_ai, cur)}`}</Sub>}</td>
          <td className={td}><span className={f?.["fin.margin"] != null && f["fin.margin"] < 50 ? "text-red-500" : ""}>{fmtPct(f?.["fin.margin"])}</span></td>
          <td className={td}>{f?.["fin.payment"] ? (
            <><span className={f["fin.payment"].status === "vencido" ? "text-red-500" : ""}>{PAYMENT_LABEL[f["fin.payment"].status]}</span>
              {f["fin.payment"].overdue_days != null && <Sub>{`há ${f["fin.payment"].overdue_days} dias`}</Sub>}</>
          ) : "-"}</td>
          <td className={td}>{f?.["fin.renewal"] ? <>{fmtDate(f["fin.renewal"].on)}<Sub>{f["fin.renewal"].days >= 0 ? `em ${f["fin.renewal"].days} dias` : "passou"}</Sub></> : "-"}</td>
        </>
      )}
      <td className="px-3 py-2 text-right align-top">
        <Button size="sm" variant="ghost" onClick={() => setWorkspace(c.id)} aria-label={`Abrir ${c.name}`}>Abrir <ArrowRightIcon /></Button>
      </td>
    </tr>
  );
}

const Sub = ({ children }: { children: React.ReactNode }) => <span className="block text-muted-foreground text-xs">{children}</span>;
