import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect } from "./helpers";

// FR-02-03 e FR-03-01 (W2-07): campanha, responsável, plataformas e etiquetas no guião; fila do teleprompter filtrável.
const GID = "numeiro-2026-10-28-20";

as("clientA")("pôr o guião numa campanha nova com responsável e filtrar a fila do teleprompter", async ({ page, errors }) => {
  const name = `E2E campanha ${Date.now() % 1_000_000}`;
  await page.goto(`/c/${WS_A}/guioes`);
  const card = page.locator(`[data-guiao="${GID}"]`);
  await card.getByRole("button", { name: "Detalhes" }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: "Detalhes do guião 20" })).toBeVisible();
  await sheet.getByLabel("Nova").fill(name);
  await sheet.getByRole("button", { name: "Criar" }).click();
  await expect(sheet.getByLabel("Campanha ou série")).toHaveValue(/[0-9a-f-]{36}/);
  const [me] = sql(`select id from auth.users where email = '${users.clientA}'`);   // o nome mostrado pode vir do perfil
  await sheet.getByLabel("Responsável").selectOption(me);
  await sheet.getByLabel("TikTok").check();
  await sheet.getByLabel(/Etiquetas/).fill("E2E, teste, e2e");
  await sheet.getByRole("button", { name: "Guardar" }).click();
  await expect(sheet.getByText("Guardado.")).toBeVisible();
  await sheet.getByRole("button", { name: "Fechar", exact: true }).first().click();
  await expect(card.locator('[data-meta="project"]')).toHaveText(`Campanha: ${name}`);
  await expect(card.locator('[data-meta="owner"]')).toBeVisible();
  await expect(card.getByText("#e2e")).toBeVisible();
  await expect(card.getByText("#teste")).toBeVisible();

  await page.goto(`/c/${WS_A}/teleprompter`);
  await page.getByLabel("Campanha").selectOption({ label: `Campanha · ${name}` });
  await expect(page.getByText(/^1 de \d+ guiões$/)).toBeVisible();
  await expect(page.locator(`[data-item="${GID}"]`)).toBeVisible();
  await page.getByLabel("Responsável").selectOption("me");
  await expect(page.locator(`[data-item="${GID}"]`)).toBeVisible();
  await page.getByLabel("Campanha").selectOption("");
  await page.getByLabel("Responsável").selectOption("none");
  await expect(page.locator(`[data-item="${GID}"]`)).toHaveCount(0);
  await page.getByRole("button", { name: "Limpar filtros" }).click();
  await expect(page.locator(`[data-item="${GID}"]`)).toBeVisible();
  expect(errors).toEqual([]);
});

test("o cliente B não vê campanhas nem mexe nos guiões do numeiro (403)", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const list = await fetch(`${API_URL}/rest/v1/rpc/projects_list`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect(list.status).toBe(403);
  const meta = await fetch(`${API_URL}/rest/v1/rpc/content_meta_set`, { method: "POST", headers: h, body: JSON.stringify({ p_id: GID, p_patch: { tags: ["x"] } }) });
  expect(meta.status).toBe(403);
  const owners = await fetch(`${API_URL}/rest/v1/rpc/content_owners`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect(owners.status).toBe(403);
  const direct = await fetch(`${API_URL}/rest/v1/projects?select=id&limit=1`, { headers: h });
  expect([401, 403]).toContain(direct.status);
});
