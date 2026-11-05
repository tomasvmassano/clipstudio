import AxeBuilder from "@axe-core/playwright";
import { test, type Page } from "@playwright/test";
import { WS_A } from "./env";
import { as, expect, expectNoCrash, settle, sidebar } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";
import { MAIN_ROUTES } from "./nav";

/*
 * QA-14 (WCAG 2.2 AA, AGENTS §9): axe nas rotas principais com conta de agência e conta de cliente; falha com violações
 * "serious" ou "critical". Teclado: percorrer o menu lateral com Tab e abrir/fechar a folha de revisão com Enter/Escape.
 */

test.beforeAll(() => flagsOnForA(["edit.studio", "media.library"]));
test.afterAll(() => restoreFlags());

async function seriousViolations(page: Page) {
  const r = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    // a pré-visualização do Next (dev overlay) e os avisos do browser não fazem parte da app
    .exclude("nextjs-portal")
    .analyze();
  return r.violations
    .filter((v) => v.impact === "serious" || v.impact === "critical")
    .map((v) => `${v.impact} ${v.id}: ${v.help}\n    ${v.nodes.slice(0, 5).map((n) => `${n.target.join(" ")}  ${n.html.slice(0, 160)}${v.id === "color-contrast" ? `  (${n.any[0]?.message ?? ""})` : ""}`).join("\n    ")}${v.nodes.length > 5 ? `\n    … +${v.nodes.length - 5}` : ""}`);
}

for (const role of ["owner", "clientA"] as const) {
  as(role)(`${role}: rotas principais sem violações graves de acessibilidade (axe)`, async ({ page, errors }) => {
    test.setTimeout(180_000);
    const found: string[] = [];
    for (const r of MAIN_ROUTES) {
      await page.goto(`/c/${WS_A}${r.path}`);
      await settle(page);
      await expect(page.getByRole("heading", { level: 1 }).first(), r.name).toBeVisible();
      await expectNoCrash(page);
      for (const v of await seriousViolations(page)) found.push(`[${r.name}] ${v}`);
    }
    expect(found, found.join("\n")).toEqual([]);
    expect(errors).toEqual([]);
  });
}

as("owner")("owner: painel da agência sem violações graves (axe)", async ({ page, errors }) => {
  await page.goto("/");
  await settle(page);
  await expect(page.getByRole("heading", { level: 1 }).first()).toBeVisible();
  const found = await seriousViolations(page);
  expect(found, found.join("\n")).toEqual([]);
  expect(errors).toEqual([]);
});

/** Carrega Tab até o foco cumprir a condição; devolve o que foi focado pelo caminho. */
async function tabUntil(page: Page, done: () => Promise<boolean>, max = 80) {
  for (let i = 0; i < max; i++) {
    await page.keyboard.press("Tab");
    if (await done()) return;
  }
  throw new Error("o foco nunca chegou ao destino com Tab");
}
const focusedHref = (page: Page) => page.evaluate(() => (document.activeElement as HTMLElement | null)?.closest("a")?.getAttribute("href") ?? null);

as("clientA")("teclado: Tab percorre todas as entradas do menu, com foco visível, e Enter abre a rota", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/tarefas`);
  await settle(page);
  const links = sidebar(page).locator('[data-sidebar="content"] a[data-sidebar="menu-button"]');
  await expect(links.first()).toBeVisible();
  const want = [...new Set(await links.evaluateAll((l) => l.map((a) => a.getAttribute("href")!)))];
  const reached: string[] = [];
  await page.locator("body").click({ position: { x: 1, y: 1 } }).catch(() => {});
  await page.evaluate(() => (document.activeElement as HTMLElement | null)?.blur());
  await tabUntil(page, async () => {
    const inMenu = await page.evaluate(() => !!document.activeElement?.closest('[data-sidebar="content"] a[data-sidebar="menu-button"]'));
    if (inMenu) {
      const h = await focusedHref(page);
      // foco visível: o anel de foco tem de existir quando se navega por teclado
      expect(await page.evaluate(() => document.activeElement!.matches(":focus-visible"))).toBe(true);
      if (h && !reached.includes(h)) reached.push(h);
    }
    return reached.length === want.length;
  }, 120);
  expect(reached).toEqual(want);   // ordem do teclado = ordem visual do menu
  // Shift+Tab volta para trás e Enter num link abre a rota
  for (let i = 0; i < 40 && (await focusedHref(page)) !== `/c/${WS_A}/guioes`; i++) await page.keyboard.press("Shift+Tab");
  expect(await focusedHref(page)).toBe(`/c/${WS_A}/guioes`);
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(new RegExp(`/c/${WS_A}/guioes$`));
  await expect(page.getByRole("heading", { level: 1, name: "Guiões" })).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("teclado: a folha de revisão abre com Enter, prende o foco e fecha com Escape", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/revisao`);
  await settle(page);
  const trigger = page.getByRole("button", { name: /^Comentários/ }).first();
  await expect(trigger).toBeVisible();
  await trigger.focus();
  await page.keyboard.press("Enter");
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: /Revisão do guião/ })).toBeVisible();
  const inSheet = () => page.evaluate(() => !!document.activeElement?.closest('[role="dialog"]'));
  await expect.poll(inSheet).toBe(true);
  await expect(sheet.locator('[data-slot="sheet-close"]').first()).toBeFocused();   // foco inicial no fecho, já com a folha aberta
  await expect(sheet.getByRole("button", { name: /^Comentar / }).first()).toBeVisible();   // conteúdo carregado antes de percorrer
  for (let i = 0; i < 25; i++) {
    await page.keyboard.press("Tab");
    await expect.poll(inSheet, { message: `Tab ${i + 1} saiu da folha`, timeout: 2_000 }).toBe(true);
  }
  await page.keyboard.press("Escape");
  await expect(sheet).toHaveCount(0);
  await expect(trigger).toBeFocused();   // o foco volta a quem abriu a folha
  expect(errors).toEqual([]);
});

as("owner")("teclado: um diálogo abre pelo teclado e fecha com Escape", async ({ page, errors }) => {
  await page.goto("/clientes");
  await settle(page);
  const open = page.getByRole("button", { name: /Novo cliente|Adicionar cliente|Criar cliente/ }).first();
  await expect(open).toBeVisible();
  await open.focus();
  await page.keyboard.press("Enter");
  const dlg = page.getByRole("dialog");
  await expect(dlg).toBeVisible();
  await expect.poll(() => page.evaluate(() => !!document.activeElement?.closest('[role="dialog"]'))).toBe(true);
  await page.keyboard.press("Escape");
  await expect(dlg).toHaveCount(0);
  await expect(open).toBeFocused();
  expect(errors).toEqual([]);
});
