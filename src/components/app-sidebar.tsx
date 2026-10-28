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
import { footerNavLinks, navGroups } from "@/components/app-shared";
import { LatestChange } from "@/components/latest-change";
import { useSession } from "@/components/session-provider";
import { MonitorPlayIcon, LogInIcon, CheckIcon } from "lucide-react";
import { WorkspaceSwitcher } from "@/components/workspace-switcher";

export function AppSidebar() {
	const { mode, label } = useSession();
	const signed = mode === "user" || mode === "code";
	return (
		<Sidebar collapsible="icon" variant="inset">
			<SidebarHeader className="h-14 justify-center">
				<WorkspaceSwitcher />
			</SidebarHeader>
			<SidebarContent>
				<SidebarGroup>
					<SidebarMenuItem className="flex items-center gap-2">
						<SidebarMenuButton
							className="min-w-8 bg-primary text-primary-foreground duration-200 ease-linear hover:bg-primary/90 hover:text-primary-foreground active:bg-primary/90 active:text-primary-foreground"
							tooltip="Abrir teleprompter"
							render={<Link href="/teleprompter" />}
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
				{navGroups.map((group, index) => (
					<NavGroup key={`sidebar-group-${index}`} {...group} />
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
