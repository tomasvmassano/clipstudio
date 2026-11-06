import { WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";
import type { Page } from "@playwright/test";

// GAZE-01/02 (PRD §46.1): a coluna segue a distância à câmara; linha de foco configurável; modo frase com 2 a 4 palavras
// por linha. Preferências guardadas na conta para este dispositivo (FR-03-05).

const colWidth = (page: Page) => page.locator("[data-gaze-column]").evaluate((n) => n.getBoundingClientRect().width);

async function openSettings(page: Page) {
  await page.mouse.move(400, 400);
  await page.getByRole("button", { name: "Definições", exact: true }).click();
  return page.getByRole("dialog", { name: "Definições do teleprompter" });
}

as("clientA")("coluna pela distância, linha de foco e modo frase, guardados por dispositivo", async ({ page, errors }) => {
  sql(`delete from teleprompter_prefs where user_id = (select id from auth.users where email = '${users.clientA}')`);
  await page.goto(`/c/${WS_A}/teleprompter`);
  await page.getByRole("button", { name: /^Começar no guião|^Retomar no guião/ }).first().click();
  await expect(page.locator("[data-gaze-column]")).toBeVisible();
  // sem tamanho do ecrã: coluna antiga e pedido para o indicar
  await expect(page.getByText("indica o tamanho do ecrã nas Definições")).toBeVisible();

  let dlg = await openSettings(page);
  await dlg.getByLabel("Tamanho do ecrã em polegadas").fill("13");
  await dlg.getByLabel("Distância à câmara em metros").fill("1");
  await expect(dlg.locator("[data-gaze-target]")).toContainText("coluna de 10,5 cm a 1 m");
  await dlg.getByRole("button", { name: "Fechar" }).click();

  await expect(page.locator("[data-gaze-angle]")).toContainText("±3,0° a 1 m");
  const w1 = await colWidth(page);
  const expected1 = await page.evaluate(() => {
    const pxPerCm = Math.hypot(screen.width, screen.height) / (13 * 2.54);
    return 2 * 100 * Math.tan((3 * Math.PI) / 180) * pxPerCm;
  });
  expect(Math.abs(w1 - expected1)).toBeLessThan(2);

  dlg = await openSettings(page);
  await dlg.getByLabel("Distância à câmara em metros").fill("1,5");
  await expect(dlg.locator("[data-gaze-target]")).toContainText("coluna de 15,7 cm a 1,5 m");
  await dlg.getByRole("button", { name: "Fechar" }).click();
  await expect.poll(() => colWidth(page)).toBeGreaterThan(w1 * 1.45);
  expect(await colWidth(page)).toBeLessThan(w1 * 1.55);

  // coluna desligada a 1 m: volta à largura antiga (até 1100 px) e o ângulo passa o teto, com aviso
  dlg = await openSettings(page);
  await dlg.getByLabel("Distância à câmara em metros").fill("1");
  await dlg.getByRole("switch", { name: "Coluna pela distância" }).click();
  await dlg.getByRole("button", { name: "Fechar" }).click();
  await expect(page.locator("[data-gaze-angle]")).toContainText("acima de ±4,5°");
  dlg = await openSettings(page);
  await dlg.getByRole("switch", { name: "Coluna pela distância" }).click();
  await dlg.getByLabel("Distância à câmara em metros").fill("1,5");
  // linha de foco a 30%
  await dlg.getByLabel("Altura da linha de foco").fill("30");
  await dlg.getByRole("button", { name: "Fechar" }).click();
  const focus = await page.locator("[data-focus-line]").evaluate((n) => (n as HTMLElement).style.top);
  expect(focus).toBe("30%");

  // modo frase: 2 a 4 palavras por linha (1 só quando o parágrafo inteiro é uma palavra), blocos mantidos
  const blocksBefore = await page.locator("[data-gaze-column] section[data-block]").count();
  await page.mouse.move(400, 400);
  await page.getByRole("button", { name: "Modo frase" }).click();
  await expect(page.locator("[data-gaze-column]")).toHaveAttribute("data-phrase-mode", "on");
  expect(await page.locator("[data-gaze-column] section[data-block]").count()).toBe(blocksBefore);
  const paras = await page.locator("[data-gaze-column] section[data-block] > div:has([data-phrase-line])").evaluateAll((divs) =>
    divs.map((d) => Array.from(d.querySelectorAll("[data-phrase-line]")).map((l) => (l.textContent ?? "").split(/\s+/).filter((t) => /[\p{L}\p{N}]/u.test(t)).length)));
  expect(paras.length).toBeGreaterThan(0);
  for (const lines of paras) {
    for (const n of lines) expect(n).toBeLessThanOrEqual(4);
    if (lines.length > 1) for (const n of lines) expect(n).toBeGreaterThanOrEqual(2);
  }
  expect(paras.flat().filter((n) => n >= 2).length).toBeGreaterThan(3);

  // ficou na conta, para este dispositivo
  await expect.poll(() => sql(`select prefs->>'distance_m' || '|' || (prefs->>'screen_in') || '|' || (prefs->>'focus_pct') || '|' || (prefs->>'phrase_mode') from teleprompter_prefs p join auth.users u on u.id = p.user_id where u.email = '${users.clientA}'`)[0])
    .toBe("1.50|13.0|30|true");
  await page.reload();
  await page.getByRole("button", { name: /^Começar no guião|^Retomar no guião/ }).first().click();
  await expect(page.locator("[data-gaze-column]")).toHaveAttribute("data-phrase-mode", "on");
  await expect(page.locator("[data-gaze-angle]")).toContainText("a 1,5 m");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
  sql(`delete from teleprompter_prefs where user_id = (select id from auth.users where email = '${users.clientA}')`);
});
