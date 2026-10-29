import type { ReactNode } from "react";
import {
	LayoutGridIcon, ScrollTextIcon, MonitorPlayIcon, LightbulbIcon, BarChart3Icon, BotIcon,
	ClapperboardIcon, LibraryIcon, ShieldCheckIcon, UsersIcon, WalletIcon, FileTextIcon, HistoryIcon, InboxIcon, ListTodoIcon,
} from "lucide-react";

export type SidebarNavItem = {
	title: string;
	path?: string;
	icon?: ReactNode;
	isActive?: boolean;
	/** Módulo do PRD ainda sem implementação: aparece desativado, sem link (AGENTS.md §4). */
	soon?: boolean;
	external?: boolean;
	/** Capacidade necessária para ver o item (registo de capacidades, AGENTS §15). O servidor volta a verificar. */
	cap?: string;
	subItems?: SidebarNavItem[];
};

export type SidebarNavGroup = {
	label?: string;
	items: SidebarNavItem[];
};

export const navGroups: SidebarNavGroup[] = [
	{
		items: [
			{ title: "Hoje", path: "/", icon: <LayoutGridIcon />, cap: "analytics.read" },
			{ title: "Caixa de entrada", path: "/caixa", icon: <InboxIcon />, cap: "tasks.work" },
		],
	},
	{
		label: "Dia a dia",
		items: [
			{ title: "Guiões", path: "/guioes", icon: <ScrollTextIcon />, cap: "scripts.read" },
			{ title: "Tarefas", path: "/tarefas", icon: <ListTodoIcon />, cap: "tasks.read" },
			{ title: "Teleprompter", path: "/teleprompter", icon: <MonitorPlayIcon />, cap: "recording.use" },
			{ title: "Fontes", path: "/fontes", icon: <LightbulbIcon />, cap: "sources.read" },
			{ title: "Referências", path: "/referencias", icon: <UsersIcon />, cap: "references.read" },
		],
	},
	{
		label: "Análise",
		items: [
			{ title: "Desempenho", path: "/desempenho", icon: <BarChart3Icon />, cap: "analytics.read" },
			{ title: "Sala dos agentes", path: "/agentes", icon: <BotIcon />, cap: "agents.read" },
		],
	},
	{
		label: "Administração",
		items: [{ title: "Equipa", path: "/equipa", icon: <ShieldCheckIcon />, cap: "team.read" }],
	},
	{
		label: "Em breve",
		items: [
			{ title: "Revisão", icon: <ClapperboardIcon />, soon: true },
			{ title: "Biblioteca", icon: <LibraryIcon />, soon: true },
			{ title: "Custos", icon: <WalletIcon />, soon: true },
		],
	},
];

export const footerNavLinks: SidebarNavItem[] = [
	{ title: "PRD v2.1", path: "https://claude.ai/artifact/CboQfT6zRXsRbxDxW7QsMg", icon: <FileTextIcon />, external: true },
	{ title: "Versão antiga", path: "/legacy/index.html", icon: <HistoryIcon />, external: true },
];

export const navLinks: SidebarNavItem[] = [
	...navGroups.flatMap((group) =>
		group.items.flatMap((item) =>
			item.subItems?.length ? [item, ...item.subItems] : [item]
		)
	),
	...footerNavLinks,
];

/** Item ativo para um pathname (o mais específico ganha). */
export function activeFor(pathname: string): SidebarNavItem | undefined {
	return navLinks
		.filter((i) => i.path && !i.external && (i.path === "/" ? pathname === "/" : pathname.startsWith(i.path)))
		.sort((a, b) => (b.path?.length ?? 0) - (a.path?.length ?? 0))[0];
}
