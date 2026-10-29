"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import {
	Collapsible,
	CollapsibleContent,
	CollapsibleTrigger,
} from "@/components/ui/collapsible";
import {
	SidebarGroup,
	SidebarGroupLabel,
	SidebarMenu,
	SidebarMenuBadge,
	SidebarMenuButton,
	SidebarMenuItem,
	SidebarMenuSub,
	SidebarMenuSubButton,
	SidebarMenuSubItem,
} from "@/components/ui/sidebar";
import { activeFor, type SidebarNavGroup } from "@/components/app-shared";
import { ChevronRightIcon } from "lucide-react";
import { useSession } from "@/components/session-provider";
import { stripWs, wsIdFromPath } from "@/lib/ws-path";
import { useFlags } from "@/lib/flags";

/** base: prefixo do cliente (/c/<cliente>) para os caminhos relativos do menu do cliente; vazio na agência. */
export function NavGroup({ label, items, base = "", all }: SidebarNavGroup & { base?: string; all: SidebarNavGroup[] }) {
	const pathname = usePathname();
	const active = activeFor(base ? stripWs(pathname) : pathname, all);
	const href = (p?: string) => (base ? `${base}${p === "/" ? "" : p ?? ""}` || "/" : p ?? "/");
	const { can, canOrg, mode, access } = useSession();
	const needsFlags = items.some((i) => i.flag);
	const flags = useFlags(base ? wsIdFromPath(pathname) : null, access?.token ?? null, needsFlags && mode !== "loading");
	// Antes de saber a sessão mostra tudo (evita saltos); depois só o que a capacidade permite.
	const visible = items.filter((i) => {
		if (i.flag && !flags?.has(i.flag)) return false;
		if (i.orgCap) return mode !== "loading" && canOrg(i.orgCap);
		return !i.cap || mode === "loading" || can(i.cap);
	});
	if (visible.length === 0) return null;
	return (
		<SidebarGroup>
			{label && <SidebarGroupLabel>{label}</SidebarGroupLabel>}
			<SidebarMenu>
				{visible.map((item) => {
					const isActive = active?.path === item.path && !!item.path;
					const childActive = !!item.subItems?.some((i) => active?.path === i.path);
					if (item.subItems?.length) {
						return (
							<SubGroup key={item.title} active={isActive || childActive}>
								<CollapsibleTrigger render={<SidebarMenuButton isActive={isActive} />}>{item.icon}<span>{item.title}</span><ChevronRightIcon className="ml-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" /></CollapsibleTrigger>
								<CollapsibleContent>
									<SidebarMenuSub>
										{item.subItems.map((subItem) => (
											<SidebarMenuSubItem key={subItem.title}>
												<SidebarMenuSubButton isActive={active?.path === subItem.path} render={<Link href={href(subItem.path)} />}>{subItem.icon}<span>{subItem.title}</span></SidebarMenuSubButton>
											</SidebarMenuSubItem>
										))}
									</SidebarMenuSub>
								</CollapsibleContent>
							</SubGroup>
						);
					}
					return (
						<SidebarMenuItem key={item.title}>
							{item.soon || !item.path ? (
								<>
									<SidebarMenuButton aria-disabled="true" className="cursor-default opacity-50 hover:bg-transparent" tooltip={`${item.title}: ainda não disponível`}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
									<SidebarMenuBadge className="text-[10px] font-normal text-muted-foreground">em breve</SidebarMenuBadge>
								</>
							) : (
								<SidebarMenuButton isActive={isActive} tooltip={item.title} render={<Link href={href(item.path)} />}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
							)}
						</SidebarMenuItem>
					);
				})}
			</SidebarMenu>
		</SidebarGroup>
	);
}

/** Grupo com submenu: estado controlado (abre quando um filho fica ativo), sem mudar o defaultOpen depois de montar. */
function SubGroup({ active, children }: { active: boolean; children: ReactNode }) {
	const [open, setOpen] = useState(active);
	const [wasActive, setWasActive] = useState(active);
	if (active !== wasActive) { setWasActive(active); if (active) setOpen(true); }
	return (
		<Collapsible className="group/collapsible" open={open} onOpenChange={setOpen} render={<SidebarMenuItem />}>
			{children}
		</Collapsible>
	);
}
