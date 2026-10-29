"use client";

import { WsLink } from "@/components/ws-link";
import { cn } from "@/lib/utils";
import type { ComponentProps } from "react";
import { Button } from "@/components/ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@/components/ui/card";
import { relTime, type HojeAtividade } from "@/lib/hoje";
import { CheckIcon, VideoIcon, XIcon, PencilIcon, BotIcon, ArrowRightIcon } from "lucide-react";

const ICON = { validado: <CheckIcon />, gravado: <VideoIcon />, rejeitado: <XIcon />, editado: <PencilIcon />, corrida: <BotIcon /> } as const;
const VERB = { validado: "validado", gravado: "gravado", rejeitado: "rejeitado", editado: "editado" } as const;

export function SupportActivity({
	className,
	items,
	...props
}: ComponentProps<typeof Card> & { items: HojeAtividade[] }) {
	return (
		<Card className={cn("gap-0 shadow-none dark:ring-0", className)} {...props}>
			<CardHeader className="border-b">
				<CardTitle >Atividade</CardTitle>
				<CardDescription>O que mudou nos guiões e no motor.</CardDescription>
			</CardHeader>
			<CardContent className="px-0">
				{items.length === 0 ? (
					<p className="px-6 py-8 text-center text-muted-foreground text-xs">Ainda nada validado, gravado ou editado.</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{items.slice(0, 4).map((item, i) => (
							<li className="flex h-18 items-center gap-3 px-3" key={`${item.tipo}-${item.n}-${item.at}-${i}`}>
								<span aria-hidden="true" className="flex size-10 shrink-0 items-center justify-center [&_svg]:size-4">
									{ICON[item.tipo]}
								</span>
								<div className="min-w-0 flex-1 space-y-1">
									<p className="line-clamp-2 text-pretty text-foreground text-xs leading-snug">
										{item.tipo === "corrida" ? `Nova ${item.tema}` : `Guião ${item.n} ${VERB[item.tipo]}: ${item.tema ?? ""}`}
									</p>
									<p className="text-muted-foreground text-xs tabular-nums">{relTime(item.at)}</p>
								</div>
							</li>
						))}
					</ul>
				)}
			</CardContent>
			<div className="flex items-center justify-center">
				<Button size="sm" variant="ghost" render={<WsLink href="/guioes" />} nativeButton={false}>Abrir guiões
					<ArrowRightIcon aria-hidden="true" data-icon="inline-end" /></Button>
			</div>
		</Card>
	);
}
