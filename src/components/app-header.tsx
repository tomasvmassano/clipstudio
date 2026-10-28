"use client";

import { useState } from "react";
import { usePathname } from "next/navigation";
import { useTheme } from "next-themes";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { AppBreadcrumbs } from "@/components/app-breadcrumbs";
import { CustomSidebarTrigger } from "@/components/custom-sidebar-trigger";
import { activeFor } from "@/components/app-shared";
import { NavUser } from "@/components/nav-user";
import { Link2Icon, CheckIcon, SunMoonIcon } from "lucide-react";

export function AppHeader() {
	const pathname = usePathname();
	const activeItem = activeFor(pathname);
	const { setTheme, resolvedTheme } = useTheme();
	const [copied, setCopied] = useState(false);

	const copyLink = async () => {
		try {
			// nunca partilha o código de equipa: só o caminho da página
			await navigator.clipboard.writeText(location.origin + location.pathname);
			setCopied(true);
			setTimeout(() => setCopied(false), 1500);
		} catch {
			setCopied(false);
		}
	};

	return (
		<header
			className={cn(
				"sticky top-0 z-50 flex h-14 shrink-0 items-center justify-between gap-2 border-b bg-background px-4 md:px-6"
			)}
		>
			<div className="flex items-center gap-3">
				<CustomSidebarTrigger />
				<Separator
					className="mr-2 h-4 data-[orientation=vertical]:self-center"
					orientation="vertical"
				/>
				<AppBreadcrumbs page={activeItem} />
			</div>
			<div className="flex items-center gap-3">
				<Button aria-label="Copiar link desta página" title="Copiar link desta página" size="icon-sm" variant="outline" onClick={copyLink}>
					{copied ? <CheckIcon /> : <Link2Icon />}
				</Button>
				<Button aria-label="Mudar tema" title="Mudar tema" size="icon-sm" variant="outline" onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}>
					<SunMoonIcon />
				</Button>
				<Separator
					className="h-4 data-[orientation=vertical]:self-center"
					orientation="vertical"
				/>
				<NavUser />
			</div>
		</header>
	);
}
