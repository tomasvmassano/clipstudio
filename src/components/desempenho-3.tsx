/**
 * Cartões de lista do Desempenho no estilo do efferd dashboard-3
 * (mesmas classes de team-on-duty, recent-conversations e support-activity).
 */
import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import {
	Table,
	TableBody,
	TableCell,
	TableHead,
	TableHeader,
	TableRow,
} from "@/components/ui/table";
import { fmtCompact, fmtDay, fmtInt, type Desempenho, type ReelRow } from "@/lib/desempenho";
import { ExternalLinkIcon, FilmIcon } from "lucide-react";

const reelUrl = (r: ReelRow) => r.url ?? `https://www.instagram.com/reel/${r.id}/`;
const titulo = (r: ReelRow) => r.titulo?.trim() || `Reel ${r.id}`;

/** Mediana do cliente vs criadores de referência, no formato do "Team on duty". */
export function ReferenciasCard({
	className,
	d,
	clienteLabel,
	...props
}: ComponentProps<typeof Card> & { d: Desempenho; clienteLabel: string }) {
	const rows = [
		{ owner: clienteLabel, mediana: d.kpi.mediana ?? 0, n: d.kpi.reels, me: true },
		...d.referencias.map((r) => ({ owner: r.owner, mediana: r.mediana, n: r.n, me: false })),
	].sort((a, b) => b.mediana - a.mediana);
	const max = Math.max(1, ...rows.map((r) => r.mediana));
	return (
		<Card className={cn("shadow-none dark:ring-0", className)} {...props}>
			<CardHeader className="border-b">
				<CardTitle >Mediana vs referências</CardTitle>
				<CardDescription>Views medianas por reel, top reels de cada perfil</CardDescription>
			</CardHeader>
			<CardContent className="p-0">
				<ul className="flex flex-col divide-y divide-border">
					{rows.map((r) => (
						<li className="flex items-center gap-2 p-3 first:pt-0 last:pb-0 sm:gap-3" key={r.owner}>
							<Avatar className="size-8">
								<AvatarFallback className={cn("text-xs", r.me && "bg-primary text-primary-foreground")}>{r.owner.slice(0, 2).toUpperCase()}</AvatarFallback>
							</Avatar>
							<div className="min-w-0 flex-1 pr-1">
								<p className={cn("truncate text-foreground text-sm leading-snug", r.me ? "font-semibold" : "font-medium")}>@{r.owner}</p>
								<div className="mt-1 h-1 w-full overflow-hidden rounded-full bg-muted">
									<div className={cn("h-full rounded-full", r.me ? "bg-primary" : "bg-muted-foreground/50")} style={{ width: `${(r.mediana / max) * 100}%` }} />
								</div>
							</div>
							<span className="shrink-0 font-medium text-sm tabular-nums">{fmtCompact(r.mediana)}</span>
						</li>
					))}
				</ul>
			</CardContent>
		</Card>
	);
}

/** Top reels no formato do "Recent conversations". */
export function TopReelsCard({
	className,
	rows,
	...props
}: ComponentProps<typeof Card> & { rows: ReelRow[] }) {
	return (
		<Card className={cn("gap-0 shadow-none md:col-span-2 dark:ring-0", className)} {...props}>
			<CardHeader className="border-b">
				<CardTitle >Reels com mais views</CardTitle>
				<CardDescription>Outlier = views a dividir pela mediana do criador; 2× ou mais é viral</CardDescription>
			</CardHeader>
			<CardContent className="p-0">
				{rows.length === 0 ? (
					<p className="px-6 py-10 text-center text-muted-foreground text-sm">Ainda não há reels guardados para esta conta.</p>
				) : (
					<Table>
						<TableHeader>
							<TableRow className="hover:bg-transparent">
								<TableHead className="pl-6">Reel</TableHead>
								<TableHead className="hidden text-right sm:table-cell">Comentários</TableHead>
								<TableHead className="text-right">Views</TableHead>
								<TableHead className="pr-6 text-right">Outlier</TableHead>
							</TableRow>
						</TableHeader>
						<TableBody>
							{rows.slice(0, 6).map((r) => (
								<TableRow className="h-14 hover:bg-transparent" key={r.id}>
									<TableCell className="max-w-56 pl-6 font-medium">
										<a className="inline-flex max-w-full items-center gap-1.5 hover:underline" href={reelUrl(r)} rel="noopener" target="_blank">
											<span className="truncate">{titulo(r)}</span>
											<ExternalLinkIcon className="size-3 shrink-0 text-muted-foreground" />
										</a>
									</TableCell>
									<TableCell className="hidden text-right text-muted-foreground text-sm tabular-nums sm:table-cell">{fmtInt(r.comments)}</TableCell>
									<TableCell className="text-right font-medium text-sm tabular-nums">{fmtCompact(r.views)}</TableCell>
									<TableCell className="pr-6 text-right">
										{r.outlier != null && <Badge variant={r.outlier >= 2 ? "default" : r.outlier < 0.5 ? "destructive" : "secondary"}>{r.outlier.toFixed(1)}×</Badge>}
									</TableCell>
								</TableRow>
							))}
						</TableBody>
					</Table>
				)}
			</CardContent>
		</Card>
	);
}

/** Últimos publicados no formato do "Workspace activity". */
export function RecentesCard({
	className,
	rows,
	...props
}: ComponentProps<typeof Card> & { rows: ReelRow[] }) {
	return (
		<Card className={cn("gap-0 shadow-none dark:ring-0", className)} {...props}>
			<CardHeader className="border-b">
				<CardTitle >Últimos publicados</CardTitle>
				<CardDescription>Os mais recentes guardados pelo scraper.</CardDescription>
			</CardHeader>
			<CardContent className="px-0">
				{rows.length === 0 ? (
					<p className="px-6 py-8 text-center text-muted-foreground text-xs">Sem publicações guardadas.</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{rows.slice(0, 5).map((r) => (
							<li className="flex h-18 items-center gap-3 px-3" key={r.id}>
								<span aria-hidden="true" className="flex size-10 shrink-0 items-center justify-center [&_svg]:size-4">
									<FilmIcon />
								</span>
								<div className="min-w-0 flex-1 space-y-1">
									<a className="line-clamp-2 text-pretty text-foreground text-xs leading-snug hover:underline" href={reelUrl(r)} rel="noopener" target="_blank">
										{titulo(r)}
									</a>
									<p className="text-muted-foreground text-xs tabular-nums">
										{fmtDay(r.dt)} · {fmtCompact(r.views)} views{r.outlier != null ? ` · ${r.outlier.toFixed(1)}×` : ""}
									</p>
								</div>
							</li>
						))}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}
