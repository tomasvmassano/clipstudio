import { WS_A } from "./env";
import { as, expect } from "./helpers";

// CAP-05, BIZ-07 (W1-16): "Ver como" pessoa ou papel, só leitura.
as("clientA")("ver como o papel leitor: vê guiões, não edita nem gere permissões", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/permissoes`);
  await page.getByRole("button", { name: "Ver como" }).click();
  await page.getByLabel("Ver como quem").selectOption("r:viewer");
  await page.getByRole("button", { name: "Ver", exact: true }).click();
  await expect(page.getByText(/Pré-visualização como/)).toBeVisible();
  const caps = page.getByRole("list", { name: "Capacidades simuladas" });
  await expect(caps.locator('[data-cap="scripts.read"]')).toContainText("✓");
  await expect(caps.locator('[data-cap="scripts.edit"]')).toContainText("✗");
  await expect(caps.locator('[data-cap="permissions.manage"]')).toContainText("✗");
  const menu = page.getByRole("list", { name: "Menu visto" });
  await expect(menu.getByText("Guiões", { exact: true })).toBeVisible();
  await expect(menu.getByText("Permissões", { exact: true })).toHaveCount(0);
  expect(errors).toEqual([]);
});
