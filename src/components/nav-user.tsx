"use client";

import { WsLink } from "@/components/ws-link";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { avatarUrl } from "@/lib/profile";
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
import { LogInIcon, MonitorPlayIcon, BotIcon, FileTextIcon, LogOutIcon, UserRoundIcon } from "lucide-react";
import { ROLE_LABEL } from "@/lib/access";

const initials = (s: string) => s.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase()).join("") || "?";

export function NavUser() {
	const { mode, label, ws, signOut, profile } = useSession();
	const [img, setImg] = useState<string | null>(null);
	useEffect(() => { let alive = true; avatarUrl(profile?.avatar_path).then((u) => { if (alive) setImg(u); }); return () => { alive = false; }; }, [profile?.avatar_path]);
	const signed = mode === "user" || mode === "code";
	const name = signed ? label ?? "" : "Sem sessão";
	const sub = signed ? (ws ? `${ws.name} · ${ROLE_LABEL[ws.role] ?? ws.role}` : "Sem workspace") : "Entra para continuar";
	return (
		<DropdownMenu>
			<DropdownMenuTrigger render={<button type="button" className="rounded-full focus-visible:outline-2 focus-visible:outline-ring" aria-label="Menu da conta" />}>
				<Avatar className="size-8 cursor-pointer">
					{img && <AvatarImage src={img} alt="" />}<AvatarFallback className="text-xs">{signed ? initials(name) : "?"}</AvatarFallback>
				</Avatar>
			</DropdownMenuTrigger>
			<DropdownMenuContent align="end" className="w-60">
				<DropdownMenuGroup>
					<DropdownMenuLabel className="pointer-events-none flex items-center gap-2">
						<Avatar className="isolate size-8">
							{img && <AvatarImage src={img} alt="" />}<AvatarFallback className="text-xs">{signed ? initials(name) : "?"}</AvatarFallback>
						</Avatar>
						<div className="min-w-0">
							<span className="font-medium text-foreground">{name}</span>
							<div className="truncate text-muted-foreground text-xs">{sub}</div>
						</div>
					</DropdownMenuLabel>
				</DropdownMenuGroup>
				<DropdownMenuSeparator />
				<DropdownMenuGroup>
					{mode === "user" && <DropdownMenuItem render={<WsLink href="/perfil" />}><UserRoundIcon />Perfil</DropdownMenuItem>}
					<DropdownMenuItem render={<WsLink href="/teleprompter" />}><MonitorPlayIcon />Teleprompter</DropdownMenuItem>
					<DropdownMenuItem render={<WsLink href="/agentes" />}><BotIcon />Sala dos agentes</DropdownMenuItem>
					<DropdownMenuItem render={<a href="https://claude.ai/artifact/CboQfT6zRXsRbxDxW7QsMg" target="_blank" rel="noopener" />}><FileTextIcon />PRD v2.1</DropdownMenuItem>
				</DropdownMenuGroup>
				<DropdownMenuSeparator />
				<DropdownMenuGroup>
					{signed ? (
						<DropdownMenuItem variant="destructive" onClick={signOut}><LogOutIcon />Sair</DropdownMenuItem>
					) : (
						<DropdownMenuItem render={<Link href="/login" />}><LogInIcon />Entrar</DropdownMenuItem>
					)}
				</DropdownMenuGroup>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}
