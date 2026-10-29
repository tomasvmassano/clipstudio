"use client";

import Link from "next/link";
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
import { stripWs } from "@/lib/ws-path";

/** base: prefixo do cliente (/c/<cliente>) para os caminhos relativos do menu do cliente; vazio na agência. */
export function NavGroup({ label, items, base = "", all }: SidebarNavGroup & { base?: string; all: SidebarNavGroup[] }) {
	const pathname = usePathname();
	const active = activeFor(base ? stripWs(pathname) : pathname, all);
	const href = (p?: string) => (base ? `${base}${p === "/" ? "" : p ?? ""}` || "/" : p ?? "/");
	const { can, canOrg, mode } = useSession();
	// Antes de saber a sessão mostra tudo (evita saltos); depois só o que a capacidade permite.
	const visible = items.filter((i) => {
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
					return (
						<Collapsible className="group/collapsible" defaultOpen={isActive || item.subItems?.some((i) => active?.path === i.path)} key={item.title} render={<SidebarMenuItem />}>
							{item.subItems?.length ? (
								<>
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
								</>
							) : item.soon || !item.path ? (
								<>
									<SidebarMenuButton aria-disabled="true" className="cursor-default opacity-50 hover:bg-transparent" tooltip={`${item.title}: ainda não disponível`}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
									<SidebarMenuBadge className="text-[10px] font-normal text-muted-foreground">em breve</SidebarMenuBadge>
								</>
							) : (
								<SidebarMenuButton isActive={isActive} tooltip={item.title} render={<Link href={href(item.path)} />}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
							)}
						</Collapsible>
					);
				})}
			</SidebarMenu>
		</SidebarGroup>
	);
}
