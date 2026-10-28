"use client";

import { useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dashboard, type DashboardData } from "@/components/dashboard";
import { DashboardSkeleton } from "@/components/dashboard-skeleton";
import { TeamCode } from "@/components/team-code";
import { useGuioes } from "@/components/use-guioes";
import { niceDate, splitDay, todayDubai } from "@/lib/data";
import { fetchDesempenho, fmtCompact, fmtDay, type Desempenho } from "@/lib/desempenho";
import { fetchHoje, pctDelta, type Hoje } from "@/lib/hoje";
import { FORMATO_LABEL } from "@/lib/types";

// Preset do workspace Numeiro (PRD §20): 30 guiões/dia. Outros clientes terão o seu.
const TARGET = 30;

export default function HojePage() {
	const date = todayDubai();
	const { all, loading, error: gErr } = useGuioes(date);
	const [hoje, setHoje] = useState<Hoje | null>(null);
	const [des, setDes] = useState<Desempenho | null>(null);
	const [err, setErr] = useState("");
	const [attempt, setAttempt] = useState(0);

	useEffect(() => {
		Promise.all([fetchHoje(), fetchDesempenho()])
			.then(([h, d]) => { setHoje(h); setDes(d); })
			.catch((e: Error) => setErr(e.message));
	}, [attempt]);

	const data = useMemo<DashboardData | null>(() => {
		if (!hoje || !des || loading) return null;
		const { day, carry } = splitDay(all, date);
		const ok = day.filter((g) => g.status !== "rejeitado");
		const val = ok.filter((g) => g.validado).length;
		const grav = ok.filter((g) => g.gravado).length;
		const rej = day.length - ok.length;

		const count = new Map<string, number>();
		ok.forEach((g) => count.set(g.formato ?? "outros", (count.get(g.formato ?? "outros") ?? 0) + 1));
		const sorted = [...count.entries()].sort((a, b) => b[1] - a[1]);
		const top = sorted.slice(0, 4);
		const rest = sorted.slice(4).reduce((t, [, n]) => t + n, 0);
		const mix = [...top, ...(rest ? [["outros", rest] as [string, number]] : [])].map(([k, n]) => ({
			key: k.replace(/[^a-z0-9]/gi, "_"),
			label: FORMATO_LABEL[k] ?? k,
			share: Math.round((n / Math.max(1, ok.length)) * 100),
		}));

		return {
			today: date,
			hoje,
			guioesHoje: day,
			mix,
			stats: [
				{ label: "Guiões para gravar", value: `${ok.length} / ${TARGET}`, footnote: rej ? `${rej} rejeitados hoje` : "meta do dia" },
				{ label: "Validados pelo Creator", value: `${val} / ${ok.length}`, footnote: val < ok.length ? `faltam ${ok.length - val}` : "tudo validado" },
				{ label: "Gravados", value: `${grav} / ${ok.length}`, footnote: carry.length ? `${carry.length} por gravar de dias anteriores` : "hoje" },
				{ label: "Views (30 dias)", value: fmtCompact(hoje.views_30d), delta: hoje.views_prev_30d ? pctDelta(hoje.views_30d, hoje.views_prev_30d) : undefined, footnote: "vs 30 dias anteriores" },
			],
			prod: des.dias.slice(-10).map((d) => ({ day: fmtDay(d.date), validados: d.validados, gravados: d.gravados, rejeitados: d.rejeitados })),
			semanas: des.semanas.slice(-7).map((s) => ({ day: fmtDay(s.semana), media: s.media })),
		};
	}, [hoje, des, loading, all, date]);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end justify-between gap-3">
				<div>
					<h1 className="text-2xl font-semibold tracking-tight">Hoje</h1>
					<p className="text-sm text-muted-foreground">{niceDate(date)} · hora de Dubai</p>
				</div>
				<TeamCode />
			</div>
			{(err || gErr) && (
				<Alert variant="destructive">
					<AlertDescription className="flex flex-wrap items-center justify-between gap-2">
						<span>Não consegui carregar os dados: {err || gErr}</span>
						<Button size="sm" variant="outline" onClick={() => { setErr(""); setAttempt((n) => n + 1); }}>Tentar de novo</Button>
					</AlertDescription>
				</Alert>
			)}
			{data ? <Dashboard data={data} /> : !err && <DashboardSkeleton />}
		</div>
	);
}
