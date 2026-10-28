"use client";

import { cn } from "@/lib/utils";
import { type ComponentProps, useId, useMemo, useState } from "react";
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
	formatChartAxisTick,
	formatChartTooltipDate,
	parseIsoCalendarDate,
} from "@/components/formater";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import {
	type ChartConfig,
	ChartContainer,
	ChartTooltip,
	ChartTooltipContent,
} from "@/components/ui/chart";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/components/ui/select";
import { Delta, DeltaIcon, DeltaValue } from "@/components/delta";

type PeriodDays = 7 | 30 | 60;

type VolumeRow = {
	date: string;
	views: number;
	reels: number;
};

const chartConfig = {
	views: {
		label: "Views",
		color: "var(--chart-2)",
	},
} satisfies ChartConfig;

function isoDay(d: Date) {
	return d.toISOString().slice(0, 10);
}

/** Views somadas por dia de publicação, dias sem reels a 0. `today` = dia de hoje no fuso do workspace. */
export function ConversationVolumeChart({
	className,
	rows,
	today,
	...props
}: ComponentProps<typeof Card> & { rows: VolumeRow[]; today: string }) {
	const chartUid = useId().replace(/:/g, "");
	const idAreaGradient = `conversation-volume-area-grad-${chartUid}`;

	const [periodDays, setPeriodDays] = useState<PeriodDays>(30);

	const byDay = useMemo(() => new Map(rows.map((r) => [r.date, r])), [rows]);
	const series = (days: number, offset = 0) => {
		const out: VolumeRow[] = [];
		const end = parseIsoCalendarDate(today);
		for (let i = days - 1 + offset; i >= offset; i--) {
			const d = new Date(end);
			d.setDate(d.getDate() - i);
			const k = isoDay(d);
			out.push(byDay.get(k) ?? { date: k, views: 0, reels: 0 });
		}
		return out;
	};
	const chartRows = useMemo(() => series(periodDays), [periodDays, byDay, today]); // eslint-disable-line react-hooks/exhaustive-deps

	// período atual vs o mesmo número de dias antes; só há dados para 60 dias, por isso 60 não tem comparação
	const growthPctNum = useMemo(() => {
		if (periodDays >= 60) return null;
		const cur = chartRows.reduce((t, r) => t + r.views, 0);
		const prev = series(periodDays, periodDays).reduce((t, r) => t + r.views, 0);
		return prev > 0 ? ((cur - prev) / prev) * 100 : null;
	}, [chartRows, periodDays]); // eslint-disable-line react-hooks/exhaustive-deps

	let xAxisMinTickGap: number | undefined;
	if (periodDays <= 7) {
		xAxisMinTickGap = undefined;
	} else if (periodDays >= 60) {
		xAxisMinTickGap = 20;
	} else {
		xAxisMinTickGap = 28;
	}

	return (
		<Card
			className={cn(
				"shadow-none md:col-span-2 lg:col-span-3 dark:ring-0",
				className
			)}
			{...props}
		>
			<CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
				<div className="min-w-0 space-y-2">
					<div className="flex flex-wrap items-center gap-2">
						<CardTitle >Views por dia</CardTitle>
						{growthPctNum != null && (
							<Delta value={growthPctNum} variant="badge">
								<DeltaIcon variant="trend" />
								<DeltaValue />
							</Delta>
						)}
					</div>
					<CardDescription>
						Soma das views dos reels publicados em cada dia, vs o período anterior.
					</CardDescription>
				</div>
				<Select
					items={[{ value: "7", label: "Últimos 7 dias" }, { value: "30", label: "Últimos 30 dias" }, { value: "60", label: "Últimos 60 dias" }]}
					onValueChange={(v) => {
						const n = Number(v);
						setPeriodDays(n as PeriodDays);
					}}
					value={String(periodDays)}
				>
					<SelectTrigger
						aria-label="Período das views"
						className="w-full min-w-36 sm:w-fit"
						size="sm"
					>
						<SelectValue placeholder="Período" />
					</SelectTrigger>
					<SelectContent align="end">
						<SelectItem value="7">Últimos 7 dias</SelectItem>
						<SelectItem value="30">Últimos 30 dias</SelectItem>
						<SelectItem value="60">Últimos 60 dias</SelectItem>
					</SelectContent>
				</Select>
			</CardHeader>
			<CardContent>
				<ChartContainer className="aspect-22/8 w-full" config={chartConfig}>
					<AreaChart
						accessibilityLayer
						data={chartRows}
						margin={{ left: 4, right: 8, top: 8, bottom: 0 }}
					>
						<defs>
							<linearGradient id={idAreaGradient} x1="0" x2="0" y1="0" y2="1">
								<stop
									offset="0%"
									stopColor="var(--color-views)"
									stopOpacity={0.45}
								/>
								<stop
									offset="55%"
									stopColor="var(--color-views)"
									stopOpacity={0.12}
								/>
								<stop
									offset="100%"
									stopColor="var(--color-views)"
									stopOpacity={0}
								/>
							</linearGradient>
						</defs>
						<CartesianGrid className="stroke-border" vertical={false} />
						<XAxis
							axisLine={false}
							dataKey="date"
							interval={periodDays <= 7 ? 0 : "preserveStartEnd"}
							minTickGap={xAxisMinTickGap}
							tickFormatter={(value) =>
								formatChartAxisTick(String(value), periodDays)
							}
							tickLine={false}
							tickMargin={8}
						/>
						<YAxis
							axisLine={false}
							tick={{ className: "tabular-nums" }}
							tickFormatter={(v) => new Intl.NumberFormat("pt-PT", { notation: "compact" }).format(Number(v))}
							tickLine={false}
							tickMargin={8}
							width={56}
						/>
						<ChartTooltip
							content={
								<ChartTooltipContent
									className="min-w-34"
									indicator="line"
									labelFormatter={(_, payload) => {
										const row = payload?.[0]?.payload as VolumeRow | undefined;
										if (!row?.date) {
											return "";
										}
										return formatChartTooltipDate(row.date, "long");
									}}
								/>
							}
							cursor={false}
						/>
						<Area
							dataKey="views"
							dot={false}
							fill={`url(#${idAreaGradient})`}
							stroke="var(--color-views)"
							strokeWidth={2}
							type="monotone"
						/>
					</AreaChart>
				</ChartContainer>
			</CardContent>
		</Card>
	);
}
