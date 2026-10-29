"use client";

import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import { useTheme } from "next-themes";
import { useSession } from "@/components/session-provider";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { AppHeader } from "@/components/app-header";
import { AppSidebar } from "@/components/app-sidebar";
import { TeamCodeDialog } from "@/components/team-code";
import { PresenceBeacon } from "@/components/ops/presence-beacon";

/** Aplica o tema guardado no perfil (FR-14-02) uma vez por sessão; depois manda o que a pessoa escolher. */
function ThemeSync() {
	const { profile } = useSession();
	const { setTheme } = useTheme();
	const done = useRef<string | null>(null);
	useEffect(() => {
		if (profile?.theme && done.current !== profile.id) { done.current = profile.id; setTheme(profile.theme); }
	}, [profile?.id, profile?.theme, setTheme]);
	return null;
}

export function AppShell({ children }: { children: React.ReactNode }) {
	const path = usePathname();
	// Entrar e voltar do email: sem menu lateral (ainda não há workspace).
	if (path.startsWith("/login") || path.startsWith("/auth") || path.startsWith("/convite")) {
		return <><ThemeSync />{children}</>;
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
			<ThemeSync />
			<PresenceBeacon />
		</div>
	);
}
