import type { ReactNode } from "react";
import {
	Building2Icon, GaugeIcon, KeyRoundIcon, ScrollIcon, SettingsIcon, SlidersHorizontalIcon,
	LayoutGridIcon, ScrollTextIcon, MonitorPlayIcon, LightbulbIcon, BarChart3Icon, BotIcon,
	BriefcaseBusinessIcon, ClapperboardIcon, FlaskRoundIcon, RotateCcwIcon, FilmIcon, ReceiptIcon, FlaskConicalIcon, LibraryIcon, ShieldCheckIcon, UsersIcon, UsersRoundIcon, WalletIcon, FileTextIcon, DoorOpenIcon, HistoryIcon, PlugIcon, InboxIcon, ListTodoIcon, CalendarDaysIcon,
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
	/** Funcionalidade em teste (MIG-09): só aparece com a flag ligada para esta pessoa. */
	flag?: string;
	/** Some quando esta flag está ligada (ex.: o "Em breve" de um módulo que já está em teste para esta pessoa). */
	unlessFlag?: string;
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
			{ title: "Negócio", path: "/negocio", icon: <BriefcaseBusinessIcon />, orgCap: "biz.read", flag: "biz.view" },
			{ title: "Contratos e custos", path: "/negocio/contratos", icon: <ReceiptIcon />, orgCap: "biz.finance", flag: "biz.view" },
			{ title: "Caixa de entrada", path: "/caixa", icon: <InboxIcon />, orgCap: "dashboard.agency" },
			{ title: "Equipa da agência", path: "/equipa-agencia", icon: <UsersRoundIcon />, orgCap: "team.read" },
			{ title: "Integrações", path: "/integracoes", icon: <PlugIcon />, orgCap: "integrations.agency.read" },
			{ title: "Funcionalidades em teste", path: "/funcionalidades", icon: <FlaskConicalIcon />, orgCap: "flags.manage" },
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
			{ title: "Portal", path: "/portal", icon: <DoorOpenIcon />, cap: "scripts.read", flag: "client.portal" },
		],
	},
	{
		label: "Dia a dia",
		items: [
			{ title: "Guiões", path: "/guioes", icon: <ScrollTextIcon />, cap: "scripts.read" },
			{ title: "Revisão", path: "/revisao", icon: <ClapperboardIcon />, cap: "scripts.read" },
			{ title: "Tarefas", path: "/tarefas", icon: <ListTodoIcon />, cap: "tasks.read" },
			{ title: "Quem trabalha em quê", path: "/quem-trabalha", icon: <UsersRoundIcon />, cap: "ops.presence", flag: "ops.team_presence" },
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
			{ title: "Centro de desempenho", path: "/desempenho/centro", icon: <GaugeIcon />, cap: "analytics.read", flag: "perf.center" },
			{ title: "Sala dos agentes", path: "/agentes", icon: <BotIcon />, cap: "agents.read" },
			{ title: "Agentes e execuções", path: "/agentes/configuracao", icon: <SlidersHorizontalIcon />, cap: "agents.read" },
			{ title: "Retrabalho", path: "/aprendizagem/retrabalho", icon: <RotateCcwIcon />, cap: "learn.read", flag: "learn.rework" },
			{ title: "Experiências e vencedores", path: "/aprendizagem/experiencias", icon: <FlaskRoundIcon />, cap: "learn.read", flag: "learn.experiments" },
			{ title: "Custos", path: "/custos", icon: <WalletIcon />, cap: "costs.read", flag: "costs.content" },
		],
	},
	{
		label: "Administração do cliente",
		items: [
			{ title: "Equipa", path: "/equipa", icon: <ShieldCheckIcon />, cap: "team.read" },
			{ title: "Permissões", path: "/permissoes", icon: <KeyRoundIcon />, cap: "team.read" },
			{ title: "Histórico", path: "/historico", icon: <ScrollIcon />, cap: "audit.read" },
			{ title: "Definições", path: "/definicoes", icon: <SettingsIcon />, cap: "team.read" },
			{ title: "Integrações", path: "/definicoes/integracoes", icon: <PlugIcon />, cap: "integrations.read", flag: "integrations.center" },
		],
	},
	{
		label: "Em breve",
		items: [
			{ title: "Biblioteca", icon: <LibraryIcon />, soon: true },
			{ title: "Custos", icon: <WalletIcon />, soon: true, unlessFlag: "costs.content" },
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
