"use client";

import { useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { DashboardSkeleton } from "@/components/dashboard-skeleton";
import { DashboardStats, type Stat } from "@/components/stats";
import { ConversationVolumeChart } from "@/components/conversation-volume-chart";
import { ChannelBreakdownChart } from "@/components/channel-breakdown-chart";
import { CsatResponsesChart } from "@/components/csat-responses-chart";
import { FirstReplyTimeChart } from "@/components/first-reply-time-chart";
import { RecentesCard, ReferenciasCard, TopReelsCard } from "@/components/desempenho-3";
import { todayDubai } from "@/lib/data";
import { WorkspaceGate } from "@/components/workspace-gate";
import type { Access } from "@/lib/access";
import { fetchDesempenho, fmtCompact, fmtDay, fmtInt, type Desempenho } from "@/lib/desempenho";
import { pctDelta } from "@/lib/hoje";

export default function DesempenhoPage() {
	return <WorkspaceGate need="analytics.read">{(access) => <DesempenhoView access={access} />}</WorkspaceGate>;
}

function DesempenhoView({ access }: { access: Access }) {
	const [d, setD] = useState<Desempenho | null>(null);
	const [error, setError] = useState("");
	const [account, setAccount] = useState<string>("todas");
	const [attempt, setAttempt] = useState(0);
	const today = todayDubai();

	useEffect(() => {
		let alive = true;
		fetchDesempenho(access, account === "todas" ? null : account)
			.then((x) => { if (alive) setD(x); })
			.catch((e: Error) => { if (alive) setError(e.message); });
		return () => { alive = false; };
	}, [account, attempt, access]);

	const conta = d?.contas.find((c) => c.id === account);
	const clienteLabel = conta ? conta.handle : d?.contas[0]?.handle ?? "cliente";

	const stats = useMemo<Stat[]>(() => {
		if (!d) return [];
		const k = d.kpi;
		return [
			{ label: "Views (30 dias)", value: fmtCompact(k.views_30d), delta: k.views_prev_30d ? pctDelta(k.views_30d, k.views_prev_30d) : undefined, footnote: "vs 30 dias anteriores" },
			{ label: "Reels publicados (30 dias)", value: fmtInt(k.reels_30d), delta: k.reels_prev_30d ? pctDelta(k.reels_30d, k.reels_prev_30d) : undefined, footnote: "vs 30 dias anteriores" },
			{ label: "Mediana por reel", value: fmtCompact(k.mediana), footnote: `média ${fmtCompact(k.media)} em ${fmtInt(k.reels)} reels` },
			{ label: "Virais (2× ou mais)", value: fmtInt(k.outliers), footnote: `${k.reels ? Math.round((k.outliers / k.reels) * 100) : 0}% dos reels · último ${fmtDay(k.ultimo)}` },
		];
	}, [d]);

	const bandas = useMemo(() => {
		if (!d) return { data: [], total: 0 };
		const b = d.bandas;
		const total = b.abaixo + b.normal + b.acima + b.viral;
		const pct = (n: number) => (total ? Math.round((n / total) * 100) : 0);
		return {
			total,
			data: [
				{ key: "viral", label: "Viral (≥2×)", share: pct(b.viral) },
				{ key: "acima", label: "Acima (1–2×)", share: pct(b.acima) },
				{ key: "normal", label: "Normal (0,5–1×)", share: pct(b.normal) },
				{ key: "abaixo", label: "Fraco (<0,5×)", share: pct(b.abaixo) },
			].filter((x) => x.share > 0),
		};
	}, [d]);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end justify-between gap-3">
				<div>
					<h1 className="text-2xl font-semibold tracking-tight">Desempenho</h1>
					<p className="text-sm text-muted-foreground">
						Por conta, a partir dos reels guardados pelo scraper. Os dados de hoje chegam quando correr a recolha diária.
					</p>
				</div>
				{d && d.contas.length > 0 && (
					<ToggleGroup value={[account]} onValueChange={(v) => setAccount(((v as string[])[0] as string) ?? "todas")} variant="outline" size="sm">
						<ToggleGroupItem value="todas">Todas as contas</ToggleGroupItem>
						{d.contas.map((c) => (
							<ToggleGroupItem key={c.id} value={c.id}>@{c.handle} · {c.platform}</ToggleGroupItem>
						))}
					</ToggleGroup>
				)}
			</div>

			{error && (
				<Alert variant="destructive">
					<AlertDescription className="flex flex-wrap items-center justify-between gap-2">
						<span>Não consegui carregar o desempenho: {error}</span>
						<Button size="sm" variant="outline" onClick={() => { setError(""); setAttempt((n) => n + 1); }}>Tentar de novo</Button>
					</AlertDescription>
				</Alert>
			)}

			{!d ? (
				!error && <DashboardSkeleton />
			) : (
				<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
					<DashboardStats stats={stats} />
					<ConversationVolumeChart rows={d.diario} today={today} />
					<ChannelBreakdownChart
						data={bandas.data}
						total={bandas.total}
						title="Reels por desempenho"
						description={`Peso de cada nível de outlier nos ${bandas.total} reels`}
						emptyText="Ainda não há reels guardados."
					/>
					<FirstReplyTimeChart rows={d.semanas.slice(-7).map((s) => ({ day: fmtDay(s.semana), media: s.media }))} />
					<CsatResponsesChart rows={d.dias.slice(-10).map((x) => ({ day: fmtDay(x.date), validados: x.validados, gravados: x.gravados, rejeitados: x.rejeitados }))} />
					<ReferenciasCard d={d} clienteLabel={clienteLabel} />
					<TopReelsCard rows={d.top} />
					<RecentesCard rows={d.recentes} />
				</div>
			)}
		</div>
	);
}
