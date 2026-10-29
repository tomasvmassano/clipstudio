import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, users } from "./env";
import { as, expect } from "./helpers";

// VAR-02, EDL-01 (W5-02): catálogo de estilos versionado e preset de edição do cliente.
as("clientA")("ponto de partida do numeiro: preset por defeito e S13 ativo", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/edicao`);
  await expect(page.getByRole("heading", { name: "Estilos de edição" })).toBeVisible();
  const preset = page.getByRole("list", { name: "Saídas do preset" });
  await expect(preset).toContainText("Masters (um por hook");
  await expect(preset).toContainText("Estilo S13 · Faixa de estatuto");
  await expect(page.locator('[data-style="S13"]')).toContainText("Ativo");
  await expect(page.locator('[data-style="S01"]')).toContainText("Rascunho");
  expect(errors).toEqual([]);
});

as("staff")("criar um estilo, ver o erro do retângulo seguro, ativar e pô-lo no preset", async ({ page, errors }) => {
  const key = `E${Date.now() % 1_000_000}`;
  await page.goto(`/c/${WS_A}/edicao`);
  await page.getByLabel("Chave do estilo novo").fill(key);
  await page.getByRole("button", { name: "Estilo novo" }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: `${key} · ${key}` })).toBeVisible();
  const json = sheet.getByLabel(/Layout \(JSON/);
  const spec = (titleX: number) => JSON.stringify({ canvas: { w: 1080, h: 1920 }, layers: [
    { kind: "video", box: [0, 0, 1080, 1920] }, { kind: "title", color: "#FFD400", box: [titleX, 300, 800, 200], max_words: 6 }] });
  await json.fill(spec(10));
  await expect(sheet.getByText(/o texto tem de ficar no retângulo seguro/)).toBeVisible();
  await expect(sheet.getByRole("button", { name: "Gravar versão nova" })).toBeDisabled();
  await json.fill(spec(100));
  await sheet.getByLabel("Nome").fill("Teste E2E");
  await sheet.getByRole("button", { name: "Gravar versão nova" }).click();
  await expect(sheet.getByText("Gravado como versão nova.")).toBeVisible();
  await expect(sheet.getByText(/^versão 2/)).toBeVisible();
  await sheet.getByRole("button", { name: "Ativar" }).click();
  await expect(sheet.getByText("Estilo ativo.")).toBeVisible();
  await sheet.getByRole("button", { name: "Fechar", exact: true }).first().click();

  await page.getByRole("button", { name: "Mudar o preset" }).click();
  await page.getByLabel(`Estilo ${key} · Teste E2E`).check();
  await page.getByRole("button", { name: "Gravar preset" }).click();
  const preset = page.getByRole("list", { name: "Saídas do preset" });
  await expect(preset).toContainText(`Estilo ${key} · Teste E2E (v2)`);
  // repor o preset sem o estilo de teste (o preset tem no máximo 12 saídas)
  await page.getByRole("button", { name: "Mudar o preset" }).click();
  await page.getByLabel(`Estilo ${key} · Teste E2E`).uncheck();
  await page.getByRole("button", { name: "Gravar preset" }).click();
  await expect(preset).not.toContainText(key);
  expect(errors).toEqual([]);
});

test("o cliente B não lê nem muda os estilos do numeiro (403)", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const read = await fetch(`${API_URL}/rest/v1/rpc/edit_catalog`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect(read.status).toBe(403);
  const write = await fetch(`${API_URL}/rest/v1/rpc/edit_preset_save`, {
    method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_outputs: [{ kind: "master" }], p_expected: 1 }),
  });
  expect(write.status).toBe(403);
  const direct = await fetch(`${API_URL}/rest/v1/edit_style_versions?select=key&limit=1`, { headers: h });
  expect([401, 403]).toContain(direct.status);
});
