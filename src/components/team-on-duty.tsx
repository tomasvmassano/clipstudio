"use client";

import Link from "next/link";
import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuLabel,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { StatusIndicator } from "@/components/indicator";
import { AGENTS } from "@/lib/agents";
import { relTime, type HojeAgente } from "@/lib/hoje";
import { EllipsisIcon, BotIcon } from "lucide-react";

const STATUS: Record<string, { label: string; color: "emerald" | "amber" | "rose" | "sky"; pulse?: boolean }> = {
	start: { label: "A começar", color: "amber", pulse: true },
	think: { label: "A pensar", color: "amber", pulse: true },
	talk: { label: "A falar", color: "emerald", pulse: true },
	done: { label: "Terminou", color: "emerald", pulse: false },
	error: { label: "Erro", color: "rose" },
};

/** Agentes da última corrida real do motor (ensaios ficam de fora). */
export function TeamOnDuty({
	className,
	agentes,
	...props
}: ComponentProps<typeof Card> & { agentes: HojeAgente[] }) {
	const byId = new Map(agentes.map((a) => [a.agent, a]));
	const last = agentes.reduce<string | null>((t, a) => (!t || a.created_at > t ? a.created_at : t), null);
	return (
		<Card className={cn("shadow-none dark:ring-0", className)} {...props}>
			<CardHeader className="border-b">
				<CardTitle >Agentes</CardTitle>
				<CardDescription>{last ? `Última corrida do motor ${relTime(last)}` : "Ainda não houve corridas reais do motor."}</CardDescription>
			</CardHeader>
			<CardContent className="p-0">
				<ul className="flex flex-col divide-y divide-border">
					{AGENTS.slice(0, 6).map((ag) => {
						const a = byId.get(ag.id);
						const st = a ? STATUS[a.status] ?? STATUS.done : null;
						return (
							<li className="flex items-center gap-2 p-3 first:pt-0 last:pb-0 sm:gap-3" key={ag.id}>
								<Avatar className="size-8">
									<AvatarFallback className="text-xs font-semibold" style={{ color: ag.cor }}>{ag.nome.slice(0, 2)}</AvatarFallback>
								</Avatar>
								<div className="min-w-0 flex-1 pr-1">
									<p className="truncate font-medium text-foreground text-sm leading-snug">{ag.nome}</p>
									<p className="flex items-center gap-2 text-[10px] leading-snug">
										<span className="flex shrink-0 items-center gap-1">
											{st ? <StatusIndicator color={st.color} pulse={st.pulse} /> : <StatusIndicator color="sky" pulse={false} />}
											{st ? st.label : "Sem atividade"}
										</span>
										<span className="inline-flex size-1 rounded-full bg-foreground/80" />
										<span className="truncate tabular-nums">{a ? `${a.passos} passos` : ag.papel}</span>
									</p>
								</div>
								<DropdownMenu>
									<DropdownMenuTrigger render={<Button aria-label={`Ações para ${ag.nome}`} size="icon-xs" variant="ghost" />}><EllipsisIcon /></DropdownMenuTrigger>
									<DropdownMenuContent align="end" className="min-w-52">
										<DropdownMenuLabel className="font-normal text-muted-foreground text-xs">{ag.nome}</DropdownMenuLabel>
										<DropdownMenuSeparator />
										<DropdownMenuItem className="gap-2" render={<Link href="/agentes" />}>
											<BotIcon className="size-4 opacity-70" />
											Ver na sala
										</DropdownMenuItem>
									</DropdownMenuContent>
								</DropdownMenu>
							</li>
						);
					})}
				</ul>
			</CardContent>
		</Card>
	);
}
