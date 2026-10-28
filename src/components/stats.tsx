import { cn } from "@/lib/utils";
import {
	Card,
	CardContent,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import { Delta, DeltaIcon, DeltaValue } from "@/components/delta";

export type Stat = {
	label: string;
	value: string;
	/** Variação em %; omitida quando não há período comparável (nunca inventada). */
	delta?: number;
	footnote: string;
	/** When true, a negative delta is treated as favorable. */
	lowerIsBetter?: boolean;
};

export function DashboardStats({ stats }: { stats: readonly Stat[] }) {
	return (
		<>
			{stats.map((s) => (
				<Card className={cn("shadow-none dark:ring-0")} key={s.label}>
					<CardHeader>
						<CardTitle className="font-normal text-muted-foreground text-xs">
							{s.label}
						</CardTitle>
					</CardHeader>
					<CardContent className="flex flex-col gap-2">
						<p className="font-semibold text-2xl tabular-nums">{s.value}</p>
						<div className="flex items-center gap-1 text-xs">
							{s.delta != null && (
								<Delta value={s.lowerIsBetter ? -s.delta : s.delta}>
									<DeltaIcon />
									<DeltaValue />
								</Delta>
							)}
							<span className="text-muted-foreground">{s.footnote}</span>
						</div>
					</CardContent>
				</Card>
			))}
		</>
	);
}
