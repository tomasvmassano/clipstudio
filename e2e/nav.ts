import type { Page, Request } from "@playwright/test";
import { agencyNavGroups, clientNavGroups, type SidebarNavGroup } from "../src/components/app-shared";

/*
 * O que o menu lateral deve mostrar a uma conta, calculado a partir da configuração real do menu (app-shared.tsx) e das
 * respostas do servidor que a app usa (my_context: capacidades; my_flags: funcionalidades em teste). Uma entrada nova no
 * menu entra automaticamente no teste do menu (QA-01).
 */

type Ctx = {
  workspaces?: { id: string; capabilities: string[] }[];
  agency?: { status: string; capabilities?: string[] }[];
};

export type NavEntry = { title: string; href: string };
export type Expected = { links: NavEntry[]; soon: string[]; flags: string[] };

/** Ouve as respostas de my_context e my_flags. Chamar antes de abrir a página. */
export function watchSession(page: Page) {
  let ctx: Ctx | null = null;
  const flags = new Map<string, string[]>();   // p_ws ("" = agência) -> flags
  page.on("response", async (r) => {
    const url = r.url();
    if (!url.includes("/rest/v1/rpc/")) return;
    try {
      if (url.includes("/rpc/my_context") && r.ok()) ctx = (await r.json()) as Ctx;
      else if (url.includes("/rpc/my_flags") && r.ok()) {
        const ws = (postData(r.request())?.p_ws as string | null) ?? "";
        flags.set(ws, (await r.json()) as string[]);
      }
    } catch { /* resposta já descartada pela navegação */ }
  });
  return {
    ctx: () => ctx,
    flags: (ws: string | null) => flags.get(ws ?? ""),
    /** Espera pelas respostas de que o menu depende. */
    async ready(ws: string | null, needsFlags = true) {
      const t0 = Date.now();
      while (!ctx || (needsFlags && !flags.has(ws ?? ""))) {
        if (Date.now() - t0 > 15_000) throw new Error(`sem resposta de my_context/my_flags (${ws ?? "agência"})`);
        await page.waitForTimeout(100);
      }
    },
  };
}

function postData(r: Request): Record<string, unknown> | null {
  try { return r.postDataJSON() as Record<string, unknown>; } catch { return null; }
}

/** Entradas que o NavGroup mostra para estas capacidades e flags (mesma regra que src/components/nav-group.tsx). */
export function expectedMenu(ctx: Ctx, flags: string[], ws: string | null): Expected {
  const caps = new Set(ws ? ctx.workspaces?.find((w) => w.id === ws)?.capabilities ?? [] : []);
  const orgCaps = new Set((ctx.agency ?? []).filter((a) => a.status === "active").flatMap((a) => a.capabilities ?? []));
  const on = new Set(flags);
  const groups: SidebarNavGroup[] = ws ? clientNavGroups : agencyNavGroups;
  const base = ws ? `/c/${ws}` : "";
  const links: NavEntry[] = [];
  const soon: string[] = [];
  if (ws && orgCaps.has("dashboard.agency")) links.push({ title: "Agência", href: "/" });
  if (ws) links.push({ title: "Gravar agora", href: `${base}/teleprompter` });
  for (const g of groups) {
    for (const i of g.items) {
      if (i.flag && !on.has(i.flag)) continue;
      if (i.unlessFlag && on.has(i.unlessFlag)) continue;
      if (i.orgCap ? !orgCaps.has(i.orgCap) : i.cap && !caps.has(i.cap)) continue;
      if (i.soon || !i.path) soon.push(i.title);
      else links.push({ title: i.title, href: ws ? `${base}${i.path === "/" ? "" : i.path}` : i.path });
    }
  }
  return { links, soon, flags };
}

/** Títulos que só existem no menu da agência (para provar que uma conta de cliente não os vê). */
const clientTitles = new Set(clientNavGroups.flatMap((g) => g.items.map((i) => i.title)));
export const agencyOnlyTitles = agencyNavGroups.flatMap((g) => g.items.filter((i) => i.path && !clientTitles.has(i.title)).map((i) => i.title));

/** Rotas principais do cliente (QA-14: acessibilidade, telemóvel e iPad). */
export const MAIN_ROUTES = [
  { name: "Início", path: "" },
  { name: "Guiões", path: "/guioes" },
  { name: "Revisão", path: "/revisao" },
  { name: "Teleprompter", path: "/teleprompter" },
  { name: "Calendário", path: "/calendario" },
  { name: "Tarefas", path: "/tarefas" },
  { name: "Biblioteca", path: "/biblioteca" },
  { name: "Edição automática", path: "/edicao-automatica" },
  { name: "Agentes", path: "/agentes" },
];
