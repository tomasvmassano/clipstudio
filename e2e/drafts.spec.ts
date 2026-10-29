import { WS_A, sql } from "./env";
import { as, expect } from "./helpers";

// FR-17-13 (W2-09): o que não chegou ao servidor fica no dispositivo e recupera-se depois de recarregar.
const GID = "numeiro-2026-10-28-22";

as("clientA")("sem rede, a edição fica no dispositivo e recupera-se depois", async ({ page, context }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));
  const text = `Frase escrita sem rede ${Date.now()}`;
  await page.goto(`/c/${WS_A}/guioes`);
  const card = page.locator(`[data-guiao="${GID}"]`);
  await card.getByRole("button", { name: "Editar" }).click();
  await context.setOffline(true);
  await card.getByLabel("Corpo").fill(`Corpo de teste do guião 22.\n${text}`);
  await expect(card.getByText("Não ficou guardado.")).toBeVisible({ timeout: 15_000 });
  await context.setOffline(false);
  await page.reload();
  await expect(card.getByRole("button", { name: "alterações por guardar neste dispositivo" })).toBeVisible();
  await card.getByRole("button", { name: "alterações por guardar neste dispositivo" }).click();
  await card.getByRole("button", { name: "Recuperar" }).click();
  await expect(card.getByLabel("Corpo")).toHaveValue(new RegExp(text));
  await expect(card.getByText(/^Guardado às/)).toBeVisible({ timeout: 15_000 });
  expect(sql(`select corpo from guioes where id = '${GID}'`).join("\n")).toContain(text);
  await card.getByRole("button", { name: "Concluir" }).click();
  await expect(card.getByRole("button", { name: "alterações por guardar neste dispositivo" })).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});
