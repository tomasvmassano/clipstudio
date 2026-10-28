import type { ReactNode } from "react";
import { LayoutDashboardIcon, ScrollTextIcon, MonitorPlayIcon, LightbulbIcon, ChartPieIcon, ClapperboardIcon, BotIcon, UsersIcon, LibraryIcon, CoinsIcon } from "lucide-react";

export type SidebarNavItem = {
	title: string;
	path?: string;
	icon?: ReactNode;
	isActive?: boolean;
	subItems?: SidebarNavItem[];
};

export type SidebarNavGroup = {
	label: string;
	items: SidebarNavItem[];
};

export const navGroups: SidebarNavGroup[] = [
	{
		label: "Dia a dia",
		items: [
			{ title: "Hoje", path: "/", icon: <LayoutDashboardIcon /> },
			{ title: "Guiões", path: "/guioes", icon: <ScrollTextIcon /> },
			{ title: "Teleprompter", path: "/teleprompter", icon: <MonitorPlayIcon /> },
			{ title: "Ideias", path: "/ideias", icon: <LightbulbIcon /> },
			{ title: "Desempenho", path: "/desempenho", icon: <ChartPieIcon /> },
		],
	},
	{
		label: "v1",
		items: [
			{ title: "Revisão", path: "/revisao", icon: <ClapperboardIcon /> },
			{ title: "Agentes", path: "/agentes", icon: <BotIcon /> },
			{ title: "Referências", path: "/referencias", icon: <UsersIcon /> },
			{ title: "Biblioteca", path: "/biblioteca", icon: <LibraryIcon /> },
			{ title: "Custos", path: "/custos", icon: <CoinsIcon /> },
		],
	},
];

export const navLinks: SidebarNavItem[] = [
	...navGroups.flatMap((group) =>
		group.items.flatMap((item) =>
			item.subItems?.length ? [item, ...item.subItems] : [item]
		)
	),
];
