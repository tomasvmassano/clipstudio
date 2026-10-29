"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import {
	Sidebar,
	SidebarContent,
	SidebarFooter,
	SidebarGroup,
	SidebarHeader,
	SidebarMenu,
	SidebarMenuButton,
	SidebarMenuItem,
} from "@/components/ui/sidebar";
import { NavGroup } from "@/components/nav-group";
import { agencyNavGroups, clientNavGroups, footerNavLinks } from "@/components/app-shared";
import { LatestChange } from "@/components/latest-change";
import { useSession } from "@/components/session-provider";
import { ArrowLeftIcon, MonitorPlayIcon, LogInIcon, CheckIcon } from "lucide-react";
import { AgencySwitcher, WorkspaceSwitcher } from "@/components/workspace-switcher";
import { clientPath } from "@/lib/ws-path";

export function AppSidebar() {
	const { mode, label, ws, wsRequested, canOrg } = useSession();
	const signed = mode === "user" || mode === "code";
	// espaço do cliente quando o endereço é /c/<cliente>; o resto é o espaço da agência
	const inClient = !!wsRequested;
	const base = ws ? clientPath(ws.id) : "";
	const groups = inClient ? clientNavGroups : agencyNavGroups;
	return (
		<Sidebar collapsible="icon" variant="inset">
			<SidebarHeader className="h-14 justify-center">
				{inClient ? <WorkspaceSwitcher /> : <AgencySwitcher />}
			</SidebarHeader>
			<SidebarContent>
				{inClient && canOrg("dashboard.agency") && (
					<SidebarGroup className="pb-0">
						<SidebarMenu>
							<SidebarMenuItem>
								<SidebarMenuButton className="text-muted-foreground" tooltip="Voltar à agência" render={<Link href="/" />}>
									<ArrowLeftIcon /><span>Agência</span>
								</SidebarMenuButton>
							</SidebarMenuItem>
						</SidebarMenu>
					</SidebarGroup>
				)}
				{inClient && (
				<SidebarGroup>
					<SidebarMenuItem className="flex items-center gap-2">
						<SidebarMenuButton
							className="min-w-8 bg-primary text-primary-foreground duration-200 ease-linear hover:bg-primary/90 hover:text-primary-foreground active:bg-primary/90 active:text-primary-foreground"
							tooltip="Abrir teleprompter"
							render={<Link href={`${base}/teleprompter`} />}
						>
							<MonitorPlayIcon />
							<span>Gravar agora</span>
						</SidebarMenuButton>
						{signed ? (
							<span title={`Ligado: ${label}`} aria-label={`Ligado: ${label}`} className="flex size-8 items-center justify-center rounded-md border group-data-[collapsible=icon]:opacity-0">
								<CheckIcon className="size-4 text-emerald-500" />
							</span>
						) : (
							<Button aria-label="Entrar" title="Entrar" className="size-8 group-data-[collapsible=icon]:opacity-0" size="icon" variant="outline" render={<Link href="/login" />} nativeButton={false}>
								<LogInIcon />
							</Button>
						)}
					</SidebarMenuItem>
				</SidebarGroup>
				)}
				{!signed && !inClient && (
					<SidebarGroup>
						<Button size="sm" variant="outline" render={<Link href="/login" />} nativeButton={false}><LogInIcon /> Entrar</Button>
					</SidebarGroup>
				)}
				{groups.map((group, index) => (
					<NavGroup key={`sidebar-group-${index}`} {...group} base={inClient ? base : ""} all={groups} />
				))}
			</SidebarContent>
			<SidebarFooter>
				<LatestChange />
				<SidebarMenu className="mt-2">
					{footerNavLinks.map((item) => (
						<SidebarMenuItem key={item.title}>
							<SidebarMenuButton className="text-muted-foreground" size="sm" render={<a href={item.path} target={item.path?.startsWith("http") ? "_blank" : undefined} rel="noopener" />}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
						</SidebarMenuItem>
					))}
				</SidebarMenu>
			</SidebarFooter>
		</Sidebar>
	);
}
