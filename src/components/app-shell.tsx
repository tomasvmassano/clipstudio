"use client";

import { usePathname } from "next/navigation";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { AppHeader } from "@/components/app-header";
import { AppSidebar } from "@/components/app-sidebar";
import { TeamCodeDialog } from "@/components/team-code";

export function AppShell({ children }: { children: React.ReactNode }) {
	const path = usePathname();
	// Entrar e voltar do email: sem menu lateral (ainda não há workspace).
	if (path.startsWith("/login") || path.startsWith("/auth")) {
		return <main className="flex min-h-svh items-center justify-center p-4">{children}</main>;
	}
	return (
		<div className="overflow-hidden">
			<SidebarProvider className="relative h-svh">
				<AppSidebar />
				<SidebarInset className="md:peer-data-[variant=inset]:ml-0">
					<AppHeader />
					<div className="flex flex-1 flex-col gap-4 overflow-y-auto p-4 md:p-6">
						{children}
					</div>
				</SidebarInset>
			</SidebarProvider>
			<TeamCodeDialog />
		</div>
	);
}
