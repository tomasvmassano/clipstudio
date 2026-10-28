"use client";

import { cn } from "@/lib/utils";
import { LogoIcon } from "@/components/logo";
import { Button } from "@/components/ui/button";
import {
	Sidebar,
	SidebarContent,
	SidebarFooter,
	SidebarGroup,
	SidebarGroupLabel,
	SidebarHeader,
	SidebarMenu,
	SidebarMenuButton,
	SidebarMenuItem,
	SidebarRail,
} from "@/components/ui/sidebar";
import { AppSearch } from "@/components/app-search";
import { navGroups } from "@/components/app-shared";
import { CustomTrigger } from "@/components/custom-trigger";
import { ThemeSwitcher } from "@/components/theme-switcher";
import { SettingsIcon } from "lucide-react";
import { usePathname } from "next/navigation";

export function AppSidebar() {
	const pathname = usePathname();
	return (
		<Sidebar
			className={cn(
				"*:data-[slot=sidebar-inner]:bg-background",
				"transition-[left,right,top,width] group-data-[collapsible=offcanvas]:top-[calc(var(--app-header-height)*0.5)]"
			)}
			collapsible="offcanvas"
			variant="sidebar"
		>
			<SidebarHeader className="h-(--app-header-height,3rem) flex-row items-center justify-between">
				<Button variant="ghost" render={<a href="#link" />} nativeButton={false}><LogoIcon /><span className="font-medium">Estúdio Numeiro</span></Button>
				<CustomTrigger place="sidebar" />
			</SidebarHeader>
			<SidebarContent>
				<SidebarGroup>
					<AppSearch />
				</SidebarGroup>
				{navGroups.map((group) => (
					<SidebarGroup key={group.label}>
						<SidebarGroupLabel className="group-data-[collapsible=icon]:pointer-events-none">
							{group.label}
						</SidebarGroupLabel>
						<SidebarMenu>
							{group.items.map((item) => (
								<SidebarMenuItem key={item.title}>
									<SidebarMenuButton isActive={item.path === pathname} tooltip={item.title} render={<a href={item.path} />}>{item.icon}<span>{item.title}</span></SidebarMenuButton>
								</SidebarMenuItem>
							))}
						</SidebarMenu>
					</SidebarGroup>
				))}
			</SidebarContent>
			<SidebarFooter className="px-4">
				<div className="flex items-center pt-4 pb-2">
					<ThemeSwitcher />
					<Button className="text-muted-foreground" size="icon-sm" variant="ghost" render={<a aria-label="Settings" href="#" />} nativeButton={false}><SettingsIcon
                    							/></Button>
				</div>
			</SidebarFooter>
			<SidebarRail />
		</Sidebar>
	);
}
