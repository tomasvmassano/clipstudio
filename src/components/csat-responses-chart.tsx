"use client";

import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { Bar, BarChart, Rectangle, XAxis } from "recharts";
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

export type ProdRow = { day: string; validados: number; gravados: number; rejeitados: number };

const chartConfig = {
	validados: { label: "Validados", color: "var(--chart-2)" },
	gravados: { label: "Gravados", color: "var(--chart-1)" },
	rejeitados: { label: "Rejeitados", color: "var(--chart-5)" },
} satisfies ChartConfig;

/** Half of bar width (8) so ends read as fully rounded “caps”. */
const BAR_RADIUS = 5;

/**
 *  column hover background.
 */
function ColumnHoverCursor(props: React.ComponentProps<typeof Rectangle>) {
	return (
		<Rectangle
			fill="var(--muted)"
			fillOpacity={0.5}
			radius={BAR_RADIUS * 2}
			stroke="none"
			{...props}
		/>
	);
}

export function CsatResponsesChart({
	className,
	rows,
	...props
}: ComponentProps<typeof Card> & { rows: ProdRow[] }) {
	return (
		<Card
			className={cn("shadow-none md:col-span-2 dark:ring-0", className)}
			{...props}
		>
			<CardHeader>
				<CardTitle >Produção diária</CardTitle>
				<CardDescription>
					Guiões validados, gravados e rejeitados por dia, últimos 10 dias.
				</CardDescription>
			</CardHeader>
			<CardContent>
				{rows.every((r) => !r.validados && !r.gravados && !r.rejeitados) ? (<p className="py-10 text-center text-muted-foreground text-sm">Ainda nada validado, gravado ou rejeitado nestes dias.</p>) : (
				<ChartContainer className="aspect-video w-full" config={chartConfig}>
					<BarChart accessibilityLayer data={rows}>
						<XAxis
							axisLine={false}
							dataKey="day"
							interval={0}
							minTickGap={8}
							tickFormatter={(value) => String(value)}
							tickLine={false}
							tickMargin={10}
						/>
						<ChartTooltip
							content={<ChartTooltipContent hideLabel />}
							cursor={<ColumnHoverCursor />}
						/>
						<Bar
							background={{
								fill: "var(--muted)",
								radius: BAR_RADIUS,
							}}
							barSize={8}
							dataKey="rejeitados"
							fill="var(--color-rejeitados)"
							overflow="visible"
							radius={[0, 0, BAR_RADIUS, BAR_RADIUS]}
							stackId="prod"
						/>
						<Bar
							barSize={8}
							dataKey="gravados"
							fill="var(--color-gravados)"
							overflow="visible"
							radius={0}
							stackId="prod"
						/>
						<Bar
							barSize={8}
							dataKey="validados"
							fill="var(--color-validados)"
							overflow="visible"
							radius={[BAR_RADIUS, BAR_RADIUS, 0, 0]}
							stackId="prod"
						/>
					</BarChart>
				</ChartContainer>
				)}
			</CardContent>
		</Card>
	);
}
