"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { RotateCwIcon, SlidersHorizontalIcon } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { ChannelBreakdownChart } from "@/components/channel-breakdown-chart";
import { ConversationVolumeChart } from "@/components/conversation-volume-chart";
import { CsatResponsesChart } from "@/components/csat-responses-chart";
import { FirstReplyTimeChart } from "@/components/first-reply-time-chart";
import { KpiCard } from "@/components/kpi-card";
import { WidgetBoundary } from "@/components/widget-boundary";
import { LayoutDialog } from "@/components/dashboard-layout-dialog";
import { RecentConversations } from "@/components/recent-conversations";
import { SupportActivity } from "@/components/support-activity";
import { TeamCode } from "@/components/team-code";
import { TeamOnDuty } from "@/components/team-on-duty";
import { useGuioes } from "@/components/use-guioes";
import { useSession } from "@/components/session-provider";
import { WorkspaceGate } from "@/components/workspace-gate";
import { MyQueue } from "@/components/ops/my-queue";
import { useFlags } from "@/lib/flags";
import type { Access } from "@/lib/access";
import { splitDay } from "@/lib/data";
import {
  PERIODS, asKpi, fetchDashboard, fmtKpi, fmtRange, loadPeriod, rangeFor, savePeriod, todayIn,
  type DashboardResp, type PeriodKey, type Widget,
} from "@/lib/dashboard";
import { fetchDesempenho, fmtDay, type Desempenho } from "@/lib/desempenho";
import { fetchHoje, type Hoje } from "@/lib/hoje";
import { FORMATO_LABEL } from "@/lib/types";
import { clientPath } from "@/lib/ws-path";

/** Início do cliente (PRD M01): KPIs do período com comparação, widgets por função (configuráveis) e o dia de hoje. */
export default function InicioPage() {
  return <WorkspaceGate>{(access) => <Inicio access={access} />}</WorkspaceGate>;
}

const NEEDS_HOJE = new Set(["chart.views_daily", "panel.agents", "panel.activity"]);
const NEEDS_DES = new Set(["chart.production", "chart.weekly_avg"]);
const NEEDS_TODAY = new Set(["chart.format_mix", "panel.scripts_today"]);

function Inicio({ access }: { access: Access }) {
  const { ws, mode } = useSession();
  const flags = useFlags(access.ws, access.token, mode !== "loading");
  // A minha fila (FR-01-03) só com conta pessoal e a flag ops.workspace; sem ela o Início fica como estava
  const showQueue = mode === "user" && !!flags?.has("ops.workspace");
  // Portal do cliente (SCALE-08): sugerido à equipa do cliente e ao código de equipa quando a flag está ligada
  const showPortal = !!flags?.has("client.portal") && (mode !== "user" || ws?.affiliation === "client_staff");
  const tz = ws?.timezone ?? "Asia/Dubai";
  const [p, setP] = useState(loadPeriod);
  const range = useMemo(() => rangeFor(p.key, tz, { from: p.from, to: p.to }), [p, tz]);
  const [dash, setDash] = useState<DashboardResp | null>(null);
  const [hoje, setHoje] = useState<Hoje | null>(null);
  const [des, setDes] = useState<Desempenho | null>(null);
  const [err, setErr] = useState("");
  const [rev, setRev] = useState(0);
  const [editing, setEditing] = useState(false);

  const setPeriod = (next: typeof p) => { setP(next); savePeriod(next); };

  useEffect(() => {
    let alive = true;
    fetchDashboard(access, range.from, range.to)
      .then(async (d) => {
        if (!alive) return;
        setDash(d); setErr("");
        const keys = new Set(d.widgets.map((w) => w.key));
        const [h, s] = await Promise.all([
          [...keys].some((k) => NEEDS_HOJE.has(k)) ? fetchHoje(access) : Promise.resolve(null),
          [...keys].some((k) => NEEDS_DES.has(k)) ? fetchDesempenho(access) : Promise.resolve(null),
        ]);
        if (alive) { setHoje(h); setDes(s); }
      })
      .catch((e: Error) => { if (alive) setErr(e.message); });
    return () => { alive = false; };
  }, [access, range.from, range.to, rev]);

  const badRange = p.key === "custom" && (!p.from || !p.to || p.to < p.from);
  const kpis = dash?.widgets.filter((w) => w.kind === "kpi") ?? [];
  const others = dash?.widgets.filter((w) => w.kind !== "kpi") ?? [];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Início</h1>
          <p className="text-sm text-muted-foreground">
            {ws?.name} · {fmtRange(range.from, range.to)} · fuso {tz}
            {dash?.target_per_day ? ` · meta ${dash.target_per_day} guiões/dia` : ""}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {dash?.can_configure && <Button size="sm" variant="outline" onClick={() => setEditing(true)}><SlidersHorizontalIcon /> Personalizar</Button>}
          <TeamCode />
        </div>
      </div>

      {showPortal && (
        <Alert data-portal-hint>
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>O que espera pela tua aprovação, as entregas do mês e os teus pedidos estão juntos no portal.</span>
            <Link className="text-sm font-medium underline underline-offset-4" href={clientPath(access.ws, "/portal")}>Abrir o portal</Link>
          </AlertDescription>
        </Alert>
      )}
      {showQueue && <WidgetBoundary label="A minha fila"><MyQueue ws={access.ws} tz={tz} /></WidgetBoundary>}

      <PeriodPicker value={p} onChange={setPeriod} />
      {badRange && <Alert><AlertDescription>Escolhe uma data de início e uma de fim (o fim não pode ser antes do início). Até lá, mostro os últimos 30 dias.</AlertDescription></Alert>}

      {err ? (
        <Alert variant="destructive">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-2">
            <span>Não consegui carregar o Início: {err}</span>
            <Button size="sm" variant="outline" onClick={() => { setErr(""); setRev((n) => n + 1); }}><RotateCwIcon /> Tentar de novo</Button>
          </AlertDescription>
        </Alert>
      ) : !dash ? (
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="h-32" />)}</div>
      ) : dash.widgets.length === 0 ? (
        <Alert><AlertDescription>Não há widgets que possas ver neste cliente. Pede a quem gere o cliente para rever as tuas permissões ou o layout da tua função.</AlertDescription></Alert>
      ) : (
        <>
          {kpis.length > 0 && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {kpis.map((w) => <WidgetBoundary key={w.key} label={w.label}><KpiCard w={w} k={asKpi(dash.kpis[w.key])} period={dash.period} extra={extraFor(w.key, dash)} /></WidgetBoundary>)}
            </div>
          )}
          {others.length > 0 && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {others.map((w) => <WidgetBoundary key={w.key} label={w.label} className="md:col-span-2"><OtherWidget w={w} hoje={hoje} des={des} access={access} tz={tz} /></WidgetBoundary>)}
            </div>
          )}
          {dash.customized && <p className="text-muted-foreground text-xs">Layout personalizado para a tua função neste cliente.</p>}
        </>
      )}

      {editing && dash && (
        <LayoutDialog ws={access.ws} myRole={dash.role} onClose={(changed) => { setEditing(false); if (changed) setRev((n) => n + 1); }} />
      )}
    </div>
  );
}

