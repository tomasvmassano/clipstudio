"use client";

import Link from "next/link";
import { Building2Icon, CheckIcon, ChevronsUpDownIcon, GaugeIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { LogoIcon } from "@/components/logo";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuGroup,
	DropdownMenuItem,
	DropdownMenuLabel,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useSession } from "@/components/session-provider";
import { ROLE_LABEL, type WorkspaceCtx } from "@/lib/access";
import { useLogoUrl } from "@/lib/branding";
import { clientPath } from "@/lib/ws-path";

/**
 * Troca de workspace (PRD: o staff da agência alterna entre clientes autorizados; o staff do cliente fica no seu).
 * A lista vem de my_context(), que só devolve workspaces onde o utilizador tem acesso ativo.
 */
/** Logótipo do cliente (se houver) ou o ícone da app; a cor da marca fica como fundo. */
function WsMark({ ws }: { ws: WorkspaceCtx | null }) {
	const url = useLogoUrl(ws?.logo_path);
	if (url) {
		// eslint-disable-next-line @next/next/no-img-element
		return <img src={url} alt="" className="size-5 rounded-sm object-contain" style={{ backgroundColor: ws?.brand_color ?? undefined }} />;
	}
	if (ws?.brand_color) return <span aria-hidden className="size-4 rounded-sm" style={{ backgroundColor: ws.brand_color }} />;
	return <LogoIcon />;
}

/** Lista de clientes para abrir (o mesmo menu nos dois espaços). */
function ClientItems({ current }: { current: string | null }) {
	const { workspaces, setWorkspace } = useSession();
	return (
		<DropdownMenuGroup>
			<DropdownMenuLabel className="text-xs text-muted-foreground">Clientes a que tens acesso</DropdownMenuLabel>
			{workspaces.length === 0 && <DropdownMenuItem disabled>Ainda não tens clientes</DropdownMenuItem>}
			{workspaces.map((w) => (
				<DropdownMenuItem key={w.id} onClick={() => setWorkspace(w.id)}>
					<WsMark ws={w} />
					<div className="min-w-0 flex-1">
						<div className="truncate">{w.name}</div>
						<div className="truncate text-xs text-muted-foreground">{ROLE_LABEL[w.role] ?? w.role}</div>
					</div>
					{w.id === current && <CheckIcon className="size-4" />}
				</DropdownMenuItem>
			))}
		</DropdownMenuGroup>
	);
}

/** Topo do espaço da agência: nome da agência e atalho para entrar num cliente. */
export function AgencySwitcher() {
	const { agencyName, canOrg } = useSession();
	const router = useRouter();
	return (
		<DropdownMenu>
			<DropdownMenuTrigger render={<SidebarMenuButton aria-label="Abrir um cliente" />}>
				<LogoIcon />
				<span className="flex min-w-0 flex-col leading-tight">
					<span className="truncate font-medium">{agencyName ?? "ClipStudio"}</span>
					<span className="truncate text-[11px] text-muted-foreground">Agência</span>
				</span>
				<ChevronsUpDownIcon className="ml-auto size-4 opacity-60" />
			</DropdownMenuTrigger>
			<DropdownMenuContent align="start" className="w-64">
				<ClientItems current={null} />
				{canOrg("workspaces.read") && (
					<>
						<DropdownMenuSeparator />
						<DropdownMenuItem onClick={() => router.push("/clientes")}><Building2Icon className="size-4" /> Gerir clientes</DropdownMenuItem>
					</>
				)}
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

/** Topo do espaço de um cliente: o cliente aberto; a agência pode saltar para outro ou voltar ao painel. */
export function WorkspaceSwitcher() {
	const { ws, workspaces, canOrg } = useSession();
	const router = useRouter();
	const title = ws?.name ?? "Cliente";
	const agency = canOrg("dashboard.agency");

	if (workspaces.length <= 1 && !agency) {
		return (
			<SidebarMenuButton render={<Link href={ws ? clientPath(ws.id) : "/"} />}>
				<WsMark ws={ws} />
				<span className="truncate font-medium">{title}</span>
			</SidebarMenuButton>
		);
	}

	return (
		<DropdownMenu>
			<DropdownMenuTrigger render={<SidebarMenuButton aria-label="Trocar de cliente" />}>
				<WsMark ws={ws} />
				<span className="truncate font-medium">{title}</span>
				<ChevronsUpDownIcon className="ml-auto size-4 opacity-60" />
			</DropdownMenuTrigger>
			<DropdownMenuContent align="start" className="w-64">
				<ClientItems current={ws?.id ?? null} />
				{agency && (
					<>
						<DropdownMenuSeparator />
						<DropdownMenuItem onClick={() => router.push("/")}><GaugeIcon className="size-4" /> Painel da agência</DropdownMenuItem>
					</>
				)}
			</DropdownMenuContent>
		</DropdownMenu>
	);
}
