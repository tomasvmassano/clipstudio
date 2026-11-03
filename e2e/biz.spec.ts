import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, sidebar } from "./helpers";

// BIZ-01 a BIZ-06 (W6): vista de negócio da agência, dois níveis de acesso, contratos, câmbio e custos.
// A flag biz.view está por defeito "só o dono"; o teste do staff liga-a para a equipa da agência e repõe no fim.

async function tokenFor(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const month = () => new Date().toISOString().slice(0, 8) + "01";

as("owner")("dono: regista câmbio e contrato e vê o cliente com receita na vista", async ({ page, errors }) => {
  await page.goto("/negocio/contratos");
  await expect(page.getByRole("heading", { name: "Contratos e custos" })).toBeVisible();
  await page.getByLabel("AED por 1 EUR").fill("4,05");
  await page.getByRole("button", { name: "Gravar taxa" }).click();
  await expect(page.getByText("Taxa gravada.")).toBeVisible();
  await expect(page.getByText(/1 EUR = 4,05 AED/).first()).toBeVisible();

  const card = page.locator(`[data-contract="${WS_B}"]`);
  await card.getByRole("button", { name: /Registar contrato|Mudar/ }).click();
  const form = card.getByRole("form", { name: /Contrato de/ });
  await form.getByLabel("Valor").fill("2000");
  await form.getByLabel("Moeda").selectOption("AED");
  await form.getByLabel("Vídeos por mês").fill("12");
  await form.getByRole("button", { name: "Gravar versão nova" }).click();
  await expect(card.getByText("Contrato gravado como versão nova.")).toBeVisible();
  await expect(card).toContainText("12 vídeos/mês");

  await page.goto("/negocio");
  await expect(page.getByRole("heading", { name: "Vista de negócio" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Precisa da tua atenção" })).toBeVisible();
  await expect(page.getByRole("columnheader", { name: "MRR" })).toBeVisible();
  const row = page.locator(`[data-client="${WS_B}"]`);
  await expect(row).toBeVisible();
  await expect(row).not.toContainText("sem contrato");
  await expect(page.locator(`[data-client="${WS_A}"]`)).toBeVisible();
  await page.getByRole("radio", { name: "AED" }).or(page.getByRole("button", { name: "AED" })).first().click();
  await expect(row).toContainText("AED");
  await expect(sidebar(page).getByRole("link", { name: "Negócio" })).toBeVisible();
  expect(errors).toEqual([]);
});

as("owner")("dono: acrescentar e anular um custo do mês (fica no histórico)", async ({ page, errors }) => {
  const label = `E2E custo ${Date.now() % 1_000_000}`;
  await page.goto("/negocio/contratos");
  const form = page.getByRole("form", { name: "Acrescentar custo" });
  await form.getByLabel("Descrição").fill(label);
  await form.getByLabel("Cliente").selectOption(WS_A);
  await form.getByLabel("Valor").fill("10");
  await form.getByRole("button", { name: "Acrescentar custo" }).click();
  await expect(page.getByText("Custo acrescentado.")).toBeVisible();
  const row = page.locator("tr", { hasText: label });
  await row.getByRole("button", { name: "Anular" }).click();
  await row.getByLabel("Motivo para anular").fill("teste E2E");
  await row.getByRole("button", { name: "Anular" }).click();
  await expect(row).toContainText("anulado: teste E2E");
  expect(errors).toEqual([]);
});

as("staff")("staff: em teste só para o dono; ligada para a agência vê só o numeiro e nada financeiro", async ({ page, errors }) => {
  await page.goto("/negocio");
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  await expect(sidebar(page).getByRole("link", { name: "Negócio" })).toHaveCount(0);
  sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'biz.view', id, null, 'agency' from organizations where slug = 'clipstudio'
       on conflict (key, organization_id, coalesce(workspace_id, '')) do update set stage = 'agency'`);
  try {
    await page.goto("/negocio");
    await expect(page.getByRole("heading", { name: "Vista de negócio" })).toBeVisible();
    await expect(page.locator(`[data-client="${WS_A}"]`)).toBeVisible();
    await expect(page.locator(`[data-client="${WS_B}"]`)).toHaveCount(0);
    await expect(page.getByRole("columnheader", { name: "MRR" })).toHaveCount(0);
    await expect(page.getByRole("columnheader", { name: "Margem de entrega" })).toHaveCount(0);
    await expect(page.locator('[data-kpi^="fin."]')).toHaveCount(0);
    await expect(page.getByText("Cliente B (E2E)")).toHaveCount(0);
    await expect(sidebar(page).getByRole("link", { name: "Contratos e custos" })).toHaveCount(0);
    await page.goto("/negocio/contratos");
    await expect(page.getByText("Contratos, câmbio e custos são só para o dono da agência.")).toBeVisible();
    expect(errors).toEqual([]);
  } finally {
    sql(`delete from feature_flags where key = 'biz.view' and workspace_id is null`);
  }
});

as("clientA")("equipa do cliente não vê a vista de negócio", async ({ page }) => {
  await page.goto("/negocio");
  await expect(page.getByText("A vista de negócio é da equipa da agência. Não tens acesso a ela.")).toBeVisible();
});

test("API: cliente e staff sem finanças recebem 403; tabelas fechadas", async () => {
  const hb = await tokenFor(users.clientB);
  const ov = await fetch(`${API_URL}/rest/v1/rpc/biz_overview`, { method: "POST", headers: hb, body: JSON.stringify({ p_month: month(), p_currency: "EUR" }) });
  expect(ov.status).toBe(403);
  const hist = await fetch(`${API_URL}/rest/v1/rpc/biz_contract_history`, { method: "POST", headers: hb, body: JSON.stringify({ p_ws: WS_A }) });
  expect(hist.status).toBe(403);
  const direct = await fetch(`${API_URL}/rest/v1/client_contracts?select=id&limit=1`, { headers: hb });
  expect([401, 403, 404]).toContain(direct.status);

  const hs = await tokenFor(users.staff);
  for (const [fn, body] of [
    ["biz_contracts", {}],
    ["biz_costs", { p_month: month() }],
    ["biz_contract_save", { p_ws: WS_A, p_fields: { amount: 1 }, p_expected: 0 }],
    ["biz_fx_save", { p_rate: 4, p_as_of: month(), p_source: null }],
  ] as const) {
    const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: hs, body: JSON.stringify(body) });
    expect(r.status, fn).toBe(403);
  }
});
