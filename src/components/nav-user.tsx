"use client";

import Link from "next/link";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuGroup,
	DropdownMenuItem,
	DropdownMenuLabel,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useSession } from "@/components/session-provider";
import { KeyRoundIcon, MonitorPlayIcon, BotIcon, FileTextIcon, LogOutIcon } from "lucide-react";

const initials = (s: string) => s.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase()).join("") || "?";

export function NavUser() {
	const { session, signOut, setDialogOpen } = useSession();
	const name = session ? session.label ?? session.role : "Sem sessão";
	const sub = session ? `${session.client_id} · ${session.role}` : "Só leitura";
	return (
		<DropdownMenu>
			<DropdownMenuTrigger render={<Avatar className="size-8 cursor-pointer" aria-label="Menu da conta" />}>
				<AvatarFallback className="text-xs">{session ? initials(name) : "?"}</AvatarFallback>
			</DropdownMenuTrigger>
			<DropdownMenuContent align="end" className="w-60">
				<DropdownMenuGroup>
					<DropdownMenuLabel className="pointer-events-none flex items-center gap-2">
						<Avatar className="isolate size-8">
							<AvatarFallback className="text-xs">{session ? initials(name) : "?"}</AvatarFallback>
						</Avatar>
						<div className="min-w-0">
							<span className="font-medium text-foreground">{name}</span>
							<div className="truncate text-muted-foreground text-xs">{sub}</div>
						</div>
					</DropdownMenuLabel>
				</DropdownMenuGroup>
				<DropdownMenuSeparator />
				<DropdownMenuGroup>
					<DropdownMenuItem render={<Link href="/teleprompter" />}><MonitorPlayIcon />Teleprompter</DropdownMenuItem>
					<DropdownMenuItem render={<Link href="/agentes" />}><BotIcon />Sala dos agentes</DropdownMenuItem>
					<DropdownMenuItem render={<a href="https://claude.ai/artifact/CboQfT6zRXsRbxDxW7QsMg" target="_blank" rel="noopener" />}><FileTextIcon />PRD v2.1</DropdownMenuItem>
				</DropdownMenuGroup>
				<DropdownMenuSeparator />
				<DropdownMenuGroup>
					{session ? (
						<DropdownMenuItem variant="destructive" onClick={signOut}><LogOutIcon />Sair</DropdownMenuItem>
					) : (
						<DropdownMenuItem onClick={() => setDialogOpen(true)}><KeyRoundIcon />Entrar com código</DropdownMenuItem>
					)}
				</DropdownMenuGroup>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}
