import { test, type Page } from "@playwright/test";
import { WS_A } from "./env";
import { as, expect, expectNoCrash, settle } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";
import { MAIN_ROUTES } from "./nav";

/*
 * QA-14: telemóvel e iPad nas rotas principais, com conta de agência e de cliente. Sem scroll horizontal (nem na página
 * nem na área de conteúdo), título visível, zero erros na consola; no telemóvel o menu lateral recolhe para uma folha que
 * abre pelo botão e fecha com Escape; no iPad o menu recolhe para ícones.
 */

test.beforeAll(() => flagsOnForA(["edit.studio", "media.library"]));
test.afterAll(() => restoreFlags());

const VIEWPORTS = [
  { name: "telemóvel", viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true },
  { name: "iPad", viewport: { width: 820, height: 1180 }, isMobile: true, hasTouch: true },
] as const;

/** Elementos mais largos do que o seu contentor com scroll (página e área de conteúdo da app). */
async function horizontalOverflow(page: Page) {
  return page.evaluate(() => {
    const out: string[] = [];
    const doc = document.scrollingElement!;
    if (doc.scrollWidth > window.innerWidth + 1) out.push(`página: ${doc.scrollWidth}px > ${window.innerWidth}px`);
    for (const el of document.querySelectorAll<HTMLElement>("[data-slot=sidebar-inset] *")) {
      const s = getComputedStyle(el);
      if (!/(auto|scroll)/.test(s.overflowX) || el.clientWidth === 0) continue;
      // zonas com scroll horizontal próprio e explícito (tabelas, overflow-x-*) são permitidas; o resto não pode transbordar
      const explicit = "[data-slot=table-container], [data-scroll-x], [class*='overflow-x-auto'], [class*='overflow-x-scroll']";
      if (el.matches(explicit)) continue;
      if (el.scrollWidth > el.clientWidth + 1) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].slice(0, 4).join(".")}: ${el.scrollWidth}px > ${el.clientWidth}px`);
    }
    return out;
  });
}

for (const vp of VIEWPORTS) {
  test.describe(vp.name, () => {
    test.use({ viewport: vp.viewport, isMobile: vp.isMobile, hasTouch: vp.hasTouch });
    for (const role of ["owner", "clientA"] as const) {
      as(role)(`${role} · ${vp.name}: rotas principais sem scroll horizontal e menu recolhido`, async ({ page, errors }) => {
        test.setTimeout(180_000);
        const bad: string[] = [];
        for (const r of MAIN_ROUTES) {
          await page.goto(`/c/${WS_A}${r.path}`);
          await settle(page);
          await expect(page.getByRole("heading", { level: 1 }).first(), r.name).toBeVisible();
          await expectNoCrash(page);
          for (const o of await horizontalOverflow(page)) bad.push(`[${r.name}] ${o}`);
          expect(errors, r.name).toEqual([]);
        }
        expect(bad, bad.join("\n")).toEqual([]);

        await page.goto(`/c/${WS_A}/guioes`);
        await settle(page);
        const trigger = page.locator('[data-sidebar="trigger"]');
        if (vp.viewport.width < 768) {
          // telemóvel: sem menu fixo; o botão abre uma folha com o menu e Escape fecha-a
          await expect(page.locator('[data-slot="sidebar-container"]')).toHaveCount(0);
          await expect(page.locator('[data-mobile="true"]')).toHaveCount(0);
          await trigger.click();
          const sheet = page.locator('[data-mobile="true"]');
          await expect(sheet.getByRole("link", { name: "Revisão" })).toBeVisible();
          await page.keyboard.press("Escape");
          await expect(sheet).toHaveCount(0);
          // e um link da folha navega e fecha a folha (a página nova não fica tapada nem inerte)
          await trigger.click();
          await sheet.getByRole("link", { name: "Tarefas" }).click();
          await expect(page).toHaveURL(new RegExp(`/c/${WS_A}/tarefas$`));
          await expect(sheet).toHaveCount(0);
          await expect(page.getByRole("heading", { level: 1, name: "Tarefas" })).toBeVisible();
        } else {
          // iPad: menu fixo que recolhe para ícones pelo botão e volta a abrir
          const side = page.locator('[data-slot="sidebar"][data-state]').first();
          const was = await side.getAttribute("data-state");
          await trigger.click();
          await expect(side).toHaveAttribute("data-state", was === "expanded" ? "collapsed" : "expanded");
          for (const o of await horizontalOverflow(page)) bad.push(`[menu ${was === "expanded" ? "recolhido" : "aberto"}] ${o}`);
          await trigger.click();
          await expect(side).toHaveAttribute("data-state", was!);
          expect(bad, bad.join("\n")).toEqual([]);
        }
        expect(errors).toEqual([]);
      });
    }
  });
}
