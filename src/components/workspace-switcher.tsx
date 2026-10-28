"use client";

import Link from "next/link";
import { CheckIcon, ChevronsUpDownIcon } from "lucide-react";
import { LogoIcon } from "@/components/logo";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuGroup,
	DropdownMenuItem,
	DropdownMenuLabel,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL } from "@/lib/access";

/**
 * Troca de workspace (PRD: o staff da agência alterna entre clientes autorizados; o staff do cliente fica no seu).
 * A lista vem de my_context(), que só devolve workspaces onde o utilizador tem acesso ativo.
 */
export function WorkspaceSwitcher() {
	const { ws, workspaces, setWorkspace } = useSession();
	const title = ws?.name ?? "ClipStudio";

	if (workspaces.length <= 1) {
		return (
			<SidebarMenuButton render={<Link href="/" />}>
				<LogoIcon />
				<span className="truncate font-medium">{title}</span>
			</SidebarMenuButton>
		);
	}

	return (
		<DropdownMenu>
			<DropdownMenuTrigger render={<SidebarMenuButton aria-label="Trocar de cliente" />}>
				<LogoIcon />
				<span className="truncate font-medium">{title}</span>
				<ChevronsUpDownIcon className="ml-auto size-4 opacity-60" />
			</DropdownMenuTrigger>
			<DropdownMenuContent align="start" className="w-64">
				<DropdownMenuGroup>
					<DropdownMenuLabel className="text-xs text-muted-foreground">Clientes a que tens acesso</DropdownMenuLabel>
					{workspaces.map((w) => (
						<DropdownMenuItem key={w.id} onClick={() => setWorkspace(w.id)}>
							<div className="min-w-0 flex-1">
								<div className="truncate">{w.name}</div>
								<div className="truncate text-xs text-muted-foreground">{ROLE_LABEL[w.role] ?? w.role}</div>
							</div>
							{w.id === ws?.id && <CheckIcon className="size-4" />}
						</DropdownMenuItem>
					))}
				</DropdownMenuGroup>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}
