import Link from "next/link";
import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { words } from "@/lib/data";
import { FORMATO_LABEL, WPS, type Guiao } from "@/lib/types";
import { ArrowRightIcon } from "lucide-react";

function estado(g: Guiao): { label: string; variant: ComponentProps<typeof Badge>["variant"] } {
	if (g.status === "rejeitado") return { label: "Rejeitado", variant: "destructive" };
	if (g.gravado) return { label: "Gravado", variant: "secondary" };
	if (g.validado) return { label: "Validado", variant: "default" };
	return { label: "Por validar", variant: "outline" };
}

/** Os próximos guiões do dia: primeiro os que ainda não foram gravados. */
export function RecentConversations({
	className,
	guioes,
	...props
}: ComponentProps<typeof Card> & { guioes: Guiao[] }) {
	const rows = [...guioes].sort((a, b) => Number(a.gravado) - Number(b.gravado) || a.n - b.n).slice(0, 5);
	return (
		<Card
			className={cn("gap-0 shadow-none md:col-span-2 dark:ring-0", className)}
			{...props}
		>
			<CardHeader className="border-b">
				<CardTitle >Guiões de hoje</CardTitle>
				<CardDescription>{guioes.length ? `Os próximos ${rows.length} de ${guioes.length}, por gravar primeiro` : "Ainda não há guiões para hoje"}</CardDescription>
			</CardHeader>
			<CardContent className="p-0">
				<Table>
					<TableHeader>
						<TableRow className="hover:bg-transparent">
							<TableHead className="pl-6">#</TableHead>
							<TableHead className="hidden sm:table-cell">Tema</TableHead>
							<TableHead>Formato</TableHead>
							<TableHead className="text-right">Duração</TableHead>
							<TableHead className="pr-6 text-right">Estado</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{rows.map((g) => {
							const st = estado(g);
							const dur = Math.round((words(g.corpo) + words(g.hooks[0]?.text)) / WPS);
							return (
								<TableRow className="h-14 hover:bg-transparent" key={g.id}>
									<TableCell className="pl-6 font-medium font-mono tabular-nums">{g.n}</TableCell>
									<TableCell className="hidden max-w-48 sm:table-cell">
										<span className="line-clamp-1 text-muted-foreground text-sm">{g.tema}</span>
									</TableCell>
									<TableCell>
										<span className="font-medium text-sm">{FORMATO_LABEL[g.formato ?? ""] ?? g.formato}</span>
									</TableCell>
									<TableCell className="text-right text-muted-foreground text-sm tabular-nums">~{dur}s</TableCell>
									<TableCell className="pr-6 text-right">
										<Badge variant={st.variant}>{st.label}</Badge>
									</TableCell>
								</TableRow>
							);
						})}
					</TableBody>
				</Table>
				<div className="flex justify-center border-t py-3">
					<Button size="sm" variant="ghost" render={<Link href="/guioes" />} nativeButton={false}>Ver todos os guiões
						<ArrowRightIcon aria-hidden="true" data-icon="inline-end" /></Button>
				</div>
			</CardContent>
		</Card>
	);
}
