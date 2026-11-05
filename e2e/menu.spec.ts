import { test } from "@playwright/test";
import { WS_A } from "./env";
import { NO_ACCESS, as, expect, expectNoCrash, settle, sidebar } from "./helpers";
import { agencyOnlyTitles, expectedMenu, watchSession, type NavEntry } from "./nav";
import { flagsOnForA, restoreFlags } from "./flags";

/*
 * QA-01: abrir cada rota pelo menu lateral (e depois refresh), com conta de agência e conta de cliente (QA-16, R-15).
 * O menu esperado sai da configuração real do menu e das respostas do servidor (capacidades e flags): uma entrada que a
 * conta não pode ver não pode aparecer, e cada entrada visível tem de abrir uma página com título, sem página de erro
 * genérica, sem "sem acesso" e sem erros na consola.
 */

// Liga dois módulos em teste no cliente A (para os clicar também com a conta do cliente); os restantes ficam como estão.
test.beforeAll(() => flagsOnForA(["edit.studio", "media.library"]));
test.afterAll(() => restoreFlags());

const content = (p: import("@playwright/test").Page) => sidebar(p).locator('[data-sidebar="content"]');

async function menuLinks(p: import("@playwright/test").Page): Promise<NavEntry[]> {
  return content(p).locator('a[data-sidebar="menu-button"]').evaluateAll((els) =>
    els.map((a) => ({ title: (a.textContent ?? "").trim(), href: a.getAttribute("href") ?? "" })));
}

async function openAndRefresh(p: import("@playwright/test").Page, e: NavEntry, errors: string[]) {
  const step = `${e.title} (${e.href})`;
  await content(p).locator(`a[data-sidebar="menu-button"][href="${e.href}"]`).first().click();
  await expect(p, step).toHaveURL((u) => u.pathname === e.href);
  for (const phase of ["menu", "refresh"]) {
    if (phase === "refresh") await p.reload();
    await settle(p);
    await expect(p.getByRole("heading", { level: 1 }).first(), `${step} · ${phase}: título`).toBeVisible();
    await expectNoCrash(p);
    await expect(p.getByText(NO_ACCESS), `${step} · ${phase}`).toHaveCount(0);
    expect(errors, `${step} · ${phase}`).toEqual([]);
  }
}

for (const role of ["owner", "clientA"] as const) {
  as(role)(`${role}: cada entrada do menu do cliente abre pelo menu e com refresh`, async ({ page, errors }) => {
    test.setTimeout(240_000);
    const s = watchSession(page);
    await page.goto(`/c/${WS_A}/guioes`);
    await s.ready(WS_A);
    const exp = expectedMenu(s.ctx()!, s.flags(WS_A)!, WS_A);
    await expect.poll(() => menuLinks(page), { message: "entradas do menu = capacidades + flags do servidor" }).toEqual(exp.links);

    // módulos por fazer: visíveis só como desativados, nunca como link nem href="#"
    const soon = content(page).locator('[data-sidebar="menu-button"][aria-disabled="true"]');
    await expect(soon).toHaveCount(exp.soon.length);
    await expect(content(page).locator('a[href="#"], a[href=""]')).toHaveCount(0);
    for (const a of await sidebar(page).locator('[data-sidebar="footer"] a').all()) expect(await a.getAttribute("href")).toMatch(/^(\/|https:\/\/)/);

    // as flags ligadas acima aparecem; uma flag por defeito "só o dono" não aparece ao cliente
    const titles = exp.links.map((l) => l.title);
    expect(titles).toEqual(expect.arrayContaining(["Início", "Guiões", "Revisão", "Tarefas", "Calendário", "Teleprompter", "Biblioteca", "Edição automática", "Sala dos agentes"]));
    if (role === "clientA") {
      expect(exp.flags).not.toContain("perf.center");
      expect(titles).not.toContain("Centro de desempenho");
      // nada da agência: nem o "Voltar à agência", nem links fora deste cliente
      expect(titles).not.toContain("Agência");
      expect(exp.links.every((l) => l.href.startsWith(`/c/${WS_A}`))).toBe(true);
      for (const t of agencyOnlyTitles) await expect(content(page).getByText(t, { exact: true })).toHaveCount(0);
    } else {
      expect(titles).toContain("Agência");
    }

    const seen = new Set<string>();
    for (const e of exp.links) {
      if (e.href === "/" || seen.has(e.href)) continue;   // "Agência" é coberto pelo teste do menu da agência
      seen.add(e.href);
      await openAndRefresh(page, e, errors);
      // o teleprompter ocupa o ecrã todo (sem menu): volta atrás como quem sai dele
      if (e.href.endsWith("/teleprompter")) { await page.goBack(); await settle(page); }
    }
  });
}

as("owner")("owner: cada entrada do menu da agência abre pelo menu e com refresh", async ({ page, errors }) => {
  test.setTimeout(120_000);
  const s = watchSession(page);
  await page.goto("/clientes");
  await s.ready(null);
  const exp = expectedMenu(s.ctx()!, s.flags(null)!, null);
  await expect.poll(() => menuLinks(page)).toEqual(exp.links);
  await expect(content(page).locator('[data-sidebar="menu-button"][aria-disabled="true"]')).toHaveCount(exp.soon.length);
  expect(exp.links.map((l) => l.title)).toEqual(expect.arrayContaining(["Painel", "Clientes", "Caixa de entrada", "Equipa da agência", "Funcionalidades em teste"]));
  for (const e of exp.links) await openAndRefresh(page, e, errors);
});

as("clientA")("clientA: o painel da agência leva ao seu cliente, sem menu da agência", async ({ page, errors }) => {
  await page.goto("/");
  await expect(page).toHaveURL((u) => u.pathname === `/c/${WS_A}`);
  await settle(page);
  await expectNoCrash(page);
  await expect(content(page).locator('a[data-sidebar="menu-button"]').first()).toBeVisible();
  for (const href of await content(page).locator('a[data-sidebar="menu-button"]').evaluateAll((l) => l.map((a) => a.getAttribute("href"))))
    expect(href).toMatch(new RegExp(`^/c/${WS_A}(/|$)`));
  for (const t of agencyOnlyTitles) await expect(content(page).getByText(t, { exact: true })).toHaveCount(0);
  expect(errors).toEqual([]);
});
