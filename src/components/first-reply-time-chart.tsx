"use client";

import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { CartesianGrid, LabelList, Line, LineChart, XAxis } from "recharts";
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
import { Delta, DeltaIcon, DeltaValue } from "@/components/delta";

export type WeekRow = { day: string; media: number };

const chartConfig = {
	media: {
		label: "Média por reel",
		color: "var(--chart-2)",
	},
} satisfies ChartConfig;

const compact = (n: number) => new Intl.NumberFormat("pt-PT", { notation: "compact", maximumFractionDigits: 1 }).format(n);

export function FirstReplyTimeChart({
	className,
	rows: chartRows,
	...props
}: ComponentProps<typeof Card> & { rows: WeekRow[] }) {
	const first = chartRows[0]?.media ?? 0;
	const last = chartRows.at(-1)?.media ?? first;
	const changePct = first > 0 ? ((last - first) / first) * 100 : null;
	return (
		<Card
			className={cn("shadow-none md:col-span-2 dark:ring-0", className)}
			{...props}
		>
			<CardHeader className="space-y-1">
				<div className="flex flex-wrap items-center gap-2">
					<CardTitle >Views médias por reel</CardTitle>
					{changePct != null && chartRows.length > 1 && (
						<Delta value={changePct} variant="badge">
							<DeltaIcon variant="trend" />
							<DeltaValue />
						</Delta>
					)}
				</div>
				<CardDescription>
					Por semana de publicação, últimas 7 semanas com reels.
				</CardDescription>
			</CardHeader>
			<CardContent>
				{chartRows.length === 0 ? (<p className="py-10 text-center text-muted-foreground text-sm">Ainda não há reels guardados.</p>) : (
				<ChartContainer className="aspect-video w-full" config={chartConfig}>
					<LineChart
						accessibilityLayer
						data={chartRows}
						margin={{ top: 24, left: 28, right: 28, bottom: 8 }}
					>
						<CartesianGrid className="stroke-border" vertical={false} />
						<XAxis
							axisLine={false}
							dataKey="day"
							interval={0}
							tickFormatter={(value) => String(value)}
							tickLine={false}
							tickMargin={8}
						/>
						<ChartTooltip
							content={<ChartTooltipContent indicator="line" />}
							cursor={false}
						/>
						<Line
							activeDot={{ r: 6 }}
							dataKey="media"
							dot={{ fill: "var(--color-media)" }}
							stroke="var(--color-media)"
							strokeWidth={2}
							type="monotone"
						>
							<LabelList
								className="fill-foreground"
								dataKey="media"
								fontSize={12}
								formatter={(label) => {
									const n = Number(label);
									return Number.isFinite(n) ? compact(n) : String(label ?? "");
								}}
								offset={12}
								position="top"
							/>
						</Line>
					</LineChart>
				</ChartContainer>
				)}
			</CardContent>
		</Card>
	);
}
