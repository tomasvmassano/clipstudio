import type { ReactNode } from "react";
import {
	Building2Icon, GaugeIcon, KeyRoundIcon, ScrollIcon, SettingsIcon, SlidersHorizontalIcon,
	LayoutGridIcon, ScrollTextIcon, MonitorPlayIcon, LightbulbIcon, BarChart3Icon, BotIcon,
	ClapperboardIcon, FilmIcon, LibraryIcon, ShieldCheckIcon, UsersIcon, UsersRoundIcon, WalletIcon, FileTextIcon, HistoryIcon, InboxIcon, ListTodoIcon, CalendarDaysIcon,
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

/** Menu do espaço da agência (tudo o que não está dentro de um cliente). */
export const agencyNavGroups: SidebarNavGroup[] = [
	{
		items: [
			{ title: "Painel", path: "/", icon: <GaugeIcon />, orgCap: "dashboard.agency" },
			{ title: "Clientes", path: "/clientes", icon: <Building2Icon />, orgCap: "workspaces.read" },
			{ title: "Caixa de entrada", path: "/caixa", icon: <InboxIcon />, orgCap: "dashboard.agency" },
			{ title: "Equipa da agência", path: "/equipa-agencia", icon: <UsersRoundIcon />, orgCap: "team.read" },
		],
	},
	{
		label: "Em breve",
		items: [
			{ title: "Calendário de todos", icon: <CalendarDaysIcon />, soon: true },
			{ title: "Custos", icon: <WalletIcon />, soon: true },
			{ title: "Histórico da agência", icon: <ScrollIcon />, soon: true },
			{ title: "Definições da agência", icon: <SettingsIcon />, soon: true },
		],
	},
];

/** Menu do espaço de um cliente. Os caminhos são relativos ao cliente: "/guioes" abre /c/<cliente>/guioes. */
export const clientNavGroups: SidebarNavGroup[] = [
	{
		items: [
			{ title: "Início", path: "/", icon: <LayoutGridIcon /> },
			{ title: "Caixa de entrada", path: "/caixa", icon: <InboxIcon />, cap: "tasks.work" },
		],
	},
	{
		label: "Dia a dia",
		items: [
			{ title: "Guiões", path: "/guioes", icon: <ScrollTextIcon />, cap: "scripts.read" },
			{ title: "Revisão", path: "/revisao", icon: <ClapperboardIcon />, cap: "scripts.read" },
			{ title: "Tarefas", path: "/tarefas", icon: <ListTodoIcon />, cap: "tasks.read" },
			{ title: "Calendário", path: "/calendario", icon: <CalendarDaysIcon />, cap: "calendar.read" },
			{ title: "Teleprompter", path: "/teleprompter", icon: <MonitorPlayIcon />, cap: "recording.use" },
			{ title: "Estilos de edição", path: "/edicao", icon: <FilmIcon />, cap: "scripts.read" },
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
		label: "Administração do cliente",
		items: [
			{ title: "Equipa", path: "/equipa", icon: <ShieldCheckIcon />, cap: "team.read" },
			{ title: "Permissões", path: "/permissoes", icon: <KeyRoundIcon />, cap: "team.read" },
			{ title: "Histórico", path: "/historico", icon: <ScrollIcon />, cap: "audit.read" },
			{ title: "Definições", path: "/definicoes", icon: <SettingsIcon />, cap: "team.read" },
		],
	},
	{
		label: "Em breve",
		items: [
			{ title: "Biblioteca", icon: <LibraryIcon />, soon: true },
			{ title: "Custos", icon: <WalletIcon />, soon: true },
		],
	},
];

export const footerNavLinks: SidebarNavItem[] = [
	{ title: "PRD v2.1", path: "https://claude.ai/artifact/CboQfT6zRXsRbxDxW7QsMg", icon: <FileTextIcon />, external: true },
	{ title: "Versão antiga", path: "/legacy/index.html", icon: <HistoryIcon />, external: true },
];

const flat = (groups: SidebarNavGroup[]) => groups.flatMap((g) => g.items.flatMap((i) => (i.subItems?.length ? [i, ...i.subItems] : [i])));

/** Item ativo para um caminho já sem o prefixo do cliente (o mais específico ganha). */
export function activeFor(pathname: string, groups: SidebarNavGroup[]): SidebarNavItem | undefined {
	return flat(groups)
		.filter((i) => i.path && !i.external && (i.path === "/" ? pathname === "/" : pathname.startsWith(i.path)))
		.sort((a, b) => (b.path?.length ?? 0) - (a.path?.length ?? 0))[0];
}