function extraFor(key: string, d: DashboardResp): string | undefined {
  if (key === "kpi.costs" && Number(d.kpis.costs_unknown ?? 0) > 0) return `${d.kpis.costs_unknown} execuções sem custo conhecido`;
  if (key === "kpi.views" && d.kpis.reels != null) return `${fmtKpi("kpi.tasks_done", Number(d.kpis.reels))} reels no período`;
  return undefined;
}

function PeriodPicker({ value, onChange }: { value: { key: PeriodKey; from: string; to: string }; onChange: (v: { key: PeriodKey; from: string; to: string }) => void }) {
  return (
    <div className="flex flex-wrap items-end gap-2">
      <ToggleGroup value={[value.key]} variant="outline" size="sm" aria-label="Período"
        onValueChange={(v) => { const k = (v as string[])[0] as PeriodKey | undefined; if (k) onChange({ ...value, key: k }); }}>
        {PERIODS.map((x) => <ToggleGroupItem key={x.key} value={x.key}>{x.label}</ToggleGroupItem>)}
        <ToggleGroupItem value="custom">Outro</ToggleGroupItem>
      </ToggleGroup>
      {value.key === "custom" && (
        <>
          <label className="flex flex-col gap-1 text-xs">De<Input type="date" value={value.from} onChange={(e) => onChange({ ...value, from: e.target.value })} /></label>
          <label className="flex flex-col gap-1 text-xs">Até<Input type="date" value={value.to} onChange={(e) => onChange({ ...value, to: e.target.value })} /></label>
        </>
      )}
    </div>
  );
}

function OtherWidget({ w, hoje, des, access, tz }: { w: Widget; hoje: Hoje | null; des: Desempenho | null; access: Access; tz: string }) {
  if (NEEDS_TODAY.has(w.key)) return <TodayWidget w={w} access={access} tz={tz} />;
  if (NEEDS_HOJE.has(w.key) && !hoje) return <Skeleton className="h-64 md:col-span-2" />;
  if (NEEDS_DES.has(w.key) && !des) return <Skeleton className="h-64 md:col-span-2" />;
  switch (w.key) {
    case "chart.views_daily": return <ConversationVolumeChart rows={hoje!.diario} today={todayIn(tz)} />;
    case "chart.production": return <CsatResponsesChart rows={des!.dias.slice(-10).map((d) => ({ day: fmtDay(d.date), validados: d.validados, gravados: d.gravados, rejeitados: d.rejeitados }))} />;
    case "chart.weekly_avg": return <FirstReplyTimeChart rows={des!.semanas.slice(-7).map((s) => ({ day: fmtDay(s.semana), media: s.media }))} />;
    case "panel.agents": return <TeamOnDuty agentes={hoje!.agentes} />;
    case "panel.activity": return <SupportActivity items={hoje!.atividade} />;
    default: return null;
  }
}

/** Widgets do dia de hoje: só carregam os guiões quando estão no layout. */
function TodayWidget({ w, access, tz }: { w: Widget; access: Access; tz: string }) {
  const date = todayIn(tz);
  const { all, loading, error } = useGuioes(access, date);
  if (error) return <Alert variant="destructive" className="md:col-span-2"><AlertDescription>{w.label}: {error}</AlertDescription></Alert>;
  if (loading) return <Skeleton className="h-64 md:col-span-2" />;
  const { day } = splitDay(all, date);
  const ok = day.filter((g) => g.status !== "rejeitado");
  if (w.key === "panel.scripts_today") return <RecentConversations guioes={day} />;
  const count = new Map<string, number>();
  ok.forEach((g) => count.set(g.formato ?? "outros", (count.get(g.formato ?? "outros") ?? 0) + 1));
  const sorted = [...count.entries()].sort((a, b) => b[1] - a[1]);
  const rest = sorted.slice(4).reduce((t, [, n]) => t + n, 0);
  const mix = [...sorted.slice(0, 4), ...(rest ? [["outros", rest] as [string, number]] : [])].map(([k, n]) => ({
    key: k.replace(/[^a-z0-9]/gi, "_"), label: FORMATO_LABEL[k] ?? k, share: Math.round((n / Math.max(1, ok.length)) * 100),
  }));
  return <ChannelBreakdownChart data={mix} total={ok.length} />;
}
