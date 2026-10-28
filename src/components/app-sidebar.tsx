"use client";

import Link from "next/link";
import { LogoIcon } from "@/components/logo";
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
import { MonitorPlayIcon, KeyRoundIcon, CheckIcon } from "lucide-react";

export function AppSidebar() {
	const { session, setDialogOpen } = useSession();
	return (
		<Sidebar collapsible="icon" variant="inset">
			<SidebarHeader className="h-14 justify-center">
				<SidebarMenuButton render={<Link href="/" />}><LogoIcon /><span className="font-medium">Estúdio Numeiro</span></SidebarMenuButton>
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
						<Button
							aria-label={session ? `Ligado: ${session.label ?? session.role}` : "Entrar com código de equipa"}
							title={session ? `Ligado: ${session.label ?? session.role}` : "Entrar com código de equipa"}
							className="size-8 group-data-[collapsible=icon]:opacity-0"
							size="icon"
							variant="outline"
							onClick={() => { if (!session) setDialogOpen(true); }}
						>
							{session ? <CheckIcon className="text-emerald-500" /> : <KeyRoundIcon />}
						</Button>
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
