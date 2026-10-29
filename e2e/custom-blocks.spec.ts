import { WS_A, sql } from "./env";
import { as, expect } from "./helpers";

// FR-03-02 (W2-08): blocos personalizados no corpo ("## Nome") aparecem no guião e no teleprompter, e saltam-se por bloco.
const GID = "numeiro-2026-10-28-21";

as("clientA")("marcas ## no corpo viram blocos com nome no guião e no teleprompter", async ({ page, errors }) => {
  sql(`update guioes set corpo = E'Abertura.\\n## Prova social\\nTexto da prova.\\n## Pergunta à câmara\\nE tu?' where id = '${GID}'`);
  await page.goto(`/c/${WS_A}/guioes`);
  const card = page.locator(`[data-guiao="${GID}"]`);
  await card.getByRole("button", { name: "Ver tudo" }).click();
  await expect(card.getByText("Prova social", { exact: true })).toBeVisible();
  await expect(card.getByText("## Prova social")).toHaveCount(0);

  await page.goto(`/c/${WS_A}/teleprompter`);
  const item = page.locator(`[data-item="${GID}"]`);
  await item.locator("button[aria-expanded]").click();
  const chip = item.getByRole("button", { name: "Pergunta à câmara" });
  await expect(item.getByRole("button", { name: "Prova social" })).toBeVisible();
  await expect(chip).toHaveAttribute("aria-pressed", "true");
  await chip.click();
  await expect(chip).toHaveAttribute("aria-pressed", "false");
  expect(sql(`select skipped_blocks from recording_session_items i join recording_sessions s on s.id = i.session_id
              where i.content_id = '${GID}' order by s.opened_at desc limit 1`)[0]).toContain("x_pergunta_a_camara");
  await chip.click();
  await expect(chip).toHaveAttribute("aria-pressed", "true");
  await item.getByRole("button", { name: "Ler" }).click();
  await expect(page.locator('section[data-block="x_prova_social"]')).toContainText("Texto da prova.");
  await expect(page.locator('section[data-block="x_pergunta_a_camara"]')).toContainText("Pergunta à câmara");
  expect(errors).toEqual([]);
});
