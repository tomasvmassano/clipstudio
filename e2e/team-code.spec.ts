import { test } from "@playwright/test";
import { TEAM_CODE, WS_A } from "./env";
import { expect, NO_ACCESS } from "./helpers";

// Acesso de transição por código de equipa (até à remoção, TEAM-01): entra só no seu cliente.
test("código de equipa entra no seu cliente e não abre outros", async ({ page }) => {
  await page.goto(`/c/${WS_A}/guioes`);
  await page.waitForURL(/\/login/);
  await page.goto(`/?k=${TEAM_CODE}`);
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
  expect(page.url()).not.toContain("k=");
  await expect(page.getByRole("heading", { name: "Início" })).toBeVisible();
  await page.goto("/c/e2e-b");
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
});
