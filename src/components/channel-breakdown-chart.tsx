"use client";

import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { LabelList, Pie, PieChart } from "recharts";
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
	ChartLegend,
	ChartLegendContent,
} from "@/components/ui/chart";

export type MixDatum = { key: string; label: string; share: number };

const COLORS = ["var(--chart-1)", "var(--chart-2)", "var(--chart-3)", "var(--chart-4)", "var(--chart-5)"];

export function ChannelBreakdownChart({
	className,
	data,
	total,
	...props
}: ComponentProps<typeof Card> & { data: MixDatum[]; total: number }) {
	const chartConfig: ChartConfig = { share: { label: "Peso" } };
	data.forEach((d, i) => { chartConfig[d.key] = { label: d.label, color: COLORS[i % COLORS.length] }; });
	const chartData = data.map((d) => ({ channel: d.key, share: d.share, fill: `var(--color-${d.key})` }));
	return (
		<Card
			className={cn("flex flex-col shadow-none dark:ring-0", className)}
			{...props}
		>
			<CardHeader className="items-center space-y-1 pb-0 sm:items-start">
				<div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start">
					<CardTitle >Formatos de hoje</CardTitle>
				</div>
				<CardDescription>
					Peso de cada formato nos {total} guiões do dia
				</CardDescription>
			</CardHeader>
			<CardContent className="my-auto">
				{total === 0 ? (<p className="py-10 text-center text-muted-foreground text-sm">Ainda não há guiões hoje.</p>) : (
				<ChartContainer
					className="mx-auto aspect-square max-h-72 w-full"
					config={chartConfig}
				>
					<PieChart accessibilityLayer>
						<Pie
							cornerRadius={8}
							data={chartData}
							dataKey="share"
							innerRadius={36}
							nameKey="channel"
							outerRadius="88%"
							stroke="var(--card)"
							strokeWidth={4}
						>
							<LabelList
								className="fill-background font-medium"
								dataKey="share"
								fill="currentColor"
								fontWeight={500}
								formatter={(label) => {
									const n = Number(label);
									return Number.isFinite(n) ? `${n}%` : String(label ?? "");
								}}
								position="inside"
								stroke="none"
							/>
						</Pie>
						<ChartLegend content={<ChartLegendContent nameKey="channel" className="flex-wrap gap-x-3 gap-y-1" />} />
					</PieChart>
				</ChartContainer>
				)}
			</CardContent>
		</Card>
	);
}
