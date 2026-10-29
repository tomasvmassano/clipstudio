import type { ReactNode } from "react";
import {
	Building2Icon, GaugeIcon, KeyRoundIcon, ScrollIcon, SettingsIcon, SlidersHorizontalIcon,
	LayoutGridIcon, ScrollTextIcon, MonitorPlayIcon, LightbulbIcon, BarChart3Icon, BotIcon,
	ClapperboardIcon, LibraryIcon, ShieldCheckIcon, UsersIcon, WalletIcon, FileTextIcon, HistoryIcon, InboxIcon, ListTodoIcon, CalendarDaysIcon,
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
	/** Capacidade de âmbito agência (não depende do cliente aberto). */
	orgCap?: string;
	subItems?: SidebarNavItem[];
};

export type SidebarNavGroup = {
	label?: string;
	items: SidebarNavItem[];
};

export const navGroups: SidebarNavGroup[] = [
	{
		items: [
			{ title: "Início", path: "/", icon: <LayoutGridIcon /> },
			{ title: "Agência", path: "/agencia", icon: <GaugeIcon />, orgCap: "dashboard.agency" },
			{ title: "Caixa de entrada", path: "/caixa", icon: <InboxIcon />, cap: "tasks.work" },
		],
	},
	{
		label: "Dia a dia",
		items: [
			{ title: "Guiões", path: "/guioes", icon: <ScrollTextIcon />, cap: "scripts.read" },
			{ title: "Tarefas", path: "/tarefas", icon: <ListTodoIcon />, cap: "tasks.read" },
			{ title: "Calendário", path: "/calendario", icon: <CalendarDaysIcon />, cap: "calendar.read" },
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
			{ title: "Agentes e execuções", path: "/agentes/configuracao", icon: <SlidersHorizontalIcon />, cap: "agents.read" },
		],
	},
	{
		label: "Administração",
		items: [
			{ title: "Clientes", path: "/clientes", icon: <Building2Icon />, orgCap: "workspaces.read" },
			{ title: "Equipa", path: "/equipa", icon: <ShieldCheckIcon />, cap: "team.read" },
			{ title: "Permissões", path: "/permissoes", icon: <KeyRoundIcon />, cap: "team.read" },
			{ title: "Histórico", path: "/historico", icon: <ScrollIcon />, cap: "audit.read" },
			{ title: "Definições", path: "/definicoes", icon: <SettingsIcon />, cap: "team.read" },
		],
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
